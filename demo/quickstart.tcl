#!/usr/bin/env tclsh
# quickstart.tcl -- DocIR Quickstart-Demo
#
# Liest eine nroff-Manpage, wandelt sie via DocIR in HTML, SVG und
# Markdown um. Zeigt:
#  - wie das docir-Repo geladen wird (selbst-finden)
#  - wie eine Quelle (docir-roff-source) genutzt wird
#  - wie mehrere Senken den selben IR konsumieren
#
# Verwendung:
#   tclsh quickstart.tcl input.n
#   tclsh quickstart.tcl input.n output-prefix
#
# Erzeugt: <prefix>.html, <prefix>.svg, <prefix>.md
# Default-Prefix: rootname von input.n

# ============================================================
# 1. Pfade auflösen — wir liegen in <docir-repo>/demo/
# ============================================================

set demoDir   [file dirname [file normalize [info script]]]
set docirRoot [file dirname $demoDir]
set libDir    [file join $docirRoot lib tm]

# Brauchen wir nroffparser. Suchstrategien:
#  1. $NROFFPARSER_HOME / man-viewer-Repo als Sibling
#  2. via auto_path
proc findNroffparser {docirRoot} {
    # Sibling-Repo suchen
    foreach base [list \
            [file dirname $docirRoot] \
            [file dirname [file dirname $docirRoot]]] {
        foreach pat {man-viewer man-viewer*} {
            foreach d [glob -nocomplain -directory $base -type d $pat] {
                # man-viewer hat geschachtelte Struktur
                foreach inner [list $d [file join $d man-viewer]] {
                    set tm [file join $inner lib tm nroffparser-0.2.tm]
                    if {[file exists $tm]} { return $tm }
                }
            }
        }
    }
    return ""
}

# ============================================================
# 2. Module laden
# ============================================================

# DocIR-Module direkt aus diesem Repo
foreach mod {docir-0.1.tm
             docir-roff-source-0.1.tm
             docir-html-0.1.tm
             docir-svg-0.1.tm
             docir-md-0.1.tm} {
    set p [file join $libDir $mod]
    if {![file exists $p]} {
        puts stderr "Demo-Fehler: $mod nicht gefunden in $libDir"
        exit 1
    }
    source -encoding utf-8 $p
}

# nroffparser separat suchen
set nroffparserPath [findNroffparser $docirRoot]
if {$nroffparserPath eq ""} {
    puts stderr "Demo-Fehler: nroffparser-0.2.tm nicht gefunden."
    puts stderr ""
    puts stderr "Diese Demo braucht das man-viewer-Repo als Sibling vom docir-Repo."
    puts stderr "Erwarteter Pfad: <parent>/man-viewer/man-viewer/lib/tm/nroffparser-0.2.tm"
    exit 1
}

# nroffparser nutzt optional mvdebug — Stubs voranschicken falls nicht da.
# (mvdebug lebt im man-viewer-Repo, ist aber fuer diese Demo nicht
# essentiell. Stub-Funktionen wirken als no-ops.)
if {[info commands ::debug::scope] eq ""} {
    namespace eval ::debug {
        proc scope {args} {}
        proc log {args} {}
        proc level {args} { return 0 }
        proc getLevel {args} { return 0 }
        proc startTimer {args} {}
        proc stopTimer {args} {}
        proc traceLine {args} {}
    }
}

source -encoding utf-8 $nroffparserPath

# ============================================================
# 3. Argumente verarbeiten
# ============================================================

if {[llength $argv] < 1} {
    puts "Verwendung: tclsh [file tail [info script]] input.n \[output-prefix\]"
    puts ""
    puts "Erzeugt: <prefix>.html, <prefix>.svg, <prefix>.md"
    puts ""
    puts "Default-Prefix: rootname von input.n"
    exit 1
}

set inputFile [lindex $argv 0]
if {![file exists $inputFile]} {
    puts stderr "Datei nicht gefunden: $inputFile"
    exit 1
}

set outputPrefix [expr {[llength $argv] >= 2 ? [lindex $argv 1] :
                        [file rootname $inputFile]}]

# ============================================================
# 4. Pipeline: nroff → AST → DocIR → 3 Senken
# ============================================================

# 4a. Datei lesen
set fh [open $inputFile r]
fconfigure $fh -encoding utf-8
set nroff [read $fh]
close $fh
puts "Eingabe:  $inputFile ([file size $inputFile] bytes)"

# 4b. Parsen — AST ist flache Liste von Block-Knoten
set ast [nroffparser::parse $nroff $inputFile]
puts "Geparst:  AST mit [llength $ast] Bloecken"

# 4c. Mapping zu DocIR
set ir [::docir::roff::fromAst $ast]
puts "DocIR:    [llength $ir] Knoten"

# 4d. Validierung (optional, dokumentiert das Format)
if {[catch {::docir::validate $ir} err]} {
    puts stderr "Warnung: DocIR-Validierung fehlgeschlagen: $err"
} else {
    puts "Valid:    DocIR ist schemakonform"
}

# 4e. Drei Senken nacheinander
puts ""

# HTML
set htmlFile "${outputPrefix}.html"
set html [::docir::html::render $ir [dict create \
    theme manpage lang de includeToc 1]]
set fh [open $htmlFile w]
fconfigure $fh -encoding utf-8
puts -nonewline $fh $html
close $fh
puts "HTML:     $htmlFile ([file size $htmlFile] bytes)"

# SVG
set svgFile "${outputPrefix}.svg"
set svg [::docir::svg::render $ir]
set fh [open $svgFile w]
fconfigure $fh -encoding utf-8
puts -nonewline $fh $svg
close $fh
puts "SVG:      $svgFile ([file size $svgFile] bytes)"

# Markdown
set mdFile "${outputPrefix}.md"
set md [::docir::md::render $ir]
set fh [open $mdFile w]
fconfigure $fh -encoding utf-8
puts -nonewline $fh $md
close $fh
puts "Markdown: $mdFile ([file size $mdFile] bytes)"

puts ""
puts "Fertig — drei Formate aus EINEM DocIR-IR gerendert."
