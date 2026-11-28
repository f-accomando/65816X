# Architecture

## Block diagram

```
                 +-------------------------------+
                 |  s_cpu_5a22                   |
                 |  +-------------+  +---------+ |
                 |  | c816_core   |  | DMA 8ch | |   one 8-bit bus
                 |  +-------------+  +---------+ |   addr[23:0], rd, wr, wdata[7:0]
                 |  regs $42xx/$43xx, mul/div    |--------+--------+--------+--------+
                 +-------------------------------+        |        |        |        |
                                                       cart_rom  wram   ppu_top  apu_stub ext_regs
```

Each peripheral has two outputs: `hit` (the address is its own) and `rdata` (registered data).
The top registers `hit` at each clock edge and uses these bits to select the read data.
Thus the data of a read is available in the cycle after the address, as in a synchronous BRAM.

## Bus protocol

- One CPU cycle is 2 FPGA clocks. In phase 0, `addr` is valid and `rd` or `wr` pulses for one clock.
- Read: `din` is valid in phase 1, and the core captures it at the end of phase 1.
- Write: `wdata` is valid with `wr`. Phase 1 follows, without a strobe.
- Internal cycles drive `addr` without a strobe.
- Read side effects (for example `$4210`, the VMADD increment) occur only in the clock with `rd`.
- The DMA takes the bus from the CPU. The CPU stops at the next CPU cycle (`halt`), also inside
  an instruction. It continues after the DMA.
- `bus_wait` (tied to 0 today) can stretch phase 1.

## WRAM and BRAM

`wram.v` uses one address for reads and writes, with a registered read.
A read returns the data that was there before a write in the same cycle.
yosys maps this form to BRAM. Two reads from different addresses put the 128 KB into logic.
The reference model for `make unit` is `tb/wram_ref.v`.

## Memory map (banks `$00-$3F` and `$80-$BF`)

| Address | Content |
|---|---|
| `$0000-$1FFF` | mirror of the first 8 KB of the WRAM |
| `$2100-$213F` | PPU registers: writes `$2100-$2133`, reads `$2134-$213F` (see "PPU registers") |
| `$2140-$217F` | APU ports (mirrored every 4 bytes) |
| `$2180-$2183` | WRAM port (data and 17-bit address with auto-increment) |
| `$4200-$421F` | 5A22 registers: NMITIMEN, mul/div, `$420B` MDMAEN, `$4210/$4212` status |
| `$4300-$437F` | DMA registers for each channel (`$43x0-$43x6`) |
| `$5F00-$5FFF` | **SNES+ extensions**: `$5F00` ID (`$58`), `$5F01` mode (0 SNES, 1 accelerated, 2 extended), `$5F02` speed, `$5F03` version of the CPU extensions (`$02`) |
| `$8000-$FFFF` | LoROM ROM |

Banks `$7E-$7F`: the full WRAM. Banks `$40-$7D` and `$C0-$FF`: ROM (only `$8000-$FFFF`).

## Core 65816X: what is implemented

The core is `c816_core` in `rtl/cpu/`. It runs one step for each cycle of the real chip
(design: [design/cpu-core.md](design/cpu-core.md)).

Registers: A, X, Y, S, D, PC, PBR, DBR, flags N V M X D I Z C and E. Reset enters emulation mode.
The core reads the reset vector from `$00FFFC`. The M and X flags set the width of A, X, and Y after `REP`/`SEP`.
In emulation mode, the high byte of S stays at 01.

| Group | Opcodes |
|---|---|
| Load, store, arithmetic, logic | `LDA`, `STA` (no immediate), `ADC`, `SBC` (binary and decimal), `CMP`, `AND`, `ORA`, `EOR` with all addressing modes: immediate, absolute, absolute,X, absolute,Y, long, long,X, direct page, direct page,X, (dp), (dp,X), (dp),Y, [dp], [dp],Y, sr,S, (sr,S),Y |
| Index and zero | `LDX`, `LDY`, `STX`, `STY`, `STZ`, `CPX`, `CPY` |
| Read-modify-write | `ASL`, `LSR`, `ROL`, `ROR`, `INC`, `DEC` (accumulator and memory), `TSB`, `TRB`, `BIT` |
| Increment of index | `INX/DEX/INY/DEY` |
| Transfers | `TAX TXA TAY TYA TXY TYX TSX TXS TCS TSC TCD TDC XBA` |
| Flags and mode | `CLC SEC SEI CLI CLV CLD SED XCE REP SEP` |
| Jumps | `BRA BRL BNE BEQ BCC BCS BPL BMI BVC BVS`, `JMP`, `JML`, `JSR`, `JSL`, `RTS`, `RTL` |
| Stack | `PHA PLA PHX PLX PHY PLY PHP PLP PHB PLB PHK PHD PLD PEA PEI PER` |
| Block move | `MVN`, `MVP` |
| Interrupts | `BRK`, `COP`, `RTI`, `WAI`, `STP` |
| Other | `NOP`, `WDM` |

All 256 opcodes run, with the cycle counts of the real chip.

### Interrupts

- NMI is taken on its rising edge. IRQ is taken while it is 1 and the I flag is 0.
- The core takes a request at the end of an instruction. The next opcode fetch becomes the first of
  the 8 cycles of the interrupt (7 in emulation mode).
- The first instruction of a handler always runs. `CLI`, `SEI`, and `PLP` act one instruction later.
- `WAI` waits for a request. With I = 1, an IRQ ends the wait without an interrupt. `STP` waits for reset.
- In the system, the vertical blank gives the NMI when `$4200` bit 7 is 1. The IRQ input is not
  connected: the H and V timers do not exist.

### Enhanced extensions through `WDM #sub`

The 65816 reserves `WDM` for future use, so original games do not use it.
The extensions run only in **extended mode** (`$5F01 = 2`, input `ext_en` of the core) and in
**native mode** of the processor (`E = 0`). In emulation mode, `WDM` only skips two bytes.
With `$5F01 = 0` (SNES, the value after reset) or `1` (accelerated), `WDM` only skips two bytes.
This is the behavior of the real chip. The extensions assume 16-bit A and X.

| Sub-opcode | Name | Effect |
|---|---|---|
| `$01` | MUL | `Y:A = A * X` (16x16 unsigned) |
| `$02` | DIV | `A = A / X`, `Y = A % X`; with `X=0`: `A=$FFFF`, `Y=A`, V=1 |
| `$03` | MAC | `ACC32 += A * X` |
| `$04` | MACRD | `A = ACC[15:0]`, `Y = ACC[31:16]` |
| `$05` | MACCLR | `ACC32 = 0` |
| `$06` | MULS | `Y:A = A * X` (signed) |
| `$07` | DIVS | signed `A / X`, toward 0; `Y` = remainder; V=1 for `X=0` and for -32768 / -1 |
| `$08` | MACS | `ACC32 += A * X` (signed product) |
| `$09` | MACLD | `ACC32 = Y:A` |

`DIV` and `DIVS` take 11 CPU cycles, because a sequential divider gives one bit at each FPGA clock.
The other sub-opcodes take 2 cycles. The rules and the proposals for more operations are in
[design/cpu-extensions.md](design/cpu-extensions.md).

Planned and not yet done: DOT3, CROSS3, ROT, BLIT, FILL, 32-bit registers R0-R7.

## Multiply and divide of the 5A22

| Start | Operation | Time | Result |
|---|---|---|---|
| write `$4203` | `$4202` x `$4203`, 8 x 8 bits | 8 CPU cycles | product in `$4216-$4217` |
| write `$4206` | `$4204-$4205` / `$4206`, 16 / 8 bits | 16 CPU cycles | quotient in `$4214-$4215`, remainder in `$4216-$4217` |

The unit does one step at the end of each CPU cycle. A read that comes too soon gives the partial
value, as on the real chip. A division by 0 gives the quotient `$FFFF` and the dividend as remainder.

## Video timing

`rtl/ppu/ppu_timing.v` counts the master clocks of the video chips. The master clock is the enable
`mce`, not a clock net. The top ties `mce` to 1. Thus one FPGA clock is one master clock today.

| Item | Value |
|---|---|
| Dot | 4 master clocks; dots 323 and 327 take 6 |
| Line | 340 dots, 1364 master clocks |
| Short line | NTSC, no interlace, field 1, line 240: no long dot, 1360 master clocks |
| Long line | PAL, interlace, field 1, line 311: 341 dots, 1368 master clocks |
| Frame | 262 lines (NTSC) or 312 (PAL); with interlace, field 0 has one line more |
| Field | changes in each frame, after dot 0 of line 0 |
| Vertical blank | from line 225 (240 with overscan) to the end of the frame |
| Horizontal blank | from dot 274 to the end of dot 0 |

The system uses NTSC without interlace and without overscan. `$2133` is stored but does not act yet. The sources of the values are in [design/ppu-plan.md](design/ppu-plan.md), section 1.5.

## PPU registers

`rtl/ppu/ppu_regs.v` holds all registers of `$2100-$213F`. Most of them get their effect with the later
steps of [design/ppu-plan.md](design/ppu-plan.md). A blank period is the forced blank or the vertical blank.

| Registers | Behaviour |
|---|---|
| `$2102-$2104`, `$2138` | sprite memory: 10-bit byte address; the low table takes words, the high table bytes; reload from `$2102/$2103` at the start of the vertical blank without forced blank |
| `$210D-$2114` | scroll values, 10 bits, with two shared latches; `$210D/$210E` also load the Mode 7 scroll |
| `$211B-$2120` | Mode 7 values, two writes each, with their own latch |
| `$2115-$2119`, `$2139-$213A` | video memory: step 1, 32, or 128, three address remaps, prefetch of reads; outside a blank period a write is lost and the buffer keeps its value |
| `$2121-$2122`, `$213B` | colour memory: two bytes for each word, one flip-flop for writes and reads |
| `$2134-$2136` | signed product of M7A (16 bits) and the last byte of `$211C` |
| `$2137`, `$213C-$213D` | latch of the dot and line counters; two reads for each counter |
| `$213E-$213F` | versions 1 and 3, field, latch flag, region; `$213F` resets the counter flip-flops |

The PPU keeps two data latches of its open bus. A read of some write-only addresses returns one of
them. Bit 7 of `$4201` lets the counters latch. The system ties it to 1.

## Pixel path

The PPU draws only the backdrop today: word 0 of the colour memory.

- `ppu_cgram.v` holds 256 colours of 15 bits. `$2121` sets the address. `$2122` takes the low byte,
  then the high byte. Then the address advances. Bit 15 is not stored.
- `ppu_math.v` gives one pixel for each visible dot: lines 1-224 (239 with overscan), dots 22-277.
- `$2100` bit 7 makes the picture black (forced blank). Bits 3-0 give the brightness.
- A register write during a dot acts from the next dot.
- The pixel stream carries the colour before the brightness, and the brightness. The video output
  will scale the colour.
- `sim/ppu_cmp.py` scales a colour by N / 15 for the pictures. No document gives the formula.

## Known limits

- No `ABORT`. No IRQ from the system: the H and V timers of the 5A22 do not exist.
- Interrupt sampling and the wake up of `WAI` can differ from the real chip by a cycle.
- The cycle counts match the real chip for all opcodes. The 6/8/12 master clocks of the original bus are not emulated.
- The reset sequence (7 cycles) follows the data sheet and was not compared with a chip.
- The multiplier and the divider of the 5A22 stop while the DMA holds the CPU. Their partial
  values were not compared with the real chip.
- DMA: no HDMA. The DMA moves 1 byte every 2 cycles.
- Here, a DMA from WRAM to `$2180` copies the data. On the real SNES it does not work (fix in phase F7).
- The PPU draws only the backdrop colour: no background layers and no sprites. The APU is a
  placeholder.
- A colour memory write is accepted at any time. The real chip writes to another address in the
  active display.
- A sprite memory write in the active display is lost. The real chip writes to another address.
- A read of `$2137` and of most write-only addresses returns 0. The real chip returns the open bus
  of the processor.
- `$213E` gives 0 for the range and time flags until the sprites exist.
- On the real chip, a change of `$2100` inside a line can lag or fade. The design does not do that.
- The NMI comes at the start of dot 0 of the first line of the vertical blank. One source puts it
  half a dot later.
- The two sources differ about the long dots of a line (section 1.5 of the PPU plan). No chip was
  measured.
- No chip was compared for the field value after reset.
- No chip was compared for a change of overscan or interlace inside a frame.
- With `mce` tied to 1, the CPU does about 3 times more cycles in a frame than the original (estimate).
