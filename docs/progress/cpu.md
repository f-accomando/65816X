# CPU

Core 65816X: `rtl/cpu65816x.v`. Test bench: `tb/tb_cpu.v`, with vectors from `sim/cpu_ref.py`.
The list of what must continue to pass is in `tests/cpu_pass.txt`.

## Status (measured with `make cpu`)

- 53 of 256 opcodes implemented; **47 pass the test bench** in native and emulation mode.
- 20,838 of 21,200 vectors pass (200 for each opcode and mode). Cycles are not checked.
- Differences found:

| Opcode | Mode | Cause |
|---|---|---|
| `JSR`, `RTS`, `PHA`, `PLA` | emulation | the stack does not stay in page 1 |
| `XCE` | native | the change to emulation does not force S into page 1 |
| `SEP` | both | the D flag (decimal) is missing |

## Open work

To close a step, make its opcodes pass the test bench and make `make check` pass.

- **C1** (test bench, remaining): public vectors SingleStepTests/65816 (MIT license, commit
  `307c63f`, 515 files, about 2.6 GB; for the 53 opcodes of today, 106 files, 457 MB). Get the permission
  of the user to download them. Then write a converter to the format of `sim/cpu_vectors.py`.
  Then check the cycles. Keep the vectors outside the repository.
- **C2** reorganize the core: table decode, one ALU, separate address calculation, one sequence step
  for each cycle of the real chip; D register and D flag; signal for an unimplemented opcode
  (`dbg_illegal`). This fixes the differences in the table above.
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
- Write `sim/cpu_ref.py` from the documented behavior of the processor, without looking at the Verilog.
  To solve a difference, find which of the two is wrong.
- In the test bench, only `load_state` and `state_diff` in `tb/tb_cpu.v` read the internal registers of the core.
