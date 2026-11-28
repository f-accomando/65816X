# PPU development plan

Status: proposal. Date: 2026-11-28. This document plans the original PPU (part 1) and the enhanced PPU+ (part 2).
It changes no decision of `HANDOFF.md`, section 3. Steps P1 to P4 are done. The other steps have not started.
The open work of the whole system is in [progress/system.md](../progress/system.md).

## 0. How to read this document

| Marker | Meaning |
|---|---|
| [V] | Verified in the repository (file read on 2026-11-28) |
| [C] | SNES fact from general knowledge. Check it against documentation before you implement it |
| [E] | Estimate (±30%). No tool measured it |
| N=n | Necessity score of `CLAUDE.md` (1-3 standard model, 4-5 expensive model) |

### 0.1 Starting point [V]

- `rtl/ppu/ppu_timing.v` gives the line and frame timing (step P1). `rtl/ppu/ppu_top.v` holds it.
- `ppu_regs.v` holds all registers `$2100-$213F` and the three memories (step P3).
- VRAM is two arrays `vram_l` and `vram_h` (32768 x 8). `tests/test_program.expect` and `sim/run_tests.py` read `u_ppu.vram_l` and `u_ppu.vram_h`.
- `tb/tb_snes_nmi.v` expects the NMI at 306,900 to 307,100 clocks after reset.
- `rtl/s_cpu_5a22.v`: `.irq(1'b0)`; `$4212` gives only the vblank bit; `$420C` is stored, but no HDMA exists; `$4207-$420A` are not decoded.
- `sim/vsim.py` does not support instance parameters, `generate`, `function`/`task`, `signed`, x/z, or more than one clock. `make test` parses every file in `rtl/files.f`.
- `syn/budget.py`: 85F = 208 `DP16KD`, threshold 256 `TRELLIS_DPR16X4`. Today: 128 blocks (WRAM 64, VRAM 32, ROM 29, decode table 1, CGRAM and OAM 2).
- Bus: one CPU cycle = 2 FPGA clocks; `rd`/`wr` pulse for one clock in phase 0; the top registers `hit`; read data is valid one clock later.

### 0.2 Assumptions

- The ULX3S has a 25 MHz oscillator and a 16-bit SDRAM (32 MB assumed by `rtl/cart_rom.v`). Check the board (HANDOFF question 8).
- An ECP5 can send DVI at 640x480 with DDR outputs at 125 MHz. Other ULX3S projects do this [C]. Check their license before you copy anything.
- The `bm` reference (`ppu_equiv.c`) exists as HANDOFF section 8 says. This plan did not read it.

---

# PART 1 - Original PPU (PPU1 + PPU2)

## 1.1 Scope

Registers `$2100-$213F`. VRAM, CGRAM, and OAM with their access rules and the VRAM read prefetch.
Dot clock and line timing (NTSC and PAL). Modes 0-7, Mode 7 EXTBG, offset-per-tile, hi-res, pseudo-hires, interlace, overscan.
Sprites with the 32-sprite and 34-tile limits. Priorities, two windows, color math, mosaic, brightness.
H/V counters and latches. Dependencies in the 5A22: H/V IRQ timers, `$4212`, HDMA.
Video output on HDMI (DVI signal, no audio). Scaling and line buffer.

## 1.2 Clocking

| Clock or enable | Value | Source | Use |
|---|---|---|---|
| `clk_sys` | 50 MHz first [E for Fmax] | PLL, 2 x oscillator | CPU, 5A22, PPU, PPU+, all bus logic |
| `mce` (master-clock enable) | 21.47727 MHz NTSC, 21.28137 MHz PAL on average [C] | NCO (phase accumulator) in `clk_sys` | PPU timing, 5A22 timers, HDMA; later F3 CPU wait states |
| dot | 4 `mce` (6 for two long dots in each line) [C] | `ppu_timing` | pixel rate (256 or 512 pixels per line) |
| CPU cycle | 2 `clk_sys` (today); 6/8/12 `mce` in SNES mode after F3 | `c816_core`, `bus_wait` | CPU |
| `clk_pix` | 25 MHz | oscillator | video timing |
| `clk_tmds` | 125 MHz, DDR (250 Mbit/s) | PLL | TMDS serializer |

Rules:
- The master clock is not a clock net. It is the enable `mce`, one `clk_sys` pulse for each master clock.
- The PPU counts `mce` in all modes. Accelerated and enhanced modes change only the CPU speed. The frame rate stays 60.1 Hz (NTSC) or 50 Hz (PAL) [C].
- Each PPU operation for one dot completes in 4 `clk_sys` after the dot enable. Thus the design works for any `clk_sys >= master clock`.
- In simulation, the top ties `mce = 1`. Thus a master clock is one `clk_sys` and a frame takes about 357,000 clocks [C].
- Before F3, a CPU cycle is 2 `clk_sys`. On the board the CPU is then about 7 times faster than the original [E]. PPU tests do not depend on this.
- Only `rtl/board/` and `rtl/video/` have more than one clock. List them in a new file `rtl/board.f`, not in `rtl/files.f`. Thus `vsim.py` never parses them.

## 1.3 Architecture

```
 system bus: addr[23:0], rd, wr, wdata, rdata, hit          mce
        |                                                     |
 +------v-------------------+                         +-------v------+   hdot, hclk, vcnt, field,
 | ppu_regs                 |<--- h/v latch ----------| ppu_timing   |-- hblank, vblank, frame_start
 | $2100-$213F, latches,    |                         +-------+------+   --> s5a22_timer (NMI, IRQ)
 | MDR, counters, prefetch  |                                 | dot_en  --> s5a22_hdma
 +--+--------+--------+-----+                                 |
    |port A  |port A  |port A          register values        |
 +--v---+ +--v----+ +-v----+    +--------------------------------v-----------------+
 | vram | | cgram | | oam  |    | ppu_bgfetch -> ppu_bgpix x4 (modes 0-6, OPT,     |
 | 64KB | | 512 B | | 544 B|    |                mosaic)                           |
 +--+---+ +--+----+ +-+----+    | ppu_m7 (Mode 7, EXTBG, $2134 multiplier)          |
    |port B  |port B  |port B   | ppu_obj (evaluate, fetch) -> ppu_objbuf           |
    +--------+--------+-------->| ppu_win (W1, W2, logic, color window)            |
                                | ppu_prio (main and sub screen selection)         |
                                | ppu_math (color math, fixed color, brightness)   |
                                +-----------------------+--------------------------+
                                                        | pixel stream (clk_sys)
                         rtl/video (two clocks)         v
                         vid_linebuf (8 lines x 512, dual clock BRAM)
                                                        v clk_pix
                         vid_timing + vid_scale (2x2, centre, bob) -> tmds_enc x3 -> hdmi_phy_ecp5 -> GPDI
```

### Modules (files under `rtl/ppu/` unless stated)

| File | Function | Original chip | LUT [E] |
|---|---|---|---|
| `ppu_top.v` | holds all PPU modules; the bus ports and the instance name `u_ppu` of the old stub | both | 0.1k |
| `ppu_timing.v` | `mce` counters, long dots, short line, NTSC/PAL, field | PPU2 | 0.2k |
| `ppu_regs.v` | registers, write-twice latches, MDR, counters latch, STAT77/78 | both | 1.5k |
| `ppu_vram.v` | 2 x 32K x 8, port A (bus) and port B (render) | VRAM chips | 0.1k |
| `ppu_cgram.v`, `ppu_oam.v` | CGRAM 256 x 15; OAM 512 + 32 bytes | PPU2, PPU1 | 0.2k |
| `ppu_bgfetch.v` | one fetch sequencer for all BG layers on VRAM port B | PPU1 | 1.2k |
| `ppu_bgpix.v` (4 instances) | tile shift registers, palette, priority bit, mosaic, OPT | PPU1 | 1.6k |
| `ppu_m7.v` | Mode 7 affine path, multiplier for `$2134-$2136` | PPU1 | 1.0k, 2-3 MULT18X18D |
| `ppu_obj.v`, `ppu_objbuf.v` | range and time evaluation, tile fetch, line buffer | PPU1 | 1.5k |
| `ppu_win.v` | two windows, logic for each layer, color window | PPU2 | 0.4k |
| `ppu_prio.v` | priority tables of modes 0-7, main and sub screens | PPU2 | 0.6k |
| `ppu_math.v` | add, subtract, half, clip, prevent, fixed color, brightness | PPU2 | 0.6k |
| `rtl/mclk_nco.v` | NCO for `mce` (single clock, in `files.f`) | - | 0.05k |
| `rtl/s5a22_timer.v` | HTIME, VTIME, `$4200` bits 4-5, `$4211`, `$4212` | 5A22 | 0.3k |
| `rtl/s5a22_hdma.v` | HDMA for 8 channels | 5A22 | 0.8k |
| `rtl/video/vid_linebuf.v`, `vid_timing.v`, `vid_scale.v` | CDC line buffer, 640x480 timing, frame lock, 2x2 scale | - | 0.6k |
| `rtl/video/tmds_enc.v`, `rtl/board/hdmi_phy_ecp5.v` | DVI 8b/10b encoder, DDR outputs | - | 0.4k |

The split of the modules is by function, not by chip. The column "Original chip" keeps the mapping for the documents.

### Interfaces

- **System bus**: unchanged. The PPU accepts a read or write in any `clk_sys` clock. A register write acts at the next dot. `rdata` is registered and valid one clock after `rd`.
- **Read of a memory through a register** (`$2138`, `$2139/$213A`, `$213B`): port A reads at the current address in every clock. Thus the data is ready one clock after `rd`.
- **VRAM**: port A = 15-bit word address, two byte-write enables, 16-bit read. Port B = 15-bit address, 16-bit registered read. Two 8-bit arrays keep the names `vram_l` and `vram_h`.
- **CGRAM, OAM**: port A for the bus, port B for the renderer. One write port and one read port per array: the form that yosys maps to `DP16KD` (verify with `make synth`).
- **Timing outputs**: `hdot[8:0]`, `hclk[10:0]` (master clock in the line), `vcnt[8:0]`, `field`, `hblank`, `vblank`, `frame_start`, `dot_en`.
- **Latch input**: `hv_latch` from `$4201` bit 7 of the 5A22 (light gun pin) [C].
- **Pixel stream**: `pix_valid`, `pix_x[8:0]`, `pix_y[8:0]`, `pix_even[14:0]`, `pix_odd[14:0]`, `pix_hires`, `bright[3:0]`, `field`, `interlace`, `overscan`. In 256-wide modes, `pix_even = pix_odd`.
- **Debug sideband** (simulation only): `dbg_layer_main[2:0]`, `dbg_layer_sub[2:0]`, `dbg_math`. The reference model writes the same fields.

## 1.4 Important choices

| Choice | Alternatives | Recommendation |
|---|---|---|
| Render method | (a) exact copy of the VRAM fetch slots of the chip; (b) dot-sequential pipeline: tile fetch just before its pixels, registers read when used, sprites evaluated on the line before; (c) whole line rendered at once with registers latched at the line start | **(b)**. It keeps most mid-line effects and HDMA effects. (a) costs more and needs chip data we do not have. (c) breaks mid-line writes |
| BG fetch | 4 separate fetch units; one shared sequencer | **One sequencer** on VRAM port B. The original has the same bandwidth: 1 word per dot in modes 0-6 [C] |
| Master clock | (a) `clk_sys = 2 x master` from a PLL; (b) NCO enable `mce` at any `clk_sys` | **(b)**. `clk_sys` can follow Fmax. The jitter of 1 clock stays inside the FPGA |
| Video transport | (a) frame lock: HDMI timing follows the SNES frame, line buffer only; (b) frame buffer in SDRAM, standard 60.00 Hz | **(a)** first. It needs no SDRAM (F4) and has 1-2 lines of latency. Keep (b) as a fallback (question Q3) |
| HDMI mode | 640x480 (2x2 integer scale); 1280x720 (3x3) | **640x480**: 512x448 (478 with overscan) inside 640x480; 25 MHz pixel clock |
| Interlace on HDMI | bob (each field doubled, field 1 one HDMI line lower); weave (needs a frame buffer) | **Bob** |
| Reference | Python model in the repository; `bm` C emulator outside | **Both**. The Python model is mandatory. `bm` is a second opinion (Q5) |
| Verilog subset | keep the `vsim.py` subset; drop `vsim.py` for the PPU | **Keep the subset** for `rtl/files.f`. Write sign extension by hand. Multi-clock video goes to `rtl/board.f` |

### Frame lock (choice 1.4, row 4)

- NTSC: SNES line = 1364 master clocks = 63.51 us [C]. Half = 793.9 pixels at 25 MHz.
- Use `htotal = 794`, `vtotal = 524`. Then 794 x 524 / 25 MHz = 16.64 ms, 60.09 Hz. The SNES frame is 60.10 Hz [C].
- PAL: line 64.09 us [C]. Use `htotal = 801`, `vtotal = 624` (50.02 Hz). Active area stays 640x480.
- At each SNES `frame_start`, the video timing ends its vertical blank. The vertical total thus changes by at most 1 line.
- The ring of 8 lines absorbs the drift inside a frame. Monitor tolerance of these totals: to check on the owner's monitor.

## 1.5 SNES facts used [C] (check each one against documentation)

| Fact | Value [C] |
|---|---|
| Master clock | NTSC 21.477272 MHz, PAL 21.281370 MHz |
| Line | 1364 master clocks = 340 dots; dots 323 and 327 last 6 master clocks |
| Short line | NTSC, interlace off, field 1, line 240: 1360 master clocks |
| Long line | PAL, interlace on, field 1, line 311: 1368 master clocks, 341 dots |
| Lines per frame | NTSC 262 (interlace: 263 and 262); PAL 312 (interlace: 313 and 312) |
| Vertical blank | starts at line 225, or 240 with overscan (`$2133` bit 2) |
| Horizontal blank flag | set at dot 274, cleared at dot 1 |
| Field flag | changes in each frame, at line 0, dot 1 |
| NMI | at about dot 0.5 of the first line of the vertical blank |
| Visible pixels | 256 for each line, about dots 22-277; 512 in modes 5, 6, and pseudo-hires |
| VRAM fetch | 1 word for each dot in modes 0-6; Mode 7 reads 1 map byte (low chip) and 1 pixel byte (high chip) per dot |
| HDMA | init near line 0 start; transfer near master clock 1104 of each visible line |
| DRAM refresh | 40 master clocks near master clock 536 of each line (CPU stop; 5A22 work, F3) |
| VRAM write | ignored during active display without forced blank; the address increments |
| VRAM read prefetch | write of `$2116/$2117` loads the buffer; a read returns the buffer, then the increment reloads it |
| VMAIN remap | bits 2-3: 8-, 9-, or 10-bit rotations of the address |
| Scroll latches | `BGnHOFS = (d<<8) | (prev & ~7) | ((old>>8) & 7)`; `BGnVOFS = (d<<8) | prev`; Mode 7 registers use their own latch |
| CGRAM | `$2122` first write is latched, the second writes 15 bits; `$213B` reads low then high |
| OAM | low table written in pairs; high table (address >= 512) written per byte; `OAMADD` reloads at vblank start without forced blank; `$2103` bit 7 = priority rotation |
| Sprites | 128 entries; 32 in range for each line (`$213E` bit 6); 34 8x8 tiles (`$213E` bit 7); lower index wins over higher index, not the priority bits |
| Multiplier | `$2134-$2136` = M7A (16-bit signed) x last byte of M7B (8-bit signed); not valid while Mode 7 renders |
| Color math | half is not applied when the sub screen pixel is the fixed color; OBJ palettes 0-3 never take color math |
| Versions | `$213E` PPU1 version 1; `$213F` PPU2 version 2 or 3 |

Check of 2026-11-28 of the timing rows (master clock to vertical blank, and the three rows after it):

- Source A: <https://wiki.superfamicom.org/timing>. Source B: <https://snes.nesdev.org/wiki/Timing>.
- A and B agree on the clocks, the short line, the lines per frame, and the first blank line.
- Long dots: A gives two dots of 6 master clocks (323 and 327). B gives four dots of 5.
- Both give the same line length. The design follows A. The difference is inside the horizontal blank.
- Only B describes the long line.
- Only A gives the field flag, the horizontal blank flag, and the NMI position.
- The other rows of the table were not checked.

Check of 2026-11-28 for step P2:

- Sources: <https://snes.nesdev.org/wiki/PPU_registers>, <https://snes.nesdev.org/wiki/Palettes>,
  and <https://snes.nesdev.org/wiki/Timing>.
- Confirmed: forced blank, the backdrop word, the writes of `$2121` and `$2122`, and the visible lines.
- The visible part of a line runs from master clock 88 to 1112. These are the dots 22 to 277.
- The brightness has "linear steps" from none to full. No formula was found.
- A colour memory write in the active display goes to another address on the real chip.

Check of 2026-11-28 for step P3 (registers):

- Sources: <https://snes.nesdev.org/wiki/PPU_registers> (N), <https://wiki.superfamicom.org/registers> (W),
  <https://snes.nesdev.org/wiki/Open_bus>, and <https://problemkaputt.de/fullsnes.htm> (F).
- Horizontal scroll: N and W give two latches. F gives one latch. The design follows N and W.
  The row "Scroll latches" of the table above is the formula of F.
- Latch by `$2137`: N latches only when the latch flag is 0. The design latches at each read.
- `$4201` bit 7: W and F let it gate the latch. N does not name it. The design uses the gate.
- `$213B`: F and W advance the address after the high byte. The design does the same.
- Sprite memory address after `$3FF`: no source. The design goes back to 0.

Documents to read for these checks (read only, do not copy text): fullsnes by Martin Korth, anomie's register and timing documents, the SNESdev wiki. Their licenses: to check.

## 1.6 BRAM and fit

| Memory | Size | DP16KD | Note |
|---|---|---|---|
| VRAM | 64 KB | 32 | already in the 126 of today [V] |
| CGRAM | 512 B | 1 | main and sub look-ups share port B in time |
| OAM | 544 B | 1 | high table (32 B) in logic |
| OBJ line buffers | 2 x 256 x 10 bit | 1 | ping-pong in one 1024 x 18 block |
| Video line buffer | 8 x 512 x 16 bit | 4 | dual clock |
| **New in part 1** | | **7** [E] | |

| FPGA | Today [V] | With part 1 [E] | Note |
|---|---|---|---|
| 85F, 208 blocks | 128 | 133 (64%) | ARAM 32 (F6) brings it to 165 (79%) |

The target `make synth-ppu` synthesizes `ppu_top` alone. It prints its blocks, LUT, and multipliers. Thus each step has a measured PPU number, also before F4.

## 1.7 Steps

Each step closes with `make check` passing. Each step adds its mutants to the list `PPU_MUTANTS` in `sim/mutation_check.py`. `make ppu-mutation` runs them (iverilog). `make ppu-unit` is part of `make unit`. `make ppu` runs the scenes and is part of `make check`. Add each new PPU bench to `PPU_BENCHES`.

### P1. Timing generator (done)
- Result: `rtl/ppu/ppu_timing.v` and `rtl/ppu/ppu_top.v` replace the stub. `make ppu-unit` checks the timing.
- Mutants: 6 in `PPU_MUTANTS`. The plan asked for 4. The 2 others cover the long line and the horizontal blank.
- Later steps add the registers that read the counters (P3, P10) and the H/V IRQ (P11).

### P2. Pixel stream, backdrop, reference model, scene tools (done)
- Result: `ppu_cgram.v`, `ppu_math.v`, `tb/tb_ppu.v`, `sim/ppu_ref.py`, `sim/ppu_scenes.py`, `sim/ppu_cmp.py`, `sim/ppu_run.py`.
- Scenes: 5 in `tests/ppu/`. One loads the colour memory through the bus. Three have random writes.
- Mutants: 6 new ones. The plan asked for 3.
- One agent wrote the model first and then the Verilog. The plan asked for two agents.

### P3. Registers and memory ports (done)
- Result: `ppu_regs.v`, `ppu_vram.v`, `ppu_oam.v`, `tb/tb_ppu_regs.v`, `sim/ppu_regs_run.py`.
- `make ppu-unit` plays 30,000 random accesses: 0 differences. Mutants: 9 new ones.
- One agent wrote the model first and then the Verilog.
- Step P10 keeps: the effect of `$2133`, the input `hv_latch`, and the checks at random positions.

### P4. Modes 0 and 1, main and sub screens (done)
- Result: `ppu_bgfetch.v`, `ppu_bgpix.v`, `ppu_prio.v`, render port of the video memory, `sim/ppu_bgscenes.py`.
- 12 directed and 40 random scenes give equal dumps. Their CRC lists are in `tests/ppu/`.
- Mutants: 9 new ones. The mutant of the scroll latch is the one of step P3.
- The dump has one more field: the layer of the sub screen.
- The background registers change only outside dots 6 to 277 in the scenes (see step P16).
- One agent wrote the model first and then the Verilog.

### P5. Modes 2-6
- Content: 8 bpp, direct color (`$2130` bit 0), offset-per-tile in modes 2, 4, 6. Then hi-res modes 5 and 6 (even pixel sub, odd pixel main [C]).
- Done when: directed scenes `m2`-`m6` (OPT with column 0 rule [C], mode 4 single OPT, direct color) and 30 random scenes give equal 512-wide dumps.
- Mutants: OPT ignores the valid bits; direct color palette bits wrong; hi-res pixel order swapped.
- Depends on: P4. Risk: medium. Agent: standard, N=3.

### P6. Sprites
- Content: `$2101` sizes (8 combinations, two of them undocumented [C]), name base and gap. Then range and time evaluation, order rules, priority rotation, X wrap, line buffer, OBJ interlace, `$213E` bits 6-7.
- Files: `ppu_obj.v`, `ppu_objbuf.v`, model, `tests/ppu/obj_*`.
- Done when: directed scenes (33 sprites on a line show 32; 35 tiles show 34; rotation; partial sprite at X = -8; all sizes and flips) and 30 random scenes are equal. `$213E` read values are equal.
- Mutants: limit 33; tile limit 35; index order reversed; rotation ignored; vertical flip wrong on 16x32.
- Depends on: P4. Risk: high (evaluation order). Agent: expensive, N=4 (a wrong limit breaks many games).

### P7. Windows and color math
- Content: W1 and W2, inversion, OR/AND/XOR/XNOR, `$212E/$212F`, color window (clip, prevent), add, subtract, half, fixed color `$2132`, sub screen backdrop.
- Done when: directed scenes and 60 random scenes are equal, with `dbg_math` equal.
- Mutants: XNOR as XOR; half applied to the fixed color; no clamp; color math on OBJ palettes 0-3.
- Depends on: P4, P6. Risk: medium. Agent: standard, N=3.

### P8. Mosaic
- Content: `$2106` size and layer enables, vertical start at the register write line [C].
- Done when: directed scenes (size 1-16, write in the middle of the frame) are equal.
- Mutants: vertical counter not reset; mosaic on the sprites.
- Depends on: P4. Risk: low. Agent: standard, N=2.

### P9. Mode 7
- Content: matrix path, 13-bit scroll and centre with their sign and clip rules [C]. Then `$211A` repeat, transparent, or tile 0 fill, flips, EXTBG (BG2 with priority bit), multiplier `$2134-$2136`.
- Files: `ppu_m7.v`, model, `tests/ppu/m7_*`.
- Done when: 20 directed scenes (matrix changed at each line by timed writes) and 50 random matrices are equal. 1,000 random multiplier pairs read equal.
- Mutants: wrong sign extension of the scroll; screen-over fill ignored; horizontal flip ignored.
- Depends on: P4. Risk: high (bit exact arithmetic). Agent: expensive, N=4.

### P10. Interlace, overscan, pseudo-hires, counters
- Content: `$2133` bits 0-3 and 6, interlace in modes 5 and 6 [C], 239 lines. Then `$2137` latch, `$213C/$213D` two reads each, `$213F` field, latch flag, PAL bit; input `hv_latch`.
- Done when: scenes for each `$2133` bit are equal over 2 frames (both fields). `tb_ppu_regs` checks latched counters at 200 random (V, H) positions.
- Mutants: field not toggled; overscan ignored by the vblank; latch flag not cleared.
- Depends on: P5, P6. Risk: medium. Agent: standard, N=3.

### P11. 5A22 H/V IRQ and `$4212`
- Content: `s5a22_timer.v` with HTIME, VTIME, `$4200` bits 4-5, `$4211` (read clears), `$4212` bits 7, 6, and 0 (joypad busy as a stub). Connect `irq` of the core. Use the PPU timing outputs.
- Files: `rtl/s5a22_timer.v`, `rtl/s_cpu_5a22.v` (one instance, one wire), `tb/tb_snes_irq.v`, `tests/irq_program.asm`.
- Done when: the test program latches the counters in the IRQ handler. WRAM holds the expected (V, H) for V-only, H-only, and V+H modes. The trigger signal positions equal the model. Do not test the CPU entry time before F3.
- Mutants: H ignored when both bits are set; `$4211` not cleared by a read; hblank flag inverted.
- Depends on: P1, P10. Risk: medium. Agent: standard, N=3.

### P12. HDMA
- Content: `$420C`, `$43x7-$43xA`, direct and indirect modes, repeat bit, line counter, init at frame start, transfer in hblank, priority over general DMA [C], CPU halt.
- Files: `rtl/s5a22_hdma.v`, `rtl/s_cpu_5a22.v`, system scene test.
- Done when: a CPU program sets HDMA tables for BG1HOFS and COLDATA. The frame equals the model that replays the same writes (section 3.4). `$43xA` and `$43x8/9` values after the frame equal the model.
- Mutants: indirect address not incremented; repeat bit ignored; no init at frame start.
- Depends on: P4, P7, P11. Risk: high (timing). Agent: expensive, N=4.

### P13. Video path in simulation
- Content: `mclk_nco.v`, `vid_linebuf.v` (8 lines, Gray-code pointers), `vid_timing.v` (totals of section 1.4), `vid_scale.v` (2x2, centre, bob), frame lock.
- Files: `rtl/mclk_nco.v`, `rtl/video/*`, `rtl/board.f`, `tb/tb_video.v`.
- Done when: `tb_video` runs 6 frames with `clk_sys` 50 MHz, `clk_pix` 25 MHz, and the NCO. From frame 3, the delay from SNES `frame_start` to HDMI vsync stays within ±1 line. The captured 640x480 image equals the model image scaled 2x2 (`sim/ppu_cmp.py --scale 2`). The overflow and underflow flags stay 0.
- Mutants: pointer without synchronizer; field offset of bob inverted; NCO increment for PAL used in NTSC.
- Depends on: P2. Risk: medium. Agent: standard, N=3.

### P14. DVI output and board top
- Content: `tmds_enc.v` (8b/10b algorithm of the DVI 1.0 specification), `hdmi_phy_ecp5.v` (DDR outputs), board top with PLL. This step joins F1b.
- Files: `rtl/video/tmds_enc.v`, `rtl/board/hdmi_phy_ecp5.v`, `rtl/board/ulx3s_top.v`, `sim/tmds_ref.py`, `tb/tb_tmds.v`.
- Done when: 100,000 random symbols equal `sim/tmds_ref.py` (own code). The running disparity stays within ±8 [C]. yosys synthesizes the board top. nextpnr meets 125 MHz when F1b exists. The owner sees an image on a monitor.
- Mutants: no inversion of the 8-bit word; control tokens swapped.
- Depends on: P13, F1b, HANDOFF question 8. Risk: medium (board). Agent: standard, N=3.

### P15. System image test
- Content: `tests/ppu_demo.asm` loads VRAM, CGRAM, and OAM with DMA. It uses mode 1, sprites, windows, and HDMA. The test bench records all `$21xx` writes with (V, H).
- Done when: `make ppu-sys` gives a frame equal to the model fed with the recorded writes. All checks of `make test` still pass.
- Mutants: the existing PPU mutants, run once on this test.
- Depends on: P12. Risk: medium (`sim/asm.py` knows only a subset). Agent: standard, N=3.

### P16. Accuracy pass
- Content: mid-line register writes, CGRAM and OAM writes in active display, open bus of PPU1 and PPU2, mid-line brightness. Optional external test ROMs (section 3.5).
- Done when: each behaviour has a directed scene equal to the model. Each approximation is in `docs/ARCHITECTURE.md`, "Known limits".
- Depends on: P15, F4 and F7 for external ROMs. Risk: high. Agent: expensive, N=4.

---

# PART 2 - Enhanced PPU ("PPU+"), extended mode only

## 2.1 Rules

- PPU+ acts only with `$5F01 = 2` (signal `ext_enhanced`). In modes 0 and 1, the PPU+ registers do not answer the bus, and PPU+ sends no SDRAM request.
- With PPU+ synthesized, every part 1 scene gives the same CRCs in SNES mode. A mutant that removes the gate must fail a test.
- Resolution: SNES resolutions only (decision 6). The 3D layer is 256x224 (239 with overscan). B can add 512x224.
- Decision of the owner (Q1, 2026-11-28): the base 3D layer is 256x224. A later version can try 512x448.
- At 512x448 the SDRAM needs about 170-220 MB/s (estimate). The 3D layer then joins in the video output stage.
- Look: point sampling, toon ramps, and outlines give the "Wind Waker" sharpness (decision 7). Filtering is an option, not the default (Q7).
- Legacy DMA and the legacy PPU stay identical. The advanced DMA is a separate engine.

## 2.2 Architecture

```
 CPU (WDM, bus) --+--> ppup_regs ($5F40-$5F7F, ext mode) --> ppup_fifo (cmd FIFO, BRAM)
 adma (descr.) ---+                                                |
      |                                                            v
      |   ppup_vertex (A: screen space + viewport; B: 3x4 matrix, 1/w, N.L)
      |                                                            v
      |   ppup_setup (edges, gradients, bbox) --> ppup_bin --> SDRAM band lists (double)
      |                                                            v (per band, after END_FRAME)
      |   ppup_raster (edge walk, 1 px/clk A, 2 px/clk B; quad mode = blitter)
      |        v                      ^
      |   ppup_tex (cache) <----------+---- SDRAM textures
      |        v
      |   ppup_shade (Gouraud intensity, toon table, combiner B, fog B)
      |        v
      |   ppup_band (Z, color, object ID in BRAM) --> outline pass --> ppup_wb --> SDRAM framebuffer (2)
      v                                                                                 |
 mp_arb (SDRAM arbiter) <-- scan-out, CPU/ROM, adma, raster, tex, bins                  |
                                                                                        v
 ppup_scanout (line FIFO) --> 3D layer pixel --> ppu_prio / ppu_math (insert, gated) --> pixel stream
```

### Modules (files under `rtl/ppup/`)

| File | Function | LUT [E] |
|---|---|---|
| `ppup_regs.v`, `ppup_fifo.v` | registers, status, FIFO, fences | 0.5k |
| `mp_arb.v` (in `rtl/`) | SDRAM arbiter with deadlines | 1.0k |
| `adma.v` | advanced DMA, 2 instances | 3.0k |
| `ppup_scanout.v` + compositor changes | 3D layer from SDRAM | 1.0k |
| `ppup_vertex.v` | transform and light | 3.0k |
| `ppup_setup.v` | triangle setup, reciprocal of the area | 3.5k |
| `ppup_bin.v` | band lists | 0.8k |
| `ppup_raster.v` | edge walk, quads | 3.5k |
| `ppup_tex.v` | cache, 4 and 8 bpp, RGB555, bilinear, DXT1, perspective | 6.0k |
| `ppup_shade.v` | toon table, combiner, fog, alpha | 5.0k |
| `ppup_band.v`, `ppup_wb.v` | band buffers, clear, outline, write-back, bloom | 3.5k |
| OBJ doubling in `ppu_obj.v` | 256 entries, 64 per line, 68 tiles | 0.5k |
| **Total** | | **~31k** |

## 2.3 Clocking and memory interfaces

- PPU+ runs on `clk_sys` at full rate, not on `mce`. It meets the legacy PPU only at the scan-out line FIFO.
- The scan-out reads line N+1 of the front buffer during line N (512 bytes per 63.5 us, 8 MB/s [E]).
- The 3D frame rate is free (target 30 fps). The front and back buffers swap at a vblank after `END_FRAME`.
- Memory port `mp_*` (defined in F4): `req`, `we`, `addr[24:0]`, `len` (burst of 1-16 words), `wdata[15:0]`, `rdata[15:0]`, `ack`, `rvalid`. PPU+ uses only this port.
- Arbiter priority: 1 scan-out (deadline 1 line); 2 CPU and ROM; 3 advanced DMA; 4 bins and command fetch; 5 texture; 6 write-back.
- In SNES mode, only the CPU and ROM client is active. Its latency stays the same as without PPU+.

## 2.4 Important choices

| Choice | Alternatives | Recommendation |
|---|---|---|
| Z buffer | (a) full frame Z in SDRAM; (b) 32x32 tiles in BRAM with 2D bins; (c) full-width bands in BRAM with 1D bins | **(c)**. Random Z traffic on a 16-bit SDRAM (a) costs about 150-300 MB/s [E]. 1D bins are simple, and the write-back is one linear burst per line |
| Band height | 8 lines, 16 lines | **16 lines**, in two banks for 2 px/clk |
| Blitter | separate unit; quad mode of the rasterizer | **Quad mode** (HANDOFF section 5) |
| Command input | CPU writes to the FIFO port; descriptor lists in SDRAM through `adma` | **Both**. The CPU port is for small scenes and tests |
| Texture filter | point; bilinear | **Point** by default; bilinear is an option bit |
| Transparency of the 3D layer | colour key; 1 coverage bit per pixel (RGB555 + 1) | **Coverage bit** |

## 2.5 SDRAM bandwidth [E]

Scene: 25,000 triangles per frame, 30 fps, 256x224, overdraw 3.

| Consumer | MB/s [E] |
|---|---|
| Command lists (40 B per triangle) | 30 |
| Bin write and read (32 B per record, 1.2 bands per triangle) | 58 |
| Texture misses (double with bilinear) | 5 (10) |
| Write-back of the frame | 3.4 |
| Scan-out (60 Hz) | 6.9 |
| CPU and ROM in SNES mode (worst case) | 7 |
| CPU and WRAM in enhanced mode without cache | up to 50 |
| **Total** | **~110-160** |

- A 16-bit SDRAM gives 200 MB/s at 100 MHz and 332 MB/s at 166 MHz (peak). Real efficiency is about 60% [E].
- The design fits at 166 MHz. At 100 MHz it is tight. The chip part and its clock: to check (HANDOFF question 8).
- To save bandwidth, keep the triangle records at 24-32 bytes. Let small scenes use the CPU FIFO port.

## 2.6 Features

| Feature | Content |
|---|---|
| Pixel rate | 2 px/clk |
| Vertex | transform and light, perspective divide, N.L lighting |
| Texture | affine and perspective, point, bilinear option, 4/8 bpp paletted, RGB555, DXT1, second texture |
| Shading | Gouraud intensity, toon table, outline, 2-3 stage combiner, alpha, fog, bloom |
| Band | 256 x 16 (two banks) |
| Advanced DMA | 2 engines |
| 3D layer | 256x224, optional 512x224 |
| OBJ doubling | yes |

## 2.7 BRAM and multipliers [E]

| Memory | Blocks |
|---|---|
| Band Z and color (double) | 8 |
| Object ID band (outline) | 2 |
| Texture cache | 4 |
| Command FIFO | 2 |
| Scan-out line FIFO | 1 |
| Setup record buffer | 2 |
| 3D palette and toon tables | 1 |
| Second OAM (doubling) | 1 |
| Bloom line buffers | 2 |
| **Total** | **23** |

- All parts: 165 (part 1 and ARAM) + boot ROM 4 + scratchpad 16 + I-cache 4 + reverb 9 + PPU+ 23 = **221 of 208** [E]. This does not fit. Move the WRAM (64) to SDRAM, or drop the reverb buffer (owner, Q10).
- Multipliers: about 30 (T&L 6, perspective 4, bilinear 6, shading 6, setup 6). This is far below 156.

## 2.8 Steps

### X0. Formats and command set (design note)
- Content: fixed-point formats (vertex 12.4, Z 16 bit, texture coordinates, gradients), fill rule (top-left), command words, registers `$5F40-$5F7F`, framebuffer layout. The width and the height of the 3D layer are parameters.
- Files: `docs/design/ppup-formats.md`.
- Done when: the owner approves the note. Each later step cites its section.
- Depends on: nothing. Risk: medium. Agent: expensive, N=4 (a wrong format costs rework in all steps).

### X1. Memory port and arbiter
- Content: `mp_*` interface, `mp_arb.v`, `tb/sdram_model.v` (own code: latency, refresh, row misses).
- Done when: `tb_mp_arb` runs 1,000,000 random requests from 6 clients. No word is lost or duplicated. The scan-out never misses its deadline. The test prints the utilization.
- Mutants: scan-out at the lowest priority (deadline assert fails); burst length off by one.
- Depends on: F4 interface definition. Risk: medium. Agent: standard, N=3.

### X2. Registers and command FIFO
- Content: `ppup_regs.v`, `ppup_fifo.v`; `ext_regs.v` gives the range `$5F40-$5F7F` to PPU+ only in mode 2.
- Done when: in mode 0, writes to `$5F40-$5F7F` do not change the FIFO, and reads equal today's value. In mode 2, 4,096 random words leave the FIFO in order.
- Mutants: gate removed; FIFO full flag one entry late.
- Depends on: X0. Risk: low. Agent: standard, N=2.

### X3. Scan-out and compositor
- Content: `ppup_scanout.v`; insertion of the 3D layer in `ppu_prio.v` and `ppu_math.v`: priority slot, main and sub enables, color math enable, coverage bit.
- Done when: (a) all part 1 scenes give the same CRCs in mode 0 and in mode 2 with the layer off; (b) scenes `c3d_*` with a test-bench framebuffer equal `sim/ppup_ref.py`.
- Mutants: gate leak in mode 0; coverage bit inverted; priority slot off by one.
- Depends on: X1, X2, P7. Risk: high (it touches the legacy compositor). Agent: expensive, N=4.

### X4. Advanced DMA
- Content: `adma.v` with descriptors (source, destination, length, 2D stride, fill, next). Destinations: SDRAM, WRAM, VRAM port A, CGRAM, OAM, FIFO.
- Done when: 500 random descriptor chains give memories equal to the model. A CPU program runs at the same time, and all its checks pass.
- Mutants: stride ignored; chain end missed; VRAM write in active display accepted in mode 0.
- Depends on: X1. Risk: medium. Agent: standard, N=3.

### X5. Band buffer and blitter
- Content: `ppup_band.v`, `ppup_wb.v`, quad mode of `ppup_raster.v`: fill, textured axis-aligned quads, integer scale.
- Done when: 200 random quads give a framebuffer equal to the model. The test prints the clocks per frame.
- Mutants: band edge off by one; band not cleared.
- Depends on: X3. Risk: medium. Agent: standard, N=3.

### X6. Triangles, Z, bins
- Content: `ppup_setup.v`, `ppup_bin.v`, triangle mode of `ppup_raster.v`, Z test.
- Done when: 1,000 random triangles are equal to the model. A square cut into 512 triangles covers each pixel exactly once. A Z scene with crossing triangles is equal.
- Mutants: wrong fill rule (the coverage test finds it); `<=` instead of `<` in the Z test; triangle missing from the second band.
- Depends on: X5. Risk: high. Agent: expensive, N=4.

### X7. Texture unit
- Content: `ppup_tex.v`, cache, 4/8 bpp paletted and RGB555, wrap and clamp, affine.
- Done when: textured scenes are equal. The test prints the cache hit rate.
- Mutants: clamp as wrap; palette offset ignored.
- Depends on: X6. Risk: medium. Agent: standard, N=3.

### X8. Toon shading and outline
- Content: `ppup_shade.v` (intensity, toon table, multiply), outline pass on Z and object ID.
- Done when: scenes with 2-, 3-, and 4-step ramps and outlines are equal.
- Mutants: toon index rounding; outline threshold compare inverted.
- Depends on: X7. Risk: low. Agent: standard, N=3.

### X9. Vertex stage
- Content: `ppup_vertex.v`. Viewport and clip flags. 3x4 matrix in 16.16, reciprocal (table plus one Newton step), N.L.
- Done when: 10,000 random vertices are bit-exact against the model.
- Mutants: matrix row swapped; reciprocal without the Newton step.
- Depends on: X6. Risk: medium. Agent: expensive, N=4.

### X10. Doubled sprites (extended mode)
- Content: second OAM, 64 sprites and 68 tiles per line, only with mode 2 and an enable bit.
- Done when: extended scenes show 64 sprites on a line. In mode 0, a scene with 40 sprites on a line still shows 32, with `$213E` bit 6 set.
- Mutants: gate leak; limit stays 32 in mode 2.
- Depends on: P6, X2. Risk: high (legacy module). Agent: expensive, N=4.

### X11. Further features (one work order each)
- Content: 2 px/clk, perspective, bilinear, alpha, fog, combiner, bloom, DXT1, second texture.
- Done when: each feature has a model case, a scene, a mutant, and `make synth` passes.
- Depends on: X7-X9. Risk: medium. Agent: standard, N=3 each.

### X12. Performance test
- Content: generated scene with 25,000 triangles.
- Done when: the simulated render time is at most 1,666,666 clocks at 50 MHz (30 fps). SDRAM utilization is at most 70%. Sim time with iverilog may be long [E]; run it outside the CI.
- Depends on: X6-X9. Risk: medium. Agent: standard, N=2.

---

# 3. Verification strategy

## 3.1 Principles
- Use only own test data: generated patterns, random tiles, an own test font. Do not use game data.
- Write `sim/ppu_ref.py` and `sim/ppup_ref.py` from documentation, without looking at the Verilog. To solve a difference, find which side is wrong (the rule of `sim/cpu_ref.py`).
- Compare per pixel and exactly, with RGB555 before brightness, plus brightness and the debug layer fields.

## 3.2 Scene format and tools
```
# tests/ppu/<name>.scn  (written by sim/ppu_scenes.py, fixed seed)
region ntsc
load vram  tests/ppu/<name>.vram.hex      # back door, fast
load cgram tests/ppu/<name>.cgram.hex
load oam   tests/ppu/<name>.oam.hex
at 0 0     w 2105 09                       # at line 0, dot 0: bus write
at 100 280 w 210D 40                       # write in hblank of line 100
frames 2   compare 1                       # run 2 frames, compare frame 1
```
- `tb/tb_ppu.v` plays the scene into the bus port. It writes `build/ppu/<name>.out`: one line per screen line, 512 values `bbbbbgggggrrrrr:bright:main:sub`.
- `sim/ppu_ref.py` writes the same file. `sim/ppu_cmp.py` prints the first difference (x, y, layers) and writes PNG files of both images and of the difference. The owner can open the PNG files on any device.
- `tests/ppu/<name>.expect` holds one CRC32 per line. Regenerate it only from the model, and check the difference.
- One scene in each step loads the memories through the bus, not the back door.

## 3.3 Random scenes
`sim/ppu_scenes.py` and `sim/ppu_bgscenes.py` make constrained random scenes for each step: mode, map sizes, scroll, windows, math, sprites. Use a fixed seed in the CI and a free seed for local runs.
The background scenes are made at each run. Only their CRC lists are in the repository.

## 3.4 System tests by replay
The system test bench records each B-bus write (`$21xx`) with its (V, H) position. The model replays the record. Thus a frame made by the CPU, DMA, and HDMA is checked without a CPU model.

## 3.5 External references (all outside the repository)

| Reference | Use | Status |
|---|---|---|
| `bm` `ppu_equiv.c` (owner) | second model on the same scenes; needs an adapter for the scene format in `bm` | needs read and write access (HANDOFF question 5) |
| Own scene-player ROM in a public emulator | build a ROM from our scenes and compare screenshots | emulators (bsnes, ares, Mesen): their licenses and screenshot functions: to check. Do not copy their code |
| Public SNES test ROMs (for example the PPU tests of PeterLemon/SNES, undisbeliever test ROMs, the 240p test suite) | after F4 and F7 | existence, content, and licenses: to check. Keep them outside the repository, like the CPU vectors |
| Documents of section 1.5 | facts | licenses: to check |

## 3.6 Mutants and faults
- Each step lists its mutants. Add each one to `PPU_MUTANTS` in `sim/mutation_check.py`.
- Each mutant must fail at least one scene. Run `make ppu-mutation` in `make check`.
- Run the timing and video tests with three `mce` patterns: every clock, every second clock, and the NCO. A difference shows a dependency on `clk_sys`.

## 3.7 PPU+ checks
- `sim/ppup_ref.py` follows the formats of X0 bit by bit.
- SNES-mode equivalence: every part 1 scene runs in the PPU+ build. All CRCs must be equal.
- The `bm` V3D path is not bit-exact. Use it only for a visual comparison.

# 4. Resource summary [E]

| Part | LUT4 | DP16KD (new) | MULT18X18D |
|---|---|---|---|
| Part 1 PPU (`rtl/ppu/`) | 9-11k | 3 (VRAM 32 already counted) | 2-3 |
| 5A22 timers and HDMA | 1.1k | 0 | 0 |
| Video and DVI | 1.0k | 4 | 0 |
| PPU+ | 31k | 23 | ~27 |

Measure part 1 with `make synth-ppu` after each step. Quote each LUT count with the yosys version (`docs/VERIFICATION.md`, section 5).

# 5. Open questions for the owner

| # | Question | Alternative 1 | Alternative 2 | Recommendation |
|---|---|---|---|---|
| Q1 | 3D layer resolution (answered on 2026-11-28) | 256x224 (+512x224) | 320x240 | **Decided: 256x224** |
| Q2 | HDMI output mode | 640x480, 2x2 | 1280x720, 3x3 (742 Mbit/s per lane: to check on ECP5) | **640x480** |
| Q3 | Frame rate | frame lock at 60.09/50.02 Hz, no SDRAM | SDRAM frame buffer at 60.00/50.00 Hz, one repeated frame about every 10 s | **Frame lock**; fallback if the monitor refuses |
| Q4 | Accuracy target | dot-sequential (section 1.4) | exact fetch slots | **Dot-sequential** |
| Q5 | Second reference | `bm` `ppu_equiv.c` with a scene adapter | Python model only | **Both** (needs access to `bm`) |
| Q6 | External test ROMs and emulators | local use outside the repository after a license check | own scenes only | **Local use** |
| Q7 | Texture filter | point only | point default, bilinear as an option bit | **Option bit** |
| Q8 | Doubled sprites | double the legacy OBJ unit and add the blitter | blitter only | **Both** (OBJ doubling costs ~0.5k LUT [E]) |
| Q9 | Interlace on HDMI | bob | weave with a frame buffer | **Bob** |
| Q10 | BRAM (section 2.7) | WRAM in SDRAM | no reverb buffer | **WRAM in SDRAM** |

