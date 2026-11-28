# CPU

The core is `c816` in `rtl/cpu/` (design: [cpu-core.md](../design/cpu-core.md)).
Test bench: `tb/tb_cpu.v`, with vectors from `sim/cpu_ref.py`.
The list of what must continue to pass is in `tests/cpu_pass.txt`.

## Status

- 251 of 256 opcodes implemented, cycle by cycle. One CPU cycle is 2 FPGA clocks.
- Own vectors (`make cpu`): 251 opcodes pass, 100,400 of 100,400 vectors, with all cycles.
- Public vectors, unchanged: **221 opcodes pass**; 4,717,725 of 4,980,400 vectors; 0 cycle differences.
  The 30 opcodes that fail are the 15 forms of `ADC` and of `SBC`, only with D = 1.
- The reference model agrees with all 4,680,310 public vectors of its 251 opcodes that are not decimal
  `ADC` or `SBC`, cycle by cycle. Our own vectors thus check the cycles in the CI.
- `make cpu-mutation`: 22 of 22 faults found.
- `WDM` extensions: the system test checks them (MUL, DIV, MAC, MACRD, and the two modes without effect).
- Missing opcodes: `BRK`, `COP`, `RTI`, `WAI`, `STP`.
- Differences from the real chip:

| Part | Difference |
|---|---|
| `ADC`, `SBC` | no decimal arithmetic (step C5) |
| the 5 missing opcodes | they run as a NOP of 2 cycles and set `dbg_illegal` |
| interrupts | NMI and IRQ do not exist (step C5) |
| reset | two reads of the vector only; the real sequence is longer (step C5) |

## Open work

To close a step, make its opcodes pass the test bench and make `make check` pass.

- **C5** interrupts (NMI, IRQ, ABORT is optional, BRK, COP, RTI, WAI, STP) and decimal mode: **256 of 256**.
- **C6** speed: multi-cycle divider (`WDM DIV`), measurement of the maximum frequency.
- **C7** extensions: more `WDM`, prefetch, optional 32-bit mode.

## Rules (do not break)

- In SNES mode, make the CPU behave like the real 65C816. Run the `WDM` extensions only with
  `$5F01 = 2` (input `ext_en` of the core).
- Run one sequence step for each cycle of the real chip. Check the cycles with the public vectors
  and `SST_FLAGS=--bus` after a change to the sequences.
- Change the sequences and the decode only in `rtl/cpu/c816_tables.txt`. Then run `make tables`.
- Keep each opcode in `tests/cpu_pass.txt` passing. After progress, run `make cpu-update` and
  check the difference of the file.
- Keep the public vectors outside the repository. Use the unchanged vectors as the official score.
  Use `--d0` and `--page1` only for diagnosis.
- Write `sim/cpu_ref.py` from the documented behavior of the processor, without looking at the Verilog.
  To solve a difference, find which of the two is wrong.
- In the test bench, only the adapter file `tb/cpu_adapt_<core>.vh` reads the internal registers of a core.
