# Variants, budget, and bottlenecks

The numbers are **estimates** (±30%), except where the text says "measured". The `make synth` results for
the current skeleton are in [VERIFICATION.md](VERIFICATION.md).

## Target resources

| FPGA | LUT | BRAM | Multipliers |
|---|---|---|---|
| ECP5 LFE5U-45F | ~44k | ~243 KB (108 blocks of 2.25 KB) | 72 |
| ECP5 LFE5U-85F | ~84k | ~468 KB (208 blocks) | 156 |

## Variant A (ECP5-45F)

- 1 core 65816X, 3-stage prefetch, 16 KB scratchpad.
- MUL, DIV, and MAC units; 1 advanced DMA engine; 3 buses.
- PPU+ at 1 px/clk with Gouraud/affine and a toon table.
- Audio: original DSP (8 voices, 32 kHz).
- WRAM in SDRAM, except the first 8 KB in BRAM.
- Estimate: ~37k LUT (84%), BRAM ~87% (see the numbers below).

## Variant B (ECP5-85F)

- 2 cores 65816X (SA-1 style), 16 KB scratchpad for each core, 4 separate buses
  (instructions, data, DMA, peripherals).
- MUL, DIV, MAC, T&L, DOT3, CROSS3, ROT; 2 advanced DMA engines.
- PPU+ at 2 px/clk: bilinear, perspective, alpha, fog, toon table, 2-3 stage combiner,
  bloom, DXT1 decoder; Z-buffer for each tile in BRAM; 320x240 at 30 fps.
- Audio: 16 voices at 44.1 kHz with reverb, plus the original DSP at 32 kHz.
- No SuperFX/DSP-1/Cx4 (load them as an alternative bitstream), no FPU, and no RISC-V.
- Estimate: ~73k LUT (87%), BRAM ~87% (see the numbers below).

## BRAM budget

One `DP16KD` block holds 2 KB. 45F: 108 blocks; 85F: 208. The original memories are calculated, the
additions are estimates.

| Memory | A | B |
|---|---|---|
| WRAM 128 KB | 4 (only the first 8 KB; the rest in SDRAM) | 64 |
| VRAM 64 KB | 32 | 32 |
| ARAM 64 KB | 32 | 32 |
| CGRAM and OAM | 2 | 2 |
| Boot ROM 8 KB | 4 | 4 |
| PPU and HDMI line buffers | 4 | 4 |
| Scratchpad (16 KB for each core) | 8 | 16 |
| I-cache (4 KB for each core) | - | 4 |
| Z and color for each tile | 4 | 8 |
| Texture cache | 2 | 4 |
| Reverb (100 ms stereo) | - | 9 |
| FIFO | 2 | 2 |
| **Total** | **94 / 108 (87%)** | **181 / 208 (87%)** |

In A, the original SNES memories alone (130 blocks) exceed the capacity: the WRAM must be in SDRAM.
The ROM is always in SDRAM. Today (measured) the skeleton uses 126 blocks: WRAM 64, VRAM 32, 29
for the placeholder ROM, and 1 for the decode table of the processor.

## Bottlenecks

| Bottleneck | Solution | Remaining limit |
|---|---|---|
| Dead cycles and 3.58 MHz clock | prefetch, fewer dead cycles, 50-80 MHz clock | timing-sensitive games stay in SNES mode |
| Shared 8-bit bus | 4 separate buses | the SDRAM stays shared |
| SDRAM bandwidth (~330 MB/s) | Z and color for each tile in BRAM, DXT1, 320x240 | scenes with many textures |
| MUL/DIV in software | parallel units, T&L | - |
| Animation, AI, collisions | second core as a worker, DOT3/CROSS3 | real limit: ~20-30k triangles for each frame |
| DMA stops the CPU | dedicated DMA bus, command lists | contention on the SDRAM |
| BRAM almost full | scratchpad instead of caches | no margin for L1/L2 |

## FPU and cache (optional)

- **Single-precision FPU**: ~3-5k LUT and 2-4 multipliers. You need it only to write C with floats
  (this needs RISC-V or WDM float instructions). 16.16 fixed point with MAC is sufficient for the planned 3D.
- **L1 cache** (4 KB for each core): ~0.8k LUT (instructions) / ~1.3k (data) and ~3 BRAM blocks each.
  **64 KB L2**: ~32 blocks, it does not fit in B.
- Recommended choice: only a 4 KB I-cache for each core (read-only, no coherence problem).
  Disable it in SNES mode. Non-cacheable areas: `$2100-$21FF`, `$4000-$43FF`, shared WRAM.

## "Cel-shaded" look

A Wind Waker style does not need GameCube emulation. It needs a toon table (~1k LUT),
a 2-3 stage combiner (~2-4k), a second texture (~2k), bloom (~1-2k), and DXT1 (~1k): about +5-10k LUT.
The bottleneck is the CPU, not the rasterizer.
