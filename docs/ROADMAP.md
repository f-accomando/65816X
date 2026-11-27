# Roadmap

Each phase depends on the previous one, unless the table says otherwise. To close a phase, verify its
criterion and make `make check` pass.

| Phase | Content | Verifiable completion | Risks |
|---|---|---|---|
| F1 | Sequential dividers: 5A22 with the latency of the original, `WDM DIV` | no `$div`/`$mod` cell before mapping; mutants on the divider | tests that depend on the instant division |
| F1b | Minimal board top, ULX3S pin file, nextpnr in the CI for 45k and 85k | placement report with maximum frequency | license of the imported pin file |
| F2 | NMI/IRQ/BRK/COP interrupts, all opcodes, signal for an unimplemented opcode (`dbg_illegal`), subfolders in `rtl/` | CPU-only harness in iverilog: vectors for all 256 opcodes in native and emulation mode | license and download of the vectors (SingleStepTests) |
| F3 | SNES timing: one clock with enable, 6/8/12 cycles, `bus_wait`, accelerated mode | cycle counts equal to the vectors; `bus_wait = 0` in SNES mode | reachable frequency |
| F4 | Real memory: `mp_*` port, SDRAM controller and arbiter, variants A/B, ROM from SD or UART, boot ROM | `make check` for A and B with an SDRAM model; memory test on the board | SDRAM timing, license of the model |
| F5 | PPU modes 0-7, OAM, CGRAM, HDMI output | simulation images equal to the expected images | LUT budget, VRAM bandwidth |
| F6 | SPC700 and S-DSP | SPC700 vectors; audio compared with the expected audio | boot handshake of the games |
| F7 | Compatibility: HDMA, cycle-correct DMA, LoROM/HiROM/ExHiROM mappers | public test ROMs with the expected result | edge cases (DMA WRAM -> `$2180`) |
| F8 | Extensions: remaining `WDM`, R0-R7, advanced DMA, optional 32-bit mode, monitor, keyboard, on-machine assembler | one test and one mutant for each | depends on questions 2 and 3 of HANDOFF |
| F9 | PPU+ toon 3D (rasterizer, Z for each tile, combiner) | images of test scenes; budget of A and B | SDRAM bandwidth |
| F10 | B only: second core, I-cache, 16-voice audio at 44.1 kHz | mailbox and semaphore tests; audio; budget of B | LUT at 85-90% (estimate) |

## Current order: CPU first

For now, develop only the CPU, in the steps C3-C7 of [progress/cpu.md](progress/cpu.md).
C3-C5 cover phase F2 and the part of F3 about internal cycles. C6 includes the `WDM DIV` divider of F1.
C7 is the CPU part of F8. The SNES bus timing (6, 8, 12 clock cycles) stays in F3.

## Next steps

1. C3: all addressing modes.
2. C4: remaining instructions.

## To decide: host port

This proposal is not approved. An SPI link in the FPGA loads ROMs, starts and stops the processor,
and reads the memory. A computer or a Raspberry Pi Zero W (later possibly a CM3) controls it.
If approved, it goes with F4. It depends on question 7 of HANDOFF (standalone machine or ARM in control).
