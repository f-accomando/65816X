#!/usr/bin/env python3
"""cpu_vectors.py - genera i vettori del banco di prova della CPU da sim/cpu_ref.py.

Uso: cpu_vectors.py <file_uscita> [casi per opcode e modo]
Il seme e' fisso: a parita' di sorgenti il file e' identico.

Formato di una riga (tutti i numeri in esadecimale):
  opcode, stato iniziale (pc s p a x y dbr d pbr e), stato finale (stessi campi), cicli,
  n, n coppie "indirizzo byte" iniziali, m, m coppie "indirizzo byte" finali,
  c, c terne "tipo indirizzo byte" dei cicli di bus (tipo: bit 0 VDA, bit 1 VPA, bit 2 scrittura;
  byte 100 = nessuno).
cicli = 0 vuol dire "non noto".

"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cpu_ref

SEED = 65816
CASES = 200
EDGES8 = (0x00, 0x01, 0x7F, 0x80, 0xFE, 0xFF)
EDGES16 = (0x0000, 0x0001, 0x00FF, 0x0100, 0x01FF, 0x7FFF, 0x8000, 0xFFFE, 0xFFFF)


def pick(rng, edges, bits):
    return rng.choice(edges) if rng.random() < 0.3 else rng.getrandbits(bits)


def initial_state(rng, e):
    st = {
        'pc': pick(rng, EDGES16, 16), 's': pick(rng, EDGES16, 16),
        'p': rng.getrandbits(8),
        'a': pick(rng, EDGES16, 16), 'x': pick(rng, EDGES16, 16), 'y': pick(rng, EDGES16, 16),
        'dbr': pick(rng, EDGES8, 8), 'd': pick(rng, EDGES16, 16), 'pbr': pick(rng, EDGES8, 8), 'e': e,
    }
    if e:
        st['p'] |= cpu_ref.M | cpu_ref.X
        st['s'] = 0x0100 | pick(rng, EDGES8, 8)
    if st['p'] & cpu_ref.X:
        st['x'] &= 0xFF
        st['y'] &= 0xFF
    return st


def make_case(rng, opcode, e):
    start = initial_state(rng, e)
    if opcode in (0x44, 0x54):  # spostamenti di blocchi: pochi byte per vettore
        start['a'] = rng.randrange(8)
    first = (start['pbr'] << 16) | start['pc']

    # caso limite: indirizzi in cima a un banco (operandi $FF con D = $FF00 o X alto)
    corner = rng.random() < 0.05
    if corner:
        start['d'] = 0xFF00

    def new_byte(kind):
        if corner and kind == 'code':
            return 0xFF
        return pick(rng, EDGES8, 8)

    cpu = cpu_ref.Cpu(start, new_byte)
    cpu.mem[first] = cpu.initial[first] = opcode
    cpu.step()
    if opcode in (0x44, 0x54):
        # uno spostamento che scrive sopra la propria istruzione cambia il programma in corsa:
        # il modello non lo segue, quindi il caso si scarta e se ne genera un altro
        code = {(start['pbr'] << 16) | ((start['pc'] + i) & 0xFFFF) for i in range(3)}
        if any(kind & 4 and addr in code for kind, addr, _ in cpu.cycles):
            return make_case(rng, opcode, e)
    return start, cpu


def line(opcode, start, cpu):
    final = cpu.regs()
    out = [opcode]
    out += [start[r] for r in cpu_ref.REGS]
    out += [final[r] for r in cpu_ref.REGS]
    out.append(len(cpu.cycles))
    for mem in (cpu.initial, cpu.mem):
        out.append(len(mem))
        for addr in sorted(mem):
            out += [addr, mem[addr]]
    out.append(len(cpu.cycles))
    for kind, addr, value in cpu.cycles:
        out += [kind, 0 if addr is None else addr, 0x100 if value is None else value]
    return ' '.join('%x' % v for v in out)


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)
    cases = int(argv[2]) if len(argv) > 2 else CASES
    rng = random.Random(SEED)
    total = 0
    os.makedirs(os.path.dirname(os.path.abspath(argv[1])), exist_ok=True)
    with open(argv[1], 'w', newline='\n') as out:
        for opcode in sorted(cpu_ref.OPCODES):
            for e in (0, 1):
                for _ in range(cases):
                    out.write(line(opcode, *make_case(rng, opcode, e)) + '\n')
                    total += 1
    print("%d vettori per %d opcode in %s" % (total, len(cpu_ref.OPCODES), argv[1]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
