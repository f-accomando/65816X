# System

All parts except the core: 5A22, memory, PPU, APU, cartridge, extensions, boards, verification.
The phases are in [ROADMAP.md](../ROADMAP.md). The open questions are in [HANDOFF.md](../../HANDOFF.md), section 9.

## Open work

- **F0**: push `main` with the structure, the test bench, and the documents. Then check the first
  run of the CI on GitHub.
- **F1**: sequential divider in the 5A22, with the latency of the original.
- **F1b**: minimal board top, pins, nextpnr in the CI. It depends on the choice of the board.
- From F3: see the roadmap.

## Rules (do not break)

- Ask the user before you change a user decision (HANDOFF, section 3).
- List the RTL sources only in `rtl/files.f`.
- Give each large memory one address, with a registered read. Otherwise it does not go into BRAM.
- Give each new function a check and at least one mutant.
