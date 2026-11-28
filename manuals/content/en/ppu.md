title: 65816X: the PPU manual
accent: PPU
lang: en
mark: 65816X PPU
kicker: Video manual
subtitle: The video part of 65816X: timing, memories, registers, and pictures.
footer: 65816X PPU manual

::: readme
**What this is.** The manual of the video part (PPU) of 65816X, an enhanced SNES written in Verilog.

**How to read it.** The column "Today" says what the design does now. "Works" means that tests in the simulator pass. "Stored" means that the register keeps its value and has no effect yet. Nothing was tried on a real board or compared with a real console.

**Sources.** The bit meanings come from public documentation, mainly the SNESdev wiki. The behaviour comes from the sources of this repository.
:::

# What works today

| Function | Today |
|---|---|
| Line and frame timing, NTSC and PAL | works |
| All registers `$2100-$213F`, with their latches | works |
| Video memory, colour memory, sprite memory | works |
| Counter latch, product `$2134-$2136` | works |
| Picture: backdrop colour, brightness, black screen | works |
| Backgrounds, modes 0 and 1 | works |
| Backgrounds, modes 2 to 6 | **[to be developed]** |
| Mode 7 picture | **[to be developed]** |
| Sprites | **[to be developed]** |
| Windows, colour math, mosaic | **[to be developed]** |
| High resolution, interlace, overscan picture | **[to be developed]** |
| Video output on a screen (HDMI) | **[to be developed]** |
| Enhanced 3D video (PPU+) | **[to be developed]** |

## Specifications

| Item | Value |
|---|---|
| Picture | 256 x 224 pixels; 239 lines with overscan |
| Colours | 256 colours from 32,768 (15 bits) |
| Video memory | 64 KB, as 32,768 words |
| Colour memory | 256 words of 15 bits |
| Sprite memory | 544 bytes: 512 and 32 |
| Sprites | 128; up to 32 in a line and 34 tiles in a line |
| Backgrounds | up to 4 layers |

# Timing

The video part counts master clocks with the enable `mce`. In the simulation, one FPGA clock is one master clock.

| Item | NTSC | PAL |
|---|---|---|
| Master clocks in a dot | 4; dots 323 and 327 take 6 | the same |
| Dots in a line | 340 | 340 |
| Master clocks in a line | 1364 | 1364 |
| Lines in a frame | 262 | 312 |
| Visible lines | 1 to 224 | 1 to 224 |
| Visible dots | 22 to 277 | 22 to 277 |
| Vertical blank | from line 225 | from line 225 |
| Horizontal blank | dot 274 to the end of dot 0 | the same |

- With interlace, the first field has one line more.
- NTSC without interlace: line 240 of the second field has 1360 master clocks.
- PAL with interlace: line 311 of the second field has 1368 master clocks and 341 dots.
- With overscan, the vertical blank starts at line 240.
- The system uses NTSC without interlace and without overscan today.

# Memories

The processor reaches the three memories only through registers.

| Memory | Write | Read | Address | Safe time to write |
|---|---|---|---|---|
| Video (VRAM) | `$2118-$2119` | `$2139-$213A` | `$2115-$2117` | blank period |
| Colour (CGRAM) | `$2122` | `$213B` | `$2121` | blank period, horizontal blank |
| Sprite (OAM) | `$2104` | `$2138` | `$2102-$2103` | blank period |

A blank period is the black screen (`$2100` bit 7) or the vertical blank. After reset the screen is black.

| Outside a blank period | The design | The real chip |
|---|---|---|
| Write to the video memory | lost; the address advances | the same |
| Read of the video memory | the buffer keeps its value | the value is not usable |
| Write to the sprite memory | lost; the address advances | goes to another address |
| Write to the colour memory | accepted | goes to another address |

## Colour memory

A colour has 15 bits: blue in bits 14-10, green in bits 9-5, red in bits 4-0. Write the low byte, then the high byte.

::: copy
        SEP #$20            ; 8-bit accumulator
        LDA #$00
        STA $2121           ; colour number 0
        LDA #$1F
        STA $2122           ; low byte
        LDA #$02
        STA $2122           ; high byte: colour $021F, orange
:::

Read a colour back in the same way. Bit 7 of the second byte is not part of the colour.

::: copy
        LDA #$00
        STA $2121           ; colour number 0
        LDA $213B
        STA $0010           ; low byte: $1F
        LDA $213B
        AND #$7F
        STA $0011           ; high byte: $02
:::

## Video memory

The address counts words. Write the two bytes of each word.

::: copy
        LDA #$80
        STA $2115           ; step 1 after the high byte
        LDA #$00
        STA $2116
        LDA #$10
        STA $2117           ; word address $1000
        LDA #$34
        STA $2118
        LDA #$12
        STA $2119           ; word $1234
        LDA #$78
        STA $2118
        LDA #$56
        STA $2119           ; word $5678
:::

A read gives the content of a buffer. After a new address, the first pair of reads and the second pair give the same word. Thus discard the first pair.

::: copy
        LDA #$00
        STA $2116
        LDA #$10
        STA $2117           ; address $1000 again
        LDA $2139
        LDA $213A           ; the first pair: discard it
        LDA $2139
        STA $0012           ; $34
        LDA $213A
        STA $0013           ; $12
        LDA $2139
        STA $0014           ; $78
        LDA $213A
        STA $0015           ; $56
:::

## Sprite memory

The first 512 bytes take one word at a time: the second byte stores both. The last 32 bytes take one byte at a time.

::: copy
        LDA #$00
        STA $2102
        STA $2103           ; sprite memory address 0
        LDA #$40
        STA $2104           ; X
        LDA #$50
        STA $2104           ; Y: the two bytes are stored now
        LDA #$02
        STA $2104           ; tile
        LDA #$30
        STA $2104           ; attributes: stored now
:::

::: copy
        LDA #$00
        STA $2102
        STA $2103
        LDA $2138
        STA $0016           ; $40
        LDA $2138
        STA $0017           ; $50
        LDA $2138
        STA $0018           ; $02
        LDA $2138
        STA $0019           ; $30
:::

# Registers

| Address | Name | Use | Today |
|---|---|---|---|
| `$2100` | INIDISP | screen and brightness | works |
| `$2101` | OBJSEL | sprite size and tiles | stored |
| `$2102-$2103` | OAMADD | sprite memory address | works |
| `$2104` | OAMDATA | sprite memory write | works |
| `$2105` | BGMODE | background mode | works: modes 0 and 1 |
| `$2106` | MOSAIC | mosaic | stored |
| `$2107-$210A` | BG1SC-BG4SC | background maps | works |
| `$210B-$210C` | BG12NBA, BG34NBA | background tiles | works |
| `$210D-$2114` | BGnHOFS, BGnVOFS | scroll | works |
| `$2115` | VMAIN | video memory step | works |
| `$2116-$2117` | VMADD | video memory address | works |
| `$2118-$2119` | VMDATA | video memory write | works |
| `$211A` | M7SEL | Mode 7 options | stored |
| `$211B-$2120` | M7A-M7D, M7X, M7Y | Mode 7 matrix and centre | stored; product works |
| `$2121` | CGADD | colour number | works |
| `$2122` | CGDATA | colour write | works |
| `$2123-$2125` | W12SEL, W34SEL, WOBJSEL | window selection | stored |
| `$2126-$2129` | WH0-WH3 | window edges | stored |
| `$212A-$212B` | WBGLOG, WOBJLOG | window logic | stored |
| `$212C-$212D` | TM, TS | main and sub screen | works; the sub screen colour is used from step P7 |
| `$212E-$212F` | TMW, TSW | window masks | stored |
| `$2130-$2132` | CGWSEL, CGADSUB, COLDATA | colour math | stored |
| `$2133` | SETINI | screen settings | stored |
| `$2134-$2136` | MPY | product | works |
| `$2137` | SLHV | latch the counters | works |
| `$2138` | OAMDATAREAD | sprite memory read | works |
| `$2139-$213A` | VMDATAREAD | video memory read | works |
| `$213B` | CGDATAREAD | colour read | works |
| `$213C-$213D` | OPHCT, OPVCT | dot and line counters | works |
| `$213E-$213F` | STAT77, STAT78 | status | works; no sprite flags yet |

"Two writes" means that the program writes the same address two times: first the low byte.

## Screen: $2100

| Bits | Meaning |
|---|---|
| 7 | 1: black screen, and the memories are free |
| 3-0 | brightness: 0 (dark) to 15 (full) |

::: copy
        LDA #$0F
        STA $2100           ; screen on, full brightness
:::

## Sprites: $2101-$2104

`$2101`:

| Bits | Meaning |
|---|---|
| 7-5 | size pair: 0 8x8 and 16x16; 1 8x8 and 32x32; 2 8x8 and 64x64; 3 16x16 and 32x32; 4 16x16 and 64x64; 5 32x32 and 64x64; 6 16x32 and 32x64; 7 16x32 and 32x32 (6 and 7 are not official) |
| 4-3 | place of the second tile block: (value + 1) x 4096 words after the first |
| 1-0 | first tile block: word address value x 8192 |

`$2102` and `$2103`:

| Bits | Meaning |
|---|---|
| `$2102` 7-0 | word address, low bits |
| `$2103` 0 | word address, bit 8: the 32-byte table |
| `$2103` 7 | 1: the sprite at the address gets the highest priority |

A write to one of the two registers loads the address again. The address also loads again at the start of the vertical blank, if the screen is not black.

## Background mode and mosaic: $2105-$2106

| Bits | Meaning |
|---|---|
| `$2105` 2-0 | mode 0 to 7 |
| `$2105` 3 | mode 1: layer 3 in front |
| `$2105` 7-4 | tile size of layers 4 to 1: 0 8x8, 1 16x16 |
| `$2106` 7-4 | mosaic block: value + 1 pixels |
| `$2106` 3-0 | mosaic on layers 4 to 1 |

| Mode | Bits per pixel of the layers | Scroll for each column |
|---|---|---|
| 0 | 2, 2, 2, 2 | no |
| 1 | 4, 4, 2 | no |
| 2 | 4, 4 | yes |
| 3 | 8, 4 | no |
| 4 | 8, 2 | yes |
| 5 | 4, 2; high resolution | no |
| 6 | 4; high resolution | yes |
| 7 | 8; one rotating layer | no |

## Background maps, tiles, and scroll: $2107-$2114

| Bits | Meaning |
|---|---|
| `$2107-$210A` 7-2 | map address: value x 1024 words |
| `$2107-$210A` 1 | 1: two maps, one below the other |
| `$2107-$210A` 0 | 1: two maps, side by side |
| `$210B` 3-0 and 7-4 | tile address of layers 1 and 2: value x 4096 words |
| `$210C` 3-0 and 7-4 | tile address of layers 3 and 4 |

| Address | Content (two writes) |
|---|---|
| `$210D`, `$210E` | horizontal and vertical scroll of layer 1, 10 bits; also the Mode 7 scroll, 13 bits |
| `$210F`, `$2110` | scroll of layer 2 |
| `$2111`, `$2112` | scroll of layer 3 |
| `$2113`, `$2114` | scroll of layer 4 |

The scroll registers share two latches. Write the two bytes of a register one after the other.

## Video memory: $2115-$2119

| Bits | Meaning |
|---|---|
| `$2115` 7 | 0: the address advances after `$2118` or `$2139`; 1: after `$2119` or `$213A` |
| `$2115` 3-2 | address remap: 0 none; 1, 2, 3 rotate the low 8, 9, or 10 bits left by 3 |
| `$2115` 1-0 | step: 0 1 word; 1 32 words; 2 and 3 128 words |
| `$2116-$2117` | word address; bit 15 has no effect; a write also loads the read buffer |
| `$2118-$2119` | low and high byte of the word |

The remap helps to write tiles of 2, 4, or 8 bits per pixel as pictures.

## Mode 7 and the product: $211A-$2120, $2134-$2136

| Bits | Meaning |
|---|---|
| `$211A` 7 | 1: do not repeat the map |
| `$211A` 6 | outside the map: 0 transparent, 1 tile 0 |
| `$211A` 1 and 0 | mirror up-down and left-right |
| `$211B-$211E` | matrix A, B, C, D: signed, 8 bits after the point; two writes |
| `$211F-$2120` | centre X and Y: signed 13 bits; two writes |

`$2134-$2136` give the signed 24-bit product of A (16 bits) and the last byte written to `$211C` (8 bits). A program can use it as a fast multiplier.

::: copy
        LDA #$23
        STA $211B           ; M7A, low byte
        LDA #$01
        STA $211B           ; M7A = $0123 (291)
        LDA #$FE
        STA $211C           ; M7B = -2
        LDA $2134
        STA $001A           ; $BA
        LDA $2135
        STA $001B           ; $FD
        LDA $2136
        STA $001C           ; $FF: the product is -582
:::

## Colours: $2121-$2122, $213B

| Address | Use |
|---|---|
| `$2121` | colour number; the next byte is the low one |
| `$2122` | write: two writes for each colour, then the number advances |
| `$213B` | read: two reads for each colour, then the number advances |

## Windows and screens: $2123-$212F

Each of `$2123-$2125` holds two groups of 4 bits. The low group serves layer 1, layer 3, or the sprites. The high group serves layer 2, layer 4, or the colour window.

| Bits | Meaning |
|---|---|
| group bit 0 | invert window 1 |
| group bit 1 | use window 1 |
| group bit 2 | invert window 2 |
| group bit 3 | use window 2 |
| `$2126`, `$2127` | left and right edge of window 1 |
| `$2128`, `$2129` | left and right edge of window 2 |
| `$212A` | logic of layers 1 to 4, 2 bits each: 0 OR, 1 AND, 2 XOR, 3 XNOR |
| `$212B` 1-0 and 3-2 | logic of the sprites and of the colour window |
| `$212C`, `$212D` 4-0 | layers on the main and the sub screen: bits 0-3 layers 1-4, bit 4 sprites |
| `$212E`, `$212F` 4-0 | layers that the windows cut, on the main and the sub screen |

## Colour math: $2130-$2132

| Bits | Meaning |
|---|---|
| `$2130` 7-6 | where the main screen turns black: 0 nowhere, 1 outside the colour window, 2 inside, 3 everywhere |
| `$2130` 5-4 | where the sub screen turns transparent for the math: the same codes |
| `$2130` 1 | what the math adds: 0 the fixed colour, 1 the sub screen |
| `$2130` 0 | direct colour for 8-bit layers |
| `$2131` 7 | 0 add, 1 subtract |
| `$2131` 6 | 1: halve the result |
| `$2131` 5-0 | math on: backdrop, sprites, layers 4 to 1 |
| `$2132` 7, 6, 5 | write blue, green, red of the fixed colour |
| `$2132` 4-0 | the value, 0 to 31 |

## Screen settings: $2133

| Bits | Meaning |
|---|---|
| 7 | external sync |
| 6 | second layer in Mode 7 |
| 3 | 512 pixels with two screens |
| 2 | 239 lines (overscan) |
| 1 | sprite interlace |
| 0 | screen interlace |

## Counters and status: $2137, $213C-$213F

A read of `$2137` stores the dot and the line. Read each counter two times: the low byte, then bit 8.

::: copy
        LDA $213F           ; the next read of a counter gives its low byte
        LDA $2137           ; latch the counters
        LDA $213C
        STA $001D           ; dot, low byte
        LDA $213C
        AND #$01
        STA $001E           ; dot, bit 8
        LDA $213D
        STA $001F           ; line, low byte
        LDA $213D
        AND #$01
        STA $0020           ; line, bit 8
:::

| Bits | Meaning |
|---|---|
| `$213E` 7 | more than 34 sprite tiles in a line (0 today) |
| `$213E` 6 | more than 32 sprites in a line (0 today) |
| `$213E` 5 | master or slave: 0 |
| `$213E` 3-0 | version of the first chip: 1 |
| `$213F` 7 | field |
| `$213F` 6 | the counters were latched; a read clears it |
| `$213F` 4 | 0 NTSC, 1 PAL |
| `$213F` 3-0 | version of the second chip: 3 |

Some bits that no register drives keep the last value that the chip put on the bus. A read of most write-only addresses returns 0 in this design.

# The picture

- The video part sends one pixel for each visible dot.
- A register write during a dot acts from the next dot. The background registers are read while the tiles are fetched: change them in the horizontal blank or the vertical blank.
- The pixel carries the colour and the brightness. The video output will scale the colour.
- The test pictures scale a colour by brightness / 15. No document gives the formula.

![The brightness from 0 to 15, from the top to the bottom. The black band is a black screen.](shots/65816x-backdrop.png)

![The backdrop changed through the colour registers, line by line.](shots/ppu-colours.png)

## Backgrounds

| Mode | Layers | Colours of a tile |
|---|---|---|
| 0 | 4 | 4 for each layer; layer n uses the colours from (n - 1) x 32 |
| 1 | 3 | 16 for layers 1 and 2; 4 for layer 3 |

A map word gives one tile:

| Bits | Meaning |
|---|---|
| 15 | mirror up-down |
| 14 | mirror left-right |
| 13 | priority: 1 in front |
| 12-10 | colour group (palette) |
| 9-0 | tile number |

- A map has 32 x 32 words. `$2107-$210A` select one, two, or four maps.
- A tile of 4 colours takes 8 words; a tile of 16 colours takes 16 words. Each word holds one row of two bit planes. The left pixel is bit 7.
- With a size of 16 x 16 (`$2105`), a tile uses the numbers n, n + 1, n + 16, and n + 17.
- Colour number 0 of a tile is transparent.
- Line 1 is the first line of the picture. It shows the map row 1 + vertical scroll.

| Place, front first | Mode 0 | Mode 1 |
|---|---|---|
| 1 | layers 1, 2 with priority | layers 1, 2 with priority |
| 2 | layers 1, 2 without | layers 1, 2 without |
| 3 | layers 3, 4 with priority | layer 3 with priority |
| 4 | layers 3, 4 without | layer 3 without |

In a place, the lower layer number is in front. In mode 1, bit 3 of `$2105` moves layer 3 with priority to the front.

## A first background

This code shows one tile: a white frame at the top left on a dark blue screen. Run the three boxes in their order.

::: copy
        SEP #$20
        ; screen off: the memories are free
        LDA #$80
        STA $2100
        ; mode 0; map of layer 1 at word 0, tiles at word $1000
        LDA #$00
        STA $2105
        STA $2107
        LDA #$01
        STA $210B
        ; scroll: horizontal 0, vertical -1 (line 1 shows row 0)
        LDA #$00
        STA $210D
        STA $210D
        LDA #$FF
        STA $210E
        LDA #$03
        STA $210E
        ; colour 0 (backdrop) dark blue, colour 1 white
        LDA #$00
        STA $2121
        STA $2122
        LDA #$30
        STA $2122
        LDA #$FF
        STA $2122
        LDA #$7F
        STA $2122
:::

::: copy
        ; tile 1: a square frame, 8 words at $1008
        LDA #$80
        STA $2115
        LDA #$08
        STA $2116
        LDA #$10
        STA $2117
        LDA #$FF
        STA $2118
        LDA #$00
        STA $2119
        LDA #$81
        STA $2118
        LDA #$00
        STA $2119
        LDA #$81
        STA $2118
        LDA #$00
        STA $2119
        LDA #$81
        STA $2118
        LDA #$00
        STA $2119
        LDA #$81
        STA $2118
        LDA #$00
        STA $2119
        LDA #$81
        STA $2118
        LDA #$00
        STA $2119
        LDA #$81
        STA $2118
        LDA #$00
        STA $2119
        LDA #$FF
        STA $2118
        LDA #$00
        STA $2119
:::

::: copy
        ; map entry at word 0: tile 1, colours 0 to 3
        STA $2116
        STA $2117
        LDA #$01
        STA $2118
        LDA #$00
        STA $2119
        ; show layer 1; screen on
        LDA #$01
        STA $212C
        LDA #$0F
        STA $2100
:::

![Mode 1: three layers.](shots/ppu-mode1.png)

![Mode 0: mirrored tiles and priorities.](shots/ppu-mirror.png)

# Sprites, other modes, and effects

All these parts are **[to be developed]**. Their registers already keep the values.

| Step | Content |
|---|---|
| P5 | background modes 2 to 6 |
| P6 | sprites |
| P7, P8 | windows, colour math, mosaic |
| P9 | Mode 7 |
| P10 to P12 | interlace, overscan, video interrupts, transfers in each line |
| P13, P14 | video output and HDMI |
| P15, P16 | full test and fine corrections |

# Enhanced video

The enhanced video acts only in extended mode. It is **[to be developed]** and a proposal.

| Item | Plan |
|---|---|
| 3D layer | 256 x 224; 512 x 224 or 512 x 448 may follow |
| Drawing | triangles with depth, 2 pixels for each clock |
| Geometry | transform and light in hardware |
| Textures | palette and 15 bits, perspective, filter, compressed |
| Look | toon colours, outlines, transparency, fog, glow |
| Copies | 2 fast copy engines |
| Sprites | twice the number |
| Target | about 25,000 triangles at 30 pictures each second (estimate) |

# Test the video part

| Command | What it checks |
|---|---|
| `make ppu` | 57 test pictures against a reference model; pictures in `build/ppu/` |
| `make ppu-unit` | the timing, and 30,000 random register accesses against the model |
| `make ppu-mutation` | that these tests find faults that a script puts into the design |
| `make synth-ppu` | the FPGA resources of the video part |

| Resource, video part alone | Measured on 2026-11-28 |
|---|---|
| Logic (equivalent LUT4), yosys 0.52 | 1,838 |
| Block RAM | 34 |
| Multipliers | 1 |

The video part with all original functions needs about 9,000 to 11,000 LUT4 (estimate).

# Differences from the real chip

- The counters latch at each read of `$2137`. One source latches only once until `$213F` is read.
- The sources differ about the long dots of a line. The design uses two dots of 6 master clocks.
- The horizontal scroll uses two latches. One source describes one latch.
- A change of `$2100` inside a line acts at the next dot. The real chip can lag or fade.
- The accesses outside a blank period are simpler: see the chapter "Memories".
- The tiles are fetched in another order than on the real chip. A change of a background register inside a line can act differently.
- No chip was measured, and no picture was compared with a console or an emulator.
