#!/usr/bin/env python3
"""asm.py - mini assembler per il sottoinsieme 65816X (LoROM, banco 0, 64 KB)."""
import re

IMPL = {'NOP': 0xEA, 'CLC': 0x18, 'SEC': 0x38, 'SEI': 0x78, 'CLI': 0x58, 'XCE': 0xFB,
        'INX': 0xE8, 'DEX': 0xCA, 'INY': 0xC8, 'DEY': 0x88, 'TAX': 0xAA, 'TXA': 0x8A,
        'TAY': 0xA8, 'TYA': 0x98, 'PHA': 0x48, 'PLA': 0x68, 'RTS': 0x60,
        'PHP': 0x08, 'PLP': 0x28}
ACC = {'INC': 0x1A, 'DEC': 0x3A}                      # INC A / DEC A
IMM8 = {'REP': 0xC2, 'SEP': 0xE2, 'WDM': 0x42}
IMMM = {'LDA': 0xA9, 'ADC': 0x69, 'SBC': 0xE9, 'CMP': 0xC9, 'AND': 0x29, 'ORA': 0x09, 'EOR': 0x49}
IMMX = {'LDX': 0xA2, 'LDY': 0xA0}
ABS = {'LDA': 0xAD, 'STA': 0x8D, 'ADC': 0x6D, 'CMP': 0xCD, 'LDX': 0xAE, 'LDY': 0xAC,
       'STX': 0x8E, 'STY': 0x8C}
ABSX = {'LDA': 0xBD, 'STA': 0x9D}
LONG = {'LDA': 0xAF, 'STA': 0x8F}
BR = {'BRA': 0x80, 'BNE': 0xD0, 'BEQ': 0xF0, 'BCC': 0x90, 'BCS': 0xB0, 'BPL': 0x10, 'BMI': 0x30,
      'BVC': 0x50, 'BVS': 0x70}
JMPS = {'JMP': 0x4C, 'JSR': 0x20, 'JML': 0x5C}

class AsmError(Exception):
    pass

def _num(tok, labels=None):
    tok = tok.strip()
    if tok.startswith('$'):
        return int(tok[1:], 16), len(tok) - 1
    if re.fullmatch(r'\d+', tok):
        return int(tok), 0
    if labels is not None:
        if tok not in labels:
            raise AsmError("simbolo non definito: " + tok)
        return labels[tok], 4
    return 0, 4

def assemble(src):
    items = []          # (addr, kind, data...)
    labels = {}
    pc = 0x8000
    m8, x8 = True, True
    for ln, raw in enumerate(src.splitlines(), 1):
        line = raw.split(';')[0].strip()
        while True:
            mm = re.match(r'^([A-Za-z_]\w*):\s*(.*)$', line)
            if not mm:
                break
            labels[mm.group(1)] = pc
            line = mm.group(2)
        if not line:
            continue
        parts = line.split(None, 1)
        mn = parts[0].upper() if not parts[0].startswith('.') else parts[0].lower()
        opd = parts[1].strip() if len(parts) > 1 else ''
        try:
            if mn == '.org':
                pc = _num(opd)[0]
            elif mn == '.byte':
                vals = [v.strip() for v in opd.split(',')]
                items.append((pc, 'bytes', vals))
                pc += len(vals)
            elif mn == '.word':
                vals = [v.strip() for v in opd.split(',')]
                items.append((pc, 'words', vals))
                pc += 2 * len(vals)
            elif mn in IMPL:
                items.append((pc, 'raw', [IMPL[mn]]))
                pc += 1
            elif mn in ACC and opd.upper() == 'A':
                items.append((pc, 'raw', [ACC[mn]]))
                pc += 1
            elif mn in IMM8:
                items.append((pc, 'imm8', IMM8[mn], opd.lstrip('#')))
                if mn in ('REP', 'SEP'):
                    v = _num(opd.lstrip('#'))[0]
                    if v & 0x20:
                        m8 = (mn == 'SEP')
                    if v & 0x10:
                        x8 = (mn == 'SEP')
                pc += 2
            elif mn in JMPS:
                items.append((pc, 'jmp', JMPS[mn], opd))
                pc += 4 if mn == 'JML' else 3
            elif mn in BR:
                items.append((pc, 'br', BR[mn], opd))
                pc += 2
            elif opd.startswith('#'):
                tab = IMMM if mn in IMMM else IMMX
                if mn not in tab:
                    raise AsmError("immediato non valido per " + mn)
                wide = not (m8 if tab is IMMM else x8)
                items.append((pc, 'imm', tab[mn], opd[1:], wide))
                pc += 3 if wide else 2
            elif opd.upper().endswith(',X'):
                a = opd[:-2]
                items.append((pc, 'abs', ABSX[mn], a))
                pc += 3
            else:
                digits = _num(opd)[1]
                if mn in LONG and digits > 4:
                    items.append((pc, 'long', LONG[mn], opd))
                    pc += 4
                elif mn in ABS:
                    items.append((pc, 'abs', ABS[mn], opd))
                    pc += 3
                else:
                    raise AsmError("istruzione non supportata: " + line)
        except KeyError:
            raise AsmError("riga %d: modo non supportato: %s" % (ln, raw.strip()))
    image = bytearray(0x10000)
    used = set()

    def put(addr, bs):
        for i, b in enumerate(bs):
            off = addr + i - 0x8000
            if not 0 <= off < 0x8000:
                raise AsmError("indirizzo fuori ROM: %04X" % (addr + i))
            if off in used:
                raise AsmError("due blocchi sullo stesso indirizzo: %04X" % (addr + i))
            used.add(off)
            image[off] = b & 0xFF

    for it in items:
        addr, kind = it[0], it[1]
        if kind == 'raw':
            put(addr, it[2])
        elif kind == 'imm8':
            put(addr, [it[2], _num(it[3], labels)[0]])
        elif kind == 'imm':
            v = _num(it[3], labels)[0]
            put(addr, [it[2], v & 0xFF] + ([(v >> 8) & 0xFF] if it[4] else []))
        elif kind == 'abs':
            v = _num(it[3], labels)[0]
            put(addr, [it[2], v & 0xFF, (v >> 8) & 0xFF])
        elif kind == 'long':
            v = _num(it[3], labels)[0]
            put(addr, [it[2], v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF])
        elif kind == 'jmp':
            v = _num(it[3], labels)[0]
            if it[2] == 0x5C:
                put(addr, [it[2], v & 0xFF, (v >> 8) & 0xFF, 0])
            else:
                put(addr, [it[2], v & 0xFF, (v >> 8) & 0xFF])
        elif kind == 'br':
            t = _num(it[3], labels)[0]
            d = t - (addr + 2)
            if not -128 <= d <= 127:
                raise AsmError("salto troppo lungo a %s" % it[3])
            put(addr, [it[2], d & 0xFF])
        elif kind == 'bytes':
            put(addr, [_num(v, labels)[0] for v in it[2]])
        elif kind == 'words':
            bs = []
            for v in it[2]:
                n = _num(v, labels)[0]
                bs += [n & 0xFF, (n >> 8) & 0xFF]
            put(addr, bs)
    return bytes(image), labels

if __name__ == '__main__':
    import sys
    img, lab = assemble(open(sys.argv[1]).read())
    open(sys.argv[2], 'w').write('\n'.join('%02x' % b for b in img) + '\n')
    print("ROM scritta in", sys.argv[2], "- simboli:", ", ".join("%s=%04X" % kv for kv in sorted(lab.items())))
