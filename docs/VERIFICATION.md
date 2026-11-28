# Verification

## 1. Levels and commands

| Command | What it does | Needs |
|---|---|---|
| `make test` | full system with the Python simulator `sim/vsim.py` | Python 3 |
| `make mutation` | inserts faults in the RTL; fails if the tests miss even one | Python 3 |
| `make iverilog` | full system with Icarus Verilog, same values as `make test` | iverilog |
| `make unit` | test for each module against a reference model (today: the WRAM with 100,000 random cycles, and the `WDM` unit with 20,000 operations) | iverilog |
| `make cpu` | CPU only: one instruction for each vector, score in `build/cpu_score.txt`, pass list `tests/cpu_pass.txt`. It checks the cycle count and each bus cycle when the vectors give them. | iverilog |
| `make cpu-update` | same as above, and writes `tests/cpu_pass.txt` again | iverilog |

| `make synth` | ECP5 synthesis and budget check (default `BUDGET=B`) | yosys |
| `make ref-public SST=<folder>` | reference model against the public vectors | public vectors |
| `make cpu-public SST=<folder>` | CPU against the public vectors, score in `build/cpu_public_score.txt` | iverilog, public vectors |
| `make cpu-int` | interrupts: directed tests of the core (`tb/tb_cpu_int.v`) and of the system NMI (`tb/tb_snes_nmi.v`) | iverilog |
| `make cpu-mutation` | inserts faults in the core; fails if the vectors and the interrupt tests miss even one | iverilog |
| `make manual-check` | the manual matches its sources (see `manuals/README.md`) | Python 3 |
| `make tables` | writes the generated tables of the new CPU core | Python 3 |
| `make tables-check` | the generated tables match `rtl/cpu/c816_tables.txt` | Python 3 |
| `make check` | `tables-check`, `test`, `mutation`, `iverilog`, `unit`, `cpu`, `cpu-int`, `cpu-mutation`, `synth`, `manual-check` | iverilog, yosys |

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
Each opcode has 10,000 vectors for native mode and 10,000 for emulation mode (`MVN` and `MVP` have 200). Keep the files outside
the repository, in `<folder>/v1/`. The 512 files of all opcodes take 2.6 GB.
`sim/cpu_sst.py` converts them. `SST_FLAGS` accepts `--limit N`, `--d0`, `--page1`, and `--bus`.
`--bus` adds the bus cycles of each vector, for a check cycle by cycle.
Only the adapter file `tb/cpu_adapt_c816.vh` reads the internal registers of the core.
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

Today variant A **does not fit** (126 blocks of 108: placeholder ROM and WRAM in BRAM). The CI checks
only B. Add A to the CI when the memory is on SDRAM (roadmap phase F4).

## 5. Results measured on 2026-11-28

In WSL (Ubuntu 26.04), with Icarus Verilog 12.0 and Yosys 0.52, after step C7a.
Older results are in the git history of this file.

| Check | Result |
|---|---|
| `make test` | 98/98 (the program ended in 2059 cycles) |
| `make mutation` | 18 of 18 faults found |
| `make iverilog` | 98/98 |
| `make unit` | 0 differences: 28,123 accesses to the WRAM port and 20,000 operations of the `WDM` unit |
| `make cpu` | 256 of 256 opcodes; 102,400 of 102,400 vectors |
| `make cpu-int` | the core test and the system NMI test pass; `WDM MUL` 2 cycles, `WDM DIV` 11 cycles |
| `make cpu-mutation` | 32 of 32 faults found |
| `$div` and `$mod` cells before mapping | none |
| equivalent LUT4 | 5761 (7% of the 85F, 13% of the 45F) |
| `DP16KD` | 126 (61% of the 85F, 117% of the 45F); yosys puts the decode table in one block |
| `MULT18X18D` | 1 |
| `TRELLIS_FF` | 789 |
| `TRELLIS_DPR16X4` | 12 |

### Public vectors

All vectors, with the cycle and bus checks.

| Run | Result |
|---|---|
| `make ref-public` (reference model, after step C5) | 0 of 5,080,400 vectors differ, cycles included |
| `make cpu-public SST_FLAGS="--bus"` (after step C7a) | **256 of 256 opcodes**; 5,080,400 of 5,080,400 vectors; 0 cycle differences; 42 minutes |

The comparisons found three errors during the development. All are fixed.

- Reference model: the high byte of S in emulation mode.
- Reference model: a read of the second byte of `WDM`.
- Core: a second IRQ right after the entry of the first one.

### CI on GitHub

The CI runs on `ubuntu-24.04` with Icarus Verilog 12.0 and Yosys 0.33. The simulation and CPU
results are equal to the local results. The synthesis counts differ: after step C6, Yosys 0.33
counts 7277 equivalent LUT4 against 5411 for Yosys 0.52. Before step C6, with combinational
dividers, the counts were 13307 and 5876. The cause of the difference is not investigated.
Quote each LUT count with the yosys version.

## 6. Not verified

- Interrupt timing against a real chip, the reset sequence, and `ABORT`.
- Placement and maximum frequency (nextpnr is not installed).
- The partial values of the 5A22 multiplier and divider against a real chip.
- Operation on a real board.
