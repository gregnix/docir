#!/usr/bin/env tclsh
## html-roundtrip-test.tcl  --  Test docir::htmlSource
##
## DocIR --docir::html--> HTML --docir::htmlSource--> DocIR'
## Prueft: valide, und dass die Rueck-Konvertierung dasselbe Dokument
## ergibt (vergleicht ueber die HTML- und Markdown-Ausgabe, da DocIR-
## Werte gleich, aber als String unterschiedlich notiert sein koennen).
##
## Aufruf:  tclsh html-roundtrip-test.tcl

source [file join [file dirname [file normalize [info script]]] .. lib repos-path.tcl]
package require docir
package require docir::html
package require docir::md
package require docir::htmlSource

set pass 0; set fail 0
proc check {name cond} {
    if {[uplevel 1 [list expr $cond]]} { puts "ok   $name"; incr ::pass } else { puts "FAIL $name"; incr ::fail }
}
proc hasType {ir t} { foreach b $ir { if {[dict get $b type] eq $t} { return 1 } }; return 0 }

# Repraesentatives DocIR (deckt die Block- und Inline-Typen ab)
set ir [list \
  [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
  [dict create type heading content {{type text text "HTML Round-Trip"}} meta {level 1 id html-round-trip}] \
  [dict create type paragraph content {{type text text "Inlines: "} {type strong text fett} {type text text " "} {type emphasis text kursiv} {type text text " "} {type underline text unter} {type text text " "} {type strike text durch} {type text text " "} {type code text code} {type text text " "} {type link text Link name "" section "" href "https://www.tcl.tk/"} {type text text "."}} meta {}] \
  [dict create type heading content {{type text text "Listen"}} meta {level 2 id listen}] \
  [dict create type list content {{type listItem content {{type text text "A"}} meta {kind ul term {}}} {type listItem content {{type text text "B"}} meta {kind ul term {}}}} meta {kind ul indentLevel 0}] \
  [dict create type list content {{type listItem content {{type text text "A.1"}} meta {kind ul term {}}}} meta {kind ul indentLevel 1}] \
  [dict create type list content {{type listItem content {{type text text "eins"}} meta {kind ol term {}}} {type listItem content {{type text text "zwei"}} meta {kind ol term {}}}} meta {kind ol indentLevel 0}] \
  [dict create type heading content {{type text text "Tabelle"}} meta {level 2 id tabelle}] \
  [dict create type table content {
      {type tableRow content {
         {type tableCell content {{type text text Links}} meta {}}
         {type tableCell content {{type text text Mitte}} meta {}}
         {type tableCell content {{type text text Rechts}} meta {}}} meta {kind header}}
      {type tableRow content {
         {type tableCell content {{type text text a}} meta {}}
         {type tableCell content {{type text text b}} meta {}}
         {type tableCell content {{type text text c}} meta {}}} meta {}}
  } meta {columns 3 alignments {left center right} hasHeader 1}] \
  [dict create type hr content {} meta {}] \
  [dict create type pre content {{type text text "set x 1\nincr x"}} meta {kind code}] \
  [dict create type image content {} meta [dict create url "Pictures/demo.png" alt "Bild"]] \
]

puts "HTMLSOURCE ROUND-TRIP TEST"
puts "pkg docir::htmlSource: [package present docir::htmlSource]"

check "Ausgangs-DocIR valide" {[docir::validate $ir] eq ""}

# Body-only Round-Trip
set html0 [docir::html::render $ir [list standalone 0]]
set back0 [docir::htmlSource::fromHtml $html0]
check "back valide (body-only)"        {[docir::validate $back0] eq ""}
check "heading erhalten"               {[hasType $back0 heading]}
check "list erhalten"                  {[hasType $back0 list]}
check "table erhalten"                 {[hasType $back0 table]}
check "pre erhalten"                   {[hasType $back0 pre]}
check "image erhalten"                 {[hasType $back0 image]}
check "hr erhalten"                    {[hasType $back0 hr]}
check "Blockzahl gleich"               {[llength $back0] == [llength $ir]}
check "HTML(ir) == HTML(back)"         {$html0 eq [docir::html::render $back0 [list standalone 0]]}
check "MD(ir)   == MD(back)"           {[docir::md::render $ir] eq [docir::md::render $back0]}

# Volles Dokument (head/CSS/TOC) -> Body muss korrekt extrahiert werden
set html1 [docir::html::render $ir [list standalone 1 includeToc 1 title T]]
set back1 [docir::htmlSource::fromHtml $html1]
check "back valide (standalone)"       {[docir::validate $back1] eq ""}
check "MD gleich (standalone)"         {[docir::md::render $ir] eq [docir::md::render $back1]}
check "kein TOC/Nav als Block"         {[llength $back1] == [llength $ir]}

# Fremdes HTML (2026-10-22, Tablelist-Doku)
# 1. ueberzaehliges </dd>: tdom bricht ab, htmlSource liest trotzdem
set h {<html><body><dl><dd><dl><dt id="size">size</dt><dd>Returns the number.</dd>
  Synonym for <b>rowcount</b>.</dd><dt id="sort">sort</dt><dd>Sorts.</dd></dl></dd></dl></body></html>}
check "ueberzaehliges </dd> wird gelesen" {![catch {docir::htmlSource::fromHtml $h}]}
check "_balance: ueberzaehliges weg, Offenes geschlossen" {
    [docir::htmlSource::_balance {<dl><dd>a</dd> b</dd><dd>c</dl>}] eq {<dl><dd>a</dd> b<dd>c</dd></dl>}}
check "_balance: </dl COMPACT>, offene Zellen, Ende" {
    [docir::htmlSource::_balance {<dl><dd><table><tr><td>x</table></dd></dl COMPACT><p>y}] eq {<dl><dd><table><tr><td>x</td></tr></table></dd></dl><p>y</p>}}
# 2. <dd> mit verschachtelter Liste: nicht mehr eine einzige Zeile
set h {<html><body><dl><dt>WIDGET COMMAND</dt><dd><p>Intro.</p><dl><dt id="a">a</dt><dd>Does a.</dd><dt>b</dt><dd>Does b.</dd></dl></dd></dl></body></html>}
set md [docir::md::render [docir::htmlSource::fromHtml $h]]
# docir::md 0.2: die innere Liste steht eingerueckt in der Definition (Pandoc)
check "dd mit Unterliste: Begriffe einzeln" {[string first "\n    **a**\n    : Does a." $md] > 0 && [string first "\n    **b**\n    : Does b." $md] > 0}
check "dd mit Unterliste: dt-id als meta.id" {[string match "*id a*" [docir::htmlSource::fromHtml $h]]}

# BWidget (BWman): <td> nach "</TR>" ohne <tr>, <a name> ohne href
check "_balance: <td> ohne <tr> bekommt eins" {
    [docir::htmlSource::_balance {<table><tr><td>a</tr><td>b</tr></table>}] eq {<table><tr><td>a</td></tr><tr><td>b</td></tr></table>}}
set ir [docir::htmlSource::fromHtml {<html><body><dl><dt><a name="-type"><b>-type</b></a></dt><dd>Type.</dd></dl></body></html>}]
check "<a name> ist kein Link, aber Sprungziel" {
    [string first "(.md)" [docir::md::render $ir]] < 0 && [string match "*id -type*" $ir]}

# <pre> in <li> (Tablelist-Anleitung): Unterblock statt eine Zeile;
# erster Zeilenumbruch nach <pre> und letzter vor </pre> fallen weg
set ir [docir::htmlSource::fromHtml "<html><body><ul><li>Implement it:<blockquote><pre>\nproc a {} { return 1 }\n</pre></blockquote></li><li>plain</li></ul></body></html>"]
set md [docir::md::render $ir]
check "li mit pre: Codeblock im Eintrag" {[string first "- Implement it:\n\n  ```\n  proc a {} { return 1 }\n  ```" $md] >= 0}
check "li ohne Block bleibt einzeilig"   {[string first "- plain" $md] >= 0}
set ir [docir::htmlSource::fromHtml "<html><body><pre>\nx\ny\n</pre></body></html>"]
check "pre: ohne Leerzeile am Rand"      {[string first "```\nx\ny\n```" [docir::md::render $ir]] >= 0}

puts "------------------------------------------"
puts "PASS $pass   FAIL $fail"
exit [expr {$fail > 0 ? 1 : 0}]
