; Programma di collaudo per il sistema SNES+ (LoROM, banco 0)
        .org $8000
reset:  CLC
        XCE                 ; modalita' nativa
        REP #$30            ; A, X, Y a 16 bit

; T1: aritmetica a 16 bit
        LDA #$1234
        CLC
        ADC #$0001
        STA $7E0000         ; 35 12

; T2: 8 bit e propagazione del carry
        SEP #$20
        LDA #$FF
        CLC
        ADC #$01            ; A=00, C=1
        STA $7E0002         ; 00
        LDA #$00
        ADC #$00            ; A=01
        STA $7E0003         ; 01

; T3: ciclo con BNE all'indietro
        REP #$30
        LDY #$0005
        LDA #$0000
loop:   CLC
        ADC #$0003
        DEY
        BNE loop
        STA $7E0004         ; 0F 00

; T4: JSR / RTS (il byte alto di 'sub' e' $E8 = INX: se RTS tornasse un byte prima, X cambierebbe)
        REP #$30
        LDX #$0000
        JSR sub
        STA $7E0006         ; EF BE
        TXA
        STA $7E0026         ; 00 00

; T16: il moltiplicatore impiega 8 cicli: letto subito il prodotto e' ancora parziale
        SEP #$20
        LDA #$FF
        STA $4202
        LDA #$09
        STA $4203           ; 255 * 9 = $08F7
        LDA $4216           ; dopo 3 passi: 7 * 9 = $3F
        STA $7E0040         ; 3F
        NOP
        NOP
        LDA $4216
        STA $7E0041         ; F7
        LDA $4217
        STA $7E0042         ; 08

; T5: moltiplicatore e divisore hardware del 5A22 (si attendono i risultati)
        SEP #$20
        LDA #$07
        STA $4202
        LDA #$09
        STA $4203
        NOP
        NOP
        NOP
        LDA $4216
        STA $7E0008         ; 3F
        LDA $4217
        STA $7E0009         ; 00
        LDA #$E8
        STA $4204
        LDA #$03
        STA $4205
        LDA #$07
        STA $4206           ; 1000 / 7, 16 cicli
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        LDA $4214
        STA $7E0020         ; 8E (142)
        LDA $4216
        STA $7E0021         ; 06 (resto)

; T6: DMA ROM -> VRAM (modo 1: $2118/$2119)
        LDA #$80
        STA $2115
        LDA #$00
        STA $2116
        STA $2117
        LDA #$01
        STA $4300
        LDA #$18
        STA $4301
        LDA #$00
        STA $4302
        LDA #$E9
        STA $4303
        LDA #$00
        STA $4304
        LDA #$04
        STA $4305
        LDA #$00
        STA $4306
        LDA #$01
        STA $420B

; T7: rilettura VRAM
        LDA #$00
        STA $2116
        STA $2117
        LDA $2139
        STA $7E001A         ; 11
        LDA $213A
        STA $7E001B         ; 22
        LDA $2139
        STA $7E001C         ; 33
        LDA $213A
        STA $7E001D         ; 44

; T14: in modalita' SNES ($5F01 = 0) WDM non fa nulla
        REP #$30
        LDA #$1234
        LDX #$0010
        LDY #$5555
        WDM $01
        STA $7E0034         ; 34 12
        TYA
        STA $7E0036         ; 55 55

; T15: anche in modalita' accelerata ($5F01 = 1) WDM non fa nulla
        SEP #$20
        LDA #$01
        STA $5F01
        REP #$30
        LDA #$4321
        WDM $01
        STA $7E0038         ; 21 43

; modalita' estesa: $5F01 = 2
        SEP #$20
        LDA #$02
        STA $5F01
        LDA $5F01
        STA $7E003A         ; 02

; T8: estensioni enhanced WDM (MUL, DIV, MAC)
        REP #$30
        LDA #$1234
        LDX #$0010
        WDM $01             ; A=2340, Y=0001
        STA $7E000A         ; 40 23
        TYA
        STA $7E000C         ; 01 00
        LDA #$1000
        LDX #$0007
        WDM $02             ; A=0249, Y=0001
        STA $7E000E         ; 49 02
        TYA
        STA $7E0010         ; 01 00
        WDM $05
        LDA #$0100
        LDX #$0100
        WDM $03
        WDM $03
        WDM $04             ; A=0000, Y=0002
        STA $7E0012         ; 00 00
        TYA
        STA $7E0014         ; 02 00

; T17: WDM DIV per zero: A = $FFFF, Y = vecchio A
        REP #$30
        LDA #$1111
        LDX #$0000
        WDM $02
        STA $7E003C         ; FF FF
        TYA
        STA $7E003E         ; 11 11

; T9: registri enhanced, porte APU, pila
        SEP #$20
        LDA $5F00
        STA $7E0016         ; 58
        LDA $2140
        STA $7E0017         ; AA
        LDA $2141
        STA $7E0018         ; BB
        LDA #$CC
        STA $2140
        LDA $2140
        STA $7E0019         ; CC
        REP #$20
        LDA #$A55A
        PHA
        LDA #$0000
        PLA
        STA $7E001E         ; 5A A5

; T10: abs,X e mirror della WRAM
        REP #$30
        LDX #$0002
        LDA #$ABCD
        STA $0100,X
        LDA $0102
        STA $7E0022         ; CD AB

; T11: CMP e BEQ
        SEP #$20
        LDA #$05
        CMP #$05
        BEQ eqok
        LDA #$00
        BRA eqend
eqok:   LDA #$77
eqend:  STA $7E0024         ; 77

; T12: porta WRAM $2180-$2183 con auto-incremento
        SEP #$20
        LDA #$30
        STA $2181
        LDA #$00
        STA $2182
        STA $2183
        LDA #$AA
        STA $2180
        LDA #$BB
        STA $2180           ; WRAM[30]=AA, WRAM[31]=BB

; T13: lettura dalla porta WRAM $2180 con auto-incremento
        LDA #$30
        STA $2181           ; WMADD = $00030 ($2182 e $2183 sono gia' 0)
        LDA $2180           ; AA (WRAM[30]), WMADD -> $00031
        STA $7E0032
        LDA $2180           ; BB (WRAM[31])
        STA $7E0033

done:   BRA done

        .org $E800
sub:    REP #$30
        LDA #$BEEF
        RTS

        .org $E900          ; dati del DMA
        .byte $11,$22,$33,$44

        .org $FFFC
        .word reset
