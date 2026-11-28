#!/usr/bin/env python3
"""run_tests.py - assembla tests/test_program.asm, lo carica nella ROM simulata,
esegue il sistema SNES+ e confronta WRAM e VRAM con tests/test_program.expect."""
import os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import asm
import vsim

PROGRAM = os.path.join(ROOT, 'tests', 'test_program.asm')
EXPECT = os.path.join(ROOT, 'tests', 'test_program.expect')
# nome della memoria nel file .expect -> percorso gerarchico sotto snes_plus_top
MEMS = {'wram': 'u_wram.mem', 'vram_l': 'u_ppu.u_regs.u_vram.vram_l',
        'vram_h': 'u_ppu.u_regs.u_vram.vram_h'}
MAX_CYCLES = 200000

def rtl_files():
    """Percorsi (relativi alla radice) elencati in rtl/files.f."""
    out = []
    for line in open(os.path.join(ROOT, 'rtl', 'files.f')):
        line = line.split('#')[0].strip()
        if line:
            out.append(line)
    return out

RTL = rtl_files()

def module_name(path):
    return os.path.splitext(os.path.basename(path))[0]

def load_expect():
    out = []
    for n, line in enumerate(open(EXPECT), 1):
        f = line.split('#')[0].split()
        if not f:
            continue
        if len(f) != 3 or f[0] not in MEMS:
            raise SystemExit("%s:%d: riga non valida" % (EXPECT, n))
        out.append((f[0], int(f[1], 16), int(f[2], 16)))
    return out

def load_sim():
    srcs = [open(os.path.join(ROOT, p)).read() for p in RTL]
    return vsim.Sim(srcs, 'snes_plus_top')

def main():
    img, labels = asm.assemble(open(PROGRAM).read())
    expect = load_expect()
    sim = load_sim()
    rom = sim.array('u_rom.mem')
    rom[:len(img)] = list(img)
    sim.poke('rst', 1)
    for _ in range(4):
        sim.tick()
    sim.poke('rst', 0)

    done = labels['done']
    t0 = time.time()
    cycles = 0
    hits = 0
    while cycles < MAX_CYCLES:
        sim.tick()
        cycles += 1
        if sim.peek('dbg_pc') in (done, done + 2):
            hits += 1
            if hits > 8:
                break
    else:
        print("TIMEOUT: pc=%04X" % sim.peek('dbg_pc'))
        return 1
    print("programma terminato in %d cicli (%.1f s di simulazione)" % (cycles, time.time() - t0))

    arrays = {k: sim.array(v) for k, v in MEMS.items()}
    fails = 0
    for mem, addr, exp in expect:
        got = arrays[mem][addr]
        if got != exp:
            print("FAIL %s[%04X] = %02X, atteso %02X" % (mem, addr, got, exp))
            fails += 1
    print("%d/%d controlli superati" % (len(expect) - fails, len(expect)))
    if sim.peek('dbg_illegal'):
        print("FAIL: the program used an opcode that the core does not implement")
        return 1
    return 1 if fails else 0

if __name__ == '__main__':
    sys.exit(main())
