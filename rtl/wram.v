// wram.v - 128 KB di WRAM: banchi $7E-$7F, mirror $0000-$1FFF dei banchi $00-$3F/$80-$BF,
// porta $2180-$2183 (WMDATA, WMADD).
module wram (
  input clk,
  input rst,
  input [23:0] addr,
  input rd,
  input wr,
  input [7:0] wdata,
  output reg [7:0] rdata,
  output hit
);
  reg [7:0] mem [0:131071];
  reg [16:0] port_addr;

  wire is_bank = (addr[23:17] == 7'b0111111);
  wire is_low = (addr[22] == 1'b0) && (addr[15:13] == 3'b000);
  wire is_port = (addr[22] == 1'b0) && (addr[15:2] == 14'h0860);
  assign hit = is_bank | is_low | is_port;

  wire [16:0] a17 = is_bank ? addr[16:0] : {4'h0, addr[12:0]};
  wire [7:0] rbyte = is_port ? ((addr[1:0] == 2'd0) ? mem[port_addr] : 8'h00) : mem[a17];

  always @(posedge clk) begin
    rdata <= rbyte;
    if (rst) port_addr <= 17'd0;
    else begin
      if (is_port && rd && addr[1:0] == 2'd0) port_addr <= port_addr + 17'd1;
      if (wr) begin
        if (is_port) begin
          case (addr[1:0])
            2'd0: begin mem[port_addr] <= wdata; port_addr <= port_addr + 17'd1; end
            2'd1: port_addr[7:0] <= wdata;
            2'd2: port_addr[15:8] <= wdata;
            default: port_addr[16] <= wdata[0];
          endcase
        end else if (is_bank | is_low) mem[a17] <= wdata;
      end
    end
  end
endmodule
