#!/usr/bin/env tclsh
## demo-odt.tcl  --  Demo der ODT-Pipeline (ohne GUI)
##
## Zeigt:
##   1) DocIR im Code aufbauen
##   2) -> ODT schreiben (docir::odt), Bild eingebettet
##   3) ODT wieder einlesen (docir::odtSource)
##   4) daraus HTML / Markdown / Text erzeugen (docir::html/md/txt)
##
## Ergebnis: demo-out.odt, demo-out.html, demo-out.md, demo-out.txt
## Die .odt in LibreOffice oeffnen, die .html im Browser.
##
## Aufruf:  tclsh demo-odt.tcl ?ZIELVERZEICHNIS?
## (Module via package require; im Repo-Setup ohne Zusatzpfade.)

package require docir
package require docir::odt
package require docir::odtSource
package require docir::md
package require docir::txt
package require docir::html

set outDir [expr {[llength $argv] > 0 ? [lindex $argv 0] : [pwd]}]
file mkdir $outDir

# kleines eingebettetes PNG (48x24) -> als Pictures/demo.png einbetten
set pngB64 "iVBORw0KGgoAAAANSUhEUgAAADAAAAAYCAIAAAAzn+mLAAAAA3NCSVQICAjb4U/gAAAAG3RFWHRTb2Z0d2FyZQBUayBUb29sa2l0IHY4LjYuMTQ0taqVAAAAOUlEQVR4nGMQ0AoZVIhhwF0w6qBRB9HeQS8W29INjTpo1EGjDhp10KiDRh1ECwcNLBp10KiDhp2DAPL+kR3xSHxxAAAAAElFTkSuQmCC"
# (falls die b64-Zeile beim Kopieren bricht: eine Zeile lassen)
set pngBytes [binary decode base64 $pngB64]
set imgUrl "Pictures/demo.png"

# --- DocIR aufbauen ---
set ir [list \
  [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
  [dict create type heading content {{type text text "docir::odt Demo"}} meta {level 1 id demo}] \
  [dict create type paragraph content {
      {type text text "Ein Absatz mit "} {type strong text fett}
      {type text text ", "} {type emphasis text kursiv}
      {type text text ", "} {type code text Code}
      {type text text " und einem "}
      {type link text "Link" name "" section "" href "https://www.tcl.tk/"}
      {type text text "."}} meta {}] \
  [dict create type heading content {{type text text "Liste"}} meta {level 2 id liste}] \
  [dict create type list content {
      {type listItem content {{type text text "Eintrag A"}} meta {kind ul term {}}}
      {type listItem content {{type text text "Eintrag B"}} meta {kind ul term {}}}
      {type listItem content {{type text text "Eintrag C"}} meta {kind ul term {}}}
  } meta {kind ul indentLevel 0}] \
  [dict create type heading content {{type text text "Tabelle"}} meta {level 2 id tabelle}] \
  [dict create type table content {
      {type tableRow content {
         {type tableCell content {{type text text Modul}} meta {}}
         {type tableCell content {{type text text Rolle}} meta {}}
         {type tableCell content {{type text text Notiz}} meta {}}} meta {kind header}}
      {type tableRow content {
         {type tableCell content {{type text text "docir::odt"}} meta {}}
         {type tableCell content {{type text text Senke}} meta {}}
         {type tableCell content {{type text text "DocIR nach ODT"}} meta {}}} meta {}}
      {type tableRow content {
         {type tableCell content {{type text text "docir::odtSource"}} meta {}}
         {type tableCell content {{type text text Quelle}} meta {}}
         {type tableCell content {{type text text "ODT nach DocIR"}} meta {}}} meta {}}
  } meta {columns 3 alignments {left left left} hasHeader 1}] \
  [dict create type heading content {{type text text "Codeblock"}} meta {level 2 id code}] \
  [dict create type pre content {{type text text "package require docir::odt\ndocir::odt::write \$ir out.odt"}} meta {kind code}] \
  [dict create type heading content {{type text text "Bild"}} meta {level 2 id bild}] \
  [dict create type image content {} meta [dict create url $imgUrl alt "Demo"]] \
]

proc save {path s} { set fh [open $path w]; fconfigure $fh -encoding utf-8; puts -nonewline $fh $s; close $fh }

# --- 2) DocIR -> ODT ---
set odtPath [file join $outDir demo-out.odt]
docir::odt::write $ir $odtPath [list media [dict create $imgUrl $pngBytes]]
puts "geschrieben: $odtPath ([file size $odtPath] Bytes)"

# --- 3) ODT -> DocIR (Rueckweg) ---
set back [docir::odtSource::fromOdt $odtPath]
puts "rueckgelesen: [llength $back] Bloecke, valide: [expr {[docir::validate $back] eq {} ? {ja} : {nein}}]"

# --- 4) DocIR -> HTML / Markdown / Text ---
save [file join $outDir demo-out.html] [docir::html::render $back [list title "docir::odt Demo"]]
save [file join $outDir demo-out.md]   [docir::md::render   $back]
save [file join $outDir demo-out.txt]  [docir::txt::render  $back]

puts "erzeugt:"
foreach f {demo-out.odt demo-out.html demo-out.md demo-out.txt} {
    puts "  [file join $outDir $f]"
}
puts "Tipp: demo-out.odt in LibreOffice oeffnen, demo-out.html im Browser."
