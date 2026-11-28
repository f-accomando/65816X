// tb_ppu.v - the scene player of the PPU. sim/ppu_run.py starts it.
// +cmd=<file>     writes of the scene, sorted: "line dot address data" (decimal, decimal, hex, hex)
// +cgram=<file>   optional: the colour memory, loaded by the back door
// +out=<file>     the pixels of the compared frame, in the format of sim/ppu_ref.py
// +mce=0|1|2      master clock enable: each clk, each second clk, pseudo-random
// +pal=0|1 +frames=n +compare=k
// A write of (line, dot) goes on the bus after the first clk of that dot, in each frame.
`timescale 1ns/1ns
module tb_ppu;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg mce = 1'b0;
  reg pal = 1'b0;
  reg [23:0] addr = 24'h000000;
  reg rd = 1'b0;
  reg wr = 1'b0;
  reg [7:0] wdata = 8'h00;
  wire [7:0] rdata;
  wire hit, vblank;
  wire pix_valid, pix_hires;
  wire [8:0] pix_x, pix_y;
  wire [14:0] pix_even, pix_odd;
  wire [3:0] bright;
  wire [2:0] dbg_layer;

  ppu_top dut (
    .clk(clk), .rst(rst), .mce(mce), .pal(pal), .interlace(1'b0), .overscan(1'b0), .hv_gate(1'b1),
    .addr(addr), .rd(rd), .wr(wr), .wdata(wdata), .rdata(rdata), .hit(hit), .vblank(vblank),
    .pix_valid(pix_valid), .pix_x(pix_x), .pix_y(pix_y), .pix_even(pix_even), .pix_odd(pix_odd),
    .pix_hires(pix_hires), .bright(bright), .dbg_layer(dbg_layer)
  );

  always #5 clk = ~clk;

  localparam MAXW = 8192;
  integer wv [0:MAXW-1], wh [0:MAXW-1], wa [0:MAXW-1], wd [0:MAXW-1];
  integer nw, next, frame, frames, compare, mode, seed, count, x, y, f, code, v, h, a, d;
  reg [8*512-1:0] cmd_file, cgram_file, out_file;
  reg [14:0] even [0:256*239-1], odd [0:256*239-1];
  reg [3:0] br [0:256*239-1];
  reg [2:0] layer [0:256*239-1];

  // the pattern of mce
  always @(negedge clk) begin
    case (mode)
      0: mce <= 1'b1;
      1: mce <= !mce;
      default: mce <= (($random(seed) & 7) < 3);
    endcase
  end

  always @(posedge clk) begin
    if (!rst && pix_valid && frame == compare) begin
      x = pix_x;
      y = pix_y;
      even[y * 256 + x] = pix_even;
      odd[y * 256 + x] = pix_odd;
      br[y * 256 + x] = bright;
      layer[y * 256 + x] = dbg_layer;
      count = count + 1;
    end
  end

  // all writes of the position (line, dot): two writes of one dot take two clk in a row
  task play_dot;
    input integer line, dot;
    integer n;
    begin
      while (next < nw && (wv[next] < line || (wv[next] == line && wh[next] < dot))) next = next + 1;
      n = 0;
      while (next < nw && wv[next] == line && wh[next] == dot) begin
        if (n == 0) @(negedge clk);          // now the first clk of the dot is over
        addr = wa[next];
        wdata = wd[next];
        wr = 1'b1;
        next = next + 1;
        n = n + 1;
        @(negedge clk);
      end
      wr = 1'b0;
    end
  endtask

  initial begin
    mode = 0; seed = 340; frames = 2; compare = 1; count = 0; frame = 0; nw = 0; next = 0;
    if (!$value$plusargs("cmd=%s", cmd_file) || !$value$plusargs("out=%s", out_file)) begin
      $display("FAIL: +cmd and +out are necessary");
      $fatal(1);
    end
    if ($value$plusargs("mce=%d", mode)) begin end
    if ($value$plusargs("pal=%d", v)) pal = v;
    if ($value$plusargs("frames=%d", frames)) begin end
    if ($value$plusargs("compare=%d", compare)) begin end
    f = $fopen(cmd_file, "r");
    if (f == 0) begin
      $display("FAIL: cannot open the writes");
      $fatal(1);
    end
    code = $fscanf(f, "%d %d %h %h", v, h, a, d);
    while (code == 4) begin
      wv[nw] = v; wh[nw] = h; wa[nw] = a; wd[nw] = d;
      nw = nw + 1;
      code = $fscanf(f, "%d %d %h %h", v, h, a, d);
    end
    $fclose(f);
    #1;
    for (x = 0; x < 256; x = x + 1) dut.u_regs.u_cgram.mem[x] = 15'd0;
    if ($value$plusargs("cgram=%s", cgram_file)) $readmemh(cgram_file, dut.u_regs.u_cgram.mem);
    repeat (4) @(negedge clk);
    rst = 1'b0;
    // after the reset the position is line 0, dot 0, without a dot_en pulse
    play_dot(0, 0);
    while (frame < frames) begin
      @(negedge clk);
      if (dut.u_timing.dot_en) begin
        v = dut.u_timing.vcnt;
        h = dut.u_timing.hdot;
        if (v == 0 && h == 0) begin
          frame = frame + 1;
          next = 0;
        end
        if (frame < frames) play_dot(v, h);
      end
    end
    if (count != 256 * 224) begin
      $display("FAIL: %0d pixels in the compared frame, expected %0d", count, 256 * 224);
      $fatal(1);
    end
    f = $fopen(out_file, "w");
    for (y = 0; y < 224; y = y + 1) begin
      for (x = 0; x < 256; x = x + 1) begin
        if (x != 0) $fwrite(f, " ");
        $fwrite(f, "%b:%h:%0d %b:%h:%0d", even[y*256+x], br[y*256+x], layer[y*256+x],
                odd[y*256+x], br[y*256+x], layer[y*256+x]);
      end
      $fwrite(f, "\n");
    end
    $fclose(f);
    $finish;
  end
endmodule
