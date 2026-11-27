# Architettura

## Schema a blocchi

```
                 +-------------------------------+
                 |  s_cpu_5a22                   |
                 |  +-------------+  +---------+ |
                 |  | cpu65816x   |  | DMA 8ch | |   bus unico a 8 bit
                 |  +-------------+  +---------+ |   addr[23:0], rd, wr, wdata[7:0]
                 |  registri $42xx/$43xx, mul/div|--------+--------+--------+--------+
                 +-------------------------------+        |        |        |        |
                                                       cart_rom  wram   ppu_stub apu_stub ext_regs
```

Ogni periferica espone `hit` (l'indirizzo e' suo) e `rdata` (dato registrato). Il top registra
`hit` a ogni fronte e usa quei bit per selezionare il dato di lettura: il dato di una lettura
e' quindi disponibile il ciclo dopo l'indirizzo, come in una BRAM sincrona.

## Protocollo del bus

- Lettura: 2 cicli. Ciclo 0: `addr` e `rd` validi. Ciclo 1: `din` valido, il core lo cattura.
- Scrittura: 1 ciclo con `wr`, `addr` e `wdata` validi.
- Gli effetti collaterali di lettura (es. `$4210`, incremento VMADD) avvengono sul solo ciclo con `rd`.
- Il DMA toglie il bus alla CPU: la CPU viene fermata sul confine di istruzione (`halt`) e riprende a DMA concluso.

## Mappa di memoria (banchi `$00-$3F` e `$80-$BF`)

| Indirizzo | Contenuto |
|---|---|
| `$0000-$1FFF` | mirror dei primi 8 KB della WRAM |
| `$2100-$213F` | PPU (VRAM: `$2115-$2119`, `$2139-$213A`) |
| `$2140-$217F` | porte APU (mirror ogni 4 byte) |
| `$2180-$2183` | porta WRAM (dato e indirizzo a 17 bit con auto-incremento) |
| `$4200-$421F` | registri 5A22: NMITIMEN, mul/div, `$420B` MDMAEN, `$4210/$4212` stato |
| `$4300-$437F` | registri DMA per canale (`$43x0-$43x6`) |
| `$5F00-$5FFF` | **estensioni SNES+**: `$5F00` ID (`$58`), `$5F01` modo timing, `$5F02` velocita' |
| `$8000-$FFFF` | ROM LoROM |

Banchi `$7E-$7F`: WRAM completa. Banchi `$40-$7D` e `$C0-$FF`: ROM (solo `$8000-$FFFF`).

## Core 65816X: cosa e' implementato

Registri: A, X, Y, S, PC, PBR, DBR, flag N V M X I Z C ed E. Reset in modalita' emulazione,
lettura del vettore da `$00FFFC`. Larghezza A/X/Y governata dai flag M e X dopo `REP`/`SEP`.

| Gruppo | Opcode |
|---|---|
| Caricamento | `LDA` imm/abs/abs,X/long, `LDX`/`LDY` imm/abs, `STA` abs/abs,X/long, `STX`/`STY` abs |
| Aritmetica | `ADC` imm/abs, `SBC` imm, `CMP` imm/abs, `AND`/`ORA`/`EOR` imm, `INC A`, `DEC A`, `INX/DEX/INY/DEY` |
| Trasferimenti | `TAX TXA TAY TYA` |
| Flag e modo | `CLC SEC SEI CLI XCE REP SEP` |
| Salti | `BRA BNE BEQ BCC BCS BPL BMI`, `JMP abs`, `JML long`, `JSR abs`, `RTS` |
| Pila | `PHA PLA` |
| Altro | `NOP`; ogni opcode non elencato viene eseguito come NOP |

### Estensioni enhanced via `WDM #sub`

`WDM` e' riservata dal 65816 per usi futuri, quindi i giochi originali non la usano.
Le estensioni assumono A e X a 16 bit.

| Sub-opcode | Nome | Effetto |
|---|---|---|
| `$01` | MUL | `Y:A = A * X` (16x16 senza segno) |
| `$02` | DIV | `A = A / X`, `Y = A % X`; con `X=0`: `A=$FFFF`, `Y=A`, V=1 |
| `$03` | MAC | `ACC32 += A * X` |
| `$04` | MACRD | `A = ACC[15:0]`, `Y = ACC[31:16]` |
| `$05` | MACCLR | `ACC32 = 0` |

Previste e non ancora fatte: DOT3, CROSS3, ROT, BLIT, FILL, registri R0-R7 a 32 bit.

## Limiti noti

- Nessun interrupt (NMI, IRQ, BRK, COP), nessun modo decimale.
- Mancano molti modi di indirizzamento (direct page, stack-relative, indiretti) e istruzioni (shift, BIT, MVN/MVP, PHX/PLX...).
- Tempi non cycle-accurate: 2 cicli per lettura, nessuna emulazione dei cicli 6/8/12 del bus originale.
- Moltiplicazione e divisione del 5A22 sono istantanee; la WDM DIV usa un divisore combinatorio, da sostituire con uno sequenziale in sintesi.
- DMA: niente HDMA; il DMA fa 1 byte ogni 2 cicli.
- La lettura VRAM non modella il prefetch dell'originale.
- PPU e APU sono segnaposto.
