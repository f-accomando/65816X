# CPU

Core 65816X: `rtl/cpu65816x.v`. Test bench: `tb/tb_cpu.v`, with vectors from `sim/cpu_ref.py`.
The list of what must continue to pass is in `tests/cpu_pass.txt`.

## Status (measured with `make cpu`)

- 53 of 256 opcodes implemented; **47 pass the test bench** in native and emulation mode.
- Own vectors: 20,845 of 21,200 pass (200 for each opcode and mode). Cycles are not checked.
- Public vectors, unchanged: 266,966 of 1,060,000 pass, and no opcode passes. The two causes are the
  missing D flag and the high byte of S in emulation mode.
- Public vectors with D = 0 and S in page 1 (diagnosis): 523,405 of 529,750 pass. The same 47 opcodes
  pass, and the same differences remain.
- The reference model agrees with all 1,030,026 public vectors that are not decimal `ADC` or `SBC`.
- Differences found:

| Opcode | Mode | Cause |
|---|---|---|
| `JSR`, `RTS`, `PHA`, `PLA` | emulation | the stack does not stay in page 1 |
| `XCE` | native | the change to emulation does not force S into page 1 |
| `SEP` | both | the D flag (decimal) is missing |
| all | both, public vectors | the D flag is missing, so P differs when D = 1 |
| all | emulation, public vectors | the core does not hold the high byte of S at 01 |

## Open work

To close a step, make its opcodes pass the test bench and make `make check` pass.

- **C2** (in progress). Design and work orders: [cpu-core.md](../design/cpu-core.md).
  Reorganize the core: table decode, one ALU, separate address calculation.
  Run one sequence step for each cycle of the real chip.
  Add the D register and D flag. Hold the high byte of S at 01 in emulation mode.
  Signal an unimplemented opcode (`dbg_illegal`). This fixes the differences in the table above.
  Done: work orders 1-6. The new core `rtl/cpu/c816_core.v` runs all sequences of the 53 opcodes
  and the `WDM` extensions. On all public vectors, unchanged, 50 opcodes pass cycle by cycle.
  `ADC` and `SBC` fail only with D = 1 (step C5). The system does not use the new core yet.
  Next: work order 7 (faults for the new core), then work order 8 (the system).
- **C3** all addressing modes, with loads, stores, and arithmetic.
- **C4** remaining instructions: shifts, stack, transfers, jumps, block moves.
- **C5** interrupts (NMI, IRQ, BRK, COP, RTI, WAI, STP) and decimal mode: **256 of 256**.
- **C6** speed: multi-cycle divider (`WDM DIV`), measurement of the maximum frequency.
- **C7** extensions: more `WDM`, prefetch, optional 32-bit mode.

## Rules (do not break)

- In SNES mode, make the CPU behave like the real 65C816. Run the `WDM` extensions only with
  `$5F01 = 2` (input `ext_en` of the core).
- Keep each opcode in `tests/cpu_pass.txt` passing. After progress, run `make cpu-update` and
  check the difference of the file.
- Keep the public vectors outside the repository. Use the unchanged vectors as the official score.
  Use `--d0` and `--page1` only for diagnosis.
- Write `sim/cpu_ref.py` from the documented behavior of the processor, without looking at the Verilog.
  To solve a difference, find which of the two is wrong.
- In the test bench, only the adapter file `tb/cpu_adapt_<core>.vh` reads the internal registers of a core.
