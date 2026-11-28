// ppu_math.v - the end of the pixel path, in the PPU2. Today: the backdrop colour, the forced
// blank, and the brightness. Colour math and the sub screen come with step P7.
// The unit samples the registers in the first clk of each visible dot (dot_en) and gives the pixel
// one clk later. Thus a register write during a dot acts from the next dot.
// Visible: lines 1 to 224 (239 with overscan), dots 22 to 277.
module ppu_math (
  input clk,
  input rst,
  input dot_en,                  // first clk of a new dot
  input [8:0] hdot,
  input [8:0] vcnt,
  input overscan,
  input [7:0] inidisp,           // $2100: bit 7 forced blank, bits 3-0 brightness
  input [14:0] backdrop,         // CGRAM word 0
  output reg pix_valid,          // one clk pulse for each visible dot
  output reg [8:0] pix_x,        // 0 to 255
  output reg [8:0] pix_y,        // 0 to 238
  output reg [14:0] pix_even,    // colour before the brightness: blue, green, red
  output reg [14:0] pix_odd,     // the same as pix_even in the 256-wide modes
  output pix_hires,
  output reg [3:0] bright,       // the video output scales the colour by this value
  output reg [2:0] dbg_layer     // for the tests: 0 backdrop, 7 forced blank
);
  wire [8:0] vlast = overscan ? 9'd239 : 9'd224;
  wire visible = (vcnt >= 9'd1) && (vcnt <= vlast) && (hdot >= 9'd22) && (hdot <= 9'd277);
  wire [14:0] colour = inidisp[7] ? 15'd0 : backdrop;

  assign pix_hires = 1'b0;

  always @(posedge clk) begin
    pix_valid <= 1'b0;
    if (rst) begin
      pix_x <= 9'd0; pix_y <= 9'd0; pix_even <= 15'd0; pix_odd <= 15'd0;
      bright <= 4'd0; dbg_layer <= 3'd0;
    end else if (dot_en && visible) begin
      pix_valid <= 1'b1;
      pix_x <= hdot - 9'd22;
      pix_y <= vcnt - 9'd1;
      pix_even <= colour;
      pix_odd <= colour;
      bright <= inidisp[3:0];
      dbg_layer <= inidisp[7] ? 3'd7 : 3'd0;
    end
  end
endmodule
