# HANDOFF - 65816X (SNES+ on FPGA)

This document passes the work to another Claude Code session. It records the user decisions.
It records the proposals of the user and of Claude, with the result of each.
It also records the ideas not yet in the code, the open points, and the next steps.

Date: 2026-11-27. Repository: `f-accomando/65816X`. Main branch: `main`.

> All numbers of LUT, BRAM, MHz, and fps in this file are **estimates** (±30%), except where the text
> says "measured".

## 1. How to work with this user

- The user usually writes in **Italian**: reply in the language of the message.
  Write the project documents in English with ASD-STE100.
- The user uses Claude from an **iPhone, without a physical keyboard**. Send downloadable files and verify with tests.
  **Do not offer live or interactive demos** (canvas, games with a keyboard): the user cannot use them.
- Give short and direct answers. Mark estimates as estimates.
- State clearly what is NOT verified. Do not present estimates as measurements.

## 2. Code status

The Verilog skeleton follows the **multi-chip structure of the original SNES** (not the 1-chip):

| Module | File | Status |
|---|---|---|
| Core 65816X | `rtl/cpu65816x.v` | subset of the opcodes, no interrupts, timing not cycle-accurate |
| Ricoh 5A22 | `rtl/s_cpu_5a22.v` | registers `$42xx`, instant mul/div, general DMA 8 channels (modes 0-7), no HDMA |
| PPU1/PPU2 | `rtl/ppu_stub.v` | only timing and VRAM (`$2115-$2119`, `$2139-$213A`) |
| SPC700 + DSP | `rtl/apu_stub.v` | 4 ports with echo, signature `$AA/$BB` |
| WRAM | `rtl/wram.v` | 128 KB, mirrors, port `$2180-$2183` |
| Cartridge | `rtl/cart_rom.v` | LoROM 64 KB (placeholder for the SDRAM) |
| Extensions | `rtl/ext_regs.v` | `$5F00` ID (`$58`), `$5F01` mode (2 = extended, enables `WDM`), `$5F02` speed |
| Top | `rtl/snes_plus_top.v` | connects all modules |

Verification done (measured, `make check`):
- `make test` and `make iverilog`: 56 checks.
- `make mutation`: 10 of 10 faults found.
- `make unit`: no differences.
- `make cpu`: 47 of 256 opcodes.
- yosys synthesis: 125 BRAM blocks and about 4,400 LUT.

**Never run with verilator or nextpnr, or on a board.** Details are in `docs/VERIFICATION.md`.
The WRAM now uses one address. The previous version did not go into BRAM, and the
project did not fit in either FPGA.

### Traps of the current code

- Bus read = 2 cycles (`ph` 0 sends the address, `ph` 1 captures); write = 1 cycle. Read side
  effects occur only in the cycle with `rd`.
- The DMA stops the CPU only at an instruction boundary (`halt` acts in `ST_FETCH` with `ph=0`).
- An unknown opcode is a silent NOP: this hides bugs. Replace it with an error signal in simulation.
- `WDM DIV` uses combinational `/` and `%`: they are large and slow in synthesis. Make them sequential.
- The WDM extensions assume 16-bit A and X.
- `sim/vsim.py` supports only a subset of Verilog (one clock, no instance parameters,
  generate, or function). If the RTL needs more, use iverilog or verilator.
- Give each large memory one read address. Otherwise it goes into logic
  (`make synth` reports it).
- With `iverilog -g2012`, the word `ref` is reserved.
- The VRAM read does not model the prefetch of the original (a declared simplification).

## 3. User decisions (ask before you reopen them)

1. **Target**: ECP5 FPGA on the ULX3S, two variants: A (45F, ~44k LUT) and B (85F, ~84k LUT).
2. **Compatibility** with SNES ROMs and cartridges; the extensions are optional ("option C": compatible and extensible). No "new technologies".
3. **Start from the original multi-chip SNES structure**, not from the 1-chip version.
4. **Programmable on the machine**: keyboard, assembly, and C.
5. **Audio of B: 16 voices at 44.1 kHz** (the user proposed 24 voices as on the PS1, then chose 16).
6. **Resolution**: no 480/720; keep SNES resolutions (the user was interested in double resolution and sprites with the same architecture).
7. **Look**: "Wind Waker" sharpness (clean polygons and textures, without the blur of the N64) without GameCube emulation.

## 4. Proposals of the user (from ChatGPT chats) and results

Source: two shared ChatGPT chats. From the first link, only the list of questions was read. From both,
only the first answers were pasted (CPU section). The other answers are not available.

| Idea | Result | Reason |
|---|---|---|
| Two modes: SNES and Enhanced | **Adopted** | same ISA, no loss of compatibility |
| "Controlled accelerated timing" (fast but keeps the PPU and peripheral windows) | **Adopted** | it becomes the middle mode: SNES / accelerated / enhanced (`$5F01`) |
| Extensions through `WDM`: MUL32, DIV32, MAC, MOV32, FILL, BLIT, SIN/COS, ROT, DOT3, CROSS3 | **Partial** | the RTL has MUL, DIV, MAC, MACRD, MACCLR; the rest is to do |
| 32-bit registers R0-R7 and ACC32, invisible in legacy mode | To do | they do not touch SNES code |
| 32-bit internal ALU | **To decide** | proposal of Claude: 32-bit extended mode with a prefix (the W65C832 was never produced) |
| In-order pipeline with 3-5 stages | Changed: 3-stage prefetch | a 65816 with a byte bus gains little from 5 stages |
| Branch prediction | Postponed | short pipeline, little gain |
| L1 cache 4-8 KB (I and D) + L2 32-128 KB | **Changed**: 16 KB scratchpad for each core + optional 4 KB I-cache for each core; no L2 | BRAM is already at 88-94%, and coherence with I/O and DMA is the difficult point |
| Separate buses: instructions, data, DMA, peripherals | **Adopted** in B (3 buses in A) | the DMA does not block the fetch |
| DMA with 8-16 channels, bursts, command lists, priorities | Changed: 8 legacy channels + advanced engines (1 in A, 2 in B) | the legacy DMA must stay identical |
| 64-bit internal bus | **Rejected** | the SDRAM of the ULX3S is 16-bit |
| 8 vector registers of 128 bits | **Rejected** | too many LUT for a 65816 |
| 50-100 MHz clock | Reduced to 50-80 MHz | realistic on ECP5 |
| Parallel MUL/DIV/MAC/DSP units, atomic operations, bit manipulation | MUL/DIV/MAC adopted; the rest not evaluated | |
| Development in phases: core, 65816X, 5A22 layer, enhanced system | **Adopted** | it is the roadmap |
| "Enhanced" SID with 8 channels / 44.1 kHz on FPGA | Replaced by the 16-voice choice | a faithful analog SID is not possible on FPGA; see section 7 |
| Switch OLED screens for own projects | **No answer** | the question ended inside the pasted text and was never discussed |

## 5. Proposal of Claude

### Variants (details in `docs/VARIANTS.md`)

| | A (ECP5-45F) | B (ECP5-85F) |
|---|---|---|
| Core | 1 core 65816X | 2 cores 65816X (SA-1 style) |
| Bus | 3 | 4 separate |
| Math | MUL, DIV, MAC | MUL, DIV, MAC, T&L, DOT3, CROSS3, ROT |
| DMA | 1 advanced engine | 2 advanced engines |
| PPU+ | 1 px/clk, toon | 2 px/clk, bilinear, perspective, alpha, fog, toon, 2-3 stage combiner, bloom, DXT1 |
| Audio | original DSP 8 voices 32 kHz | 16 voices 44.1 kHz with reverb + original DSP 32 kHz |
| Estimate | ~37k LUT (84%), BRAM ~87% (WRAM in SDRAM) | ~73k LUT (87%), BRAM ~87% |

B excludes SuperFX/DSP-1/Cx4 (load them as an alternative bitstream), FPU, and RISC-V: they do not fit.

### PPU+ pipeline (to implement)

1. Command FIFO
2. Vertex (MAC)
3. Triangle setup
4. Rasterizer (1 px/clk in A, 2 px/clk in B)
5. Texture + Z (Z for each tile in BRAM)
6. Shading
7. Framebuffer (SDRAM, double buffer)
8. Compositor with the legacy layers

The blitter is the rasterizer on a quad (this doubles the sprites). Planned 3D resolution: 320x240 at 30 fps,
about 20-30k triangles for each frame. Cel-shaded look: toon table (~1k LUT), 2-3 stage combiner (~2-4k), second texture
(~2k), bloom (~1-2k), DXT1 (~1k): +5-10k LUT in total. The real limit is the CPU (animation, AI, collisions), not the rasterizer.

### Other choices of Claude

- **Timing modes**: SNES (identical to the original), accelerated, enhanced (`$5F01`).
- **32-bit extension** with a prefix (optional, ~+3k LUT, to decide).
- **Single-precision FPU**: ~3-5k LUT, useful only with RISC-V or WDM float instructions; 16.16 fixed point with MAC is sufficient for the planned 3D.
- **Cache**: only a 4 KB read-only I-cache for each core; non-cacheable areas `$2100-$21FF`, `$4000-$43FF`, shared WRAM; disabled in SNES mode.
- **Audio**: 16 voices with reverb ~5k LUT; it needs a 22.5792 MHz oscillator or a resampler (~0.5k LUT); the original DSP stays at 32 kHz with a rate converter.
- **Boot and OS**: 4-8 KB boot ROM in BRAM, over the vectors, disabled with a register write (to assign in `$5F00-$5FFF`); OS from SD or flash loaded in RAM (monitor, editor, on-device assembler, BASIC), ~8-16 KB.
- **Quad-core cluster** (discussed, not in the variants): core 0 + 3 workers. Each has 16 KB of local BRAM and a DMA. They use mailboxes, semaphores, and IRQ. All see the same map with a core ID. In compatible mode, only core 0 is active.
- **Alternative with real chips**: WDC W65C816S (~14 MHz) and a Cortex-M33/M7 MCU instead of FPU + RISC-V. That needs ~66k LUT in total + ~1k LUT of bridge. Other options: salvaged original PPU/APU, a glue CPLD, or an "enhancer" cartridge such as the FXPak.

### List of improvements, in order

1. Verification with real tools: `make iverilog` and `make synth` done; remaining: nextpnr (real frequency) and the first CI run.
2. Sequential divider instead of the combinational `/` (small and certain).
3. Interrupts (NMI, IRQ, BRK, COP): almost all games synchronize on the NMI; the flag is in the registers, but the core ignores it.
4. Full opcode set and verification with test vectors for each instruction (public 65816 suites, if available) and with the reference of section 8.
5. Prefetch and one clock with enable for the 6/8/12 master clock cycles.
6. Real memory: SDRAM controller, ROM from SD, boot ROM overlay.
7. Show an image: HDMI and rendering of modes 0-7, then PPU+.
8. APU: at least a fake boot handshake (the current echo probably blocks games), then SPC700 and S-DSP.
9. HDMA and cycle-correct DMA.
10. Enhanced extensions (DOT3, CROSS3, ROT, R0-R7, advanced DMA), then the second core and the I-cache.

## 6. Where the proposals differ (close them with the user)

| Topic | ChatGPT | Claude |
|---|---|---|
| Cache | L1 + L2 | scratchpad + I-cache, no L2 |
| Internal bus | 32/64 bit | 8 bit (as the original); 16-bit SDRAM |
| Pipeline | 5 stages, branch prediction | 3-stage prefetch, no prediction |
| DMA | 8-16 channels | 8 legacy channels + advanced engines |
| Clock | 50-100 MHz | 50-80 MHz |
| Registers | R0-R7 + 8 vector 128 bit | R0-R7 + ACC32, no vector registers |

## 7. Ideas discussed but not in the code

- **C64 + SNES**: programming and BASIC, keyboard and SID audio of the C64, with SNES games kept. Hints (verify
  them on the official pinout): on the cartridge connector, pin 31 SOUND-L and pin 62 SOUND-R go into the mixer
  of the console; pin 1 MCK at 21.47727 MHz divided by 21 is ~1.0227 MHz, the clock of the NTSC C64; pin 18 /IRQ. SID substitutes:
  SIDKick pico, ARMSID, FPGASID, USBSID-Pico. An FPGA cannot give a SID that is faithful to the analog chip.
  The filter is a model with two integrators. The analog variation of the 6581 also limits the fidelity.
  On a cartridge, use a real chip.
- **Parity with other consoles** (estimates of Claude):
  - PS1: 60-90k LUT (cores exist on a Cyclone V with 110k LE).
  - N64: 90-150k+ (needs a larger and faster FPGA; bandwidth and RDRAM timing problems).
  - GameCube: 250-500k+ (no FPGA core exists).

  They are out of reach for the ECP5-85F. At most, a very tight PS1 can fit.
- **Tools**: ca65 or WLA-DX assembler, Wiz; C with PVSnesLib (816-tcc) or Calypsi (`--target=SNES`). **cc65 does not
  support the 65816 as a C compiler.** No compiler knows the WDM extensions: extended C needs a
  new backend, or a RISC-V core. Microsoft released the 6502 BASIC with the MIT license (to verify).

## 8. Emulator in the project `f-accomando/bm`

The `bm` repository is a bare-metal console for Pi Zero W and RGB30, with Lua games.
It has an SNES machine in C and ARM assembly. It includes SA-1, Super FX, and DSP-1.
The files are `core/src/bm/snes_*.c`, `snes_cpu_arm.S`, `snes_ppu_arm.S`, and `api_snes.c`.
The user cartridge is `bm/snes`. Its reports on the Pi Zero W (Super Mario World, measured): frame ~14.5 ms of 16.6, with CPU ~2.2-2.5,
audio ~2.3, PPU ~9, drawing ~0.9; at 60 fps it is already at the limit.

Evaluation by Claude of an "enhanced mode" in the emulator (estimates on the numbers above):

| Enhanced part | On the Pi Zero W |
|---|---|
| WDM extensions (MUL, DIV, MAC, DOT3, CROSS3) | yes, they are native ARM operations |
| Advanced DMA | yes |
| PPU+ toon 3D (20-30k triangles) | yes, on the V3D engine (measured 49,956 triangles in 13.7 ms) |
| 16-voice audio 44.1 kHz | tight (~4-5 ms): OK at 30 fps |
| 1 core up to ~10 MHz equivalent | yes (the emulator already runs the SA-1 at 10.74 MHz) |
| 2 cores at 50-80 MHz | no on the Pi Zero W (~8-12 MHz equivalent with half of the frame); RGB30 not measured |

Principles: the enhanced game must move the math into the native extensions; emulated speed must scale as `adapt` does;
3D at 30 fps; PPU+ on the V3D. The emulator is also a **reference for the RTL**.
Use its tests `tests/snes/cpu_golden.c` (`make test-snes-cpu`) and `ppu_equiv.c`.
They compare registers and memory with the Verilog on random programs.
A change to `bm` needs write access to that repository (that session had read access only). Do not change the golden tests
of the SNES mode.

## 9. Open questions for the user

1. Which variant do we implement first, A or B?
2. 32-bit mode with a prefix: yes or no?
3. FPU and RISC-V, Cortex MCU, or none of the three?
4. License of the repository (not chosen).
5. Do you want the "enhanced mode" in the `bm` emulator, with access to it?
6. Do we discuss the question about the Switch OLED screens again?
7. Standalone machine or ARM in control (Pi Zero W, later possibly CM3)? In a standalone machine, the
   system lives in the FPGA, and a Raspberry is only a development tool. Proposal of Claude: a small boot ROM in the FPGA and an
   SPI host port; Pi Zero W first, CM3 only if it is not sufficient. It blocks phase F4 and the place of the host port.
8. Which ULX3S do you have (45F or 85F, how much SDRAM)? It blocks the board tests of F4.
9. Permission to download the 65816 test vectors (SingleStepTests) in the CI, without a copy in the repository?
   It blocks the second part of F2.

Question 1 blocks F4; questions 2 and 3 block F8 and F10; question 4 blocks the import of third-party files.

## 10. Suggested next step

The work rules are in `CLAUDE.md`, and the open work is in `docs/progress/`. First step: push `main`
and make the CI pass.
Criteria for each step:
- `make check` passes.
- Each new function has a check and at least one fault in `sim/mutation_check.py`.
- The documents in `docs/` are up to date.
