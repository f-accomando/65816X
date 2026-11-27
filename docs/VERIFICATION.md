# Verification

## 1. Levels and commands

| Command | What it does | Needs |
|---|---|---|
| `make test` | full system with the Python simulator `sim/vsim.py` | Python 3 |
| `make mutation` | inserts faults in the RTL; fails if the tests miss even one | Python 3 |
| `make iverilog` | full system with Icarus Verilog, same values as `make test` | iverilog |
| `make unit` | test for each module against a reference model (today: WRAM, 100,000 random cycles) | iverilog |
| `make cpu` | CPU only: one instruction for each vector, score in `build/cpu_score.txt` | iverilog |
| `make cpu-update` | same as above, and writes `tests/cpu_pass.txt` again | iverilog |
| `make synth` | ECP5 synthesis and budget check (default `BUDGET=B`) | yosys |
| `make check` | all of the above | iverilog, yosys |

Keep `sim/vsim.py` while the RTL needs no parameters, `generate`, or `function`.
Do not shape the RTL for the mini simulator: the design would get worse.

The CI (`.github/workflows/ci.yml`) runs the same commands on each pull request and on each push to `main` and `claude/**`.

## 2. Single sources

- `rtl/files.f`: list of the RTL sources. The Makefile, `sim/run_tests.py`, and `sim/mutation_check.py` read it.
  In the comments of this file, write no word that ends in `.v` (the Makefile filters with `%.v`).
- `tests/<program>.expect`: expected values. `sim/run_tests.py` and `sim/gen_tb.py` read it.
- `sim/cpu_ref.py`: reference model of the CPU. `sim/cpu_vectors.py` makes the vectors from it
  (fixed seed). `tests/cpu_pass.txt`: opcodes and modes that must continue to pass.
- New check: add one line to the `.expect` file. New mutant: add one line to `MUTANTS` in `sim/mutation_check.py`.

## 3. Rule for each change

Give each new function a check and at least one mutant. Before you close a task, run `make check`.
Update the documents in `docs/`.

Trap: with `iverilog -g2012`, the word `ref` is reserved. Do not use it as an instance name.

## 4. Synthesis budget

`syn/budget.py` reads `build/stat.json` and compares it with the variant:

- equivalent LUT4: `LUT4 + 2 x CCU2C + 2 x TRELLIS_DPR16X4` (estimate before placement);
- `DP16KD` BRAM blocks and `MULT18X18D` multipliers;
- error above 256 `TRELLIS_DPR16X4`: a large memory went into logic instead of BRAM.

Check the device numbers in the script against the Lattice datasheet.

Today variant A **does not fit** (125 blocks of 108: placeholder ROM and WRAM in BRAM). The CI checks
only B. Add A to the CI when the memory is on SDRAM (roadmap phase F4).

## 5. Results measured on 2026-11-27

In WSL (Ubuntu 26.04), with Icarus Verilog 12.0 and Yosys 0.52, with `make check`:

| Check | Result |
|---|---|
| `make test` | 56/56 (the program ended in 1321 cycles) |
| `make mutation` | 10 of 10 faults found |
| `make iverilog` | 56/56 |
| `make unit` | 0 differences, 28,123 accesses to the WRAM port |
| `make cpu` | 47 of 256 opcodes; 20,838 of 21,200 vectors |
| equivalent LUT4 | 4393 (5% of the 85F, 10% of the 45F) |
| `DP16KD` | 125 (60% of the 85F, 116% of the 45F) |
| `MULT18X18D` | 2 |
| `TRELLIS_FF` | 726 |
| `TRELLIS_DPR16X4` | 12 |

Before the change to `rtl/wram.v`, the WRAM used 16,384 `TRELLIS_DPR16X4` (about 98,000 LUT,
calculated). The full synthesis did not end in 570 s.

One test inserted three faults by hand in the CPU (one extra byte written, Z flag not updated,
core stopped). The CPU test bench found all three.

## 6. Not verified

- The CPU test bench compares the core with our own model. It finds differences between the two.
  It does not prove that the core matches the chip. It does not check cycles or decimal mode.
- Placement and maximum frequency (nextpnr is not installed).
- Operation on a real board.
- The CI on GitHub, until the first run: the yosys version of the distribution can differ from 0.52.
