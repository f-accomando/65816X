# CPU extensions

The extensions are new operations behind `WDM #sub`. They run only in extended mode (`$5F01 = 2`).
In the other modes, `WDM` skips two bytes, as on the real chip.

This document has two parts: what exists (step C7a), and the proposals for the rest of C7. No
proposal of section 3 is approved.

## 1. What exists

`$5F03` gives the version of the extension set. `$02` means sub-opcodes `$01-$09`. It is read-only.

| Sub-opcode | Name | Effect | CPU cycles | Flags |
|---|---|---|---|---|
| `$01` | MUL | `Y:A = A * X`, unsigned | 2 | N, Z |
| `$02` | DIV | `A = A / X`, `Y` = remainder, unsigned | 11 | V = 1 if X = 0 |
| `$03` | MAC | `ACC32 += A * X`, unsigned | 2 | none |
| `$04` | MACRD | `Y:A = ACC32` | 2 | none |
| `$05` | MACCLR | `ACC32 = 0` | 2 | none |
| `$06` | MULS | `Y:A = A * X`, signed | 2 | N, Z |
| `$07` | DIVS | `A = A / X`, `Y` = remainder, signed | 11 | V = 1 if X = 0, or for -32768 / -1 |
| `$08` | MACS | `ACC32 += A * X`, signed product | 2 | none |
| `$09` | MACLD | `ACC32 = Y:A` | 2 | none |

Rules of the set:

- Operands are 16 bits. Use `REP #$30` first.
- A sub-opcode without an entry does nothing in 2 cycles.
- `DIVS` rounds toward 0. The remainder has the sign of the dividend.
- With X = 0, `DIV` and `DIVS` give `A = $FFFF`, `Y` = the dividend, and V = 1.
- `-32768 / -1` gives `A = $8000`, `Y = 0`, and V = 1.
- `ACC32` is 32 bits. It wraps around without a flag.
- An interrupt handler that uses `ACC32` saves it with `MACRD` and restores it with `MACLD`.

## 2. How it is built

| Part | Method |
|---|---|
| Multiplier | one unsigned 16 x 16 block (`MULT18X18D`). A negative operand subtracts the other one from the high half |
| Divider | restoring, 16 FPGA clocks, on magnitudes. `DIVS` changes the signs at the end |
| Check | `tb/tb_c816_ext.v`: 20,000 random and corner operations against the arithmetic of the simulator; system tests T18-T20 |

The correction of the high half adds two subtractors after the multiplier, in the same clock. The
maximum frequency is not measured.

## 3. Proposals for the rest (owner decisions)

| Item | Proposal | Reason | Cost (estimate) |
|---|---|---|---|
| Registers R0-R7, 32 bits | yes, as the next step. `WDM $20+n` writes `Rn` from `Y:A`; `WDM $28+n` reads it | one byte selects the operation and the register; SNES code does not change | 300-500 LUT, or 1 BRAM block |
| DOT3, CROSS3 | after R0-R7: signed 16-bit vectors in the registers, one shared multiplier, result in `ACC32` | no memory operand format to invent | 200-400 LUT, 0-2 multipliers |
| ROT | after the sine table decision | it needs sine and cosine | not estimated |
| SIN, COS | a table in the program, no hardware | block RAM is almost full | 0 |
| MUL32, DIV32, MOV32 | after R0-R7 | they need 32-bit operands | not estimated |
| FILL, BLIT | in the advanced DMA of the enhanced PPU, not in the CPU ([ppu-plan.md](ppu-plan.md), X4 and X5) | the CPU bus has 8 bits | in the PPU+ estimate |
| Prefetch, I-cache | after the real memory (F4) | the gain depends on the memory | 800 LUT, 3 BRAM blocks for 4 KB |
| 32-bit mode with a prefix | no, for now (HANDOFF, question 2) | new decode, new tests, no compiler; R0-R7 give 32-bit data without it | about 3,000 LUT |
| `ABORT` | no | no part of the system sends it | small |

### Questions

1. R0-R7 and DOT3: approve the encoding above?
2. 32-bit mode with a prefix: yes or no (HANDOFF, question 2)?
