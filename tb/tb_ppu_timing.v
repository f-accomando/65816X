// tb_ppu_timing.v - the video timing against a second description of it, in this file.
// The bench counts only master clocks (clk with mce = 1) and compares each output in each clk.
// It runs NTSC and PAL, without and with interlace, over 4 frames, with three patterns of mce.
// At the end of each run it also compares the totals with numbers written by hand.
`timescale 1ns/1ns
module tb_ppu_timing;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg mce = 1'b0;
  reg pal = 1'b0;
  reg interlace = 1'b0;
  reg overscan = 1'b0;
  wire [10:0] hclk;
  wire [8:0] hdot, vcnt;
  wire field, dot_en, hblank, vblank, frame_start;

  ppu_timing dut (
    .clk(clk), .rst(rst), .mce(mce), .pal(pal), .interlace(interlace), .overscan(overscan),
    .hclk(hclk), .hdot(hdot), .vcnt(vcnt), .field(field), .dot_en(dot_en),
    .hblank(hblank), .vblank(vblank), .frame_start(frame_start)
  );

  always #5 clk = ~clk;

  integer fails, seed;
  integer pattern, step, ones;                        // the pattern of mce
  integer x_dot, x_line, x_field, dclk, lclk;         // expected position
  integer frames, lines, total, shorts, longs, rises, falls;
  reg x_dot_en, x_frame_start, vb_q;

  task bad;
    input [127:0] what;
    begin
      fails = fails + 1;
      $display("FAIL %0s: pal=%b il=%b ov=%b pattern=%0d frame=%0d line=%0d dot=%0d (dut line=%0d dot=%0d hclk=%0d field=%b)",
               what, pal, interlace, overscan, pattern, frames, x_line, x_dot, vcnt, hdot, hclk, field);
      if (fails >= 5) $fatal(1);
    end
  endtask

  // The value of mce for the next clk.
  task next_mce;
    begin
      case (pattern)
        0: mce = 1'b1;                                // each clk
        1: mce = !mce;                                // each second clk
        default: begin                                // 3 in each group of 7, pseudo-random places
          if (step == 7) begin
            step = 0;
            ones = 3;
          end
          mce = (({$random(seed)} % (7 - step)) < ones);
          if (mce) ones = ones - 1;
          step = step + 1;
        end
      endcase
    end
  endtask

  task restart;
    begin
      @(negedge clk);
      rst = 1'b1;
      mce = 1'b0;
      step = 0;
      ones = 3;
      repeat (3) @(negedge clk);
      rst = 1'b0;
      x_dot = 0; x_line = 0; x_field = 1; dclk = 0; lclk = 0;
      frames = 0; lines = 0; total = 0; shorts = 0; longs = 0; rises = 0; falls = 0;
      vb_q = 1'b0;
    end
  endtask

  // One master clock of the expected timing.
  task advance;
    reg is_short, is_long;
    integer dlen, last_dot, last_line, llen;
    begin
      total = total + 1;
      dclk = dclk + 1;
      lclk = lclk + 1;
      is_short = (pal == 0) && (interlace == 0) && (x_field == 1) && (x_line == 240);
      is_long = (pal == 1) && (interlace == 1) && (x_field == 1) && (x_line == 311);
      dlen = (((x_dot == 323) || (x_dot == 327)) && !is_short) ? 6 : 4;
      if (dclk == dlen) begin
        dclk = 0;
        x_dot_en = 1'b1;
        if (x_dot == 0 && x_line == 0) x_field = 1 - x_field;
        last_dot = is_long ? 340 : 339;
        if (x_dot == last_dot) begin
          llen = is_long ? 1368 : (is_short ? 1360 : 1364);
          if (lclk != llen) bad("line length");
          if (is_short) shorts = shorts + 1;
          if (is_long) longs = longs + 1;
          lclk = 0;
          x_dot = 0;
          lines = lines + 1;
          last_line = (pal ? 312 : 262) - 1;
          if (interlace && x_field == 0) last_line = last_line + 1;
          if (x_line == last_line) begin
            x_line = 0;
            frames = frames + 1;
            x_frame_start = 1'b1;
          end else x_line = x_line + 1;
        end else x_dot = x_dot + 1;
      end
    end
  endtask

  task cycle;
    begin
      @(negedge clk);
      next_mce;
      @(posedge clk);
      #1;
      x_dot_en = 1'b0;
      x_frame_start = 1'b0;
      if (mce) advance;
      if (hdot !== x_dot) bad("hdot");
      if (vcnt !== x_line) bad("vcnt");
      if (hclk !== lclk) bad("hclk");
      if (field !== x_field[0]) bad("field");
      if (dot_en !== x_dot_en) bad("dot_en");
      if (frame_start !== x_frame_start) bad("frame_start");
      if (vblank !== (x_line >= (overscan ? 240 : 225))) bad("vblank");
      if (hblank !== (x_dot >= 274 || x_dot == 0)) bad("hblank");
      if (vblank && !vb_q) begin
        rises = rises + 1;
        if (vcnt !== (overscan ? 9'd240 : 9'd225) || hdot !== 9'd0) bad("vblank rise");
      end
      if (!vblank && vb_q) begin
        falls = falls + 1;
        if (vcnt !== 9'd0 || hdot !== 9'd0) bad("vblank fall");
      end
      vb_q = vblank;
    end
  endtask

  task run;
    input p, il, ov;
    input integer pat, nframes, w_total, w_lines, w_shorts, w_longs;
    begin
      pal = p; interlace = il; overscan = ov; pattern = pat;
      restart;
      while (frames < nframes && total <= w_total) cycle;
      if (frames != nframes || total != w_total) bad("master clocks");
      if (lines != w_lines) bad("lines");
      if (shorts != w_shorts) bad("short lines");
      if (longs != w_longs) bad("long lines");
      if (rises != nframes || falls != nframes) bad("vblank count");
      $display("  pal=%b il=%b ov=%b pattern=%0d: %0d lines, %0d master clocks", p, il, ov, pat, lines, total);
    end
  endtask

  integer pat, n, since;

  initial begin
    fails = 0;
    seed = 5822;
    for (pat = 0; pat < 3; pat = pat + 1) begin
      //   pal   il    ov   pat  frames  clocks   lines short long
      run(1'b0, 1'b0, 1'b0, pat, 4, 1429464, 1048, 2, 0);   // 4 x 262 x 1364 - 2 x 4
      run(1'b0, 1'b1, 1'b0, pat, 4, 1432200, 1050, 0, 0);   // (263 + 262) x 2 x 1364
      run(1'b1, 1'b0, 1'b0, pat, 4, 1702272, 1248, 0, 0);   // 4 x 312 x 1364
      run(1'b1, 1'b1, 1'b0, pat, 4, 1705008, 1250, 0, 2);   // (313 + 312) x 2 x 1364 + 2 x 4
    end
    // overscan: the vertical blank starts at line 240
    run(1'b0, 1'b0, 1'b1, 0, 2, 714732, 524, 1, 0);
    run(1'b1, 1'b0, 1'b1, 2, 2, 851136, 624, 0, 0);

    // a reset in the middle of a frame
    pal = 1'b0; interlace = 1'b0; overscan = 1'b0; pattern = 0;
    restart;
    for (n = 0; n < 320000; n = n + 1) cycle;
    restart;
    if (hdot !== 9'd0 || vcnt !== 9'd0 || hclk !== 11'd0 || vblank !== 1'b0) bad("reset");
    for (n = 0; n < 3000; n = n + 1) cycle;

    // the inputs change at any time: no counter leaves its range, and frames go on
    restart;
    since = 0;
    for (n = 0; n < 3000000; n = n + 1) begin
      @(negedge clk);
      mce = 1'b1;
      if (({$random(seed)} % 20000) == 0) {pal, interlace, overscan} = $random(seed);
      @(posedge clk);
      #1;
      since = frame_start ? 0 : since + 1;
      if (hdot > 9'd340 || vcnt > 9'd312 || hclk > 11'd1367) bad("range");
      if (vcnt == 9'd0 && vblank !== 1'b0) bad("vblank line 0");
      if (since > 314 * 1368) bad("no new frame");
    end

    if (fails != 0) $fatal(1);
    $display("PPU timing: PASS");
    $finish;
  end
endmodule
