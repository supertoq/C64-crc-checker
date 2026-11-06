; =====================================================================
;  fb_uci.asm  -  UCI-Teil des Dateibrowsers (wird von filebrowser.asm
;  eingebunden).  Ultimate Command Interface, DOS-Ziel 1.
; =====================================================================

; ---------------------------------------------------------------------
;  UCI-Schnittstelle (Ultimate Command Interface)
;  Befehl: Bytes nach UCI_CMD, dann Bit 0 in UCI_CTRL.
;  Antwort: Zustand in UCI_CTRL (Bit 4-5), Daten aus UCI_DATA (Bit 7),
;  Statustext aus UCI_STAT (Bit 6), quittieren mit Bit 1 in UCI_CTRL.
; ---------------------------------------------------------------------
; UCI erkennen: Kennung $C9 mehrmals lesbar und IDENTIFY antwortet
; Danach in den Startordner wechseln (m_uhome)
ucidet  lda #0
        sta ucion
        ldx #16
-       lda UCI_CMD             ; Kennung: $C9 (oder $49 mit IRQ)
        and #$7f
        cmp #$49
        bne ud_rt
        nop
        nop
        dex
        bne -
        lda #$01                ; IDENTIFY
        jsr ucmd
        jsr ucirun
        bcs ud_rt               ; keine Antwort
        jsr uciok
        bcs ud_rt
        lda #1
        sta ucion
        lda #0                  ; UCI ist das erste Laufwerk
        sta device
        lda #$11                ; CHANGE_DIR Startordner (m_uhome)
        jsr ucmd
        ldx #0
-       lda m_uhome,x
        beq +
        jsr uaddb
        inx
        bne -
+       jsr ucirun
ud_rt   rts

; Ist die Schnittstelle eingeblendet?  Kennung $C9 (oder $49 mit IRQ)
; Carry gesetzt: nein
ucihere lda UCI_CMD
        and #$7f
        cmp #$49
        bne +
        clc
        rts
+       sec
        rts

; Befehl beginnen: Ziel DOS (1) und Befehlsbyte aus A
; Antwortdaten werden danach verworfen (ucbv = cb_none)
ucmd    pha
        lda #$01
        sta UCBUF
        pla
        sta UCBUF+1
        lda #2
        sta ucl
        lda #0
        sta ucl+1
        lda #<cb_none
        sta ucbv
        lda #>cb_none
        sta ucbv+1
        rts

; Byte aus A an den Befehl anhaengen (A und X bleiben erhalten)
uaddb   sta ubt
        clc
        lda #<UCBUF
        adc ucl
        sta ux
        lda #>UCBUF
        adc ucl+1
        sta ux+1
        lda ubt
        ldy #0
        sta (ux),y
        inc ucl
        bne +
        inc ucl+1
+       rts

; Dateinamen anhaengen
uaddname
        ldx #0
-       cpx flen
        beq +
        lda fname,x
        jsr uaddb
        inx
        bne -
+       rts

; Befehl senden und Antwort abarbeiten
; Jeder Antwortblock (Daten in URBUF, Laenge url) geht an die
; Routine in ucbv; sie meldet mit Carry gesetzt: abbrechen.
; Statustext steht danach in USTAT (mit 0 am Ende), Laenge ustl.
; Carry gesetzt: keine Antwort (Zeitgrenze), USTAT enthaelt Meldung
ucirun  lda #0
        sta ustl
        jsr ucihere             ; Schnittstelle noch eingeblendet?
        bcc +
        jmp ur_gone
+       jsr uciidle
        bcs ur_to
        lda #<UCBUF              ; Befehl schreiben
        sta ux
        lda #>UCBUF
        sta ux+1
        ldy #0
        ldx ucl+1
        beq ur_rest
-       lda (ux),y              ; volle 256-Byte-Seiten
        sta UCI_CMD
        iny
        bne -
        inc ux+1
        dex
        bne -
ur_rest ldx ucl
        beq ur_push
-       lda (ux),y
        sta UCI_CMD
        iny
        dex
        bne -
ur_push lda #$01                ; Befehl absenden
        sta UCI_CTRL
ur_blk  jsr uciwait              ; auf gueltige Antwort warten
        bcs ur_to
        sta ust                 ; 2 = letzter Block, 3 = weitere
        jsr ucirdat             ; Daten und Status lesen
        jsr ucicb               ; Block verarbeiten
        bcs ur_ab
        jsr uciack              ; quittieren
        bcs ur_to
        lda ust
        cmp #3
        beq ur_blk              ; weitere Bloecke folgen
ur_ab   jsr uciabrt             ; Ende oder Abbruch: UCI in den Leerlauf
ur_end  ldx ustl
        lda #0
        sta USTAT,x
        clc
        rts
ur_gone lda #0                  ; Schnittstelle nicht da
        sta ucion
        lda #<m_unact
        ldy #>m_unact
        jmp ustset
ur_to   lda UCI_CTRL            ; Statusregister fuer die Diagnose
        sta ustreg
        jsr uciabrt             ; Zeitgrenze: abbrechen, Meldung
        ldx #0
-       lda m_uto,x
        sta USTAT,x
        beq +
        inx
        bne -
+       lda #' '                ; Diagnose: Befehl, Stelle, Status
        sta USTAT,x
        inx
        lda UCBUF+1             ; Befehlsbyte
        jsr uhex
        lda #' '
        sta USTAT,x
        inx
        lda #'W'
        sta USTAT,x
        inx
        lda uwhere
        clc
        adc #'0'
        sta USTAT,x
        inx
        lda #' '
        sta USTAT,x
        inx
        lda #'$'
        sta USTAT,x
        inx
        lda ustreg
        jsr uhex
        lda #0
        sta USTAT,x
        stx ustl
        sec
        rts

; Byte in A als zwei Hex-Ziffern nach USTAT,x schreiben
uhex    pha
        lsr
        lsr
        lsr
        lsr
        jsr uh_d
        pla
        and #$0f
uh_d    cmp #10
        bcc +
        adc #6                  ; A-F (Carry ist gesetzt)
+       adc #'0'
        sta USTAT,x
        inx
        rts

ucicb   lda ucbv                ; nach ucbv springen (ohne JMP (ind),
        sec                     ; der bei $xxFF die falsche Adresse liest)
        sbc #1
        tax
        lda ucbv+1
        sbc #0
        pha
        txa
        pha
        rts
cb_none clc
        rts

; Daten (nach URBUF, Laenge url) und Status (an USTAT) lesen
ucirdat lda #<URBUF
        sta ur
        lda #>URBUF
        sta ur+1
        lda #0
        sta url
        sta url+1
        ldy #0
rd_lp   lda UCI_CTRL
        bpl rd_st               ; keine Daten mehr
        lda UCI_DATA
        ldx url+1
        cpx #4                  ; hoechstens 1024 Bytes ablegen
        bcs rd_lp
        sta (ur),y
        inc ur
        bne +
        inc ur+1
+       inc url
        bne rd_lp
        inc url+1
        jmp rd_lp
rd_st   lda UCI_CTRL
        and #$40
        beq rd_rt               ; kein Status mehr
        lda UCI_STAT
        ldx ustl
        cpx #79
        bcs rd_st
        sta USTAT,x
        inc ustl
        jmp rd_st
rd_rt   rts

; Warten, solange die UCI beschaeftigt ist
; A = Zustand danach: 0 Leerlauf, 2 letzte Daten, 3 weitere Daten
; Carry gesetzt: keine Antwort (nach etwa 6 Sekunden)
uciwait lda #2                  ; Stelle fuer die Diagnose
        sta uwhere
        jsr utoset
uw_lp   lda UCI_CTRL
        tax
        and #$08                ; Fehlerbit: Befehl nicht angenommen
        bne uw_er
        txa
        and #$20                ; Bit 5: Antwort liegt vor
        bne uw_ok
        jsr utodec
        bcc uw_lp
        rts
uw_er   lda #4                  ; Diagnose: Stelle 4 = Fehlerbit
        sta uwhere
        sec
        rts
uw_ok   txa
        and #$30
        lsr
        lsr
        lsr
        lsr
        clc
        rts

; Daten quittieren und warten, bis das Ultimate es bestaetigt hat
; Carry gesetzt: keine Antwort
uciack  lda #3                  ; Stelle fuer die Diagnose
        sta uwhere
        lda #$02
        sta UCI_CTRL
        jsr utoset
-       lda UCI_CTRL
        and #$02
        beq +
        jsr utodec
        bcc -
        rts
+       clc
        rts

; Abbrechen und warten, bis die UCI wieder im Leerlauf ist
uciabrt lda #$04
        sta UCI_CTRL
        jsr utoset
-       lda UCI_CTRL
        and #$34                ; Abbruch erledigt und Leerlauf?
        beq +
        jsr utodec
        bcc -
+       rts

; Vor einem Befehl: UCI muss im Leerlauf sein (Zustandsbits 0)
; Fehlerbit loeschen; liegen noch Daten an, diese quittieren;
; nur wenn sie haengt, abbrechen.  Carry gesetzt: keine Antwort
uciidle lda #1                  ; Stelle fuer die Diagnose
        sta uwhere
        lda UCI_CTRL
        and #$08
        beq +
        lda #$08                ; Fehlerbit loeschen
        sta UCI_CTRL
+       jsr utoset
ui_lp   lda UCI_CTRL
        and #$34                ; Leerlauf ohne offenen Abbruch
        beq ui_ok
        and #$30
        beq +                   ; nur Abbruch offen: warten
        cmp #$10
        beq +                   ; beschaeftigt: warten
        lda UCI_CTRL            ; Daten liegen an: quittieren
        and #$02
        bne +
        lda #$02
        sta UCI_CTRL
+       jsr utodec
        bcc ui_lp
        jsr uciabrt             ; haengt: abbrechen
        lda UCI_CTRL
        and #$30
        beq ui_ok
        sec
        rts
ui_ok   clc
        rts

; Zeitgrenze setzen und herunterzaehlen (Carry gesetzt: abgelaufen)
utoset  lda #0
        sta uto
        sta uto+1
        lda #4
        sta uto+2
        rts
utodec  lda uto
        bne ++
        lda uto+1
        bne +
        lda uto+2
        beq ut_end
        dec uto+2
+       dec uto+1
+       dec uto
        clc
        rts
ut_end  sec
        rts

; Statustext pruefen: leer oder "00..." = in Ordnung
; Carry gesetzt: Fehler
uciok   lda ustl
        beq +
        lda USTAT
        cmp #'0'
        bne uo_err
        lda USTAT+1
        cmp #'0'
        bne uo_err
+       clc
        rts
uo_err  sec
        rts

; Statustext der UCI in der Statuszeile zeigen (leer = 00,OK)
ushow   ldx #0
        lda ustl
        bne +
-       lda m_uok,x             ; leer: "00,OK" zeigen
        sta msgbuf,x
        beq us_sh
        inx
        bne -
+
-       lda USTAT,x
        sta msgbuf,x
        beq us_sh
        inx
        cpx #39                 ; hoechstens 39 Zeichen
        bcc -
        lda #0
        sta msgbuf,x
us_sh   jsr stclear
        jmp showdrv

; ---------------------------------------------------------------------
;  UCI: Ordner und Inhaltsverzeichnis
; ---------------------------------------------------------------------
; Ordner wechseln.  Der Pfad steht in fname, z.B. "TEXTE/", "..",
; "/" oder "/USB0/TEXTE/".  Jeder Teil wird im Verzeichnis gesucht,
; Gross/Klein egal, und mit der echten Schreibweise gewechselt.
; Carry gesetzt: Fehler (Meldung steht, fname bleibt erhalten)
ucicd   ldx flen                ; Laenge ohne / am Ende
        stx cdlen
        cpx #1
        beq +
        lda fname-1,x
        cmp #'/'
        bne +
        dec cdlen
+       lda #0
        sta cdpos
        lda fname               ; / am Anfang: vom Root aus
        cmp #'/'
        bne cd_part
        lda #'/'
        sta cbuf
        lda #1
        sta cblen
        jsr cd_cmd
        bcs cd_err
        inc cdpos
cd_part lda cdpos               ; naechster Teil bis / oder Ende
        cmp cdlen
        bcs cd_done
        ldx cdpos
        ldy #0
-       cpx cdlen
        beq +
        lda fname,x
        cmp #'/'
        beq +
        sta cbuf,y
        iny
        inx
        bne -
+       sty cblen
        inx                     ; / ueberspringen
        stx cdpos
        lda cblen
        beq cd_part             ; leerer Teil (z.B. //)
        cmp #2                  ; ".." direkt wechseln
        bne cd_find
        lda cbuf
        cmp #'.'
        bne cd_find
        lda cbuf+1
        cmp #'.'
        beq cd_go
cd_find jsr cd_look             ; echte Schreibweise suchen
cd_go   jsr cd_cmd
        bcs cd_err
        jmp cd_part
cd_done lda #0                  ; geschafft: Name leeren
        sta flen
        clc
        rts
cd_err  jsr ushow
        sec
        rts

; CHANGE_DIR mit dem Namen in cbuf (Laenge cblen)
; Carry gesetzt: Fehler (Meldung in USTAT)
cd_cmd  lda #$11
        jsr ucmd
        ldx #0
-       cpx cblen
        beq +
        lda cbuf,x
        jsr uaddb
        inx
        bne -
+       jsr ucirun
        bcs +
        jsr uciok
+       rts

; Ordner cbuf im aktuellen Verzeichnis suchen (Gross/Klein egal).
; Gefunden: cbuf/cblen enthalten danach die echte Schreibweise.
cd_look lda #0
        sta cdfnd
        lda #$13                ; OPEN_DIR
        jsr ucmd
        jsr ucirun
        bcs cl_rt
        jsr uciok
        bcs cl_rt
        lda #$14                ; READ_DIR, jeden Eintrag vergleichen
        jsr ucmd
        lda #<cb_find
        sta ucbv
        lda #>cb_find
        sta ucbv+1
        jsr ucirun
        lda cdfnd
        beq cl_rt
        ldx #0                  ; gefundene Schreibweise uebernehmen
-       lda rbuf,x
        sta cbuf,x
        inx
        cpx cdfnd
        bne -
        stx cblen
cl_rt   rts

; Ein Verzeichniseintrag: Ordner mit gleichem Namen (Gross/Klein egal)?
cb_find lda cdfnd               ; schon gefunden: Rest ueberlesen
        bne cf_ok
        lda URBUF               ; nur Ordner
        and #$10
        beq cf_ok
        lda url+1               ; sehr langer Eintrag: kein Ordnername
        bne cf_ok
        ldx #0
-       cpx cblen
        beq cf_end
        txa                     ; Name beginnt bei URBUF+1
        clc
        adc #1
        cmp url
        bcs cf_ok               ; Eintrag kuerzer
        lda URBUF+1,x
        jsr upcase
        sta ubt
        lda cbuf,x
        jsr upcase
        cmp ubt
        bne cf_ok
        inx
        bne -
cf_end  inx                     ; Eintrag muss hier zu Ende sein
        cpx url
        bcs +
        lda URBUF,x
        bne cf_ok
+       ldx #0                  ; echte Schreibweise merken
-       lda URBUF+1,x
        sta rbuf,x
        inx
        cpx cblen
        bne -
        stx cdfnd
cf_ok   clc
        rts

; a-z in A-Z umwandeln (ASCII)
upcase  cmp #'a'
        bcc +
        cmp #'z'+1
        bcs +
        and #$df
+       rts

; Pfad aus der Antwort nach lbuf/llen (hoechstens 40 Zeichen)
cb_path ldx #0
-       cpx url
        beq +
        cpx #40
        bcs +
        lda URBUF,x
        beq +
        sta lbuf,x
        inx
        bne -
+       stx llen
        clc
        rts

; Meldung (A = low, Y = high) als UCI-Status zeigen.  Carry gesetzt
ushow_m jsr ustset
        jsr ushow
        sec
        rts
; Meldung (A = low, Y = high) als UCI-Status ablegen.  Carry gesetzt
ustset  sta q
        sty q+1
        ldy #0
-       lda (q),y
        sta USTAT,y
        beq +
        iny
        bne -
+       sty ustl
        sec
        rts
