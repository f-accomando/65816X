// tb_snes_plus.v - testbench per Icarus Verilog. Carica rom.hex (make rom), esegue il
// programma di collaudo fino all'etichetta 'done' e controlla tutti i valori di
// tests/test_program.expect tramite build/checks.vh (generato da sim/gen_tb.py).
`timescale 1ns/1ps
module tb_snes_plus;
  reg clk = 1'b0;
  reg rst = 1'b1;
  wire [15:0] pc, a, x, y;
  wire vb;
  integer fails = 0;
  integer cycles = 0;
  integer hits = 0;

  snes_plus_top dut (.clk(clk), .rst(rst), .dbg_pc(pc), .dbg_a(a), .dbg_x(x), .dbg_y(y), .dbg_vblank(vb));
  always #5 clk = ~clk;

`include "checks.vh"

  initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;
    while (hits <= 8 && cycles < MAX_CYCLES) begin
      @(posedge clk);
      cycles = cycles + 1;
      if (pc == DONE || pc == DONE + 16'd2) hits = hits + 1;
    end
    if (hits <= 8) begin
      $display("TIMEOUT: pc=%h", pc);
      $fatal(1, "FAIL");
    end
    $display("programma terminato in %0d cicli", cycles);
    run_checks;
    $display("%0d/%0d controlli superati", TOTAL - fails, TOTAL);
    if (fails != 0) $fatal(1, "FAIL");
    $display("PASS");
    $finish;
  end
endmodule
