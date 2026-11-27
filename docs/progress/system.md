# System

All parts except the core: 5A22, memory, PPU, APU, cartridge, extensions, boards, verification.
The phases are in [ROADMAP.md](../ROADMAP.md). The open questions are in [HANDOFF.md](../../HANDOFF.md), section 9.

## Open work

- **CI**: GitHub warns that `actions/checkout@v4` and `actions/upload-artifact@v4` use Node.js 20,
  which is deprecated. Move to versions that use Node.js 24.
- **Synthesis**: find why Yosys 0.33 (CI) counts 12604 equivalent LUT4 and Yosys 0.52 counts 4393
  (see [VERIFICATION.md](../VERIFICATION.md), section 5).
- **F1**: sequential divider in the 5A22, with the latency of the original.
- **F1b**: minimal board top, pins, nextpnr in the CI. It depends on the choice of the board.
- From F3: see the roadmap.

## Rules (do not break)

- Ask the user before you change a user decision (HANDOFF, section 3).
- List the RTL sources only in `rtl/files.f`.
- Give each large memory one address, with a registered read. Otherwise it does not go into BRAM.
- Give each new function a check and at least one mutant.
- Keep the manual true: `make manual-check` must pass (see `manuals/README.md`).
