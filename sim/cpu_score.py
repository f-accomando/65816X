#!/usr/bin/env python3
"""cpu_score.py - pagella della CPU dai risultati di tb/tb_cpu.v.

Uso: cpu_score.py <risultati> <pagella_uscita> [--update | --report-only]
Un opcode "passa" in un modo (n = nativo, e = emulazione) se tutti i suoi vettori passano.
tests/cpu_pass.txt elenca cio' che passa: se qualcosa dell'elenco smette di passare si esce con
errore. --update riscrive l'elenco. --report-only scrive solo la pagella (vettori pubblici).
"""
import collections
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASSLIST = os.path.join(ROOT, 'tests', 'cpu_pass.txt')
# ordine dei bit nella maschera di tb/tb_cpu.v
FIELDS = ('PC', 'S', 'P', 'A', 'X', 'Y', 'DBR', 'D', 'PBR', 'E', 'memoria', 'scrittura_in_piu', 'blocco')
MODES = {'0': 'n', '1': 'e'}


def read_results(path):
    res = collections.defaultdict(lambda: {'tot': 0, 'bad': 0, 'fields': collections.Counter(),
                                           'cyc_known': 0, 'cyc_bad': 0})
    for line in open(path):
        op, e, mask, clocks, expected = line.split()
        r = res[(int(op, 16), MODES[e])]
        r['tot'] += 1
        try:
            mask = int(mask, 16)
        except ValueError:  # bit sconosciuti: conta come errore
            mask = (1 << len(FIELDS)) - 1
        if mask:
            r['bad'] += 1
            for bit, name in enumerate(FIELDS):
                if mask >> bit & 1:
                    r['fields'][name] += 1
        if int(expected):
            r['cyc_known'] += 1
            if int(expected) != int(clocks):
                r['cyc_bad'] += 1
    return res


def read_passlist():
    out = set()
    if os.path.exists(PASSLIST):
        for line in open(PASSLIST):
            f = line.split('#')[0].split()
            if f:
                out.add((int(f[0], 16), f[1]))
    return out


def report(res):
    passing = {k for k, r in res.items() if r['bad'] == 0}
    both = [op for op in range(256) if (op, 'n') in passing and (op, 'e') in passing]
    tested = sorted({op for op, _ in res})
    total = sum(r['tot'] for r in res.values())
    good = total - sum(r['bad'] for r in res.values())
    out = ["Pagella CPU 65816X",
           "opcode che passano in entrambi i modi: %d su 256" % len(both),
           "opcode con vettori: %d su 256" % len(tested),
           "vettori superati: %d su %d" % (good, total)]
    known = sum(r['cyc_known'] for r in res.values())
    if known:
        out.append("cicli sbagliati: %d su %d" % (sum(r['cyc_bad'] for r in res.values()), known))
    else:
        out.append("cicli: non controllati (i vettori non li indicano)")
    out += ["", "Mappa: # passa, n/e passa solo in quel modo, ! non passa, . senza vettori", "",
            "    " + " ".join("%X" % i for i in range(16))]
    for hi in range(16):
        row = []
        for lo in range(16):
            op = hi << 4 | lo
            n, e = (op, 'n') in passing, (op, 'e') in passing
            row.append('.' if op not in tested else '#' if n and e else 'n' if n else 'e' if e else '!')
        out.append("%X_  %s" % (hi, " ".join(row)))
    bad = sorted(k for k, r in res.items() if r['bad'])
    if bad:
        out += ["", "Non superati (opcode, modo, vettori sbagliati, campi diversi):"]
        for op, mode in bad:
            r = res[(op, mode)]
            fields = ", ".join("%s %d" % kv for kv in r['fields'].most_common())
            out.append("  $%02X %s  %d/%d  %s" % (op, mode, r['bad'], r['tot'], fields))
    return passing, "\n".join(out) + "\n"


def main(argv):
    args = [a for a in argv[1:] if a not in ('--update', '--report-only')]
    if len(args) != 2:
        raise SystemExit(__doc__)
    res = read_results(args[0])
    if not res:
        raise SystemExit("nessun risultato in " + args[0])
    passing, text = report(res)
    open(args[1], 'w', newline='\n').write(text)
    sys.stdout.write(text)
    if '--report-only' in argv:  # vettori diversi da quelli dell'elenco: solo pagella
        return 0
    if '--update' in argv:
        with open(PASSLIST, 'w', newline='\n') as f:
            f.write("# Opcode (e modo) che il banco di prova deve continuare a superare.\n"
                    "# Rigenerare con: make cpu-update\n")
            for op, mode in sorted(passing):
                f.write("%02X %s\n" % (op, mode))
        print("elenco aggiornato: %d voci" % len(passing))
        return 0
    wanted = read_passlist()
    lost = sorted(wanted - passing)
    if not wanted:
        print("ERRORE: tests/cpu_pass.txt vuoto o assente")
        return 1
    for op, mode in lost:
        print("ERRORE: $%02X %s non passa piu'" % (op, mode))
    for op, mode in sorted(passing - wanted):
        print("nuovo: $%02X %s passa ma non e' nell'elenco (make cpu-update)" % (op, mode))
    return 1 if lost else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
