#!/usr/bin/env tclsh
# demo-md-pdf-index.tcl -- Markdown -> DocIR -> PDF mit Sachindex
# (generateIndex) und Inhaltsverzeichnis (generateToc).
#
# Index-Begriffe werden im Markdown als bracketed span mit der Klasse
# "index" markiert:  [Begriff]{.index}
# Der Begriff bleibt im Fliesstext sichtbar und erscheint zugleich im
# Stichwortverzeichnis mit allen Seiten, auf denen er vorkommt. Ein
# Begriff darf in jedem Absatz auf jeder Ebene stehen; die Seite wird
# beim Rendern erfasst, also auch korrekt ueber Seitenumbrueche hinweg.
#
# Voraussetzungen auf dem tcl::tm::path / auto_path:
#   - mdstack::parser
#   - docir (docir::mdSource, docir::pdf)
#   - pdf4tcl, pdf4tcllib
#
# Usage:
#   tclsh demo-md-pdf-index.tcl ?input.md? ?output.pdf?
# Ohne Argumente wird ein eingebautes Beispiel gerendert.

package require mdstack::parser
package require docir::mdSource
package require docir::pdf

set inFile  [lindex $argv 0]
set outFile [lindex $argv 1]
if {$outFile eq ""} { set outFile "demo-md-pdf-index.pdf" }

if {$inFile ne "" && [file exists $inFile]} {
    set fh [open $inFile]
    fconfigure $fh -encoding utf-8
    set md [read $fh]
    close $fh
    set root [file dirname $inFile]
} else {
    # Built-in example. Filler paragraphs spread the chapters over several
    # pages so the index lists distinct (and repeated) page numbers.
    proc filler {n} {
        set out ""
        for {set i 1} {$i <= $n} {incr i} {
            append out "Filler paragraph $i to spread the content across pages.\n\n"
        }
        return $out
    }
    set md "# Coroutines\n\nThe \[coroutine\]{.index} command suspends a script.\n\n"
    append md [filler 28]
    append md "# Namespaces\n\nA \[namespace\]{.index} groups commands; see also \[coroutine\]{.index}.\n\n"
    append md [filler 28]
    append md "# Packages\n\nUse \[package require\]{.index} to load a \[namespace\]{.index}.\n\n"
    set root [pwd]
}

set ast [mdstack::parser::parse $md]
set ir  [docir::md::fromAst $ast]

# generateToc + generateIndex: Inhaltsverzeichnis vorne, Sachindex hinten.
docir::pdf::render $ir $outFile [dict create \
    title         "Index Demo" \
    root          $root \
    generateToc   1 \
    tocTitle      "Inhaltsverzeichnis" \
    tocDepth      2 \
    generateIndex 1 \
    indexTitle    "Stichwortverzeichnis"]

puts "geschrieben: $outFile"
