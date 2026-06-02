#!/usr/bin/env wish
## odt-view.tcl  --  ODT im Tk-Fenster anzeigen (ODT -> DocIR -> Tk)
##
## Pipeline: docir::odtSource::fromOdt  ->  docir::renderer::tk::render
##
## Nutzung:
##   wish odt-view.tcl ?datei.odt?
##   (ohne Argument: Datei -> Oeffnen, oder Strg+O)
##
## Pfade: source ../lib/repos-path.tcl (findet docir/odf/mdstack als Sibling
## oder unter ~/lib/tcltk) -- dieselbe Bruecke wie docir-view.tcl.

package require Tk

set here [file dirname [file normalize [info script]]]
source -encoding utf-8 [file normalize [file join $here .. lib repos-path.tcl]]

if {[catch {
    package require odf
    package require docir
    package require docir::rendererTk
    package require docir::odtSource
} err]} {
    tk_messageBox -icon error -title "Laden fehlgeschlagen" -message \
        "docir/odf nicht ladbar:\n$err\n\nrepos-path.tcl erwartet odf (und mdstack) als\nSibling-Repo oder installiert unter ~/lib/tcltk/."
    exit 2
}

## Temp-Wurzel fuer extrahierte Bilder (eine pro Sitzung)
set tmproot [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] \
    odtview-[pid]]
file mkdir $tmproot
set mediaSeq 0

## Anzeige-Zustand: Frame- vs. ASCII-Tabellen (Toolbar-Umschalter) und die
## aktuell angezeigte (bild-gemappte) IR, damit Umschalten ohne Neu-Lesen geht.
set useFrameTables 1
set currentIrView {}

## --- UI ---
wm title . "ODT-View"
wm geometry . 900x700

ttk::frame .bar
ttk::button .bar.open -text "Öffnen…" -command openDialog
ttk::checkbutton .bar.frame -text "Frame-Tabellen" \
    -variable ::useFrameTables -command rerender
ttk::label  .bar.file -text "(keine Datei)"
pack .bar.open .bar.frame -side left -padx 4 -pady 4
pack .bar.file -side left -padx 8
pack .bar -side top -fill x

ttk::frame .main
text .main.t -wrap word -relief flat -padx 12 -pady 8 \
    -yscrollcommand {.main.sb set}
ttk::scrollbar .main.sb -orient vertical -command {.main.t yview}
pack .main.sb -side right -fill y
pack .main.t  -side left -fill both -expand 1
pack .main -side top -fill both -expand 1

proc openDialog {} {
    set f [tk_getOpenFile -title "ODT öffnen" \
        -filetypes {{ODT {.odt}} {Alle *}}]
    if {$f ne ""} { openOdt $f }
}

## Container-Teile (z. B. Pictures/…) nach destDir schreiben, via odf::Package.
## Liefert die rohen (dekomprimierten) Bytes pro Teil; nicht vorhandene
## Member werden uebersprungen (no magic -- fehlende zeigen sich oben als
## fehlende lokale Datei).
proc extractParts {path members destDir} {
    set pkg [odf::Package new $path]
    try {
        foreach m $members {
            if {![$pkg has $m]} continue
            set dst [file join $destDir $m]
            file mkdir [file dirname $dst]
            set fh [open $dst wb]
            puts -nonewline $fh [$pkg part $m]
            close $fh
        }
    } finally {
        $pkg destroy
    }
}

## Bild-urls (Pictures/…) extrahieren und in einer IR-Kopie auf die
## entpackten Temp-Pfade umbiegen — nur fuer die Anzeige. Das Original-IR
## (und damit der Export ueber andere Senken) bleibt mit portablen
## Pictures/…-Pfaden unangetastet.
proc remapImages {path ir} {
    set urls {}
    foreach b $ir {
        if {[dict get $b type] eq "image"} { lappend urls [dict get $b meta url] }
    }
    if {[llength $urls] == 0} { return $ir }
    set dir [file join $::tmproot media[incr ::mediaSeq]]
    file mkdir $dir
    catch {extractParts $path $urls $dir}
    set out {}
    foreach b $ir {
        if {[dict get $b type] eq "image"} {
            set local [file join $dir [dict get $b meta url]]
            if {[file exists $local]} { dict set b meta url $local }
        }
        lappend out $b
    }
    return $out
}

proc openOdt {path} {
    if {[catch {docir::odtSource::fromOdt $path} ir]} {
        tk_messageBox -icon error -title "Fehler" -message "ODT lesen:\n$ir"
        return
    }
    set ::currentIrView [remapImages $path $ir]
    rerender
    .bar.file configure -text [file tail $path]
    wm title . "ODT-View — [file tail $path]"
}

## (Neu) rendern mit aktuellem Tabellenmodus -- vom Umschalter und von openOdt
## genutzt. tablemode frame -> native Frame-Tabellen (docir::rendererTk),
## sonst die Monospace-Box.
proc rerender {} {
    if {$::currentIrView eq ""} return
    set tmode [expr {$::useFrameTables ? "frame" : "ascii"}]
    docir::renderer::tk::render .main.t $::currentIrView \
        [dict create fontSize 11 fontFamily TkDefaultFont monoFamily TkFixedFont \
            tablemode $tmode]
}

bind . <Control-o> { openDialog }
bind . <Control-q> { exit }
wm protocol . WM_DELETE_WINDOW { catch {file delete -force $tmproot}; exit }

## Datei aus argv
if {[llength $argv] > 0} { openOdt [lindex $argv 0] }

## Selbsttest-Hook (headless): ODTVIEW_SELFTEST=1 -> Diagnose + exit
if {[info exists ::env(ODTVIEW_SELFTEST)]} {
    update idletasks
    set txt [.main.t get 1.0 end]
    set imgs [.main.t image names]
    set wins [.main.t window names]
    set mode [expr {$::useFrameTables ? "frame" : "ascii"}]
    puts "SELFTEST: [.main.t index end] Zeilen, [string length $txt] Zeichen, [llength $imgs] Bild(er), [llength $wins] Frame-Tabelle(n), tablemode=$mode"
    puts "ERSTE ZEILEN:"
    foreach l [lrange [split $txt \n] 0 6] { puts "  | $l" }
    catch {file delete -force $tmproot}
    exit 0
}
