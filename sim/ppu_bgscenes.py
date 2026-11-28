#!/usr/bin/env python3
"""ppu_bgscenes.py - the background scenes of the PPU (step P4): 12 directed scenes and 40 random
ones, with a fixed seed. sim/ppu_run.py writes them in build/ppu/gen/ at each run; only their CRC
lists (tests/ppu/<name>.expect) are in the repository."""
import os, random

DOTS = 340
RANDOM_SCENES = 40


class Scene:
    def __init__(self, name):
        self.name = name
        self.vram = {}
        self.cgram = [0] * 256
        self.writes = []
        self.used = {}
        self.frames, self.compare = 1, 0
        self.cursor = 0                       # the next free place for a setup write in line 0

    def at(self, line, dot, address, data):
        """A bus write; moves on if the dot already has its two writes."""
        while self.used.get((line, dot), 0) >= 2:
            dot += 1
        assert dot < DOTS, (self.name, line, dot)
        self.used[line, dot] = self.used.get((line, dot), 0) + 1
        self.writes.append((line, dot, address, data & 0xFF))

    def set(self, address, *data):
        """A write in line 0, which the video part does not draw."""
        for d in data:
            self.at(0, self.cursor, address, d)
            self.cursor += 1

    def scroll(self, address, value, line=None, dot=None):
        """The two writes of a scroll register."""
        if line is None:
            self.set(address, value, value >> 8)
        else:
            self.at(line, dot, address, value)
            self.at(line, dot + 1, address, value >> 8)

    def save(self, directory, root):
        base = os.path.join(directory, self.name)
        relative = os.path.relpath(base, root).replace(os.sep, '/')
        with open(base + '.vram', 'w', newline='\n') as f:
            f.write(''.join('%04x %04x\n' % (a, w) for a, w in sorted(self.vram.items())))
        with open(base + '.cgram', 'w', newline='\n') as f:
            f.write(''.join('%04x\n' % c for c in self.cgram))
        out = ['# written by sim/ppu_bgscenes.py', 'region ntsc', 'load vram %s.vram' % relative,
               'load cgram %s.cgram' % relative]
        out += ['at %d %d w %04X %02X' % w for w in sorted(self.writes, key=lambda w: (w[0], w[1]))]
        out.append('frames %d compare %d' % (self.frames, self.compare))
        with open(base + '.scn', 'w', newline='\n') as f:
            f.write('\n'.join(out) + '\n')
        return base + '.scn'


# ---- pictures for the directed scenes ---------------------------------------------------------

SHAPES = (
    ('........',) * 8,                                                                 # 0 empty
    ('111111..', '11......', '11......', '11111...', '11......', '11......', '11......', '........'),
    ('33333333', '3......3', '3.2222.3', '3.2..2.3', '3.2..2.3', '3.2222.3', '3......3', '33333333'),
    ('1.......', '21......', '321.....', '.321....', '..321...', '...321..', '....321.', '.....321'),
    ('12121212', '21212121') * 4,
    ('........', '...33...', '..3333..', '.333333.', '.333333.', '..3333..', '...33...', '........'),
)


def tile_words(shape, depth, shift):
    """The words of a tile; `shift` moves the colour numbers up in a 4-bit tile."""
    rows = []
    for line in shape:
        rows.append([0 if c == '.' else int(c) + shift for c in line])
    words = []
    for pair in range(depth // 2):
        for row in rows:
            low = sum(((n >> (2 * pair)) & 1) << (7 - x) for x, n in enumerate(row))
            high = sum(((n >> (2 * pair + 1)) & 1) << (7 - x) for x, n in enumerate(row))
            words.append(low | (high << 8))
    return words


def colours():
    """256 colours: each group of 4 or 16 has its own hue, brighter with the number."""
    hues = ((31, 6, 4), (6, 28, 8), (8, 14, 31), (31, 26, 4), (28, 6, 28), (4, 28, 28), (31, 18, 6), (22, 22, 22))
    out = []
    for i in range(256):
        r, g, b = hues[(i // 4 + i // 32) % 8]
        k = (i % 4) + 1 + (i % 16) // 4
        out.append((r * k // 7 if k < 7 else r) | ((g * k // 7 if k < 7 else g) << 5)
                   | ((b * k // 7 if k < 7 else b) << 10))
    out[0] = 0x1C63                                           # backdrop: dark grey blue
    return out


TILE_BASE = (0x1000, 0x2000, 0x3000, 0x4000)
MAP_BASE = (0x0000, 0x0800, 0x5000, 0x6000)


def directed(name, mode, entry=None, maps=(0, 0, 0, 0), bgmode=None):
    """A scene with the same shapes in each layer; entry(n, tx, ty) gives a map entry."""
    s = Scene(name)
    s.cgram = colours()
    layers = 4 if mode == 0 else 3
    for n in range(layers):
        depth = 2 if mode == 0 or n == 2 else 4
        for t in range(64):                    # 64 tiles: the shapes repeat; 16 x 16 tiles use n+16
            words = tile_words(SHAPES[t % len(SHAPES)], depth, 4 * (t % 3) if depth == 4 else 0)
            for i, w in enumerate(words):
                s.vram[TILE_BASE[n] + t * depth * 4 + i] = w
        size = maps[n]
        screens = 1 + (size & 1) + (size >> 1) * (1 + (size & 1))
        for k in range(screens * 1024):
            screen = k // 1024
            tx = k % 32 + (32 if size & 1 and screen % 2 else 0)
            ty = (k % 1024) // 32 + (32 if screen >= 1 + (size & 1) else 0)
            s.vram[MAP_BASE[n] + k] = entry(n, tx, ty) if entry else default_entry(n, tx, ty)
    s.set(0x2100, 0x0F)
    s.set(0x2105, mode if bgmode is None else bgmode)
    for n in range(layers):
        s.set(0x2107 + n, (MAP_BASE[n] >> 10 << 2) | maps[n])
    s.set(0x210B, (TILE_BASE[0] >> 12) | (TILE_BASE[1] >> 12 << 4))
    s.set(0x210C, (TILE_BASE[2] >> 12) | (TILE_BASE[3] >> 12 << 4))
    for n in range(4):
        s.scroll(0x210D + 2 * n, 0)
        s.scroll(0x210E + 2 * n, 0)
    s.set(0x212C, (1 << layers) - 1)
    s.set(0x212D, 0)
    return s


def default_entry(n, tx, ty):
    """Layer n shows a diagonal band of tiles; the other places are empty."""
    if (tx + ty + 2 * n) % 8 >= 4 - n // 2:
        return 0
    tile = 1 + (tx + 2 * ty + n) % 5
    return tile | (((tx // 4 + n) & 7) << 10) | (((tx + ty) & 4) << 11)


def flip_entry(n, tx, ty):
    if (tx + ty * 3 + n) % 4:
        return 0
    return 1 + (tx // 2) % 5 | ((ty & 7) << 10) | (((tx >> 2) & 1) << 13) | ((tx & 3) << 14)


def directed_scenes():
    out = [directed('m0_basic', 0)]
    s = directed('m0_scroll', 0)
    for n, (h, v) in enumerate(((3, 5), (0x3FF, 0x3F9), (260, 13), (517, 1023))):
        s.scroll(0x210D + 2 * n, h)
        s.scroll(0x210E + 2 * n, v)
    out.append(s)
    out.append(directed('m0_flip_prio', 0, flip_entry))
    s = directed('m0_maps', 0, lambda n, tx, ty: 1 + (tx // 32 + 2 * (ty // 32) + n) % 5 if (tx + ty) % 3 == n % 3
                 else 0, maps=(1, 2, 3, 0))
    for n, (h, v) in enumerate(((200, 0), (0, 200), (300, 300), (400, 400))):
        s.scroll(0x210D + 2 * n, h)
        s.scroll(0x210E + 2 * n, v)
    out.append(s)
    s = directed('m0_tile16', 0, flip_entry, bgmode=0xF0)
    s.scroll(0x210D, 5)
    s.scroll(0x2110, 11)
    out.append(s)
    s = directed('m0_screens', 0)
    for line in range(1, 224, 14):
        s.at(line, 290, 0x212C, line // 14)
        s.at(line, 292, 0x212D, 15 - line // 14)
    out.append(s)
    out.append(directed('m1_basic', 1))
    s = directed('m1_scroll', 1)
    for line in range(0, 224):                       # a new horizontal scroll in each line
        s.scroll(0x210D, (line // 2) % 17 + line // 8, line, 285)
        s.scroll(0x2112, line // 3, line, 300)
    out.append(s)
    s = directed('m1_bg3prio', 1, flip_entry, bgmode=0x09)
    for line in range(31, 224, 32):
        s.at(line, 290, 0x2105, 0x01 if (line // 32) % 2 == 0 else 0x09)
    out.append(s)
    s = directed('m1_tile16', 1, flip_entry, bgmode=0x71)
    s.scroll(0x210D, 9)
    s.scroll(0x210E, 250)
    s.scroll(0x2111, 1021)
    out.append(s)
    s = directed('m1_midline', 1)
    rng = random.Random(4)
    for line in range(4, 224, 3):
        dot = 22 + rng.randrange(250)
        kind = line % 4
        if kind == 0:
            s.at(line, dot, 0x212C, rng.randrange(8))
        elif kind == 1:
            s.at(line, dot, 0x2100, rng.randrange(16) | (0x80 if line % 24 == 5 else 0))
            s.at(line, dot + 20, 0x2100, 0x0F)
        elif kind == 2:
            s.at(line, dot, 0x2121, rng.choice((0, 1, 2, 17)))
            s.at(line, dot + 1, 0x2122, rng.randrange(256))
            s.at(line, dot + 2, 0x2122, rng.randrange(128))
        else:
            s.at(line, dot, 0x212D, rng.randrange(8))
    out.append(s)
    # the same picture as m1_basic, with the memories written through the bus in the vertical blank
    s = directed('m1_bus', 1)
    words, s.vram = sorted(s.vram.items()), {}
    s.frames, s.compare = 2, 1
    picked = [(a, w) for a, w in words if w]
    s.set(0x2115, 0x80)
    slot, last = 226 * 2 * DOTS, None            # two writes in each dot
    for address, word in picked:
        group = [] if address == last else [(0x2116, address), (0x2117, address >> 8)]
        group += [(0x2118, word), (0x2119, word >> 8)]
        for register, data in group:
            s.at(slot // (2 * DOTS), slot % (2 * DOTS) // 2, register, data)
            slot += 1
        last = address + 1
    assert slot < 262 * 2 * DOTS, slot
    out.append(s)
    return out


def random_scene(k):
    rng = random.Random(40000 + k)
    s = Scene('bg_random%02d' % (k + 1))
    for a in range(0x8000):
        s.vram[a] = 0 if rng.random() < 0.2 else rng.getrandbits(16)
    s.cgram = [rng.getrandbits(15) for _ in range(256)]
    mode = k & 1

    def fetch_value(register):
        if register == 0x2105:
            return (rng.getrandbits(8) & 0xF8) | mode
        return rng.getrandbits(8)

    s.set(0x2100, 0x0F)
    for register in (0x2105, 0x2107, 0x2108, 0x2109, 0x210A, 0x210B, 0x210C):
        s.set(register, fetch_value(register))
    for n in range(4):
        s.scroll(0x210D + 2 * n, rng.getrandbits(10))
        s.scroll(0x210E + 2 * n, rng.getrandbits(10))
    s.set(0x212C, rng.randrange(1, 16))
    s.set(0x212D, rng.randrange(16))
    for _ in range(120):                     # registers that the fetch reads: outside dots 6 to 277
        line, dot = rng.randrange(0, 224), rng.choice((rng.randrange(280, 336), rng.randrange(0, 3)))
        if rng.random() < 0.6:
            s.scroll(0x210D + rng.randrange(8), rng.getrandbits(10), line, dot)
        else:
            register = rng.choice((0x2105, 0x2107, 0x2108, 0x2109, 0x210A, 0x210B, 0x210C))
            s.at(line, dot, register, fetch_value(register))
    for _ in range(150):                     # registers that each dot reads: anywhere
        line, dot = rng.randrange(1, 225), rng.randrange(0, 330)
        x = rng.random()
        if x < 0.35:
            s.at(line, dot, rng.choice((0x212C, 0x212D)), rng.randrange(32))
        elif x < 0.55:
            s.at(line, dot, 0x2100, rng.randrange(16) | (0x80 if rng.random() < 0.1 else 0))
        else:
            s.at(line, dot, 0x2121, rng.randrange(256))
            s.at(line, dot + 1, 0x2122, rng.getrandbits(8))
            s.at(line, dot + 2, 0x2122, rng.getrandbits(8))
    for line, dot, register, _ in s.writes:  # the rule of the scenes: the fetch reads stable values
        assert not (0x2105 <= register <= 0x2114 and 1 <= line <= 224 and 6 <= dot < 278), (s.name, line, dot)
    return s


def generate(directory, root):
    """Write all scenes; the paths of the .scn files, the directed ones first."""
    os.makedirs(directory, exist_ok=True)
    scenes = directed_scenes() + [random_scene(k) for k in range(RANDOM_SCENES)]
    return [s.save(directory, root) for s in scenes]
