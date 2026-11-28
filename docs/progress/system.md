# System

All parts except the core: 5A22, memory, PPU, APU, cartridge, extensions, boards, verification.
The phases are in [ROADMAP.md](../ROADMAP.md). The open questions are in [HANDOFF.md](../../HANDOFF.md), section 9.

## Open work

- **CI**: GitHub warns that `actions/checkout@v4` and `actions/upload-artifact@v4` use Node.js 20,
  which is deprecated. Move to versions that use Node.js 24.
- **Synthesis**: find why Yosys 0.33 (CI) counts many more equivalent LUT4 than Yosys 0.52
  (13307 against 5876 after step C5)
  (see [VERIFICATION.md](../VERIFICATION.md), section 5).
- **Assembler**: `sim/asm.py` knows only part of the instructions and addressing modes of the core.
- **IRQ timers**: the H and V timers of the 5A22 (`$4207-$420A`) and their IRQ.
- **F1b**: minimal board top, pins, nextpnr in the CI. It depends on the choice of the board.
- From F3: see the roadmap.

## Rules (do not break)

- Ask the user before you change a user decision (HANDOFF, section 3).
- List the RTL sources only in `rtl/files.f`.
- Give each large memory one address, with a registered read. Otherwise it does not go into BRAM.
- Give each new function a check and at least one mutant.
- Compute each quotient and remainder of `rtl/` in steps. A `/` or `%` operator makes large and
  slow logic.
- Keep the manual true: `make manual-check` must pass (see `manuals/README.md`).
