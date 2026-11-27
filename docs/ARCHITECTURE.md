# Architecture

## Block diagram

```
                 +-------------------------------+
                 |  s_cpu_5a22                   |
                 |  +-------------+  +---------+ |
                 |  | cpu65816x   |  | DMA 8ch | |   one 8-bit bus
                 |  +-------------+  +---------+ |   addr[23:0], rd, wr, wdata[7:0]
                 |  regs $42xx/$43xx, mul/div    |--------+--------+--------+--------+
                 +-------------------------------+        |        |        |        |
                                                       cart_rom  wram   ppu_stub apu_stub ext_regs
```

Each peripheral has two outputs: `hit` (the address is its own) and `rdata` (registered data).
The top registers `hit` at each clock edge and uses these bits to select the read data.
Thus the data of a read is available in the cycle after the address, as in a synchronous BRAM.

## Bus protocol

- Read: 2 cycles. Cycle 0: `addr` and `rd` are valid. Cycle 1: `din` is valid, and the core captures it.
- Write: 1 cycle with valid `wr`, `addr`, and `wdata`.
- Read side effects (for example `$4210`, the VMADD increment) occur only in the cycle with `rd`.
- The DMA takes the bus from the CPU. The CPU stops at an instruction boundary (`halt`). It continues after the DMA.
- `rd` and `wr` last one cycle for each access.

## WRAM and BRAM

`wram.v` uses one address for reads and writes, with a registered read.
A read returns the data that was there before a write in the same cycle.
yosys maps this form to BRAM. Two reads from different addresses put the 128 KB into logic.
The reference model for `make unit` is `tb/wram_ref.v`.

## Memory map (banks `$00-$3F` and `$80-$BF`)

| Address | Content |
|---|---|
| `$0000-$1FFF` | mirror of the first 8 KB of the WRAM |
| `$2100-$213F` | PPU (VRAM: `$2115-$2119`, `$2139-$213A`) |
| `$2140-$217F` | APU ports (mirrored every 4 bytes) |
| `$2180-$2183` | WRAM port (data and 17-bit address with auto-increment) |
| `$4200-$421F` | 5A22 registers: NMITIMEN, mul/div, `$420B` MDMAEN, `$4210/$4212` status |
| `$4300-$437F` | DMA registers for each channel (`$43x0-$43x6`) |
| `$5F00-$5FFF` | **SNES+ extensions**: `$5F00` ID (`$58`), `$5F01` mode (0 SNES, 1 accelerated, 2 extended), `$5F02` speed |
| `$8000-$FFFF` | LoROM ROM |

Banks `$7E-$7F`: the full WRAM. Banks `$40-$7D` and `$C0-$FF`: ROM (only `$8000-$FFFF`).

## Core 65816X: what is implemented

Registers: A, X, Y, S, PC, PBR, DBR, flags N V M X I Z C and E. Reset enters emulation mode.
The core reads the reset vector from `$00FFFC`. The M and X flags set the width of A, X, and Y after `REP`/`SEP`.

| Group | Opcodes |
|---|---|
| Load and store | `LDA` imm/abs/abs,X/long, `LDX`/`LDY` imm/abs, `STA` abs/abs,X/long, `STX`/`STY` abs |
| Arithmetic | `ADC` imm/abs, `SBC` imm, `CMP` imm/abs, `AND`/`ORA`/`EOR` imm, `INC A`, `DEC A`, `INX/DEX/INY/DEY` |
| Transfers | `TAX TXA TAY TYA` |
| Flags and mode | `CLC SEC SEI CLI XCE REP SEP` |
| Jumps | `BRA BNE BEQ BCC BCS BPL BMI`, `JMP abs`, `JML long`, `JSR abs`, `RTS` |
| Stack | `PHA PLA` |
| Other | `NOP`; the core executes each opcode that is not in this table as NOP |

### Enhanced extensions through `WDM #sub`

The 65816 reserves `WDM` for future use, so original games do not use it.
The extensions run only in **extended mode** (`$5F01 = 2`, input `ext_en` of the core).
With `$5F01 = 0` (SNES, the value after reset) or `1` (accelerated), `WDM` only skips two bytes.
This is the behavior of the real chip. The extensions assume 16-bit A and X.

| Sub-opcode | Name | Effect |
|---|---|---|
| `$01` | MUL | `Y:A = A * X` (16x16 unsigned) |
| `$02` | DIV | `A = A / X`, `Y = A % X`; with `X=0`: `A=$FFFF`, `Y=A`, V=1 |
| `$03` | MAC | `ACC32 += A * X` |
| `$04` | MACRD | `A = ACC[15:0]`, `Y = ACC[31:16]` |
| `$05` | MACCLR | `ACC32 = 0` |

Planned and not yet done: DOT3, CROSS3, ROT, BLIT, FILL, 32-bit registers R0-R7.

## Known limits

- No interrupts (NMI, IRQ, BRK, COP) and no decimal mode.
- Many addressing modes are missing (direct page, stack-relative, indirect). Many instructions are missing (shift, BIT, MVN/MVP, PHX/PLX...).
- The timing is not cycle-accurate: 2 cycles for each read. The 6/8/12 cycles of the original bus are not emulated.
- The 5A22 multiplies and divides instantly. WDM DIV uses a combinational divider. Replace it with a sequential divider.
- DMA: no HDMA. The DMA moves 1 byte every 2 cycles.
- The VRAM read does not model the prefetch of the original.
- Here, a DMA from WRAM to `$2180` copies the data. On the real SNES it does not work (fix in phase F7).
- PPU and APU are placeholders.
