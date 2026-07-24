#!/usr/bin/env tclsh
# demo-docirblock.tcl -- Test- und Diagnose-Etikett
#
#   Layout (Blöcke in mm)  +  DocIR je Block
#        -> docir::block::pdf  ->  PDF  ->  pdfium  ->  PNG  ->  lp
#
# Das erzeugte Etikett beschreibt sich selbst: Band, Maße, Auflösung,
# Drucker, Zeit -- und trägt einen gedruckten MASSSTAB. Damit lässt sich
# am Ausdruck mit einem Lineal prüfen, ob die Größe stimmt. Das ist der
# einzige verlässliche Test: Zahlen im Protokoll sagen nichts darüber,
# was der Treiber am Ende skaliert.
#
## Aus dem docir-Repo heraus starten:
##     tclsh demo/demo-docirblock.tcl ?band_mm? ?laenge_mm?
## Pfade kommen aus ../lib/repos-path.tcl -- wie bei den anderen Demos.
## Zusätzlich nötig, weil sie nicht zum docir-Baum gehören:
##     export LD_LIBRARY_PATH=/pfad/tclpdfium/vendor/pdfium-linux-x64/lib
##     export TCLLIBPATH="/pfad/tclpdfium /pfad/pdf4tcl/pkg"
## Tk wird geladen (pdfium::render schreibt in ein Tk-Photo); ein Bildschirm
## muss also erreichbar sein. Das abschließende `exit` ist Pflicht, sonst
## hängt der Prozess in Tks Hauptschleife.

package require Tk
wm withdraw .
fconfigure stdout -encoding utf-8
package require Tcl 8.6-
source [file join [file dirname [file normalize [info script]]] .. lib repos-path.tcl]
package require docir::block
package require pdfiumtcl

# Version des Demos. Steht mit auf dem Etikett -- damit ist an einem
# Ausdruck ablesbar, welche Fassung ihn erzeugt hat. Bei jeder Änderung
# an Größen oder Aufbau hochzählen.
set DEMOVERSION "0.3"

# --- Parameter ------------------------------------------------------------
# 54 mm ist ein Beispiel und passt zum verbreiteten DK-N55224-Endlosband.
# Anderes Band als Argument: tclsh demo-docirblock.tcl 62 80
set BAND   [expr {[llength $argv] > 0 ? [lindex $argv 0] : 54}]
set LAENGE 60      ;# vorlaeufig, wird nach dem Messlauf gesetzt

# Druckbreite in Pixeln bei 300 dpi -- aus `brother_ql info labels`.
# WICHTIG: kleiner als das Band. 54 mm Band druckt 590 px = 49,95 mm.
set BANDPX {12 106  29 306  38 413  50 554  54 590  62 696  102 1164}
set wpx [expr {[dict exists $BANDPX $BAND] ? [dict get $BANDPX $BAND]
                                           : int($BAND/25.4*300+0.5)}]

set MM 2.8346456692913385      ;# mm -> pt

# Kleinste Schriftgröße. Bei 300 dpi ist ein Kleinbuchstabe rund 0,52 x der
# Punktgröße hoch, also bei 6 pt nur ~13 Pixel -- und der Thermokopf
# verbreitert jeden Punkt zusätzlich, wodurch dünne Striche zulaufen.
# In der Praxis erwies sich das als zu klein; 8 pt ist die Untergrenze.
# Endlosband ist billig, Augen sind es nicht: lieber länger als kleiner.
set MINPT 8

# --- Drucker aus CUPS, nicht geraten -------------------------------------
set drucker "<drucker>"
set alleDrucker {}
if {![catch {exec lpstat -a} _out]} {
    foreach zeile [split $_out \n] {
        set n [lindex [split $zeile] 0]
        if {$n ne ""} { lappend alleDrucker $n }
    }
    set ql [lsort -unique [concat \
        [lsearch -inline -all -nocase $alleDrucker "*ql*"] \
        [lsearch -inline -all -nocase $alleDrucker "*brother*"]]]
    if {[llength $ql]} { set drucker [lindex $ql 0] }
}

# --- Hilfsprozeduren für DocIR -------------------------------------------
proc titel {t} {
    list [dict create type heading \
        content [list [dict create type text text $t]] meta {level 2}]
}
proc kv {k v} {
    list [dict create type paragraph content [list \
        [dict create type strong text "$k "] \
        [dict create type text   text $v]] meta {}]
}
proc mono {t} {
    list [dict create type pre \
        content [list [dict create type text text $t]] meta {kind code}]
}

# --- Maßstab: das eigentliche Prüfmittel ---------------------------------
# Millimeterstriche zum Nachmessen. Wer hier eine Abweichung findet,
# weiß, dass der Treiber skaliert -- und keine Zahl im Protokoll hätte
# das verraten.
proc massstab {pdf xmm ymm laengemm} {
    global MM
    set x0 [expr {$xmm*$MM}]
    set y  [expr {$ymm*$MM}]
    $pdf setLineWidth 0.4
    $pdf line $x0 $y [expr {$x0+$laengemm*$MM}] $y
    $pdf setFont 7 Helvetica
    for {set mm 0} {$mm <= $laengemm} {incr mm} {
        set x [expr {$x0 + $mm*$MM}]
        if {$mm % 10 == 0} {
            set h 8.0 ; $pdf setLineWidth 0.4
        } elseif {$mm % 5 == 0} {
            set h 5.0 ; $pdf setLineWidth 0.3
        } else {
            set h 2.5 ; $pdf setLineWidth 0.2
        }
        $pdf line $x $y $x [expr {$y - $h}]
        if {$mm % 10 == 0} {
            $pdf text "$mm" -x [expr {$x-1.5}] -y [expr {$y+4.5}]
        }
    }
}

# --- Etikett bauen --------------------------------------------------------
# Ein Durchgang, zweimal gerufen: erst trocken zum Messen, dann echt.
# So bestimmt der Inhalt die Bandlänge -- wer die Schrift vergrößert, muss
# die Länge nicht von Hand nachziehen. Bei Endlosband kostet Länge nichts.
proc etikettBauen {pdf band laenge drucker wpx trocken} {
    global MM MINPT
    set nutzbar [expr {$band - 6}]           ;# 3 mm Rand links und rechts
    set y 3.0

    set r [docir::block::pdf $pdf [titel "QL-Testetikett"] \
              -x 3 -y $y -w $nutzbar -size 12 -dryrun $trocken]
    set y [expr {$y + [dict get $r used] + 3}]

    # Maßstab quer, so lang wie der nutzbare Bereich
    set skala [expr {int($nutzbar) - 1}]
    if {!$trocken} { massstab $pdf 3 [expr {$y + 3}] $skala }
    set y [expr {$y + 7}]
    set r [docir::block::pdf $pdf \
              [kv "Massstab:" "0-$skala mm, Strich je 1 mm -- nachmessen!"] \
              -x 3 -y $y -w $nutzbar -size $MINPT -dryrun $trocken]
    set y [expr {$y + [dict get $r used] + 2}]

    set effdpi [format %.1f [expr {$wpx / ($band/25.4)}]]
    foreach {k v} [list \
        "Band"      "$band mm" \
        "Seite"     "$band x $laenge mm" \
        "Render"    "$wpx px (Druckbreite)" \
        "das sind"  "[format %.2f [expr {$wpx/300.0*25.4}]] mm bei 300 dpi" \
        "eff. dpi"  "$effdpi auf $band mm" \
        "Drucker"   $drucker \
        "Zeit"      [clock format [clock seconds] -format "%Y-%m-%d %H:%M"] \
        "Demo"      "v$::DEMOVERSION, Schrift ab $MINPT pt" \
    ] {
        set r [docir::block::pdf $pdf [kv "${k}:" $v] \
                  -x 3 -y $y -w $nutzbar -size $MINPT -dryrun $trocken]
        set y [expr {$y + [dict get $r used]}]
    }

    set y [expr {$y + 2}]
    # Nur die Option, die den Maßstab bestimmt -- der vollständige Befehl
    # steht im Terminal und muss nicht aufs Etikett.
    set r [docir::block::pdf $pdf \
        [mono "PageSize=Custom.${band}x${laenge}mm"] \
        -x 3 -y $y -w $nutzbar -size $MINPT -dryrun $trocken]
    set y [expr {$y + [dict get $r used] + 2}]

    set proben {
      {type paragraph content {
          {type text text {Stil: }}
          {type strong text {fett}}
          {type text text { }}
          {type emphasis text {kursiv}}
          {type text text { }}
          {type underline text {untstr}}
          {type text text { }}
          {type strike text {durch}}
          {type text text { }}
          {type code text {mono}}} meta {}}
    }
    set r [docir::block::pdf $pdf $proben \
              -x 3 -y $y -w $nutzbar -size $MINPT -dryrun $trocken]
    set y [expr {$y + [dict get $r used]}]

    if {!$trocken} {
        # Rahmen 1 mm vom Rand: zeigt seitlichen Beschnitt sofort
        $pdf setLineWidth 0.3
        $pdf rectangle [expr {1*$MM}] [expr {1*$MM}] \
                       [expr {($band-2)*$MM}] [expr {($laenge-2)*$MM}]
    }
    return $y
}

# Durchgang 1: messen. Die Seitengröße ist dabei egal, es wird nichts
# gezeichnet -- nur die Blockhöhen summiert.
set probe [pdf4tcl::new %AUTO% -paper [list ${BAND}m 300m]]
$probe startPage
set noetig [etikettBauen $probe $BAND $LAENGE $drucker $wpx 1]
$probe destroy

# Länge aus dem Inhalt, aufgerundet auf ganze Millimeter, plus 3 mm Fuß.
# Ein ausdrücklich mitgegebenes zweites Argument hat Vorrang.
if {[llength $argv] > 1} {
    set LAENGE [lindex $argv 1]
} else {
    set LAENGE [expr {int(ceil($noetig)) + 3}]
}

# Durchgang 2: zeichnen
set pdf [pdf4tcl::new %AUTO% -paper [list ${BAND}m ${LAENGE}m]]
$pdf startPage
etikettBauen $pdf $BAND $LAENGE $drucker $wpx 0
$pdf write -file /tmp/demo-etikett.pdf
$pdf destroy

# --- Rastern wie beim Druck ----------------------------------------------
set doc [pdfium::open /tmp/demo-etikett.pdf]
lassign [pdfium::pagesize $doc 0] pw ph
pdfium::render $doc 0 -width $wpx -imagename etikett
etikett write /tmp/demo-etikett.png -format png
set iw [image width etikett] ; set ih [image height etikett]
pdfium::close $doc

puts [format "Demo      : v%s, Schrift ab %s pt" $DEMOVERSION $MINPT]
puts [format "Band      : %s mm  ->  %s px Druckbreite" $BAND $wpx]
puts [format "PDF-Seite : %.2f x %.2f mm" $pw $ph]
puts [format "PNG       : %d x %d px" $iw $ih]
puts [format "Laenge    : %.1f mm (Seitenverhaeltnis x Band)" \
        [expr {double($ih)/$iw*$BAND}]]
puts "PDF       : /tmp/demo-etikett.pdf"
puts "PNG       : /tmp/demo-etikett.png"
if {[llength $alleDrucker]} { puts "CUPS      : [join $alleDrucker {, }]" }
puts ""
puts "Drucken:"
puts "  lp -d $drucker -o PageSize=Custom.${BAND}x[format %.1f $ph]mm \\"
puts "     -o MediaType=Roll -o CutMedia=EndOfPage /tmp/demo-etikett.png"
puts ""
puts "Danach den gedruckten Massstab mit dem Lineal nachmessen."
puts "Weicht er ab, skaliert der Treiber -- und dann sagt keine Zahl"
puts "aus diesem Protokoll etwas ueber den tatsaechlichen Ausdruck."
exit 0
