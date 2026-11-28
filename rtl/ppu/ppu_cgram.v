// ppu_cgram.v - the colour memory: 256 words of 15 bits (blue, green, red), in the PPU2.
// Bus side: $2121 sets the word address and clears the byte flip-flop. $2122 takes the low byte,
// then the high byte; the second write stores the word and advances the address. Bit 15 is not
// stored. A read of $213B uses the same flip-flop and advances the address after the high byte.
// Port A (bus) has one address; its registered read gives the word at the address one clk later.
// Port B is for the renderer. One write port and two read ports.
// Simplification: a write is accepted at any time (the real chip needs a blank period).
module ppu_cgram (
  input clk,
  input rst,
  input wr_addr,            // write to $2121
  input wr_data,            // write to $2122
  input rd_data,            // read of $213B
  input [7:0] wdata,
  output reg [7:0] cgadd,
  output reg half,          // 0: the low byte comes next; 1: the high byte
  output reg [14:0] qdata,  // port A: the word at cgadd
  input [7:0] raddr,
  output reg [14:0] rdata   // port B
);
  reg [14:0] mem [0:255];
  reg [7:0] low;
  wire commit = wr_data && half && !rst;

  always @(posedge clk) begin
    // no port reads in the clk of a write: then the synthesis needs no old-data copy of the array
    if (commit) mem[cgadd] <= {wdata[6:0], low};
    else begin
      qdata <= mem[cgadd];
      rdata <= mem[raddr];
    end
    if (rst) begin
      cgadd <= 8'd0; low <= 8'd0; half <= 1'b0;
    end else if (wr_addr) begin
      cgadd <= wdata;
      half <= 1'b0;
    end else if (wr_data) begin
      if (!half) low <= wdata;
      else cgadd <= cgadd + 8'd1;
      half <= !half;
    end else if (rd_data) begin
      if (half) cgadd <= cgadd + 8'd1;
      half <= !half;
    end
  end
endmodule
