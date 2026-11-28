#!/usr/bin/env python3
"""ppu_ref.py - reference model of the PPU.

Written from the documented behaviour of the SNES, without looking at the Verilog. To solve a
difference, find which of the two is wrong (the rule of sim/cpu_ref.py). The sources and the points
where they differ are in docs/design/ppu-plan.md, section 1.5.

Two uses:
  ppu_ref.py <scene.scn> <dump.out>         the picture of a scene (today: the backdrop only)
  ppu_ref.py --regs <seed> <count> <file>   random register accesses with the expected results,
                                            for tb/tb_ppu_regs.v

Timing rules of the scene player: the colour of a dot uses the registers as they are before the
writes of that dot. A write during dot H acts from dot H + 1.
Dump: one line for each screen line, 512 values "bbbbbgggggrrrrr:bright:layer". In a 256-wide mode
each pixel appears twice. layer: 0 backdrop, 7 forced blank."""
import os, random, sys
import ppu_scenes

FIRST_DOT, WIDTH = 22, 256
LAYER_BACKDROP, LAYER_BLANK = 0, 7
PPU1_VERSION, PPU2_VERSION = 1, 3
# write-only addresses that read back the data latch of the PPU1
READ_MDR1 = {0x2100 + x * 0x10 + n for x in range(3) for n in (4, 5, 6, 8, 9, 10)}

# the registers that tb_ppu_regs compares, in the order of its numbers
REGISTERS = ('inidisp obsel oam_reload oam_prio bgmode mosaic bg1sc bg2sc bg3sc bg4sc bg12nba bg34nba '
             'bg1hofs bg2hofs bg3hofs bg4hofs bg1vofs bg2vofs bg3vofs bg4vofs m7hofs m7vofs vmain vmadd '
             'm7sel m7a m7b m7c m7d m7x m7y w12sel w34sel wobjsel wh0 wh1 wh2 wh3 wbglog wobjlog '
             'tm ts tmw tsw cgwsel cgadsub col_r col_g col_b setini oam_addr cg_addr').split()
SIMPLE = {0x01: 'obsel', 0x05: 'bgmode', 0x06: 'mosaic', 0x07: 'bg1sc', 0x08: 'bg2sc', 0x09: 'bg3sc',
          0x0A: 'bg4sc', 0x0B: 'bg12nba', 0x0C: 'bg34nba', 0x15: 'vmain', 0x1A: 'm7sel',
          0x23: 'w12sel', 0x24: 'w34sel', 0x25: 'wobjsel', 0x26: 'wh0', 0x27: 'wh1', 0x28: 'wh2',
          0x29: 'wh3', 0x2A: 'wbglog', 0x2B: 'wobjlog', 0x2C: 'tm', 0x2D: 'ts', 0x2E: 'tmw',
          0x2F: 'tsw', 0x30: 'cgwsel', 0x31: 'cgadsub', 0x33: 'setini'}
MODE7 = {0x1B: ('m7a', 0xFFFF), 0x1C: ('m7b', 0xFFFF), 0x1D: ('m7c', 0xFFFF), 0x1E: ('m7d', 0xFFFF),
         0x1F: ('m7x', 0x1FFF), 0x20: ('m7y', 0x1FFF)}


def signed(value, bits):
    return value - (1 << bits) if value >> (bits - 1) else value


def remap(address, mode):
    """The word that a VRAM access uses: the low 8, 9, or 10 bits rotate left by 3."""
    if mode:
        n = 7 + mode
        low = address & ((1 << n) - 1)
        low = ((low << 3) | (low >> (n - 3))) & ((1 << n) - 1)
        address = (address & ~((1 << n) - 1)) | low
    return address & 0x7FFF


class Ppu:
    def __init__(self):
        for name in REGISTERS:
            setattr(self, name, 0)
        self.inidisp = 0x80                    # after reset: forced blank
        self.m7a, self.mul_b = 0xFFFF, 0xFF    # documented power-up values: the product reads 1
        self.cgram = [0] * 256
        self.cg_low = 0                        # the first byte of a word, until the second one comes
        self.cg_byte = 0                       # one flip-flop for $2122 and $213B
        self.vram = [0] * 0x8000
        self.vram_buffer = 0
        self.oam = [0] * 544
        self.oam_latch = 0
        self.bgofs_latch = self.bghofs_latch = self.m7_latch = 0
        self.ophct = self.opvct = 0x1FF
        self.ophct_byte = self.opvct_byte = 0
        self.latched = 0
        self.mdr1 = self.mdr2 = 0
        # position, given by the timing unit
        self.v = self.h = self.field = self.pal = 0

    # ---- position ----
    def in_vblank(self):
        return self.v >= 225                   # overscan comes with step P10

    def position(self, v, h, field=0, pal=0):
        was = self.in_vblank()
        self.v, self.h, self.field, self.pal = v, h, field, pal
        if self.in_vblank() and not was and not self.inidisp & 0x80:
            self.reload_oam()

    def blank(self):
        return bool(self.inidisp & 0x80) or self.in_vblank()

    # ---- helpers ----
    def reload_oam(self):
        self.oam_addr = (self.oam_reload & 0x1FF) << 1

    @staticmethod
    def oam_index(a):
        return a if a < 0x200 else 0x200 | (a & 0x1F)

    def vram_load(self):
        if self.blank():                       # in the active display the buffer keeps its value
            self.vram_buffer = self.vram[remap(self.vmadd, (self.vmain >> 2) & 3)]

    def vram_step(self):
        self.vmadd = (self.vmadd + (1, 32, 128, 128)[self.vmain & 3]) & 0xFFFF

    # ---- writes ----
    def write(self, addr, data):
        r = addr - 0x2100
        if r in SIMPLE:
            setattr(self, SIMPLE[r], data)
        elif r == 0x00:
            if self.v == 225 and self.inidisp & 0x80:      # first line of the vertical blank
                self.reload_oam()
            self.inidisp = data
        elif r == 0x02:
            self.oam_reload = (self.oam_reload & 0x100) | data
            self.reload_oam()
        elif r == 0x03:
            self.oam_reload = ((data & 1) << 8) | (self.oam_reload & 0xFF)
            self.oam_prio = data >> 7
            self.reload_oam()
        elif r == 0x04:
            a = self.oam_addr
            if not a & 1:
                self.oam_latch = data
            if self.blank():                   # a write in the active display is lost (approximation)
                if a >= 0x200:
                    self.oam[self.oam_index(a)] = data
                elif a & 1:
                    self.oam[a - 1], self.oam[a] = self.oam_latch, data
            self.oam_addr = (a + 1) & 0x3FF
        elif 0x0D <= r <= 0x14:
            bg = (r - 0x0D) // 2 + 1
            if (r - 0x0D) % 2 == 0:
                value = (data << 8) | (self.bgofs_latch & ~7) | (self.bghofs_latch & 7)
                setattr(self, 'bg%dhofs' % bg, value & 0x3FF)
                self.bgofs_latch = self.bghofs_latch = data
            else:
                setattr(self, 'bg%dvofs' % bg, ((data << 8) | self.bgofs_latch) & 0x3FF)
                self.bgofs_latch = data
            if r in (0x0D, 0x0E):
                setattr(self, 'm7hofs' if r == 0x0D else 'm7vofs', ((data << 8) | self.m7_latch) & 0x1FFF)
                self.m7_latch = data
        elif r in (0x16, 0x17):
            if r == 0x16:
                self.vmadd = (self.vmadd & 0xFF00) | data
            else:
                self.vmadd = (data << 8) | (self.vmadd & 0xFF)
            self.vram_load()
        elif r in (0x18, 0x19):
            high = r - 0x18
            if self.blank():
                a = remap(self.vmadd, (self.vmain >> 2) & 3)
                if high:
                    self.vram[a] = (self.vram[a] & 0x00FF) | (data << 8)
                else:
                    self.vram[a] = (self.vram[a] & 0xFF00) | data
            if self.vmain >> 7 == high:
                self.vram_step()
        elif r in MODE7:
            name, mask = MODE7[r]
            setattr(self, name, ((data << 8) | self.m7_latch) & mask)
            self.m7_latch = data
            if r == 0x1C:
                self.mul_b = data
        elif r == 0x21:
            self.cg_addr = data
            self.cg_byte = 0
        elif r == 0x22:
            if self.cg_byte == 0:
                self.cg_low = data
            else:                              # accepted at any time (approximation)
                self.cgram[self.cg_addr] = ((data & 0x7F) << 8) | self.cg_low
                self.cg_addr = (self.cg_addr + 1) & 0xFF
            self.cg_byte ^= 1
        elif r == 0x32:
            if data & 0x20:
                self.col_r = data & 31
            if data & 0x40:
                self.col_g = data & 31
            if data & 0x80:
                self.col_b = data & 31

    # ---- reads ----
    def read(self, addr, gate=1):
        """gate: bit 7 of $4201, which lets the counters latch."""
        r = addr - 0x2100
        if r in (0x34, 0x35, 0x36):
            product = signed(self.m7a, 16) * signed(self.mul_b, 8) & 0xFFFFFF
            self.mdr1 = (product >> (8 * (r - 0x34))) & 0xFF
            return self.mdr1
        if r == 0x37:
            if gate:
                self.ophct, self.opvct, self.latched = self.h, self.v, 1
            return 0                            # the open bus of the processor: not modelled
        if r == 0x38:
            self.mdr1 = self.oam[self.oam_index(self.oam_addr)]
            self.oam_addr = (self.oam_addr + 1) & 0x3FF
            return self.mdr1
        if r in (0x39, 0x3A):
            high = r - 0x39
            self.mdr1 = (self.vram_buffer >> (8 * high)) & 0xFF
            if self.vmain >> 7 == high:
                self.vram_load()               # from the old address
                self.vram_step()
            return self.mdr1
        if r == 0x3B:
            word = self.cgram[self.cg_addr]
            if self.cg_byte == 0:
                self.mdr2 = word & 0xFF
            else:
                self.mdr2 = (self.mdr2 & 0x80) | (word >> 8)
                self.cg_addr = (self.cg_addr + 1) & 0xFF
            self.cg_byte ^= 1
            return self.mdr2
        if r in (0x3C, 0x3D):
            counter, flip = ('ophct', 'ophct_byte') if r == 0x3C else ('opvct', 'opvct_byte')
            value = getattr(self, counter)
            if getattr(self, flip):
                self.mdr2 = (self.mdr2 & 0xFE) | (value >> 8)
            else:
                self.mdr2 = value & 0xFF
            setattr(self, flip, getattr(self, flip) ^ 1)
            return self.mdr2
        if r == 0x3E:
            self.mdr1 = (self.mdr1 & 0x10) | PPU1_VERSION       # range and time over: with step P6
            return self.mdr1
        if r == 0x3F:
            self.mdr2 = ((self.field << 7) | (self.latched << 6) | (self.mdr2 & 0x20) | (self.pal << 4)
                         | PPU2_VERSION)
            if gate:
                self.latched = 0
            self.ophct_byte = self.opvct_byte = 0
            return self.mdr2
        return self.mdr1 if addr in READ_MDR1 else 0

    # ---- picture ----
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
            ppu.v = v
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


# ---- random register accesses ------------------------------------------------------------------

def register_stimulus(seed, count):
    """Command lines for tb/tb_ppu_regs.v:
       P line dot field pal   position from the timing unit (decimal)
       W address data         write (hexadecimal)
       R address value        read, with the expected value
       C number value         internal register REGISTERS[number]
       V / G / O address value   a word of the VRAM or of the colour memory, a byte of the OAM"""
    rng = random.Random(seed)
    ppu = Ppu()
    out, done = [], [0]

    def move():
        v = rng.choice((0, 1, 100, 224, 225, 226, 261, rng.randrange(262)))
        h, field, pal = rng.randrange(340), rng.randrange(2), int(rng.random() < 0.2)
        ppu.position(v, h, field, pal)
        out.append("P %x %x %x %x" % (v, h, field, pal))

    def w(a, d):
        ppu.write(a, d)
        out.append("W %x %x" % (a, d))
        done[0] += 1

    def r(a):
        value = ppu.read(a)
        out.append("R %x %x" % (a, value))
        done[0] += 1

    def check():
        for n, name in enumerate(REGISTERS):
            out.append("C %x %x" % (n, getattr(ppu, name)))

    def screen(on):
        w(0x2100, rng.randrange(16) if on else 0x80 | rng.randrange(16))

    def vram_burst():
        w(0x2115, rng.randrange(256) if rng.random() < 0.5 else rng.choice((0x80, 0x00, 0x84, 0x08, 0x8C)))
        base = rng.choice((0, 0x20, 0x80, 0x400, 0x7FF0, 0x8000, 0xFFFF))
        w(0x2116, (base + rng.randrange(8)) & 0xFF)
        w(0x2117, base >> 8)
        for _ in range(rng.randrange(4, 24)):
            if rng.random() < 0.5:
                w(rng.choice((0x2118, 0x2119)), rng.randrange(256))
            else:
                r(rng.choice((0x2139, 0x213A)))

    def oam_burst():
        w(0x2102, rng.choice((0, 1, 0x7F, 0xFF, rng.randrange(256))))
        w(0x2103, rng.choice((0, 0, 1, 0x80, 0x81, rng.randrange(256))))
        for _ in range(rng.randrange(4, 24)):
            if rng.random() < 0.65:
                w(0x2104, rng.randrange(256))
            else:
                r(0x2138)

    def cg_burst():
        w(0x2121, rng.choice((0, 1, 255, rng.randrange(256))))
        for _ in range(rng.randrange(3, 16)):
            if rng.random() < 0.6:
                w(0x2122, rng.randrange(256))
            else:
                r(0x213B)

    def mixed():
        for _ in range(rng.randrange(4, 30)):
            x = rng.random()
            if x < 0.30:
                a = rng.choice((0x210D, 0x210E, 0x210F, 0x2110, 0x2111, 0x2112, 0x2113, 0x2114,
                                0x211B, 0x211C, 0x211D, 0x211E, 0x211F, 0x2120))
                w(a, rng.randrange(256))
            elif x < 0.50:
                w(rng.randrange(0x2101, 0x2134), rng.randrange(256))
            elif x < 0.62:
                r(rng.choice((0x2134, 0x2135, 0x2136)))
            elif x < 0.80:
                r(rng.choice((0x2137, 0x213C, 0x213C, 0x213D, 0x213D, 0x213E, 0x213F)))
            else:
                r(rng.randrange(0x2100, 0x2140))

    r(0x2134)                                  # the values after reset
    r(0x213C)
    r(0x213C)
    r(0x213F)
    move()
    checks = 0
    while done[0] < count:
        if rng.random() < 0.35:
            move()
        if rng.random() < 0.25:
            screen(rng.random() < 0.5)
        rng.choice((vram_burst, oam_burst, cg_burst, mixed, mixed))()
        if done[0] // 200 > checks:
            checks = done[0] // 200
            check()
    check()
    out += ["V %x %x" % (a, v) for a, v in enumerate(ppu.vram) if v]
    out += ["G %x %x" % (a, v) for a, v in enumerate(ppu.cgram)]
    out += ["O %x %x" % (a, v) for a, v in enumerate(ppu.oam)]
    return out


if __name__ == '__main__':
    if len(sys.argv) == 5 and sys.argv[1] == '--regs':
        with open(sys.argv[4], 'w', newline='\n') as f:
            f.write('\n'.join(register_stimulus(int(sys.argv[2]), int(sys.argv[3]))) + '\n')
    elif len(sys.argv) == 3:
        with open(sys.argv[2], 'w', newline='\n') as f:
            f.write('\n'.join(render(ppu_scenes.parse(sys.argv[1]))) + '\n')
    else:
        raise SystemExit("use: ppu_ref.py <scene.scn> <dump.out> | --regs <seed> <count> <file>")
