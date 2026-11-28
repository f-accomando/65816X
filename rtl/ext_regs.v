// ext_regs.v - registri delle estensioni SNES+ in $5F00-$5FFF (zona libera sull'SNES).
// $5F00 ID (legge $58), $5F01 modo (0=SNES, 1=accelerato, 2=enhanced), $5F02 velocita',
// $5F03 versione delle estensioni della CPU (sola lettura: 2 = sotto-opcode 1-9).
module ext_regs (
  input clk,
  input rst,
  input [23:0] addr,
  input rd,
  input wr,
  input [7:0] wdata,
  output reg [7:0] rdata,
  output hit,
  output reg [7:0] mode,
  output reg [7:0] speed,
  output enhanced
);
  assign hit = (addr[22] == 1'b0) && (addr[15:8] == 8'h5F);
  // le estensioni della CPU agiscono solo in modalita' estesa
  assign enhanced = (mode == 8'd2);
  reg [7:0] rb;
  always @* begin
    case (addr[7:0])
      8'h00: rb = 8'h58;
      8'h01: rb = mode;
      8'h02: rb = speed;
      8'h03: rb = 8'h02;
      default: rb = 8'h00;
    endcase
  end
  always @(posedge clk) begin
    rdata <= rb;
    if (rst) begin mode <= 8'd0; speed <= 8'd0; end
    else if (hit && wr) begin
      if (addr[7:0] == 8'h01) mode <= wdata;
      if (addr[7:0] == 8'h02) speed <= wdata;
    end
  end
endmodule
