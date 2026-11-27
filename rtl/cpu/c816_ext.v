// c816_ext.v - the WDM extensions of the c816 core (docs/design/cpu-core.md, section 5.2).
// go = 1 runs the operation sub in this clock. The core sets go only with ext_en = 1.
// Sub-opcodes: 1 MUL, 2 DIV, 3 MAC, 4 MACRD, 5 MACCLR. The operations assume 16-bit A and X.
// The divider is combinational until a later step replaces it; busy stays 0.
module c816_ext (
  input clk,
  input rst,
  input go,
  input [7:0] sub,
  input [15:0] a,
  input [15:0] x,
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

  assign busy = 1'b0;

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
        8'h01: begin   // MUL: Y:A = A * X
          we_a = 1'b1; a_out = prod[15:0];
          we_y = 1'b1; y_out = prod[31:16];
          f_we = 1'b1; f_n = prod[31]; f_z = (prod == 32'd0);
        end
        8'h02: begin   // DIV: A = A / X, Y = remainder; X = 0 gives A = $FFFF, Y = A, V = 1
          we_a = 1'b1;
          we_y = 1'b1;
          fv_we = 1'b1;
          if (x == 16'h0000) begin
            a_out = 16'hFFFF; y_out = a; f_v = 1'b1;
          end else begin
            a_out = a / x; y_out = a % x;
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
      if (sub == 8'h03) acc <= acc + prod;        // MAC
      if (sub == 8'h05) acc <= 32'd0;             // MACCLR
    end
  end
endmodule
