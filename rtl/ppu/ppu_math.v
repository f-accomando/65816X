// ppu_math.v - the end of the pixel path, in the PPU2. Today: the colour of the main screen, the
// forced blank, and the brightness. Colour math, and the colour of the sub screen, come with step
// P7.
// The unit samples the registers and the layers in the first clk of each visible dot (dot_en). The
// colour memory gets the number of the main screen in that clk; the pixel follows 2 clk later.
// Thus a register write during a dot acts from the next dot.
// Visible: lines 1 to 224 (239 with overscan), dots 22 to 277.
module ppu_math (
  input clk,
  input rst,
  input dot_en,                  // first clk of a new dot
  input [8:0] hdot,
  input [8:0] vcnt,
  input overscan,
  input [7:0] inidisp,           // $2100: bit 7 forced blank, bits 3-0 brightness
  input [2:0] main_layer,
  input [2:0] sub_layer,
  input [14:0] colour_in,        // the colour memory, one clk after dot_en
  output reg pix_valid,          // one clk pulse for each visible dot
  output reg [8:0] pix_x,        // 0 to 255
  output reg [8:0] pix_y,        // 0 to 238
  output reg [14:0] pix_even,    // colour before the brightness: blue, green, red
  output reg [14:0] pix_odd,     // the same as pix_even in the 256-wide modes
  output pix_hires,
  output reg [3:0] bright,       // the video output scales the colour by this value
  output reg [2:0] dbg_layer,    // for the tests: layer of the main screen; 7 forced blank
  output reg [2:0] dbg_sub       // the same for the sub screen
);
  wire [8:0] vlast = overscan ? 9'd239 : 9'd224;
  wire visible = (vcnt >= 9'd1) && (vcnt <= vlast) && (hdot >= 9'd22) && (hdot <= 9'd277);

  reg s_valid;                   // second stage: the colour memory answers
  reg [8:0] s_x, s_y;
  reg [7:0] s_inidisp;
  reg [2:0] s_main, s_sub;

  wire [14:0] colour = s_inidisp[7] ? 15'd0 : colour_in;

  assign pix_hires = 1'b0;

  always @(posedge clk) begin
    s_valid <= 1'b0;
    pix_valid <= 1'b0;
    if (rst) begin
      s_x <= 9'd0; s_y <= 9'd0; s_inidisp <= 8'h80; s_main <= 3'd0; s_sub <= 3'd0;
      pix_x <= 9'd0; pix_y <= 9'd0; pix_even <= 15'd0; pix_odd <= 15'd0;
      bright <= 4'd0; dbg_layer <= 3'd0; dbg_sub <= 3'd0;
    end else begin
      if (dot_en && visible) begin
        s_valid <= 1'b1;
        s_x <= hdot - 9'd22;
        s_y <= vcnt - 9'd1;
        s_inidisp <= inidisp;
        s_main <= main_layer;
        s_sub <= sub_layer;
      end
      if (s_valid) begin
        pix_valid <= 1'b1;
        pix_x <= s_x;
        pix_y <= s_y;
        pix_even <= colour;
        pix_odd <= colour;
        bright <= s_inidisp[3:0];
        dbg_layer <= s_inidisp[7] ? 3'd7 : s_main;
        dbg_sub <= s_inidisp[7] ? 3'd7 : s_sub;
      end
    end
  end
endmodule
