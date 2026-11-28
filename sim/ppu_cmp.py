#!/usr/bin/env python3
"""ppu_cmp.py - compare two pixel dumps and write them as PNG pictures.

The brightness N (0 to 15) scales each colour by N / 15. The documentation says "linear steps from
0 = none to 15 = full" and gives no formula: this one is an assumption."""
import struct, sys, zlib


def read_dump(path):
    return [line.split() for line in open(path) if line.strip()]


def rgb(value):
    """One value "bbbbbgggggrrrrr:bright:main:sub" as 3 bytes."""
    try:
        colour, bright = value.split(':')[:2]
        c, n = int(colour, 2), int(bright, 16)
    except ValueError:                       # unknown bits (x) from the simulator
        return bytes((255, 0, 255))
    return bytes((((c >> s) & 31) * n * 255 + 232) // 465 for s in (0, 5, 10))


def write_png(path, rows):
    """rows: list of lines, each a bytes object of 3 bytes for each pixel."""
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    raw = b''.join(b'\x00' + r for r in rows)
    head = struct.pack('>IIBBBBB', len(rows[0]) // 3, len(rows), 8, 2, 0, 0, 0)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', head) + chunk(b'IDAT', zlib.compress(raw, 9))
                + chunk(b'IEND', b''))


def picture(dump, path):
    """512 x (2 x lines): each screen line twice, for square pixels."""
    rows = []
    for line in dump:
        row = b''.join(rgb(v) for v in line)
        rows += [row, row]
    write_png(path, rows)


def difference(a, b):
    """None if the dumps are equal, or a text about the first difference."""
    if len(a) != len(b):
        return "%d lines against %d lines" % (len(a), len(b))
    first, count = None, 0
    for y, (la, lb) in enumerate(zip(a, b)):
        if len(la) != len(lb):
            return "line %d: %d values against %d values" % (y, len(la), len(lb))
        for x, (va, vb) in enumerate(zip(la, lb)):
            if va != vb:
                count += 1
                first = first or (x, y, va, vb)
    if first:
        return "%d values differ; first at x=%d y=%d: %s against %s" % ((count,) + first)
    return None


if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit("use: ppu_cmp.py <a.out> <b.out> [picture of a.png]")
    a, b = read_dump(sys.argv[1]), read_dump(sys.argv[2])
    if len(sys.argv) > 3:
        picture(a, sys.argv[3])
    text = difference(a, b)
    print(text or "equal")
    sys.exit(1 if text else 0)
