#!/usr/bin/env wish
# demo-docirblock.tcl -- die ganze Kette an einem Etikett
#
#   Layout (Blöcke in mm)  +  Inhalt (DocIR je Block)
#        -> docir::block::pdf  ->  PDF  ->  pdfium  ->  PNG  ->  lp
#
## Aus dem docir-Repo heraus starten:
##     wish demo/demo-docirblock.tcl
## Pfade kommen aus ../lib/repos-path.tcl -- wie bei den anderen Demos.
## Zusaetzlich noetig, weil sie nicht zum docir-Baum gehoeren:
##     export LD_LIBRARY_PATH=/pfad/tclpdfium/vendor/pdfium-linux-x64/lib
##     export TCLLIBPATH="/pfad/tclpdfium /pfad/pdf4tcl/pkg"
## Braucht Tk (pdfium::render schreibt in ein Tk-Photo) -- also wish, nicht tclsh.

package require Tk
wm withdraw .
fconfigure stdout -encoding utf-8
package require Tcl 8.6-
source [file join [file dirname [file normalize [info script]]] .. lib repos-path.tcl]
package require docir::block
package require pdfiumtcl

# --- Was der Layouter liefert: Geometrie je Block, in Millimetern ----------
# Genau die Struktur aus tclutils::tulayout.
set layout {
    kopf   {x 3  y 3  w 48 h 12 show 1 label "Kopf"}
    text   {x 3  y 16 w 48 h 13 show 1 label "Text"}
    liste  {x 3  y 31 w 30 h 16 show 1 label "Liste"}
    code   {x 35 y 31 w 16 h 8  show 1 label "Code"}
    fuss   {x 3  y 49 w 48 h 5  show 1 label "Fuß"}
}

# --- Was der Editor liefert: Inhalt je Block, als DocIR -------------------
set inhalt [dict create \
    kopf {
        {type heading content {{type text text {Kiste 42}}} meta {level 2}}
    } \
    text {
        {type paragraph content {
            {type text text {Lager }}
            {type strong text {Nord}}
            {type text text { / Regal }}
            {type emphasis text {7}}
            {type text text { — Kleinteile, sortiert}}} meta {}}
    } \
    liste {
        {type list content {
            {type listItem content {{type text text {Schrauben M4}}} meta {kind ul}}
            {type listItem content {{type text text {Unterlegscheiben}}} meta {kind ul}}
        } meta {kind ul}}
    } \
    code {
        {type pre content {{type text text {ABC-9931-X}}} meta {kind code}}
    } \
    fuss {
        {type paragraph content {{type text text {2026-07-23}}} meta {}}
    }]

# --- Zusammensetzen -------------------------------------------------------
set BREITE 54.0
set HOEHE  56.0

set pdf [pdf4tcl::new %AUTO% -paper [list ${BREITE}m ${HOEHE}m]]
$pdf startPage

puts [format "%-8s %-22s %8s %6s %5s" Block Rechteck genutzt Zeilen Überl.]
foreach {id blk} $layout {
    if {![dict get $blk show]} continue
    if {![dict exists $inhalt $id]} continue
    set opts [list \
        -x [dict get $blk x] -y [dict get $blk y] \
        -w [dict get $blk w] -h [dict get $blk h] \
        -size 8]
    # Code-Block rechtsbündig, sonst links
    if {$id eq "code"} { lappend opts -align right -size 7 }
    if {$id eq "fuss"} { lappend opts -size 6 }
    set r [docir::block::pdf $pdf [dict get $inhalt $id] {*}$opts]
    puts [format "%-8s %-22s %8s %6s %5s" $id \
        "[dict get $blk x],[dict get $blk y] [dict get $blk w]x[dict get $blk h]mm" \
        [dict get $r used] [dict get $r lines] \
        [expr {[dict get $r overflow] ? "JA" : "nein"}]]
}

$pdf write -file /tmp/demo-etikett.pdf
$pdf destroy
puts "\nPDF: /tmp/demo-etikett.pdf"

# --- Rastern wie beim Druck ----------------------------------------------
set doc [pdfium::open /tmp/demo-etikett.pdf]
puts "Seite: [pdfium::pagesize $doc 0] mm"
pdfium::render $doc 0 -width 590 -imagename etikett   ;# 54 mm Band
etikett write /tmp/demo-etikett.png -format png
pdfium::close $doc
puts "PNG: [image width etikett] x [image height etikett] px -> /tmp/demo-etikett.png"
# Druckername nicht raten: aus CUPS holen. Vorgeschlagen wird ein Gerät
# mit "ql" oder "brother" im Namen -- so macht es auch der QL-Knopf in
# viewer2.tcl. Findet sich keines, bleibt ein sichtbarer Platzhalter stehen.
set drucker "<drucker>"
if {![catch {exec lpstat -a} _out]} {
    set alle {}
    foreach zeile [split $_out \n] {
        set n [lindex [split $zeile] 0]
        if {$n ne ""} { lappend alle $n }
    }
    set ql [lsort -unique [concat \
        [lsearch -inline -all -nocase $alle "*ql*"] \
        [lsearch -inline -all -nocase $alle "*brother*"]]]
    if {[llength $ql]} {
        set drucker [lindex $ql 0]
        if {[llength $ql] > 1} {
            puts "\nQL-Drucker gefunden: [join $ql {, }]"
            puts "(unten der erste -- bei mehreren selbst waehlen)"
        }
    } elseif {[llength $alle]} {
        puts "\nKein QL in CUPS. Vorhanden: [join $alle {, }]"
    }
}
puts "\nDrucken:  lp -d $drucker -o PageSize=Custom.54x56.0mm \\"
puts "             -o MediaType=Roll -o CutMedia=EndOfPage /tmp/demo-etikett.png"
exit 0
