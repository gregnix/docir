#!/usr/bin/env tclsh
## demo-html.tcl  --  Demo: HTML (Webseite) -> DocIR -> PDF / Markdown / HTML
##
## Zeigt die Drehscheibe: eine HTML-Quelle ueber docir::htmlSource ins
## DocIR und von dort in beliebige Senken -- u.a. PDF.
##
##   HTML --docir::htmlSource--> DocIR --docir::pdf--> PDF
##                                     --docir::md---> Markdown
##                                     --docir::html-> HTML (normalisiert)
##
## Aufruf:  tclsh demo-html.tcl ?seite.html? ?zielverzeichnis?
##   ohne Argument wird ein eingebettetes Beispiel verwendet.
##   Eine echte Webseite: im Browser als HTML speichern und hier angeben.
##
## Hinweis: der PDF-Schritt braucht docir::pdf + pdf4tcl. Fehlt pdf4tcl,
## ueberspringt die Demo PDF und macht mit Markdown/HTML weiter.

package require docir
package require docir::htmlSource
package require docir::md
package require docir::html

set htmlArg [lindex $argv 0]
set outDir  [expr {[llength $argv] > 1 ? [lindex $argv 1] : [pwd]}]
file mkdir $outDir

set sampleHtml {<!DOCTYPE html>
<html><head><title>Beispielseite</title>
<style>body{font-family:sans-serif}</style></head>
<body>
<h1>Beispiel-Webseite</h1>
<p>Ein Absatz mit <strong>fett</strong>, <em>kursiv</em>, <code>Code</code>
und einem <a href="https://www.tcl.tk/">Link</a>.</p>
<h2>Punkte</h2>
<ul><li>Erster Punkt</li><li>Zweiter Punkt</li><li>Dritter Punkt</li></ul>
<h2>Tabelle</h2>
<table>
<tr><th>Quelle</th><th>Format</th></tr>
<tr><td>htmlSource</td><td>HTML</td></tr>
<tr><td>mdSource</td><td>Markdown</td></tr>
</table>
<h2>Code</h2>
<pre><code>set ir [docir::htmlSource::fromHtml $html]</code></pre>
<nav class="menu">Diese Navigation wird verworfen.</nav>
</body></html>}

if {$htmlArg ne "" && [file isfile $htmlArg]} {
    set fh [open $htmlArg]; fconfigure $fh -encoding utf-8
    set html [read $fh]; close $fh
    puts "Eingabe: $htmlArg"
} else {
    set html $sampleHtml
    puts "Eingabe: eingebettetes Beispiel"
}

# HTML -> DocIR
set ir [docir::htmlSource::fromHtml $html]
puts "DocIR: [llength $ir] Bloecke, valide: [expr {[docir::validate $ir] eq {} ? {ja} : {nein}}]"

proc save {path s} { set fh [open $path w]; fconfigure $fh -encoding utf-8; puts -nonewline $fh $s; close $fh }

# DocIR -> Markdown / HTML
save [file join $outDir demo-html-out.md]   [docir::md::render   $ir]
save [file join $outDir demo-html-out.html] [docir::html::render $ir [list title "Aus HTML"]]
set created {demo-html-out.md demo-html-out.html}

# DocIR -> PDF (optional, braucht pdf4tcl)
set pdfPath [file join $outDir demo-html-out.pdf]
if {![catch {package require docir::pdf}]} {
    if {[catch {docir::pdf::render $ir $pdfPath} err]} {
        puts "PDF uebersprungen: $err"
    } else {
        lappend created demo-html-out.pdf
    }
} else {
    puts "PDF uebersprungen: docir::pdf/pdf4tcl nicht verfuegbar"
}

puts "erzeugt:"
foreach f $created { puts "  [file join $outDir $f]" }
