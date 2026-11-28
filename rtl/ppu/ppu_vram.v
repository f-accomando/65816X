// ppu_vram.v - the video memory: 32K words of 16 bits, as two arrays of bytes.
// Port A (bus): one address for the write and for the read. The read has an enable: its output
// register is the prefetch buffer of $2139 and $213A. A port for the renderer comes with step P4.
module ppu_vram (
  input clk,
  input [14:0] addr,
  input we_l,
  input we_h,
  input [7:0] wdata,
  input load,               // 1: take the word at addr into the buffer
  output reg [7:0] q_l,
  output reg [7:0] q_h
);
  reg [7:0] vram_l [0:32767];
  reg [7:0] vram_h [0:32767];

  always @(posedge clk) begin
    if (we_l) vram_l[addr] <= wdata;
    if (we_h) vram_h[addr] <= wdata;
    if (load) begin
      q_l <= vram_l[addr];
      q_h <= vram_h[addr];
    end
  end
endmodule
