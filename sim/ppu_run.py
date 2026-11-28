#!/usr/bin/env python3
"""ppu_run.py - run the scenes of tests/ppu/ in the RTL (Icarus Verilog) and in the reference model.

For each scene: the RTL dump must equal the model dump, and each line of the model dump must have
the CRC32 of tests/ppu/<name>.expect. The pictures are in build/ppu/<name>.png.
Option --update writes the .expect files from the model: check the difference before you keep it."""
import os, subprocess, sys, zlib
import ppu_cmp, ppu_ref, ppu_scenes
import run_tests

ROOT = ppu_scenes.ROOT
BUILD = os.path.join(ROOT, 'build', 'ppu')
# the first scene also runs with these patterns of mce (0 each clk, 1 each second clk, 2 random)
MCE_PATTERNS = (1, 2)


def scene_files():
    return sorted(os.path.join(ppu_scenes.DIR, f) for f in os.listdir(ppu_scenes.DIR) if f.endswith('.scn'))


def compile_bench(sources, work):
    vvp = os.path.join(work, 'tb_ppu.vvp')
    subprocess.run([os.environ.get('IVERILOG', 'iverilog'), '-g2012', '-s', 'tb_ppu', '-o', vvp]
                   + sources + [os.path.join(ROOT, 'tb', 'tb_ppu.v')], check=True)
    return vvp


def run_rtl(vvp, scene, work, mce):
    name = scene['name']
    cmd = os.path.join(work, name + '.cmd')
    with open(cmd, 'w') as f:
        for w in scene['writes']:
            f.write("%d %d %x %x\n" % w)
    out = os.path.join(work, name + '.out')
    if os.path.exists(out):
        os.remove(out)
    args = [os.environ.get('VVP', 'vvp'), '-n', vvp, '+cmd=' + cmd, '+out=' + out, '+mce=%d' % mce,
            '+pal=%d' % (scene['region'] == 'pal'), '+frames=%d' % scene['frames'],
            '+compare=%d' % scene['compare']]
    if 'cgram' in scene['loads']:
        args.append('+cgram=' + os.path.join(ROOT, scene['loads']['cgram']))
    done = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=600)
    if done.returncode != 0 or not os.path.exists(out):
        return None, done.stdout.strip()
    return ppu_cmp.read_dump(out), ''


def expect_path(scene_path):
    return scene_path[:-len('.scn')] + '.expect'


def crcs(lines):
    return ['%08x' % zlib.crc32(line.encode()) for line in lines]


def run(sources=None, update=False, quiet=False, work=BUILD, all_patterns=True):
    """Return the number of failures."""
    os.makedirs(work, exist_ok=True)
    sources = sources or [os.path.join(ROOT, p) for p in run_tests.RTL]
    vvp = compile_bench(sources, work)
    fails = 0
    for i, path in enumerate(scene_files()):
        scene = ppu_scenes.parse(path)
        name = scene['name']
        model = ppu_ref.render(scene)
        if update:
            with open(expect_path(path), 'w', newline='\n') as f:
                f.write('\n'.join(crcs(model)) + '\n')
        problems = []
        try:
            expect = open(expect_path(path)).read().split()
        except OSError:
            expect = []
        if crcs(model) != expect:
            problems.append("the model does not give the CRC list of %s" % os.path.basename(expect_path(path)))
        model_dump = [line.split() for line in model]
        patterns = (0,) + (MCE_PATTERNS if i == 0 and all_patterns else ())
        wrong = os.path.join(work, name + '.rtl.png')
        if os.path.exists(wrong):
            os.remove(wrong)                       # from an earlier run
        for mce in patterns:
            rtl, error = run_rtl(vvp, scene, work, mce)
            if rtl is None:
                problems.append("mce %d: the simulation failed: %s" % (mce, error))
                continue
            diff = ppu_cmp.difference(rtl, model_dump)
            if diff:
                problems.append("mce %d: RTL against model: %s" % (mce, diff))
                ppu_cmp.picture(rtl, wrong)
        ppu_cmp.picture(model_dump, os.path.join(work, name + '.png'))
        fails += bool(problems)
        if not quiet:
            print("%-4s %s (%d lines, %d mce pattern%s)" % ('FAIL' if problems else 'ok', name, len(model),
                                                           len(patterns), 's' if len(patterns) > 1 else ''))
            for p in problems:
                print("     " + p)
        if problems and quiet:
            break                                  # one failing scene is enough for the mutation test
    return fails


if __name__ == '__main__':
    fails = run(update='--update' in sys.argv[1:])
    print("PPU scenes: %s" % ('PASS' if not fails else '%d FAILED' % fails))
    sys.exit(1 if fails else 0)
