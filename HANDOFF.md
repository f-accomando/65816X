# HANDOFF - 65816X (SNES+ su FPGA)

Documento per passare il lavoro a un'altra sessione di Claude Code. Raccoglie le decisioni
dell'utente, le proposte dell'utente e quelle di Claude (con l'esito di ognuna), le idee
discusse ma non ancora nel codice, i dubbi aperti e i prossimi passi.

Data: 2026-11-27. Repository: `f-accomando/65816X`. Branch di lavoro: `feat/snes-plus-skeleton` (PR #1).

> Tutte le cifre di LUT, BRAM, MHz e fps in questo file sono **stime** (±30%), salvo dove e'
> scritto "misurato". Nessuna e' un risultato di sintesi.

## 1. Come lavorare con questo utente

- Scrive in **italiano**: rispondere e documentare in italiano.
- Usa Claude da **iPhone, senza tastiera fisica**: preferisce file scaricabili e verifica con test,
  **niente demo live o interattive** (canvas, giochi con tastiera).
- Vuole risposte brevi e dirette, con le cifre dichiarate come stime quando lo sono.
- Dire apertamente cosa NON e' stato verificato. Non presentare stime come misure.

## 2. Stato del codice

Scheletro Verilog costruito sulla **struttura a piu' chip della SNES originale** (non la 1-chip):

| Modulo | File | Stato |
|---|---|---|
| Core 65816X | `rtl/cpu65816x.v` | sottoinsieme di opcode, niente interrupt, tempi non cycle-accurate |
| Ricoh 5A22 | `rtl/s_cpu_5a22.v` | registri `$42xx`, mul/div istantanei, DMA generale 8 canali (modi 0-7), niente HDMA |
| PPU1/PPU2 | `rtl/ppu_stub.v` | solo timing e VRAM (`$2115-$2119`, `$2139-$213A`) |
| SPC700 + DSP | `rtl/apu_stub.v` | 4 porte con eco, firma `$AA/$BB` |
| WRAM | `rtl/wram.v` | 128 KB, mirror, porta `$2180-$2183` |
| Cartuccia | `rtl/cart_rom.v` | LoROM 64 KB (segnaposto della SDRAM) |
| Estensioni | `rtl/ext_regs.v` | `$5F00` ID (`$58`), `$5F01` modo timing, `$5F02` velocita' |
| Top | `rtl/snes_plus_top.v` | collega tutto |

Verifica fatta: `make test` (45 controlli) e `make mutation` (7 guasti su 7 rilevati), con il
mini simulatore Python `sim/vsim.py`. **Mai eseguito con iverilog, verilator, yosys o nextpnr**
(non c'erano nell'ambiente di sviluppo). `tb/tb_snes_plus.v` e' scritto ma non eseguito.

### Trabocchetti del codice attuale

- Lettura sul bus = 2 cicli (`ph` 0 invia l'indirizzo, `ph` 1 cattura); scrittura = 1 ciclo. Gli effetti
  collaterali di lettura avvengono solo sul ciclo con `rd`.
- Il DMA ferma la CPU solo sul confine di istruzione (`halt` agisce in `ST_FETCH` con `ph=0`).
- Opcode sconosciuti = NOP silenzioso: nasconde i bug, da sostituire con un segnale di errore in simulazione.
- `WDM DIV` usa `/` e `%` combinatori: in sintesi sono grossi e lenti, da rifare sequenziali.
- Le estensioni WDM assumono A e X a 16 bit.
- `sim/vsim.py` supporta solo un sottoinsieme di Verilog (un clock, niente parametri di istanza,
  generate, function): se l'RTL cresce oltre, usare iverilog/verilator.
- La lettura VRAM non modella il prefetch dell'originale (semplificazione dichiarata).

## 3. Decisioni prese dall'utente (da non rimettere in discussione senza chiedere)

1. **Target**: FPGA ECP5 su ULX3S, due varianti: A (45F, ~44k LUT) e B (85F, ~84k LUT).
2. **Compatibilita'** con ROM e cartucce SNES; le estensioni sono opzionali ("opzione C": compatibile ed estensibile). Senza "nuove tecnologie".
3. **Partire dalla struttura SNES originale a piu' chip**, non dalla versione 1-chip.
4. **Programmabile sulla macchina**: tastiera, assembly e C.
5. **Audio della B: 16 voci a 44,1 kHz** (aveva proposto 24 voci come la PS1, poi ha scelto 16).
6. **Risoluzione**: niente 480/720; resta a risoluzioni da SNES (era interessato a risoluzione e sprite raddoppiati mantenendo l'architettura).
7. **Look**: nitidezza "alla Wind Waker" (poligoni e texture nette, senza la sfocatura dell'N64) senza emulare la GameCube.

## 4. Proposte dell'utente (dalle sue chat con ChatGPT) e esito

Fonte: due chat condivise di ChatGPT. Del primo link e' stata letta solo la lista delle domande; di entrambe
sono state incollate solo le prime risposte (sezione CPU). Il resto delle risposte non e' disponibile.

| Idea | Esito | Perche' |
|---|---|---|
| Due modalita': SNES ed Enhanced | **Adottata** | stessa ISA, nessuna perdita di compatibilita' |
| "Timing accelerato controllato" (veloce ma rispetta le finestre di PPU/periferiche) | **Adottata** | diventa il modo intermedio: SNES / accelerato / enhanced (`$5F01`) |
| Estensioni via `WDM`: MUL32, DIV32, MAC, MOV32, FILL, BLIT, SIN/COS, ROT, DOT3, CROSS3 | **Parziale** | in RTL ci sono MUL, DIV, MAC, MACRD, MACCLR; il resto va fatto |
| Registri R0-R7 a 32 bit e ACC32, invisibili in modalita' legacy | Da fare | non toccano il codice SNES |
| ALU interna a 32 bit | **Da decidere** | proposta di Claude: modalita' estesa a 32 bit con prefisso (il W65C832 non fu mai prodotto) |
| Pipeline in-order a 3-5 stadi | Modificata: prefetch a 3 stadi | un 65816 con bus a byte guadagna poco da 5 stadi |
| Branch prediction | Rimandata | pipeline corta, poco guadagno |
| Cache L1 4-8 KB (I e D) + L2 32-128 KB | **Modificata**: scratchpad 16 KB per core + I-cache 4 KB per core opzionale; L2 no | BRAM gia' all'88-94%, e la coerenza con I/O e DMA e' il punto delicato |
| Bus separati: istruzioni, dati, DMA, periferiche | **Adottata** in B (3 bus in A) | il DMA non blocca il fetch |
| DMA a 8-16 canali, burst, liste di comandi, priorita' | Modificata: 8 canali legacy + motori avanzati (1 in A, 2 in B) | il DMA legacy deve restare identico |
| Bus interno 64 bit | **Scartata** | la SDRAM della ULX3S e' a 16 bit |
| 8 registri vettoriali da 128 bit | **Scartata** | troppi LUT per un 65816 |
| Clock 50-100 MHz | Ridotta a 50-80 MHz | realismo su ECP5 |
| Unita' parallele MUL/DIV/MAC/DSP, operazioni atomiche, bit manipulation | MUL/DIV/MAC adottate; il resto non valutato | |
| Sviluppo a fasi: core, 65816X, strato 5A22, sistema enhanced | **Adottata** | e' la roadmap |
| SID "enhanced" a 8 canali / 44,1 kHz su FPGA | Superata dalla scelta a 16 voci | un SID analogico fedele non si riproduce su FPGA; vedi sez. 7 |
| Schermi OLED della Switch per progetti propri | **Senza risposta** | domanda finita nel testo incollato, mai affrontata |

## 5. Proposta di Claude

### Varianti (dettaglio in `docs/VARIANTI.md`)

| | A (ECP5-45F) | B (ECP5-85F) |
|---|---|---|
| Core | 1 core 65816X | 2 core 65816X (stile SA-1) |
| Bus | 3 | 4 separati |
| Calcolo | MUL, DIV, MAC | MUL, DIV, MAC, T&L, DOT3, CROSS3, ROT |
| DMA | 1 motore avanzato | 2 motori avanzati |
| PPU+ | 1 px/clk, toon | 2 px/clk, bilinear, prospettiva, alpha, nebbia, toon, combiner 2-3 stadi, bloom, DXT1 |
| Audio | DSP originale 8 voci 32 kHz | 16 voci 44,1 kHz con riverbero + DSP originale 32 kHz |
| Stima | ~37k LUT (84%), BRAM ~78% | ~73k LUT (87%), BRAM ~88% |

La B esclude SuperFX/DSP-1/Cx4 (caricabili come bitstream alternativo), FPU e RISC-V: non ci stanno.

### Pipeline PPU+ (da implementare)

Command FIFO -> Vertex (MAC) -> Triangle setup -> Rasterizer (1 px/clk in A, 2 px/clk in B) ->
Texture + Z (Z per tile in BRAM) -> Shading -> Framebuffer (SDRAM, doppio buffer) -> Compositor con i layer legacy.
Il blitter e' il rasterizer su un quad (cosi' si raddoppiano gli sprite). Risoluzione 3D prevista: 320x240 a 30 fps,
circa 20-30k triangoli per frame. Look cel-shaded: tabella toon (~1k LUT), combiner 2-3 stadi (~2-4k), seconda texture
(~2k), bloom (~1-2k), DXT1 (~1k): in totale +5-10k LUT. Il limite reale e' la CPU (animazione, IA, collisioni), non il rasterizer.

### Altre scelte di Claude

- **Modi di timing**: SNES (identico all'originale), accelerato, enhanced (`$5F01`).
- **Estensione a 32 bit** con prefisso (opzionale, ~+3k LUT, da decidere).
- **FPU single-precision**: ~3-5k LUT, utile solo con RISC-V o istruzioni WDM float; il fixed-point 16.16 con MAC basta per il 3D previsto.
- **Cache**: solo I-cache da 4 KB per core, in sola lettura; aree non cacheable `$2100-$21FF`, `$4000-$43FF`, WRAM condivisa; disattivata in modalita' SNES.
- **Audio**: 16 voci con riverbero ~5k LUT; serve un oscillatore da 22,5792 MHz oppure un ricampionatore (~0,5k LUT); il DSP originale resta a 32 kHz con convertitore di frequenza.
- **Boot e OS**: boot ROM da 4-8 KB nella BRAM, sovrapposta ai vettori e disattivata con una scrittura a un registro (da assegnare in `$5F00-$5FFF`); OS da SD o flash caricato in RAM (monitor, editor, assembler on-device, BASIC), ~8-16 KB.
- **Cluster quad-core** (discusso, non nelle varianti): core 0 + 3 worker, 16 KB di BRAM locale ciascuno, DMA per core, mailbox/semafori/IRQ, stessa mappa con ID del core, in modalita' compatibile attivo solo il core 0.
- **Alternativa con chip reali**: WDC W65C816S (~14 MHz), MCU Cortex-M33/M7 al posto di FPU + RISC-V (~66k LUT totali + ~1k LUT di bridge), PPU/APU originali recuperate, CPLD di colla, o cartuccia "enhancer" tipo FXPak.

### Elenco migliorie da fare, in ordine

1. Verifica con strumenti reali: `make iverilog`, `make synth` (LUT/BRAM/Fmax reali), CI su GitHub che esegue `make test`.
2. Divisore sequenziale al posto del `/` combinatorio (piccolo e certo).
3. Interrupt (NMI, IRQ, BRK, COP): quasi tutti i giochi girano agganciati all'NMI; il flag e' gia' nei registri ma il core non lo vede.
4. Set di opcode completo e verifica con vettori di test per istruzione (suite pubbliche per il 65816, se disponibili) e con il riferimento descritto in sez. 8.
5. Prefetch e clock unico con enable per i cicli da 6/8/12 master clock.
6. Memoria reale: controller SDRAM, ROM da SD, boot ROM sovrapposta.
7. Vedere qualcosa a schermo: HDMI e rendering dei modi 0-7, poi PPU+.
8. APU: almeno un finto handshake di avvio (l'eco attuale probabilmente blocca i giochi), poi SPC700 e S-DSP.
9. HDMA e DMA a cicli corretti.
10. Estensioni enhanced (DOT3, CROSS3, ROT, R0-R7, DMA avanzato), poi secondo core e I-cache.

## 6. Dove le proposte divergono (da chiudere con l'utente)

| Tema | ChatGPT | Claude |
|---|---|---|
| Cache | L1 + L2 | scratchpad + I-cache, niente L2 |
| Bus interno | 32/64 bit | 8 bit (come l'originale); SDRAM a 16 bit |
| Pipeline | 5 stadi, branch prediction | prefetch a 3 stadi, senza predizione |
| DMA | 8-16 canali | 8 canali legacy + motori avanzati |
| Clock | 50-100 MHz | 50-80 MHz |
| Registri | R0-R7 + 8 vettoriali 128 bit | R0-R7 + ACC32, niente vettoriali |

## 7. Idee discusse ma non nel codice

- **C64 + SNES**: programmabilita' e BASIC, tastiera e audio SID del C64, mantenendo i giochi SNES. Spunti (da
  verificare sulla piedinatura ufficiale): sul connettore cartuccia pin 31 SOUND-L e pin 62 SOUND-R entrano nel mixer
  della console; pin 1 MCK a 21,47727 MHz diviso 21 e' ~1,0227 MHz, il clock del C64 NTSC; pin 18 /IRQ. Sostituti SID:
  SIDKick pico, ARMSID, FPGASID, USBSID-Pico. Un SID fedele all'analogico non si ottiene su FPGA (il filtro e' un modello
  a due integratori, e la variazione analogica del 6581 limita la fedelta'): su cartuccia, chip reale.
- **Parita' con altre console** (stime di Claude): PS1 60-90k LUT (esistono core su Cyclone V da 110k LE), N64 90-150k+
  (serve FPGA piu' grande e veloce, problemi di banda/tempi RDRAM), GameCube 250-500k+ (non esiste un core FPGA).
  Fuori portata per l'ECP5-85F; al massimo una PS1 molto stretta.
- **Strumenti**: assembler ca65 o WLA-DX, Wiz; C con PVSnesLib (816-tcc) o Calypsi (`--target=SNES`). **cc65 non
  supporta il 65816 come compilatore C.** Nessun compilatore conosce le estensioni WDM: per C esteso servirebbe un
  backend nuovo, oppure un core RISC-V. Il BASIC Microsoft 6502 e' stato rilasciato con licenza MIT (da verificare).

## 8. Emulatore nel progetto `f-accomando/bm`

Il repo `bm` (console bare-metal per Pi Zero W e RGB30, giochi Lua) ha gia' una macchina SNES in C e assembly ARM
(`core/src/bm/snes_*.c`, `snes_cpu_arm.S`, `snes_ppu_arm.S`, `api_snes.c`; SA-1, Super FX e DSP-1 compresi; cartuccia
utente `bm/snes`). Dai suoi report su Pi Zero W (Super Mario World, misurato): frame ~14,5 ms su 16,6, di cui CPU ~2,2-2,5,
audio ~2,3, PPU ~9, disegno ~0,9; a 60 fps e' gia' al limite.

Valutazione di Claude su un "modo enhanced" nell'emulatore (stime sui numeri sopra):

| Parte enhanced | Sul Pi Zero W |
|---|---|
| Estensioni WDM (MUL, DIV, MAC, DOT3, CROSS3) | si', sono operazioni native ARM |
| DMA avanzato | si' |
| PPU+ 3D toon (20-30k triangoli) | si', sul motore V3D (misurati 49.956 triangoli a 13,7 ms) |
| Audio 16 voci 44,1 kHz | stretto (~4-5 ms): ok a 30 fps |
| 1 core fino a ~10 MHz equivalenti | si' (l'SA-1 a 10,74 MHz e' gia' emulato) |
| 2 core a 50-80 MHz | no sul Pi Zero W (~8-12 MHz equivalenti con la meta' del frame); RGB30 non misurato |

Principi: il gioco enhanced deve spostare il calcolo nelle estensioni native; velocita' emulata scalabile come fa `adapt`;
3D a 30 fps; PPU+ sul V3D. L'emulatore e' anche un **riferimento per l'RTL**: i suoi test `tests/snes/cpu_golden.c`
(`make test-snes-cpu`) e `ppu_equiv.c` si possono usare per confrontare registri e memorie con il Verilog su programmi casuali.
Per modificare `bm` serve l'accesso in scrittura a quel repository (a questa sessione era in sola lettura); i test golden
del modo SNES non vanno toccati.

## 9. Domande aperte per l'utente

1. Quale variante implementare per prima, A o B?
2. Modalita' a 32 bit con prefisso: si' o no?
3. FPU e RISC-V, MCU Cortex, o niente dei tre?
4. Licenza del repository (non scelta).
5. Vuole il "modo enhanced" nell'emulatore di `bm` e darne l'accesso?
6. La domanda sugli schermi OLED della Switch va ripresa?

## 10. Prossimo passo suggerito

Iniziare da 1 e 2 della lista in sez. 5 (strumenti reali, CI, divisore sequenziale), poi interrupt e opcode completi.
Criterio per ogni passo: `make test` e `make mutation` restano verdi, ogni nuova funzione ha un controllo nel test e
almeno un guasto in `sim/mutation_check.py`, e i documenti in `docs/` sono aggiornati.
