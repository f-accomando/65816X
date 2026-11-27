// c816_core.v - top of the c816 core, a cycle-accurate 65C816 (docs/design/cpu-core.md).
// One CPU cycle is two FPGA clocks: phase 0 drives addr and one rd or wr pulse, phase 1 waits
// for din. The core captures din at the clock that ends phase 1 (cyc_end).
// Latches: IR (9 bits, bit 8 = pseudo-opcode), AL, AH, BA, DL, DH, OF (direct page or stack
// offset). Execute happens at commit.
// nmi and irq are reserved and have no effect yet. WDM runs the extensions only with ext_en = 1.
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
  wire [4:0] seq;
  wire [4:0] op;
  wire [3:0] ea;
  wire [2:0] w;
  wire [2:0] src;
  wire [2:0] dst;
  wire [3:0] arg;
  wire imp;
  wire [4:0] seq_wdmx;
  c816_decode u_dec (
    .ir(ir), .seq(seq), .op(op), .ea(ea), .w(w), .src(src), .dst(dst), .arg(arg),
    .imp(imp), .seq_wdmx(seq_wdmx)
  );
  wire [4:0] seq_eff = ((ir == 9'h042) && ext_en) ? seq_wdmx : seq;

  // ---- cycle descriptor ----
  wire [3:0] t;
  wire [2:0] bus;
  wire [4:0] asel;
  wire [2:0] cap;
  wire pcinc;
  wire [1:0] sop;
  wire [2:0] wsel;
  wire [2:0] last;
  wire [2:0] skip;
  wire [2:0] pcop;
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

  // ---- width, condition, bus kind ----
  // w codes: 0 M, 1 X, 2 B8, 3 W16
  wire w8 = (w == 3'd0) ? r_p[5] : (w == 3'd1) ? r_p[4] : (w != 3'd3);
  wire taken = (op == 5'd17) || (r_p[arg[2:0]] == arg[3]);
  wire is_store = (op == 5'd2);
  wire reads = (bus == 3'd1) || (bus == 3'd2) || (bus == 3'd4) || ((bus == 3'd3) && !is_store);
  assign vda = (bus == 3'd1) || (bus == 3'd3) || (bus == 3'd4) || (bus == 3'd5);
  assign vpa = (bus == 3'd1) || (bus == 3'd2);

  reg wr_en;
  reg [3:0] f_we;
  reg p_we;
  reg [7:0] p_val;
  reg e_we;
  reg [3:0] alu_op;
  wire [15:0] alu_r;
  wire alu_n, alu_v, alu_z, alu_c;
  wire is_xce = (op == 5'd15);
  // PC changes: pcop has priority over the increment. pcop codes: 1 ABS, 2 LONG (also PBR),
  // 3 BRL (branch target if this step is the last), 4 BR (branch target), 5 RTS ({AH, AL} + 1).
  // al_by, ah_by, ba_by include the byte that the current cycle captures.
  wire [7:0] al_by = (reads && (cap == 3'd1)) ? din : al;
  wire [7:0] ah_by = (reads && (cap == 3'd2)) ? din : ah;
  wire [7:0] ba_by = (reads && (cap == 3'd3)) ? din : ba;
  wire xcarry;
  wire br_cross;
  wire [15:0] br_target;
  wire [15:0] pc_m1;
  wire load_abs = (pcop == 3'd1) || (pcop == 3'd2);
  wire load_br = (pcop == 3'd4) || ((pcop == 3'd3) && commit);
  wire load_rts = (pcop == 3'd5);
  wire pc_we = cyc_end && (pcinc || load_abs || load_br || load_rts);
  wire [15:0] pc_next = load_abs ? {ah_by, al_by} :
                        load_br ? br_target :
                        load_rts ? ({ah, al} + 16'd1) : r_pc + 16'd1;
  wire pbr_we = cyc_end && (pcop == 3'd2);

  // bypass: the execute logic sees the byte that the current cycle captures
  wire [7:0] dl_by = (reads && (cap == 3'd4)) ? din : dl;
  wire [7:0] dh_by = (reads && (cap == 3'd5)) ? din : dh;

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
  // flag write mask in the order N V Z C: from the extensions during WDM, else from execute
  wire [3:0] ext_mask = {ext_f_we, ext_fv_we, ext_f_we, 1'b0};
  wire [3:0] f_mask = is_wdm ? ext_mask : (commit ? f_we : 4'd0);
  c816_regs u_regs (
    .clk(clk), .rst(rst),
    .wr_en(commit && wr_en), .wr_sel(dst), .wr_val(alu_r), .wr_w16(!w8),
    .ext_we_a(ext_we_a), .ext_we_y(ext_we_y), .ext_a(ext_a), .ext_y(ext_y),
    .f_we(f_mask), .f_n(is_wdm ? ext_f_n : alu_n), .f_v(is_wdm ? ext_f_v : alu_v),
    .f_z(is_wdm ? ext_f_z : alu_z), .f_c(is_xce ? r_e : alu_c),
    .p_we(commit && p_we), .p_val(p_val), .e_we(commit && e_we), .e_val(r_p[0]),
    .pc_we(pc_we), .pc_val(pc_next), .pbr_we(pbr_we), .pbr_val(ba_by),
    .s_inc(cyc_end && (sop == 2'd1)), .s_dec(cyc_end && (sop == 2'd2)),
    .a(r_a), .x(r_x), .y(r_y), .s(r_s), .d(r_d), .pc(r_pc),
    .pbr(r_pbr), .dbr(r_dbr), .p(r_p), .e(r_e)
  );

  // ---- address unit ----
  c816_addr u_addr (
    .asel(asel), .ea(ea), .pc(r_pc), .pbr(r_pbr), .dbr(r_dbr), .s(r_s), .x(r_x), .y(r_y),
    .d(r_d), .e(r_e), .al(al), .ah(ah), .ba(ba), .of(of), .vec(8'hFC),
    .addr(addr), .xcarry(xcarry), .br_cross(br_cross), .br_target(br_target), .pc_m1(pc_m1)
  );

  // ---- sequencer ----
  // XNC skips the dummy step only with an 8-bit index (P.X = 1): a 16-bit index acts as a carry
  c816_seq u_seq (
    .clk(clk), .rst(rst), .halt(halt), .bus_wait(bus_wait), .bus(bus), .last(last),
    .skip(skip), .imp(imp), .w8(w8), .taken(taken), .br_cross(br_cross),
    .xcarry(xcarry || !r_p[4]), .is_store(is_store), .e(r_e), .dlz(r_d[7:0] == 8'h00),
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
        3'd6: ir <= {1'b0, din};
        3'd7: of <= din;
        default: ;
      endcase
    end
  end

  // ---- execute (at commit) ----
  reg [15:0] src_v;
  wire [7:0] bitm = 8'd1 << arg[2:0];
  always @* begin
    case (src)
      3'd1: src_v = r_a;
      3'd2: src_v = r_x;
      3'd3: src_v = r_y;
      3'd4: src_v = r_s;
      3'd5: src_v = r_d;
      default: src_v = 16'd0;
    endcase
  end

  c816_alu u_alu (
    .op(alu_op), .a(src_v), .b({dh_by, dl_by}), .ci(r_p[0]), .w16(!w8), .dec(r_p[3]),
    .r(alu_r), .n(alu_n), .v(alu_v), .z(alu_z), .c(alu_c)
  );

  // op codes: 1 LD, 2 ST, 3 TR, 4 ADC, 5 SBC, 6 CMP, 7 AND, 8 ORA, 9 EOR, 10 INC, 11 DEC,
  // 12 FLG, 13 REP, 14 SEP, 15 XCE; the others write no register yet
  always @* begin
    alu_op = 4'd0;
    wr_en = 1'b0;
    f_we = 4'b0000;
    p_we = 1'b0;
    p_val = r_p;
    e_we = 1'b0;
    case (op)
      5'd1: begin alu_op = 4'd0; wr_en = (dst != 3'd0); f_we = 4'b1010; end
      5'd3: begin alu_op = 4'd1; wr_en = (dst != 3'd0); f_we = 4'b1010; end
      5'd4: begin alu_op = 4'd2; wr_en = 1'b1; f_we = 4'b1111; end
      5'd5: begin alu_op = 4'd3; wr_en = 1'b1; f_we = 4'b1111; end
      5'd6: begin alu_op = 4'd4; f_we = 4'b1011; end
      5'd7: begin alu_op = 4'd5; wr_en = 1'b1; f_we = 4'b1010; end
      5'd8: begin alu_op = 4'd6; wr_en = 1'b1; f_we = 4'b1010; end
      5'd9: begin alu_op = 4'd7; wr_en = 1'b1; f_we = 4'b1010; end
      5'd10: begin alu_op = 4'd8; wr_en = (dst != 3'd0); f_we = 4'b1010; end
      5'd11: begin alu_op = 4'd9; wr_en = (dst != 3'd0); f_we = 4'b1010; end
      5'd12: begin p_we = 1'b1; p_val = arg[3] ? (r_p | bitm) : (r_p & ~bitm); end
      5'd13: begin p_we = 1'b1; p_val = r_p & ~dl_by; end
      5'd14: begin p_we = 1'b1; p_val = r_p | dl_by; end
      5'd15: begin f_we = 4'b0001; e_we = 1'b1; end
      default: ;
    endcase
  end

  // written byte. wsel codes: 0 low byte of src, 1 high byte of src, 2 and 3 low and high byte
  // of PC - 1 (JSR)
  assign wdata = (wsel == 3'd1) ? src_v[15:8] :
                 (wsel == 3'd2) ? pc_m1[7:0] :
                 (wsel == 3'd3) ? pc_m1[15:8] : src_v[7:0];
  assign dbg_illegal = illegal;
  assign dbg_pc = r_pc;
  assign dbg_a = r_a;
  assign dbg_x = r_x;
  assign dbg_y = r_y;
endmodule
