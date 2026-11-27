# Varianti, budget e colli di bottiglia

Tutte le cifre sono **stime** (±30%), non risultati di sintesi. Vanno sostituite con i numeri
di `make synth` appena possibile.

## Risorse del target

| FPGA | LUT | BRAM | Moltiplicatori |
|---|---|---|---|
| ECP5 LFE5U-45F | ~44k | ~243 KB (108 blocchi da 2,25 KB) | 72 |
| ECP5 LFE5U-85F | ~84k | ~468 KB (208 blocchi) | 156 |

## Variante A (ECP5-45F)

- 1 core 65816X, prefetch a 3 stadi, scratchpad da 16 KB.
- Unita MUL, DIV, MAC; 1 motore DMA avanzato; 3 bus.
- PPU+ a 1 px/clk con Gouraud/affine e tabella toon.
- Audio: DSP originale (8 voci, 32 kHz).
- Stima: ~37k LUT (84%), BRAM ~78%.

## Variante B (ECP5-85F)

- 2 core 65816X (stile SA-1), scratchpad da 16 KB per core, 4 bus separati
  (istruzioni, dati, DMA, periferiche).
- MUL, DIV, MAC, T&L, DOT3, CROSS3, ROT; 2 motori DMA avanzati.
- PPU+ a 2 px/clk: bilinear, prospettiva, alpha, nebbia, tabella toon, combiner a 2-3 stadi,
  bloom, decoder DXT1; Z-buffer per tile in BRAM; 320x240 a 30 fps.
- Audio: 16 voci a 44,1 kHz con riverbero, piu' il DSP originale a 32 kHz.
- Senza SuperFX/DSP-1/Cx4 (caricabili come bitstream alternativo), senza FPU e RISC-V.
- Stima: ~73k LUT (87%), BRAM ~88%.

## Colli di bottiglia

| Collo | Soluzione | Resta |
|---|---|---|
| Cicli morti e clock a 3,58 MHz | prefetch, meno cicli morti, clock 50-80 MHz | i giochi sensibili ai tempi restano in modalita' SNES |
| Bus a 8 bit condiviso | 4 bus separati | la SDRAM e' comunque condivisa |
| Banda SDRAM (~330 MB/s) | Z e colore per tile in BRAM, DXT1, 320x240 | scene con molte texture |
| MUL/DIV in software | unita parallele, T&L | - |
| Animazione, IA, collisioni | secondo core come worker, DOT3/CROSS3 | limite reale: ~20-30k triangoli per frame |
| DMA che blocca la CPU | bus DMA dedicato, liste di comandi | contesa sulla SDRAM |
| BRAM quasi piena | scratchpad al posto delle cache | nessun margine per L1/L2 |

## FPU e cache (opzionali)

- **FPU single-precision**: ~3-5k LUT e 2-4 moltiplicatori. Serve solo per scrivere in C con float
  (richiede RISC-V o istruzioni WDM float). Il fixed-point 16.16 con MAC basta per il 3D previsto.
- **Cache L1** (4 KB per core): ~0,8k LUT (istruzioni) / ~1,3k (dati) e ~3 blocchi BRAM ciascuna.
  **L2 da 64 KB**: ~32 blocchi, non ci sta in B.
- Scelta consigliata: solo I-cache da 4 KB per core (sola lettura, nessun problema di coerenza),
  disattivata in modalita' SNES. Aree non cacheable: `$2100-$21FF`, `$4000-$43FF`, WRAM condivisa.

## Look "cel-shaded"

Per un'estetica tipo Wind Waker non serve emulare la GameCube: servono tabella toon (~1k LUT),
combiner a 2-3 stadi (~2-4k), seconda texture (~2k), bloom (~1-2k) e DXT1 (~1k), circa +5-10k LUT.
Il collo e' la CPU, non il rasterizer.
