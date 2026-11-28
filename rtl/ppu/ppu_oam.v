// ppu_oam.v - the sprite memory: 512 bytes (low table, as 256 words) and 32 bytes (high table).
// Byte addresses $200 to $3FF give the high table, which repeats each 32 bytes.
// The low table is written one word at a time; the high table one byte at a time.
// The read is registered: the data follow the address by one clk.
// A port for the renderer comes with step P6.
module ppu_oam (
  input clk,
  input [9:0] addr,
  input we_word,            // write wdata to the word of the low table at addr
  input we_high,            // write the low byte of wdata to the high table at addr
  input [15:0] wdata,
  output [7:0] rdata
);
  reg [15:0] low [0:255];
  reg [7:0] high [0:31];
  reg [15:0] q_low;
  reg [7:0] q_high;
  reg sel_high, sel_odd;

  always @(posedge clk) begin
    if (we_word) low[addr[8:1]] <= wdata;
    q_low <= low[addr[8:1]];
    if (we_high) high[addr[4:0]] <= wdata[7:0];
    q_high <= high[addr[4:0]];
    sel_high <= addr[9];
    sel_odd <= addr[0];
  end

  assign rdata = sel_high ? q_high : (sel_odd ? q_low[15:8] : q_low[7:0]);
endmodule
