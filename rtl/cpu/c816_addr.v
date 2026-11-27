// c816_addr.v - address unit of the c816 core (docs/design/cpu-core.md, section 3.3). Combinational.
// Implemented asel codes: 0 PC, 1 PCD, 2 EA, 3 EA1, 4 DUMX. The other codes give {PBR, PC} until
// their step adds them. br_cross is 0, and br_target is PC, until their step adds them.
// ea codes: 1 absolute, 2 absolute,X, 3 long.
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
  assign br_cross = 1'b0;
  assign br_target = pc;

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
      default: addr = {pbr, pc};
    endcase
  end
endmodule
