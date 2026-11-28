// ppu_top.v - PPU1 and PPU2. Today: the line and frame timing (ppu_timing.v) and the VRAM
// through $2115-$2119 and $2139-$213A. No picture yet: docs/design/ppu-plan.md has the steps.
// Simplifications: a VRAM read has no prefetch, and a write is accepted at any time.
module ppu_top (
  input clk,
  input rst,
  input mce,          // master clock enable
  input pal,
  input interlace,
  input overscan,
  input [23:0] addr,
  input rd,
  input wr,
  input [7:0] wdata,
  output reg [7:0] rdata,
  output hit,
  output vblank
);
  // The other outputs get their readers with the next steps (counters, H/V IRQ, HDMA).
  wire [10:0] hclk;
  wire [8:0] hdot, vcnt;
  wire field, dot_en, hblank, frame_start;

  ppu_timing u_timing (
    .clk(clk), .rst(rst), .mce(mce), .pal(pal), .interlace(interlace), .overscan(overscan),
    .hclk(hclk), .hdot(hdot), .vcnt(vcnt), .field(field), .dot_en(dot_en),
    .hblank(hblank), .vblank(vblank), .frame_start(frame_start)
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
      inidisp <= 8'h80; vmain <= 8'h00; vmadd <= 16'd0;
    end else begin
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
