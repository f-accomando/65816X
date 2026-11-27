# CPU

The core is `c816` in `rtl/cpu/` (design: [cpu-core.md](../design/cpu-core.md)).
Test bench: `tb/tb_cpu.v`, with vectors from `sim/cpu_ref.py`.
The list of what must continue to pass is in `tests/cpu_pass.txt`.

## Status

- 53 of 256 opcodes implemented, cycle by cycle. One CPU cycle is 2 FPGA clocks.
- Own vectors (`make cpu`): 53 opcodes pass, 21,200 of 21,200 vectors.
- Public vectors, unchanged: **50 opcodes pass**; 1,032,847 of 1,060,000 vectors; 0 cycle differences.
- Public vectors with D = 0: 53 opcodes pass; 529,750 of 529,750 vectors.
- `WDM` extensions: the system test checks them (MUL, DIV, MAC, MACRD, and the two modes without effect).
- Differences from the real chip:

| Opcode | Difference |
|---|---|
| `ADC`, `SBC` | no decimal arithmetic (step C5) |
| opcodes without a table row | they run as a NOP of 2 cycles and set `dbg_illegal` |
| interrupts | NMI, IRQ, BRK, and COP do not exist (step C5) |
| reset | two reads of the vector only; the real sequence is longer (step C5) |


## Open work

To close a step, make its opcodes pass the test bench and make `make check` pass.


- **C2** open point: our own vectors carry no cycle counts, so the CI does not check the cycles.
  Only the public vectors check them, on a local computer. Choose how to close this gap.
- **C3** all addressing modes, with loads, stores, and arithmetic.
- **C4** remaining instructions: shifts, stack, transfers, jumps, block moves.
- **C5** interrupts (NMI, IRQ, BRK, COP, RTI, WAI, STP) and decimal mode: **256 of 256**.
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
