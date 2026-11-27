// cart_rom.v - cartuccia LoROM da 64 KB (segnaposto della SDRAM da 32 MB).
// Banchi $00-$7D / $80-$FF, offset $8000-$FFFF. Per sintesi caricare rom.hex.
module cart_rom (
  input clk,
  input rst,
  input [23:0] addr,
  input rd,
  input wr,
  input [7:0] wdata,
  output reg [7:0] rdata,
  output hit
);
  reg [7:0] mem [0:65535];
  assign hit = addr[15] && (addr[23:17] != 7'b0111111);
  initial $readmemh("rom.hex", mem);
  always @(posedge clk) begin
    rdata <= mem[{addr[16], addr[14:0]}];
  end
endmodule
