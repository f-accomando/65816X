// c816_addr.v - address unit of the c816 core (docs/design/cpu-core.md, section 3.3). Combinational.
// asel: 0 PC, 1 PCD, 2 EA, 3 EA1, 4 DUMI (indexed, before the high byte is fixed), 5 S, 6 S1,
//       7 VEC, 8 VEC1, 9-10 pointer of (dp) and (dp),Y, 11-12 pointer of (dp,X),
//       13-15 pointer of [dp], 16-17 pointer of (sr,S),Y.
// ea:   1 absolute, 2 absolute,X, 3 long, 4 absolute,Y, 5 long,X, 6 long,Y, 7 direct page,
//       8 direct page,X, 9 direct page,Y, 10 stack relative.
// Direct page and stack addresses are in bank 0. In emulation mode, the stack stays in page 1,
// and the 6502 direct page modes stay in one page when D[7:0] = 0.
module c816_addr (
  input [4:0] asel,
  input [3:0] ea,
  input [15:0] pc,
  input [7:0] pbr,
  input [7:0] dbr,
  input [15:0] s,
  input [15:0] x,
  input [15:0] y,
  input [15:0] d,
  input e,
  input [7:0] al,
  input [7:0] ah,
  input [7:0] ba,
  input [7:0] of,
  input [7:0] vec,
  output reg [23:0] addr,
  output xcarry,
  output br_cross,
  output [15:0] br_target,
  output [15:0] pc_m1
);
  assign pc_m1 = pc - 16'd1;

  // abs,X, abs,Y and (dp),Y: carry of the low byte into the high byte (dummy cycle)
  wire [7:0] ilow = (ea == 4'd4) ? y[7:0] : x[7:0];
  wire [8:0] xsum = {1'b0, al} + {1'b0, ilow};
  assign xcarry = xsum[8];

  // relative branch: PC already points to the next instruction, AL holds the signed offset
  wire [15:0] offset = {al[7] ? 8'hFF : 8'h00, al};
  assign br_target = pc + offset;
  assign br_cross = (br_target[15:8] != pc[15:8]);

  wire [7:0] s_low1 = s[7:0] + 8'd1;
  wire [15:0] s1 = s + 16'd1;

  // direct page: OF is the offset byte of the instruction
  wire wrap = e && (d[7:0] == 8'h00);
  wire [15:0] dp0 = d + {8'h00, of};
  wire [7:0] dp0_low1 = dp0[7:0] + 8'd1;
  wire [15:0] dp0_next = dp0 + 16'd1;
  wire [15:0] dp1 = wrap ? {dp0[15:8], dp0_low1} : dp0_next;

  wire [15:0] dindex = (ea == 4'd8) ? x : (ea == 4'd9) ? y : 16'd0;
  wire [15:0] dsum = dp0 + dindex;
  wire [7:0] dlow = of + dindex[7:0];
  wire [15:0] ddata = wrap ? {d[15:8], dlow} : dsum;

  wire [15:0] xp_sum = dp0 + x;
  wire [7:0] xp_low = of + x[7:0];
  wire [15:0] xp0 = wrap ? {d[15:8], xp_low} : xp_sum;
  wire [7:0] xp0_low1 = xp0[7:0] + 8'd1;
  wire [15:0] xp0_next = xp0 + 16'd1;
  wire [15:0] xp1 = wrap ? {xp0[15:8], xp0_low1} : xp0_next;

  wire [15:0] lp2 = dp0 + 16'd2;

  wire [15:0] sr0 = s + {8'h00, of};
  wire [15:0] sr1 = sr0 + 16'd1;

  reg [23:0] eff;
  always @* begin
    case (ea)
      4'd1: eff = {dbr, ah, al};
      4'd2: eff = {dbr, ah, al} + {8'h00, x};   // 24-bit: the index can reach the next bank
      4'd3: eff = {ba, ah, al};
      4'd4: eff = {dbr, ah, al} + {8'h00, y};
      4'd5: eff = {ba, ah, al} + {8'h00, x};
      4'd6: eff = {ba, ah, al} + {8'h00, y};
      4'd7: eff = {8'h00, ddata};
      4'd8: eff = {8'h00, ddata};
      4'd9: eff = {8'h00, ddata};
      4'd10: eff = {8'h00, sr0};
      default: eff = 24'h000000;
    endcase
  end

  // the second byte of a 16-bit value stays in bank 0 for direct page and stack data
  wire bank0 = (ea == 4'd7) || (ea == 4'd8) || (ea == 4'd9) || (ea == 4'd10);
  wire [15:0] eff_low1 = eff[15:0] + 16'd1;
  wire [23:0] eff_next = eff + 24'd1;
  wire [23:0] eff1 = bank0 ? {8'h00, eff_low1} : eff_next;

  always @* begin
    addr = {pbr, pc};
    case (asel)
      5'd0: addr = {pbr, pc};
      5'd1: addr = {pbr, pc_m1};
      5'd2: addr = eff;
      5'd3: addr = eff1;
      5'd4: addr = {dbr, ah, xsum[7:0]};
      5'd5: addr = e ? {16'h0001, s[7:0]} : {8'h00, s};
      5'd6: addr = e ? {16'h0001, s_low1} : {8'h00, s1};
      5'd7: addr = {16'h00FF, vec};
      5'd8: addr = {16'h00FF, vec} + 24'd1;
      5'd9: addr = {8'h00, dp0};
      5'd10: addr = {8'h00, dp1};
      5'd11: addr = {8'h00, xp0};
      5'd12: addr = {8'h00, xp1};
      5'd13: addr = {8'h00, dp0};
      5'd14: addr = {8'h00, dp0_next};
      5'd15: addr = {8'h00, lp2};
      5'd16: addr = {8'h00, sr0};
      5'd17: addr = {8'h00, sr1};
      default: addr = {pbr, pc};
    endcase
  end
endmodule
