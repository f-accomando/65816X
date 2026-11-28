// ppu_top.v - PPU1 and PPU2: the line and frame timing (ppu_timing.v), the registers and the
// memories (ppu_regs.v), the backgrounds of modes 0 and 1 (ppu_bgfetch.v, ppu_bgpix.v,
// ppu_prio.v), and the pixel stream (ppu_math.v).
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
  output [2:0] dbg_layer,
  output [2:0] dbg_sub
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

  wire [7:0] inidisp, bgmode, bg1sc, bg2sc, bg3sc, bg4sc, bg12nba, bg34nba, tm, ts;
  wire [9:0] bg1hofs, bg2hofs, bg3hofs, bg4hofs, bg1vofs, bg2vofs, bg3vofs, bg4vofs;
  wire [14:0] bg_vaddr, colour;
  wire [15:0] bg_vdata;
  wire [7:0] main_index;
  ppu_regs u_regs (
    .clk(clk), .rst(rst), .addr(addr), .rd(rd), .wr(wr), .wdata(wdata), .rdata(rdata), .hit(hit),
    .hdot(hdot), .vcnt(vcnt), .field(field), .vblank(vblank), .overscan(overscan), .pal(pal),
    .hv_gate(hv_gate), .inidisp(inidisp), .bgmode(bgmode),
    .bg1sc(bg1sc), .bg2sc(bg2sc), .bg3sc(bg3sc), .bg4sc(bg4sc), .bg12nba(bg12nba), .bg34nba(bg34nba),
    .bg1hofs(bg1hofs), .bg2hofs(bg2hofs), .bg3hofs(bg3hofs), .bg4hofs(bg4hofs),
    .bg1vofs(bg1vofs), .bg2vofs(bg2vofs), .bg3vofs(bg3vofs), .bg4vofs(bg4vofs), .tm(tm), .ts(ts),
    .bg_vaddr(bg_vaddr), .bg_vdata(bg_vdata), .cg_raddr(main_index), .cg_rdata(colour)
  );

  // ---- backgrounds ----
  wire slot_start;
  wire [3:0] load;
  wire [4:0] attr;
  wire [15:0] planes01, planes23;
  ppu_bgfetch u_bgfetch (
    .clk(clk), .rst(rst), .dot_en(dot_en), .hdot(hdot), .vcnt(vcnt), .overscan(overscan),
    .bgmode(bgmode), .bg1sc(bg1sc), .bg2sc(bg2sc), .bg3sc(bg3sc), .bg4sc(bg4sc),
    .bg12nba(bg12nba), .bg34nba(bg34nba),
    .bg1hofs(bg1hofs), .bg2hofs(bg2hofs), .bg3hofs(bg3hofs), .bg4hofs(bg4hofs),
    .bg1vofs(bg1vofs), .bg2vofs(bg2vofs), .bg3vofs(bg3vofs), .bg4vofs(bg4vofs),
    .vaddr(bg_vaddr), .vdata(bg_vdata), .slot_start(slot_start), .load(load), .attr(attr),
    .planes01(planes01), .planes23(planes23)
  );

  // one wire for each output: sim/vsim.py does not connect an output to one bit of a vector
  wire op1, op2, op3, op4, pr1, pr2, pr3, pr4;
  wire [3:0] opaque = {op4, op3, op2, op1};
  wire [3:0] pri = {pr4, pr3, pr2, pr1};
  wire [2:0] pal1, pal2, pal3, pal4;
  wire [3:0] num1, num2, num3, num4;
  ppu_bgpix u_bg1 (.clk(clk), .slot_start(slot_start), .load(load[0]), .attr(attr), .planes01(planes01),
    .planes23(planes23), .hdot(hdot), .fine(bg1hofs[2:0]), .opaque(op1), .priority_bit(pr1),
    .palette(pal1), .number(num1));
  ppu_bgpix u_bg2 (.clk(clk), .slot_start(slot_start), .load(load[1]), .attr(attr), .planes01(planes01),
    .planes23(planes23), .hdot(hdot), .fine(bg2hofs[2:0]), .opaque(op2), .priority_bit(pr2),
    .palette(pal2), .number(num2));
  ppu_bgpix u_bg3 (.clk(clk), .slot_start(slot_start), .load(load[2]), .attr(attr), .planes01(planes01),
    .planes23(planes23), .hdot(hdot), .fine(bg3hofs[2:0]), .opaque(op3), .priority_bit(pr3),
    .palette(pal3), .number(num3));
  ppu_bgpix u_bg4 (.clk(clk), .slot_start(slot_start), .load(load[3]), .attr(attr), .planes01(planes01),
    .planes23(planes23), .hdot(hdot), .fine(bg4hofs[2:0]), .opaque(op4), .priority_bit(pr4),
    .palette(pal4), .number(num4));

  wire [2:0] main_layer, sub_layer;
  wire [7:0] sub_index;       // its colour is used from step P7
  ppu_prio u_main (.mode(bgmode[2:0]), .bg3_front(bgmode[3]), .enable(tm[4:0]), .opaque(opaque), .pri(pri),
    .pal1(pal1), .pal2(pal2), .pal3(pal3), .pal4(pal4), .num1(num1), .num2(num2), .num3(num3), .num4(num4),
    .layer(main_layer), .index(main_index));
  ppu_prio u_sub (.mode(bgmode[2:0]), .bg3_front(bgmode[3]), .enable(ts[4:0]), .opaque(opaque), .pri(pri),
    .pal1(pal1), .pal2(pal2), .pal3(pal3), .pal4(pal4), .num1(num1), .num2(num2), .num3(num3), .num4(num4),
    .layer(sub_layer), .index(sub_index));

  ppu_math u_math (
    .clk(clk), .rst(rst), .dot_en(dot_en), .hdot(hdot), .vcnt(vcnt), .overscan(overscan),
    .inidisp(inidisp), .main_layer(main_layer), .sub_layer(sub_layer), .colour_in(colour),
    .pix_valid(pix_valid), .pix_x(pix_x), .pix_y(pix_y), .pix_even(pix_even), .pix_odd(pix_odd),
    .pix_hires(pix_hires), .bright(bright), .dbg_layer(dbg_layer), .dbg_sub(dbg_sub)
  );
endmodule
