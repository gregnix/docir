#!/usr/bin/env tclsh
# demo-md-html-index.tcl -- Markdown -> DocIR -> HTML mit Sachindex
# (includeIndex) und Inhaltsverzeichnis (includeToc).
#
# Index-Begriffe werden im Markdown als bracketed span mit der Klasse
# "index" markiert:  [Begriff]{.index}
# Der Begriff bleibt im Fliesstext sichtbar, bekommt einen Sprung-Anker
# und erscheint im Stichwortverzeichnis am Seitenende mit Links zu allen
# Vorkommen (Linktext = Abschnittstitel, pro Abschnitt zusammengefasst).
#
# Voraussetzungen auf dem tcl::tm::path / auto_path:
#   - mdstack::parser
#   - docir (docir::mdSource, docir::html)
#
# Usage:
#   tclsh demo-md-html-index.tcl ?input.md? ?output.html?
# Ohne Argumente wird ein eingebautes Beispiel gerendert.

package require mdstack::parser
package require docir::mdSource
package require docir::html

set inFile  [lindex $argv 0]
set outFile [lindex $argv 1]
if {$outFile eq ""} { set outFile "demo-md-html-index.html" }

if {$inFile ne "" && [file exists $inFile]} {
    set fh [open $inFile]
    fconfigure $fh -encoding utf-8
    set md [read $fh]
    close $fh
} else {
    set md "# Coroutines\n\nThe \[coroutine\]{.index} command suspends a script.\n\n"
    append md "# Namespaces\n\nA \[namespace\]{.index} groups commands; see also \[coroutine\]{.index}.\n\n"
    append md "# Packages\n\nUse \[package require\]{.index} to load a \[namespace\]{.index}.\n\n"
}

set ast [mdstack::parser::parse $md]
set ir  [docir::md::fromAst $ast]

# includeToc + includeIndex: Inhaltsverzeichnis oben, Sachindex unten.
set html [docir::html::render $ir [dict create \
    title        "Index Demo" \
    includeToc   1 \
    includeIndex 1 \
    indexTitle   "Stichwortverzeichnis"]]

set fh [open $outFile w]
fconfigure $fh -encoding utf-8
puts -nonewline $fh $html
close $fh

puts "geschrieben: $outFile"
