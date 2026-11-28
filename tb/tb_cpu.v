// tb_cpu.v - CPU-only test bench.
// For each vector: load registers and memory, run one instruction, compare the final state.
// Usage: vvp tb_cpu.vvp +vec=<vectors> +out=<results>   (format: see sim/cpu_vectors.py)
// Result line: opcode, initial e, mask of the differences, count, expected cycles.
// The adapter file cpu_adapt_c816.vh holds the core instance. Only the adapter reads internal
// registers: it defines load_state, state_diff, and run_instruction.
`timescale 1ns/1ns
module tb_cpu;
  // a block move vector (MVN, MVP) covers the whole move: thousands of cycles
  localparam MAXRAM = 4096;
  localparam MAXCYC = 8192;
  localparam MAXCLK = 40000;
  // bits of the mask, in the order of FIELDS in sim/cpu_score.py
  localparam F_PC = 0, F_S = 1, F_P = 2, F_A = 3, F_X = 4, F_Y = 5, F_DBR = 6, F_D = 7,
             F_PBR = 8, F_E = 9, F_RAM = 10, F_STRAY = 11, F_TIME = 12, F_CYC = 13,
             F_BUS = 14, F_ILL = 15;

  reg clk = 1'b0;
  reg rst = 1'b1;
  wire [23:0] addr;
  wire rd, wr;
  wire [7:0] wdata;
  reg [7:0] din;

  always #5 clk = ~clk;

  // 16 MB memory: read data arrives in the next clock, and only if rd was active
  reg [7:0] mem [0:16777215];
  reg [23:0] written [0:MAXRAM-1];
  integer nwritten;
  reg expected [0:16777215];      // 1 while the address is in the final list of the vector
  reg running;
  always @(posedge clk) begin
    din <= rd ? mem[addr] : 8'hxx;
    if (wr && running) begin
      mem[addr] <= wdata;
      if (nwritten < MAXRAM) begin
        written[nwritten] = addr;
        nwritten = nwritten + 1;
      end
    end
  end

  // state: 0 pc, 1 s, 2 p, 3 a, 4 x, 5 y, 6 dbr, 7 d, 8 pbr, 9 e
  reg [31:0] ini [0:9];
  reg [31:0] fin [0:9];
  reg [31:0] ra [0:MAXRAM-1], rv [0:MAXRAM-1];
  reg [31:0] fa [0:MAXRAM-1], fv [0:MAXRAM-1];
  // bus cycles of the vector (kind bit 0 VDA, bit 1 VPA, bit 2 write; value 100 = none)
  reg [31:0] ck [0:MAXCYC-1], ca [0:MAXCYC-1], cv [0:MAXCYC-1];
  reg [31:0] opcode, expcyc, nr, nf, nc;
  // set by run_instruction
  integer count;
  reg timeout, bus_bad, illegal;

`include "cpu_adapt_c816.vh"

  integer vec, out, code, i, j, tests;
  reg [15:0] diff;
  reg [1023:0] vecname, outname;

  task need;
    input integer got;
    begin
      if (got != 1) begin
        $display("invalid line %0d in the vectors", tests + 1);
        $fatal(1);
      end
    end
  endtask

  initial begin
    if (!$value$plusargs("vec=%s", vecname) || !$value$plusargs("out=%s", outname)) begin
      $display("missing +vec= and +out=");
      $fatal(1);
    end
    vec = $fopen(vecname, "r");
    out = $fopen(outname, "w");
    if (vec == 0 || out == 0) begin
      $display("cannot open the vector file or the result file");
      $fatal(1);
    end
    running = 1'b0;
    nwritten = 0;
    tests = 0;
    repeat (2) @(posedge clk);
    @(negedge clk) rst = 1'b0;

    code = $fscanf(vec, "%h", opcode);
    while (code == 1) begin
      for (i = 0; i < 10; i = i + 1) need($fscanf(vec, "%h", ini[i]));
      for (i = 0; i < 10; i = i + 1) need($fscanf(vec, "%h", fin[i]));
      need($fscanf(vec, "%h", expcyc));
      need($fscanf(vec, "%h", nr));
      if (nr > MAXRAM) need(0);
      for (i = 0; i < nr; i = i + 1) begin
        need($fscanf(vec, "%h", ra[i]));
        need($fscanf(vec, "%h", rv[i]));
      end
      need($fscanf(vec, "%h", nf));
      if (nf > MAXRAM) need(0);
      for (i = 0; i < nf; i = i + 1) begin
        need($fscanf(vec, "%h", fa[i]));
        need($fscanf(vec, "%h", fv[i]));
      end
      need($fscanf(vec, "%h", nc));
      if (nc > MAXCYC) need(0);
      for (i = 0; i < nc; i = i + 1) begin
        need($fscanf(vec, "%h", ck[i]));
        need($fscanf(vec, "%h", ca[i]));
        need($fscanf(vec, "%h", cv[i]));
      end

      // prepare between two rising edges
      @(negedge clk);
      for (i = 0; i < nr; i = i + 1) mem[ra[i][23:0]] = rv[i][7:0];
      load_state;
      nwritten = 0;
      running = 1'b1;
      run_instruction;
      running = 1'b0;

      diff = state_diff(1'b0);
      diff[F_TIME] = timeout;
      diff[F_BUS] = bus_bad;
      diff[F_ILL] = illegal;
      for (i = 0; i < nf; i = i + 1)
        if (mem[fa[i][23:0]] !== fv[i][7:0]) diff[F_RAM] = 1'b1;
      for (i = 0; i < nf; i = i + 1) expected[fa[i][23:0]] = 1'b1;
      for (j = 0; j < nwritten; j = j + 1)
        if (expected[written[j]] !== 1'b1) diff[F_STRAY] = 1'b1;
      for (i = 0; i < nf; i = i + 1) expected[fa[i][23:0]] = 1'bx;
      $fdisplay(out, "%02h %0d %h %0d %0d", opcode[7:0], ini[9][0], diff, count, expcyc);

      for (i = 0; i < nr; i = i + 1) mem[ra[i][23:0]] = 8'hxx;
      for (i = 0; i < nf; i = i + 1) mem[fa[i][23:0]] = 8'hxx;
      for (j = 0; j < nwritten; j = j + 1) mem[written[j]] = 8'hxx;

      // after a hang, start again from reset
      if (timeout) begin
        @(negedge clk) rst = 1'b1;
        @(negedge clk) rst = 1'b0;
      end
      tests = tests + 1;
      code = $fscanf(vec, "%h", opcode);
    end
    $fclose(vec);
    $fclose(out);
    $display("CPU test bench: %0d vectors run", tests);
    if (tests == 0) $fatal(1);
    $finish;
  end
endmodule
