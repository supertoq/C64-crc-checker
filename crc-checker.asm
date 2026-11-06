; =====================================================================
;  CRC-CHECKER - Pruefsummen-Rechner fuer den Commodore 64
;  Version 1.0
;
;  Berechnet fuer eine Datei:
;    - CRC-32 (identisch zu crc32/ZIP/7-Zip auf dem PC)
;    - 16-Bit-Summe aller Bytes
;    - Dateigroesse in Bytes
;
;  Die Datei wird mit dem Dateibrowser gewaehlt (filebrowser.asm):
;    - Diskettenlaufwerke 8-11 (auch SD2IEC, JiffyDOS usw.)
;    - U: USB-Sticks und SD-Karten von Ultimate-Geraeten
;      (1541 Ultimate-II/II+, Ultimate 64, C64 Ultimate) ueber das
;      Ultimate Command Interface (UCI). Im Ultimate-Menue muss
;      "Command Interface" eingeschaltet sein.
;
;  Assemblieren:  64tass -C crc-checker.asm -o crc-checker.prg
;                 (filebrowser.asm und fb_uci.asm im selben Ordner)
;  Starten:       LOAD"CRC-CHECKER",8  dann RUN
;
;  Bedienung:
;    F3 / RETURN  Dateibrowser: Laufwerk, Ordner, Datei waehlen;
;                 RETURN auf einer Datei berechnet die Pruefsumme.
;                 Getippte Namen mit * und ? sind erlaubt, im
;                 Ergebnis steht der vollstaendige Name.
;    F5           Vergleichswert (erwartete CRC-32) eingeben,
;                 leere Eingabe loescht ihn. Das Ergebnis zeigt dann
;                 MATCH (gruen) oder MISMATCH (rot).
;    F7           Programm beenden
;    RUN/STOP     bricht das Lesen ab
;
;  Bildschirm:
;    Zeile 0       Titel (mit Farbverlauf)
;    Zeilen 1-11   Ergebnis im Rahmen: Laufwerk, Ordner, Datei, Groesse,
;                  Summe, CRC-32 in grossen Ziffern, Vergleichswert.
;                  Waehrend des Lesens: Fortschrittsbalken.
;    Zeilen 12-20  Verlauf der letzten 7 Pruefungen (neueste oben)
;    Zeile 23/24   Status- und Infozeile
; =====================================================================
        .cpu "6502"
        .enc "ascii"            ; Zeichen als ASCII, auch mit 64tass -a
        .cdef $00, $ff, $00

; ---------------- Farben (Optionen) ----------------
;  0 schwarz   1 weiss     2 rot        3 tuerkis
;  4 violett   5 gruen     6 blau       7 gelb
;  8 orange    9 braun    10 hellrot   11 dunkelgrau
; 12 grau     13 hellgruen 14 hellblau  15 hellgrau
COL_BORDER  = 0         ; Rahmen
COL_SCREEN  = 0         ; Hintergrund (Fenster)
COL_TEXT    = 7         ; Schrift (Statuszeile)
COL_TITLE   = 7         ; Titelzeile (ohne Farbverlauf)
COL_BOX     = 14        ; Rahmen um das Ergebnis, Trennlinie im Verlauf
COL_LABEL   = 3         ; Bezeichnungen (Drive, File, Size ...)
COL_VALUE   = 1         ; Werte
COL_CRC     = 7         ; grosse CRC-Ziffern ohne Vergleichswert
COL_MATCH   = 13        ; Vergleich stimmt
COL_BAD     = 10        ; Vergleich stimmt nicht, Fehler
COL_BAR     = 13        ; Fortschrittsbalken
COL_BAREMPTY = 11       ; Fortschrittsbalken, noch offen
COL_HIST    = 15        ; Verlauf
COL_HISTNEW = 14        ; neuester Eintrag im Verlauf (invers)
COL_HINT    = 12        ; Hinweise, Infozeile
COL_BROWSER = 0         ; Rahmen im Dateibrowser
COL_FOLDER  = 14        ; Laufwerke und Ordner im Dateibrowser
COL_POINTER = 15        ; Zeiger > im Dateibrowser

; ---------------- weitere Optionen ----------------
RESTORECOL  = 1         ; 1 = beim Beenden alte Farben wiederherstellen
TITLE_ANIM  = 1         ; 1 = Farbverlauf in der Titelzeile
TITLE_SPEED = 3         ; Farbverlauf: Schritt alle n/60 Sekunden
SOUND       = 1         ; 1 = Ton nach dem Lesen (hell: ok, tief: Fehler)
BORDERFLASH = 1         ; 1 = Rahmen flackert beim Lesen
; Farben des Verlaufs in der Titelzeile (32 Werte, laufen nach links)
TITLECOLS .macro
        .byte 6,6,14,14,3,3,1,1,3,3,14,14,6,6,4,4
        .byte 10,10,7,7,1,1,7,7,10,10,4,4,6,6,6,6
        .endm

; ---------------- Werte fuer den Dateibrowser ----------------
SCREEN  = $0400
TEXTCOL = COL_TEXT
BORDCOL = COL_BORDER
DIRCOL  = COL_BROWSER
FOLDCOL = COL_FOLDER
PTRCOL  = COL_POINTER
BSHOWX  = 1             ; alle Dateien zeigen (auch .d64, .prg usw.)

; ---------------- Speicher ----------------
TAB0    = $c000         ; CRC-Tabelle, 4 Seiten (Byte 0..3)
TAB1    = $c100
TAB2    = $c200
TAB3    = $c300
HIST    = $c400         ; Verlauf: HMAX Eintraege zu 32 Bytes
HMAX    = 7
BORDER  = $d020
BGCOL   = $d021
TXTCOL  = $0286         ; Schriftfarbe des KERNAL
JIFFY   = $a2           ; Uhr, zaehlt 60-mal pro Sekunde
SID     = $d400
cc      = $22           ; Zeiger in den Farbspeicher (2 Bytes)

; Bildschirmzeilen
R_BOX   = 1             ; Rahmen oben
R_DRV   = 2
R_DIR   = 3
R_FILE  = 4
R_SEP   = 5
R_SIZE  = 6
R_BIG   = 7             ; 3 Zeilen grosse Ziffern / Fortschritt
R_EXP   = 10
R_BOXE  = 11            ; Rahmen unten
R_HHEAD = 12            ; Verlauf: Kopf
R_HLINE = 13
R_HIST  = 14            ; Verlauf: erste Zeile
R_HINT  = 22
R_INFO  = 24
VCOL    = 10            ; Spalte der Werte im Rahmen

; Bildschirmcodes fuer Rahmen und Balken
SC_H    = $40           ; waagrecht
SC_V    = $5d           ; senkrecht
SC_TL   = $70
SC_TR   = $6e
SC_BL   = $6d
SC_BR   = $7d
SC_LT   = $6b           ; |- links
SC_RT   = $73           ; -| rechts
SC_FULL = $a0           ; voller Block

; ---------------- BASIC-Startzeile ----------------
        * = $0801
        .word (+), 2026
        .null $9e, format("%d", start)
+       .word 0

; =====================================================================
start   lda BORDER              ; alte Farben merken
        sta oldcol
        lda BGCOL
        sta oldcol+1
        lda TXTCOL
        sta oldcol+2
        lda #COL_BORDER         ; eigene Farben setzen
        sta BORDER
        lda #COL_SCREEN
        sta BGCOL
        lda #COL_TEXT
        sta TXTCOL
        lda #$17                ; Zeichensatz Gross/Klein
        sta $d018
        lda #$80                ; Umschalten mit C=+SHIFT sperren
        sta $0291
        jsr gentab
        lda #0
        sta hasres
        sta hasexp
        sta hcount
        sta reading
        jsr k_clr
        jsr k_title
        lda $ba                 ; Startlaufwerk (UCI, wenn vorhanden)
        jsr fb_init
        lda #1                  ; Browser gleich im Startlaufwerk oeffnen
        sta blevel
        jsr k_main
        jsr stclear
        #msg m_ready

; Hauptschleife: Tasten, dazwischen Farbverlauf im Titel
mainlp  jsr GETIN
        cmp #0
        bne ml_key
        .if TITLE_ANIM
        lda JIFFY
        cmp lastj
        beq mainlp
        sta lastj
        dec tick
        bpl mainlp
        lda #TITLE_SPEED-1
        sta tick
        jsr k_anim
        .endif
        jmp mainlp
ml_key  cmp #$86                ; F3
        beq k_brw
        cmp #$0d                ; RETURN
        beq k_brw
        cmp #$87                ; F5
        bne +
        jsr k_expin
        jmp mainlp
+       cmp #$88                ; F7
        bne mainlp
        jmp k_quit

; Dateibrowser zeigen, danach Pruefsumme berechnen
k_brw   lda #1                  ; wie LOAD: Zeiger zuerst, * ? erlaubt
        sta gload
        lda #0                  ; Namenszeile leer
        sta flen
        lda #<m_fprompt
        sta gnp
        lda #>m_fprompt
        sta gnp+1
        lda #R_INFO             ; Infozeile fuer den Browser leeren
        jsr k_clrow
        jsr fb_select
        php
        jsr fb_restore
        plp
        bcs +                   ; STOP: zurueck
        lda #0                  ; altes Ergebnis weg
        sta hasres
        jsr k_main
        jsr k_check
        jmp mainlp
+       jsr k_main
        jsr stclear
        #msg m_ready
        jmp mainlp

; Programm beenden
k_quit  jsr closeall
        .if SOUND
        lda #0                  ; Ton aus
        sta SID+4
        sta SID+$18
        .endif
        lda #$37                ; Speicher wie bei BASIC
        sta $01
        .if RESTORECOL
        lda oldcol              ; alte Farben wiederherstellen
        sta BORDER
        lda oldcol+1
        sta BGCOL
        lda oldcol+2
        sta TXTCOL
        .endif
        lda #0                  ; Zeichensatz wieder umschaltbar
        sta $0291
        lda #$8e                ; Grossbuchstaben/Grafik
        jsr CHROUT
        lda #$93                ; Bildschirm loeschen
        jsr CHROUT
        ldx #0
-       lda m_bye,x
        beq +
        jsr CHROUT
        inx
        bne -
+       rts                     ; zurueck zu BASIC

; =====================================================================
;  Bildschirm: Grundroutinen
; =====================================================================
; Ganzen Bildschirm leeren, Farbe COL_TEXT
k_clr   ldx #0
-       lda #$20
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$2e8,x
        lda #COL_TEXT
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne -
        rts

; Schreibposition: Zeile A, Spalte Y (setzt sc, cc, scol)
k_goto  tax
        lda rowlo,x
        sta sc
        sta cc
        lda rowhi,x
        sta sc+1
        clc
        adc #>($d800-SCREEN)
        sta cc+1
        sty scol
        rts

; Bildschirmcode A in Farbe pcol an die Schreibposition (X bleibt)
k_putsc ldy scol
        cpy #40
        bcs +
        sta (sc),y
        lda pcol
        sta (cc),y
        inc scol
+       rts

; Zeichen A (ASCII) an die Schreibposition (X wird 0)
k_putc  jsr a2s
        ora pinv
        jmp k_putsc

; Text X/Y (low/high, Ende 0) an die Schreibposition
k_puts  stx r
        sty r+1
        ldy #0
-       lda (r),y
        beq +
        sty kidx
        jsr k_putc
        ldy kidx
        iny
        bne -
+       rts

; Leerzeichen bis vor Spalte A
k_spto  sta kend
-       lda scol
        cmp kend
        bcs +
        lda #' '
        jsr k_putc
        jmp -
+       rts

; Bildschirmcode A X-mal
k_fill  sta kfch
-       lda kfch
        jsr k_putsc
        dex
        bne -
        rts

; Zeile A leeren (Zeichen und Farbe COL_TEXT)
k_clrow ldy #0
        jsr k_goto
        lda #COL_TEXT
        sta pcol
        lda #$20
        ldx #40
        jmp k_fill

; A als zwei Hex-Ziffern
k_phex  pha
        lsr
        lsr
        lsr
        lsr
        tax
        lda hexdig,x
        jsr k_putc
        pla
        and #$0f
        tax
        lda hexdig,x
        jmp k_putc

; num0..num3 (32 Bit) als Ziffern nach dbuf (dlen Stellen, num wird 0)
k_dec   lda #0
        sta dlen
-       jsr k_div10
        clc
        adc #'0'
        ldx dlen
        sta dbuf,x
        inc dlen
        lda num0
        ora num1
        ora num2
        ora num3
        bne -
        rts

; num dezimal ausgeben
k_pdec  jsr k_dec
k_pdbuf ldx dlen
-       lda dbuf-1,x
        stx kdx
        jsr k_putc
        ldx kdx
        dex
        bne -
        rts

; num dezimal, rechtsbuendig auf A Stellen
k_pdecr sta kw
        jsr k_dec
-       lda dlen
        cmp kw
        bcs k_pdbuf
        lda #' '
        jsr k_putc
        dec kw
        jmp -

; num /= 10, Rest in A
k_div10 lda #0
        ldx #32
-       asl num0
        rol num1
        rol num2
        rol num3
        rol a
        cmp #10
        bcc +
        sbc #10
        inc num0
+       dex
        bne -
        rts

; 4 Bytes ab Adresse X/A (low/high) nach num0..num3
k_tonum stx q
        sta q+1
        ldy #3
-       lda (q),y
        sta num0,y
        dey
        bpl -
        rts

; =====================================================================
;  Bildschirm: Teile
; =====================================================================
; Titelzeile (Zeile 0, invers)
k_title lda #0
        ldy #0
        jsr k_goto
        lda #COL_TITLE
        sta pcol
        lda #$80
        sta pinv
        ldx #<m_title
        ldy #>m_title
        jsr k_puts
        lda #40
        jsr k_spto
        lda #0
        sta pinv
        .if TITLE_ANIM
        jsr k_anim
        .endif
        rts

        .if TITLE_ANIM
; Farbverlauf: Farben der Titelzeile einen Schritt weiter
k_anim  inc tphase
        ldx #39
-       txa
        clc
        adc tphase
        and #31
        tay
        lda titlecols,y
        sta $d800,x
        dex
        bpl -
        rts
titlecols #TITLECOLS
        .endif

; Hauptbildschirm: Titel, Ergebnis, Verlauf, Infozeile
k_main  ldx #1                  ; Zeilen 1-22 leeren
-       stx kx
        txa
        jsr k_clrow
        ldx kx
        inx
        cpx #23
        bcc -
        jsr k_title
        jsr k_box
        jsr k_res
        jsr k_hist
        lda #R_HINT             ; Hinweis
        ldy #1
        jsr k_goto
        lda #COL_HINT
        sta pcol
        ldx #<m_hint
        ldy #>m_hint
        jsr k_puts
        lda #R_INFO             ; Infozeile
        jsr k_clrow
        lda #R_INFO
        ldy #0
        jsr k_goto
        lda #COL_HINT
        sta pcol
        ldx #<m_info
        ldy #>m_info
        jmp k_puts

; Rahmen um das Ergebnis
k_box   lda #R_BOX              ; oben
        ldy #0
        jsr k_goto
        lda #COL_BOX
        sta pcol
        lda #SC_TL
        jsr k_putsc
        lda #SC_H
        ldx #38
        jsr k_fill
        lda #SC_TR
        jsr k_putsc
        lda #R_BOX+1            ; Seiten
        sta kx
-       lda kx
        ldy #0
        jsr k_goto
        lda #SC_V
        jsr k_putsc
        lda kx
        ldy #39
        jsr k_goto
        lda #SC_V
        jsr k_putsc
        inc kx
        lda kx
        cmp #R_BOXE
        bcc -
        lda #R_SEP              ; Trennlinie
        ldy #0
        jsr k_goto
        lda #SC_LT
        jsr k_putsc
        lda #SC_H
        ldx #38
        jsr k_fill
        lda #SC_RT
        jsr k_putsc
        lda #R_BOXE             ; unten
        ldy #0
        jsr k_goto
        lda #SC_BL
        jsr k_putsc
        lda #SC_H
        ldx #38
        jsr k_fill
        lda #SC_BR
        jmp k_putsc

; Bezeichnung X/Y in Zeile A, Spalte 2, danach Schreibposition VCOL
k_label pha
        stx klx
        sty kly
        pla
        pha
        ldy #2
        jsr k_goto
        lda #COL_LABEL
        sta pcol
        ldx klx
        ldy kly
        jsr k_puts
        pla
        ldy #VCOL
        jsr k_goto
        lda #COL_VALUE
        sta pcol
        rts

; Ergebnis im Rahmen zeigen
k_res   lda hasres
        bne +
        lda #R_BIG+1            ; noch nichts: Hinweis
        ldy #8
        jsr k_goto
        lda #COL_HINT
        sta pcol
        ldx #<m_start
        ldy #>m_start
        jsr k_puts
        jmp k_exprow
+       lda #R_DRV              ; Laufwerk
        ldx #<m_rdrv
        ldy #>m_rdrv
        jsr k_label
        lda rdev
        jsr k_pdev
        lda rdev                ; UCI: Ordner
        bne kr_nm
        lda #R_DIR
        ldx #<m_rpath
        ldy #>m_rpath
        jsr k_label
        ldx #0
-       cpx rplen
        beq kr_nm
        lda scol
        cmp #39
        bcs kr_nm
        lda rpath,x
        stx kx
        jsr k_putc
        ldx kx
        inx
        bne -
kr_nm   lda #R_FILE             ; Dateiname
        ldx #<m_rfile
        ldy #>m_rfile
        jsr k_label
        ldx #0
-       cpx rlen
        beq +
        lda scol
        cmp #39
        bcs +
        lda rname,x
        stx kx
        ldy rdev                ; Diskette: Zeichen wie im Verzeichnis
        beq kr_a
        jsr dchra
kr_a    jsr k_putc
        ldx kx
        inx
        bne -
+       lda rok                 ; Werte nur bei vollstaendigem Lesen
        bne +
        lda #R_BIG+1            ; sonst: kein Ergebnis
        ldy #VCOL
        jsr k_goto
        lda #COL_BAD
        sta pcol
        ldx #<m_nores
        ldy #>m_nores
        jsr k_puts
        jmp k_exprow
+       lda #R_SIZE             ; Groesse
        ldx #<m_rsize
        ldy #>m_rsize
        jsr k_label
        ldx #<cnt0
        lda #>cnt0
        jsr k_tonum
        jsr k_pdec
        ldx #<m_bytes
        ldy #>m_bytes
        jsr k_puts
        lda #R_SIZE             ; Summe
        ldy #28
        jsr k_goto
        lda #COL_LABEL
        sta pcol
        ldx #<m_rsum
        ldy #>m_rsum
        jsr k_puts
        lda #COL_VALUE
        sta pcol
        lda sum1
        jsr k_phex
        lda sum0
        jsr k_phex
        jsr k_big               ; CRC-32 gross
        jmp k_exprow

; Laufwerk A ausgeben: 0 = U, sonst Nummer
k_pdev  bne +
        lda #'U'
        jmp k_putc
+       sta num0
        lda #0
        sta num1
        sta num2
        sta num3
        jmp k_pdec

; CRC-32 in grossen Ziffern (Zeilen R_BIG..R_BIG+2, Spalten 4-35)
; Farbe: MATCH gruen, MISMATCH rot, sonst COL_CRC
k_big   lda #COL_CRC
        ldx rmatch
        beq ++
        lda #COL_MATCH
        dex
        beq +
        lda #COL_BAD
+
+       sta pcol
        lda #0                  ; Ziffer 0-7, hoechste zuerst
        sta kdig
kb_lp   lda kdig
        lsr
        eor #3                  ; Byte: crc3 fuer Ziffer 0/1 ...
        tax
        lda crc0,x
        ldx kdig
        pha
        txa
        and #1
        tax
        pla
        cpx #0
        bne +
        lsr                     ; gerade Ziffer: oberes Halbbyte
        lsr
        lsr
        lsr
+       and #$0f
        sta kx                  ; Glyphe * 9
        asl
        asl
        asl
        clc
        adc kx
        sta kgl
        lda kdig                ; Spalte 4 + Ziffer * 4
        asl
        asl
        clc
        adc #4
        sta kcol
        lda #0
        sta krow
-       lda krow
        clc
        adc #R_BIG
        ldy kcol
        jsr k_goto
        ldx kgl
        lda bigfont,x
        jsr k_putsc
        lda bigfont+1,x
        jsr k_putsc
        lda bigfont+2,x
        jsr k_putsc
        lda kgl
        clc
        adc #3
        sta kgl
        inc krow
        lda krow
        cmp #3
        bcc -
        inc kdig
        lda kdig
        cmp #8
        bcc kb_lp
        rts

; Zeile Vergleichswert: "Expect  XXXXXXXX   MATCH"
k_exprow
        lda #R_EXP
        ldx #<m_rexp
        ldy #>m_rexp
        jsr k_label
        lda hasexp
        bne +
        lda #COL_HINT
        sta pcol
        ldx #<m_noexp
        ldy #>m_noexp
        jmp k_puts
+       ldx #<exp0
        lda #>exp0
        jsr k_hx4
        lda hasres
        beq ke_rt
        lda rok
        beq ke_rt
        lda #R_EXP
        ldy #28
        jsr k_goto
        lda rmatch
        cmp #1
        bne +
        lda #COL_MATCH
        sta pcol
        ldx #<m_match
        ldy #>m_match
        jmp k_puts
+       lda #COL_BAD
        sta pcol
        ldx #<m_mism
        ldy #>m_mism
        jmp k_puts
ke_rt   rts

; Verlauf zeigen (Zeilen R_HHEAD ...)
k_hist  lda #R_HHEAD
        ldy #0
        jsr k_goto
        lda #COL_LABEL
        sta pcol
        ldx #<m_hhead
        ldy #>m_hhead
        jsr k_puts
        lda #R_HLINE
        ldy #1
        jsr k_goto
        lda #COL_BOX
        sta pcol
        lda #SC_H
        ldx #38
        jsr k_fill
        lda hcount
        bne +
        lda #R_HIST
        ldy #1
        jsr k_goto
        lda #COL_HINT
        sta pcol
        ldx #<m_hempty
        ldy #>m_hempty
        jmp k_puts
+       lda #0
        sta kent
-       jsr k_hrow
        inc kent
        lda kent
        cmp hcount
        bcc -
        rts

; Verlaufseintrag kent in Zeile R_HIST+kent
; Eintrag: 0 Laenge, 1-16 Name (ASCII), 17-20 Groesse, 21-24 CRC,
;          25-26 Summe, 27 Vergleich (0 keiner, 1 MATCH, 2 MISMATCH)
k_hrow  lda kent
        asl
        asl
        asl
        asl
        asl
        sta khp                 ; Versatz im Verlauf
        lda kent
        clc
        adc #R_HIST
        ldy #0
        jsr k_goto
        lda #COL_HIST
        ldx kent
        bne +
        lda #$80                ; neuester Eintrag: invers
        sta pinv
        lda #COL_HISTNEW
+       sta pcol
        ldx khp                 ; Zeichen fuer den Vergleich
        lda HIST+27,x
        tay
        lda hmark,y
        jsr k_putc
        ldx khp                 ; Name (16)
        lda HIST,x
        sta kw
        ldy #0
-       cpy kw
        beq +
        sty kidx
        ldx khp
        txa
        clc
        adc kidx
        tax
        lda HIST+1,x
        jsr k_putc
        ldy kidx
        iny
        bne -
+       lda #18
        jsr k_spto
        ldx khp                 ; Groesse (8 Stellen)
        lda HIST+17,x
        sta num0
        lda HIST+18,x
        sta num1
        lda HIST+19,x
        sta num2
        lda HIST+20,x
        sta num3
        lda #8
        jsr k_pdecr
        lda #' '
        jsr k_putc
        lda khp                 ; CRC
        clc
        adc #<(HIST+21)
        tax
        lda #0
        adc #>(HIST+21)
        jsr k_hx4
        lda #' '
        jsr k_putc
        ldx khp                 ; Summe
        lda HIST+26,x
        jsr k_phex
        ldx khp
        lda HIST+25,x
        jsr k_phex
        lda #40
        jsr k_spto
        lda #0
        sta pinv
        rts

; 4 Bytes ab Adresse X/A (low/high) als 8 Hex-Ziffern
k_hx4   stx q
        sta q+1
        ldy #3
-       sty kidx
        lda (q),y
        jsr k_phex
        ldy kidx
        dey
        bpl -
        rts

hmark   .text " +x"             ; Vergleich: keiner, MATCH, MISMATCH

; Ergebnis in den Verlauf (oben), aeltester faellt heraus
k_hadd  ldx #(HMAX-1)*32-1      ; Eintraege eine Zeile nach unten
-       lda HIST,x
        sta HIST+32,x
        dex
        cpx #$ff
        bne -
        ldx #0                  ; Name (hoechstens 16, als ASCII)
-       cpx rlen
        beq +
        cpx #16
        bcs +
        lda rname,x
        ldy rdev
        beq ha_a
        jsr dchra               ; Diskette: Zeichen wie im Verzeichnis
ha_a    sta HIST+1,x
        inx
        bne -
+       stx HIST
        ldx #3
-       lda cnt0,x
        sta HIST+17,x
        lda crc0,x
        sta HIST+21,x
        dex
        bpl -
        lda sum0
        sta HIST+25
        lda sum1
        sta HIST+26
        lda rmatch
        sta HIST+27
        lda hcount
        cmp #HMAX
        bcs +
        inc hcount
+       rts

; Vergleich: rmatch = 0 kein Wert, 1 MATCH, 2 MISMATCH
k_cmp   lda #0
        sta rmatch
        lda hasexp
        beq +
        lda #1
        sta rmatch
        ldx #3
-       lda crc0,x
        cmp exp0,x
        beq kc_nx
        lda #2
        sta rmatch
kc_nx   dex
        bpl -
+       rts

; =====================================================================
;  F5: Vergleichswert eingeben (bis zu 8 Hex-Ziffern, leer = loeschen)
; =====================================================================
k_expin jsr stclear
        #msg m_expp
        lda #0
        sta elen
ki_key  jsr getkey
        cmp #$0d
        beq ki_ok
        cmp #$03                ; STOP: unveraendert zurueck
        bne +
        jsr stclear
        #msg m_ready
        rts
+       cmp #$14                ; DEL
        bne +
        lda elen
        beq ki_key
        dec elen
        dec stcol
        ldx stcol
        lda #$a0
        sta STAT,x
        jmp ki_key
+       cmp #$c1                ; mit SHIFT: wie ohne
        bcc +
        and #$7f
+       sec                     ; 0-9
        sbc #'0'
        cmp #10
        bcc ki_dig
        sbc #'A'-'0'            ; A-F (Carry ist gesetzt)
        cmp #6
        bcs ki_key
        adc #10
ki_dig  ldx elen
        cpx #8
        bcs ki_key
        sta ebuf,x
        inc elen
        tax
        lda hexdig,x
        jsr stputc
        jmp ki_key
ki_ok   lda #0
        sta hasexp
        sta exp0
        sta exp1
        sta exp2
        sta exp3
        lda elen
        beq ki_set
        ldx #0                  ; Ziffern zusammensetzen
-       ldy #4
-       asl exp0
        rol exp1
        rol exp2
        rol exp3
        dey
        bne -
        lda ebuf,x
        ora exp0
        sta exp0
        inx
        cpx elen
        bne --
        inc hasexp
ki_set  lda hasres              ; vorhandenes Ergebnis neu vergleichen
        beq +
        lda rok
        beq +
        lda hasexp              ; geloescht: Verlauf bleibt, wie er war
        beq +
        jsr k_cmp
        lda rmatch              ; auch im Verlauf
        sta HIST+27
+       jsr k_main
        jsr stclear
        #msg m_ready
        rts

; =====================================================================
;  Fortschritt waehrend des Lesens (Zeilen R_BIG, R_BIG+1)
;  ptotal = erwartete Groesse (0 = unbekannt), pest = 1: geschaetzt
; =====================================================================
k_prog  lda ptotal
        ora ptotal+1
        ora ptotal+2
        ora ptotal+3
        bne +
        jmp kp_cnt
+       ldx #3                  ; Balken: cnt*32/ptotal
-       lda cnt0,x
        sta dv0,x
        dex
        bpl -
        ldx #5
-       asl dv0
        rol dv1
        rol dv2
        rol dv3
        dex
        bne -
        jsr k_div
        lda dv1
        ora dv2
        ora dv3
        bne +
        lda dv0
        cmp #33
        bcc ++
+       lda #32
+       sta kpos
        lda #R_BIG
        ldy #3
        jsr k_goto
        ldx #0
-       lda #COL_BAR
        cpx kpos
        bcc +
        lda #COL_BAREMPTY
+       sta pcol
        lda #SC_FULL
        jsr k_putsc
        inx
        cpx #32
        bcc -
        ldx #3                  ; Prozent: cnt*100/ptotal (hoechstens 99)
-       lda cnt0,x
        sta dv0,x
        sta num0,x
        dex
        bpl -
        ldx #2                  ; *4
        jsr k_shnum
        jsr k_adddv             ; dv = cnt + 4*cnt ... siehe unten
        ldx #3                  ; num = cnt*32
        jsr k_shnum
        jsr k_adddv
        ldx #1                  ; num = cnt*64
        jsr k_shnum
        jsr k_adddv
        lda dv0                 ; dv = cnt*101: cnt abziehen -> cnt*100
        sec
        sbc cnt0
        sta dv0
        lda dv1
        sbc cnt1
        sta dv1
        lda dv2
        sbc cnt2
        sta dv2
        lda dv3
        sbc cnt3
        sta dv3
        jsr k_div
        lda dv1
        ora dv2
        ora dv3
        bne +
        lda dv0
        cmp #100
        bcc ++
+       lda #99
+       sta num0
        lda #0
        sta num1
        sta num2
        sta num3
        lda #R_BIG
        ldy #35
        jsr k_goto
        lda #COL_VALUE
        sta pcol
        lda #3
        jsr k_pdecr
        lda #'%'
        jsr k_putc
kp_cnt  lda #R_BIG+1            ; "nnnn / nnnn bytes"
        ldy #3
        jsr k_goto
        lda #COL_LABEL
        sta pcol
        ldx #<cnt0
        lda #>cnt0
        jsr k_tonum
        jsr k_pdec
        lda ptotal
        ora ptotal+1
        ora ptotal+2
        ora ptotal+3
        beq kp_by
        ldx #<m_of
        ldy #>m_of
        jsr k_puts
        lda pest
        beq +
        lda #'~'
        jsr k_putc
+       ldx #<ptotal
        lda #>ptotal
        jsr k_tonum
        jsr k_pdec
kp_by   ldx #<m_bytes
        ldy #>m_bytes
        jsr k_puts
        lda #39
        jmp k_spto

; num um X Stellen nach links schieben
k_shnum asl num0
        rol num1
        rol num2
        rol num3
        dex
        bne k_shnum
        rts
; dv += num
k_adddv clc
        lda dv0
        adc num0
        sta dv0
        lda dv1
        adc num1
        sta dv1
        lda dv2
        adc num2
        sta dv2
        lda dv3
        adc num3
        sta dv3
        rts

; dv0..3 / ptotal -> Quotient in dv0..3 (Rest in rm0..3)
k_div   lda #0
        sta rm0
        sta rm1
        sta rm2
        sta rm3
        ldx #32
-       asl dv0
        rol dv1
        rol dv2
        rol dv3
        rol rm0
        rol rm1
        rol rm2
        rol rm3
        lda rm0
        sec
        sbc ptotal
        tay
        lda rm1
        sbc ptotal+1
        sta kt1
        lda rm2
        sbc ptotal+2
        sta kt2
        lda rm3
        sbc ptotal+3
        bcc +
        sta rm3
        lda kt2
        sta rm2
        lda kt1
        sta rm1
        sty rm0
        inc dv0
+       dex
        bne -
        rts

; Bereich fuer den Fortschritt leeren (Zeilen R_SIZE..R_EXP im Rahmen)
k_pclr  lda #R_SIZE
        sta kx
-       lda kx
        ldy #1
        jsr k_goto
        lda #COL_TEXT
        sta pcol
        lda #39
        jsr k_spto
        inc kx
        lda kx
        cmp #R_EXP+1
        bcc -
        rts

; =====================================================================
;  Ton (SID, Stimme 1)
; =====================================================================
; A = 0: heller Ton (fertig), 1: tiefer Ton (Fehler, MISMATCH)
k_sound .if SOUND
        tax
        lda #$0f
        sta SID+$18             ; Lautstaerke
        lda #0
        sta SID+4               ; Ton neu beginnen
        sta SID+6               ; Halten 0, Ausklingen 0
        sta SID+0
        cpx #0
        bne +
        lda #$09                ; Anschlag 0, Abklingen 9
        sta SID+5
        lda #$40                ; etwa 1 kHz
        sta SID+1
        lda #$11                ; Dreieck, an
        sta SID+4
        rts
+       lda #$0a
        sta SID+5
        lda #$08                ; tief
        sta SID+1
        lda #$21                ; Saegezahn, an
        sta SID+4
        .endif
        rts

; =====================================================================
;  CRC-32
; =====================================================================
; Tabelle erzeugen (Polynom $EDB88320, reflektiert)
gentab  ldx #0
gt_lp   stx t0
        lda #0
        sta t1
        sta t2
        sta t3
        ldy #8
gt_bit  lsr t3
        ror t2
        ror t1
        ror t0
        bcc gt_nx
        lda t3
        eor #$ed
        sta t3
        lda t2
        eor #$b8
        sta t2
        lda t1
        eor #$83
        sta t1
        lda t0
        eor #$20
        sta t0
gt_nx   dey
        bne gt_bit
        lda t0
        sta TAB0,x
        lda t1
        sta TAB1,x
        lda t2
        sta TAB2,x
        lda t3
        sta TAB3,x
        inx
        bne gt_lp
        rts

; Startwerte
crcinit lda #$ff
        sta crc0
        sta crc1
        sta crc2
        sta crc3
        lda #0
        sta sum0
        sta sum1
        sta cnt0
        sta cnt1
        sta cnt2
        sta cnt3
        rts

; CRC abschliessen (XOR $FFFFFFFF)
crcfin  ldx #3
-       lda crc0,x
        eor #$ff
        sta crc0,x
        dex
        bpl -
        rts

; Ein Byte (in A) aufnehmen.  X wird veraendert, Y bleibt.
addbyte pha
        eor crc0
        tax
        lda crc1
        eor TAB0,x
        sta crc0
        lda crc2
        eor TAB1,x
        sta crc1
        lda crc3
        eor TAB2,x
        sta crc2
        lda TAB3,x
        sta crc3
        pla
        clc
        adc sum0
        sta sum0
        bcc +
        inc sum1
+       inc cnt0
        bne +
        inc cnt1
        bne +
        inc cnt2
        bne +
        inc cnt3
+
        .if BORDERFLASH
        inc BORDER              ; Rahmenflackern als Aktivitaetsanzeige
        .endif
        rts

; =====================================================================
;  Pruefsumme der gewaehlten Datei (device, fname/flen)
; =====================================================================
k_check lda device
        sta rdev
        lda #0
        sta rok
        sta rplen
        sta uabort
        sta rmatch
        sta pest
        ldx #3
-       sta ptotal,x
        dex
        bpl -
        jsr crcinit
        lda device
        bne +
        jmp k_uci
+       jmp k_iec

; Ergebnis der Datei uebernehmen: Name (fname) nach rname
k_keep  ldx #0
-       cpx flen
        beq +
        lda fname,x
        sta rname,x
        inx
        bne -
+       stx rlen
        lda #1
        sta hasres
        rts

; Lesen beginnt: Meldung, Name und Fortschritt zeigen
k_rdmsg jsr k_res               ; Laufwerk, Ordner, Name
        jsr k_pclr
        jsr k_prog
        jsr stclear
        #msg m_read
        rts

; Lesen fertig: Ergebnis zeigen, Ton
k_done  lda #COL_BORDER
        sta BORDER
        jsr crcfin
        lda #1
        sta rok
        jsr k_cmp
        jsr k_hadd
        jsr k_main
        jsr stclear
        lda rmatch
        cmp #2
        beq +
        #msg m_done
        lda #0
        jmp k_sound
+       #msg m_dmism
        lda #1
        jmp k_sound

; Abgebrochen
k_abrt  lda #COL_BORDER
        sta BORDER
        jsr k_main
        jsr stclear
        #msg m_abort
        rts

; Fehler (Meldung steht schon in der Statuszeile): Name zeigen, Ton
k_errnm lda #COL_BORDER
        sta BORDER
        jsr k_main
        lda #1
        jmp k_sound

; ---------------- Diskette ----------------
k_iec   lda #0
        jsr SETNAM
        jsr open15              ; Laufwerk vorhanden?
        bcc +
        jsr closeall
        jsr k_main
        jsr stclear
        #msg m_dev
        lda #1
        jmp k_sound
+       jsr k_blks              ; Bloecke aus der Liste (Schaetzung)
        jsr haswild             ; Platzhalter: echten Namen suchen
        bcc +
        jsr iecfind
+       jsr k_keep
        lda #2                  ; Datei als Kanal 2 oeffnen
        ldx device
        ldy #2
        jsr SETLFS
        lda flen
        ldx #<fname
        ldy #>fname
        jsr SETNAM
        jsr OPEN
        bcs ki_dev
        jsr drvstat             ; Meldung des Laufwerks
        lda msgbuf
        cmp #'2'                ; 00-19: in Ordnung
        bcc +
        jsr closeall
        jsr k_errnm
        jsr stclear
        jmp showdrv
+       ldx #2
        jsr CHKIN
        bcs ki_dev
        jsr k_rdmsg
        ldx #2                  ; (k_rdmsg benutzt den Bildschirm)
        jsr CHKIN
ki_lp   jsr CHRIN
        sta ktmp
        jsr READST
        sta kst
        and #%10111111          ; alles ausser EOF ist ein Fehler
        bne ki_err
        lda ktmp
        jsr addbyte
        lda cnt0                ; alle 256 Bytes: Fortschritt
        bne +
        jsr k_prog
+       lda kst
        bne ki_eof              ; Bit 6 = Dateiende
        jsr KSTOP
        bne ki_lp
        jsr closeall            ; RUN/STOP
        jmp k_abrt
ki_eof  jsr closeall
        jmp k_done
ki_err  jsr closeall
        jsr k_errnm
        jsr stclear
        #msg m_rderr
        lda kst
        jmp st_hex
ki_dev  jsr closeall
        jsr k_errnm
        jsr stclear
        #msg m_dev
        rts

; Groesse schaetzen: Bloecke des gewaehlten Listeneintrags * 254
; (nur wenn der Name zum Eintrag unter dem Zeiger passt)
k_blks  lda brec
        cmp #3                  ; Datei?
        bne kbl_rt
        lda brec+6
        cmp flen
        bne kbl_rt
        ldx #0
-       cpx flen
        beq +
        lda brec+7,x
        cmp fname,x
        bne kbl_rt
        inx
        bne -
+       lda brec+1
        ldx brec+2
; Bloecke A/X (low/high) -> ptotal = Bloecke * 254
k_setbl sta ptotal+1            ; * 256
        stx ptotal+2
        lda #0
        sta ptotal
        sta ptotal+3
        sta kt1
        lda ptotal+1            ; - Bloecke * 2
        asl
        sta kt2
        lda ptotal+2
        rol
        sta kt1
        lda ptotal
        sec
        sbc kt2
        sta ptotal
        lda ptotal+1
        sbc kt1
        sta ptotal+1
        lda ptotal+2
        sbc #0
        sta ptotal+2
        lda ptotal+3
        sbc #0
        sta ptotal+3
        lda #1
        sta pest
kbl_rt  rts

; A als zwei Hex-Ziffern in die Statuszeile
st_hex  pha
        lsr
        lsr
        lsr
        lsr
        tax
        lda hexdig,x
        jsr stputc
        pla
        and #$0f
        tax
        lda hexdig,x
        jmp stputc

; Enthaelt fname * oder ?  Carry gesetzt: ja
haswild ldx #0
-       cpx flen
        beq +
        lda fname,x
        cmp #'*'
        beq hw_y
        cmp #'?'
        beq hw_y
        inx
        bne -
+       clc
        rts
hw_y    sec
        rts

; Diskette: "$:muster" lesen und den Namen des ersten Treffers nach
; fname uebernehmen.  Genau diese Datei oeffnet das Laufwerk auch.
; Ohne Treffer bleibt der Name, das Laufwerk meldet dann den Fehler.
iecfind lda #'$'
        sta wbuf
        lda #':'
        sta wbuf+1
        ldx #0
-       cpx flen
        beq +
        lda fname,x
        sta wbuf+2,x
        inx
        bne -
+       inx
        inx
        txa
        ldx #<wbuf
        ldy #>wbuf
        jsr SETNAM
        lda #2
        ldx device
        ldy #0
        jsr SETLFS
        jsr OPEN
        bcs if_end
        lda #0
        sta deof
        ldx #2
        jsr CHKIN
        bcs if_end
        jsr dgetb               ; Ladeadresse
        jsr dgetb
        jsr dline               ; Kopfzeile
        bcs if_end
        jsr dline               ; erste Eintragszeile
        bcs if_end
        ldx #0                  ; Anfuehrungszeichen suchen
-       cpx llen
        beq if_end              ; z.B. "BLOCKS FREE.": kein Treffer
        lda lbuf,x
        inx
        cmp #'"'
        bne -
        ldy #0                  ; Name bis zum naechsten "
-       cpx llen
        beq if_end
        lda lbuf,x
        inx
        cmp #'"'
        beq +
        sta fname,y
        iny
        cpy #16
        bcc -
+       sty flen
        lda dnum                ; Bloecke des Treffers: Schaetzung
        ldx dnum+1
        jsr k_setbl
if_end  lda #2
        jsr CLOSE
        jmp CLRCHN

; ---------------- UCI ----------------
ku_cerr jsr ushow               ; Fehler merken (msgbuf), Datei schliessen
        jsr uclose
        jmp ku_e2
ku_err  jsr ushow               ; Fehler merken (msgbuf)
ku_e2   jsr k_errnm
        jsr stclear
        jmp showdrv

k_uci   lda #$12                ; GET_PATH: Ordner fuer die Anzeige
        jsr ucmd
        lda #<cb_path
        sta ucbv
        lda #>cb_path
        sta ucbv+1
        lda #0
        sta llen
        jsr ucirun
        bcs ku_err
        ldx #0
-       cpx llen
        beq +
        lda lbuf,x
        sta rpath,x
        inx
        bne -
+       stx rplen
        jsr haswild             ; Platzhalter: passende Datei suchen
        bcc +
        jsr ufind
        bcc +
        jmp ku_err
+       jsr k_keep
        lda #$02                ; OPEN_FILE zum Lesen
        jsr ucmd
        lda #$01
        jsr uaddb
        jsr uaddname
        jsr ucirun
        bcs ku_err
        jsr uciok
        bcs ku_err
        lda #$07                ; FILE_INFO: Dateigroesse
        jsr ucmd
        jsr ucirun
        bcs ku_cerr
        jsr uciok
        bcs ku_cerr
        ldx #3
-       lda URBUF,x
        sta usize,x
        sta ptotal,x            ; genaue Groesse fuer den Fortschritt
        dex
        bpl -
        jsr k_rdmsg
ku_lp   lda usize               ; noch etwas zu lesen?
        ora usize+1
        ora usize+2
        ora usize+3
        bne +
        jsr uclose
        jmp k_done
+       lda #<$4000             ; Stueck: hoechstens 16 KByte
        sta uchk
        lda #>$4000
        sta uchk+1
        lda usize+2
        ora usize+3
        bne +
        lda usize+1
        cmp #>$4000
        bcs +
        lda usize               ; Rest ist kleiner
        sta uchk
        lda usize+1
        sta uchk+1
+       lda #$04                ; READ_DATA
        jsr ucmd
        lda uchk
        jsr uaddb
        lda uchk+1
        jsr uaddb
        lda #<cb_crc
        sta ucbv
        lda #>cb_crc
        sta ucbv+1
        lda #0
        sta rdcnt
        sta rdcnt+1
        jsr ucirun
        bcs ku_ce2
        lda uabort
        beq +
        jsr uclose              ; RUN/STOP
        jmp k_abrt
+       jsr uciok
        bcc +
ku_ce2  jmp ku_cerr
+       lda rdcnt               ; nichts gekommen: Fehler
        ora rdcnt+1
        bne +
        lda #<m_nodata
        ldy #>m_nodata
        jsr ustset
        jmp ku_cerr
+       sec                     ; Rest = Rest - gelesen
        lda usize
        sbc rdcnt
        sta usize
        lda usize+1
        sbc rdcnt+1
        sta usize+1
        lda usize+2
        sbc #0
        sta usize+2
        lda usize+3
        sbc #0
        sta usize+3
        bcs +
        lda #0                  ; mehr als erwartet: fertig
        sta usize
        sta usize+1
        sta usize+2
        sta usize+3
+       jmp ku_lp
uclose  lda #$03                ; CLOSE_FILE (Meldung bleibt stehen)
        jsr ucmd
        jmp ucirun

; Ein Datenblock von READ_DATA (URBUF, Laenge url): in die Pruefsumme.
; Danach Fortschritt zeigen und RUN/STOP pruefen (Carry: abbrechen)
cb_crc  lda #<URBUF
        sta r
        lda #>URBUF
        sta r+1
        lda url
        sta kcnt
        lda url+1
        sta kcnt+1
        ldy #0
cc_lp   lda kcnt
        ora kcnt+1
        beq cc_end
        lda (r),y
        jsr addbyte
        inc r
        bne +
        inc r+1
+       lda kcnt
        bne +
        dec kcnt+1
+       dec kcnt
        jmp cc_lp
cc_end  clc                     ; gelesene Bytes zaehlen
        lda rdcnt
        adc url
        sta rdcnt
        lda rdcnt+1
        adc url+1
        sta rdcnt+1
        jsr k_prog
        jsr KSTOP
        bne +
        lda #1
        sta uabort
        sec
        rts
+       clc
        rts

; UCI: erste Datei im Ordner suchen, die zum Muster in fname passt;
; ihr echter Name kommt nach fname.  Carry gesetzt: Fehler oder kein
; Treffer (Meldung steht in USTAT)
ufind   lda #0
        sta found
        lda #$13                ; OPEN_DIR
        jsr ucmd
        jsr ucirun
        bcs uq_err
        jsr uciok
        bcs uq_err
        lda USTAT+1             ; "01": leer
        cmp #'1'
        beq uq_none
        lda #$14                ; READ_DIR
        jsr ucmd
        lda #<cb_match
        sta ucbv
        lda #>cb_match
        sta ucbv+1
        jsr ucirun
        bcs uq_err
        lda found
        beq uq_none
        ldx #0                  ; Treffer nach fname
-       cpx mlen
        beq +
        lda mbuf,x
        sta fname,x
        inx
        bne -
+       stx flen
        clc
        rts
uq_none lda #<m_nomatch
        ldy #>m_nomatch
        jsr ustset
uq_err  sec
        rts

; Eintrag gegen das Muster pruefen (nur Dateien, erster Treffer)
cb_match
        lda found
        bne cm_rt
        lda URBUF
        and #$10                ; Ordner ueberspringen
        bne cm_rt
        lda url+1               ; sehr langer Eintrag: ueberspringen
        bne cm_rt
        ldx #0                  ; Laenge des Namens
-       inx
        cpx url
        bcs +
        lda URBUF,x
        bne -
+       dex
        stx slen
        cpx #UNAMEL+1           ; laenger als ein Name sein darf
        bcs cm_rt
        jsr glob
        bcc cm_rt
        ldx #0                  ; Treffer: echten Namen merken
-       cpx slen
        beq +
        lda URBUF+1,x
        sta mbuf,x
        inx
        bne -
+       stx mlen
        inc found
cm_rt   clc
        rts

; Passt der Name (URBUF+1, Laenge slen) zum Muster (fname, flen)?
; * = beliebig viele Zeichen, ? = ein Zeichen, ohne Gross/Klein.
; Carry gesetzt: ja
glob    lda #0
        sta gp
        sta gs
        lda #$ff
        sta gstar
gl_lp   lda gs
        cmp slen
        bcs gl_tail             ; Name zu Ende
        ldx gp
        cpx flen
        bcs gl_back             ; Muster zu Ende
        lda fname,x
        cmp #'*'
        beq gl_star
        cmp #'?'
        beq gl_adv
        jsr upcase
        sta ktmp
        ldy gs
        lda URBUF+1,y
        jsr upcase
        cmp ktmp
        bne gl_back
gl_adv  inc gp
        inc gs
        jmp gl_lp
gl_star stx gstar               ; * merken, erst einmal leer
        lda gs
        sta gmark
        inc gp
        jmp gl_lp
gl_back lda gstar               ; zurueck zum letzten *, ein Zeichen mehr
        bmi gl_no
        tax
        inx
        stx gp
        inc gmark
        lda gmark
        sta gs
        jmp gl_lp
gl_tail ldx gp                  ; Rest des Musters darf nur * sein
-       cpx flen
        beq gl_yes
        lda fname,x
        cmp #'*'
        bne gl_no
        inx
        bne -
gl_yes  sec
        rts
gl_no   clc
        rts

; =====================================================================
;  Dateibrowser (Modul, unveraendert)
; =====================================================================
        .include "filebrowser.asm"

; =====================================================================
;  Grosse Ziffern 0-F: je 3x3 Bildschirmcodes (Halbbloecke)
; =====================================================================
bigfont
        .byte $a0, $e2, $a0, $a0, $20, $a0, $e2, $e2, $e2   ; 0
        .byte $62, $a0, $20, $20, $a0, $20, $e2, $e2, $e2   ; 1
        .byte $e2, $e2, $a0, $a0, $e2, $e2, $e2, $e2, $e2   ; 2
        .byte $e2, $e2, $a0, $e2, $e2, $a0, $e2, $e2, $e2   ; 3
        .byte $a0, $20, $a0, $e2, $e2, $a0, $20, $20, $e2   ; 4
        .byte $a0, $e2, $e2, $e2, $e2, $a0, $e2, $e2, $e2   ; 5
        .byte $a0, $e2, $e2, $a0, $e2, $a0, $e2, $e2, $e2   ; 6
        .byte $e2, $e2, $a0, $20, $20, $a0, $20, $20, $e2   ; 7
        .byte $a0, $e2, $a0, $a0, $e2, $a0, $e2, $e2, $e2   ; 8
        .byte $a0, $e2, $a0, $e2, $e2, $a0, $e2, $e2, $e2   ; 9
        .byte $a0, $e2, $a0, $a0, $e2, $a0, $e2, $20, $e2   ; A
        .byte $a0, $e2, $62, $a0, $e2, $62, $e2, $e2, $20   ; B
        .byte $a0, $e2, $e2, $a0, $20, $20, $e2, $e2, $e2   ; C
        .byte $a0, $e2, $62, $a0, $20, $a0, $e2, $e2, $20   ; D
        .byte $a0, $e2, $e2, $a0, $e2, $e2, $e2, $e2, $e2   ; E
        .byte $a0, $e2, $e2, $a0, $e2, $e2, $e2, $20, $20   ; F

; =====================================================================
;  Texte (ASCII, Ausgabe ueber a2s)
; =====================================================================
hexdig    .text "0123456789ABCDEF"
m_title   .null " CRC-CHECKER 1.0 - CRC-32 for the C64"
m_info    .null " F3 Select  F5 Expected CRC  F7 Exit"
m_hint    .null "Typed names may use * and ?"
m_start   .null "Press F3 to choose a file"
m_fprompt .null " FILE: "
m_ready   .null " Ready."
m_read    .null " Reading...  (RUN/STOP aborts)"
m_done    .null " Done."
m_dmism   .null " Done. CRC does not match!"
m_abort   .null " Aborted."
m_rderr   .null " Read error, status $"
m_nodata  .null "UCI: read error (no data)"
m_nomatch .null "UCI: no matching file"
m_expp    .null " Expected CRC-32: "
m_rdrv    .null "Drive"
m_rpath   .null "Folder"
m_rfile   .null "File"
m_rsize   .null "Size"
m_rsum    .null "Sum  "
m_rexp    .null "Expect"
m_noexp   .null "-       (F5 to enter)"
m_match   .null "MATCH"
m_mism    .null "MISMATCH"
m_nores   .null "no result"
m_bytes   .null " bytes"
m_of      .null " / "
m_hhead   .null " File                 Size CRC-32   Sum"
m_hempty  .null "(no files checked yet)"
m_bye     .byte $42, $59, $45, $21, $0d, 0      ; "BYE!" (PETSCII)

; =====================================================================
;  Variablen
; =====================================================================
oldcol  .fill 3, 0              ; Rahmen, Hintergrund, Schrift beim Start
hasres  .byte 0                 ; 1 = Ergebnis vorhanden
rok     .byte 0                 ; 1 = Datei vollstaendig gelesen
rdev    .byte 0                 ; Laufwerk des Ergebnisses
rlen    .byte 0
rname   .fill 26, 0             ; Name des Ergebnisses
rplen   .byte 0
rpath   .fill 40, 0             ; Ordner des Ergebnisses (UCI)
rmatch  .byte 0                 ; 0 kein Vergleich, 1 MATCH, 2 MISMATCH
hasexp  .byte 0                 ; 1 = Vergleichswert gesetzt
exp0    .byte 0                 ; Vergleichswert (exp0 = niedrigstes Byte)
exp1    .byte 0
exp2    .byte 0
exp3    .byte 0
ebuf    .fill 8, 0              ; Eingabe des Vergleichswerts
elen    .byte 0
hcount  .byte 0                 ; Eintraege im Verlauf
reading .byte 0
ptotal  .fill 4, 0              ; erwartete Groesse (Fortschritt)
pest    .byte 0                 ; 1 = Groesse geschaetzt (Bloecke)
dv0     .byte 0                 ; Division
dv1     .byte 0
dv2     .byte 0
dv3     .byte 0
rm0     .byte 0
rm1     .byte 0
rm2     .byte 0
rm3     .byte 0
kt1     .byte 0
kt2     .byte 0
kpos    .byte 0
wbuf    .fill 20, 0             ; "$:muster"
mbuf    .fill 26, 0             ; Treffer der Suche
mlen    .byte 0
dbuf    .fill 10, 0             ; Dezimalziffern (rueckwaerts)
dlen    .byte 0
scol    .byte 0                 ; Schreibposition: Spalte
pcol    .byte 0                 ; Schreibfarbe
pinv    .byte 0                 ; $80 = invers
lastj   .byte 0                 ; Farbverlauf: letzte Uhrzeit
tick    .byte 0
tphase  .byte 0
kidx    .byte 0
kx      .byte 0
kdx     .byte 0
khx     .byte 0
klx     .byte 0
kly     .byte 0
kw      .byte 0
kend    .byte 0
kfch    .byte 0
kdig    .byte 0
kgl     .byte 0
kcol    .byte 0
krow    .byte 0
kent    .byte 0
khp     .byte 0
ktmp    .byte 0
kst     .byte 0
kcnt    .word 0
t0      .byte 0
t1      .byte 0
t2      .byte 0
t3      .byte 0
crc0    .byte 0
crc1    .byte 0
crc2    .byte 0
crc3    .byte 0
sum0    .byte 0
sum1    .byte 0
cnt0    .byte 0
cnt1    .byte 0
cnt2    .byte 0
cnt3    .byte 0
num0    .byte 0
num1    .byte 0
num2    .byte 0
num3    .byte 0
usize   .fill 4, 0
uchk    .word 0
rdcnt   .word 0
uabort  .byte 0
found   .byte 0
slen    .byte 0
gp      .byte 0
gs      .byte 0
gstar   .byte 0
gmark   .byte 0
progend
        .cerror progend > UCBUF, "Programm reicht in die UCI-Puffer"
