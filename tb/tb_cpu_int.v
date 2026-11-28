// tb_cpu_int.v - directed test of the interrupts of c816_core: reset, IRQ, NMI, BRK, RTI, WAI,
// STP, in native and emulation mode. The public vectors do not cover the NMI and IRQ inputs.
// The last part counts the cycles of WDM MUL and WDM DIV with the extensions on.
// Memory is bank 0 only. A write to $4000 withdraws the IRQ request, a write to $4001 raises it,
// a write to $4002 pulses NMI. Each check prints one line; any failure ends with $fatal.
`timescale 1ns/1ns
module tb_cpu_int;
  reg clk = 1'b0;
  reg rst = 1'b1;
  reg nmi = 1'b0;
  reg irq = 1'b0;
  reg ext_en = 1'b0;
  wire [23:0] addr;
  wire rd, wr, vda, vpa, sync, cyc_end, dbg_illegal;
  wire [7:0] wdata;
  reg [7:0] din;
  wire [15:0] dbg_pc, dbg_a, dbg_x, dbg_y;

  c816_core dut (
    .clk(clk), .rst(rst), .halt(1'b0), .bus_wait(1'b0), .ext_en(ext_en), .nmi(nmi), .irq(irq),
    .din(din), .addr(addr), .rd(rd), .wr(wr), .wdata(wdata), .vda(vda), .vpa(vpa),
    .sync(sync), .cyc_end(cyc_end), .dbg_illegal(dbg_illegal),
    .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_x(dbg_x), .dbg_y(dbg_y)
  );

  always #5 clk = ~clk;

  reg [7:0] mem [0:65535];
  integer nmi_hold;
  always @(posedge clk) begin
    din <= rd ? mem[addr[15:0]] : 8'hxx;
    if (wr) begin
      mem[addr[15:0]] <= wdata;
      if (addr == 24'h004000) irq <= 1'b0;
      if (addr == 24'h004001) irq <= 1'b1;
      if (addr == 24'h004002) begin nmi <= 1'b1; nmi_hold <= 20; end
    end
    if (nmi_hold > 0) begin
      nmi_hold <= nmi_hold - 1;
      if (nmi_hold == 1) nmi <= 1'b0;
    end
  end

  // CPU cycles and opcode fetches
  integer cycles = 0;
  reg [23:0] last_fetch;
  integer fetch_cycle;
  always @(posedge clk) begin
    if (rst) cycles <= 0;
    else if (cyc_end) begin
      cycles <= cycles + 1;
      if (sync) begin last_fetch <= addr; fetch_cycle <= cycles; end
    end
  end

  integer fails = 0;
  task check;
    input ok;
    input [511:0] text;
    begin
      if (ok !== 1'b1) begin
        fails = fails + 1;
        $display("FAIL %0s", text);
      end else $display("ok   %0s", text);
    end
  endtask

  // wait until the opcode fetch at the address, at most n clocks
  reg seen;
  integer waited;
  task run_to;
    input [15:0] where;
    input integer limit;
    begin
      seen = 1'b0;
      waited = 0;
      while (!seen && waited < limit) begin
        @(negedge clk);
        waited = waited + 1;
        if (cyc_end && sync && addr == {8'h00, where}) seen = 1'b1;
      end
    end
  endtask

  integer i, p;
  task put;
    input [15:0] a;
    input [7:0] b;
    begin mem[a] = b; end
  endtask

  integer start_cycle;
  reg [7:0] pushed;
  initial begin
    for (i = 0; i < 65536; i = i + 1) mem[i] = 8'hEA;
    for (i = 0; i < 'h0200; i = i + 1) mem[i] = 8'h00;
    nmi_hold = 0;
    // vectors
    put(16'hFFFC, 8'h00); put(16'hFFFD, 8'h80);   // reset      $8000
    put(16'hFFEA, 8'h00); put(16'hFFEB, 8'h90);   // NMI native $9000
    put(16'hFFEE, 8'h00); put(16'hFFEF, 8'h91);   // IRQ native $9100
    put(16'hFFE6, 8'h00); put(16'hFFE7, 8'h92);   // BRK native $9200
    put(16'hFFFA, 8'h00); put(16'hFFFB, 8'h93);   // NMI emul.  $9300
    put(16'hFFFE, 8'h00); put(16'hFFFF, 8'h94);   // IRQ emul.  $9400
    // main program
    p = 'h8000;
    put(p, 8'h18); p = p + 1;                      // CLC
    put(p, 8'hFB); p = p + 1;                      // XCE          native
    put(p, 8'hA9); put(p+1, 8'h01); p = p + 2;     // LDA #$01
    put(p, 8'h8D); put(p+1, 8'h01); put(p+2, 8'h40); p = p + 3;   // STA $4001  raise IRQ, I = 1
    put(p, 8'hEA); p = p + 1;                      // NOP          IRQ masked
    put(p, 8'h58); p = p + 1;                      // $8008 CLI
    put(p, 8'hEA); p = p + 1;                      // $8009 NOP    runs before the IRQ
    put(p, 8'hEA); p = p + 1;                      // $800A NOP    the IRQ comes here
    put(p, 8'h8D); put(p+1, 8'h02); put(p+2, 8'h40); p = p + 3;   // $800B STA $4002  NMI
    put(p, 8'hEA); put(p+1, 8'hEA); p = p + 2;     // $800E
    put(p, 8'h00); put(p+1, 8'h55); p = p + 2;     // $8010 BRK #$55
    put(p, 8'h78); p = p + 1;                      // $8012 SEI
    put(p, 8'h8D); put(p+1, 8'h01); put(p+2, 8'h40); p = p + 3;   // $8013 raise IRQ
    put(p, 8'hCB); p = p + 1;                      // $8016 WAI    ends, IRQ masked: no interrupt
    put(p, 8'h8D); put(p+1, 8'h00); put(p+2, 8'h40); p = p + 3;   // $8017 withdraw IRQ
    put(p, 8'hE6); put(p+1, 8'h22); p = p + 2;     // $801A INC $22
    put(p, 8'h38); p = p + 1;                      // $801C SEC
    put(p, 8'hFB); p = p + 1;                      // $801D XCE    emulation
    put(p, 8'h58); p = p + 1;                      // $801E CLI
    put(p, 8'h8D); put(p+1, 8'h01); put(p+2, 8'h40); p = p + 3;   // $801F raise IRQ
    put(p, 8'hEA); put(p+1, 8'hEA); p = p + 2;     // $8022
    put(p, 8'hCB); p = p + 1;                      // $8024 WAI    wait for the NMI of the bench
    put(p, 8'hE6); put(p+1, 8'h23); p = p + 2;     // $8025 INC $23
    put(p, 8'hDB); p = p + 1;                      // $8027 STP
    put(p, 8'hE6); put(p+1, 8'h24); p = p + 2;     // $8028 never
    // handlers: count, then RTI (the IRQ handlers also withdraw the request)
    put(16'h9000, 8'hE6); put(16'h9001, 8'h10); put(16'h9002, 8'h40);
    put(16'h9100, 8'h8D); put(16'h9101, 8'h00); put(16'h9102, 8'h40);
    put(16'h9103, 8'hE6); put(16'h9104, 8'h11); put(16'h9105, 8'h40);
    put(16'h9200, 8'hE6); put(16'h9201, 8'h12); put(16'h9202, 8'h40);
    put(16'h9300, 8'hE6); put(16'h9301, 8'h13); put(16'h9302, 8'h40);
    put(16'h9400, 8'h8D); put(16'h9401, 8'h00); put(16'h9402, 8'h40);
    put(16'h9403, 8'hE6); put(16'h9404, 8'h14); put(16'h9405, 8'h40);

    repeat (3) @(posedge clk);
    @(negedge clk) rst = 1'b0;

    run_to(16'h8000, 100);
    check(seen && cycles == 7, "reset: first opcode fetch after 7 cycles");
    check(dut.u_regs.e === 1'b1 && dut.u_regs.s === 16'h01FC, "reset: emulation mode, S = $01FC");

    run_to(16'h8009, 200);
    check(seen, "IRQ stays masked while I = 1");
    run_to(16'h800A, 100);
    check(seen, "CLI lets one more instruction run before the IRQ");
    start_cycle = cycles;
    run_to(16'h9100, 100);
    check(seen && cycles - start_cycle == 8, "native IRQ: 8 cycles, handler at $9100");
    check(mem[16'h01FC] === 8'h00 && mem[16'h01FB] === 8'h80 && mem[16'h01FA] === 8'h0A,
          "native IRQ pushes PBR, PCH, PCL of the interrupted instruction");
    check(dut.u_regs.p[2] === 1'b1 && mem[16'h01F9][2] === 1'b0, "IRQ sets I; the pushed P has I = 0");
    run_to(16'h800A, 200);
    check(seen && mem[16'h0011] === 8'h01 && dut.u_regs.p[2] === 1'b0, "RTI returns and restores P");

    run_to(16'h9000, 200);
    check(seen, "NMI taken on a rising edge");
    run_to(16'h9200, 400);
    check(seen && mem[16'h0010] === 8'h01, "NMI runs once for one edge");
    check(mem[16'h01FA] === 8'h12, "BRK pushes the address after the signature byte");
    run_to(16'h8012, 200);
    check(seen && mem[16'h0012] === 8'h01, "RTI after BRK returns past the signature");

    run_to(16'h8017, 200);
    check(seen && mem[16'h0011] === 8'h01, "WAI with I = 1 ends on IRQ and takes no interrupt");
    run_to(16'h801E, 200);
    check(seen && mem[16'h0022] === 8'h01, "the program goes on after WAI");

    run_to(16'h9400, 200);
    check(seen && mem[16'h0023] === 8'h00, "emulation IRQ goes to $FFFE");
    pushed = mem[{8'h01, dut.u_regs.s[7:0] + 8'd1}];
    check(pushed[4] === 1'b0, "emulation IRQ pushes P with bit 4 at 0");
    run_to(16'h8024, 200);
    check(seen && mem[16'h0014] === 8'h01, "RTI in emulation mode returns");

    repeat (40) @(posedge clk);
    check(mem[16'h0023] === 8'h00, "WAI waits while no request is pending");
    @(negedge clk) nmi = 1'b1;
    repeat (6) @(posedge clk);
    @(negedge clk) nmi = 1'b0;
    run_to(16'h9300, 200);
    check(seen, "NMI ends WAI and is taken (emulation vector $FFFA)");
    run_to(16'h8027, 200);
    check(seen && mem[16'h0013] === 8'h01, "after the NMI the program goes on");

    repeat (20) @(posedge clk);
    @(negedge clk) nmi = 1'b1;
    repeat (6) @(posedge clk);
    @(negedge clk) nmi = 1'b0;
    repeat (80) @(posedge clk);
    check(mem[16'h0013] === 8'h01 && mem[16'h0024] === 8'h00, "STP stops the processor, also for NMI");
    @(negedge clk) rst = 1'b1;
    repeat (3) @(posedge clk);
    @(negedge clk) rst = 1'b0;
    run_to(16'h8000, 100);
    check(seen, "reset ends STP");

    // extensions: cycles of WDM MUL and WDM DIV
    @(negedge clk) rst = 1'b1;
    ext_en = 1'b1;
    put(16'h8000, 8'h18); put(16'h8001, 8'hFB);                          // CLC, XCE
    put(16'h8002, 8'hC2); put(16'h8003, 8'h30);                          // REP #$30
    put(16'h8004, 8'hA9); put(16'h8005, 8'h11); put(16'h8006, 8'h11);    // LDA #$1111
    put(16'h8007, 8'hA2); put(16'h8008, 8'h07); put(16'h8009, 8'h00);    // LDX #$0007
    put(16'h800A, 8'h42); put(16'h800B, 8'h01);                          // WDM $01  MUL
    put(16'h800C, 8'h42); put(16'h800D, 8'h02);                          // WDM $02  DIV
    put(16'h800E, 8'hDB);                                                // STP
    repeat (3) @(posedge clk);
    @(negedge clk) rst = 1'b0;
    run_to(16'h800A, 200);
    start_cycle = cycles;
    run_to(16'h800C, 100);
    check(seen && cycles - start_cycle == 2, "WDM MUL takes 2 cycles");
    start_cycle = cycles;
    run_to(16'h800E, 100);
    check(seen && cycles - start_cycle == 11, "WDM DIV takes 11 cycles");
    check(dbg_a === 16'h1111 && dbg_y === 16'h0000, "WDM DIV gives the quotient and the remainder");

    if (fails != 0) begin
      $display("%0d checks failed", fails);
      $fatal(1);
    end
    $display("interrupt test: PASS");
    $finish;
  end
endmodule
