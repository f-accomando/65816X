# Target, budget, and bottlenecks

The numbers are **estimates** (±30%), except where the text says "measured". The `make synth` results for
the current design are in [VERIFICATION.md](VERIFICATION.md). The project has one target (HANDOFF,
decision 10).

## Target resources

| FPGA | LUT4 | BRAM | Multipliers |
|---|---|---|---|
| ECP5 LFE5U-85F | 83,640 | ~468 KB (208 blocks of 2.25 KB) | 156 |

## Content of the design

- 2 cores 65816X (SA-1 style), 16 KB scratchpad for each core, 4 separate buses
  (instructions, data, DMA, peripherals).
- MUL, DIV, MAC, T&L, DOT3, CROSS3, ROT; 2 advanced DMA engines.
- PPU+ at 2 px/clk: bilinear, perspective, alpha, fog, toon table, 2-3 stage combiner,
  bloom, DXT1 decoder; Z-buffer for each tile in BRAM; 3D at 256x224 and 30 fps.
- Audio: 16 voices at 44.1 kHz with reverb, plus the original DSP at 32 kHz.
- Load SuperFX, DSP-1, and Cx4 as an alternative bitstream. No FPU and no RISC-V in the plan.

## Logic budget (2026-11-28)

Numbers without "measured" are estimates (about 30%).

### The original SNES, without extensions

| Block | LUT4 | Kind |
|---|---|---|
| 65C816 processor (the module holds the extensions too) | 3,200 | measured |
| 5A22: DMA and math | 1,600 | measured |
| 5A22: HDMA, video interrupts, controller ports | 1,300 | estimate |
| PPU: timing, registers, memories | 800 | measured |
| PPU: backgrounds, sprites, effects | 9,000 | estimate |
| Audio: SPC700 and DSP | 7,000 | estimate |
| Memories, cartridge, SDRAM controller | 2,600 | estimate |
| Video output | 1,000 | estimate |
| **Total** | **about 26,500 (32% of the 85F)** | |

The chips of some cartridges (SA-1, Super FX, DSP-1, and others) add about 15,000-20,000 LUT4.

### The enhanced machine without compromises

| Addition | LUT4 |
|---|---|
| Original system | 26,500 |
| Second processor | 3,500 |
| All extensions: R0-R7, vector operations, prefetch, caches, 32-bit mode, FPU | 16,000 |
| Full PPU+ with 2 copy engines | 31,000 |
| 16 audio voices with reverb | 5,500 |
| Start, SD card, keyboard, network link | 2,500 |
| **Total** | **about 85,000 (about 100%)** |

- Plan for 85% of the FPGA as the practical limit: about 71,000 LUT4.
- Without the 32-bit mode (5,000), the FPU (4,000), and the data cache (2,600): about 73,000 (87%).
- Load the cartridge chips as an alternative bitstream.

## BRAM budget

One `DP16KD` block holds 2 KB. The 85F has 208. The original memories are calculated, the
additions are estimates.

| Memory | Blocks |
|---|---|
| WRAM 128 KB | 64 |
| VRAM 64 KB | 32 |
| ARAM 64 KB | 32 |
| CGRAM and OAM | 2 |
| Boot ROM 8 KB | 4 |
| PPU and HDMI line buffers | 4 |
| Scratchpad (16 KB for each core) | 16 |
| I-cache (4 KB for each core) | 4 |
| Z and color for each tile | 8 |
| Texture cache | 4 |
| Reverb (100 ms stereo) | 9 |
| FIFO | 2 |
| **Total** | **181 / 208 (87%)** |

The PPU plan counts more blocks for the PPU+ (221, section 2.7 of the plan). Question Q10 of that
plan stays open: put the WRAM in SDRAM, or drop the reverb buffer.

The ROM is always in SDRAM. Today (measured) the design uses 128 blocks: WRAM 64, VRAM 32. Then 29
are for the placeholder ROM, and 1 for the decode table of the processor. The colour and sprite
memories take 2 blocks.

## Bottlenecks

| Bottleneck | Solution | Remaining limit |
|---|---|---|
| Dead cycles and 3.58 MHz clock | prefetch, fewer dead cycles, 50-80 MHz clock | timing-sensitive games stay in SNES mode |
| Shared 8-bit bus | 4 separate buses | the SDRAM stays shared |
| SDRAM bandwidth (~330 MB/s) | Z and color for each tile in BRAM, DXT1, 3D at 256x224 | scenes with many textures |
| MUL/DIV in software | parallel units, T&L | - |
| Animation, AI, collisions | second core as a worker, DOT3/CROSS3 | real limit: ~20-30k triangles for each frame |
| DMA stops the CPU | dedicated DMA bus, command lists | contention on the SDRAM |
| BRAM almost full | scratchpad instead of caches | no margin for L1/L2 |

## FPU and cache (optional)

- **Single-precision FPU**: ~3-5k LUT and 2-4 multipliers. You need it only to write C with floats
  (this needs RISC-V or WDM float instructions). 16.16 fixed point with MAC is sufficient for the planned 3D.
- **L1 cache** (4 KB for each core): ~0.8k LUT (instructions) / ~1.3k (data) and ~3 BRAM blocks each.
  **64 KB L2**: ~32 blocks, it does not fit.
- Recommended choice: only a 4 KB I-cache for each core (read-only, no coherence problem).
  Disable it in SNES mode. Non-cacheable areas: `$2100-$21FF`, `$4000-$43FF`, shared WRAM.

## "Cel-shaded" look

A Wind Waker style does not need GameCube emulation. It needs a toon table (~1k LUT),
a 2-3 stage combiner (~2-4k), a second texture (~2k), bloom (~1-2k), and DXT1 (~1k): about +5-10k LUT.
The bottleneck is the CPU, not the rasterizer.
