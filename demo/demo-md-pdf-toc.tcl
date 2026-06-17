#!/usr/bin/env tclsh
# demo-md-pdf-toc.tcl -- Markdown -> DocIR -> PDF mit nummeriertem
# Inhaltsverzeichnis (generateToc, Zwei-Pass).
#
# Voraussetzungen auf dem tcl::tm::path / auto_path:
#   - mdstack::parser
#   - docir (docir::mdSource, docir::pdf)
#   - pdf4tcl, pdf4tcllib
#
# Bei -generateToc 1 rendert docir::pdf::render das Dokument iterativ,
# bis die Heading-Seiten stabil sind, und stellt ein Inhaltsverzeichnis
# mit rechtsbuendigen Seitenzahlen voran. tocDepth steuert, bis zu
# welchem Heading-Level Eintraege erscheinen (Default 2), tocTitle den
# Titel der TOC-Seite (Default "Inhaltsverzeichnis").
#
# Usage:
#   tclsh demo-md-pdf-toc.tcl ?input.md? ?output.pdf?
# Ohne Argumente wird ein eingebautes Beispiel gerendert, dessen Kapitel
# durch Fuelltext auf verschiedene Seiten fallen.

package require mdstack::parser
package require docir::mdSource
package require docir::pdf

set inFile  [lindex $argv 0]
set outFile [lindex $argv 1]
if {$outFile eq ""} { set outFile "demo-md-pdf-toc.pdf" }

if {$inFile ne "" && [file exists $inFile]} {
    set fh [open $inFile]
    fconfigure $fh -encoding utf-8
    set md [read $fh]
    close $fh
    set root [file dirname $inFile]
} else {
    # Built-in example. Filler paragraphs push each chapter onto its own
    # page so the TOC shows distinct page numbers.
    proc filler {label n} {
        set out ""
        for {set i 1} {$i <= $n} {incr i} {
            append out "Paragraph $i of $label. This is filler text used to\
                         demonstrate that the table of contents reports the\
                         real page on which each heading begins.\n\n"
        }
        return $out
    }
    set md "# Introduction\n\nOpening remarks.\n\n"
    append md "## Background\n\n[filler Background 12]"
    append md "# Concepts\n\n[filler Concepts 14]"
    append md "## Building Blocks\n\n[filler {Building Blocks} 10]"
    append md "### Internal Details\n\nA level-3 heading; with the default\
               tocDepth of 2 it does not appear in the table of contents.\n\n"
    append md "# Reference\n\n[filler Reference 6]"
    set root [pwd]
}

set ast [mdstack::parser::parse $md]
set ir  [docir::md::fromAst $ast]

# generateToc 1 -> Inhaltsverzeichnis mit Seitenzahlen vor dem Hauptteil.
docir::pdf::render $ir $outFile [dict create \
    title       "TOC Demo" \
    root        $root \
    generateToc 1 \
    tocTitle    "Inhaltsverzeichnis" \
    tocDepth    2]

puts "geschrieben: $outFile"
