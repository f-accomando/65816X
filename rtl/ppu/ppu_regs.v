// ppu_regs.v - the bus side of the PPU: the registers $2100 to $213F, their latches, the counter
// latch, the product $2134-$2136, the two data latches of the open bus (MDR), and the access to
// the video, colour, and sprite memories.
// Bus: a write or a read acts in the clk with its strobe; rdata is valid one clk later.
// Two accesses are at least 2 clk apart (one cycle of the processor).
// Blank period: forced blank or vertical blank. Outside it, a VRAM write is lost and the VRAM
// buffer keeps its value, as on the real chip. An OAM write is lost too (approximation). A colour
// memory write is accepted at any time (approximation).
// The effects of most registers come with the steps P4 to P10 (docs/design/ppu-plan.md).
module ppu_regs (
  input clk,
  input rst,
  input [23:0] addr,
  input rd,
  input wr,
  input [7:0] wdata,
  output reg [7:0] rdata,
  output hit,
  // position, from the timing unit
  input [8:0] hdot,
  input [8:0] vcnt,
  input field,
  input vblank,
  input overscan,
  input pal,
  input hv_gate,             // bit 7 of $4201: 1 lets $2137 latch the counters
  // render side
  output reg [7:0] inidisp,
  input [7:0] cg_raddr,
  output [14:0] cg_rdata
);
  assign hit = (addr[22] == 1'b0) && (addr[15:6] == 10'h084);
  wire [5:0] a = addr[5:0];
  wire w = hit && wr;
  wire r = hit && rd;
  wire blank = inidisp[7] || vblank;

  // ---- registers ----
  reg [7:0] obsel, bgmode, mosaic, bg1sc, bg2sc, bg3sc, bg4sc, bg12nba, bg34nba, m7sel, vmain;
  reg [7:0] w12sel, w34sel, wobjsel, wh0, wh1, wh2, wh3, wbglog, wobjlog, tm, ts, tmw, tsw;
  reg [7:0] cgwsel, cgadsub, setini;
  reg [4:0] col_r, col_g, col_b;
  reg [9:0] bg1hofs, bg2hofs, bg3hofs, bg4hofs, bg1vofs, bg2vofs, bg3vofs, bg4vofs;
  reg [12:0] m7hofs, m7vofs, m7x, m7y;
  reg [15:0] m7a, m7b, m7c, m7d;
  reg [15:0] vmadd;
  reg [8:0] oam_reload;
  reg [9:0] oam_addr;
  reg oam_prio;

  // ---- latches ----
  reg [7:0] bgofs_latch, bghofs_latch, m7_latch, oam_latch, mul_b;
  reg [8:0] ophct, opvct;
  reg ophct_byte, opvct_byte, latched, vblank_q;
  reg [7:0] mdr1, mdr2;

  // ---- video memory ----
  wire w_vaddr = w && ((a == 6'h16) || (a == 6'h17));
  wire w_vlow = w && (a == 6'h18);
  wire w_vhigh = w && (a == 6'h19);
  wire r_vstep = r && (((a == 6'h39) && !vmain[7]) || ((a == 6'h3A) && vmain[7]));
  wire w_vstep = (w_vlow && !vmain[7]) || (w_vhigh && vmain[7]);
  wire [15:0] vmadd_new = (a == 6'h16) ? {vmadd[15:8], wdata} : {wdata, vmadd[7:0]};
  wire [15:0] vsel = w_vaddr ? vmadd_new : vmadd;      // a write of the address loads the new one
  wire [15:0] vstep = (vmain[1:0] == 2'd0) ? 16'd1 : ((vmain[1:0] == 2'd1) ? 16'd32 : 16'd128);

  reg [14:0] vaddr;
  always @* begin
    case (vmain[3:2])
      2'd0: vaddr = vsel[14:0];
      2'd1: vaddr = {vsel[14:8], vsel[4:0], vsel[7:5]};
      2'd2: vaddr = {vsel[14:9], vsel[5:0], vsel[8:6]};
      default: vaddr = {vsel[14:10], vsel[6:0], vsel[9:7]};
    endcase
  end

  wire [7:0] vq_l, vq_h;
  ppu_vram u_vram (
    .clk(clk), .addr(vaddr), .we_l(w_vlow && blank), .we_h(w_vhigh && blank), .wdata(wdata),
    .load((w_vaddr || r_vstep) && blank), .q_l(vq_l), .q_h(vq_h)
  );

  // ---- colour memory ----
  wire [14:0] cg_q;
  wire [7:0] cg_addr;
  wire cg_half;
  ppu_cgram u_cgram (
    .clk(clk), .rst(rst), .wr_addr(w && (a == 6'h21)), .wr_data(w && (a == 6'h22)),
    .rd_data(r && (a == 6'h3B)), .wdata(wdata), .cgadd(cg_addr), .half(cg_half), .qdata(cg_q),
    .raddr(cg_raddr), .rdata(cg_rdata)
  );

  // ---- sprite memory ----
  wire w_oam = w && (a == 6'h04);
  wire [7:0] oam_q;
  ppu_oam u_oam (
    .clk(clk), .addr(oam_addr), .we_word(w_oam && blank && !oam_addr[9] && oam_addr[0]),
    .we_high(w_oam && blank && oam_addr[9]),
    .wdata(oam_addr[9] ? {8'h00, wdata} : {wdata, oam_latch}), .rdata(oam_q)
  );

  // the reload at the start of the vertical blank, or when $2100 is written on its first line
  // while the forced blank is on
  wire [8:0] vfirst = overscan ? 9'd240 : 9'd225;
  wire oam_restart = (vblank && !vblank_q && !inidisp[7]) ||
                     (w && (a == 6'h00) && (vcnt == vfirst) && inidisp[7]);

  // ---- product: signed 16 bits x signed 8 bits, from one unsigned multiplier ----
  wire [23:0] uprod = {8'h00, m7a} * {16'h0000, mul_b};
  wire [23:0] fix_a = m7a[15] ? {mul_b, 16'h0000} : 24'h000000;
  wire [23:0] fix_b = mul_b[7] ? {m7a, 8'h00} : 24'h000000;
  wire [23:0] product = uprod - fix_a - fix_b;

  // ---- read data ----
  wire mdr1_back = (a[5:4] != 2'd3) &&
                   ((a[3:0] == 4'h4) || (a[3:0] == 4'h5) || (a[3:0] == 4'h6) ||
                    (a[3:0] == 4'h8) || (a[3:0] == 4'h9) || (a[3:0] == 4'hA));
  reg [7:0] rb;
  reg from1, from2;          // the value goes into the data latch of the PPU1 or of the PPU2
  always @* begin
    rb = 8'h00;
    from1 = 1'b0;
    from2 = 1'b0;
    case (a)
      6'h34: begin rb = product[7:0]; from1 = 1'b1; end
      6'h35: begin rb = product[15:8]; from1 = 1'b1; end
      6'h36: begin rb = product[23:16]; from1 = 1'b1; end
      6'h38: begin rb = oam_q; from1 = 1'b1; end
      6'h39: begin rb = vq_l; from1 = 1'b1; end
      6'h3A: begin rb = vq_h; from1 = 1'b1; end
      6'h3B: begin rb = cg_half ? {mdr2[7], cg_q[14:8]} : cg_q[7:0]; from2 = 1'b1; end
      6'h3C: begin rb = ophct_byte ? {mdr2[7:1], ophct[8]} : ophct[7:0]; from2 = 1'b1; end
      6'h3D: begin rb = opvct_byte ? {mdr2[7:1], opvct[8]} : opvct[7:0]; from2 = 1'b1; end
      6'h3E: begin rb = {3'b000, mdr1[4], 4'd1}; from1 = 1'b1; end   // flags: step P6
      6'h3F: begin rb = {field, latched, mdr2[5], pal, 4'd3}; from2 = 1'b1; end
      default: rb = mdr1_back ? mdr1 : 8'h00;
    endcase
  end

  always @(posedge clk) begin
    rdata <= rb;
    vblank_q <= vblank;
    if (rst) begin
      inidisp <= 8'h80; obsel <= 8'd0; bgmode <= 8'd0; mosaic <= 8'd0;
      bg1sc <= 8'd0; bg2sc <= 8'd0; bg3sc <= 8'd0; bg4sc <= 8'd0; bg12nba <= 8'd0; bg34nba <= 8'd0;
      m7sel <= 8'd0; vmain <= 8'd0; w12sel <= 8'd0; w34sel <= 8'd0; wobjsel <= 8'd0;
      wh0 <= 8'd0; wh1 <= 8'd0; wh2 <= 8'd0; wh3 <= 8'd0; wbglog <= 8'd0; wobjlog <= 8'd0;
      tm <= 8'd0; ts <= 8'd0; tmw <= 8'd0; tsw <= 8'd0; cgwsel <= 8'd0; cgadsub <= 8'd0;
      setini <= 8'd0; col_r <= 5'd0; col_g <= 5'd0; col_b <= 5'd0;
      bg1hofs <= 10'd0; bg2hofs <= 10'd0; bg3hofs <= 10'd0; bg4hofs <= 10'd0;
      bg1vofs <= 10'd0; bg2vofs <= 10'd0; bg3vofs <= 10'd0; bg4vofs <= 10'd0;
      m7hofs <= 13'd0; m7vofs <= 13'd0; m7x <= 13'd0; m7y <= 13'd0;
      m7a <= 16'hFFFF; m7b <= 16'd0; m7c <= 16'd0; m7d <= 16'd0; mul_b <= 8'hFF;
      vmadd <= 16'd0; oam_reload <= 9'd0; oam_addr <= 10'd0; oam_prio <= 1'b0;
      bgofs_latch <= 8'd0; bghofs_latch <= 8'd0; m7_latch <= 8'd0; oam_latch <= 8'd0;
      ophct <= 9'h1FF; opvct <= 9'h1FF; ophct_byte <= 1'b0; opvct_byte <= 1'b0; latched <= 1'b0;
      mdr1 <= 8'd0; mdr2 <= 8'd0;
    end else begin
      if (w) begin
        case (a)
          6'h00: inidisp <= wdata;
          6'h01: obsel <= wdata;
          6'h02: begin oam_reload[7:0] <= wdata; oam_addr <= {oam_reload[8], wdata, 1'b0}; end
          6'h03: begin
            oam_reload[8] <= wdata[0];
            oam_prio <= wdata[7];
            oam_addr <= {wdata[0], oam_reload[7:0], 1'b0};
          end
          6'h04: begin
            if (!oam_addr[0]) oam_latch <= wdata;
            oam_addr <= oam_addr + 10'd1;
          end
          6'h05: bgmode <= wdata;
          6'h06: mosaic <= wdata;
          6'h07: bg1sc <= wdata;
          6'h08: bg2sc <= wdata;
          6'h09: bg3sc <= wdata;
          6'h0A: bg4sc <= wdata;
          6'h0B: bg12nba <= wdata;
          6'h0C: bg34nba <= wdata;
          6'h0D: begin
            bg1hofs <= {wdata[1:0], bgofs_latch[7:3], bghofs_latch[2:0]};
            bgofs_latch <= wdata; bghofs_latch <= wdata;
            m7hofs <= {wdata[4:0], m7_latch}; m7_latch <= wdata;
          end
          6'h0E: begin
            bg1vofs <= {wdata[1:0], bgofs_latch}; bgofs_latch <= wdata;
            m7vofs <= {wdata[4:0], m7_latch}; m7_latch <= wdata;
          end
          6'h0F: begin
            bg2hofs <= {wdata[1:0], bgofs_latch[7:3], bghofs_latch[2:0]};
            bgofs_latch <= wdata; bghofs_latch <= wdata;
          end
          6'h10: begin bg2vofs <= {wdata[1:0], bgofs_latch}; bgofs_latch <= wdata; end
          6'h11: begin
            bg3hofs <= {wdata[1:0], bgofs_latch[7:3], bghofs_latch[2:0]};
            bgofs_latch <= wdata; bghofs_latch <= wdata;
          end
          6'h12: begin bg3vofs <= {wdata[1:0], bgofs_latch}; bgofs_latch <= wdata; end
          6'h13: begin
            bg4hofs <= {wdata[1:0], bgofs_latch[7:3], bghofs_latch[2:0]};
            bgofs_latch <= wdata; bghofs_latch <= wdata;
          end
          6'h14: begin bg4vofs <= {wdata[1:0], bgofs_latch}; bgofs_latch <= wdata; end
          6'h15: vmain <= wdata;
          6'h16, 6'h17: vmadd <= vmadd_new;
          6'h1A: m7sel <= wdata;
          6'h1B: begin m7a <= {wdata, m7_latch}; m7_latch <= wdata; end
          6'h1C: begin m7b <= {wdata, m7_latch}; m7_latch <= wdata; mul_b <= wdata; end
          6'h1D: begin m7c <= {wdata, m7_latch}; m7_latch <= wdata; end
          6'h1E: begin m7d <= {wdata, m7_latch}; m7_latch <= wdata; end
          6'h1F: begin m7x <= {wdata[4:0], m7_latch}; m7_latch <= wdata; end
          6'h20: begin m7y <= {wdata[4:0], m7_latch}; m7_latch <= wdata; end
          6'h23: w12sel <= wdata;
          6'h24: w34sel <= wdata;
          6'h25: wobjsel <= wdata;
          6'h26: wh0 <= wdata;
          6'h27: wh1 <= wdata;
          6'h28: wh2 <= wdata;
          6'h29: wh3 <= wdata;
          6'h2A: wbglog <= wdata;
          6'h2B: wobjlog <= wdata;
          6'h2C: tm <= wdata;
          6'h2D: ts <= wdata;
          6'h2E: tmw <= wdata;
          6'h2F: tsw <= wdata;
          6'h30: cgwsel <= wdata;
          6'h31: cgadsub <= wdata;
          6'h32: begin
            if (wdata[5]) col_r <= wdata[4:0];
            if (wdata[6]) col_g <= wdata[4:0];
            if (wdata[7]) col_b <= wdata[4:0];
          end
          6'h33: setini <= wdata;
          default: ;
        endcase
      end
      if (w_vstep || r_vstep) vmadd <= vmadd + vstep;
      if (r) begin
        if (from1) mdr1 <= rb;
        if (from2) mdr2 <= rb;
        case (a)
          6'h37: if (hv_gate) begin ophct <= hdot; opvct <= vcnt; latched <= 1'b1; end
          6'h38: oam_addr <= oam_addr + 10'd1;
          6'h3C: ophct_byte <= !ophct_byte;
          6'h3D: opvct_byte <= !opvct_byte;
          6'h3F: begin
            if (hv_gate) latched <= 1'b0;
            ophct_byte <= 1'b0;
            opvct_byte <= 1'b0;
          end
          default: ;
        endcase
      end
      if (oam_restart) oam_addr <= {oam_reload, 1'b0};
    end
  end
endmodule
