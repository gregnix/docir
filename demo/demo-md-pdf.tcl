#!/usr/bin/env tclsh
# demo-md-pdf.tcl -- Markdown -> DocIR -> PDF, mit gerenderter Display-Math.
#
# Voraussetzungen auf dem tcl::tm::path / auto_path:
#   - mdstack::parser
#   - docir (docir::mdSource, docir::pdf)
#   - pdf4tcllib   MIT pdf4tcllib::math::renderLatex   (sonst Math als Text!)
#
# Pruefen, ob die Math-faehige pdf4tcllib geladen wird:
#   echo 'package require pdf4tcllib; \
#         puts [llength [info commands ::pdf4tcllib::math::renderLatex]]' | tclsh
#   -> 1 = ok (neue Version), 0 = alte Version ohne renderLatex
#
# Hinweis: Aktuell ist nur DISPLAY-Math ($$...$$) gerendert.
#          Inline-Math ($...$) erscheint noch als Text.
#
# Usage:
#   tclsh demo-md-pdf.tcl ?input.md? ?output.pdf?
# Ohne Argumente wird ein eingebautes Beispiel gerendert.

package require mdstack::parser
package require docir::mdSource
package require docir::pdf

set inFile  [lindex $argv 0]
set outFile [lindex $argv 1]
if {$outFile eq ""} { set outFile "demo-md-pdf.pdf" }

if {$inFile ne "" && [file exists $inFile]} {
    set fh [open $inFile]
    fconfigure $fh -encoding utf-8
    set md [read $fh]
    close $fh
    set root [file dirname $inFile]
} else {
    set md {# Math-Demo

Ein Absatz mit Text. Es folgt eine Display-Formel:

$$
\int_{-\infty}^{\infty} e^{-x^2}\, dx = \sqrt{\pi}
$$

Ein Bruch und Symbole:

$$
\frac{a + b}{c} = \alpha + \beta
$$

Summe mit Grenzen:

$$
\sum_{n=1}^{N} a_n = S
$$
}
    set root [pwd]
}

set ast [mdstack::parser::parse $md]
set ir  [docir::md::fromAst $ast]

# cid 1 -> volles Unicode (Griechisch/Math-Symbole) im PDF.
docir::pdf::render $ir $outFile [dict create \
    cid   1 \
    root  $root \
    title "Math-Demo"]

puts "geschrieben: $outFile"
