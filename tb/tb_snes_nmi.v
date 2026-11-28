// tb_snes_nmi.v - the NMI of the system: the vertical blank of the video stub reaches the core
// through the 5A22 when $4200 bit 7 is 1. The program waits with WAI, the handler reads $4210.
`timescale 1ns/1ps
module tb_snes_nmi;
  reg clk = 1'b0;
  reg rst = 1'b1;
  wire [15:0] pc, a, x, y;
  wire vb, illegal;
  integer cycles = 0;

  snes_plus_top dut (.clk(clk), .rst(rst), .dbg_pc(pc), .dbg_a(a), .dbg_x(x), .dbg_y(y),
                     .dbg_vblank(vb), .dbg_illegal(illegal));
  always #5 clk = ~clk;

  integer p;
  task put;
    input [7:0] b;
    begin
      dut.u_rom.mem[p] = b;
      p = p + 1;
    end
  endtask

  initial begin
    #1;                                   // after the ROM file of the cartridge is loaded
    p = 0;                                // $8000
    put(8'h18); put(8'hFB);               // CLC, XCE
    put(8'hA9); put(8'h80);               // LDA #$80
    put(8'h8D); put(8'h00); put(8'h42);   // STA $4200      NMI on
    put(8'hCB);                           // WAI
    put(8'hE6); put(8'h10);               // INC $10        after the handler
    put(8'hDB);                           // STP
    p = 'h100;                            // $8100, NMI handler
    put(8'hAD); put(8'h10); put(8'h42);   // LDA $4210
    put(8'hE6); put(8'h11);               // INC $11
    put(8'h40);                           // RTI
    p = 'h7FEA; put(8'h00); put(8'h81);   // native NMI vector
    p = 'h7FFC; put(8'h00); put(8'h80);   // reset vector
    dut.u_wram.mem[17'h10] = 8'h00;
    dut.u_wram.mem[17'h11] = 8'h00;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    while (cycles < 200000 && dut.u_wram.mem[17'h10] !== 8'h01) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    repeat (2000) @(posedge clk);
    if (dut.u_wram.mem[17'h10] !== 8'h01 || dut.u_wram.mem[17'h11] !== 8'h01 || illegal !== 1'b0) begin
      $display("FAIL: marker $10 = %h, handler count $11 = %h, pc = %h",
               dut.u_wram.mem[17'h10], dut.u_wram.mem[17'h11], pc);
      $fatal(1);
    end
    if (cycles < 76000) begin
      $display("FAIL: the NMI came before the vertical blank (%0d clocks)", cycles);
      $fatal(1);
    end
    $display("NMI test: PASS after %0d clocks", cycles);
    $finish;
  end
endmodule
