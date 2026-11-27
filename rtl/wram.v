// wram.v - 128 KB di WRAM: banchi $7E-$7F, mirror $0000-$1FFF dei banchi $00-$3F/$80-$BF,
// porta $2180-$2183 (WMDATA, WMADD).
// Un solo indirizzo (ma) per lettura e scrittura e lettura registrata "read-before-write":
// e' la forma che yosys mappa su BRAM a porta singola (DP16KD su ECP5).
// Comportamento ai morsetti identico alla versione precedente: il dato letto e' quello
// presente prima di un'eventuale scrittura nello stesso ciclo; $2181-$2183 si leggono $00.
module wram (
  input clk,
  input rst,
  input [23:0] addr,
  input rd,
  input wr,
  input [7:0] wdata,
  output [7:0] rdata,
  output hit
);
  reg [7:0] mem [0:131071];
  reg [16:0] port_addr;
  reg [7:0] q;
  reg zero_q;

  wire is_bank = (addr[23:17] == 7'b0111111);
  wire is_low = (addr[22] == 1'b0) && (addr[15:13] == 3'b000);
  wire is_port = (addr[22] == 1'b0) && (addr[15:2] == 14'h0860);
  wire is_data = is_port && (addr[1:0] == 2'd0);
  assign hit = is_bank | is_low | is_port;

  wire [16:0] a17 = is_bank ? addr[16:0] : {4'h0, addr[12:0]};
  wire [16:0] ma = is_port ? port_addr : a17;
  wire we = !rst && wr && (is_port ? is_data : (is_bank | is_low));
  assign rdata = zero_q ? 8'h00 : q;

  // memoria: solo questo blocco tocca mem
  always @(posedge clk) begin
    if (we) mem[ma] <= wdata;
    q <= mem[ma];
    zero_q <= is_port && !is_data;
  end

  // registri della porta $2180-$2183
  always @(posedge clk) begin
    if (rst) port_addr <= 17'd0;
    else begin
      if (is_data && rd) port_addr <= port_addr + 17'd1;
      if (wr && is_port) begin
        case (addr[1:0])
          2'd0: port_addr <= port_addr + 17'd1;
          2'd1: port_addr[7:0] <= wdata;
          2'd2: port_addr[15:8] <= wdata;
          default: port_addr[16] <= wdata[0];
        endcase
      end
    end
  end
endmodule
