# CPU

The core is `c816` in `rtl/cpu/` (design: [cpu-core.md](../design/cpu-core.md)).
Test bench: `tb/tb_cpu.v`, with vectors from `sim/cpu_ref.py`.
The list of what must continue to pass is in `tests/cpu_pass.txt`.

## Status

- **All 256 opcodes** of the 65C816, cycle by cycle. One CPU cycle is 2 FPGA clocks.
- Public vectors, unchanged: **256 opcodes pass**; 5,080,400 of 5,080,400 vectors; 0 cycle differences.
- Own vectors (`make cpu`): 102,400 of 102,400 vectors, with all cycles.
- The reference model agrees with all 5,080,400 public vectors, cycle by cycle. Our own vectors thus
  check the cycles in the CI.
- Interrupts (`make cpu-int`): reset, NMI, IRQ, BRK, COP, RTI, WAI, STP, and the NMI of the system.
  The same test counts the cycles of `WDM MUL` (2) and `WDM DIV` (11).
- Signed extensions (C7a): `MULS`, `DIVS`, `MACS`, `MACLD`, and the version register `$5F03`.
  `make unit` checks the unit with 20,000 operations
  ([cpu-extensions.md](../design/cpu-extensions.md)).
- `make cpu-mutation`: 32 of 32 faults found.
- `WDM` extensions: the system test checks them (MUL, DIV, MAC, MACRD, the two modes without effect,
  and emulation mode).
  `WDM DIV` uses a sequential divider.
- Differences from the real chip (the public vectors do not cover them):

| Part | Difference |
|---|---|
| interrupt timing | the core samples NMI and IRQ at the end of the last cycle; the real chip samples one cycle earlier |
| `WAI` | the core goes on one cycle after the request; the real chip needs more cycles |
| reset | modeled from the data sheet (7 cycles); not compared with a chip |
| `ABORT` | not implemented |
| memory speed | every cycle takes 2 FPGA clocks; the SNES 6, 8, and 12 master clocks are not emulated (F3) |

## Open work

To close a step, make `make check` pass.

- **Maximum frequency**: not measured. It needs nextpnr, which is not installed (F1b).
- **C7b** more extensions: R0-R7, DOT3, CROSS3, then MUL32 and DIV32. The owner approves the
  encoding first ([cpu-extensions.md](../design/cpu-extensions.md), section 3).
- **Prefetch**: after the real memory (F4).
- **32-bit mode**: an owner decision (HANDOFF, question 2).

## Rules (do not break)

- In SNES mode, make the CPU behave like the real 65C816. Run the `WDM` extensions only with
  `$5F01 = 2` (input `ext_en` of the core) and in native mode (`E = 0`).
- Run one sequence step for each cycle of the real chip. Check the cycles with the public vectors
  and `SST_FLAGS=--bus` after a change to the sequences.
- Change the sequences and the decode only in `rtl/cpu/c816_tables.txt`. Then run `make tables`.
- Keep all 256 opcodes passing the public vectors. Run `make cpu-public SST_FLAGS=--bus` after a
  change to the core.
- Keep each opcode in `tests/cpu_pass.txt` passing. After progress, run `make cpu-update` and
  check the difference of the file.
- Keep the public vectors outside the repository. Use the unchanged vectors as the official score.
  Use `--d0` and `--page1` only for diagnosis.
- Write `sim/cpu_ref.py` from the documented behavior of the processor, without looking at the Verilog.
  To solve a difference, find which of the two is wrong.
- In the test bench, only the adapter file `tb/cpu_adapt_<core>.vh` reads the internal registers of a core.
