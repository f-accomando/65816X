#!/usr/bin/env python3
"""cpu_sst.py - use the public test vectors SingleStepTests/65816 (MIT license).

The vectors stay outside the repository. <folder> contains the files v1/XX.n.json and v1/XX.e.json.

  cpu_sst.py convert <folder> <out_file> [--limit N] [--d0] [--page1] [--bus]
      write the vectors in the format of the test bench (see sim/cpu_vectors.py)
      --page1 (diagnosis only): in emulation mode, start with the high byte of S at 01, the only
      value that the real chip can hold. The public vectors start with any value there.
      --bus: also write the bus cycles of each vector, for the cycle by cycle check.
  cpu_sst.py check-ref <folder> [--limit N]
      run the reference model sim/cpu_ref.py on the vectors and report the differences

--limit N: use only the first N vectors of each file. --d0: skip vectors that start with D = 1.
Files of opcodes that cpu_ref.OPCODES does not list are skipped.
"""
import collections
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cpu_ref

DECIMAL = (0x69, 0x6D, 0xE9)  # the reference model has no decimal ADC and SBC


def files(folder):
    found = []
    for path in sorted(glob.glob(os.path.join(folder, 'v1', '*.json'))):
        m = re.match(r'([0-9a-f]{2})\.([ne])\.json$', os.path.basename(path))
        if m and int(m.group(1), 16) in cpu_ref.OPCODES:
            found.append((int(m.group(1), 16), m.group(2), path))
    if not found:
        raise SystemExit("no vector files in " + os.path.join(folder, 'v1'))
    return found


def load(path, limit):
    with open(path, encoding='utf-8') as f:
        tests = json.load(f)
    return tests[:limit] if limit else tests


def bus_list(cycles):
    """[count, kind, address, value, ...]; kind bit 0 VDA, bit 1 VPA, bit 2 write; value 100 = none"""
    row = [len(cycles)]
    for addr, value, flags in cycles:
        kind = (flags[0] == 'd') | (flags[1] == 'p') << 1 | (flags[3] == 'w') << 2
        row += [kind, addr, 0x100 if value is None else value]
    return row


def convert(folder, out_path, limit, d0, page1, bus):
    total = 0
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    found = files(folder)
    with open(out_path, 'w', newline='\n') as out:
        for opcode, _, path in found:
            for t in load(path, limit):
                ini, fin = t['initial'], t['final']
                if d0 and ini['p'] & cpu_ref.D:
                    continue
                if page1 and ini['e']:
                    ini = dict(ini, s=0x0100 | (ini['s'] & 0xFF))
                row = [opcode]
                row += [ini[r] for r in cpu_ref.REGS]
                row += [fin[r] for r in cpu_ref.REGS]
                row.append(len(t['cycles']))
                for ram in (ini['ram'], fin['ram']):
                    row.append(len(ram))
                    for addr, value in ram:
                        row += [addr, value]
                row += bus_list(t['cycles']) if bus else [0]
                out.write(' '.join('%x' % v for v in row) + '\n')
                total += 1
    print("%d vectors from %d files in %s" % (total, len(found), out_path))
    return 0 if total else 1


class Missing(Exception):
    pass


def no_byte(kind):
    raise Missing()


def check_one(t):
    """Return the names of the fields where the reference model differs from the vector."""
    ini, fin = t['initial'], t['final']
    cpu = cpu_ref.Cpu(ini, no_byte)
    for addr, value in ini['ram']:
        cpu.mem[addr] = value
    try:
        cpu.step()
    except Missing:
        return ['read_outside_vector']
    got = cpu.regs()
    bad = [r for r in cpu_ref.REGS if got[r] != fin[r]]
    expected = dict((a, v) for a, v in fin['ram'])
    if any(cpu.mem.get(a) != v for a, v in expected.items()):
        bad.append('memory')
    if set(cpu.mem) - set(expected):
        bad.append('extra_write')
    cycles = [((f[0] == 'd') | (f[1] == 'p') << 1 | (f[3] == 'w') << 2, a, v) for a, v, f in t['cycles']]
    if len(cpu.cycles) != len(cycles):
        bad.append('cycle_count')
    elif cpu.cycles != cycles:
        bad.append('bus')
    return bad


def check_ref(folder, limit):
    total = wrong = skipped = 0
    report = []
    for opcode, mode, path in files(folder):
        fields = collections.Counter()
        count = bad = 0
        first = None
        for t in load(path, limit):
            if opcode in DECIMAL and t['initial']['p'] & cpu_ref.D:
                skipped += 1
                continue
            count += 1
            diff = check_one(t)
            if diff:
                bad += 1
                fields.update(diff)
                first = first or t['name']
        total += count
        wrong += bad
        if bad:
            report.append("  $%02X %s  %d/%d  %s  (first: %s)" % (
                opcode, mode, bad, count, ", ".join("%s %d" % kv for kv in fields.most_common()), first))
    print("reference model: %d of %d vectors differ; %d decimal vectors skipped" % (wrong, total, skipped))
    for line in report:
        print(line)
    return 1 if wrong else 0


def main(argv):
    args = argv[1:]
    d0 = '--d0' in args
    page1 = '--page1' in args
    bus = '--bus' in args
    args = [a for a in args if a not in ('--d0', '--page1', '--bus')]
    limit = 0
    if '--limit' in args:
        i = args.index('--limit')
        limit = int(args[i + 1])
        del args[i:i + 2]
    if len(args) == 3 and args[0] == 'convert':
        return convert(args[1], args[2], limit, d0, page1, bus)
    if len(args) == 2 and args[0] == 'check-ref':
        return check_ref(args[1], limit)
    raise SystemExit(__doc__)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
