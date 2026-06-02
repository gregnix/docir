#!/usr/bin/env wish
## demo-tk2odt.tcl  --  Demo: Tk-Widget -> ODT (via docir::tkSource)
##
## Ein Beispiel-DocIR wird im Text-Widget angezeigt (renderer::tk).
## Buttons exportieren den Widget-Inhalt -- ganz oder nur die Markierung --
## ueber docir::tkSource nach ODT (docir::odt). Das ist der ttd-aehnliche
## "speichere (einen Teil) des Widgets"-Weg, aber portabel als ODT.
##
## Hinweis: beim Auslesen aus dem Widget werden Tabellen/Listen zu Absaetzen
## (das Widget haelt ihre Struktur nicht). Fuer strukturerhaltenden Export
## das DocIR direkt an docir::odt geben (siehe demo-odt.tcl).
##
## Aufruf:  wish demo-tk2odt.tcl
##          wish demo-tk2odt.tcl --selftest   (headless: exportiert + prueft)

package require Tk
package require docir
package require docir::rendererTk
package require docir::tkSource
package require docir::odt

set selftest [expr {"--selftest" in $argv}]
set outOdt [file join [pwd] demo-tk-out.odt]

set sampleIR {
  {type doc_meta content {} meta {irSchemaVersion 1}}
  {type heading content {{type text text "Tk -> ODT Demo"}} meta {level 1 id x}}
  {type paragraph content {{type text text "Markiere etwas und exportiere nur die Markierung, "} {type text text "oder exportiere alles. "} {type strong text "Fett"} {type text text " und "} {type emphasis text kursiv} {type text text " bleiben erhalten."}} meta {}}
  {type heading content {{type text text "Code"}} meta {level 2 id y}}
  {type pre content {{type text text "set ir [docir::tkSource::fromWidget .t]\ndocir::odt::write $ir out.odt"}} meta {kind code}}
  {type paragraph content {{type text text "Schluss."}} meta {}}
}

proc setStatus {msg} { .status configure -text $msg }

proc exportRange {i1 i2} {
    global outOdt
    if {$i1 eq ""} {
        set ir [docir::tkSource::fromWidget .t]
        set what "alles"
    } else {
        set ir [docir::tkSource::fromWidget .t $i1 $i2]
        set what "Markierung"
    }
    set media [docir::tkSource::media]
    docir::odt::write $ir $outOdt [list media $media]
    setStatus "exportiert ($what): $outOdt  -- [llength $ir] Bloecke, [dict size $media] Bild(er)"
    return $ir
}

proc exportAll {} { exportRange "" "" }
proc exportSel {} {
    if {[catch {.t index sel.first} a]} { setStatus "keine Markierung"; return }
    exportRange [.t index sel.first] [.t index sel.last]
}

# --- UI ---
wm title . "demo: Tk -> ODT"
frame .bar
button .bar.all -text "Alles \u2192 ODT" -command exportAll
button .bar.sel -text "Markierung \u2192 ODT" -command exportSel
pack .bar.all .bar.sel -side left -padx 4 -pady 4
label .status -text "bereit" -anchor w -relief sunken
text .t -wrap word -width 72 -height 20
pack .bar -side top -fill x
pack .status -side bottom -fill x
pack .t -side top -fill both -expand 1

docir::renderer::tk::render .t $sampleIR
update idletasks

if {$selftest} {
    set ir [exportRange "" ""]
    set ok [expr {[file exists $outOdt] && [file size $outOdt] > 1000}]
    puts "SELFTEST: ODT=[file exists $outOdt] groesse=[file size $outOdt] bloecke=[llength $ir]"
    puts [expr {$ok ? "PASS" : "FAIL"}]
    exit [expr {$ok ? 0 : 1}]
}
