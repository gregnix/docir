#!/usr/bin/env wish
## demo-md-tk.tcl  --  Demo: Markdown im Tk-Fenster anzeigen
##
## Kette (wie im docir-cookbook):
##   Markdown --mdstack::parser--> AST --docir::md::fromAst--> DocIR
##           --docir::renderer::tk--> Text-Widget
##
## Tabellen erscheinen als ausgerichtete Box-Tabellen (Monospace).
##
## Aufruf:  wish demo-md-tk.tcl ?datei.md?
##          wish demo-md-tk.tcl --selftest      (headless: rendert + prueft)

package require Tk
package require mdstack::parser
package require docir
package require docir::mdSource     ;# stellt docir::md::fromAst bereit
package require docir::rendererTk

set selftest [expr {"--selftest" in $argv}]
set argv [lsearch -all -inline -not -exact $argv --selftest]

set sampleMd {# Markdown in Tk

Ein Absatz mit **fett**, *kursiv*, `Code` und einem [Link](https://www.tcl.tk/).

## Liste

- Eintrag A
- Eintrag B
- Eintrag C

## Tabelle

| Modul            | Rolle  | Notiz                |
| ---------------- | ------ | -------------------- |
| docir::odt       | Senke  | DocIR nach ODT       |
| docir::mdSource  | Quelle | Markdown nach DocIR  |
| docir::rendererTk| Anzeige| DocIR ins Tk-Widget  |

## Code

    set ir [docir::md::fromAst [mdstack::parser::parse $md]]

Schlusssatz.
}

# Markdown beschaffen: Datei aus argv oder Sample
if {[llength $argv] > 0 && [file readable [lindex $argv 0]]} {
    set fh [open [lindex $argv 0]]; fconfigure $fh -encoding utf-8
    set md [read $fh]; close $fh
} else {
    set md $sampleMd
}

# Markdown -> AST -> DocIR
set ir [docir::md::fromAst [mdstack::parser::parse $md]]

# --- UI ---
wm title . "demo: Markdown in Tk"
text .t -wrap word -width 80 -height 28
pack .t -fill both -expand 1
docir::renderer::tk::render .t $ir
.t configure -state disabled
update idletasks

if {$selftest} {
    set txt [.t get 1.0 end]
    set hasBox  [string match *\u250c* $txt]    ;# obere linke Ecke der Box
    set hasHead [string match *Markdown\ in\ Tk* $txt]
    puts "SELFTEST: bloecke=[llength $ir] box-tabelle=$hasBox heading=$hasHead"
    puts [expr {($hasBox && $hasHead) ? "PASS" : "FAIL"}]
    exit [expr {($hasBox && $hasHead) ? 0 : 1}]
}
