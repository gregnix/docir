#!/usr/bin/env tclsh
# run-all-tests.tcl - Sammel-Runner für alle Unit-Tests
#
# WAS DAS HIER MACHT (vs. run-manpage-tests.tcl):
#   Führt jede test-*.tcl-Datei in einem eigenen Sub-Prozess aus,
#   sammelt die Pass/Fail-Zähler und meldet die Gesamtsumme. Das
#   ist der CI-taugliche Lauf — eine grüne Antwort heißt: alle
#   Unit-Tests durch.
#
# WAS DAS HIER NICHT MACHT:
#   Parst KEINE *.man/*.n-Beispieldateien. Dafür
#   run-manpage-tests.tcl benutzen.
#
# Verwendung:
#   cd tests
#   tclsh run-all-tests.tcl

set testDir [file dirname [file normalize [info script]]]

puts "=== Running All Tests ===\n"

set testFiles {
    test-validator.tcl
    test-mdstack-bridge.tcl
    test-docir.tcl
    test-docir-html.tcl
    test-docir-svg.tcl
    test-docir-pdf.tcl
    test-docir-canvas.tcl
    test-docir-md.tcl
    test-docir-roff.tcl
    test-docir-sinks-schema-blocks.tcl
    test-docir-schema-version.tcl
    test-docir-table-alignments.tcl
    test-docir-tilepdf.tcl
    test-docir-list-indent.tcl
    test-docir-tilehtml.tcl
    test-docir-tilemd.tcl
}

set totalPassed 0
set totalFailed 0
set failedFiles {}

foreach testFile $testFiles {
    set testPath [file join $testDir $testFile]
    if {![file exists $testPath]} {
        puts "⚠️  Skipping $testFile (not found)"
        continue
    }

    puts "Running $testFile..."
    # Crashende Tests duerfen den Runner nicht stoppen -- mit catch
    # fangen und als "Failed: 1, Crashed" zaehlen.
    set rc [catch {exec tclsh $testPath 2>@1} output]

    # Passed/Failed aus Ausgabe extrahieren
    set p 0; set f 0
    regexp {Passed:\s+(\d+)} $output -> p
    regexp {Failed:\s+(\d+)} $output -> f
    incr totalPassed $p
    incr totalFailed $f

    if {$rc != 0 && $p == 0 && $f == 0} {
        # Crash ohne Passed/Failed-Markers -- als 1 Fail zaehlen
        incr totalFailed
        lappend failedFiles "${testFile} (crashed)"
        puts "  ✗ CRASHED:"
        puts $output
    } elseif {$f > 0} {
        lappend failedFiles $testFile
        puts $output
    } else {
        puts "  ✓ $p/$p tests passed"
    }
    puts ""
}

puts [string repeat "=" 40]
puts "Gesamtergebnis:"
puts "  Passed: $totalPassed"
puts "  Failed: $totalFailed"
puts "  Total:  [expr {$totalPassed + $totalFailed}]"
puts ""

if {[llength $failedFiles] == 0} {
    puts "✓ Alle Tests bestanden!"
    exit 0
} else {
    puts "✗ Fehlgeschlagene Dateien:"
    foreach f $failedFiles { puts "  - $f" }
    exit 1
}
