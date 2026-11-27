// cpu_adapt_old.vh - adapter of the old core cpu65816x for tb_cpu.v.
// The count is the number of FPGA clocks: this core is not cycle accurate, so the adapter
// reports no cycle or bus difference.
  wire [15:0] dbg_pc, dbg_a, dbg_x, dbg_y;

  cpu65816x dut (
    .clk(clk), .rst(rst), .halt(1'b0), .ext_en(1'b0),
    .addr(addr), .rd(rd), .wr(wr), .wdata(wdata), .din(din),
    .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_x(dbg_x), .dbg_y(dbg_y)
  );

  task load_state;
    begin
      dut.pc = ini[0]; dut.s = ini[1];
      {dut.fn, dut.fv, dut.fm, dut.fx} = ini[2][7:4];
      {dut.fi, dut.fz, dut.fc} = ini[2][2:0];
      dut.a = ini[3]; dut.x = ini[4]; dut.y = ini[5];
      dut.db = ini[6]; dut.pb = ini[8]; dut.fe = ini[9][0];
      dut.acc = 32'd0; dut.op = 8'd0;
      dut.st = 4'd0; dut.ph = 1'b0; dut.n = 2'd0;
    end
  endtask

  // the instruction ends when the core goes back to the fetch state (0) after it left it
  task run_instruction;
    begin
      count = 0;
      timeout = 1'b0;
      bus_bad = 1'b0;
      illegal = 1'b0;
      while (dut.st === 4'd0 && !timeout) begin
        @(posedge clk); #1; count = count + 1;
        if (count >= MAXCLK) timeout = 1'b1;
      end
      while (dut.st !== 4'd0 && !timeout) begin
        @(posedge clk); #1; count = count + 1;
        if (count >= MAXCLK) timeout = 1'b1;
      end
    end
  endtask

  // the core has no D register and no D flag: they stay at the initial value and at 0
  function [15:0] state_diff;
    input dummy;
    reg [7:0] p;
    begin
      p = {dut.fn, dut.fv, dut.fm, dut.fx, 1'b0, dut.fi, dut.fz, dut.fc};
      state_diff = 16'd0;
      if (dut.pc !== fin[0][15:0]) state_diff[F_PC] = 1'b1;
      if (dut.s !== fin[1][15:0]) state_diff[F_S] = 1'b1;
      if (p !== fin[2][7:0]) state_diff[F_P] = 1'b1;
      if (dut.a !== fin[3][15:0]) state_diff[F_A] = 1'b1;
      if (dut.x !== fin[4][15:0]) state_diff[F_X] = 1'b1;
      if (dut.y !== fin[5][15:0]) state_diff[F_Y] = 1'b1;
      if (dut.db !== fin[6][7:0]) state_diff[F_DBR] = 1'b1;
      if (ini[7] !== fin[7]) state_diff[F_D] = 1'b1;
      if (dut.pb !== fin[8][7:0]) state_diff[F_PBR] = 1'b1;
      if (dut.fe !== fin[9][0]) state_diff[F_E] = 1'b1;
    end
  endfunction
