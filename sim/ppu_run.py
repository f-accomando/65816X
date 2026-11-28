#!/usr/bin/env python3
"""ppu_run.py - run the PPU scenes in the RTL (Icarus Verilog) and in the reference model: the
scenes of tests/ppu/ and the background scenes that sim/ppu_bgscenes.py makes in build/ppu/gen/.

For each scene: the RTL dump must equal the model dump, and each line of the model dump must have
the CRC32 of tests/ppu/<name>.expect. The pictures are in build/ppu/<name>.png.
Option --update writes the .expect files from the model: check the difference before you keep it."""
import os, subprocess, sys, zlib
from concurrent.futures import ProcessPoolExecutor
import ppu_bgscenes, ppu_cmp, ppu_ref, ppu_scenes
import run_tests

ROOT = ppu_scenes.ROOT
BUILD = os.path.join(ROOT, 'build', 'ppu')
# the first scene also runs with these patterns of mce (0 each clk, 1 each second clk, 2 random)
MCE_PATTERNS = (1, 2)


_files = []


def scene_files():
    """The scenes of the repository, then the generated ones (made once in each run of Python)."""
    if not _files:
        _files.extend(_scene_files())
    return _files


def _scene_files():
    committed = sorted(os.path.join(ppu_scenes.DIR, f) for f in os.listdir(ppu_scenes.DIR) if f.endswith('.scn'))
    return committed + ppu_bgscenes.generate(os.path.join(BUILD, 'gen'), ROOT)


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
    if 'vram' in scene['loads']:
        words = ppu_scenes.read_vram(os.path.join(ROOT, scene['loads']['vram']))
        for half, shift in (('l', 0), ('h', 8)):
            path = os.path.join(work, '%s.vram%s' % (name, half))
            with open(path, 'w') as f:
                f.write(''.join('@%x %02x\n' % (a, (w >> shift) & 255) for a, w in words))
            args.append('+vram%s=%s' % (half, path))
    done = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=600)
    if done.returncode != 0 or not os.path.exists(out):
        return None, done.stdout.strip()
    return ppu_cmp.read_dump(out), ''


def expect_path(scene_path):
    return os.path.join(ppu_scenes.DIR, os.path.basename(scene_path)[:-len('.scn')] + '.expect')


def crcs(lines):
    return ['%08x' % zlib.crc32(line.encode()) for line in lines]


def one_scene(job):
    """Model and RTL for one scene: (name, number of lines, patterns, problems)."""
    path, vvp, work, update, patterns = job
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
    return name, len(model), len(patterns), problems


def run(sources=None, update=False, quiet=False, work=BUILD, all_patterns=True):
    """Return the number of failing scenes. In quiet mode, stop soon after the first one."""
    os.makedirs(work, exist_ok=True)
    sources = sources or [os.path.join(ROOT, p) for p in run_tests.RTL]
    vvp = compile_bench(sources, work)
    # the first scene of the list, and one with backgrounds, also run with the other mce patterns
    jobs = []
    for path in scene_files():
        extra = all_patterns and os.path.basename(path) in ('backdrop_bright.scn', 'm1_midline.scn')
        jobs.append((path, vvp, work, update, (0,) + (MCE_PATTERNS if extra else ())))
    workers = os.cpu_count() or 1
    fails = 0
    with ProcessPoolExecutor(max_workers=workers) as pool:
        step = workers if quiet else len(jobs)         # quiet: stop between two groups
        for first in range(0, len(jobs), step):
            for name, lines, patterns, problems in pool.map(one_scene, jobs[first:first + step]):
                fails += bool(problems)
                if not quiet:
                    print("%-4s %s (%d lines, %d mce pattern%s)" % ('FAIL' if problems else 'ok', name, lines,
                                                                   patterns, 's' if patterns > 1 else ''))
                    for p in problems:
                        print("     " + p)
            if fails and quiet:
                break
    return fails


if __name__ == '__main__':
    fails = run(update='--update' in sys.argv[1:])
    print("PPU scenes: %s" % ('PASS' if not fails else '%d FAILED' % fails))
    sys.exit(1 if fails else 0)
