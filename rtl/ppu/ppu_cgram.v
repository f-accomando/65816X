// ppu_cgram.v - the colour memory: 256 words of 15 bits (blue, green, red), in the PPU2.
// Bus side: $2121 sets the word address and forgets a half word. $2122 takes the low byte first;
// the second write stores the word and advances the address. Bit 15 is not stored.
// Render side: a registered read port. One write port and one read port: the form of a block RAM.
// Simplification: a write is accepted at any time (the real chip needs a blank period).
module ppu_cgram (
  input clk,
  input rst,
  input wr_addr,            // write to $2121
  input wr_data,            // write to $2122
  input [7:0] wdata,
  input [7:0] raddr,
  output reg [14:0] rdata
);
  reg [14:0] mem [0:255];
  reg [7:0] cgadd, low;
  reg half;                 // 1: the low byte waits for the high byte

  always @(posedge clk) begin
    rdata <= mem[raddr];
    if (rst) begin
      cgadd <= 8'd0; low <= 8'd0; half <= 1'b0;
    end else if (wr_addr) begin
      cgadd <= wdata;
      half <= 1'b0;
    end else if (wr_data) begin
      if (!half) begin
        low <= wdata;
        half <= 1'b1;
      end else begin
        mem[cgadd] <= {wdata[6:0], low};
        cgadd <= cgadd + 8'd1;
        half <= 1'b0;
      end
    end
  end
endmodule
