// ppu_stub.v - PPU1/PPU2 ridotte: timing video, VRAM via $2115-$2119/$2139-$213A.
// Nessun rendering. Qui si innestera' la pipeline PPU+ (rasterizer, toon, compositor).
// Semplificazione: la lettura VRAM non modella il prefetch dell'originale.
module ppu_stub (
  input clk,
  input rst,
  input [23:0] addr,
  input rd,
  input wr,
  input [7:0] wdata,
  output reg [7:0] rdata,
  output hit,
  output reg vblank,
  output reg [8:0] hpos,
  output reg [8:0] vpos
);
  reg [7:0] inidisp, vmain;
  reg [15:0] vmadd;
  reg [7:0] vram_l [0:32767];
  reg [7:0] vram_h [0:32767];

  assign hit = (addr[22] == 1'b0) && (addr[15:6] == 10'h084);

  wire [15:0] vstep = (vmain[1:0] == 2'd0) ? 16'd1 : ((vmain[1:0] == 2'd1) ? 16'd32 : 16'd128);

  reg [7:0] rb;
  always @* begin
    rb = 8'h00;
    case (addr[5:0])
      6'h39: rb = vram_l[vmadd[14:0]];
      6'h3A: rb = vram_h[vmadd[14:0]];
      default: rb = 8'h00;
    endcase
  end

  always @(posedge clk) begin
    rdata <= rb;
    if (rst) begin
      inidisp <= 8'h80; vmain <= 8'h00; vmadd <= 16'd0; hpos <= 9'd0; vpos <= 9'd0; vblank <= 1'b0;
    end else begin
      if (hpos == 9'd340) begin
        hpos <= 9'd0;
        if (vpos == 9'd261) vpos <= 9'd0; else vpos <= vpos + 9'd1;
      end else hpos <= hpos + 9'd1;
      vblank <= (vpos >= 9'd225);

      if (hit && wr) begin
        case (addr[5:0])
          6'h00: inidisp <= wdata;
          6'h15: vmain <= wdata;
          6'h16: vmadd[7:0] <= wdata;
          6'h17: vmadd[15:8] <= wdata;
          6'h18: begin
            vram_l[vmadd[14:0]] <= wdata;
            if (!vmain[7]) vmadd <= vmadd + vstep;
          end
          6'h19: begin
            vram_h[vmadd[14:0]] <= wdata;
            if (vmain[7]) vmadd <= vmadd + vstep;
          end
          default: ;
        endcase
      end
      if (hit && rd) begin
        if (addr[5:0] == 6'h39 && !vmain[7]) vmadd <= vmadd + vstep;
        if (addr[5:0] == 6'h3A && vmain[7]) vmadd <= vmadd + vstep;
      end
    end
  end
endmodule
