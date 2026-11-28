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
    ('c816_alu', "c = w16 ? s16[16] : s8[8];", "c = 1'b0;", "carry ADC sempre 0"),
    ('c816_core', "(r_p[arg[2:0]] == arg[3])", "(r_p[arg[2:0]] != arg[3])", "salti condizionati invertiti"),
    ('c816_ext', "wire [31:0] prod = {16'h0000, a} * {16'h0000, x};", "wire [31:0] prod = {16'h0000, a} + {16'h0000, x};", "WDM MUL somma invece di moltiplicare"),
    ('s_cpu_5a22', "3'd1: boff = {7'd0, dpat[0]};", "3'd1: boff = 8'd0;", "DMA modo 1 senza alternanza dei registri B"),
    ('s_cpu_5a22', "if (rddiv[0]) rdmpy <= rdmpy + alu_shift[15:0];", "if (rddiv[1]) rdmpy <= rdmpy + alu_shift[15:0];", "moltiplicatore 5A22 errato"),
    ('s_cpu_5a22', "rddiv <= {rddiv[14:0], div_fits};", "rddiv <= {rddiv[14:0], 1'b0};", "divisore 5A22 errato"),
    ('c816_ext', "quo <= {quo[14:0], fits};", "quo <= {quo[14:0], 1'b0};", "divisore di WDM DIV errato"),
    ('c816_seq', "|| (hold == 2'd3) || ext_busy;", "|| (hold == 2'd3);", "WDM DIV non attende il divisore"),
    ('c816_ext', "wire [15:0] fix_x = (mul_signed && x[15]) ? a : 16'h0000;", "wire [15:0] fix_x = 16'h0000;", "MULS ignora il segno di X"),
    ('c816_ext', "wire [15:0] rem_s = (div_signed && a[15]) ? (16'h0000 - rem) : rem;", "wire [15:0] rem_s = rem;", "DIVS resto senza segno"),
    ('c816_ext', "a_out = quo_s; y_out = rem_s; f_v = div_over;", "a_out = quo_s; y_out = rem_s;", "DIVS senza V nel traboccamento"),
    ('c816_ext', "if (sub == 8'h09) acc <= {y, a};", "if (sub == 8'h09) acc <= {a, y};", "MACLD scambia le due meta'"),
    ('wram', "2'd0: port_addr <= port_addr + 17'd1;", "2'd0: ;", "porta WRAM: scrittura senza auto-incremento"),
    ('wram', "if (is_data && rd) port_addr <= port_addr + 17'd1;", "", "porta WRAM: lettura senza auto-incremento"),
    ('c816_core', "load_ret ? ({ah, al} + 16'd1)", "load_ret ? ({ah, al})", "RTS senza +1"),
    ('s_cpu_5a22', ".ext_en(ext_en), .nmi", ".ext_en(1'b1), .nmi", "WDM attivo anche in modalita' SNES"),
    ('c816_seq', "if ((t == 4'd1) && !imp) illegal <= 1'b1;", "if (t == 4'd1) illegal <= 1'b1;", "segnale di opcode non implementato sempre acceso"),
    ('ext_regs', "assign enhanced = (mode == 8'd2);", "assign enhanced = (mode != 8'd0);", "estensioni attive anche in modalita' accelerata"),
]

# Faults in the new core (rtl/cpu/): (module, original text, faulty text, description).
# They run with Icarus Verilog on the CPU test bench and our own vectors: option --cpu.
# The vectors check the registers, the memory, the cycle count, and each bus cycle.
CPU_MUTANTS = [
    ('c816_core', "5'd14: begin p_we = 1'b1; p_val = r_p | dl_by; end",
     "5'd14: begin p_we = 1'b1; p_val = r_p | (dl_by & 8'hF7); end", "SEP does not set the D flag"),
    ('c816_regs', "if (!s_open) s_n[15:8] = 8'h01;", "", "high byte of S not held at 01 in emulation mode"),
    ('c816_alu', "c = w16 ? s16[16] : s8[8];", "c = 1'b0;", "carry of ADC, SBC, CMP always 0"),
    ('c816_core', "load_ret ? ({ah, al} + 16'd1)", "load_ret ? ({ah, al})", "RTS and RTL without +1"),
    ('c816_regs', "x_n[15:8] = 8'h00;", "", "high byte of X kept with an 8-bit index"),
    ('c816_addr', "al[7] ? 8'hFF : 8'h00", "8'h00", "branch offset without sign"),
    ('c816_addr', "eff = {dbr, ah, al} + {8'h00, x};", "eff = {dbr, ah, al} + {16'h0000, x[7:0]};",
     "absolute,X ignores the high byte of X"),
    ('c816_core', ".xcarry(xcarry || !r_p[4])", ".xcarry(1'b1)", "absolute,X dummy cycle never skipped"),
    ('c816_core', "wire load_br = (pcop == 4'd4) || ((pcop == 4'd3) && commit);",
     "wire load_br = (pcop == 4'd4) || (pcop == 4'd3);", "taken branch loads PC one cycle early"),
    ('c816_seq', "((skip == 3'd3) && dlz)", "((skip == 3'd3) && 1'b0)",
     "direct page: extra cycle also when D is aligned"),
    ('c816_addr', "wire wrap = e && (d[7:0] == 8'h00);", "wire wrap = 1'b0;",
     "direct page does not stay in the page in emulation mode"),
    ('c816_addr', "wire [23:0] eff1 = bank0 ? {8'h00, eff_low1} : eff_next;", "wire [23:0] eff1 = eff_next;",
     "second byte of direct page data leaves bank 0"),
    ('c816_addr', "4'd4: eff = {dbr, ah, al} + {8'h00, y};", "4'd4: eff = {dbr, ah, al} + {8'h00, x};",
     "absolute,Y uses X"),
    ('c816_addr', "5'd15: addr = {8'h00, lp2};", "5'd15: addr = {8'h00, dp0_next};",
     "long pointer reads the wrong bank byte"),
    ('c816_addr', "5'd17: addr = {8'h00, sr1};", "5'd17: addr = {8'h00, sr0};",
     "(sr,S),Y reads the wrong pointer byte"),
    ('c816_alu', "4'd13: begin r = w16 ? {ci, a[15:1]} : {8'd0, ci, a[7:1]};",
     "4'd13: begin r = w16 ? {1'b0, a[15:1]} : {9'd0, a[7:1]};", "ROR ignores the carry"),
    ('c816_alu', "test = ((op == 4'd14) || (op == 4'd15)) ? (a & b) : r;", "test = r;",
     "TSB and TRB set Z from the result"),
    ('c816_seq', "((bus == 3'd6) && e);", "((bus == 3'd6) && 1'b0);",
     "emulation mode: no write in the modify cycle"),
    ('c816_regs', "if (!s_open) s_n[15:8] = 8'h01;", "s_n[15:8] = 8'h01;",
     "wide stack instructions wrap in page 1"),
    ('c816_core', "wire load_back = (pcop == 4'd10) && (r_a != 16'd0);", "wire load_back = 1'b0;",
     "block move does not repeat"),
    ('c816_core', "wire f_v = is_wdm ? ext_f_v : is_bit ? bit_v : alu_v;",
     "wire f_v = is_wdm ? ext_f_v : alu_v;", "BIT does not take V from memory"),
    ('c816_addr', "5'd23: addr = {pbr, absx};", "5'd23: addr = {8'h00, absx};",
     "(abs,X) jump table read from bank 0"),
    ('c816_alu', "wire k0 = sub ? q0[4] : (q0 > 5'd9);", "wire k0 = q0[4];", "decimal ADC without digit adjust"),
    ('c816_alu', "v = (sa == sb) && (sa != (dm ? dsign : (w16 ? r[15] : r[7])));",
     "v = (sa == sb) && (sa != (w16 ? r[15] : r[7]));", "decimal V taken after the last correction"),
    ('c816_core', "take_irq <= irq && !irq_mask && !is_int_seq;", "take_irq <= irq && !is_int_seq;",
     "IRQ ignores the I flag"),
    ('c816_core', "take_irq <= irq && !irq_mask && !is_int_seq;", "take_irq <= irq && !irq_mask;",
     "a second IRQ is taken before the handler runs"),
    ('c816_core', "wire [7:0] pbr_next = (pcop == 4'd11) ? 8'h00 : ba_by;", "wire [7:0] pbr_next = ba_by;",
     "interrupt keeps the program bank"),
    ('c816_core', "4'd14: wbyte = (r_e && hw_int) ? (r_p & 8'hEF) : r_p;", "4'd14: wbyte = r_p;",
     "emulation IRQ pushes the B flag"),
    ('c816_core', "else if (cyc_end && fetch_int && take_nmi) nmi_pend <= 1'b0;", "",
     "NMI stays pending after it is taken"),
    ('c816_core', "wire wake = nmi_pend || irq;", "wire wake = nmi_pend;", "WAI does not end on IRQ"),
    ('c816_seq', "|| (hold == 2'd3)", "|| 1'b0", "STP does not stop"),
    ('s_cpu_5a22', ".nmi(nmi_flag && nmitimen[7])", ".nmi(1'b0)", "the vertical blank does not reach the NMI"),
]
CPU_CASES = 20   # vectors for each opcode and mode


def cpu_bench(sources, work, vectors):
    """Compile the CPU test bench with these sources; return the number of failing vectors."""
    root = run_tests.ROOT
    vvp, result = os.path.join(work, 'tb.vvp'), os.path.join(work, 'results.txt')
    subprocess.run([os.environ.get('IVERILOG', 'iverilog'), '-g2012', '-s', 'tb_cpu', '-I',
                    os.path.join(root, 'tb'), '-o', vvp] + sources + [os.path.join(root, 'tb', 'tb_cpu.v')],
                   check=True)
    subprocess.run([os.environ.get('VVP', 'vvp'), '-n', vvp, '+vec=' + vectors, '+out=' + result],
                   check=True, stdout=subprocess.DEVNULL)
    with open(result) as f:
        return sum(1 for line in f if line.split()[2].strip('0') != '')


def interrupt_bench(sources, work):
    """Compile and run the two interrupt benches with these sources; return True if both pass."""
    root = run_tests.ROOT
    for bench in ('tb_cpu_int', 'tb_snes_nmi'):
        vvp = os.path.join(work, bench + '.vvp')
        subprocess.run([os.environ.get('IVERILOG', 'iverilog'), '-g2012', '-s', bench, '-o', vvp]
                       + sources + [os.path.join(root, 'tb', bench + '.v')], check=True)
        try:
            done = subprocess.run([os.environ.get('VVP', 'vvp'), '-n', vvp], stdout=subprocess.DEVNULL,
                                  timeout=60, cwd=root)
        except subprocess.TimeoutExpired:
            return False
        if done.returncode != 0:
            return False
    return True


def run_cpu():
    root = run_tests.ROOT
    work = os.path.join(root, 'build', 'mut')
    os.makedirs(work, exist_ok=True)
    vectors = os.path.join(work, 'vectors.txt')
    subprocess.run([sys.executable, os.path.join(root, 'sim', 'cpu_vectors.py'), vectors, str(CPU_CASES)],
                   check=True, stdout=subprocess.DEVNULL)
    sources = [os.path.join(root, p) for p in run_tests.RTL]
    clean = cpu_bench(sources, work, vectors)
    if clean or not interrupt_bench(sources, work):
        print("ERROR: a test fails without any fault (%d vectors)" % clean)
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
        faulty = [copy if p == paths[0] else p for p in sources]
        failed = cpu_bench(faulty, work, vectors)
        how = "%d vectors" % failed
        if not failed and not interrupt_bench(faulty, work):
            failed, how = 1, "interrupt test"
        missed += failed == 0
        print("%-8s %s (%s)" % ('FOUND' if failed else 'MISSED', text, how))
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
