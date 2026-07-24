#!/usr/bin/env wish
# etikett-editor.tcl -- Etiketten setzen: Blöcke schieben, Inhalt schreiben,
# drucken.
#
#   Geometrie   tclutils::tulayout / tkutils::tkulayoutcanvas   (mm)
#   Inhalt      Markdown -> mdstack::parser -> docir::md::fromAst
#   Satz        docir::block::pdf                                (mm)
#   Ausgabe     pdf4tcl -> pdfium -> PNG -> lp
#
# Es gibt bewusst kein eigenes Inhaltsformat: der Blocktext ist Markdown,
# und daraus wird DocIR. Damit erbt der Editor fett/kursiv/Code/Listen,
# ohne dass hier ein Parser entsteht, den niemand pflegt.
#
## Start (aus dem docir-Repo, damit repos-path.tcl greift):
##     export LD_LIBRARY_PATH=/pfad/tclpdfium/vendor/pdfium-linux-x64/lib
##     export TCLLIBPATH="/pfad/tclpdfium /pfad/pdf4tcl/pkg /pfad/tclutils/lib/tm"
##     wish etikett-editor.tcl ?datei.etikett?
##
## tkutils/tclutils müssen auf dem tm-Pfad liegen; tulayout muss den Patch
## für freie Papierformate haben, sonst kennt es nur a4/letter/a5.

set VERSION 0.1

package require Tk
fconfigure stdout -encoding utf-8

# --- Abhängigkeiten, mit brauchbarer Meldung -----------------------------
proc fehlerFenster {titel text} {
    catch {
        set fh [open /tmp/etikett-editor.log a]
        puts $fh "--- [clock format [clock seconds]]\n$text" ; close $fh
    }
    catch {destroy .err}
    toplevel .err ; wm title .err $titel
    text .err.t -width 86 -height 16 -wrap word
    pack .err.t -fill both -expand 1 -padx 8 -pady 8
    .err.t insert 1.0 $text ; .err.t tag add sel 1.0 end
    frame .err.b ; pack .err.b -fill x -padx 8 -pady {0 8}
    button .err.b.c -text "In Zwischenablage" -command \
        {clipboard clear; clipboard append [.err.t get 1.0 end-1c]}
    button .err.b.x -text "Schließen" -command {destroy .err}
    pack .err.b.c -side left ; pack .err.b.x -side right
}
proc bgerror {msg} { fehlerFenster "Fehler" "$msg\n\n$::errorInfo" }

set fehlt {}
foreach p {docir::block mdstack::parser docir::mdSource pdfiumtcl
           tkutils::tkulayoutcanvas tclutils::tulayout} {
    if {[catch {package require $p} e]} { lappend fehlt "$p:\n    $e" }
}
if {[llength $fehlt]} {
    wm withdraw .
    fehlerFenster "Pakete fehlen" \
        "Der Editor kann nicht starten.\n\n[join $fehlt \n\n]\n\n\
tm-Pfade:\n  [join [::tcl::tm::path list] \n  ]\n\n\
TCLLIBPATH: [expr {[info exists ::env(TCLLIBPATH)] ? $::env(TCLLIBPATH) : {(leer)}}]\n\
LD_LIBRARY_PATH: [expr {[info exists ::env(LD_LIBRARY_PATH)] ? $::env(LD_LIBRARY_PATH) : {(leer)}}]"
    vwait ewig
}

# --- Zustand --------------------------------------------------------------
# Bandbreite -> Druckbreite in Pixeln bei 300 dpi (brother_ql info labels).
# Kleiner als das Band: 54 mm druckt 590 px = 49,95 mm.
set BANDPX {12 106  29 306  38 413  50 554  54 590  62 696  102 1164}

array set E {
    band     54
    laenge   40
    datei    ""
    dirty    0
    drucker  ""
}
# Inhalt und Stil je Block. Geometrie hält das Layout-Widget selbst.
array set INHALT {}
array set STIL   {}

set E(blocks) {
    kopf  {x 3 y 3  w 48 h 10 show 1 label "Kopf"}
    text  {x 3 y 15 w 48 h 14 show 1 label "Text"}
    fuss  {x 3 y 31 w 48 h 6  show 1 label "Fuss"}
}
set INHALT(kopf) "# Kiste 42"
set INHALT(text) "Lager **Nord** / Regal *7*"
set INHALT(fuss) "`ABC-9931-X`"
foreach id {kopf text fuss} { set STIL($id) {size 8 align left} }

proc breitePx {mm} {
    global BANDPX
    expr {[dict exists $BANDPX $mm] ? [dict get $BANDPX $mm]
                                    : int($mm/25.4*300+0.5)}
}

# --- Markdown -> DocIR ----------------------------------------------------
proc irVon {md} {
    if {[string trim $md] eq ""} { return {} }
    return [docir::md::fromAst [mdstack::parser::parse $md]]
}

# --- Etikett setzen -------------------------------------------------------
# Liefert {pdfdatei} oder wirft. Blöcke ohne show werden übersprungen.
proc etikettPdf {datei} {
    global E INHALT STIL
    set blocks [::tkutils::tkulayoutcanvas::getBlocks .lc]
    set pdf [pdf4tcl::new %AUTO% -paper [list $E(band)m $E(laenge)m]]
    $pdf startPage
    set warnungen {}
    foreach {id b} $blocks {
        if {![dict get $b show]} continue
        if {![info exists INHALT($id)]} continue
        set st [expr {[info exists STIL($id)] ? $STIL($id) : {size 8 align left}}]
        set r [docir::block::pdf $pdf [irVon $INHALT($id)] \
                   -x [dict get $b x] -y [dict get $b y] \
                   -w [dict get $b w] -h [dict get $b h] \
                   -size [dict get $st size] -align [dict get $st align]]
        if {[dict get $r overflow]} {
            lappend warnungen "$id: [dict get $r truncated] Zeile(n) abgeschnitten"
        }
    }
    $pdf write -file $datei
    $pdf destroy
    return $warnungen
}

# --- Vorschau -------------------------------------------------------------
proc vorschau {} {
    global E
    if {[catch {set warn [etikettPdf /tmp/etikett-editor.pdf]} e]} {
        .st configure -text "Satz: $e" -foreground #a33 ; return
    }
    set wpx [breitePx $E(band)]
    if {[catch {
        set d [pdfium::open /tmp/etikett-editor.pdf]
        pdfium::render $d 0 -width $wpx -imagename ::seite
        pdfium::close $d
    } e]} { .st configure -text "Rastern: $e" -foreground #a33 ; return }
    set iw [image width ::seite] ; set ih [image height ::seite]
    set teiler [expr {int(ceil($ih/380.0))}]
    if {$teiler < 1} { set teiler 1 }
    ::gezeigt blank
    ::gezeigt copy ::seite -subsample $teiler $teiler
    .rechts.vs configure -image ::gezeigt
    set txt "$E(band) x $E(laenge) mm   ${iw}x${ih} px"
    if {[llength $warn]} {
        .st configure -text "$txt   ACHTUNG: [join $warn {; }]" -foreground #a60
    } else {
        .st configure -text $txt -foreground #333
    }
}

# --- Drucken --------------------------------------------------------------
proc drucke {{trocken 0}} {
    global E
    if {$E(drucker) eq ""} {
        .st configure -text "Kein Drucker gewählt." -foreground #a33 ; return
    }
    if {[catch {set warn [etikettPdf /tmp/etikett-druck.pdf]} e]} {
        fehlerFenster "Satz fehlgeschlagen" "$e\n\n$::errorInfo" ; return
    }
    set wpx [breitePx $E(band)]
    set png /tmp/etikett-druck.png
    if {[catch {
        set d [pdfium::open /tmp/etikett-druck.pdf]
        pdfium::render $d 0 -width $wpx -imagename ::druck
        pdfium::close $d
        ::druck write $png -format png
    } e]} { fehlerFenster "Rastern fehlgeschlagen" "$e\n\n$::errorInfo" ; return }

    # Länge aus Seitenverhältnis und Bandbreite -- nicht aus 300 dpi.
    # Die gerenderte Breite ist die Druckbreite (49,95 mm bei Band 54),
    # gemeldet wird aber das Band; wer da zwei Maßstäbe mischt, bekommt
    # zu kurze Etiketten und bei 600 dpi doppelt so lange.
    set iw [image width ::druck] ; set ih [image height ::druck]
    set hmm [format %.1f [expr {double($ih)/$iw*$E(band)}]]
    set cmd [list lp -d $E(drucker) \
                 -o "PageSize=Custom.$E(band)x${hmm}mm" \
                 -o MediaType=Roll -o CutMedia=EndOfPage $png]
    if {$trocken} {
        fehlerFenster "Testlauf -- nicht gedruckt" \
            "[join $cmd { }]\n\nBild: $png ($iw x $ih px)\nSeite: $E(band) x $hmm mm"
        return
    }
    if {[catch {exec {*}$cmd 2>@1} out]} {
        fehlerFenster "Druckfehler" \
            "$out\n\nBefehl:\n[join $cmd { }]\n\n\
Weiter:\n  lpstat -p $E(drucker) -l\n  tail -30 /var/log/cups/error_log"
    } else {
        .st configure -text "Gesendet an $E(drucker): $E(band) x $hmm mm" \
            -foreground #185
    }
}

# --- Speichern und Laden --------------------------------------------------
# Als Dict-Literal. Beim Lesen wird NICHT ausgewertet -- die Datei ist
# Daten, kein Skript, und `dict get` braucht keinen Interpreter.
proc speichern {{datei ""}} {
    global E INHALT STIL VERSION
    if {$datei eq ""} {
        set datei [tk_getSaveFile -defaultextension .etikett \
            -filetypes {{Etikett {.etikett}} {Alle *}}]
        if {$datei eq ""} return
    }
    set inh {} ; set stl {}
    foreach k [array names INHALT] { dict set inh $k $INHALT($k) }
    foreach k [array names STIL]   { dict set stl $k $STIL($k) }
    set d [dict create \
        version $VERSION \
        band    $E(band) \
        laenge  $E(laenge) \
        blocks  [::tkutils::tkulayoutcanvas::getBlocks .lc] \
        inhalt  $inh \
        stil    $stl]
    set fh [open $datei w] ; fconfigure $fh -encoding utf-8
    puts $fh "# etikett-editor $VERSION -- Daten, kein Skript"
    puts $fh $d
    close $fh
    set E(datei) $datei ; set E(dirty) 0
    .st configure -text "Gespeichert: $datei" -foreground #185
}

proc laden {{datei ""}} {
    global E INHALT STIL
    if {$datei eq ""} {
        set datei [tk_getOpenFile -filetypes {{Etikett {.etikett}} {Alle *}}]
        if {$datei eq ""} return
    }
    set fh [open $datei] ; fconfigure $fh -encoding utf-8
    set roh [read $fh] ; close $fh
    set d {}
    foreach zeile [split $roh \n] {
        if {[string match "#*" [string trim $zeile]]} continue
        if {[string trim $zeile] eq ""} continue
        append d $zeile "\n"
    }
    set d [string trim $d]
    # Prüfen statt vertrauen: eine kaputte Datei soll hier scheitern,
    # nicht erst beim Satz.
    if {[catch {dict size $d} e]} {
        fehlerFenster "Datei unlesbar" "$datei ist kein gültiges Dict:\n$e" ; return
    }
    foreach k {band laenge blocks inhalt stil} {
        if {![dict exists $d $k]} {
            fehlerFenster "Datei unvollständig" "Schlüssel '$k' fehlt in $datei" ; return
        }
    }
    set E(band)   [dict get $d band]
    set E(laenge) [dict get $d laenge]
    array unset INHALT ; array unset STIL
    foreach {k v} [dict get $d inhalt] { set INHALT($k) $v }
    foreach {k v} [dict get $d stil]   { set STIL($k)   $v }
    ::tkutils::tkulayoutcanvas::configure .lc \
        -paper [list $E(band) $E(laenge)] -blocks [dict get $d blocks]
    set E(datei) $datei ; set E(dirty) 0
    blockListeFuellen
    vorschau
    .st configure -text "Geladen: $datei" -foreground #185
}

# --- Blockverwaltung ------------------------------------------------------
# Die Auswahl hält das Layout-Widget in einer internen Variablen; es gibt
# dafür keinen öffentlichen Getter. Bewusste Kopplung -- wenn tkutils das
# ändert, bricht genau diese Zeile.
proc gewaehlt {} {
    if {[info exists ::tkutils::tkulayoutcanvas::state(.lc,sel)]} {
        return $::tkutils::tkulayoutcanvas::state(.lc,sel)
    }
    return ""
}

proc blockListeFuellen {} {
    set blocks [::tkutils::tkulayoutcanvas::getBlocks .lc]
    .rechts.liste delete 0 end
    foreach {id b} $blocks { .rechts.liste insert end $id }
}

proc blockZeigen {id} {
    global INHALT STIL akt
    if {$id eq ""} return
    set akt $id
    .rechts.txt delete 1.0 end
    if {[info exists INHALT($id)]} { .rechts.txt insert 1.0 $INHALT($id) }
    set st [expr {[info exists STIL($id)] ? $STIL($id) : {size 8 align left}}]
    set ::uiSize  [dict get $st size]
    set ::uiAlign [dict get $st align]
    .rechts.kopf configure -text "Block: $id"
}

proc blockSichern {} {
    global INHALT STIL akt E
    if {![info exists akt] || $akt eq ""} return
    set INHALT($akt) [string trimright [.rechts.txt get 1.0 end] \n]
    set STIL($akt) [dict create size $::uiSize align $::uiAlign]
    set E(dirty) 1
}

proc blockNeu {} {
    global INHALT STIL E
    set n 1
    set blocks [::tkutils::tkulayoutcanvas::getBlocks .lc]
    while {[dict exists $blocks "block$n"]} { incr n }
    set id "block$n"
    dict set blocks $id [dict create x 3 y 3 w [expr {$E(band)-6}] h 8 \
                             show 1 label $id]
    ::tkutils::tkulayoutcanvas::setBlocks .lc $blocks
    set INHALT($id) "neuer Text"
    set STIL($id) {size 8 align left}
    blockListeFuellen
    ::tkutils::tkulayoutcanvas::select .lc $id
    blockZeigen $id
    vorschau
}

proc blockWeg {} {
    global INHALT STIL akt
    set id [gewaehlt]
    if {$id eq ""} { set id [expr {[info exists akt] ? $akt : ""}] }
    if {$id eq ""} { .st configure -text "Kein Block gewählt." -foreground #a33 ; return }
    set blocks [::tkutils::tkulayoutcanvas::getBlocks .lc]
    dict unset blocks $id
    ::tkutils::tkulayoutcanvas::setBlocks .lc $blocks
    array unset INHALT $id ; array unset STIL $id
    set akt ""
    .rechts.txt delete 1.0 end
    .rechts.kopf configure -text "Block: --"
    blockListeFuellen
    vorschau
}

proc bandGeaendert {args} {
    global E
    ::tkutils::tkulayoutcanvas::configure .lc -paper [list $E(band) $E(laenge)]
    vorschau
}

proc druckerSuchen {} {
    global E
    set alle {}
    if {![catch {exec lpstat -a} out]} {
        foreach z [split $out \n] {
            set n [lindex [split $z] 0]
            if {$n ne ""} { lappend alle $n }
        }
    }
    .top2.d configure -values $alle
    if {$E(drucker) eq "" && [llength $alle]} {
        set ql [lsort -unique [concat \
            [lsearch -inline -all -nocase $alle "*ql*"] \
            [lsearch -inline -all -nocase $alle "*brother*"]]]
        set E(drucker) [expr {[llength $ql] ? [lindex $ql 0] : [lindex $alle 0]}]
    }
}

# --- Oberfläche -----------------------------------------------------------
wm title . "Etikett-Editor $VERSION"
wm minsize . 1000 600

frame .top -padx 6 -pady 4
pack .top -fill x
label .top.l1 -text "Band:"
ttk::combobox .top.band -width 5 -state readonly \
    -values [dict keys $BANDPX] -textvariable E(band)
label .top.l2 -text "mm   Länge:"
ttk::spinbox .top.len -width 5 -from 10 -to 300 -textvariable E(laenge)
label .top.l3 -text "mm"
pack .top.l1 .top.band .top.l2 .top.len .top.l3 -side left -padx 2

frame .top2 -padx 6
pack .top2 -fill x
label .top2.l -text "Drucker:"
ttk::combobox .top2.d -width 26 -state readonly -textvariable E(drucker)
button .top2.r -text "suchen" -command druckerSuchen
pack .top2.l .top2.d .top2.r -side left -padx 2

panedwindow .pw -orient horizontal -sashwidth 6
pack .pw -fill both -expand 1 -padx 6 -pady 6

::tkutils::tkulayoutcanvas::widget .lc \
    -paper [list $E(band) $E(laenge)] -margin 4 -gridmm 1 \
    -blocks $E(blocks) -width 420 -height 460 \
    -onchange {apply {{p blocks} { vorschau }}}
.pw add .lc

frame .rechts
.pw add .rechts
label .rechts.kopf -text "Block: --" -anchor w -font {TkDefaultFont 10 bold}
pack .rechts.kopf -fill x
listbox .rechts.liste -height 5 -exportselection 0
pack .rechts.liste -fill x -pady 2
frame .rechts.bb
pack .rechts.bb -fill x
button .rechts.bb.neu -text "+ Block" -command blockNeu
button .rechts.bb.weg -text "- Block" -command blockWeg
pack .rechts.bb.neu .rechts.bb.weg -side left -padx {0 4}

frame .rechts.stil -pady 4
pack .rechts.stil -fill x
label .rechts.stil.l1 -text "pt:"
ttk::spinbox .rechts.stil.size -width 4 -from 4 -to 40 -textvariable uiSize
label .rechts.stil.l2 -text "Ausrichtung:"
ttk::combobox .rechts.stil.al -width 8 -state readonly \
    -values {left center right} -textvariable uiAlign
pack .rechts.stil.l1 .rechts.stil.size .rechts.stil.l2 .rechts.stil.al \
     -side left -padx 2

label .rechts.mdl -text "Inhalt (Markdown: **fett** *kursiv* `code` # Titel)" \
      -anchor w -foreground #666
pack .rechts.mdl -fill x
text .rechts.txt -height 7 -wrap word -relief solid -borderwidth 1 -undo 1
pack .rechts.txt -fill x -pady 2

label .rechts.vs -relief solid -borderwidth 1 -background white -anchor nw
pack .rechts.vs -fill both -expand 1 -pady 4

frame .b -padx 6 -pady 4
pack .b -fill x
button .b.v -text "Vorschau" -command {blockSichern; vorschau}
button .b.p -text "Drucken" -command {blockSichern; drucke 0}
button .b.t -text "Testlauf" -command {blockSichern; drucke 1}
button .b.s -text "Speichern" -command {blockSichern; speichern}
button .b.l -text "Laden" -command laden
pack .b.v .b.p .b.t .b.s .b.l -side left -padx {0 4}

label .st -anchor w -padx 6
pack .st -fill x -pady {0 4}

image create photo ::seite
image create photo ::gezeigt
set uiSize 8
set uiAlign left

bind .rechts.liste <<ListboxSelect>> {
    blockSichern
    set _i [.rechts.liste curselection]
    if {$_i ne ""} {
        set _id [.rechts.liste get $_i]
        ::tkutils::tkulayoutcanvas::select .lc $_id
        blockZeigen $_id
    }
}
# Klick im Layout: die Auswahl des Widgets übernehmen.
bind [::tkutils::tkulayoutcanvas::getCanvas .lc] <ButtonRelease-1> {
    after 20 {
        set _s [gewaehlt]
        if {$_s ne "" && (![info exists akt] || $_s ne $akt)} {
            blockSichern ; blockZeigen $_s
        }
    }
}
trace add variable E(band)   write bandGeaendert
trace add variable E(laenge) write bandGeaendert
bind . <Control-s> {blockSichern; speichern $E(datei)}
bind . <Control-p> {blockSichern; drucke 0}

druckerSuchen
blockListeFuellen
blockZeigen kopf
vorschau

if {[llength $argv] > 0} { laden [lindex $argv 0] }
