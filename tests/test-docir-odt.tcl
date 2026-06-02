#!/usr/bin/env tclsh
# test-docir-odt.tcl
#
# Test fuer docir::odt 0.3
#
# Zweck:
#   - DocIR manuell erzeugen
#   - mit docir::odt::write als ODT schreiben
#   - erzeugte Datei grob pruefen
#   - optional via docir::odtSource wieder einlesen
#
# Aufruf:
#   tclsh test-docir-odt.tcl
#   tclsh test-docir-odt.tcl out.odt
#   tclsh test-docir-odt.tcl -v out.odt
#
# Erwartete Pakete:
#   package require docir::odt 0.3
#
# Optional fuer Ruecklesetest:
#   package require docir::odtSource

fconfigure stdout -encoding utf-8
fconfigure stderr -encoding utf-8

proc usage {} {
  puts "usage: tclsh test-docir-odt.tcl ?-v? ?out.odt?"
  exit 1
}

set verbose 0
set outFile "docir-odt-test-output.odt"

foreach arg $argv {
  switch -- $arg {
    -v { set verbose 1 }
    default {
      if {$outFile eq "docir-odt-test-output.odt"} {
        set outFile $arg
      } else {
        usage
      }
    }
  }
}

package require Tcl 8.6
source [file join [file dirname [file normalize [info script]]] .. lib repos-path.tcl]
puts "pkg docir::odt: [package require docir::odt]"

proc ok {msg} {
  puts "ok   $msg"
}

proc fail {msg} {
  puts stderr "FAIL $msg"
  exit 1
}

proc check {condition msg} {
  # condition is a Tcl expression string evaluated in the caller scope.
  if {![uplevel 1 [list expr $condition]]} {
    fail $msg
  }
  ok $msg
}

proc slurpBytes {path} {
  set fh [open $path rb]
  fconfigure $fh -translation binary
  set data [read $fh]
  close $fh
  return $data
}

proc inline {type text args} {
  return [dict create type $type text $text {*}$args]
}

proc block {type content {meta {}}} {
  return [dict create type $type meta $meta content $content]
}

proc tableCell {content {meta {}}} {
  return [dict create type tableCell meta $meta content $content]
}

proc tableRow {cells {meta {}}} {
  return [dict create type tableRow meta $meta content $cells]
}

# Kleines 1x1 PNG, base64-kodiert.
# Reicht fuer den Test, ob docir::odt::write Media in Pictures/ einbetten kann.
set pngBytes [binary decode base64 {
  iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=
}]

set imageUrl "Pictures/test-dot.png"

# ----------------------------------------------------------------------
# DocIR aufbauen
# ----------------------------------------------------------------------

set ir {}

lappend ir [dict create type doc_meta meta {irSchemaVersion 1 title {docir::odt Test}} content {}]

lappend ir [block heading \
    [list [inline text "docir::odt Testdokument"]] \
    [dict create level 1 id docir-odt-testdokument]]

lappend ir [block paragraph [list \
    [inline text "Dies ist ein "] \
    [inline strong "fetter"] \
    [inline text " und "] \
    [inline emphasis "kursiver"] \
    [inline text " Absatz mit "] \
    [dict create type link text "Tcl/Tk-Link" href "https://www.tcl.tk/"] \
    [inline text "."]]]

lappend ir [block paragraph [list \
    [inline text "Linebreak-Test: Zeile 1"] \
    [dict create type linebreak] \
    [inline text "Zeile 2"] \
    [dict create type linebreak] \
    [inline text "Zeile 3"]]]

lappend ir [block pre \
    [list [inline text {package require docir::odt
  set ir {}
docir::odt::write $ir out.odt}]] \
    [dict create kind code]]

lappend ir [block list \
    [list \
        [dict create type listItem content [list [inline text "Listeneintrag A"]] meta {}] \
        [dict create type listItem content [list [inline text "Listeneintrag B"]] meta {}] \
        [dict create type listItem content [list [inline strong "Listeneintrag C fett"]] meta {}]] \
    [dict create kind ul indentLevel 0]]

lappend ir [block table \
    [list \
        [tableRow [list \
            [tableCell [list [inline text "Name"]]] \
            [tableCell [list [inline text "Typ"]]] \
            [tableCell [list [inline text "Notiz"]]]] \
            [dict create kind header]] \
        [tableRow [list \
            [tableCell [list [inline text "docir::odt"]]] \
            [tableCell [list [inline text "Senke"]]] \
            [tableCell [list [inline text "DocIR nach ODT"]]]] ] \
        [tableRow [list \
            [tableCell [list [inline text "docir::odtSource"]]] \
            [tableCell [list [inline text "Quelle"]]] \
            [tableCell [list [inline text "ODT nach DocIR"]]]] ]] \
    [dict create columns 3 alignments {left left left} hasHeader 1]]

lappend ir [block image {} [dict create url $imageUrl alt {kleines Testbild}]]

lappend ir [block heading \
    [list [inline text "Fazit"]] \
    [dict create level 2 id fazit]]

lappend ir [block paragraph [list \
    [inline text "Wenn diese Datei in LibreOffice geoeffnet werden kann, funktioniert die Grundsenke."]]]

# ----------------------------------------------------------------------
# Schreiben
# ----------------------------------------------------------------------

set media [dict create $imageUrl $pngBytes]

puts "DOCIR::ODT TEST"
puts "out: $outFile"
puts "blocks: [llength $ir]"
puts ""

if {[catch {
    docir::odt::write $ir $outFile [dict create media $media]
  } err opts]} {
  puts stderr $err
  puts stderr [dict get $opts -errorinfo]
  exit 1
}

check [file exists $outFile] "ODT-Datei wurde erstellt"
check {[file size $outFile] > 1000} "ODT-Datei ist groesser als 1000 Bytes"

set data [slurpBytes $outFile]
check {[string range $data 0 1] eq "PK"} "ODT ist ZIP-kompatibel"
check {[string first "application/vnd.oasis.opendocument.text" $data] >= 0} "mimetype ist enthalten"
check {[string first "content.xml" $data] >= 0} "content.xml ist im ZIP sichtbar"
check {[string first "styles.xml" $data] >= 0} "styles.xml ist im ZIP sichtbar"
check {[string first "META-INF/manifest.xml" $data] >= 0} "manifest.xml ist im ZIP sichtbar"
check {[string first $imageUrl $data] >= 0} "Bildpfad ist im ZIP/Manifest sichtbar"

# ----------------------------------------------------------------------
# Optional: Ruecklesen mit docir::odtSource
# ----------------------------------------------------------------------

puts ""
puts "OPTIONAL ROUNDTRIP"

puts "pkg docir::odt: [package require docir::odt]"
puts "pkg docir::odtSource: [package require docir::odtSource]"

set ir2 [docir::odtSource::fromOdt $outFile]
puts "roundtrip blocks: [llength $ir2]"

set counts {}
foreach b $ir2 {
  dict incr counts [dict get $b type]
}

foreach t [lsort [dict keys $counts]] {
  puts [format "  %-10s %s" $t [dict get $counts $t]]
}

check {[dict exists $counts heading]} "Ruecklesen: heading vorhanden"
check {[dict exists $counts paragraph]} "Ruecklesen: paragraph vorhanden"
check {[dict exists $counts table]} "Ruecklesen: table vorhanden"
check {[dict exists $counts image]} "Ruecklesen: image vorhanden"


puts ""
puts "RESULT: OK"
puts "created: $outFile"
exit 0

