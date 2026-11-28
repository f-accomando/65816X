// ppu_top.v - PPU1 and PPU2: the line and frame timing (ppu_timing.v), the registers and the
// memories (ppu_regs.v), and the pixel stream with the backdrop only (ppu_math.v).
// docs/design/ppu-plan.md has the next steps.
module ppu_top (
  input clk,
  input rst,
  input mce,          // master clock enable
  input pal,
  input interlace,
  input overscan,
  input hv_gate,      // bit 7 of $4201: 1 lets $2137 latch the counters
  input [23:0] addr,
  input rd,
  input wr,
  input [7:0] wdata,
  output [7:0] rdata,
  output hit,
  output vblank,
  // pixel stream, one pulse for each visible dot (ppu_math.v)
  output pix_valid,
  output [8:0] pix_x,
  output [8:0] pix_y,
  output [14:0] pix_even,
  output [14:0] pix_odd,
  output pix_hires,
  output [3:0] bright,
  output [2:0] dbg_layer
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

  wire [7:0] inidisp;
  wire [14:0] backdrop;
  ppu_regs u_regs (
    .clk(clk), .rst(rst), .addr(addr), .rd(rd), .wr(wr), .wdata(wdata), .rdata(rdata), .hit(hit),
    .hdot(hdot), .vcnt(vcnt), .field(field), .vblank(vblank), .overscan(overscan), .pal(pal),
    .hv_gate(hv_gate), .inidisp(inidisp), .cg_raddr(8'd0), .cg_rdata(backdrop)
  );

  ppu_math u_math (
    .clk(clk), .rst(rst), .dot_en(dot_en), .hdot(hdot), .vcnt(vcnt), .overscan(overscan),
    .inidisp(inidisp), .backdrop(backdrop),
    .pix_valid(pix_valid), .pix_x(pix_x), .pix_y(pix_y), .pix_even(pix_even), .pix_odd(pix_odd),
    .pix_hires(pix_hires), .bright(bright), .dbg_layer(dbg_layer)
  );
endmodule
