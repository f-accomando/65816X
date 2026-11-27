#!/usr/bin/env python3
"""mutation_check.py - verifica che il collaudo scopra davvero errori: introduce guasti
nell'RTL (in memoria) e controlla che run_tests.py fallisca per ognuno.
Esce con errore se anche un solo guasto non viene rilevato o se un modello non si trova."""
import os, sys, io, contextlib, subprocess
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import run_tests, vsim

# (modulo, testo originale, testo guasto, descrizione)
MUTANTS = [
    ('cpu65816x', "a[7:0] <= sum9[7:0]; fc <= sum9[8];", "a[7:0] <= sum9[7:0]; fc <= 1'b0;", "carry ADC 8 bit sempre 0"),
    ('cpu65816x', "8'hD0: if (!fz)", "8'hD0: if (fz)", "BNE con condizione invertita"),
    ('cpu65816x', "prod = {16'h0000, a} * {16'h0000, x};\n                  a <= prod[15:0]; y <= prod[31:16];", "prod = {16'h0000, a} + {16'h0000, x};\n                  a <= prod[15:0]; y <= prod[31:16];", "WDM MUL somma invece di moltiplicare"),
    ('s_cpu_5a22', "3'd1: boff = {7'd0, dpat[0]};", "3'd1: boff = 8'd0;", "DMA modo 1 senza alternanza dei registri B"),
    ('s_cpu_5a22', "5'h03: rdmpy <= wrmpya * bus_wdata;", "5'h03: rdmpy <= wrmpya + bus_wdata;", "moltiplicatore 5A22 errato"),
    ('wram', "2'd0: port_addr <= port_addr + 17'd1;", "2'd0: ;", "porta WRAM: scrittura senza auto-incremento"),
    ('wram', "if (is_data && rd) port_addr <= port_addr + 17'd1;", "", "porta WRAM: lettura senza auto-incremento"),
    ('cpu65816x', "if (op == 8'h60) pc <= {din, tmp[7:0]} + 16'd1;", "if (op == 8'h60) pc <= {din, tmp[7:0]};", "RTS senza +1"),
    ('cpu65816x', "8'h42: if (ext_en) begin", "8'h42: begin", "WDM attivo anche in modalita' SNES"),
    ('ext_regs', "assign enhanced = (mode == 8'd2);", "assign enhanced = (mode != 8'd0);", "estensioni attive anche in modalita' accelerata"),
]

# Faults in the new core (rtl/cpu/): (module, original text, faulty text, description).
# They run with Icarus Verilog on the CPU test bench and our own vectors: option --cpu.
# These vectors carry no cycle counts, so each fault must change a register or the memory.
CPU_MUTANTS = [
    ('c816_core', "5'd14: begin p_we = 1'b1; p_val = r_p | dl_by; end",
     "5'd14: begin p_we = 1'b1; p_val = r_p | (dl_by & 8'hF7); end", "SEP does not set the D flag"),
    ('c816_regs', "s_n[15:8] = 8'h01;", "", "high byte of S not held at 01 in emulation mode"),
    ('c816_alu', "c = w16 ? s16[16] : s8[8];", "c = 1'b0;", "carry of ADC, SBC, CMP always 0"),
    ('c816_core', "load_rts ? ({ah, al} + 16'd1)", "load_rts ? ({ah, al})", "RTS without +1"),
    ('c816_regs', "x_n[15:8] = 8'h00;", "", "high byte of X kept with an 8-bit index"),
    ('c816_addr', "al[7] ? 8'hFF : 8'h00", "8'h00", "branch offset without sign"),
    ('c816_addr', "eff = {dbr, ah, al} + {8'h00, x};", "eff = {dbr, ah, al} + {16'h0000, x[7:0]};",
     "absolute,X ignores the high byte of X"),
]
CPU_CASES = 20   # vectors for each opcode and mode


def cpu_bench(sources, work, vectors):
    """Compile the CPU test bench with these sources; return the number of failing vectors."""
    root = run_tests.ROOT
    vvp, result = os.path.join(work, 'tb.vvp'), os.path.join(work, 'results.txt')
    subprocess.run([os.environ.get('IVERILOG', 'iverilog'), '-g2012', '-s', 'tb_cpu', '-DC816', '-I',
                    os.path.join(root, 'tb'), '-o', vvp] + sources + [os.path.join(root, 'tb', 'tb_cpu.v')],
                   check=True)
    subprocess.run([os.environ.get('VVP', 'vvp'), '-n', vvp, '+vec=' + vectors, '+out=' + result],
                   check=True, stdout=subprocess.DEVNULL)
    with open(result) as f:
        return sum(1 for line in f if line.split()[2].strip('0') != '')


def run_cpu():
    root = run_tests.ROOT
    work = os.path.join(root, 'build', 'mut')
    os.makedirs(work, exist_ok=True)
    vectors = os.path.join(work, 'vectors.txt')
    subprocess.run([sys.executable, os.path.join(root, 'sim', 'cpu_vectors.py'), vectors, str(CPU_CASES)],
                   check=True, stdout=subprocess.DEVNULL)
    sources = [os.path.join(root, p) for p in run_tests.RTL]
    clean = cpu_bench(sources, work, vectors)
    if clean:
        print("ERROR: %d vectors fail without any fault" % clean)
        return 1
    missed = 0
    for module, old, new, text in CPU_MUTANTS:
        paths = [p for p in sources if run_tests.module_name(p) == module]
        source = open(paths[0]).read() if paths else ''
        if old not in source:
            raise SystemExit("pattern not found for the fault: " + text)
        copy = os.path.join(work, module + '.v')
        with open(copy, 'w') as f:
            f.write(source.replace(old, new, 1))
        failed = cpu_bench([copy if p == paths[0] else p for p in sources], work, vectors)
        missed += failed == 0
        print("%-8s %s (%d vectors)" % ('FOUND' if failed else 'MISSED', text, failed))
    print("new core: %d faults of %d missed" % (missed, len(CPU_MUTANTS)))
    return 1 if missed else 0


def run(mutated):
    srcs = []
    found = False
    for p in run_tests.RTL:
        s = open(os.path.join(run_tests.ROOT, p)).read()
        if run_tests.module_name(p) == mutated[0]:
            if mutated[1] not in s:
                raise SystemExit("modello non trovato per il mutante: " + mutated[3])
            s = s.replace(mutated[1], mutated[2], 1)
            found = True
        srcs.append(s)
    if not found:
        raise SystemExit("modulo %s non presente in rtl/files.f" % mutated[0])
    run_tests.load_sim = lambda: vsim.Sim(srcs, 'snes_plus_top')
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = run_tests.main()
    return rc, buf.getvalue()

if __name__ == '__main__':
    if sys.argv[1:] == ['--cpu']:
        sys.exit(run_cpu())
    bad = 0
    for m in MUTANTS:
        rc, out = run(m)
        status = 'RILEVATO' if rc != 0 else 'NON RILEVATO'
        if rc == 0:
            bad += 1
        print("%-13s %s" % (status, m[3]))
    print("%d mutanti su %d non rilevati" % (bad, len(MUTANTS)))
    sys.exit(0 if bad == 0 else 1)
