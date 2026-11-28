#!/usr/bin/env python3
"""budget.py - legge il conteggio celle di yosys (stat -json) e lo confronta con le risorse della
ECP5 LFE5U-85F, l'unico FPGA del progetto. Uso: python3 syn/budget.py build/stat.json
Esce con errore se il progetto non entra o se la RAM distribuita supera la soglia (segno che una
memoria grande non e' finita in BRAM)."""
import json, sys

# Risorse della LFE5U-85F (datasheet Lattice ECP5): LUT4, blocchi DP16KD, moltiplicatori.
DEVICE, CAPACITY = 'LFE5U-85F', {'LUT4': 83640, 'DP16KD': 208, 'MULT18X18D': 156}
# Ogni TRELLIS_DPR16X4 e' una RAM 16x4 in logica: oggi ne servono 12. Oltre la soglia
# una memoria grande e' quasi certamente scivolata in LUT.
MAX_DPR16X4 = 256

def cell_counts(path):
    data = json.load(open(path))
    if 'design' in data:
        by_type = data['design'].get('num_cells_by_type', {})
    else:
        mods = data.get('modules', {})
        top = max(mods.values(), key=lambda m: m.get('num_cells', 0))
        by_type = top.get('num_cells_by_type', {})
    out = {}
    for k, v in by_type.items():
        name = k.split(chr(92))[-1]
        out[name] = out.get(name, 0) + v
    return out

def main(path):
    c = cell_counts(path)
    dpr = c.get('TRELLIS_DPR16X4', 0)
    # LUT4 occupati: LUT4 + 2 per ogni CCU2C (sommatore a 2 bit) + 2 per ogni DPR16X4
    used = {'LUT4': c.get('LUT4', 0) + 2 * c.get('CCU2C', 0) + 2 * dpr,
            'DP16KD': c.get('DP16KD', 0), 'MULT18X18D': c.get('MULT18X18D', 0)}
    print("celle: " + ", ".join("%s %d" % kv for kv in sorted(c.items())))
    ok = True
    if dpr > MAX_DPR16X4:
        print("ERRORE: %d TRELLIS_DPR16X4 (soglia %d): una memoria non e' in BRAM" % (dpr, MAX_DPR16X4))
        ok = False
    fits = all(used[k] <= CAPACITY[k] for k in CAPACITY)
    ok = ok and fits
    print("%s: %s%s" % (DEVICE, ", ".join(
        "%s %d/%d (%.0f%%)" % (k, used[k], CAPACITY[k], 100.0 * used[k] / CAPACITY[k]) for k in CAPACITY),
        "" if fits else "  NON ENTRA"))
    return 0 if ok else 1

if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
