// c816_ext.v - the WDM extensions of the c816 core (docs/design/cpu-core.md, section 5.2).
// go = 1 runs the operation sub in this clock. The core sets go only with ext_en = 1.
// Sub-opcodes: 1 MUL, 2 DIV, 3 MAC, 4 MACRD, 5 MACCLR, 6 MULS, 7 DIVS, 8 MACS, 9 MACLD.
// The operations assume 16-bit A, X, and Y. MULS, DIVS, and MACS take signed numbers.
// One unsigned multiplier serves both kinds: a negative operand corrects the high half.
// The divider is sequential and works on magnitudes: start loads A, one quotient bit follows at
// each clock, and busy is 1 for 16 clocks. The core repeats the second cycle of WDM DIV and DIVS
// until busy is 0. DIVS rounds toward 0; the remainder has the sign of A.
module c816_ext (
  input clk,
  input rst,
  input go,
  input start,
  input [7:0] sub,
  input [15:0] a,
  input [15:0] x,
  input [15:0] y,
  output reg we_a,
  output reg we_y,
  output reg [15:0] a_out,
  output reg [15:0] y_out,
  output reg f_we,
  output reg f_n,
  output reg f_z,
  output reg fv_we,
  output reg f_v,
  output busy
);
  reg [31:0] acc;
  wire [31:0] prod = {16'h0000, a} * {16'h0000, x};
  wire mul_signed = (sub == 8'h06) || (sub == 8'h08);
  wire [15:0] fix_a = (mul_signed && a[15]) ? x : 16'h0000;
  wire [15:0] fix_x = (mul_signed && x[15]) ? a : 16'h0000;
  wire [31:0] result = {prod[31:16] - fix_a - fix_x, prod[15:0]};

  // restoring division, one bit for each clock
  reg [15:0] quo, rem;
  reg [4:0] left;
  wire div_signed = (sub == 8'h07);
  wire [15:0] mag_a = (div_signed && a[15]) ? (16'h0000 - a) : a;
  wire [15:0] mag_x = (div_signed && x[15]) ? (16'h0000 - x) : x;
  wire [15:0] quo_s = (div_signed && (a[15] != x[15])) ? (16'h0000 - quo) : quo;
  wire [15:0] rem_s = (div_signed && a[15]) ? (16'h0000 - rem) : rem;
  // the only signed quotient that does not fit: -32768 / -1
  wire div_over = div_signed && (a == 16'h8000) && (x == 16'hFFFF);
  wire [16:0] trial = {rem, quo[15]};
  wire [16:0] diff = trial - {1'b0, mag_x};
  wire fits = !diff[16];
  assign busy = (left != 5'd0);

  always @(posedge clk) begin
    if (rst) begin
      quo <= 16'h0000;
      rem <= 16'h0000;
      left <= 5'd0;
    end else if (start) begin
      quo <= mag_a;
      rem <= 16'h0000;
      left <= 5'd16;
    end else if (left != 5'd0) begin
      rem <= fits ? diff[15:0] : trial[15:0];
      quo <= {quo[14:0], fits};
      left <= left - 5'd1;
    end
  end

  always @* begin
    we_a = 1'b0;
    we_y = 1'b0;
    a_out = 16'h0000;
    y_out = 16'h0000;
    f_we = 1'b0;
    f_n = 1'b0;
    f_z = 1'b0;
    fv_we = 1'b0;
    f_v = 1'b0;
    if (go) begin
      case (sub)
        8'h01, 8'h06: begin   // MUL, MULS: Y:A = A * X
          we_a = 1'b1; a_out = result[15:0];
          we_y = 1'b1; y_out = result[31:16];
          f_we = 1'b1; f_n = result[31]; f_z = (result == 32'd0);
        end
        8'h02, 8'h07: begin   // DIV, DIVS: A = A / X, Y = remainder; X = 0 gives A = $FFFF, Y = A, V = 1
          we_a = 1'b1;
          we_y = 1'b1;
          fv_we = 1'b1;
          if (x == 16'h0000) begin
            a_out = 16'hFFFF; y_out = a; f_v = 1'b1;
          end else begin
            a_out = quo_s; y_out = rem_s; f_v = div_over;
          end
        end
        8'h04: begin   // MACRD: A = low half, Y = high half of the total
          we_a = 1'b1; a_out = acc[15:0];
          we_y = 1'b1; y_out = acc[31:16];
        end
        default: ;
      endcase
    end
  end

  always @(posedge clk) begin
    if (rst) acc <= 32'd0;
    else if (go) begin
      if (sub == 8'h03 || sub == 8'h08) acc <= acc + result;   // MAC, MACS
      if (sub == 8'h05) acc <= 32'd0;                          // MACCLR
      if (sub == 8'h09) acc <= {y, a};                         // MACLD
    end
  end
endmodule
