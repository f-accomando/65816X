# System

All parts except the core: 5A22, memory, PPU, APU, cartridge, extensions, boards, verification.
The phases are in [ROADMAP.md](../ROADMAP.md). The open questions are in [HANDOFF.md](../../HANDOFF.md), section 9.

## Open work

- **CI times**: after the next run on GitHub, record the time of each job in
  [VERIFICATION.md](../VERIFICATION.md), section 5. The one test `tb_ppu_timing` is now the longest part
  of `make unit` and `make ppu-mutation`.
- **CI**: GitHub warns that `actions/checkout@v4` and `actions/upload-artifact@v4` use Node.js 20,
  which is deprecated. Move to versions that use Node.js 24.
- **Synthesis**: find why Yosys 0.33 (CI) counts many more equivalent LUT4 than Yosys 0.52
  (7277 against 5411 after step C6)
  (see [VERIFICATION.md](../VERIFICATION.md), section 5).
- **Assembler**: `sim/asm.py` knows only part of the instructions and addressing modes of the core.
- **IRQ timers**: the H and V timers of the 5A22 (`$4207-$420A`) and their IRQ.
- **F1b**: minimal board top, pins, nextpnr in the CI. It depends on the choice of the board.
- **PPU**: do step P5 of [ppu-plan.md](../design/ppu-plan.md): modes 2 to 6, offset per tile, high
  resolution. The owner answered Q1. Q2-Q10 are open.
- **Backgrounds**: model a change of the background registers inside a line (step P16).
- **Brightness**: find the formula of the output for each value. Today the pictures use N / 15.
- **Video timing**: check the long dots, the NMI position, and the field value after reset. Use a
  chip or a third document.
- **Certus-N2 CT20**: before phase F9, check again the tools, the board, the price, and the data sheet
  ([VARIANTS.md](../VARIANTS.md)).
- From F3: see the roadmap.

## Rules (do not break)

- Ask the user before you change a user decision (HANDOFF, section 3).
- List the RTL sources only in `rtl/files.f`.
- Put the code that belongs to one FPGA family in `rtl/board/`. Write the rest of `rtl/` as plain
  Verilog, so that it can move to another FPGA.
- Count the video time with the enable `mce`. The master clock is never a clock net.
- Write `sim/ppu_ref.py` from the documented behavior, without looking at the Verilog.
- Change the CRC lists of `tests/ppu/` only with `make ppu-update`. Then check the difference.
- Keep the memory blocks of the PPU with one write port and two read ports. Do not read in the clock
  of a write: then the synthesis needs no copy.
- Give each large memory one address, with a registered read. Otherwise it does not go into BRAM.
- Give each new function a check and at least one mutant.
- Compute each quotient and remainder of `rtl/` in steps. A `/` or `%` operator makes large and
  slow logic.
- Keep the manual true: `make manual-check` must pass (see `manuals/README.md`).
