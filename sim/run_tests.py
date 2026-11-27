#!/usr/bin/env python3
"""run_tests.py - assembla tests/test_program.asm, lo carica nella ROM simulata,
esegue il sistema SNES+ e verifica WRAM, VRAM e registri."""
import os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import asm
import vsim

RTL = ['cpu65816x', 's_cpu_5a22', 'ppu_stub', 'apu_stub', 'wram', 'cart_rom', 'ext_regs', 'snes_plus_top']

def load_sim():
    srcs = [open(os.path.join(ROOT, 'rtl', n + '.v')).read() for n in RTL]
    return vsim.Sim(srcs, 'snes_plus_top')

def main():
    img, labels = asm.assemble(open(os.path.join(ROOT, 'tests', 'test_program.asm')).read())
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
    while cycles < 200000:
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

    w = sim.array('u_wram.mem')
    vl = sim.array('u_ppu.vram_l')
    vh = sim.array('u_ppu.vram_h')
    expect_wram = {
        0x0000: 0x35, 0x0001: 0x12,                  # T1
        0x0002: 0x00, 0x0003: 0x01,                  # T2
        0x0004: 0x0F, 0x0005: 0x00,                  # T3
        0x0006: 0xEF, 0x0007: 0xBE,                  # T4
        0x0008: 0x3F, 0x0009: 0x00,                  # T5 mul
        0x0020: 0x8E, 0x0021: 0x06,                  # T5 div
        0x001A: 0x11, 0x001B: 0x22, 0x001C: 0x33, 0x001D: 0x44,   # T7
        0x000A: 0x40, 0x000B: 0x23, 0x000C: 0x01, 0x000D: 0x00,   # T8 MUL
        0x000E: 0x49, 0x000F: 0x02, 0x0010: 0x01, 0x0011: 0x00,   # T8 DIV
        0x0012: 0x00, 0x0013: 0x00, 0x0014: 0x02, 0x0015: 0x00,   # T8 MAC
        0x0016: 0x58, 0x0017: 0xAA, 0x0018: 0xBB, 0x0019: 0xCC,   # T9
        0x001E: 0x5A, 0x001F: 0xA5,                  # T9 pila
        0x0022: 0xCD, 0x0023: 0xAB,                  # T10
        0x0024: 0x77,                                # T11
        0x0102: 0xCD, 0x0103: 0xAB,                  # mirror WRAM
        0x0026: 0x00, 0x0027: 0x00,                  # X intatto dopo RTS
        0x0030: 0xAA, 0x0031: 0xBB,                  # T12 porta WRAM
    }
    fails = 0
    for addr, exp in sorted(expect_wram.items()):
        got = w[addr]
        if got != exp:
            print("FAIL WRAM[%04X] = %02X, atteso %02X" % (addr, got, exp))
            fails += 1
    for i, (l, h) in enumerate(((0x11, 0x22), (0x33, 0x44))):
        if (vl[i], vh[i]) != (l, h):
            print("FAIL VRAM[%d] = %02X/%02X, atteso %02X/%02X" % (i, vl[i], vh[i], l, h))
            fails += 1
    total = len(expect_wram) + 2
    print("%d/%d controlli superati" % (total - fails, total))
    return 1 if fails else 0

if __name__ == '__main__':
    sys.exit(main())
