// snes_plus_top.v - sistema completo sul modello a piu' chip dell'SNES originale:
// 5A22 (core + DMA), PPU, APU, WRAM, cartuccia, piu' i registri enhanced.
module snes_plus_top (
  input clk,
  input rst,
  output [15:0] dbg_pc,
  output [15:0] dbg_a,
  output [15:0] dbg_x,
  output [15:0] dbg_y,
  output dbg_vblank,
  output dbg_illegal
);
  wire [23:0] bus_addr;
  wire bus_rd, bus_wr;
  wire [7:0] bus_wdata, bus_rdata;
  wire hit_rom, hit_wram, hit_ppu, hit_apu, hit_cpu, hit_ext;
  wire [7:0] rd_rom, rd_wram, rd_ppu, rd_apu, rd_cpu, rd_ext;
  wire [7:0] ext_mode, ext_speed;
  wire ext_enhanced;
  wire vblank;

  s_cpu_5a22 u_cpu (
    .clk(clk), .rst(rst), .ext_en(ext_enhanced),
    .bus_addr(bus_addr), .bus_rd(bus_rd), .bus_wr(bus_wr), .bus_wdata(bus_wdata),
    .bus_rdata(bus_rdata), .vblank(vblank),
    .regs_rdata(rd_cpu), .regs_hit(hit_cpu),
    .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_x(dbg_x), .dbg_y(dbg_y), .dbg_illegal(dbg_illegal)
  );
  cart_rom u_rom (.clk(clk), .rst(rst), .addr(bus_addr), .rd(bus_rd), .wr(bus_wr), .wdata(bus_wdata), .rdata(rd_rom), .hit(hit_rom));
  wram u_wram (.clk(clk), .rst(rst), .addr(bus_addr), .rd(bus_rd), .wr(bus_wr), .wdata(bus_wdata), .rdata(rd_wram), .hit(hit_wram));
  // NTSC, no interlace, no overscan. In simulation one clk is one master clock (mce = 1).
  ppu_top u_ppu (.clk(clk), .rst(rst), .mce(1'b1), .pal(1'b0), .interlace(1'b0), .overscan(1'b0), .hv_gate(1'b1),
    .addr(bus_addr), .rd(bus_rd), .wr(bus_wr), .wdata(bus_wdata), .rdata(rd_ppu), .hit(hit_ppu), .vblank(vblank));
  apu_stub u_apu (.clk(clk), .rst(rst), .addr(bus_addr), .rd(bus_rd), .wr(bus_wr), .wdata(bus_wdata), .rdata(rd_apu), .hit(hit_apu));
  ext_regs u_ext (.clk(clk), .rst(rst), .addr(bus_addr), .rd(bus_rd), .wr(bus_wr), .wdata(bus_wdata), .rdata(rd_ext), .hit(hit_ext), .mode(ext_mode), .speed(ext_speed), .enhanced(ext_enhanced));

  reg q_rom, q_wram, q_ppu, q_apu, q_cpu, q_ext;
  always @(posedge clk) begin
    q_rom <= hit_rom; q_wram <= hit_wram; q_ppu <= hit_ppu;
    q_apu <= hit_apu; q_cpu <= hit_cpu; q_ext <= hit_ext;
  end

  assign bus_rdata = (rd_rom & {8{q_rom}}) | (rd_wram & {8{q_wram}}) | (rd_ppu & {8{q_ppu}})
                   | (rd_apu & {8{q_apu}}) | (rd_cpu & {8{q_cpu}}) | (rd_ext & {8{q_ext}});
  assign dbg_vblank = vblank;
endmodule
