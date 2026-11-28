#!/usr/bin/env python3
"""mutation_check.py - verifica che il collaudo scopra davvero errori: introduce guasti
nell'RTL (in memoria) e controlla che run_tests.py fallisca per ognuno.
Esce con errore se anche un solo guasto non viene rilevato o se un modello non si trova.
The faults run in parallel (run_tests.jobs(): SIM_JOBS, or one for each processor). Each fault of
--cpu and --ppu has its own folder build/mut/<cpu|ppu>/<number>. The lines come out in the order
of the lists."""
import os, sys, io, contextlib, shutil, subprocess
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ppu_regs_run, ppu_run, run_tests, vsim

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
    ('c816_core', "wire ext_on = ext_en && !r_e;", "wire ext_on = ext_en;", "WDM attivo anche in emulazione"),
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


# Faults in the PPU (rtl/ppu/): (module, original text, faulty text, description).
# They run with Icarus Verilog on the benches of the PPU: option --ppu.
PPU_MUTANTS = [
    ('ppu_timing', "wire long_dot = ((hdot == 9'd323) || (hdot == 9'd327)) && !short_line;",
     "wire long_dot = 1'b0;", "no long dots"),
    ('ppu_timing', "!pal && !interlace && field && (vcnt == 9'd240)", "!pal && !interlace && (vcnt == 9'd240)",
     "short line in every frame"),
    ('ppu_timing', "wire extra = interlace && !field;", "wire extra = (interlace || pal) && !field;",
     "PAL with 313 lines without interlace"),
    ('ppu_timing', "overscan ? 9'd240 : 9'd225", "overscan ? 9'd240 : 9'd224", "vertical blank at line 224"),
    ('ppu_timing', "pal && interlace && field && (vcnt == 9'd311)", "1'b0", "no long line in PAL with interlace"),
    ('ppu_timing', "(hdot >= 9'd274)", "(hdot >= 9'd256)", "horizontal blank starts at dot 256"),
    ('ppu_math', "bright <= s_inidisp[3:0];", "bright <= s_inidisp[3:0] + 4'd1;", "brightness off by one"),
    ('ppu_math', "s_inidisp[7] ? 15'd0 : colour_in", "colour_in", "forced blank ignored"),
    ('ppu_prio', "default: index = 8'd0;", "default: index = 8'd1;", "backdrop taken from CGRAM word 1"),
    ('ppu_cgram', "cgadd <= wdata;\n      half <= 1'b0;", "cgadd <= wdata;", "$2121 keeps the half word"),
    ('ppu_cgram', "else cgadd <= cgadd + 8'd1;", "else cgadd <= cgadd;", "CGRAM address does not advance"),
    ('ppu_cgram', "wire commit = wr_data && half && !rst;", "wire commit = wr_data && !rst;",
     "CGRAM written without the byte latch"),
    ('ppu_regs', ".load((w_vaddr || r_vstep) && blank)", ".load(r_vstep && blank)", "no VRAM prefetch"),
    ('ppu_regs', "2'd1: vaddr = {vsel[14:8], vsel[4:0], vsel[7:5]};",
     "2'd1: vaddr = {vsel[14:8], vsel[5:0], vsel[7:6]};", "wrong VRAM remap in mode 1"),
    ('ppu_regs', ".we_l(w_vlow && blank)", ".we_l(w_vlow)", "VRAM write accepted in the active display"),
    ('ppu_regs', "            ophct_byte <= 1'b0;\n            opvct_byte <= 1'b0;\n", "",
     "$213F keeps the counter flip-flops"),
    ('ppu_regs', "if (oam_restart) oam_addr", "if (1'b0) oam_addr", "no OAM reload at the vertical blank"),
    ('ppu_regs', "bg1hofs <= {wdata[1:0], bgofs_latch[7:3], bghofs_latch[2:0]};",
     "bg1hofs <= {wdata[1:0], bgofs_latch};", "horizontal scroll without its own latch"),
    ('ppu_regs', "wire [23:0] product = uprod - fix_a - fix_b;", "wire [23:0] product = uprod;",
     "product without the signs"),
    ('ppu_oam', "if (we_high) high[addr[4:0]] <= wdata[7:0];", "if (we_high) high[addr[4:0]] <= wdata[15:8];",
     "wrong byte in the high sprite table"),
    ('ppu_math', "(hdot >= 9'd22) && (hdot <= 9'd277)", "(hdot >= 9'd23) && (hdot <= 9'd278)",
     "picture one dot late"),
    ('ppu_bgpix', "column_attr[4] ? sum[2:0] : (3'd7 - sum[2:0])", "(3'd7 - sum[2:0])", "horizontal mirror ignored"),
    ('ppu_bgfetch', "wire [2:0] row = mirror_y ? (3'd7 - py[2:0]) : py[2:0];", "wire [2:0] row = py[2:0];",
     "vertical mirror ignored"),
    ('ppu_bgfetch', "wire right = sc[0] && tx[5];", "wire right = 1'b0;", "64-wide map wraps at 32"),
    ('ppu_prio', "if (mode == 3'd1 && bg3_front && hi[2]) layer = 3'd3;\n    else if", "if",
     "layer 3 priority bit of mode 1 ignored"),
    ('ppu_bgfetch', "{9'd0, sub_x} + {5'd0, sub_y, 4'd0}", "{9'd0, sub_x} + {8'd0, sub_y, 1'b0}",
     "16 x 16 tile: wrong tile below"),
    ('ppu_prio', "{3'b001, pal2, num2[1:0]}", "{3'b000, pal2, num2[1:0]}", "mode 0: layer 2 without its colour offset"),
    ('ppu_bgpix', "assign opaque = (number != 4'd0);", "assign opaque = 1'b1;", "colour 0 is not transparent"),
    ('ppu_top', ".enable(ts[4:0])", ".enable(tm[4:0])", "sub screen uses the main screen enables"),
    ('ppu_bgpix', "wire [36:0] column = sum[3] ? then_ : now;", "wire [36:0] column = now;", "fine scroll stays in one tile"),
]
PPU_BENCHES = ['tb_ppu_timing']


def in_parallel(pool_class, work, items):
    """work(item) for each item, run_tests.jobs() at a time; the results in the order of the items."""
    pool = pool_class(max_workers=run_tests.jobs())
    try:
        yield from pool.map(work, items)
    finally:
        pool.shutdown(cancel_futures=True)      # after an error, do not start the other items


def fault_files(sources, mutant, folder):
    """Write the module with the fault in folder. Return (the new list of sources, folder)."""
    module, old, new, text = mutant
    paths = [p for p in sources if run_tests.module_name(p) == module]
    source = open(paths[0]).read() if paths else ''
    if old not in source:
        raise SystemExit("pattern not found for the fault: " + text)
    os.makedirs(folder, exist_ok=True)
    copy = os.path.join(folder, module + '.v')
    with open(copy, 'w') as f:
        f.write(source.replace(old, new, 1))
    return [copy if p == paths[0] else p for p in sources], folder


def ppu_bench_passes(files, bench, work):
    root = run_tests.ROOT
    os.makedirs(work, exist_ok=True)
    vvp = os.path.join(work, bench + '.vvp')
    subprocess.run([os.environ.get('IVERILOG', 'iverilog'), '-g2012', '-s', bench, '-o', vvp]
                   + files + [os.path.join(root, 'tb', bench + '.v')], check=True)
    # A bench that passes the time limit counts as a failure, so it can hide a fault that no test
    # finds. Keep the limit far above the time of a good run: some minutes alone, and about
    # 20 minutes when other programs also keep all the processors busy.
    try:
        done = subprocess.run([os.environ.get('VVP', 'vvp'), '-n', vvp], stdout=subprocess.DEVNULL,
                              timeout=3600, cwd=root)
    except subprocess.TimeoutExpired:
        return False
    return done.returncode == 0


def ppu_registers_pass(files, work):
    return not ppu_regs_run.run(files, quiet=True, work=os.path.join(work, 'regs'))


def ppu_fault_found(fault, module, scene_files):
    """Run the scenes and the benches on one fault until a test fails; the test that probably
    finds a fault of `module` runs first. All the work is in this process and in this folder."""
    files, work = fault

    def scenes():
        return not ppu_run.run(files, quiet=True, work=os.path.join(work, 'ppu'), all_patterns=False,
                               workers=1, scenes=scene_files)

    def registers():
        return ppu_registers_pass(files, work)

    timing = [(lambda b=b: ppu_bench_passes(files, b, work)) for b in PPU_BENCHES]
    if module == 'ppu_timing':
        tests = timing + [registers, scenes]
    elif module in ('ppu_regs', 'ppu_cgram', 'ppu_vram', 'ppu_oam'):
        tests = [registers, scenes] + timing
    else:
        tests = [scenes, registers] + timing
    found = not all(test() for test in tests)      # all() stops at the first failure
    for name in ('ppu', 'regs'):                   # large dumps: do not keep one set for each fault
        shutil.rmtree(os.path.join(work, name), ignore_errors=True)
    return found


def run_ppu():
    root = run_tests.ROOT
    work = os.path.join(root, 'build', 'mut', 'ppu')
    clean_work = os.path.join(work, 'clean')
    sources = [os.path.join(root, p) for p in run_tests.RTL]
    faults = [fault_files(sources, m, os.path.join(work, '%02d' % n)) for n, m in enumerate(PPU_MUTANTS)]
    # made once, here: the processes below only read the files of the generated scenes
    scene_files = ppu_run.scene_files()
    scene_jobs = ppu_run.scene_jobs(sources, os.path.join(clean_work, 'ppu'), scenes=scene_files,
                                    all_patterns=False)

    # One pool of processes for everything (the model of the scenes is Python). The tests without
    # any fault go first in the queue; the faults start as soon as a process is free.
    pool = ProcessPoolExecutor(max_workers=run_tests.jobs())
    try:
        benches = [pool.submit(ppu_bench_passes, sources, b, clean_work) for b in PPU_BENCHES]
        registers = pool.submit(ppu_registers_pass, sources, clean_work)
        scenes = [pool.submit(ppu_run.one_scene, job) for job in scene_jobs]
        results = [pool.submit(ppu_fault_found, fault, m[0], scene_files)
                   for fault, m in zip(faults, PPU_MUTANTS)]
        # no line about a fault before all the tests without a fault pass (a scene result is
        # (name, lines, patterns, problems))
        if (any(f.result()[3] for f in scenes) or not registers.result()
                or not all(f.result() for f in benches)):
            print("ERROR: a test fails without any fault")
            return 1
        missed = 0
        for m, result in zip(PPU_MUTANTS, results):
            found = result.result()
            missed += not found
            print("%-8s %s" % ('FOUND' if found else 'MISSED', m[3]), flush=True)
    finally:
        pool.shutdown(cancel_futures=True)      # after an error, do not start the other tests
    print("PPU: %d faults of %d missed" % (missed, len(PPU_MUTANTS)))
    return 1 if missed else 0


def cpu_bench(sources, work, vectors):
    """Compile the CPU test bench with these sources; return the number of failing vectors."""
    root = run_tests.ROOT
    vvp, result = os.path.join(work, 'tb.vvp'), os.path.join(work, 'results.txt')
    subprocess.run([os.environ.get('IVERILOG', 'iverilog'), '-g2012', '-s', 'tb_cpu', '-I',
                    os.path.join(root, 'tb'), '-o', vvp] + sources + [os.path.join(root, 'tb', 'tb_cpu.v')],
                   check=True)
    # tb_cpu keeps 128 characters of a file name: give it names relative to the root
    subprocess.run([os.environ.get('VVP', 'vvp'), '-n', vvp, '+vec=' + os.path.relpath(vectors, root),
                    '+out=' + os.path.relpath(result, root)], check=True, stdout=subprocess.DEVNULL, cwd=root)
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
    work = os.path.join(root, 'build', 'mut', 'cpu')
    vectors = os.path.join(work, 'vectors.txt')
    clean_work = os.path.join(work, 'clean')
    os.makedirs(clean_work, exist_ok=True)
    subprocess.run([sys.executable, os.path.join(root, 'sim', 'cpu_vectors.py'), vectors, str(CPU_CASES)],
                   check=True, stdout=subprocess.DEVNULL)
    sources = [os.path.join(root, p) for p in run_tests.RTL]
    faults = [fault_files(sources, m, os.path.join(work, '%02d' % n)) for n, m in enumerate(CPU_MUTANTS)]
    clean = cpu_bench(sources, clean_work, vectors)
    if clean or not interrupt_bench(sources, clean_work):
        print("ERROR: a test fails without any fault (%d vectors)" % clean)
        return 1

    def check(fault):
        """One fault: (number of failures, the text about the test that failed)."""
        faulty, folder = fault
        failed = cpu_bench(faulty, folder, vectors)
        how = "%d vectors" % failed
        if not failed and not interrupt_bench(faulty, folder):
            failed, how = 1, "interrupt test"
        return failed, how

    missed = 0
    # threads: the work is in the processes of iverilog and vvp
    for m, (failed, how) in zip(CPU_MUTANTS, in_parallel(ThreadPoolExecutor, check, faults)):
        missed += failed == 0
        print("%-8s %s (%s)" % ('FOUND' if failed else 'MISSED', m[3], how), flush=True)
    print("new core: %d faults of %d missed" % (missed, len(CPU_MUTANTS)))
    return 1 if missed else 0


def mutated_sources(mutated):
    """The text of all RTL sources, with the fault of one entry of MUTANTS."""
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
    return srcs


def run(mutated):
    srcs = mutated_sources(mutated)
    run_tests.load_sim = lambda: vsim.Sim(srcs, 'snes_plus_top')
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = run_tests.main()
    return rc, buf.getvalue()


def run_system():
    for m in MUTANTS:
        mutated_sources(m)                     # stop at once if a pattern is not there
    bad = 0
    # processes: the Python simulator does all its work in Python
    for m, (rc, out) in zip(MUTANTS, in_parallel(ProcessPoolExecutor, run, MUTANTS)):
        status = 'RILEVATO' if rc != 0 else 'NON RILEVATO'
        if rc == 0:
            bad += 1
        print("%-13s %s" % (status, m[3]), flush=True)
    print("%d mutanti su %d non rilevati" % (bad, len(MUTANTS)))
    return 0 if bad == 0 else 1


if __name__ == '__main__':
    if sys.argv[1:] == ['--cpu']:
        sys.exit(run_cpu())
    if sys.argv[1:] == ['--ppu']:
        sys.exit(run_ppu())
    sys.exit(run_system())
