// tb_ppu_regs.v - plays the register accesses of sim/ppu_ref.py (--regs) on ppu_regs and compares
// each read, the internal registers, and at the end the memories. sim/ppu_regs_run.py starts it.
// The position (line, dot, field, region) comes from the commands, not from a timing unit.
// The accesses are as close as the processor can make them: one clk of strobe, one clk without.
`timescale 1ns/1ns
module tb_ppu_regs;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg [23:0] addr = 24'h000000;
  reg rd = 1'b0;
  reg wr = 1'b0;
  reg [7:0] wdata = 8'h00;
  reg [8:0] hdot = 9'd0, vcnt = 9'd0;
  reg field = 1'b0, pal = 1'b0;
  wire vblank = (vcnt >= 9'd225);
  wire [7:0] rdata, inidisp;
  wire hit;
  wire [14:0] cg_rdata;

  ppu_regs dut (
    .clk(clk), .rst(rst), .addr(addr), .rd(rd), .wr(wr), .wdata(wdata), .rdata(rdata), .hit(hit),
    .hdot(hdot), .vcnt(vcnt), .field(field), .vblank(vblank), .overscan(1'b0), .pal(pal),
    .hv_gate(1'b1), .inidisp(inidisp), .cg_raddr(8'd0), .cg_rdata(cg_rdata)
  );

  always #5 clk = ~clk;

  integer f, code, i, fails, lines, reads, writes, checks, words;
  integer p0, p1, p2, p3;
  reg [7:0] op;
  reg [8*256-1:0] cmd_file;
  reg [31:0] got;

  // the internal register of each number: the order of REGISTERS in sim/ppu_ref.py
  function [31:0] reg_value;
    input integer n;
    case (n)
      0: reg_value = dut.inidisp;      1: reg_value = dut.obsel;        2: reg_value = dut.oam_reload;
      3: reg_value = dut.oam_prio;     4: reg_value = dut.bgmode;       5: reg_value = dut.mosaic;
      6: reg_value = dut.bg1sc;        7: reg_value = dut.bg2sc;        8: reg_value = dut.bg3sc;
      9: reg_value = dut.bg4sc;        10: reg_value = dut.bg12nba;     11: reg_value = dut.bg34nba;
      12: reg_value = dut.bg1hofs;     13: reg_value = dut.bg2hofs;     14: reg_value = dut.bg3hofs;
      15: reg_value = dut.bg4hofs;     16: reg_value = dut.bg1vofs;     17: reg_value = dut.bg2vofs;
      18: reg_value = dut.bg3vofs;     19: reg_value = dut.bg4vofs;     20: reg_value = dut.m7hofs;
      21: reg_value = dut.m7vofs;      22: reg_value = dut.vmain;       23: reg_value = dut.vmadd;
      24: reg_value = dut.m7sel;       25: reg_value = dut.m7a;         26: reg_value = dut.m7b;
      27: reg_value = dut.m7c;         28: reg_value = dut.m7d;         29: reg_value = dut.m7x;
      30: reg_value = dut.m7y;         31: reg_value = dut.w12sel;      32: reg_value = dut.w34sel;
      33: reg_value = dut.wobjsel;     34: reg_value = dut.wh0;         35: reg_value = dut.wh1;
      36: reg_value = dut.wh2;         37: reg_value = dut.wh3;         38: reg_value = dut.wbglog;
      39: reg_value = dut.wobjlog;     40: reg_value = dut.tm;          41: reg_value = dut.ts;
      42: reg_value = dut.tmw;         43: reg_value = dut.tsw;         44: reg_value = dut.cgwsel;
      45: reg_value = dut.cgadsub;     46: reg_value = dut.col_r;       47: reg_value = dut.col_g;
      48: reg_value = dut.col_b;       49: reg_value = dut.setini;      50: reg_value = dut.oam_addr;
      51: reg_value = dut.u_cgram.cgadd;
      default: reg_value = 32'hxxxxxxxx;
    endcase
  endfunction

  task bad;
    input [127:0] what;
    input [31:0] value, want;
    begin
      fails = fails + 1;
      $display("FAIL command %0d, %0s %h: %h, expected %h", lines, what, p0, value, want);
      if (fails >= 5) $fatal(1);
    end
  endtask

  initial begin
    fails = 0; lines = 0; reads = 0; writes = 0; checks = 0; words = 0;
    if (!$value$plusargs("cmd=%s", cmd_file)) begin
      $display("FAIL: +cmd is necessary");
      $fatal(1);
    end
    f = $fopen(cmd_file, "r");
    if (f == 0) begin
      $display("FAIL: cannot open the commands");
      $fatal(1);
    end
    #1;
    for (i = 0; i < 32768; i = i + 1) begin
      dut.u_vram.vram_l[i] = 8'h00;
      dut.u_vram.vram_h[i] = 8'h00;
    end
    for (i = 0; i < 256; i = i + 1) begin
      dut.u_cgram.mem[i] = 15'd0;
      dut.u_oam.low[i] = 16'd0;
    end
    for (i = 0; i < 32; i = i + 1) dut.u_oam.high[i] = 8'h00;
    dut.u_vram.q_l = 8'h00;
    dut.u_vram.q_h = 8'h00;
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);
    code = $fscanf(f, " %c", op);
    while (code == 1) begin
      lines = lines + 1;
      case (op)
        "P": begin
          code = $fscanf(f, "%h %h %h %h", p0, p1, p2, p3);
          vcnt = p0; hdot = p1; field = p2; pal = p3;
          repeat (2) @(negedge clk);
        end
        "W": begin
          code = $fscanf(f, "%h %h", p0, p1);
          addr = p0; wdata = p1; wr = 1'b1;
          @(negedge clk) wr = 1'b0;
          @(negedge clk);
          writes = writes + 1;
        end
        "R": begin
          code = $fscanf(f, "%h %h", p0, p1);
          addr = p0; rd = 1'b1;
          @(negedge clk) rd = 1'b0;
          if (rdata !== p1[7:0]) bad("read", rdata, p1);
          @(negedge clk);
          reads = reads + 1;
        end
        "C": begin
          code = $fscanf(f, "%h %h", p0, p1);
          got = reg_value(p0);
          if (got !== p1) bad("register", got, p1);
          checks = checks + 1;
        end
        "V": begin
          code = $fscanf(f, "%h %h", p0, p1);
          got = {dut.u_vram.vram_h[p0], dut.u_vram.vram_l[p0]};
          if (got !== p1) bad("VRAM word", got, p1);
          words = words + 1;
        end
        "G": begin
          code = $fscanf(f, "%h %h", p0, p1);
          got = dut.u_cgram.mem[p0];
          if (got !== p1) bad("CGRAM word", got, p1);
          words = words + 1;
        end
        "O": begin
          code = $fscanf(f, "%h %h", p0, p1);
          if (p0 >= 512) got = dut.u_oam.high[p0 - 512];
          else got = p0[0] ? dut.u_oam.low[p0 / 2][15:8] : dut.u_oam.low[p0 / 2][7:0];
          if (got !== p1) bad("OAM byte", got, p1);
          words = words + 1;
        end
        default: begin
          $display("FAIL: unknown command %c", op);
          $fatal(1);
        end
      endcase
      code = $fscanf(f, " %c", op);
    end
    $fclose(f);
    if (reads + writes < 10000) begin
      $display("FAIL: only %0d accesses", reads + writes);
      $fatal(1);
    end
    if (fails != 0) $fatal(1);
    $display("%0d reads, %0d writes, %0d register checks, %0d memory checks: 0 differences",
             reads, writes, checks, words);
    $finish;
  end
endmodule
