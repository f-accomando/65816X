// tb_c816_ext.v - the WDM unit against the signed and unsigned arithmetic of the simulator:
// random and corner operands for each sub-opcode. A difference ends with $fatal.
`timescale 1ns/1ns
module tb_c816_ext;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg go = 1'b0;
  reg start = 1'b0;
  reg [7:0] sub = 8'h00;
  reg [15:0] a = 16'h0000;
  reg [15:0] x = 16'h0000;
  reg [15:0] y = 16'h0000;
  wire we_a, we_y, f_we, f_n, f_z, fv_we, f_v, busy;
  wire [15:0] a_out, y_out;

  c816_ext dut (
    .clk(clk), .rst(rst), .go(go), .start(start), .sub(sub), .a(a), .x(x), .y(y),
    .we_a(we_a), .we_y(we_y), .a_out(a_out), .y_out(y_out),
    .f_we(f_we), .f_n(f_n), .f_z(f_z), .fv_we(fv_we), .f_v(f_v), .busy(busy)
  );

  always #5 clk = ~clk;

  integer n, seed, fails, clocks, k;
  reg [31:0] total, uprod, sprod, want;
  integer sa, sx, sq, sr;
  reg [15:0] eq, er;
  reg ev;

  function [15:0] pick;
    input [31:0] r;
    begin
      case (r[18:16])
        3'd0: pick = 16'h0000;
        3'd1: pick = 16'h0001;
        3'd2: pick = 16'hFFFF;
        3'd3: pick = 16'h8000;
        3'd4: pick = 16'h7FFF;
        default: pick = r[15:0];
      endcase
    end
  endfunction

  task bad;
    input [127:0] what;
    begin
      fails = fails + 1;
      if (fails < 10) $display("FAIL %0s sub=%h a=%h x=%h: A=%h Y=%h V=%b", what, sub, a, x, a_out, y_out, f_v);
    end
  endtask

  initial begin
    seed = 65816;
    fails = 0;
    total = 32'd0;
    repeat (3) @(posedge clk);
    @(negedge clk) rst = 1'b0;
    for (n = 0; n < 20000; n = n + 1) begin
      @(negedge clk);
      k = {$random(seed)} % 9;
      sub = k + 1;
      a = pick($random(seed));
      x = pick($random(seed));
      y = pick($random(seed));
      uprod = {16'h0000, a} * {16'h0000, x};
      sa = $signed(a);
      sx = $signed(x);
      sprod = sa * sx;
      if (sub == 8'h02 || sub == 8'h07) begin
        start = 1'b1;
        @(negedge clk) start = 1'b0;
        clocks = 0;
        while (busy) begin
          @(negedge clk);
          clocks = clocks + 1;
        end
        if (clocks != 16) bad("clocks");
      end
      go = 1'b1;
      #1;
      case (sub)
        8'h01, 8'h06: begin
          want = (sub == 8'h06) ? sprod : uprod;
          if (!we_a || !we_y || {y_out, a_out} !== want) bad("product");
          if (!f_we || f_n !== want[31] || f_z !== (want == 32'd0)) bad("product flags");
        end
        8'h02, 8'h07: begin
          ev = 1'b0;
          if (x == 16'h0000) begin
            eq = 16'hFFFF; er = a; ev = 1'b1;
          end else if (sub == 8'h02) begin
            eq = a / x; er = a % x;
          end else begin
            sq = sa / sx;
            sr = sa % sx;
            eq = sq[15:0]; er = sr[15:0];
            ev = (sa == -32768) && (sx == -1);
          end
          if (!we_a || !we_y || a_out !== eq || y_out !== er) bad("quotient");
          if (!fv_we || f_v !== ev) bad("quotient flag");
        end
        8'h04: if ({y_out, a_out} !== total) bad("total");
        default: if (we_a || we_y) bad("write");
      endcase
      @(negedge clk) go = 1'b0;
      if (sub == 8'h03) total = total + uprod;
      if (sub == 8'h08) total = total + sprod;
      if (sub == 8'h05) total = 32'd0;
      if (sub == 8'h09) total = {y, a};
    end
    if (fails != 0) begin
      $display("WDM unit: %0d differences", fails);
      $fatal(1);
    end
    $display("WDM unit: 20000 operations, 0 differences");
    $finish;
  end
endmodule
