#!/usr/bin/env python3
"""ppu_ref.py - reference model of the PPU: from a scene to the pixel dump.

Written from the documented behaviour of the SNES, without looking at the Verilog. To solve a
difference, find which of the two is wrong (the rule of sim/cpu_ref.py).

What it does today (step P2): $2100 (forced blank, brightness), $2121 and $2122 (CGRAM), and the
backdrop colour (CGRAM word 0).
Timing rules of the scene player: the colour of a dot uses the registers as they are before the
writes of that dot. A write during dot H acts from dot H + 1.

Dump: one line for each screen line, 512 values "bbbbbgggggrrrrr:bright:layer". In a 256-wide mode
each pixel appears twice. layer: 0 backdrop, 7 forced blank."""
import os, sys
import ppu_scenes

FIRST_DOT, WIDTH = 22, 256
LAYER_BACKDROP, LAYER_BLANK = 0, 7


class Ppu:
    def __init__(self):
        self.inidisp = 0x80            # after reset: forced blank
        self.cgram = [0] * 256
        self.cg_addr = 0
        self.cg_low = None             # the first byte of a word, until the second one comes

    def write(self, addr, data):
        if addr == 0x2100:
            self.inidisp = data
        elif addr == 0x2121:
            self.cg_addr = data
            self.cg_low = None
        elif addr == 0x2122:
            if self.cg_low is None:
                self.cg_low = data
            else:
                self.cgram[self.cg_addr] = ((data & 0x7F) << 8) | self.cg_low
                self.cg_addr = (self.cg_addr + 1) & 0xFF
                self.cg_low = None

    def pixel(self):
        if self.inidisp & 0x80:
            return (0, self.inidisp & 15, LAYER_BLANK)
        return (self.cgram[0], self.inidisp & 15, LAYER_BACKDROP)


def render(scene, root=ppu_scenes.ROOT):
    """The lines of the dump of the compared frame."""
    ppu = Ppu()
    if 'cgram' in scene['loads']:
        words = open(os.path.join(root, scene['loads']['cgram'])).read().split()
        ppu.cgram[:len(words)] = [int(w, 16) & 0x7FFF for w in words]
    at = {}
    for v, h, a, d in scene['writes']:
        at.setdefault((v, h), []).append((a, d))
    last_visible = 224                 # overscan comes with step P10
    lines = []
    for frame in range(scene['compare'] + 1):
        for v in range(ppu_scenes.LINES[scene['region']]):
            row = []
            for h in range(ppu_scenes.DOTS):
                if 1 <= v <= last_visible and FIRST_DOT <= h < FIRST_DOT + WIDTH:
                    colour, bright, layer = ppu.pixel()
                    text = "%s:%x:%d" % (format(colour, '015b'), bright, layer)
                    row += [text, text]
                for a, d in at.get((v, h), []):
                    ppu.write(a, d)
            if row and frame == scene['compare']:
                lines.append(' '.join(row))
    return lines


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit("use: ppu_ref.py <scene.scn> <dump.out>")
    with open(sys.argv[2], 'w', newline='\n') as f:
        f.write('\n'.join(render(ppu_scenes.parse(sys.argv[1]))) + '\n')
