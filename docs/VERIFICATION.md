# Verification

## 1. Levels and commands

| Command | What it does | Needs |
|---|---|---|
| `make test` | full system with the Python simulator `sim/vsim.py` | Python 3 |
| `make mutation` | inserts faults in the RTL; fails if the tests miss even one | Python 3 |
| `make iverilog` | full system with Icarus Verilog, same values as `make test` | iverilog |
| `make unit` | test for each module against a reference model (today: WRAM, 100,000 random cycles) | iverilog |
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

## 5. Results measured on 2026-11-27

In WSL (Ubuntu 26.04), with Icarus Verilog 12.0 and Yosys 0.52, with `make check`.
The system uses the new core `c816`.

| Check | Result |
|---|---|
| `make test` | 56/56 (the program ended in 1305 cycles) |
| `make mutation` | 11 of 11 faults found |
| `make iverilog` | 56/56 |
| `make unit` | 0 differences, 28,123 accesses to the WRAM port |
| `make cpu` | 256 of 256 opcodes; 102,400 of 102,400 vectors |
| `make cpu-int` | the core test and the system NMI test pass |
| `make cpu-mutation` | 32 of 32 faults found |
| equivalent LUT4 | 5876 (7% of the 85F, 13% of the 45F) |
| `DP16KD` | 126 (61% of the 85F, 117% of the 45F); yosys puts the decode table in one block |
| `MULT18X18D` | 2 |
| `TRELLIS_FF` | 718 |
| `TRELLIS_DPR16X4` | 12 |

With the old core, the system took 1321 cycles for the test program, 4393 equivalent LUT4, and 726 FF.

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
| `make cpu-public CORE=c816 SST_FLAGS="--limit 1000 --bus"` | 26 of 256 opcodes; 60,201 of 106,000 vectors. Of the 28 opcodes of work order 3, only `$69` and `$E9` fail, because decimal mode is missing. None of the 28 has a cycle or bus difference |
| `make cpu-public CORE=c816 SST_FLAGS="--limit 1000 --bus --d0"` | 28 of 256 opcodes; 31,033 of 53,118 vectors |

The cycle counts differ in all vectors. The core uses 2 clocks for each read.

The first `make ref-public` run found two errors in the reference model. Both are fixed:
the high byte of S in emulation mode, and a read of the second byte of `WDM`.

Since 2026-11-27 the reference model also records each bus cycle, and `make ref-public` compares
them: 0 differences in 1,030,026 vectors. Thus the own vectors check the cycles, also in the CI.

### Public vectors on the new core

Run on 2026-11-27, all vectors, with the cycle and bus checks. At that time the repository had two
cores, and `CORE=c816` selected the one that is the only core today.

| Run | Result |
|---|---|
| `make cpu-public CORE=c816 SST_FLAGS="--bus"` | **50 of 256 opcodes**; 1,032,847 of 1,060,000 vectors; 0 cycle differences |
| `make cpu-public CORE=c816 SST_FLAGS="--bus --d0"` | **53 of 256 opcodes**; 529,750 of 529,750 vectors; 0 cycle differences |

In the first run, only `$69`, `$6D`, and `$E9` fail, only in A and P, because decimal mode is missing.
No vector of any opcode has a cycle or bus difference.

### Public vectors after step C3 (all addressing modes)

Run on 2026-11-28, all vectors of the 177 opcodes, with the cycle and bus checks.

| Run | Result |
|---|---|
| `make ref-public` | 0 of 3,239,910 vectors differ, cycles included; 300,090 decimal vectors skipped |
| `make cpu-public SST_FLAGS="--bus"` | **147 of 256 opcodes**; 3,277,325 of 3,540,000 vectors; 0 cycle differences |
| `make cpu-public SST_FLAGS="--limit 500 --bus --d0"` | 177 of 256 opcodes; 88,622 of 88,622 vectors |

In the full run, only the 15 forms of `ADC` and of `SBC` fail, only in A and P, because decimal mode
is missing.

### Public vectors after step C4 (all instructions except interrupts)

Run on 2026-11-28, all vectors of the 251 opcodes, with the cycle and bus checks.

| Run | Result |
|---|---|
| `make ref-public` | 0 of 4,680,310 vectors differ, cycles included; 300,090 decimal vectors skipped |
| `make cpu-public SST_FLAGS="--bus"` | **221 of 256 opcodes**; 4,717,725 of 4,980,400 vectors; 0 cycle differences |
| `make cpu-public SST_FLAGS="--limit 300 --bus --d0"` | 251 of 256 opcodes; 75,080 of 75,080 vectors |

In the full run, only the 15 forms of `ADC` and of `SBC` fail, because decimal mode is missing.
A vector of `MVN` or `MVP` covers a whole block move, with up to about 7,000 cycles.

### Public vectors after step C5 (all 256 opcodes)

Run on 2026-11-28, all vectors, with the cycle and bus checks.

| Run | Result |
|---|---|
| `make ref-public` | 0 of 5,080,400 vectors differ, cycles included |
| `make cpu-public SST_FLAGS="--bus"` | **256 of 256 opcodes**; 5,080,400 of 5,080,400 vectors; 0 cycle differences |

The interrupt test found one error in the core: a second IRQ right after the entry of the first one.
The error is fixed.

### CI on GitHub

These numbers are from the system with the old core. First run on 2026-11-27, commit `b7903f3`, `ubuntu-24.04`, Icarus Verilog 12.0 and Yosys 0.33:
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

With the core `c816` in the system (commit `99858f4`,
[run 46074388791](https://github.com/f-accomando/65816X/actions/runs/46074388791)), Yosys 0.33 counts
11245 equivalent LUT4 (13% of the 85F). The cells are 8383 `LUT4`, 1419 `CCU2C`, and 680 `TRELLIS_FF`.

## 6. Not verified

- Interrupt timing against a real chip, the reset sequence, and `ABORT`.
- Placement and maximum frequency (nextpnr is not installed).
- Operation on a real board.
