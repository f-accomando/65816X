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
| `make ref-public SST=<folder>` | reference model against the public vectors | public vectors |
| `make cpu-public SST=<folder>` | CPU against the public vectors, score in `build/cpu_public_score.txt` | iverilog, public vectors |
| `make manual-check` | the manual matches its sources (see `manuals/README.md`) | Python 3 |
| `make check` | `test`, `mutation`, `iverilog`, `unit`, `cpu`, `synth`, `manual-check` | iverilog, yosys |

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

### Public vectors

Source: [SingleStepTests/65816](https://github.com/SingleStepTests/65816), MIT license, commit `307c63f`.
Each opcode has 10,000 vectors for native mode and 10,000 for emulation mode. Keep the files outside
the repository, in `<folder>/v1/`. The 106 files of the 53 opcodes of today take 457 MB.
`sim/cpu_sst.py` converts them. `SST_FLAGS` accepts `--limit N`, `--d0`, and `--page1`.
The CI does not run these commands, because it does not have the files.

In emulation mode, the vectors start with any value in the high byte of S. The real chip holds it at 01,
and the expected results follow the chip. `--page1` changes the start value, for diagnosis only.

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
| `make cpu` | 47 of 256 opcodes; 20,845 of 21,200 vectors |
| equivalent LUT4 | 4393 (5% of the 85F, 10% of the 45F) |
| `DP16KD` | 125 (60% of the 85F, 116% of the 45F) |
| `MULT18X18D` | 2 |
| `TRELLIS_FF` | 726 |
| `TRELLIS_DPR16X4` | 12 |

Before the change to `rtl/wram.v`, the WRAM used 16,384 `TRELLIS_DPR16X4` (about 98,000 LUT,
calculated). The full synthesis did not end in 570 s.

One test inserted three faults by hand in the CPU (one extra byte written, Z flag not updated,
core stopped). The CPU test bench found all three.

### Public vectors

| Run | Result |
|---|---|
| `make ref-public` | 0 of 1,030,026 vectors differ; 29,974 decimal vectors skipped |
| `make cpu-public` | 0 of 256 opcodes; 266,966 of 1,060,000 vectors; 3 min 22 s |
| `make cpu-public SST_FLAGS="--d0 --page1"` | 47 of 256 opcodes; 523,405 of 529,750 vectors |

The cycle counts differ in all vectors. The core uses 2 clocks for each read.

The first `make ref-public` run found two errors in the reference model. Both are fixed:
the high byte of S in emulation mode, and a read of the second byte of `WDM`.

### CI on GitHub

First run on 2026-11-27, commit `b7903f3`, `ubuntu-24.04`, Icarus Verilog 12.0 and Yosys 0.33:
[run 46048677412](https://github.com/f-accomando/65816X/actions/runs/46048677412). All steps passed.
The simulation and CPU results are equal to the local results. The synthesis counts differ:

| Cells | Yosys 0.52 (local) | Yosys 0.33 (CI) |
|---|---|---|
| equivalent LUT4 | 4393 (5% of the 85F, 10% of the 45F) | 12604 (15% of the 85F, 29% of the 45F) |
| `LUT4` | 3149 | 9572 |
| `CCU2C` | 610 | 1504 |
| `DP16KD` | 125 | 125 |
| `MULT18X18D` | 2 | 2 |
| `TRELLIS_FF` | 726 | 726 |
| `TRELLIS_DPR16X4` | 12 | 12 |

The cause of the LUT difference is not investigated. Quote the LUT count with the yosys version.

## 6. Not verified

- `make cpu` compares the core with our own model. The public vectors confirm this model only for the
  53 opcodes of today, without decimal mode and without cycles.
- Decimal mode and cycle counts of the core.
- Placement and maximum frequency (nextpnr is not installed).
- Operation on a real board.
