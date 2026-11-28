# 65816X

A Verilog starting point for an **enhanced SNES on an FPGA** (target: Lattice ECP5, ULX3S board).
It has an improved 65816 that is compatible with SNES ROMs, with the DMA and multiplier of the Ricoh 5A22.
It also has optional "enhanced" extensions and a PPU that will later contain a 3D pipeline.

The project starts from the **multi-chip structure of the original SNES** (not the 1-chip version).
5A22, PPU, APU, WRAM, and cartridge are separate modules. One 8-bit bus connects them.

## Status

The skeleton works. The Python mini simulator, Icarus Verilog, and yosys synthesis for ECP5 verify it.
The CI on GitHub passes. Measured: 128 BRAM blocks, and about 5,700 LUT with Yosys 0.52. It fits in the 85F. It does not fit in the 45F yet (BRAM).
CPU: all 256 opcodes pass all 5,080,400 public test vectors, cycle by cycle.
**Not verified**: placement, maximum frequency, verilator, and real hardware.
Details are in [docs/VERIFICATION.md](docs/VERIFICATION.md) and [docs/progress/cpu.md](docs/progress/cpu.md).

| Module | File | Status |
|---|---|---|
| Core 65816X | `rtl/cpu/` | all 256 opcodes, cycle by cycle (2 clocks for each CPU cycle); NMI, IRQ, reset |
| Ricoh 5A22 | `rtl/s_cpu_5a22.v` | registers `$42xx`, mul/div, general DMA (8 channels, modes 0-7), no HDMA |
| PPU1/PPU2 | `rtl/ppu/` | SNES timing, all registers and memories; the picture shows only the backdrop colour |
| SPC700 + DSP | `rtl/apu_stub.v` | 4 ports `$2140-$2143` with echo and signature `$AA/$BB` |
| WRAM | `rtl/wram.v` | 128 KB, mirrors, port `$2180-$2183` |
| Cartridge | `rtl/cart_rom.v` | LoROM 64 KB (placeholder for the SDRAM) |
| Extensions | `rtl/ext_regs.v` | enhanced registers in `$5F00-$5FFF` |
| Top | `rtl/snes_plus_top.v` | connects all modules and selects the read data |

## Quick use

```
make test        # assemble tests/test_program.asm and run the system checks (Python 3 only)
make mutation    # insert faults in the RTL and verify that the tests find each one
make iverilog    # the same checks with Icarus Verilog
make unit        # test for each module (WRAM against the reference model)
make cpu         # test bench of the CPU only: score in build/cpu_score.txt
make cpu-public SST=<folder>   # the same with the public vectors (not in the repository)
make synth       # ECP5 synthesis with yosys and budget; BUDGET="A B" checks both variants
make manual      # build the PDF manual (needs reportlab)
make check       # everything that the CI runs
```

## Documents

- [The manual (PDF)](manuals/pdf/65816x.pdf): for the people who use the project. Its text and rules are in [manuals/](manuals/README.md).
- [docs/design/cpu-core.md](docs/design/cpu-core.md): design of the CPU core.
- [docs/design/cpu-extensions.md](docs/design/cpu-extensions.md): the CPU extensions and the proposals for more.
- [docs/design/ppu-plan.md](docs/design/ppu-plan.md): plan of the original PPU and of the enhanced PPU+.
- [CLAUDE.md](CLAUDE.md): work rules for Claude Code sessions.
- [docs/progress/cpu.md](docs/progress/cpu.md) and [docs/progress/system.md](docs/progress/system.md): status, open work, and rules of each area.
- [HANDOFF.md](HANDOFF.md): for the next session: user decisions, proposals and results, ideas not yet in the code, open questions, next steps.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): bus, memory map, supported opcodes, WDM extensions, limits.
- [docs/VARIANTS.md](docs/VARIANTS.md): variants A (ECP5-45F) and B (ECP5-85F), LUT and BRAM budget, bottlenecks, FPU and cache.
- [docs/ROADMAP.md](docs/ROADMAP.md): project phases and next steps.
- [docs/VERIFICATION.md](docs/VERIFICATION.md): check commands, synthesis budget, measured results.

## Included tools

- `sim/asm.py`: assembler for the supported subset (`python3 sim/asm.py in.asm rom.hex`).
- `sim/vsim.py`: mini simulator for a synchronous subset of Verilog, with one clock.
  It is a regression test without dependencies. It does not replace iverilog or verilator.

The LUT and BRAM numbers for functions not yet written are estimates (±30%), not synthesis results.
The repository has no license. The owner of the repository must add one.
