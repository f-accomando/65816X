// c816_addr.v - address unit of the c816 core (docs/design/cpu-core.md, section 3.3). Combinational.
// asel codes: 0 PC, 1 PCD, 2 EA, 3 EA1, 4 DUMX, 5 S, 6 S1, 7 VEC, 8 VEC1. The other codes are
// reserved and give {PBR, PC}. ea codes: 1 absolute, 2 absolute,X, 3 long.
// In emulation mode, the stack addresses stay in page 1.
module c816_addr (
  input [3:0] asel,
  input [3:0] ea,
  input [15:0] pc,
  input [7:0] pbr,
  input [7:0] dbr,
  input [15:0] s,
  input [15:0] x,
  input e,
  input [7:0] al,
  input [7:0] ah,
  input [7:0] ba,
  input [7:0] vec,
  output reg [23:0] addr,
  output xcarry,
  output br_cross,
  output [15:0] br_target,
  output [15:0] pc_m1
);
  assign pc_m1 = pc - 16'd1;
  // xcarry: the low byte of AL + X carries into the high byte (abs,X dummy cycle)
  wire [8:0] xsum = {1'b0, al} + {1'b0, x[7:0]};
  assign xcarry = xsum[8];
  // relative branch: PC already points to the next instruction, AL holds the signed offset
  wire [15:0] offset = {al[7] ? 8'hFF : 8'h00, al};
  assign br_target = pc + offset;
  assign br_cross = (br_target[15:8] != pc[15:8]);

  wire [7:0] s_low1 = s[7:0] + 8'd1;
  wire [15:0] s1 = s + 16'd1;

  reg [23:0] eff;
  always @* begin
    case (ea)
      4'd1: eff = {dbr, ah, al};
      4'd2: eff = {dbr, ah, al} + {8'h00, x};   // 24-bit: the index can reach the next bank
      4'd3: eff = {ba, ah, al};
      default: eff = 24'h000000;
    endcase
  end

  always @* begin
    addr = {pbr, pc};
    case (asel)
      4'd0: addr = {pbr, pc};
      4'd1: addr = {pbr, pc_m1};
      4'd2: addr = eff;
      4'd3: addr = eff + 24'd1;
      4'd4: addr = {dbr, ah, xsum[7:0]};        // abs,X: address before the high byte is fixed
      4'd5: addr = e ? {16'h0001, s[7:0]} : {8'h00, s};
      4'd6: addr = e ? {16'h0001, s_low1} : {8'h00, s1};
      4'd7: addr = {16'h00FF, vec};
      4'd8: addr = {16'h00FF, vec} + 24'd1;
      default: addr = {pbr, pc};
    endcase
  end
endmodule
