// apu_stub.v - SPC700 + S-DSP sostituiti da 4 porte $2140-$2143 con eco.
// Dopo il reset le porte 0 e 1 leggono $AA e $BB (firma di boot dell'SPC700).
module apu_stub (
  input clk,
  input rst,
  input [23:0] addr,
  input rd,
  input wr,
  input [7:0] wdata,
  output reg [7:0] rdata,
  output hit
);
  reg [7:0] p0, p1, p2, p3;
  reg [3:0] written;
  assign hit = (addr[22] == 1'b0) && (addr[15:6] == 10'h085);

  reg [7:0] rb;
  always @* begin
    case (addr[1:0])
      2'd0: rb = written[0] ? p0 : 8'hAA;
      2'd1: rb = written[1] ? p1 : 8'hBB;
      2'd2: rb = written[2] ? p2 : 8'h00;
      default: rb = written[3] ? p3 : 8'h00;
    endcase
  end

  always @(posedge clk) begin
    rdata <= rb;
    if (rst) begin
      p0 <= 8'd0; p1 <= 8'd0; p2 <= 8'd0; p3 <= 8'd0; written <= 4'd0;
    end else if (hit && wr) begin
      case (addr[1:0])
        2'd0: begin p0 <= wdata; written[0] <= 1'b1; end
        2'd1: begin p1 <= wdata; written[1] <= 1'b1; end
        2'd2: begin p2 <= wdata; written[2] <= 1'b1; end
        default: begin p3 <= wdata; written[3] <= 1'b1; end
      endcase
    end
  end
endmodule
