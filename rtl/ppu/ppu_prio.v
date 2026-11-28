// ppu_prio.v - the front pixel of one screen, in the PPU2, and its colour number in the colour
// memory. Today: the backgrounds of the modes 0 and 1. Sprites come with step P6.
// Front to back, mode 0: 1H 2H 1L 2L 3H 4H 3L 4L. Mode 1: 1H 2H 1L 2L 3H 3L, and with $2105
// bit 3 the order is 3H 1H 2H 1L 2L 3L. (H: priority bit 1 of the tile; L: 0.)
// Colour numbers: mode 0: (layer - 1) x 32 + palette x 4 + number. Mode 1: palette x 16 + number
// for layers 1 and 2, palette x 4 + number for layer 3. The backdrop is colour 0.
module ppu_prio (
  input [2:0] mode,
  input bg3_front,              // $2105 bit 3
  input [4:0] enable,           // $212C or $212D
  input [3:0] opaque,
  input [3:0] pri,
  input [2:0] pal1, input [2:0] pal2, input [2:0] pal3, input [2:0] pal4,
  input [3:0] num1, input [3:0] num2, input [3:0] num3, input [3:0] num4,
  output reg [2:0] layer,       // 0 backdrop, 1 to 4 a background
  output reg [7:0] index
);
  wire [3:0] in_mode = (mode == 3'd0) ? 4'b1111 : ((mode == 3'd1) ? 4'b0111 : 4'b0000);
  wire [3:0] shown = opaque & enable[3:0] & in_mode;
  wire [3:0] hi = shown & pri;
  wire [3:0] lo = shown & ~pri;

  always @* begin
    if (mode == 3'd1 && bg3_front && hi[2]) layer = 3'd3;
    else if (hi[0]) layer = 3'd1;
    else if (hi[1]) layer = 3'd2;
    else if (lo[0]) layer = 3'd1;
    else if (lo[1]) layer = 3'd2;
    else if (hi[2]) layer = 3'd3;
    else if (hi[3]) layer = 3'd4;
    else if (lo[2]) layer = 3'd3;
    else if (lo[3]) layer = 3'd4;
    else layer = 3'd0;
  end

  always @* begin
    case (layer)
      3'd1: index = (mode == 3'd0) ? {3'b000, pal1, num1[1:0]} : {1'b0, pal1, num1};
      3'd2: index = (mode == 3'd0) ? {3'b001, pal2, num2[1:0]} : {1'b0, pal2, num2};
      3'd3: index = (mode == 3'd0) ? {3'b010, pal3, num3[1:0]} : {3'b000, pal3, num3[1:0]};
      3'd4: index = {3'b011, pal4, num4[1:0]};
      default: index = 8'd0;
    endcase
  end
endmodule
