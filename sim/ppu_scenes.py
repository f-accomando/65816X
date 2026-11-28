#!/usr/bin/env python3
"""ppu_scenes.py - the test scenes of the PPU: the file format and the generator.

A scene (tests/ppu/<name>.scn):
  region ntsc | pal
  load cgram <file>              256 lines, one 15-bit word (hexadecimal) in each
  at <line> <dot> w <addr> <data>   a bus write to a register, during that dot, in each frame
  frames <n> compare <k>         run n frames, compare frame k (the first one is 0)

Run this file to write the scenes again (fixed seed). Then check the difference of the files."""
import os, random, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, 'tests', 'ppu')
LINES = {'ntsc': 262, 'pal': 312}
DOTS = 340
MAX_WRITES_PER_DOT = 2       # a dot lasts at least 4 clocks; the player writes in its clocks 1 and 2


def parse(path):
    s = {'name': os.path.splitext(os.path.basename(path))[0], 'region': 'ntsc', 'loads': {},
         'writes': [], 'frames': 2, 'compare': 1}
    per_dot = {}
    for n, line in enumerate(open(path), 1):
        f = line.split('#')[0].split()
        if not f:
            continue
        try:
            if f[0] == 'region' and f[1] in LINES:
                s['region'] = f[1]
            elif f[0] == 'load' and f[1] == 'cgram':
                s['loads'][f[1]] = f[2]
            elif f[0] == 'at' and f[3] == 'w':
                v, h, a, d = int(f[1]), int(f[2]), int(f[4], 16), int(f[5], 16)
                if not (0 <= v < LINES[s['region']] and 0 <= h < DOTS and 0x2100 <= a <= 0x213F
                        and 0 <= d <= 255):
                    raise ValueError
                per_dot[v, h] = per_dot.get((v, h), 0) + 1
                if per_dot[v, h] > MAX_WRITES_PER_DOT:
                    raise ValueError
                s['writes'].append((v, h, a, d))
            elif f[0] == 'frames' and f[2] == 'compare':
                s['frames'], s['compare'] = int(f[1]), int(f[3])
                if not 0 <= s['compare'] < s['frames']:
                    raise ValueError
            else:
                raise ValueError
        except (ValueError, IndexError):
            raise SystemExit("%s:%d: bad line" % (path, n))
    s['writes'].sort(key=lambda w: (w[0], w[1]))     # stable: two writes of a dot keep their order
    return s


# ---- generator --------------------------------------------------------------------------------

def write_scene(name, comment, cgram, writes):
    os.makedirs(DIR, exist_ok=True)
    out = ["# " + comment, "# written by sim/ppu_scenes.py", "region ntsc"]
    if cgram is not None:
        with open(os.path.join(DIR, name + '.cgram.hex'), 'w', newline='\n') as f:
            f.write(''.join('%04x\n' % c for c in cgram))
        out.append("load cgram tests/ppu/%s.cgram.hex" % name)
    out += ["at %d %d w %04X %02X" % w for w in writes]
    out.append("frames 2 compare 1")
    with open(os.path.join(DIR, name + '.scn'), 'w', newline='\n') as f:
        f.write('\n'.join(out) + '\n')


def colour_writes(v, h, index, colour):
    """Set one CGRAM word through the bus: address, low byte, high byte (2 writes in each dot)."""
    return [(v, h, 0x2121, index), (v, h + 1, 0x2122, colour & 0xFF), (v, h + 1, 0x2122, colour >> 8)]


def scene_bright(rng):
    """Brightness 0-15 and forced blank, changed at given lines; CGRAM loaded by the back door."""
    cgram = [rng.randrange(0x8000) for _ in range(256)]
    cgram[0] = 0x021F                                  # orange: red 31, green 16, blue 0
    w = [(0, 10, 0x2100, 0x0F)]
    for level in range(16):
        w.append((8 + 12 * level, 300, 0x2100, level))      # in the horizontal blank
    w += [(200, 300, 0x2100, 0x8F), (206, 300, 0x2100, 0x0F)]        # forced blank for 6 lines
    for k, dot in enumerate((22, 23, 100, 149, 150, 276, 277, 278)):  # in the middle of a line
        w.append((210 + k, dot, 0x2100, 0x04 if k % 2 else 0x0B))
    w += [(219, 128, 0x2100, 0x80), (219, 192, 0x2100, 0x0F)]
    w += [(223, 339, 0x2100, 0x07), (230, 0, 0x2100, 0x0F)]
    write_scene('backdrop_bright', "brightness and forced blank over a fixed backdrop", cgram, w)


def scene_bus(rng):
    """CGRAM loaded through the bus: latch, increment, wrap, and a new address in a half word."""
    w = [(225, 10, 0x2100, 0x8F)]
    # three words from $FF: the address goes to $00, then $01
    w += [(226, 10, 0x2121, 0xFF), (226, 12, 0x2122, 0x11), (226, 12, 0x2122, 0x22),
          (226, 14, 0x2122, 0x1F), (226, 14, 0x2122, 0x00),            # word 0: red
          (226, 16, 0x2122, 0xE0), (226, 16, 0x2122, 0x03)]            # word 1: green
    w += [(0, 10, 0x2100, 0x0F)]
    # a new colour in the horizontal blank each 8 lines
    for i in range(1, 27):
        w += colour_writes(8 * i, 290, 0, rng.randrange(0x8000))
    # a single byte, then a new address: the byte is lost
    w += [(216, 290, 0x2121, 0x00), (216, 292, 0x2122, 0x55)]
    w += colour_writes(217, 290, 0, 0x7C00)
    # bit 15 of the second byte is not part of the word
    w += colour_writes(220, 290, 0, 0xFFE0)
    # a change in the middle of a line
    w += colour_writes(222, 120, 0, 0x03FF)
    # leave word 0 red for the first lines of the next frame
    w += colour_writes(240, 10, 0, 0x001F)
    write_scene('backdrop_bus', "backdrop loaded and changed through $2121 and $2122", None, w)


def scene_random(rng, k):
    """Random writes to $2100, $2121, and $2122 at random places."""
    cgram = [rng.randrange(0x8000) for _ in range(256)]
    w, used = [(0, 10, 0x2100, 0x0F)], {(0, 10): 1}
    for _ in range(600):
        v = rng.randrange(262) if rng.random() < 0.2 else rng.randrange(1, 225)
        h = rng.randrange(DOTS)
        if used.get((v, h), 0) >= MAX_WRITES_PER_DOT:
            continue
        used[v, h] = used.get((v, h), 0) + 1
        a = rng.choice((0x2100, 0x2121, 0x2122, 0x2122, 0x2122))
        if a == 0x2100:
            d = rng.randrange(16) | (0x80 if rng.random() < 0.15 else 0)
        elif a == 0x2121:
            d = rng.choice((0, 0, 0, 1, 255, rng.randrange(256)))
        else:
            d = rng.randrange(256)
        w.append((v, h, a, d))
    w.sort(key=lambda x: (x[0], x[1]))
    write_scene('backdrop_random%d' % k, "random register writes, seed fixed", cgram, w)


def main():
    rng = random.Random(65816)
    scene_bright(rng)
    scene_bus(rng)
    for k in range(1, 4):
        scene_random(rng, k)
    print("scenes written in", DIR)
    return 0


if __name__ == '__main__':
    sys.exit(main())
