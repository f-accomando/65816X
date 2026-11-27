// tb_wram.v - confronto ciclo per ciclo tra rtl/wram.v e il modello tb/wram_ref.v con
// stimoli casuali (banchi $7E-$7F, mirror basso, porta $2180-$2183, reset sparsi).
// Controlla rdata e hit a ogni ciclo e tutta la memoria alla fine.
`timescale 1ns/1ps
module tb_wram;
  reg clk = 1'b0, rst = 1'b1;
  reg [23:0] addr = 24'd0;
  reg rd = 1'b0, wr = 1'b0;
  reg [7:0] wdata = 8'd0;
  wire [7:0] r_dut, r_ref;
  wire h_dut, h_ref;
  integer i, k, errs = 0, seed = 1, nport = 0;

  wram     dut (.clk(clk), .rst(rst), .addr(addr), .rd(rd), .wr(wr), .wdata(wdata), .rdata(r_dut), .hit(h_dut));
  wram_ref u_ref (.clk(clk), .rst(rst), .addr(addr), .rd(rd), .wr(wr), .wdata(wdata), .rdata(r_ref), .hit(h_ref));
  always #5 clk = ~clk;

  initial begin
    for (i = 0; i < 131072; i = i + 1) begin
      dut.mem[i] = i[7:0] ^ i[15:8];
      u_ref.mem[i] = i[7:0] ^ i[15:8];
    end
    for (i = 0; i < 100000; i = i + 1) begin
      @(negedge clk);
      if (r_dut !== r_ref || h_dut !== h_ref) begin
        errs = errs + 1;
        if (errs <= 10) $display("DIFF ciclo %0d addr %h rdata %h atteso %h", i, addr, r_dut, r_ref);
      end
      rst = (i < 3) || (($random(seed) & 4095) == 0);
      k = $random(seed) & 7;
      case (k)
        0, 1, 2: addr = 24'h002180 | ($random(seed) & 24'h800003);   // porta, anche banco $80
        3: addr = 24'h7E0000 | ($random(seed) & 24'h01003F);         // banchi $7E-$7F
        4: addr = $random(seed) & 24'h80003F;                         // mirror $0000-$1FFF
        5: addr = $random(seed);                                      // ovunque
        default: addr = 24'h7F0000 | ($random(seed) & 24'h01003F);
      endcase
      rd = $random(seed); wr = $random(seed); wdata = $random(seed) & 8'h3F;
      if ((addr[15:0] & 16'hFFFC) == 16'h2180 && (rd || wr)) nport = nport + 1;
    end
    for (i = 0; i < 131072; i = i + 1) if (dut.mem[i] !== u_ref.mem[i]) errs = errs + 1;
    $display("tb_wram: %0d differenze, %0d accessi alla porta", errs, nport);
    if (errs != 0) $fatal(1, "FAIL");
    $display("PASS");
    $finish;
  end
endmodule
