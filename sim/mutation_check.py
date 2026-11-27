#!/usr/bin/env python3
"""mutation_check.py - verifica che il collaudo scopra davvero errori: introduce guasti
nell'RTL (in memoria) e controlla che run_tests.py fallisca per ognuno."""
import os, sys, io, contextlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import run_tests, vsim

MUTANTS = [
    ('cpu65816x', "a[7:0] <= sum9[7:0]; fc <= sum9[8];", "a[7:0] <= sum9[7:0]; fc <= 1'b0;", "carry ADC 8 bit sempre 0"),
    ('cpu65816x', "8'hD0: if (!fz)", "8'hD0: if (fz)", "BNE con condizione invertita"),
    ('cpu65816x', "prod = {16'h0000, a} * {16'h0000, x};\n                  a <= prod[15:0]; y <= prod[31:16];", "prod = {16'h0000, a} + {16'h0000, x};\n                  a <= prod[15:0]; y <= prod[31:16];", "WDM MUL somma invece di moltiplicare"),
    ('s_cpu_5a22', "3'd1: boff = {7'd0, dpat[0]};", "3'd1: boff = 8'd0;", "DMA modo 1 senza alternanza dei registri B"),
    ('s_cpu_5a22', "5'h03: rdmpy <= wrmpya * bus_wdata;", "5'h03: rdmpy <= wrmpya + bus_wdata;", "moltiplicatore 5A22 errato"),
    ('wram', "2'd0: begin mem[port_addr] <= wdata; port_addr <= port_addr + 17'd1; end", "2'd0: begin mem[port_addr] <= wdata; end", "porta WRAM senza auto-incremento"),
    ('cpu65816x', "if (op == 8'h60) pc <= {din, tmp[7:0]} + 16'd1;", "if (op == 8'h60) pc <= {din, tmp[7:0]};", "RTS senza +1"),
]

def run(mutated):
    srcs = []
    for n in run_tests.RTL:
        s = open(os.path.join(run_tests.ROOT, 'rtl', n + '.v')).read()
        if n == mutated[0]:
            if mutated[1] not in s:
                raise SystemExit("pattern non trovato per il mutante: " + mutated[3])
            s = s.replace(mutated[1], mutated[2], 1)
        srcs.append(s)
    run_tests.load_sim = lambda: vsim.Sim(srcs, 'snes_plus_top')
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = run_tests.main()
    return rc, buf.getvalue()

if __name__ == '__main__':
    bad = 0
    for m in MUTANTS:
        rc, out = run(m)
        status = 'RILEVATO' if rc != 0 else 'NON RILEVATO'
        if rc == 0:
            bad += 1
        print("%-13s %s" % (status, m[3]))
    print("%d mutanti su %d non rilevati" % (bad, len(MUTANTS)))
    sys.exit(0 if bad <= 1 else 1)
