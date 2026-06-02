#!/usr/bin/env wish
## test-tksource.tcl  --  Test fuer docir::tkSource (Widget -> DocIR)
## und die Export-Schleife Tk-Widget -> docir::odt -> ODT.
##
## Pipeline:
##   DocIR --renderer::tk--> Text-Widget --tkSource--> DocIR' (+media)
##         --docir::odt--> ODT --odtSource--> DocIR''
##
## Nutzung:
##   wish test-tksource.tcl              (oeffnet kurz ein Fenster)
##   xvfb-run -a wish test-tksource.tcl  (headless)
##
## Braucht: rendererTk MIT heading-Fix (index "end-1c"), sonst werden
## Ueberschriften nicht erkannt -- der Test sagt das dann deutlich.

package require Tk

set here [file dirname [file normalize [info script]]]
::tcl::tm::path add $here
if {[info exists ::env(DOCIR_TM)]} { ::tcl::tm::path add $::env(DOCIR_TM) }

proc need {pkg {glob {}}} {
    if {![catch {package require $pkg}]} { return }
    if {$glob ne ""} {
        set c [lsort [glob -nocomplain -directory $::here $glob]]
        if {[llength $c]} { source -encoding utf-8 [lindex $c end]; return }
    }
    puts stderr "FEHLT: $pkg (DOCIR_TM setzen oder Modul ins Skriptverzeichnis)"
    exit 2
}
need docir
need docir::rendererTk
need docir::odt
need docir::odtSource
need docir::tkSource     tkSource-*.tm

puts "TKSOURCE TEST"
puts "pkg docir::tkSource: [package present docir::tkSource]"

# --- Testbild erzeugen (kein externes File noetig) ---
set png [file join [file dirname [file tempfile dummy]] tkt_[pid].png]
set gen [image create photo -width 32 -height 16]
$gen put navy -to 0 0 32 16
$gen put orange -to 4 4 28 12
$gen write $png -format png
puts "Testbild: $png ([file size $png] Bytes)"

# --- Quell-DocIR ---
set ir [list \
  [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
  [dict create type heading content {{type text text "Widget-Export"}} meta {level 1 id x}] \
  [dict create type paragraph content {{type text text {Ein }} {type strong text fett} {type text text { und }} {type emphasis text kursiv} {type text text { Absatz mit }} {type code text code()} {type text text .}} meta {}] \
  [dict create type heading content {{type text text "Code"}} meta {level 2 id y}] \
  [dict create type pre content {{type text text "zeile1\nzeile2"}} meta {kind code}] \
  [dict create type image content {} meta [dict create url $png alt ""]] \
  [dict create type paragraph content {{type text text "Schluss."}} meta {}] \
]

# --- 1) DocIR -> Widget ---
text .t -wrap word -width 80 -height 24
pack .t -fill both -expand 1
docir::renderer::tk::render .t $ir
update idletasks

# --- 2) Widget -> DocIR (+ media) ---
set back  [docir::tkSource::fromWidget .t]
set media [docir::tkSource::media]

# --- Pruefungen auf dem ausgelesenen IR ---
set pass 0; set fail 0
proc check {name cond} {
    if {[uplevel 1 [list expr $cond]]} { puts "ok   $name"; incr ::pass } else { puts "FAIL $name"; incr ::fail }
}
proc hasType {ir t} { foreach b $ir { if {[dict get $b type] eq $t} { return 1 } }; return 0 }
proc countType {ir t} { set n 0; foreach b $ir { if {[dict get $b type] eq $t} { incr n } }; return $n }

puts "ausgelesen: [llength $back] Bloecke"
check "DocIR nicht leer"        {[llength $back] > 1}
check "heading erkannt"         {[hasType $back heading]}
check "  -> 2 headings"         {[countType $back heading] == 2}
check "paragraph erkannt"       {[hasType $back paragraph]}
check "pre/code erkannt"        {[hasType $back pre]}
check "image erkannt"           {[hasType $back image]}
check "media hat 1 Bild"        {[dict size $media] == 1}

if {![hasType $back heading]} {
    puts "HINWEIS: keine heading erkannt -> ist der rendererTk-Fix"
    puts "         (index \"end-1c\") eingespielt?"
}

# --- 3) DocIR -> ODT (mit eingebetteten Bildern) ---
set out [file join $here tksource-test-output.odt]
docir::odt::write $back $out [list media $media]
check "ODT geschrieben"         {[file exists $out] && [file size $out] > 1000}

# --- 4) ODT -> DocIR (Rueckweg) ---
set rt [docir::odtSource::fromOdt $out]
check "ODT wieder lesbar"       {[hasType $rt heading] || [hasType $rt paragraph]}
check "Bild im ODT"             {[hasType $rt image]}
check "DocIR valide"            {[docir::validate $rt] eq ""}

puts "------------------------------------------"
puts "PASS $pass   FAIL $fail"
puts "ODT: $out"
catch {file delete $png}

# Headless beenden; fuers Anschauen die naechste Zeile auskommentieren.
exit [expr {$fail > 0 ? 1 : 0}]
