// c816_addr.v - address unit of the c816 core (docs/design/cpu-core.md, section 3.3). Combinational.
// Implemented asel codes: 0 PC, 1 PCD. The other codes give {PBR, PC} until their step adds them.
// xcarry and br_cross are 0, and br_target is PC, until their step adds them.
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
  assign xcarry = 1'b0;
  assign br_cross = 1'b0;
  assign br_target = pc;

  always @* begin
    addr = {pbr, pc};
    case (asel)
      4'd0: addr = {pbr, pc};
      4'd1: addr = {pbr, pc_m1};
      default: addr = {pbr, pc};
    endcase
  end
endmodule
