; =====================================================================
;  filebrowser.asm  -  Dateibrowser fuer LOAD und SAVE auf dem C64
;  Laufwerke 8-11 (IEC) und U (UCI, Ultimate-Geraete)
;  Herausgeloest aus TextEditor64 2.0_u (supertoq), 64tass
; =====================================================================
;
;  EINBINDEN
;    Dateien: filebrowser.asm und fb_uci.asm (UCI-Teil, wird von hier
;    eingebunden).  Eigene Werte (siehe KONFIGURATION) im Hauptprogramm
;    festlegen, dann irgendwo im Code:      .include "filebrowser.asm"
;    Texte und Namen sind ASCII; das Modul stellt .enc "ascii" ein.
;    Bildschirm mit Zeichensatz Gross/Klein (z.B. $D018 = $17).
;
;  AUFRUFE
;    fb_init     einmal beim Start.  A = Startlaufwerk (8-11, z.B. $BA).
;                Loescht die Variablen, setzt den NMI-Vektor im RAM unter
;                dem KERNAL, erkennt die UCI (dann device = 0 = U) und
;                wechselt dort in den Startordner m_uhome.
;    fb_select   Browser zeigen.  Vorher setzen:
;                  gnp   = Adresse des Hinweistexts, z.B. " LOAD: "
;                  gload = 1 LOAD (Platzhalter * ? erlaubt, Zeiger zuerst)
;                          0 SAVE (Name zuerst)
;                  fname/flen duerfen einen Vorschlag enthalten.
;                Ergebnis: Carry geloescht = Name gewaehlt
;                  fname/flen = Dateiname (ASCII, bei Diskette PETSCII)
;                  device     = 0 UCI (Ordner ist schon gewechselt)
;                               8-11 Diskettenlaufwerk
;                Carry gesetzt = mit STOP abgebrochen
;                Der Browser merkt sich Laufwerk, Ordner und Zeiger.
;    fb_restore  danach: Farben der Liste und Rahmen zuruecksetzen.
;                (Den Textbereich zeichnet das Hauptprogramm neu.)
;    fb_dirty    Liste beim naechsten Aufruf neu lesen (nach dem Speichern).
;
;  NUTZBAR FUER DAS HAUPTPROGRAMM
;    getkey                 auf eine Taste warten (A = Taste)
;    stclear, stmsg, stputc  Statuszeile STAT (stmsg: X/Y = Text)
;    showdrv                Text aus msgbuf in die Statuszeile
;    open15, drvstat, closeall   IEC-Kommandokanal, Meldung nach msgbuf
;    ucmd, uaddb, uaddname, ucirun, uciok, ushow   UCI-Befehle
;    extchk                 gesperrte Dateiendung in fname? (Carry)
;    a2s, p2a, upcase       Zeichen umwandeln
;
;  BILDSCHIRM
;    Zeile 0 Titel, Zeilen 1-BROWS Liste, Zeile STAT Namens- und
;    Statuszeile, Zeile INFO Infozeile (FB_INFO = 1: "F7 Help").
;
;  SPEICHER
;    Liste im RAM unter dem KERNAL: BLIST bis $FEFF (32 Bytes je Eintrag)
;    UCI-Puffer: UCBUF (512), URBUF (1024), USTAT (80)
;    Zero Page:  p, q, r, sc, sz, ur, ux (je 2 Bytes)
;    Variablen:  FB_VARS = 0: im Modul, sonst ab dieser Adresse
;
; =====================================================================

; ---- KONFIGURATION
; Vorgaben (.weak): eine eigene Definition im Hauptprogramm, z.B.
; SCREEN = $0400, ersetzt den Wert hier, egal ob davor oder danach.
        .weak
SCREEN  = $0400                 ; Bildschirmspeicher
STAT    = SCREEN+23*40          ; Namens- und Statuszeile
INFO    = SCREEN+24*40          ; Infozeile
BROWS   = 22                    ; Zeilen der Liste (Zeile 0 = Titel)
FB_INFO = 1                     ; 1 = Infozeile "F4 PgUp  F6 PgDn  F7 Help"
TEXTCOL = 15                    ; Farben: Text
BORDCOL = 6                     ;   Rahmen ausserhalb des Browsers
DIRCOL  = 14                    ;   Rahmen im Browser
FOLDCOL = 14                    ;   Laufwerke, Ordner und ..
PTRCOL  = 15                    ;   Zeiger >
BSHOWX  = 1                     ; Dateien mit gesperrter Endung zeigen (1)
UNAMEL  = 25                    ; Dateiname bei UCI hoechstens 25 Zeichen
BLIST   = $e000                 ; Liste unter dem KERNAL
BMAX    = 248                   ; Eintraege ($E000-$FEFF)
UCBUF   = $4000                 ; UCI-Befehlspuffer (512 Bytes)
URBUF   = $4200                 ; UCI-Antwortpuffer (1024 Bytes)
USTAT   = $4600                 ; UCI-Statustext (80 Bytes)
FB_VARS = 0                     ; Variablen: 0 = im Modul
; Zero Page (je 2 Bytes)
p       = $fb
q       = $fd
r       = $28
sc      = $f7
sz      = $f9
ur      = $50
ux      = $52
; Ersatzzeichen (Bildschirmcodes) fuer nicht darstellbare Zeichen
ALT_LBRACE      = 168
ALT_RBRACE      = 169
ALT_TILDE       = 173
ALT_BACKTICK    = 167
ALT_PIPE        = 93
ALT_UNDERSCORE  = 100
ALT_BACKSLASH   = 28
ALT_CARET       = 30
ALT_OTHER       = 174
; Gesperrte Dateiendungen (Grossbuchstaben, durch Leerzeichen getrennt)
BLOCKED .macro
        .text "D64 G64 D71 G71 D81 DNP ISO CRT TAP T64 REU SID PRG ZIP"
        .endm
        .endweak

; ---- feste Werte
BRECL   = 32                    ; Bytes je Listeneintrag
TAB     = $09
UCI_CTRL = $df1c                ; schreiben: Steuerung, lesen: Zustand
UCI_CMD  = $df1d                ; schreiben: Befehl, lesen: Kennung ($C9)
UCI_DATA = $df1e                ; lesen: Antwortdaten
UCI_STAT = $df1f                ; lesen: Statustext
SETLFS  = $ffba
SETNAM  = $ffbd
OPEN    = $ffc0
CLOSE   = $ffc3
CHKIN   = $ffc6
CHKOUT  = $ffc9
CLRCHN  = $ffcc
CHRIN   = $ffcf
CHROUT  = $ffd2
GETIN   = $ffe4
READST  = $ffb7
LISTEN  = $ffb1
UNLSN   = $ffae
CLALL   = $ffe7
KSTOP   = $ffe1

        .enc "ascii"
        .cdef $00, $ff, $00

inc16   .macro
        inc \1
        bne _skip
        inc \1+1
_skip
        .endm

msg     .macro
        ldx #<\1
        ldy #>\1
        jsr stmsg
        .endm

; ---------------------------------------------------------------------
;  Aufrufe des Moduls
; ---------------------------------------------------------------------
fb_init pha                     ; Startlaufwerk
        lda #<fb_vstart         ; Variablen loeschen
        sta p
        lda #>fb_vstart
        sta p+1
        lda #<fb_vsize
        sta sz
        lda #>fb_vsize
        sta sz+1
        ldy #0
-       tya
        sta (p),y
        #inc16 p
        lda sz
        bne +
        dec sz+1
+       dec sz
        lda sz
        ora sz+1
        bne -
        pla
        cmp #8
        bcs +
        lda #8
+       sta device
        lda #<nmiret            ; NMI-Vektor im RAM unter dem KERNAL
        sta $fffa               ; (wirkt nur, waehrend der KERNAL
        lda #>nmiret            ; fuer die Liste ausgeblendet ist)
        sta $fffb
        jmp ucidet

fb_select = getname

fb_restore
        lda bcols               ; Liste gefaerbt: Zeilen zuruecksetzen
        beq +
        lda #BROWS
        sta drow2
-       lda #TEXTCOL
        jsr rowcol
        dec drow2
        bpl -
        lda #0
        sta bcols
+       lda #BORDCOL
        sta $d020
        rts

fb_dirty
        lda #0
        sta bvalid
        rts

nmiret  rti

getkey  jsr GETIN
        cmp #0
        beq getkey
        rts

; Tastencode in ASCII-Zeichen umwandeln
; Der Tastencode kommt im Register A an,
; das Ergebnis steht danach wieder in A.
; Ergebnis 0: Taste ohne Zeichen, wird ignoriert
p2a     cmp #TAB
        beq p2a_ok              ; CTRL+I = Tabulator
        cmp #$20
        bcc p2a_no
        cmp #$41
        bcc p2a_ok              ; $20-$40 unveraendert
        cmp #$5b
        bcc p2a_lo              ; $41-$5A = Kleinbuchstaben
        cmp #$5e
        beq p2a_pi              ; Pfeil hoch -> |
        cmp #$5f
        beq p2a_bt              ; Pfeil links -> `
        cmp #$60
        bcc p2a_ok              ; $5B-$5D  [ \ ]
        cmp #$a9
        beq p2a_us              ; SHIFT+Pfund-Taste -> _
        cmp #$db
        beq p2a_lb              ; SHIFT+Plus-Taste -> {
        cmp #$dd
        beq p2a_rb              ; SHIFT+Minus-Taste -> }
        cmp #$de
        beq p2a_ca              ; SHIFT+Pfeil hoch -> ^
        cmp #$c1
        bcc p2a_no
        cmp #$db
        bcs p2a_no
        and #$7f                ; $C1-$DA = Grossbuchstaben
        rts
p2a_lo  clc
        adc #$20
p2a_ok  rts
p2a_no  lda #0
        rts
p2a_pi  lda #$7c                ; |
        rts
p2a_us  lda #$5f                ; _
        rts
p2a_ca  lda #$5e                ; ^
        rts
p2a_bt  lda #$60                ; `
        rts
p2a_lb  lda #$7b                ; {
        rts
p2a_rb  lda #$7d                ; }
        rts

; ASCII-Zeichen in Bildschirmcode umwandeln
; Das Zeichen kommt im Register A an,
; der Bildschirmcode steht danach in A. X ist danach 0.
a2s     cmp #$80
        bcs a2s_np              ; ab 128: nicht darstellbar
        tax
        lda a2stab,x
        ldx #0
        rts
a2s_np  lda #ALT_OTHER
        ldx #0
        rts

; Tabelle ASCII 0-127 -> Bildschirmcode (Ersatzzeichen aus den Optionen)
a2stab  .for i = 0, i < 128, i += 1
        .byte i < $20 ? ALT_OTHER : i < $40 ? i : i == $40 ? 0 : i < $5b ? i : i == $5c ? ALT_BACKSLASH : i == $5e ? ALT_CARET : i == $5f ? ALT_UNDERSCORE : i < $60 ? i & $1f : i == $60 ? ALT_BACKTICK : i < $7b ? i & $1f : i == $7b ? ALT_LBRACE : i == $7c ? ALT_PIPE : i == $7d ? ALT_RBRACE : i == $7e ? ALT_TILDE : ALT_OTHER
        .next

rowlo   .for i = 0, i < 25, i += 1
        .byte <(SCREEN+i*40)
        .next
rowhi   .for i = 0, i < 25, i += 1
        .byte >(SCREEN+i*40)
        .next

; Zahl sz (0-65535) als 5 Zeichen nach numbuf schreiben,
; fuehrende Nullen werden Leerzeichen
todec   ldx #0                  ; 5 Dezimalstellen bestimmen
dg_nx   lda #'0'
        sta numbuf,x
dg_sub  sec
        lda sz
        sbc pwlo,x
        tay
        lda sz+1
        sbc pwhi,x
        bcc dg_dn
        sta sz+1
        sty sz
        inc numbuf,x
        jmp dg_sub
dg_dn   inx
        cpx #5
        bne dg_nx
        ldx #0                  ; fuehrende Nullen durch Leerzeichen ersetzen
-       lda numbuf,x
        cmp #'0'
        bne +
        lda #$20
        sta numbuf,x
        inx
        cpx #4
        bne -
+       rts

pwlo    .byte <10000, <1000, <100, <10, <1
pwhi    .byte >10000, >1000, >100, >10, >1

; ---------------------------------------------------------------------
;  Statuszeile (invertiert)
; ---------------------------------------------------------------------
stclear ldx #39
        lda #$a0
-       sta STAT,x
        dex
        bpl -
        lda #0
        sta stcol
        rts

stputc  jsr a2s                 ; Zeichen im Register A ausgeben
        ora #$80
        ldx stcol
        cpx #40
        bcs +
        sta STAT,x
        inc stcol
+       rts

stmsg   stx p                   ; Text ausgeben, Adresse in X (low) und Y (high)
        sty p+1
stprint ldy #0                  ; Text ausgeben, Adresse steht in p, Ende = 0
-       lda (p),y
        beq +
        jsr stputc
        iny
        bne -
+       rts

; Text (A = low, Y = high) links in die Infozeile schreiben
infopg  sta q
        sty q+1
        ldy #0
-       lda (q),y
        beq +
        jsr a2s
        sta INFO,y
        iny
        bne -
+       rts

; ---------------------------------------------------------------------
;  Dateibrowser fuer LOAD und SAVE
;  Oben die Liste mit dem Zeiger > (Laufwerke, Ordner, Dateien),
;  unten immer die Namenszeile.  Die Liste liegt im RAM unter dem
;  KERNAL ($E000-$FEFF, je Eintrag 32 Bytes).
;  CRSR hoch/runter, F4/F6 (Seite), HOME: Zeiger bewegen
;  RETURN: Name aus der Zeile verwenden, wenn zuletzt getippt wurde
;          (oder der Name gerade uebernommen wurde), sonst den
;          Eintrag unter dem Zeiger: Laufwerk/Ordner/.. wechseln,
;          Datei laden (LOAD) oder ihren Namen uebernehmen (SAVE)
;  STOP: abbrechen.  Laufwerk und Ordner bleiben fuer das naechste Mal.
;  gnp = Adresse des Hinweistexts (SAVE: / LOAD:)
;  Carry-Bit gesetzt: abgebrochen
; ---------------------------------------------------------------------
getname lda device              ; UCI gewaehlt, aber nicht mehr da?
        bne gn_brw
        jsr ucihere
        bcc gn_brw
        lda #8                  ; auf Laufwerk 8 wechseln
        sta device
        lda #0                  ; Liste neu: Laufwerksauswahl
        sta blevel
        sta bvalid
        lda ucion
        beq gn_brw
        lda #0                  ; einmal melden, warum
        sta ucion
        lda #<m_unact
        ldy #>m_unact
        jsr ushow_m
        jsr getkey
gn_brw  lda gload               ; LOAD: Zeiger zuerst, SAVE: Name zuerst
        sta bmoved
gn_list lda bvalid              ; Liste lesen, wenn noetig
        bne +
        jsr bload
+
        .if FB_INFO
        lda #<m_pgb             ; Infozeile: F7 Help
        ldy #>m_pgb
        jsr infopg
        .endif
        jsr bdraw
gn_go   jsr gnsetmax
        jsr stclear
        lda gnp                 ; Hinweistext ausgeben
        sta p
        lda gnp+1
        sta p+1
        jsr stprint
        ldy #0
-       cpy flen
        beq +
        lda fname,y
        ldx device              ; Diskette: Zeichen wie im Verzeichnis
        beq gn_pc
        jsr dchra
gn_pc   jsr stputc
        iny
        bne -
+       jsr gn_drv              ; Laufwerk rechts anzeigen
gn_lp   jsr getkey
        cmp #$0d
        bne +
        jmp gn_ok
+       cmp #$03                ; STOP: abbrechen
        bne +
        sec
        rts
+       cmp #$14
        beq gn_bs
        ldx #nbkeys-1           ; Tasten fuer den Zeiger
-       cmp bkeys,x
        beq gn_bk
        dex
        bpl -
        cmp #$20
        bcc gn_lp
        ldx device              ; UCI: Zeichen wie im Text (ASCII)
        bne gn_iec
        jsr p2a
        cmp #$20
        bcc gn_lp
        cmp #$7f
        bcs gn_lp
        bcc gn_put
gn_iec  cmp #$60                ; Diskette: wie bisher
        bcs gn_lp
gn_put  jsr badchr              ; im Namen nicht erlaubt?
        bcs gn_lp
        ldx flen
        cpx gnmax
        bcs gn_lp
        sta fname,x
        inc flen
        jsr stputc
        lda #0                  ; zuletzt getippt
        sta bmoved
        jmp gn_lp
gn_bs   lda flen
        beq gn_lp
        dec flen
        dec stcol
        ldx stcol
        lda #$a0
        sta STAT,x
        lda #0
        sta bmoved
        jmp gn_lp
gn_bk   txa                     ; Zeiger bewegen
        asl
        tax
        lda bkhand+1,x
        pha
        lda bkhand,x
        pha
        rts
bkeys   .byte $11,$91,$8b,$8a,$13,$88
nbkeys  = * - bkeys
bkhand  .word bk_dn-1,bk_up-1,bk_pd-1,bk_pu-1,bk_hm-1,bk_help-1
bk_dn   ldx bsel
        inx
        cpx bcount
        bcs bk_no
        stx bsel
        bcc bk_mv
bk_up   ldx bsel
        beq bk_no
        dex
        stx bsel
        jmp bk_mv
bk_pd   lda bsel                ; eine Seite weiter
        clc
        adc #BROWS
        bcs +
        cmp bcount
        bcc ++
+       ldx bcount
        dex
        txa
+       sta bsel
        jmp bk_mv
bk_pu   lda bsel                ; eine Seite zurueck
        sec
        sbc #BROWS
        bcs +
        lda #0
+       sta bsel
        jmp bk_mv
bk_hm   lda #0
        sta bsel
bk_mv   lda #1                  ; zuletzt den Zeiger bewegt
        sta bmoved
        jsr bdraw
bk_no   jmp gn_lp

; F7: Hilfe ueber der Liste zeigen, eine Taste: zurueck zur Liste
bk_help lda #0                  ; Titel
        sta drow2
        jsr sd_clr
        ldy #0
-       lda m_hlpt,y
        beq +
        jsr a2s
        ora #$80
        sta (sc),y
        iny
        bne -
+       lda #<m_hlp
        sta p
        lda #>m_hlp
        sta p+1
        lda #1
        sta drow2
bh_ln   jsr sd_clr              ; eine Zeile (Text endet mit $FF)
        lda #TEXTCOL
        jsr rowcol
        ldx #0
        lda (p,x)
        cmp #$ff
        beq bh_rest
        ldy #1                  ; Text ab Spalte 1
bh_ch   ldx #0
        lda (p,x)
        #inc16 p
        cmp #$20                ; 0 = Zeilenende, 1-31 = Spalte
        bcs +
        tay
        bne bh_ch
        inc drow2
        bne bh_ln
+       jsr a2s
        sta (sc),y
        iny
        bne bh_ch
bh_rest lda drow2               ; restliche Zeilen leeren
        cmp #BROWS+1
        bcs +
        jsr sd_clr
        inc drow2
        bne bh_rest
+       jsr getkey
        jsr bdraw
        jmp gn_lp

; RETURN
gn_ok   lda bmoved              ; Zeiger bewegt oder Zeile leer:
        bne gn_ptr              ; Eintrag unter dem Zeiger
        lda flen
        beq gn_ptr
        lda device              ; Name aus der Zeile.  UCI: Ordner?
        bne gn_dol
        jsr isdirnm
        bcc gn_dol
        jsr ucicd
        php
        jsr binval
        lda #1
        sta blevel
        plp
        bcc +
        jsr getkey              ; Fehler: Meldung lesen, Name bleibt
+       jmp gn_list
gn_dol  lda flen
        cmp #1                  ; Name $ = Liste neu lesen
        bne gn_ret
        lda fname
        cmp #'$'
        bne gn_ret
        lda #0
        sta flen
        jsr binval
        lda #1
        sta blevel
        jmp gn_list
gn_ret  clc
        rts

; Eintrag unter dem Zeiger
gn_ptr  lda bsel
        jsr bget
        lda blevel
        bne +
        lda device              ; Laufwerksauswahl: Laufwerk waehlen
        sta gnold
        lda brec+1
        sta device
        jsr gn_conv
        lda #1
        sta blevel
        jmp gn_nav
+       lda brec
        beq gn_upd              ; ..
        cmp #2
        beq gn_dir              ; Ordner
        cmp #3
        beq +
        jmp gn_lp               ; Name zu lang: nicht waehlbar
+       ldx #0                  ; Datei: Namen uebernehmen
-       cpx brec+6
        beq +
        lda brec+7,x
        sta fname,x
        inx
        bne -
+       stx flen
        txa                     ; leerer Name: nicht waehlbar
        bne +
        jmp gn_lp
+       lda #0
        sta bmoved
        lda gload               ; LOAD: gleich laden
        bne gn_ret
        jmp gn_go               ; SAVE: Name in die Zeile
gn_dir  ldx #0                  ; Ordner: hinein wechseln
-       cpx brec+6
        beq +
        lda brec+7,x
        sta cbuf,x
        inx
        bne -
+       stx cblen
        jmp gn_cd
gn_upd  lda device              ; ..: Diskette oder UCI-Stamm
        bne gn_top              ; -> Laufwerksauswahl
        lda broot
        bne gn_top
        jsr bfromset            ; Zeiger danach auf diesen Ordner
        lda #'.'                ; UCI: eine Ebene hoeher
        sta cbuf
        sta cbuf+1
        lda #2
        sta cblen
gn_cd   jsr cd_cmd
        bcc gn_nav
        jsr ushow
        jsr getkey
        jmp gn_nav
gn_top  lda #0
        sta blevel
gn_nav  jsr binval              ; Liste neu lesen, Zeiger oben
        jmp gn_brw

; Laufwerkswechsel: Namen anpassen (UCI ASCII, Diskette Grossbuchstaben)
gn_conv lda gnold
        bne gw_iec
        lda device
        beq gw_ok               ; UCI -> UCI
        jsr nm_up               ; UCI -> Diskette: Grossbuchstaben
        jmp gw_ok
gw_iec  lda device
        bne gw_ok               ; Diskette -> Diskette
        jsr nm_low              ; Diskette -> UCI: Kleinbuchstaben
gw_ok   jsr nm_clean            ; nicht erlaubte Zeichen entfernen
        jsr gnsetmax            ; Name ggf. kuerzen
        lda flen
        cmp gnmax
        bcc +
        lda gnmax
        sta flen
+       rts

; Liste ungueltig machen, Zeiger an den Anfang
binval  lda #0
        sta bvalid
        sta bsel
        sta btop
        rts

; Liste lesen (Laufwerksauswahl, Diskette oder UCI-Ordner)
; Bei einem Fehler: Meldung lesen lassen, dann Laufwerksauswahl
bload   lda blevel
        beq bl_err2
        lda device
        bne +
        jsr bl_uci
        jmp ++
+       jsr bl_disk
+       bcc bl_ok
        jsr getkey              ; Fehlermeldung lesen lassen
        lda #0
        sta blevel
bl_err2 jsr bl_drv
bl_ok   lda #1
        sta bvalid
        lda bfind               ; nach ..: Ordner suchen, aus dem
        beq bfs_rt              ; man kommt, Zeiger darauf
        lda #1
        sta bidx
bfs_lp  lda bidx
        cmp bcount
        bcs bfs_end
        jsr bget
        lda brec                ; Ordner mit gleichem Namen?
        cmp #2
        bne bfs_nx
        lda brec+6
        cmp bfind
        bne bfs_nx
        ldx #0
-       cpx bfind
        beq bfs_hit
        lda brec+7,x
        cmp bfrom,x
        bne bfs_nx
        inx
        bne -
bfs_hit lda bidx
        sta bsel
        bcs bfs_end             ; (Carry ist hier gesetzt)
bfs_nx  inc bidx
        bne bfs_lp
bfs_end lda #0
        sta bfind
bfs_rt  rts

; Namen des aktuellen UCI-Ordners (letzter Teil des Pfads im Titel)
; nach bfrom/bfind merken
bfromset
        lda #0
        sta bfind
        ldx btlen
        beq bf_rt
        dex
        lda btit,x              ; / am Ende weglassen
        cmp #'/'
        bne +
        dex
        bmi bf_rt
+       stx bfend               ; letztes Zeichen des Namens
-       lda btit,x              ; Anfang: nach dem / davor
        cmp #'/'
        beq +
        dex
        bpl -
+       inx
        ldy #0
-       cpy #UNAMEL             ; zu lang: nicht suchen
        bcs bf_rt
        lda btit,x
        sta bfrom,y
        iny
        cpx bfend
        beq +
        inx
        bne -
+       sty bfind
bf_rt   rts

; Laufwerksauswahl: U (wenn vorhanden), 8, 9, 10, 11
bl_drv  lda #0
        sta bcount
        ldx #0                  ; Titel
-       lda m_drvs,x
        sta btit,x
        beq +
        inx
        bne -
+       stx btlen
        lda #1
        sta brec
        lda ucion
        beq +
        lda #0
        jsr bl_dadd
+       lda #8
-       jsr bl_dadd
        lda brec+1
        clc
        adc #1
        cmp #12
        bcc -
        clc
        rts
bl_dadd sta brec+1
        cmp device              ; Zeiger auf das aktuelle Laufwerk
        bne +
        ldx bcount
        stx bsel
+       jmp badd

; Neue Liste beginnen: Eintrag ..
bl_init lda #0
        sta bcount
        sta brec
        sta dok
        jmp badd

; Diskette: Verzeichnis lesen
bl_disk jsr diropen
        bcc +
        rts
+       jsr bl_init
        jsr dline               ; Kopfzeile = Titel
        bcs bd_endj
        ldx #0
-       cpx llen
        beq +
        lda lbuf,x
        sta btit,x
        inx
        bne -
+       stx btlen
bd_lp   jsr KSTOP               ; STOP: Lesen beenden
        beq bd_endj
        jsr dline
        bcc +
bd_endj jmp bd_end
+
        ldx #0                  ; Anfuehrungszeichen suchen
-       cpx llen
        beq bd_free
        lda lbuf,x
        inx
        cmp #'"'
        bne -
        ldy #0                  ; Name bis zum naechsten "
-       cpx llen
        beq bd_typ
        lda lbuf,x
        inx
        cmp #'"'
        beq bd_typ
        cpy #16
        bcs -
        sta brec+7,y
        iny
        bne -
bd_typ  sty brec+6
-       cpx llen                ; Leerzeichen und * ueberspringen
        beq +
        lda lbuf,x
        cmp #' '
        beq bd_sk
        cmp #'*'
        bne +
bd_sk   inx
        bne -
+       ldy #0                  ; Dateityp (3 Zeichen)
-       lda #' '
        cpx llen
        bcs +
        lda lbuf,x
        inx
+       sta brec+3,y
        iny
        cpy #3
        bne -
        lda dnum                ; Bloecke
        sta brec+1
        lda dnum+1
        sta brec+2
        lda #3
        sta brec
        jsr bl_fadd
        jmp bd_lp
bd_free lda dnum                ; Zeile ohne ": BLOCKS FREE
        sta dfree
        lda dnum+1
        sta dfree+1
        lda #1
        sta dok
        jmp bd_lp
bd_end  jsr closeall
        clc
        rts

; Datei in die Liste (gesperrte Endung nur, wenn BSHOWX = 1)
bl_fadd .if BSHOWX == 0
        lda #<(brec+7)
        sta r
        lda #>(brec+7)
        sta r+1
        lda brec+6
        sta xlen
        jsr extchkp
        bcc badd
        rts
        .endif
; Eintrag brec ans Ende der Liste (hoechstens BMAX Eintraege)
badd    lda bcount
        cmp #BMAX
        bcs +
        jsr bput
        inc bcount
+       rts

; UCI: Ordner lesen
bl_uci  lda #$12                ; GET_PATH = Titel
        jsr ucmd
        lda #<cb_path
        sta ucbv
        lda #>cb_path
        sta ucbv+1
        lda #0
        sta llen
        jsr ucirun
        bcs bu_err
        ldx #0
        stx broot
-       cpx llen
        beq +
        lda lbuf,x
        sta btit,x
        inx
        bne -
+       stx btlen
        cpx #1                  ; Pfad "/" = Stamm
        bne +
        lda lbuf
        cmp #'/'
        bne +
        inc broot
+       jsr bl_init
        lda #$13                ; OPEN_DIR
        jsr ucmd
        jsr ucirun
        bcs bu_err
        lda USTAT               ; "01,DIRECTORY EMPTY": nichts lesen
        cmp #'0'
        bne bu_err
        lda USTAT+1
        cmp #'1'
        beq bu_ok
        jsr uciok
        bcs bu_err
        lda #$14                ; READ_DIR
        jsr ucmd
        lda #<cb_bent
        sta ucbv
        lda #>cb_bent
        sta ucbv+1
        jsr ucirun
        bcs bu_err
bu_ok   clc
        rts
bu_err  jsr ushow
        sec
        rts

; Ein Verzeichniseintrag der UCI: URBUF = Attribut, Name
; Carry gesetzt: STOP gedrueckt (Lesen beenden)
cb_bent jsr KSTOP
        bne +
        sec
        rts
+       lda #2                  ; Ordner oder Datei
        sta brec
        lda URBUF
        and #$10
        bne +
        inc brec
+       ldx #0                  ; Name bis zur 0 oder zum Ende
-       txa
        clc
        adc #1
        cmp url
        bcs +
        lda URBUF+1,x
        beq +
        cpx #UNAMEL
        bcs cb_long
        sta brec+7,x
        inx
        bne -
cb_long lda #4                  ; zu lang: nur anzeigen
        sta brec
+       stx brec+6
        lda brec
        cmp #3
        bne +
        jsr bl_fadd             ; Datei
        clc
        rts
+       jsr badd
        clc
        rts

; Liste zeigen: Titel invers in Zeile 0, darunter BROWS Eintraege
bdraw   lda #DIRCOL             ; Laufwerksinhalt: eigene Rahmenfarbe
        sta $d020
        lda bsel                ; Zeiger sichtbar halten
        cmp btop
        bcs +
        sta btop
+       sec
        sbc btop
        cmp #BROWS
        bcc +
        lda bsel
        sec
        sbc #BROWS-1
        sta btop
+       lda #0
        sta bdisk
        lda blevel
        beq +
        lda device
        beq +
        inc bdisk               ; Diskette: Zeichen wie im Verzeichnis
+       lda #0
        sta drow2
        jsr sd_clr
        ldx #0
        ldy #0
-       cpx btlen
        beq bt_free
        lda btit,x
        inx
        cmp #$12                ; Invers-Steuerzeichen weglassen
        beq -
        stx dx
        jsr bchr
        ldx dx
        ora #$80
        sta (sc),y
        iny
        cpy #40
        bcc -
bt_free lda bdisk               ; Diskette: freie Bloecke rechts
        beq bt_rows
        lda dok
        beq bt_rows
        lda dfree
        sta sz
        lda dfree+1
        sta sz+1
        jsr todec
        ldy #25                 ; Zahl ohne fuehrende Leerzeichen,
        ldx #0                  ; "nnn BLKS FREE" endet in Spalte 39
-       lda numbuf,x
        cmp #$20
        beq +
        ora #$80
        sta (sc),y
+       iny
        inx
        cpx #5
        bne -
        ldx #0
-       lda m_bfree,x
        beq bt_rows
        stx dx
        jsr a2s
        ldx dx
        ora #$80
        sta (sc),y
        iny
        inx
        bne -
bt_rows lda #1                  ; Zeilen 1 bis BROWS
        sta drow2
bt_lp   lda drow2               ; Eintrag btop + Zeile - 1
        clc
        adc btop
        bcs bt_clr
        sbc #0                  ; (Carry geloescht: minus 1)
        cmp bcount
        bcs bt_clr
        jsr brow
        jmp bt_nx
bt_clr  jsr sd_clr
        lda #TEXTCOL
        jsr rowcol
bt_nx   inc drow2
        lda drow2
        cmp #BROWS+1
        bcc bt_lp
        rts

; Eintrag A in Zeile drow2 zeigen
brow    sta bidx
        jsr bget
        jsr sd_clr
        lda #FOLDCOL            ; Farbe: Laufwerke, Ordner und .. in FOLDCOL
        ldx brec
        cpx #3                  ; Dateien (3, 4) in TEXTCOL
        bcc +
        lda #TEXTCOL
+       jsr rowcol
        lda bidx
        cmp bsel
        bne +
        lda #PTRCOL             ; Zeiger in eigener Farbe
        ldy #0
        sta (q),y
        lda #'>'
        sta (sc),y
+       ldy #2
        lda brec
        bne br_dev
        lda #'.'                ; ..
        sta (sc),y
        iny
        sta (sc),y
        rts
br_dev  cmp #1
        bne br_nm
        lda brec+1              ; Laufwerk: U, 8, 9, 10, 11
        bne +
        lda #'U'
        sta (sc),y
        rts
+       cmp #10
        bcc +
        lda #'1'
        sta (sc),y
        iny
        lda brec+1
        sbc #10
+       ora #'0'
        sta (sc),y
        rts
br_nm   ldx #0                  ; Name
-       cpx brec+6
        beq +
        lda brec+7,x
        stx dx
        jsr bchr
        ldx dx
        sta (sc),y
        iny
        inx
        bne -
+       lda brec
        cmp #2                  ; Ordner: / anhaengen
        bne +
        lda #'/'
        sta (sc),y
+       lda bdisk               ; Diskette: Typ und Bloecke
        beq br_rt
        ldy #20
        ldx #0
-       lda brec+3,x
        stx dx
        jsr dchr
        ldx dx
        sta (sc),y
        iny
        inx
        cpx #3
        bne -
        lda brec+1
        sta sz
        lda brec+2
        sta sz+1
        jsr todec
        ldy #25
        ldx #0
-       lda numbuf,x
        sta (sc),y
        iny
        inx
        cpx #5
        bne -
br_rt   rts

; Farbe A fuer Zeile drow2 setzen (merkt sich, dass der Text
; danach wieder einheitlich gefaerbt werden muss)
rowcol  ldx #1
        stx bcols
        ldy drow2
        ldx rowlo,y
        stx q
        ldx rowhi,y
        stx q+1
        pha
        lda q+1                 ; Farbspeicher = Bildschirm + $D400
        clc
        adc #>($d800-SCREEN)
        sta q+1
        pla
        ldy #39
-       sta (q),y
        dey
        bpl -
        rts

; Zeichen fuer die Liste: Diskette wie im Verzeichnis, sonst ASCII
bchr    ldx bdisk
        beq +
        jmp dchr
+       jmp a2s

; Adresse des Eintrags A im RAM unter dem KERNAL nach q
baddr   pha
        and #7
        asl
        asl
        asl
        asl
        asl
        sta q
        pla
        lsr
        lsr
        lsr
        clc
        adc #>BLIST
        sta q+1
        rts
; brec in Eintrag A schreiben / Eintrag A nach brec lesen
bput    jsr baddr
        sei
        lda $01                 ; Speicherbelegung merken
        sta bkmem
        lda #$35                ; KERNAL aus (RAM sichtbar), I/O an
        sta $01
        ldy #BRECL-1
-       lda brec,y
        sta (q),y
        dey
        bpl -
        bmi bk_end
bget    jsr baddr
        sei
        lda $01
        sta bkmem
        lda #$35
        sta $01
        ldy #BRECL-1
-       lda (q),y
        sta brec,y
        dey
        bpl -
bk_end  lda bkmem               ; Speicherbelegung zurueck
        sta $01
        cli
        rts

; Ist das Zeichen in A im Dateinamen verboten?  Carry gesetzt: ja
; (beim Laden, gload = 1, sind die Platzhalter * und ? erlaubt)
; Diskette: * ? , : = " /   (DOS-Befehle, Platzhalter, Unterordner)
; UCI:      * ? : " < > | \ (im FAT-Dateisystem nicht erlaubt)
; A und X bleiben erhalten (Y wird veraendert)
badchr  stx bcx
        ldx gload               ; beim Laden sind * und ? erlaubt
        beq bc_chk
        cmp #'*'
        beq bc_n
        cmp #'?'
        beq bc_n
bc_chk  ldx #0
        ldy device
        bne bc_iec
-       cmp bad_uci,x
        beq bc_y
        inx
        cpx #8
        bcc -
        bcs bc_n
bc_iec
-       cmp bad_iec,x
        beq bc_y
        inx
        cpx #7
        bcc -
bc_n    ldx bcx
        clc
        rts
bc_y    ldx bcx
        sec
        rts
bad_iec .text "*?,:=", $22, "/"
bad_uci .text "*?:", $22, "<>|", $5c

; Verbotene Zeichen aus dem Dateinamen entfernen (nach Laufwerkswechsel)
nm_clean
        ldx #0                  ; X = lesen, Y = schreiben
        ldy #0
-       cpx flen
        beq +
        lda fname,x
        sty bcy
        jsr badchr
        ldy bcy
        bcs nc_skip
        sta fname,y
        iny
nc_skip inx
        bne -
+       sty flen
        rts

; Dateinamen in Grossbuchstaben (a-z -> A-Z), fuer Diskette
nm_up   ldx #0
-       cpx flen
        beq +
        lda fname,x
        jsr upcase
        sta fname,x
        inx
        bne -
+       rts

; Dateinamen in Kleinbuchstaben (A-Z -> a-z), fuer UCI
nm_low  ldx #0
-       cpx flen
        beq +
        lda fname,x
        cmp #'A'
        bcc nl_nx
        cmp #'Z'+1
        bcs nl_nx
        ora #$20
        sta fname,x
nl_nx   inx
        bne -
+       rts

; Hoechstlaenge des Namens setzen: UCI 25, Diskette 16
gnsetmax
        lda #16
        ldx device
        bne +
        lda #UNAMEL
+       sta gnmax
        rts

; "Drive n" rechtsbuendig in der Statuszeile anzeigen
; (Drive 8 / Drive 10 / Drive U, endet in Spalte 39)
gn_drv  ldy #0                  ; Text in lbuf zusammensetzen
-       lda m_drv,y
        beq +
        sta lbuf,y
        iny
        bne -
+       lda device
        bne gd_num
        ldx #0                  ; UCI
-       lda m_uci,x
        beq gd_out
        sta lbuf,y
        iny
        inx
        bne -
gd_num  cmp #10
        bcc gd_1
        lda #'1'                ; zweistellig: 10, 11
        sta lbuf,y
        iny
        lda device
        sec
        sbc #10
gd_1    clc
        adc #'0'
        sta lbuf,y
        iny
gd_out  sty llen                ; Startspalte = 40 - Laenge
        sec
        lda #40
        sbc llen
        tay
        ldx #0
-       lda lbuf,x
        stx dx
        jsr a2s
        ldx dx
        ora #$80
        sta STAT,y
        iny
        inx
        cpx llen
        bne -
        rts

; Ist der Name ein Ordnerwechsel?  ".." oder Name mit / am Ende
; Carry gesetzt: ja
isdirnm lda flen
        cmp #2
        bne +
        lda fname
        cmp #'.'
        bne +
        lda fname+1
        cmp #'.'
        beq id_y
+       ldx flen
        lda fname-1,x
        cmp #'/'
        beq id_y
        clc
        rts
id_y    sec
        rts

; ---------------------------------------------------------------------
;  Inhaltsverzeichnis lesen
; ---------------------------------------------------------------------
; Verzeichnis ($) des Laufwerks oeffnen, Ladeadresse ueberlesen
; Carry gesetzt: Fehler (Meldung steht in der Statuszeile)
diropen lda #0
        jsr SETNAM
        jsr open15
        bcs do_err
        lda #2
        ldx device
        ldy #0
        jsr SETLFS
        lda #1
        ldx #<m_dollar
        ldy #>m_dollar
        jsr SETNAM
        jsr OPEN
        jsr drvstat             ; Laufwerk bereit?
        lda msgbuf
        cmp #'0'
        bne do_bad
        lda msgbuf+1
        cmp #'0'
        bne do_bad
        lda #0
        sta deof
        ldx #2
        jsr CHKIN
        bcc +
        jmp do_bad              ; Laufwerk antwortet nicht
+       jsr dgetb               ; Ladeadresse (2 Bytes)
        jsr dgetb
        clc
        rts
do_bad  jsr closeall
        jsr stclear
        jsr showdrv
        sec
        rts
do_err  jsr CLALL
        jsr stclear
        #msg m_dev
        lda #1
        sta statshow
        sec
        rts

; Ein Byte des Verzeichnisses lesen (nach dem Ende immer 0)
dgetb   lda deof
        bne db_z
        jsr CHRIN
        pha
        jsr READST
        sta deof                ; nicht 0: das war das letzte Byte
        pla
        rts
db_z    lda #0
        rts

; Eine Zeile des Verzeichnisses lesen
; dnum = Zahl am Zeilenanfang (Bloecke), lbuf/llen = Text der Zeile
; Carry gesetzt: Ende des Verzeichnisses
dline   jsr dgetb               ; Verkettung: 0 0 = Ende
        sta tmp
        jsr dgetb
        ora tmp
        beq dl_end
        jsr dgetb               ; Zahl (Bloecke)
        sta dnum
        jsr dgetb
        sta dnum+1
        ldy #0
dl_lp   jsr dgetb               ; Text bis zur 0
        beq dl_ok
        cpy #40
        bcs dl_lp               ; zu lang: Rest ueberlesen
        sta lbuf,y
        iny
        bne dl_lp
dl_ok   sty llen
        clc
        rts
dl_end  sec
        rts

; Zeile drow2 leeren, sc zeigt danach auf die Zeile
sd_clr  ldy drow2
        lda rowlo,y
        sta sc
        lda rowhi,y
        sta sc+1
        ldy #39
        lda #$20
-       sta (sc),y
        dey
        bpl -
        rts

; Zeichen aus dem Verzeichnis in Bildschirmcode umwandeln
; (Namen wie in der Dateiabfrage: ohne SHIFT = Grossbuchstaben)
dchr    jsr dchra
        jmp a2s
; dasselbe, Ergebnis als ASCII-Zeichen (X und Y bleiben erhalten)
dchra   cmp #$a0                ; geschuetztes Leerzeichen
        bne +
        lda #$20
+       cmp #$c1                ; mit SHIFT: Kleinbuchstaben
        bcc +
        cmp #$db
        bcs +
        and #$7f
        ora #$20
+       rts

; Kommandokanal 15 des Laufwerks oeffnen
; Vorher SETNAM aufrufen (setzt den Dateinamen)
; Carry gesetzt: Fehler
; Zuerst kurz anrufen (LISTEN/UNLSN): ein fehlendes Laufwerk
; wird so sofort erkannt. Spaeter wuerde CHKIN ewig warten.
open15  lda #0
        sta $90                 ; Status loeschen
        lda device
        jsr LISTEN
        jsr UNLSN
        jsr READST
        and #$80                ; Geraet fehlt?
        bne o15e
        lda #15
        ldx device
        ldy #15
        jsr SETLFS
        jsr OPEN
        bcs o15e
        jsr READST
        bne o15e
        clc
        rts
o15e    sec
        rts

; Meldung des Laufwerks lesen und in msgbuf ablegen
; (endet mit 0).  Antwortet das Laufwerk nicht, steht dort
; "Drive not ready!" (sonst wuerde CHRIN auf die Tastatur warten)
drvstat ldx #15
        jsr CHKIN
        bcc +
        jmp nodrive
+       ldy #0
-       jsr CHRIN
        cmp #$0d
        beq +
        sta msgbuf,y
        iny
        cpy #38
        bcc -
+       lda #0
        sta msgbuf,y
        jmp CLRCHN

; Laufwerk antwortet nicht: Eingabe zuruecksetzen, Meldung ablegen
nodrive jsr CLRCHN
        ldx #0
-       lda m_dev+1,x
        sta msgbuf,x
        beq +
        inx
        bne -
+       rts

showdrv ldy #0
-       lda msgbuf,y
        beq +
        jsr stputc
        iny
        bne -
+       lda #1
        sta statshow
        rts

closeall
        lda #2
        jsr CLOSE
        lda #15
        jsr CLOSE
        jmp CLRCHN

; ---------------------------------------------------------------------
;  UCI-Schnittstelle: eigene Datei
; ---------------------------------------------------------------------
        .include "fb_uci.asm"

; Hat fname eine gesperrte Endung (Liste xblock)?  Carry gesetzt: ja
extchk  lda #<fname
        sta r
        lda #>fname
        sta r+1
        lda flen
        sta xlen
; dasselbe fuer den Namen bei r (Laenge xlen)
extchkp ldy xlen                ; letzten Punkt suchen
-       dey
        bmi ec_no               ; kein Punkt: erlaubt
        lda (r),y
        cmp #'.'
        bne -
        iny
        sty gpi                 ; Anfang der Endung
        ldx #0
ec_ent  ldy gpi                 ; einen Eintrag der Liste vergleichen
ec_cmp  lda xblock,x
        beq ec_end
        cmp #' '
        beq ec_end
        cpy xlen
        bcs ec_skip             ; Endung kuerzer
        sta ubt
        lda (r),y
        jsr upcase
        cmp ubt
        bne ec_skip
        iny
        inx
        bne ec_cmp
ec_end  cpy xlen                ; Eintrag zu Ende: Endung auch?
        beq ec_yes
ec_skip lda xblock,x            ; Rest des Eintrags ueberspringen
        beq ec_no
        inx
        cmp #' '
        bne ec_skip
        beq ec_ent
ec_yes  sec
        rts
ec_no   clc
        rts

; ---------------------------------------------------------------------
;  Texte
; ---------------------------------------------------------------------
m_pgb   .null "F4 PgUp  F6 PgDn  F7 Help  "
m_hlpt  .null "HELP:"
HC      = 16                    ; Hilfe: Spalte der Erklaerungen
m_hlp   .byte 0
        .null "CRSR UP/DOWN", HC, "select"
        .null "F4 / F6", HC, "page up / down"
        .null "HOME", HC, "first entry"
        .null "RETURN", HC, "open folder / drive,"
        .null HC, "LOAD: load file"
        .null HC, "SAVE: take name,"
        .null HC, "RETURN again saves"
        .null "..", HC, "one level up"
        .null "Type a name", HC, "then RETURN uses it"
        .null "* ?", HC, "wildcards (LOAD)"
        .null "STOP", HC, "cancel"
        .byte 0
        .null "Any key: back to the list"
        .byte $ff
m_dev   .null " Drive not ready!"
m_drv   .null "Drive "
m_uci   .null "U"
m_drvs  .null "DRIVES:"
m_bfree .null " BLKS FREE"
m_dollar .null "$"
m_uhome .null "/"                  ; Startordner fuer UCI
m_uto   .null "UCI: no response"
m_unact .null "UCI inactive (please check $DF00-$DFFF)"
m_uok   .null "00,OK"
xblock  #BLOCKED                ; gesperrte Endungen (Option oben)
        .byte 0

; ---------------------------------------------------------------------
;  Variablen
; ---------------------------------------------------------------------
fb_vdef .segment
fb_vstart
device  .byte 0                 ; Laufwerk: 0 = UCI, 8-11
statshow .byte 0
stcol   .byte 0
tmp     .byte 0
gnp     .word 0
flen    .byte 0
numbuf  .fill 5, 0
fname   .fill 26, 0
deof    .byte 0
dnum    .word 0
llen    .byte 0
drow2   .byte 0
dx      .byte 0
dfree   .word 0
dok     .byte 0
gnmax   .byte 0
ucion   .byte 0
ucl     .word 0
ubt     .byte 0
ucbv    .word 0
ustl    .byte 0
url     .word 0
uto     .fill 3, 0
uwhere  .byte 0
ust     .byte 0
gnold   .byte 0
bcx     .byte 0
bcy     .byte 0
gload   .byte 0
gpi     .byte 0
cdlen   .byte 0
cdpos   .byte 0
cblen   .byte 0
cdfnd   .byte 0
ustreg  .byte 0
blevel  .byte 0                 ; Browser: 0 = Laufwerksauswahl, 1 = Laufwerk
bvalid  .byte 0                 ; 1 = Liste ist gelesen
bsel    .byte 0                 ; Eintrag unter dem Zeiger
btop    .byte 0                 ; erster sichtbarer Eintrag
bcount  .byte 0                 ; Anzahl der Eintraege
bmoved  .byte 0                 ; 1 = zuletzt den Zeiger bewegt
broot   .byte 0                 ; 1 = UCI im Stammordner
bdisk   .byte 0                 ; 1 = Liste einer Diskette
bidx    .byte 0
bfind   .byte 0                 ; Laenge von bfrom (0 = nichts suchen)
bfend   .byte 0
bfrom   .fill UNAMEL, 0         ; Ordner, aus dem man mit .. kommt
bcols   .byte 0                 ; 1 = Zeilen im Browser gefaerbt
xlen    .byte 0
btlen   .byte 0
lbuf    .fill 40, 0
cbuf    .fill 26, 0
rbuf    .fill 26, 0
msgbuf  .fill 40, 0
btit    .fill 40, 0             ; Titel (Diskettenname oder Pfad)
brec    .fill BRECL, 0          ; ein Eintrag: Art, Bloecke/Laufwerk,
bkmem   .byte 0
fb_vend
        .endsegment
        .if FB_VARS == 0
        #fb_vdef
        .else
        .virtual FB_VARS
        #fb_vdef
        .endv
        .endif
fb_vsize = fb_vend - fb_vstart
