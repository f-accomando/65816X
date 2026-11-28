// ppu_bgfetch.v - the fetch sequencer of the backgrounds, in the PPU1: one for all layers, on the
// render port of the video memory.
// A line is cut in slots of 8 dots, the first one at dot 6. In slot p the sequencer reads, for each
// background of the mode, the map entry and the tile line of tile column p (column 0 holds screen
// pixel 0). Slot p + 2 draws the pixels 8p to 8p + 7, from the columns p and p + 1. ppu_bgpix.v
// keeps them.
// Each layer takes 4 clk: map address; map entry in, planes 0 and 1; planes 2 and 3; data in.
// A slot has at least 32 clk, thus 4 layers take half of it.
// The registers are read while the layer is fetched.
module ppu_bgfetch (
  input clk,
  input rst,
  input dot_en,
  input [8:0] hdot,
  input [8:0] vcnt,
  input overscan,
  input [7:0] bgmode,
  input [7:0] bg1sc, input [7:0] bg2sc, input [7:0] bg3sc, input [7:0] bg4sc,
  input [7:0] bg12nba, input [7:0] bg34nba,
  input [9:0] bg1hofs, input [9:0] bg2hofs, input [9:0] bg3hofs, input [9:0] bg4hofs,
  input [9:0] bg1vofs, input [9:0] bg2vofs, input [9:0] bg3vofs, input [9:0] bg4vofs,
  output reg [14:0] vaddr,      // render port of the video memory
  input [15:0] vdata,           // the word at vaddr, one clk later
  output slot_start,            // the first clk of a slot: the layers take over the fetched tile
  output reg [3:0] load,        // one pulse: the tile of a layer is ready on the next outputs
  output reg [4:0] attr,        // horizontal mirror, priority, palette (3 bits)
  output reg [15:0] planes01,
  output reg [15:0] planes23
);
  wire [8:0] vlast = overscan ? 9'd239 : 9'd224;
  wire line_on = (vcnt >= 9'd1) && (vcnt <= vlast);
  wire [8:0] pos = hdot - 9'd6;
  wire in_window = (hdot >= 9'd6) && (hdot < 9'd278);
  assign slot_start = dot_en && in_window && (pos[2:0] == 3'd0);

  wire [2:0] mode = bgmode[2:0];
  wire [2:0] layers = (mode == 3'd0) ? 3'd4 : ((mode == 3'd1) ? 3'd3 : 3'd0);

  reg busy;
  reg [1:0] layer, phase;
  reg [5:0] column;             // tile column of the line, 0 to 33
  reg [15:0] entry_q;
  reg [15:0] p01_q;
  reg [14:0] planes_addr;       // address of planes 0 and 1, for the second read

  // ---- the registers of the current layer ----
  reg [7:0] sc;
  reg [3:0] nba;
  reg [9:0] hofs, vofs;
  always @* begin
    case (layer)
      2'd0: begin sc = bg1sc; nba = bg12nba[3:0]; hofs = bg1hofs; vofs = bg1vofs; end
      2'd1: begin sc = bg2sc; nba = bg12nba[7:4]; hofs = bg2hofs; vofs = bg2vofs; end
      2'd2: begin sc = bg3sc; nba = bg34nba[3:0]; hofs = bg3hofs; vofs = bg3vofs; end
      default: begin sc = bg4sc; nba = bg34nba[7:4]; hofs = bg4hofs; vofs = bg4vofs; end
    endcase
  end
  wire big = (layer == 2'd0) ? bgmode[4] : (layer == 2'd1) ? bgmode[5] : (layer == 2'd2) ? bgmode[6] : bgmode[7];
  wire deep = (mode == 3'd1) && (layer != 2'd2);      // 4 bits for each pixel

  // ---- map address ----
  wire [9:0] px = {1'b0, column, 3'b000} + {hofs[9:3], 3'b000};
  wire [9:0] py = {1'b0, vcnt} + vofs;
  wire [6:0] tx = big ? {1'b0, px[9:4]} : px[9:3];
  wire [6:0] ty = big ? {1'b0, py[9:4]} : py[9:3];
  wire right = sc[0] && tx[5];
  wire below = sc[1] && ty[5];
  wire [14:0] base = {sc[6:2], 10'd0};                // bit 7 of $210x is outside the 32K words
  wire [14:0] screen = (right ? 15'h0400 : 15'h0000) + (below ? (sc[0] ? 15'h0800 : 15'h0400) : 15'h0000);
  wire [14:0] map_addr = base + screen + {5'd0, ty[4:0], tx[4:0]};

  // ---- tile address, from the map entry that has just arrived ----
  wire mirror_x = vdata[14];
  wire mirror_y = vdata[15];
  wire sub_x = big && (px[3] ^ mirror_x);
  wire sub_y = big && (py[3] ^ mirror_y);
  wire [9:0] tile = vdata[9:0] + {9'd0, sub_x} + {5'd0, sub_y, 4'd0};
  wire [2:0] row = mirror_y ? (3'd7 - py[2:0]) : py[2:0];
  wire [14:0] tile_offset = deep ? {1'b0, tile, 4'd0} : {2'b00, tile, 3'd0};
  wire [14:0] tile_addr = {nba[2:0], 12'd0} + tile_offset + {12'd0, row};

  always @* begin
    case (phase)
      2'd0: vaddr = map_addr;
      2'd1: vaddr = tile_addr;
      default: vaddr = planes_addr + 15'd8;
    endcase
  end

  always @(posedge clk) begin
    load <= 4'd0;
    if (rst) begin
      busy <= 1'b0; layer <= 2'd0; phase <= 2'd0; column <= 6'd0;
    end else if (slot_start && line_on) begin
      busy <= (layers != 3'd0);
      layer <= 2'd0;
      phase <= 2'd0;
      column <= pos[8:3];
    end else if (busy) begin
      phase <= phase + 2'd1;
      case (phase)
        2'd1: begin entry_q <= vdata; planes_addr <= tile_addr; end
        2'd2: p01_q <= vdata;
        2'd3: begin
          load <= 4'b0001 << layer;
          attr <= {entry_q[14], entry_q[13], entry_q[12:10]};
          planes01 <= p01_q;
          planes23 <= deep ? vdata : 16'h0000;
          layer <= layer + 2'd1;
          if ({1'b0, layer} + 3'd1 >= layers) busy <= 1'b0;
        end
        default: ;
      endcase
    end
  end
endmodule
