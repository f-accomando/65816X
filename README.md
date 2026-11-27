# 65816X

Punto di partenza in Verilog per una **SNES avanzata su FPGA** (target: Lattice ECP5, scheda ULX3S):
un 65816 migliorato e compatibile con le ROM SNES, con DMA/moltiplicatore come il Ricoh 5A22,
estensioni "enhanced" opzionali e una PPU che in futuro ospitera' una pipeline 3D.

Il progetto parte dalla **struttura a piu' chip della SNES originale** (non la versione 1-chip):
5A22, PPU, APU, WRAM e cartuccia sono moduli separati collegati da un unico bus a 8 bit.

## Stato

Scheletro funzionante, verificato in simulazione con un mini simulatore Python (vedi sotto).
**Non e' ancora** stato eseguito con iverilog/verilator ne' sintetizzato con yosys: nell'ambiente
in cui e' stato scritto non erano disponibili. Primo passo consigliato: `make iverilog` e `make synth`.

| Modulo | File | Stato |
|---|---|---|
| Core 65816X | `rtl/cpu65816x.v` | sottoinsieme di opcode, niente interrupt, tempi non cycle-accurate |
| Ricoh 5A22 | `rtl/s_cpu_5a22.v` | registri `$42xx`, mul/div, DMA generale (8 canali, modi 0-7), niente HDMA |
| PPU1/PPU2 | `rtl/ppu_stub.v` | timing video e VRAM, nessun rendering |
| SPC700 + DSP | `rtl/apu_stub.v` | 4 porte `$2140-$2143` con eco e firma `$AA/$BB` |
| WRAM | `rtl/wram.v` | 128 KB, mirror, porta `$2180-$2183` |
| Cartuccia | `rtl/cart_rom.v` | LoROM 64 KB (segnaposto della SDRAM) |
| Estensioni | `rtl/ext_regs.v` | registri enhanced in `$5F00-$5FFF` |
| Top | `rtl/snes_plus_top.v` | collega tutto e fa il mux di lettura |

## Uso rapido

```
make test        # assembla tests/test_program.asm ed esegue 45 controlli (solo Python 3)
make mutation    # introduce 7 guasti nell'RTL e verifica che il collaudo li scopra
make iverilog    # stesso programma con Icarus Verilog (se installato)
make synth       # sintesi ECP5 con yosys (se installato): conteggio reale di LUT e BRAM
```

## Documentazione

- [HANDOFF.md](HANDOFF.md): per chi riprende il lavoro: decisioni dell'utente, proposte e loro esito, idee non ancora nel codice, domande aperte, prossimi passi.
- [docs/ARCHITETTURA.md](docs/ARCHITETTURA.md): bus, mappa di memoria, opcode supportati, estensioni WDM, limiti.
- [docs/VARIANTI.md](docs/VARIANTI.md): varianti A (ECP5-45F) e B (ECP5-85F), budget LUT/BRAM, colli di bottiglia, FPU e cache.
- [docs/ROADMAP.md](docs/ROADMAP.md): prossimi passi in ordine.

## Strumenti inclusi

- `sim/asm.py`: assembler per il sottoinsieme supportato (`python3 sim/asm.py in.asm rom.hex`).
- `sim/vsim.py`: mini simulatore per un sottoinsieme sincrono di Verilog, a un solo clock.
  Serve come test di regressione senza dipendenze; non sostituisce iverilog o verilator.

Le cifre di LUT e BRAM nei documenti sono stime (±30%), non risultati di sintesi.
Nessuna licenza e' stata scelta: va aggiunta dal proprietario del repository.
