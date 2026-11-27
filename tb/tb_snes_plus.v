// tb_snes_plus.v - testbench per Icarus Verilog. Carica rom.hex (vedi 'make rom'),
// esegue il programma di collaudo e controlla alcune celle di WRAM.
// NOTA: scritto ma NON ancora eseguito con iverilog (non disponibile nell'ambiente di
// sviluppo); l'equivalente verificato e' sim/run_tests.py.
`timescale 1ns/1ps
module tb_snes_plus;
  reg clk = 1'b0;
  reg rst = 1'b1;
  wire [15:0] pc, a, x, y;
  wire vb;
  integer fails = 0;

  snes_plus_top dut (.clk(clk), .rst(rst), .dbg_pc(pc), .dbg_a(a), .dbg_x(x), .dbg_y(y), .dbg_vblank(vb));
  always #5 clk = ~clk;

  task check(input [16:0] addr, input [7:0] expected);
    begin
      if (dut.u_wram.mem[addr] !== expected) begin
        $display("FAIL WRAM[%h] = %h, atteso %h", addr, dut.u_wram.mem[addr], expected);
        fails = fails + 1;
      end
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (4000) @(posedge clk);
    check(17'h0000, 8'h35); check(17'h0001, 8'h12);   // T1
    check(17'h0004, 8'h0F);                           // T3
    check(17'h0006, 8'hEF); check(17'h0007, 8'hBE);   // T4
    check(17'h0008, 8'h3F);                           // T5 moltiplicatore
    check(17'h000A, 8'h40); check(17'h000B, 8'h23);   // T8 WDM MUL
    check(17'h001A, 8'h11); check(17'h001D, 8'h44);   // T7 VRAM via DMA
    check(17'h0030, 8'hAA); check(17'h0031, 8'hBB);   // T12 porta WRAM
    if (fails == 0) $display("PASS");
    else $display("FAIL: %0d controlli", fails);
    $finish;
  end
endmodule
