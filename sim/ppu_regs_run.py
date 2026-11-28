#!/usr/bin/env python3
"""ppu_regs_run.py - random register accesses: the PPU registers (Icarus Verilog) against the
reference model. sim/ppu_ref.py writes the accesses and the expected results; tb/tb_ppu_regs.v
plays them."""
import os, subprocess, sys
import ppu_ref
import run_tests

ROOT = run_tests.ROOT
BUILD = os.path.join(ROOT, 'build', 'ppu_regs')
SEEDS = (2100, 2115, 213)
ACCESSES = 10000


def run(sources=None, quiet=False, work=BUILD):
    """Return the number of seeds that fail."""
    os.makedirs(work, exist_ok=True)
    sources = sources or [os.path.join(ROOT, p) for p in run_tests.RTL]
    vvp = os.path.join(work, 'tb_ppu_regs.vvp')
    subprocess.run([os.environ.get('IVERILOG', 'iverilog'), '-g2012', '-s', 'tb_ppu_regs', '-o', vvp]
                   + sources + [os.path.join(ROOT, 'tb', 'tb_ppu_regs.v')], check=True)
    fails = 0
    for seed in SEEDS:
        cmd = os.path.join(work, 'regs%d.cmd' % seed)
        with open(cmd, 'w', newline='\n') as f:
            f.write('\n'.join(ppu_ref.register_stimulus(seed, ACCESSES)) + '\n')
        done = subprocess.run([os.environ.get('VVP', 'vvp'), '-n', vvp, '+cmd=' + cmd],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=600)
        if not quiet:
            print("seed %d: %s" % (seed, done.stdout.strip()))
        if done.returncode != 0:
            fails += 1
            if quiet:
                break
    return fails


if __name__ == '__main__':
    fails = run()
    print("PPU registers: %s" % ('PASS' if not fails else '%d FAILED' % fails))
    sys.exit(1 if fails else 0)
