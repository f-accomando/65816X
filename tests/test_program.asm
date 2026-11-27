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

; T5: moltiplicatore e divisore hardware del 5A22
        SEP #$20
        LDA #$07
        STA $4202
        LDA #$09
        STA $4203
        LDA $4216
        STA $7E0008         ; 3F
        LDA $4217
        STA $7E0009         ; 00
        LDA #$E8
        STA $4204
        LDA #$03
        STA $4205
        LDA #$07
        STA $4206           ; 1000 / 7
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
        LDA #$82
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

done:   BRA done

        .org $E800
sub:    REP #$30
        LDA #$BEEF
        RTS

        .org $8200
        .byte $11,$22,$33,$44

        .org $FFFC
        .word reset
