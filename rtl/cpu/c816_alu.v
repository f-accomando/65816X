// c816_alu.v - the one ALU of the c816 core (docs/design/cpu-core.md, section 3.2). Combinational.
// w16 = 0 uses bits 7:0: N, Z, V and C come from bit 7, and r[15:8] is "don't care".
// dec (P.D) is reserved for decimal mode and has no effect yet.
module c816_alu (
  input [3:0] op,
  input [15:0] a,
  input [15:0] b,
  input ci,
  input w16,
  input dec,
  output reg [15:0] r,
  output reg n,
  output reg v,
  output reg z,
  output reg c
);
  // op codes: 0 PASSB, 1 PASSA, 2 ADD, 3 SUB, 4 CMP, 5 AND, 6 ORA, 7 EOR, 8 INC, 9 DEC
  wire inv = (op == 4'd3) || (op == 4'd4);
  wire [15:0] bb = inv ? ~b : b;
  wire cin = (op == 4'd4) ? 1'b1 : ci;
  wire [16:0] s16 = {1'b0, a} + {1'b0, bb} + {16'd0, cin};
  wire [8:0] s8 = {1'b0, a[7:0]} + {1'b0, bb[7:0]} + {8'd0, cin};
  wire sa = w16 ? a[15] : a[7];
  wire sb = w16 ? bb[15] : bb[7];

  always @* begin
    r = 16'd0;
    n = 1'b0;
    v = 1'b0;
    z = 1'b0;
    c = 1'b0;
    case (op)
      4'd0: r = b;
      4'd1: r = a;
      4'd2, 4'd3, 4'd4: begin
        r = w16 ? s16[15:0] : {8'd0, s8[7:0]};
        c = w16 ? s16[16] : s8[8];
      end
      4'd5: r = a & b;
      4'd6: r = a | b;
      4'd7: r = a ^ b;
      4'd8: r = a + 16'd1;
      4'd9: r = a - 16'd1;
      default: r = b;
    endcase
    n = w16 ? r[15] : r[7];
    z = w16 ? (r == 16'd0) : (r[7:0] == 8'd0);
    // overflow: both inputs have the same sign and the result has the other sign
    v = (sa == sb) && (sa != (w16 ? r[15] : r[7]));
  end
endmodule
