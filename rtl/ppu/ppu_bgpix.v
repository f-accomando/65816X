// ppu_bgpix.v - the pixels of one background, in the PPU1: three tile columns (the one that the
// sequencer fetched, the next one, and the current one) and the choice of the bit of this dot.
// A fine scroll takes the first pixels from the current column and the rest from the next one.
// Pixels of the screen start at dot 22, thus the dot in a slot gives the pixel in the column.
module ppu_bgpix (
  input clk,
  input slot_start,             // first clk of a slot: the columns move on
  input load,                   // the tile of this layer is on the inputs
  input [4:0] attr,             // horizontal mirror, priority, palette (3 bits)
  input [15:0] planes01,
  input [15:0] planes23,
  input [8:0] hdot,
  input [2:0] fine,             // low 3 bits of the horizontal scroll
  output opaque,
  output priority_bit,
  output [2:0] palette,
  output [3:0] number           // colour number in the tile; 0 is transparent
);
  reg [36:0] fetched, ahead, current;       // {attr, planes23, planes01}

  always @(posedge clk) begin
    if (load) fetched <= {attr, planes23, planes01};
    if (slot_start) begin
      current <= ahead;
      ahead <= fetched;
    end
  end

  // in the first clk of a slot the columns have not moved yet: look at the new ones
  wire [36:0] now = slot_start ? ahead : current;
  wire [36:0] then_ = slot_start ? fetched : ahead;
  wire [2:0] in_slot = hdot[2:0] - 3'd6;
  wire [3:0] sum = {1'b0, in_slot} + {1'b0, fine};
  wire [36:0] column = sum[3] ? then_ : now;
  wire [4:0] column_attr = column[36:32];
  wire [2:0] which = column_attr[4] ? sum[2:0] : (3'd7 - sum[2:0]);
  wire [15:0] s01 = column[15:0] >> which;
  wire [15:0] s23 = column[31:16] >> which;

  assign number = {s23[8], s23[0], s01[8], s01[0]};
  assign opaque = (number != 4'd0);
  assign priority_bit = column_attr[3];
  assign palette = column_attr[2:0];
endmodule
