// tb_cpu.v - banco di prova della sola CPU.
// Per ogni vettore: carica registri e memoria, esegue una istruzione, confronta lo stato finale.
// Uso: vvp tb_cpu.vvp +vec=<vettori> +out=<risultati>   (formato: vedi sim/cpu_vectors.py)
// Riga dei risultati: opcode, e iniziale, maschera dei campi diversi, cicli di clock, cicli attesi.
// Solo le funzioni load_state e state_diff conoscono i registri interni del core.
`timescale 1ns/1ns
module tb_cpu;
  localparam MAXRAM = 256;
  localparam MAXCLK = 200;
  // bit della maschera, nello stesso ordine di FIELDS in sim/cpu_score.py
  localparam F_PC = 0, F_S = 1, F_P = 2, F_A = 3, F_X = 4, F_Y = 5, F_DBR = 6, F_D = 7,
             F_PBR = 8, F_E = 9, F_RAM = 10, F_STRAY = 11, F_TIME = 12;

  reg clk = 1'b0;
  reg rst = 1'b1;
  wire [23:0] addr;
  wire rd, wr;
  wire [7:0] wdata;
  reg [7:0] din;
  wire [15:0] dbg_pc, dbg_a, dbg_x, dbg_y;

  cpu65816x dut (
    .clk(clk), .rst(rst), .halt(1'b0), .ext_en(1'b0),
    .addr(addr), .rd(rd), .wr(wr), .wdata(wdata), .din(din),
    .dbg_pc(dbg_pc), .dbg_a(dbg_a), .dbg_x(dbg_x), .dbg_y(dbg_y)
  );

  always #5 clk = ~clk;

  // memoria da 16 MB: il dato letto arriva il ciclo dopo, e solo se rd era attivo
  reg [7:0] mem [0:16777215];
  reg [23:0] written [0:MAXRAM-1];
  integer nwritten;
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

  // stato: 0 pc, 1 s, 2 p, 3 a, 4 x, 5 y, 6 dbr, 7 d, 8 pbr, 9 e
  reg [31:0] ini [0:9];
  reg [31:0] fin [0:9];
  reg [31:0] ra [0:MAXRAM-1], rv [0:MAXRAM-1];
  reg [31:0] fa [0:MAXRAM-1], fv [0:MAXRAM-1];
  reg [31:0] opcode, expcyc, nr, nf;

  task load_state;
    begin
      dut.pc = ini[0]; dut.s = ini[1];
      {dut.fn, dut.fv, dut.fm, dut.fx} = ini[2][7:4];
      {dut.fi, dut.fz, dut.fc} = ini[2][2:0];
      dut.a = ini[3]; dut.x = ini[4]; dut.y = ini[5];
      dut.db = ini[6]; dut.pb = ini[8]; dut.fe = ini[9][0];
      dut.acc = 32'd0; dut.op = 8'd0;
      dut.st = 4'd0; dut.ph = 1'b0; dut.n = 2'd0;
    end
  endtask

  // il core non ha ancora il registro D ne' il flag D: restano quelli iniziali e 0
  function [12:0] state_diff;
    input dummy;
    reg [7:0] p;
    begin
      p = {dut.fn, dut.fv, dut.fm, dut.fx, 1'b0, dut.fi, dut.fz, dut.fc};
      state_diff = 13'd0;
      if (dut.pc !== fin[0][15:0]) state_diff[F_PC] = 1'b1;
      if (dut.s !== fin[1][15:0]) state_diff[F_S] = 1'b1;
      if (p !== fin[2][7:0]) state_diff[F_P] = 1'b1;
      if (dut.a !== fin[3][15:0]) state_diff[F_A] = 1'b1;
      if (dut.x !== fin[4][15:0]) state_diff[F_X] = 1'b1;
      if (dut.y !== fin[5][15:0]) state_diff[F_Y] = 1'b1;
      if (dut.db !== fin[6][7:0]) state_diff[F_DBR] = 1'b1;
      if (ini[7] !== fin[7]) state_diff[F_D] = 1'b1;
      if (dut.pb !== fin[8][7:0]) state_diff[F_PBR] = 1'b1;
      if (dut.fe !== fin[9][0]) state_diff[F_E] = 1'b1;
    end
  endfunction

  integer vec, out, code, i, j, clocks, tests;
  reg [12:0] diff;
  reg found, timeout;
  reg [1023:0] vecname, outname;

  task need;
    input integer got;
    begin
      if (got != 1) begin
        $display("riga %0d dei vettori non valida", tests + 1);
        $fatal(1);
      end
    end
  endtask

  initial begin
    if (!$value$plusargs("vec=%s", vecname) || !$value$plusargs("out=%s", outname)) begin
      $display("mancano +vec= e +out=");
      $fatal(1);
    end
    vec = $fopen(vecname, "r");
    out = $fopen(outname, "w");
    if (vec == 0 || out == 0) begin
      $display("file dei vettori o dei risultati non apribile");
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

      // preparazione tra due fronti di salita
      @(negedge clk);
      for (i = 0; i < nr; i = i + 1) mem[ra[i][23:0]] = rv[i][7:0];
      load_state;
      nwritten = 0;
      running = 1'b1;

      // l'istruzione finisce quando il core torna al fetch (stato 0) dopo averlo lasciato
      clocks = 0;
      timeout = 1'b0;
      while (dut.st === 4'd0 && !timeout) begin
        @(posedge clk); #1; clocks = clocks + 1;
        if (clocks >= MAXCLK) timeout = 1'b1;
      end
      while (dut.st !== 4'd0 && !timeout) begin
        @(posedge clk); #1; clocks = clocks + 1;
        if (clocks >= MAXCLK) timeout = 1'b1;
      end
      running = 1'b0;

      diff = state_diff(1'b0);
      diff[F_TIME] = timeout;
      for (i = 0; i < nf; i = i + 1)
        if (mem[fa[i][23:0]] !== fv[i][7:0]) diff[F_RAM] = 1'b1;
      for (j = 0; j < nwritten; j = j + 1) begin
        found = 1'b0;
        for (i = 0; i < nf; i = i + 1)
          if (fa[i][23:0] == written[j]) found = 1'b1;
        if (!found) diff[F_STRAY] = 1'b1;
      end
      $fdisplay(out, "%02h %0d %h %0d %0d", opcode[7:0], ini[9][0], diff, clocks, expcyc);

      for (i = 0; i < nr; i = i + 1) mem[ra[i][23:0]] = 8'hxx;
      for (i = 0; i < nf; i = i + 1) mem[fa[i][23:0]] = 8'hxx;
      for (j = 0; j < nwritten; j = j + 1) mem[written[j]] = 8'hxx;

      // dopo un blocco si riparte dal reset
      if (timeout) begin
        @(negedge clk) rst = 1'b1;
        @(negedge clk) rst = 1'b0;
      end
      tests = tests + 1;
      code = $fscanf(vec, "%h", opcode);
    end
    $fclose(vec);
    $fclose(out);
    $display("banco CPU: %0d vettori eseguiti", tests);
    if (tests == 0) $fatal(1);
    $finish;
  end
endmodule
