#!/usr/bin/env tclsh
## odt-roundtrip-test.tcl  --  Snapshot-Test fuer ODT -> DocIR -> Senken
##
## Pro .odt: DocIR via docir::odtSource bauen, validieren, dann mit den
## Senken md/txt/html rendern und gegen Soll-Dateien (golden/) diffen.
##
## Nutzung:
##   tclsh odt-roundtrip-test.tcl ?--update? ?ODT-DIR? ?GOLDEN-DIR?
##     --update     Soll-Dateien (neu) schreiben statt vergleichen
##     ODT-DIR      Verzeichnis mit *.odt   (Default: .)
##     GOLDEN-DIR   Verzeichnis der Snapshots (Default: ./golden)
##
## tm-Pfade:
##   - Skriptverzeichnis (fuer odt-*.tm und odtSource-*.tm)
##   - $env(DOCIR_TM)  -> docir/lib/tm  (Pflicht, falls docir nicht im Pfad)

fconfigure stdout -encoding utf-8
fconfigure stderr -encoding utf-8

    package require docir
    package require docir::md
    package require docir::txt
    package require docir::html

    package require docir::odtSource
# wenn flach abgelegt; im Repo liegt es als docir/odtSource-0.1.tm)
if {[catch {package require docir::odtSource}]} {
    set cand [lsort [glob -nocomplain -directory $here odtSource-*.tm]]
    if {[llength $cand] == 0} { puts stderr "odtSource-*.tm nicht gefunden"; exit 2 }
    source -encoding utf-8 [lindex $cand end]
}

## --- Argumente ---
set update 0
set rest {}
foreach a $argv {
    if {$a eq "--update"} { set update 1 } else { lappend rest $a }
}
set odtDir    [expr {[llength $rest] > 0 ? [lindex $rest 0] : "."}]
set goldenDir [expr {[llength $rest] > 1 ? [lindex $rest 1] : [file join $odtDir golden]}]
file mkdir $goldenDir

set sinks {md docir::md::render txt docir::txt::render html docir::html::render}

proc slurp {path} {
    set fh [open $path rb]; set d [read $fh]; close $fh
    return [encoding convertfrom utf-8 $d]
}
proc spit {path s} {
    set fh [open $path wb]; puts -nonewline $fh [encoding convertto utf-8 $s]; close $fh
}

set odts [lsort [glob -nocomplain -directory $odtDir *.odt]]
if {[llength $odts] == 0} { puts "Keine *.odt in $odtDir"; exit 0 }

set nPass 0; set nFail 0; set nWrite 0; set nInvalid 0
set hasDiff [expr {![catch {exec diff --version}]}]

foreach odt $odts {
    set base [file rootname [file tail $odt]]
    if {[catch {docir::odtSource::fromOdt $odt} ir]} {
        puts "✗ $base : fromOdt FEHLER: $ir"; incr nFail; continue
    }
    set verr [docir::validate $ir]
    if {$verr ne ""} {
        puts "✗ $base : DocIR INVALID: $verr"; incr nInvalid; incr nFail; continue
    }
    puts "• $base  ([llength $ir] Bloecke, valid)"

    foreach {ext renderProc} $sinks {
        if {[catch {$renderProc $ir} out]} {
            puts "    ✗ $ext : render FEHLER: $out"; incr nFail; continue
        }
        set gf [file join $goldenDir $base.$ext]
        if {$update || ![file exists $gf]} {
            spit $gf $out
            puts "    ✎ $ext : geschrieben"; incr nWrite; continue
        }
        set want [slurp $gf]
        if {$out eq $want} {
            puts "    ✓ $ext"; incr nPass
        } else {
            incr nFail
            puts "    ✗ $ext : weicht ab"
            if {$hasDiff} {
                set tmp [file join [file dirname $gf] .$base.$ext.actual]
                spit $tmp $out
                set d ""
                catch {exec sh -c {diff -u "$1" "$2" || true} -- $gf $tmp} d
                # nur die ersten 15 Diff-Zeilen zeigen
                set dl [lrange [split $d \n] 0 14]
                foreach line $dl { puts "      $line" }
                file delete $tmp
            }
        }
    }
}

puts "------------------------------------------"
puts "PASS $nPass   FAIL $nFail   WRITE $nWrite   INVALID $nInvalid   ([llength $odts] Dateien)"
exit [expr {$nFail > 0 ? 1 : 0}]
