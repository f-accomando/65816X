// c816_core.v - top of the c816 core, a cycle-accurate 65C816 (docs/design/cpu-core.md).
// One CPU cycle is two FPGA clocks: phase 0 drives addr and one rd or wr pulse, phase 1 waits
// for din. The core captures din at the clock that ends phase 1 (cyc_end).
// Latches: IR (9 bits, bit 8 = pseudo-opcode), AL, AH, BA, DL, DH, OF (direct page or stack
// offset). Execute happens at commit.
// Interrupts: nmi is taken on its rising edge, irq while it is 1 and P.I = 0. Both are sampled
// at the end of an instruction; the next opcode fetch then loads a pseudo-opcode ($101 NMI,
// $102 IRQ) and does not move the program counter. WDM runs the extensions only with ext_en = 1.
module c816_core (
  input clk,
  input rst,
  input halt,
  input bus_wait,
  input ext_en,
  input nmi,
  input irq,
  input [7:0] din,
  output [23:0] addr,
  output rd,
  output wr,
  output [7:0] wdata,
  output vda,
  output vpa,
  output sync,
  output cyc_end,
  output dbg_illegal,
  output [15:0] dbg_pc,
  output [15:0] dbg_a,
  output [15:0] dbg_x,
  output [15:0] dbg_y
);
  reg [8:0] ir;
  reg [7:0] al, ah, ba, dl, dh, of;

  // ---- decode ----
  wire [5:0] seq;
  wire [4:0] op;
  wire [3:0] ea;
  wire [2:0] w;
  wire [3:0] src;
  wire [3:0] dst;
  wire [3:0] arg;
  wire imp;
  wire [5:0] seq_wdmx;
  c816_decode u_dec (
    .ir(ir), .seq(seq), .op(op), .ea(ea), .w(w), .src(src), .dst(dst), .arg(arg),
    .imp(imp), .seq_wdmx(seq_wdmx)
  );
  wire [5:0] seq_eff = ((ir == 9'h042) && ext_en) ? seq_wdmx : seq;

  // ---- cycle descriptor ----
  wire [3:0] t;
  wire [2:0] bus;
  wire [4:0] asel;
  wire [2:0] cap;
  wire pcinc;
  wire [1:0] sop;
  wire [3:0] wsel;
  wire [2:0] last;
  wire [2:0] skip;
  wire [3:0] pcop;
  wire [1:0] hold;
  c816_ucode u_uc (
    .seq(seq_eff), .t(t), .bus(bus), .asel(asel), .cap(cap), .pcinc(pcinc), .sop(sop),
    .wsel(wsel), .last(last), .skip(skip), .pcop(pcop), .hold(hold)
  );

  // ---- registers ----
  wire [15:0] r_a, r_x, r_y, r_s, r_d, r_pc;
  wire [7:0] r_pbr, r_dbr, r_p;
  wire r_e;
  wire ph;
  wire illegal;
  wire commit;
  wire skip1;

  // ---- interrupts ----
  reg nmi_q, nmi_pend, take_nmi, take_irq;
  wire fetch_int = (t == 4'd0) && (take_nmi || take_irq);
  wire hw_int = ir[8];                 // pseudo-opcodes: reset, NMI, IRQ
  wire wake = nmi_pend || irq;         // WAI ends also with IRQ masked
  wire [7:0] vec_e = (ir == 9'h101) ? 8'hFA : (ir == 9'h002) ? 8'hF4 : (ir == 9'h100) ? 8'hFC : 8'hFE;
  wire [7:0] vec_n = (ir == 9'h101) ? 8'hEA : (ir == 9'h102) ? 8'hEE : (ir == 9'h002) ? 8'hE4 : 8'hE6;
  wire [7:0] vec = (r_e || (ir == 9'h100)) ? vec_e : vec_n;

  // ---- width, condition, bus kind ----
  // w codes: 0 M, 1 X, 2 B8, 3 W16
  wire w8 = (w == 3'd0) ? r_p[5] : (w == 3'd1) ? r_p[4] : (w != 3'd3);
  wire taken = (op == 5'd17) || (r_p[arg[2:0]] == arg[3]);
  wire is_store = (op == 5'd2);
  // bus codes: 0 IO, 1 OPF, 2 PRG, 3 DAT, 4 DRD, 5 DWR, 6 MOD (a write only in emulation mode)
  wire reads = (bus == 3'd1) || (bus == 3'd2) || (bus == 3'd4) || ((bus == 3'd3) && !is_store);
  assign vda = (bus == 3'd1) || (bus == 3'd3) || (bus == 3'd4) || (bus == 3'd5);
  assign vpa = (bus == 3'd1) || (bus == 3'd2);

  // ---- bytes that the current cycle captures (the execute logic sees them at once) ----
  wire [7:0] al_by = (reads && (cap == 3'd1)) ? din : al;
  wire [7:0] ah_by = (reads && (cap == 3'd2)) ? din : ah;
  wire [7:0] ba_by = (reads && (cap == 3'd3)) ? din : ba;
  wire [7:0] dl_by = (reads && (cap == 3'd4)) ? din : dl;
  wire [7:0] dh_by = (reads && (cap == 3'd5)) ? din : dh;

  // ---- program counter ----
  // pcop: 1 ABS, 2 LONG (also PBR), 3 BRL (branch target if this step is the last), 4 BR,
  // 5 RTS ({AH, AL} + 1), 6 REL16 (PC + {AH, AL}), 7 RTL ({AH, AL} + 1, PBR = BA),
  // 8 DPTR ({DH, DL}), 9 DPTRL ({DH, DL}, PBR = BA), 10 REWIND (block move: PC - 3 while A != 0)
  wire xcarry;
  wire br_cross;
  wire [15:0] br_target;
  wire [15:0] rel16;
  wire [15:0] pc_m1;
  wire load_abs = (pcop == 4'd1) || (pcop == 4'd2) || (pcop == 4'd11);
  wire load_br = (pcop == 4'd4) || ((pcop == 4'd3) && commit);
  wire load_ret = (pcop == 4'd5) || (pcop == 4'd7);
  wire load_rel = (pcop == 4'd6);
  wire load_ptr = (pcop == 4'd8) || (pcop == 4'd9);
  wire load_back = (pcop == 4'd10) && (r_a != 16'd0);
  wire pc_load = load_abs || load_br || load_ret || load_rel || load_ptr || load_back;
  wire pc_we = cyc_end && ((pcinc && !fetch_int) || pc_load);
  wire [15:0] pc_next = load_abs ? {ah_by, al_by} :
                        load_br ? br_target :
                        load_ret ? ({ah, al} + 16'd1) :
                        load_rel ? rel16 :
                        load_ptr ? {dh_by, dl_by} :
                        load_back ? (r_pc - 16'd3) : r_pc + 16'd1;
  wire pbr_we = cyc_end && ((pcop == 4'd2) || (pcop == 4'd7) || (pcop == 4'd9) || (pcop == 4'd11));
  wire [7:0] pbr_next = (pcop == 4'd11) ? 8'h00 : ba_by;     // vectors are in bank 0

  // ---- extensions ----
  wire is_wdm = (op == 5'd18);
  wire ext_we_a, ext_we_y, ext_f_we, ext_f_n, ext_f_z, ext_fv_we, ext_f_v, ext_busy;
  wire [15:0] ext_a, ext_y;
  wire ext_go = commit && ext_en && is_wdm;
  c816_ext u_ext (
    .clk(clk), .rst(rst), .go(ext_go), .sub(dl_by), .a(r_a), .x(r_x),
    .we_a(ext_we_a), .we_y(ext_we_y), .a_out(ext_a), .y_out(ext_y),
    .f_we(ext_f_we), .f_n(ext_f_n), .f_z(ext_f_z), .fv_we(ext_fv_we), .f_v(ext_f_v),
    .busy(ext_busy)
  );

  // ---- operands ----
  // src codes: 0 none, 1 A, 2 X, 3 Y, 4 S, 5 D, 6 P, 7 DBR, 8 PBR
  reg [15:0] src_v;
  always @* begin
    case (src)
      4'd1: src_v = r_a;
      4'd2: src_v = r_x;
      4'd3: src_v = r_y;
      4'd4: src_v = r_s;
      4'd5: src_v = r_d;
      4'd6: src_v = {8'h00, r_p};
      4'd7: src_v = {8'h00, r_dbr};
      4'd8: src_v = {8'h00, r_pbr};
      default: src_v = 16'd0;
    endcase
  end

  wire [15:0] mem_v = {dh_by, dl_by};
  // a memory operand takes the place of the source register in a read-modify-write instruction
  wire [15:0] alu_a = (src == 4'd0) ? mem_v : src_v;
  reg [3:0] alu_op;
  wire [15:0] alu_r;
  wire alu_n, alu_v, alu_z, alu_c;
  c816_alu u_alu (
    .op(alu_op), .a(alu_a), .b(mem_v), .ci(r_p[0]), .w16(!w8), .dec(r_p[3]),
    .r(alu_r), .n(alu_n), .v(alu_v), .z(alu_z), .c(alu_c)
  );

  // ---- execute (at commit) ----
  // op codes: 1 LD, 2 ST, 3 TR, 4 ADC, 5 SBC, 6 CMP, 7 AND, 8 ORA, 9 EOR, 10 INC, 11 DEC,
  // 12 FLG, 13 REP, 14 SEP, 15 XCE, 16 BR, 17 BRA, 18 WDM, 19 ASL, 20 LSR, 21 ROL, 22 ROR,
  // 23 TSB, 24 TRB, 25 BIT, 26 BITI, 27 XBA, 28 PLP (also RTI), 29 MVN, 30 MVP, 31 BRK
  wire [7:0] bitm = 8'd1 << arg[2:0];
  wire is_xce = (op == 5'd15);
  wire is_xba = (op == 5'd27);
  wire is_bit = (op == 5'd25);
  wire has_dst = (dst != 4'd0);
  reg wr_en;
  reg [3:0] f_we;
  reg p_we;
  reg [7:0] p_val;
  reg e_we;
  always @* begin
    alu_op = 4'd0;
    wr_en = 1'b0;
    f_we = 4'b0000;
    p_we = 1'b0;
    p_val = r_p;
    e_we = 1'b0;
    case (op)
      5'd1: begin alu_op = 4'd0; wr_en = has_dst; f_we = 4'b1010; end
      // a transfer to S changes no flag
      5'd3: begin alu_op = 4'd1; wr_en = has_dst; f_we = (dst == 4'd4) ? 4'b0000 : 4'b1010; end
      5'd4: begin alu_op = 4'd2; wr_en = 1'b1; f_we = 4'b1111; end
      5'd5: begin alu_op = 4'd3; wr_en = 1'b1; f_we = 4'b1111; end
      5'd6: begin alu_op = 4'd4; f_we = 4'b1011; end
      5'd7: begin alu_op = 4'd5; wr_en = 1'b1; f_we = 4'b1010; end
      5'd8: begin alu_op = 4'd6; wr_en = 1'b1; f_we = 4'b1010; end
      5'd9: begin alu_op = 4'd7; wr_en = 1'b1; f_we = 4'b1010; end
      5'd10: begin alu_op = 4'd8; wr_en = has_dst; f_we = 4'b1010; end
      5'd11: begin alu_op = 4'd9; wr_en = has_dst; f_we = 4'b1010; end
      5'd12: begin p_we = 1'b1; p_val = arg[3] ? (r_p | bitm) : (r_p & ~bitm); end
      5'd13: begin p_we = 1'b1; p_val = r_p & ~dl_by; end
      5'd14: begin p_we = 1'b1; p_val = r_p | dl_by; end
      5'd15: begin f_we = 4'b0001; e_we = 1'b1; end
      5'd19: begin alu_op = 4'd10; wr_en = has_dst; f_we = 4'b1011; end
      5'd20: begin alu_op = 4'd11; wr_en = has_dst; f_we = 4'b1011; end
      5'd21: begin alu_op = 4'd12; wr_en = has_dst; f_we = 4'b1011; end
      5'd22: begin alu_op = 4'd13; wr_en = has_dst; f_we = 4'b1011; end
      5'd23: begin alu_op = 4'd14; f_we = 4'b0010; end
      5'd24: begin alu_op = 4'd15; f_we = 4'b0010; end
      5'd25: begin alu_op = 4'd5; f_we = 4'b1110; end     // BIT: N and V from memory
      5'd26: begin alu_op = 4'd5; f_we = 4'b0010; end     // BIT immediate: only Z
      5'd27: begin wr_en = 1'b1; f_we = 4'b1010; end      // XBA
      5'd28: begin p_we = 1'b1; p_val = dl_by; end
      5'd31: begin p_we = 1'b1; p_val = (r_p | 8'h04) & 8'hF7; end   // set I, clear D
      default: ;
    endcase
  end

  // flag values: from the extensions during WDM, from memory for BIT, from the old high byte
  // for XBA, else from the ALU. Mask order N V Z C.
  wire [3:0] ext_mask = {ext_f_we, ext_fv_we, ext_f_we, 1'b0};
  wire [3:0] f_mask = is_wdm ? ext_mask : (commit ? f_we : 4'd0);
  wire bit_n = w8 ? mem_v[7] : mem_v[15];
  wire bit_v = w8 ? mem_v[6] : mem_v[14];
  wire xba_z = (r_a[15:8] == 8'h00);
  wire f_n = is_wdm ? ext_f_n : is_bit ? bit_n : is_xba ? r_a[15] : alu_n;
  wire f_v = is_wdm ? ext_f_v : is_bit ? bit_v : alu_v;
  wire f_z = is_wdm ? ext_f_z : is_xba ? xba_z : alu_z;
  wire f_c = is_xce ? r_e : alu_c;
  wire [15:0] swapped = {r_a[7:0], r_a[15:8]};
  wire [15:0] wr_val = is_xba ? swapped : alu_r;
  wire wr_w16 = is_xba || !w8;

  // block move: one byte for each pass; X and Y step with the index width, A counts down
  wire mv_we = commit && ((op == 5'd29) || (op == 5'd30));
  wire mv_up = (op == 5'd29);
  wire [15:0] mv_x = mv_up ? (r_x + 16'd1) : (r_x - 16'd1);
  wire [15:0] mv_y = mv_up ? (r_y + 16'd1) : (r_y - 16'd1);
  wire [15:0] mv_a = r_a - 16'd1;

  // hold = 1: an instruction of the 65816 that leaves page 1 on the stack in emulation mode
  wire s_wide = (hold == 2'd1);
  wire s_open = s_wide && !commit;

  c816_regs u_regs (
    .clk(clk), .rst(rst),
    .wr_en(commit && wr_en), .wr_sel(dst), .wr_val(wr_val), .wr_w16(wr_w16),
    .ext_we_a(ext_we_a), .ext_we_y(ext_we_y), .ext_a(ext_a), .ext_y(ext_y),
    .f_we(f_mask), .f_n(f_n), .f_v(f_v), .f_z(f_z), .f_c(f_c),
    .p_we(commit && p_we), .p_val(p_val), .e_we(commit && e_we), .e_val(r_p[0]),
    .pc_we(pc_we), .pc_val(pc_next), .pbr_we(pbr_we), .pbr_val(pbr_next),
    .s_inc(cyc_end && (sop == 2'd1)), .s_dec(cyc_end && (sop == 2'd2)),
    .s_wide(s_wide), .s_open(s_open),
    .mv_we(mv_we), .mv_a(mv_a), .mv_x(mv_x), .mv_y(mv_y), .mv_dbr(ba),
    .a(r_a), .x(r_x), .y(r_y), .s(r_s), .d(r_d), .pc(r_pc),
    .pbr(r_pbr), .dbr(r_dbr), .p(r_p), .e(r_e)
  );

  // ---- address unit ----
  c816_addr u_addr (
    .asel(asel), .ea(ea), .pc(r_pc), .pbr(r_pbr), .dbr(r_dbr), .s(r_s), .x(r_x), .y(r_y),
    .d(r_d), .e(r_e), .w8(w8), .al(al), .ah(ah), .ba(ba), .of(of), .vec(vec),
    .addr(addr), .xcarry(xcarry), .br_cross(br_cross), .br_target(br_target), .rel16(rel16),
    .pc_m1(pc_m1)
  );

  // ---- sequencer ----
  // XNC skips the dummy step only with an 8-bit index (P.X = 1): a 16-bit index acts as a carry
  c816_seq u_seq (
    .clk(clk), .rst(rst), .halt(halt), .bus_wait(bus_wait), .bus(bus), .last(last),
    .skip(skip), .imp(imp), .w8(w8), .taken(taken), .br_cross(br_cross),
    .xcarry(xcarry || !r_p[4]), .is_store(is_store), .e(r_e), .dlz(r_d[7:0] == 8'h00),
    .hold(hold), .wake(wake),
    .t(t), .ph(ph), .illegal(illegal), .cyc_end(cyc_end), .commit(commit), .skip1(skip1),
    .rd(rd), .wr(wr), .sync(sync)
  );

  // ---- latches ----
  always @(posedge clk) begin
    if (rst) begin
      ir <= 9'h100;
      al <= 8'h00;
      ah <= 8'h00;
      ba <= 8'h00;
      dl <= 8'h00;
      dh <= 8'h00;
      of <= 8'h00;
    end else if (cyc_end && reads) begin
      case (cap)
        3'd1: al <= din;
        3'd2: ah <= din;
        3'd3: ba <= din;
        3'd4: dl <= din;
        3'd5: dh <= din;
        3'd6: ir <= take_nmi && fetch_int ? 9'h101 : fetch_int ? 9'h102 : {1'b0, din};
        3'd7: of <= din;
        default: ;
      endcase
    end
  end

  // ---- interrupt requests ----
  wire is_int_seq = (op == 5'd31);
  wire irq_mask = (ir == 9'h040) ? dl_by[2] : r_p[2];
  always @(posedge clk) begin
    if (rst) begin
      nmi_q <= 1'b0;
      nmi_pend <= 1'b0;
      take_nmi <= 1'b0;
      take_irq <= 1'b0;
    end else begin
      nmi_q <= nmi;
      if (nmi && !nmi_q) nmi_pend <= 1'b1;
      else if (cyc_end && fetch_int && take_nmi) nmi_pend <= 1'b0;
      if (commit) begin
        // The flags that the instruction found decide (CLI, SEI, and PLP act one instruction
        // later); RTI acts at once. An interrupt or BRK sequence takes no second request: the
        // first instruction of the handler always runs.
        take_nmi <= nmi_pend && !is_int_seq;
        take_irq <= irq && !irq_mask && !is_int_seq;
      end else if (cyc_end && (t == 4'd0)) begin
        take_nmi <= 1'b0;
        take_irq <= 1'b0;
      end
    end
  end

  // ---- written byte ----
  // wsel: 0 low byte of src, 1 high byte of src, 2-3 PC - 1, 4-5 ALU result, 6 DL, 7 PBR,
  // 8 AL, 9 AH, 10-11 PC, 12-13 PC + {AH, AL}, 14 P (in emulation mode, NMI and IRQ push it
  // with bit 4 at 0)
  reg [7:0] wbyte;
  always @* begin
    case (wsel)
      4'd1: wbyte = src_v[15:8];
      4'd2: wbyte = pc_m1[7:0];
      4'd3: wbyte = pc_m1[15:8];
      4'd4: wbyte = alu_r[7:0];
      4'd5: wbyte = alu_r[15:8];
      4'd6: wbyte = dl;
      4'd7: wbyte = r_pbr;
      4'd8: wbyte = al;
      4'd9: wbyte = ah;
      4'd10: wbyte = r_pc[7:0];
      4'd11: wbyte = r_pc[15:8];
      4'd12: wbyte = rel16[7:0];
      4'd13: wbyte = rel16[15:8];
      4'd14: wbyte = (r_e && hw_int) ? (r_p & 8'hEF) : r_p;
      default: wbyte = src_v[7:0];
    endcase
  end
  assign wdata = wbyte;
  assign dbg_illegal = illegal;
  assign dbg_pc = r_pc;
  assign dbg_a = r_a;
  assign dbg_x = r_x;
  assign dbg_y = r_y;
endmodule
