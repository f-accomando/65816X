# Roadmap

1. **Verifica con strumenti reali**: `make iverilog` (correggere eventuali differenze dal mini simulatore)
   e `make synth` (conteggio reale di LUT/BRAM e timing con nextpnr-ecp5).
2. **Core completo**: interrupt (NMI/IRQ/BRK/COP), direct page, stack-relative, indiretti, shift, BIT,
   MVN/MVP, modo decimale; confronto con suite di test indipendenti e con hardware di riferimento.
3. **Timing SNES**: cicli bus da 6/8/12 master clock, refresh, modo "timing accelerato controllato".
4. **Memoria reale**: controller SDRAM, caricamento ROM da SD, boot ROM da 4-8 KB sovrapposta ai
   vettori e disattivabile con una scrittura.
5. **PPU**: rendering dei modi 0-7, OAM, CGRAM, poi la pipeline PPU+ (rasterizer, Z per tile, toon).
6. **APU**: SPC700 e S-DSP, poi le 16 voci a 44,1 kHz.
7. **Uscita video**: HDMI su ULX3S (GPDI), 320x240 scalato.
8. **Estensioni**: DOT3, CROSS3, ROT, BLIT, FILL, registri R0-R7, DMA avanzato (memcpy, memset, stride, liste).
9. **Secondo core** (stile SA-1) con mailbox e semaforo; I-cache da 4 KB per core.
10. **Strumenti**: assembler esteso alle istruzioni enhanced; C tramite PVSnesLib o Calypsi
    per il codice compatibile (nessun compilatore C supporta ancora le estensioni).
