// cpu_adapt_c816.vh - adapter of the new core c816_core for tb_cpu.v (docs/design/cpu-core.md, 7.2).
// The count is the number of CPU cycles, taken from the ports only: cyc_end ends a cycle, and
// sync = 1 after at least one cycle marks the next opcode fetch.
// If the vector has a bus list (nc > 0), every cycle is compared with it: VDA, VPA, address,
// the strobe of phase 0 (rd for a read, wr for a write, none for an IO cycle) and the written byte.
  wire [15:0] dbg_pc, dbg_a, dbg_x, dbg_y;
  wire vda, vpa, sync, cyc_end, dbg_illegal;

  c816_core dut (
    .clk(clk), .rst(rst), .halt(1'b0), .bus_wait(1'b0), .ext_en(1'b0), .nmi(1'b0), .irq(1'b0),
    .din(din), .addr(addr), .rd(rd), .wr(wr), .wdata(wdata), .vda(vda), .vpa(vpa),
    .sync(sync), .cyc_end(cyc_end), .dbg_illegal(dbg_illegal),
    .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_x(dbg_x), .dbg_y(dbg_y)
  );

  // the register rules (E = 1, P.X = 1) correct the loaded values at the first clock edge
  task load_state;
    begin
      dut.u_regs.pc = ini[0]; dut.u_regs.s = ini[1]; dut.u_regs.p = ini[2];
      dut.u_regs.a = ini[3]; dut.u_regs.x = ini[4]; dut.u_regs.y = ini[5];
      dut.u_regs.dbr = ini[6]; dut.u_regs.d = ini[7]; dut.u_regs.pbr = ini[8];
      dut.u_regs.e = ini[9][0];
      dut.u_seq.t = 4'd0; dut.u_seq.ph = 1'b0; dut.u_seq.illegal = 1'b0;
      dut.u_ext.acc = 32'd0;
    end
  endtask

  // the instruction is over at the next opcode fetch. A block move fetches its own opcode again
  // after each byte: it is over when the program counter has left it
  function done_now;
    input integer cycles;
    begin
      done_now = cycles > 0 && sync === 1'b1 &&
                 !((opcode[7:0] == 8'h54 || opcode[7:0] == 8'h44) && dut.u_regs.pc === ini[0][15:0]);
    end
  endfunction

  // called at a negative edge; returns just after a positive edge
  reg ce, s_rd, s_wr;
  reg [7:0] s_wdata;
  integer clocks, k;
  task run_instruction;
    begin
      count = 0;
      clocks = 0;
      k = 0;
      timeout = 1'b0;
      bus_bad = 1'b0;
      illegal = 1'b0;
      #1;
      while (!timeout && !done_now(count)) begin
        ce = cyc_end;
        if (ce !== 1'b1) begin
          // phase 0: keep the strobes for the check at the end of the cycle
          s_rd = rd; s_wr = wr; s_wdata = wdata;
        end else if (nc > 0) begin
          if (k >= nc) bus_bad = 1'b1;
          else begin
            if (vda !== ck[k][0] || vpa !== ck[k][1] || addr !== ca[k][23:0]) bus_bad = 1'b1;
            if (ck[k][2]) begin
              if (s_wr !== 1'b1 || s_rd !== 1'b0 || s_wdata !== cv[k][7:0]) bus_bad = 1'b1;
            end else if (ck[k][1:0] != 2'd0) begin
              if (s_rd !== 1'b1 || s_wr !== 1'b0) bus_bad = 1'b1;
            end else begin
              if (s_rd !== 1'b0 || s_wr !== 1'b0) bus_bad = 1'b1;
            end
          end
          k = k + 1;
        end
        @(posedge clk); #1;
        if (ce === 1'b1) count = count + 1;
        clocks = clocks + 1;
        if (clocks >= MAXCLK) timeout = 1'b1;
        if (!timeout && !done_now(count)) begin
          @(negedge clk); #1;
        end
      end
      if (nc > 0 && k != nc) bus_bad = 1'b1;
      illegal = (dbg_illegal !== 1'b0);
    end
  endtask

  function [15:0] state_diff;
    input dummy;
    begin
      state_diff = 16'd0;
      if (dut.u_regs.pc !== fin[0][15:0]) state_diff[F_PC] = 1'b1;
      if (dut.u_regs.s !== fin[1][15:0]) state_diff[F_S] = 1'b1;
      if (dut.u_regs.p !== fin[2][7:0]) state_diff[F_P] = 1'b1;
      if (dut.u_regs.a !== fin[3][15:0]) state_diff[F_A] = 1'b1;
      if (dut.u_regs.x !== fin[4][15:0]) state_diff[F_X] = 1'b1;
      if (dut.u_regs.y !== fin[5][15:0]) state_diff[F_Y] = 1'b1;
      if (dut.u_regs.dbr !== fin[6][7:0]) state_diff[F_DBR] = 1'b1;
      if (dut.u_regs.d !== fin[7][15:0]) state_diff[F_D] = 1'b1;
      if (dut.u_regs.pbr !== fin[8][7:0]) state_diff[F_PBR] = 1'b1;
      if (dut.u_regs.e !== fin[9][0]) state_diff[F_E] = 1'b1;
      if (expcyc != 0 && count != expcyc) state_diff[F_CYC] = 1'b1;
    end
  endfunction
