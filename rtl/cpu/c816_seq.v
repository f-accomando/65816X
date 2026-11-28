// c816_seq.v - sequencer of the c816 core (docs/design/cpu-core.md, section 5.1).
// One CPU cycle is two FPGA clocks: phase 0 (address and strobe) and phase 1 (data).
// halt holds phase 0. bus_wait stretches phase 1. t is the step of the instruction.
module c816_seq (
  input clk,
  input rst,
  input halt,
  input bus_wait,
  input [2:0] bus,
  input [2:0] last,
  input [2:0] skip,
  input imp,
  input w8,
  input taken,
  input br_cross,
  input xcarry,
  input is_store,
  input e,
  input dlz,
  input [1:0] hold,
  input wake,
  output reg [3:0] t,
  output reg ph,
  output reg illegal,
  output cyc_end,
  output commit,
  output skip1,
  output rd,
  output wr,
  output sync
);
  // bus codes: 0 IO, 1 OPF, 2 PRG, 3 DAT, 4 DRD, 5 DWR, 6 MOD (a write only in emulation mode)
  wire reads = (bus == 3'd1) || (bus == 3'd2) || (bus == 3'd4) || ((bus == 3'd3) && !is_store);
  wire writes = (bus == 3'd5) || ((bus == 3'd3) && is_store) || ((bus == 3'd6) && e);

  // hold codes: 0 none, 1 wide stack, 2 WAI (repeat the step until wake), 3 STP (repeat for ever)
  wire stall = ((hold == 2'd2) && !wake) || (hold == 2'd3);

  // last codes: 0 NO, 1 ALW, 2 W8, 3 NTK, 4 NEC, 5 EMU
  wire is_last = !stall && ((last == 3'd1) || ((last == 3'd2) && w8) || ((last == 3'd3) && !taken) ||
                 ((last == 3'd4) && !(e && br_cross)) || ((last == 3'd5) && e));
  // skip codes: 0 NO, 1 XNC, 2 W8, 3 DL0 (dlz = 1: D[7:0] is 0), 4 EMU
  assign skip1 = ((skip == 3'd1) && !is_store && !xcarry) || ((skip == 3'd2) && w8) ||
                 ((skip == 3'd3) && dlz) || ((skip == 3'd4) && e);

  assign rd = !ph && !halt && reads;
  assign wr = !ph && !halt && writes;
  assign sync = (t == 4'd0);
  assign cyc_end = ph && !bus_wait;
  assign commit = cyc_end && is_last;

  always @(posedge clk) begin
    if (rst) begin
      t <= 4'd1;
      ph <= 1'b0;
      illegal <= 1'b0;
    end else if (!ph) begin
      if (!halt) ph <= 1'b1;
    end else if (!bus_wait) begin
      ph <= 1'b0;
      if ((t == 4'd1) && !imp) illegal <= 1'b1;
      if (is_last) t <= 4'd0;
      else if (stall) t <= t;
      else if (skip1) t <= t + 4'd2;
      else t <= t + 4'd1;
    end
  end
endmodule
