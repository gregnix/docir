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
# Zaehlweise:
#   Primaer das Urteil ueber den Exit-Code (0 = ok, !=0 = Fehler).
#   Zaehler werden zusaetzlich aus der Ausgabe extrahiert, sofern
#   vorhanden -- erkannt werden "Passed:/Failed:" (test-framework) und
#   "PASS n / FAIL n" (odt-/html-/tksource-Tests). Fehlen Zaehler,
#   zaehlt die Datei als 1 Test (nach Exit-Code).
#
# Verwendung:
#   cd tests
#   tclsh run-all-tests.tcl      (the files run under this same interpreter)

set testDir [file dirname [file normalize [info script]]]

# Tcl 9 writes strictly: a "\u2713" on a stdout whose encoding cannot hold it
# (cp1252 into a pipe on Windows) is an error, not a "?".
catch {fconfigure stdout -profile replace}

# The child interpreter is the running one, not "tclsh" from PATH:
# started with tclsh9.0, the files ran under whatever "tclsh" was.
set tclInterp [info nameofexecutable]
proc wishInterp {} {
    set cand [file join [file dirname $::tclInterp] \
        [string map {tclsh wish} [file tail $::tclInterp]]]
    if {[file executable $cand]} { return $cand }
    return [auto_execok wish]
}

puts "=== Running All Tests ===\n"

# Headless-Tests (reiner tclsh-Subprozess)
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
    test-docir-renderer-frame.tcl
    test-docir-tilehtml.tcl
    test-docir-tilemd.tcl
    test-docir-odt.tcl
    test-odt-ol.tcl
    test-odt-ol2.tcl
    html-roundtrip-test.tcl
}

# GUI-Tests: brauchen Tk + Display, laufen mit wish und nur wenn $DISPLAY
# gesetzt ist (sonst uebersprungen).
set guiTestFiles {
    test-tksource.tcl
}

set totalPassed 0
set totalFailed 0
set failedFiles {}
set skippedFiles {}

# Eine Testdatei ausfuehren und (passed failed verdict) zurueckgeben.
# verdict: ok | fail | crash
proc runOne {interp testPath} {
    # -encoding utf-8: the test files are UTF-8; without it Tcl 8.6 on
    # Windows reads them as cp1252 and every umlaut literal is wrong.
    set rc [catch {exec {*}$interp -encoding utf-8 $testPath 2>@1} output]
    set p 0; set f 0; set have 0
    if {[regexp {Passed:\s+(\d+)} $output -> p]} {
        regexp {Failed:\s+(\d+)} $output -> f; set have 1
    } elseif {[regexp {PASS\s+(\d+)} $output -> p]} {
        regexp {FAIL\s+(\d+)} $output -> f; set have 1
    }
    if {!$have} {
        # keine Zaehler -> nach Exit-Code werten
        if {$rc == 0} { set p 1; set f 0 } else { set p 0; set f 1 }
    }
    set verdict [expr {($rc != 0 || $f > 0) ? "fail" : "ok"}]
    if {$rc != 0 && !$have} { set verdict "crash" }
    # the optional odf packages are missing: not a failure of docir
    if {$verdict eq "crash" && [regexp {can't find package odf::|FEHLT: docir::odt} $output]} {
        set verdict "skip"
        set p 0 ; set f 0
    }
    return [list $p $f $verdict $output]
}

foreach testFile $testFiles {
    set testPath [file join $testDir $testFile]
    if {![file exists $testPath]} {
        puts "⚠️  Skipping $testFile (not found)"
        continue
    }
    puts "Running $testFile..."
    lassign [runOne $tclInterp $testPath] p f verdict output
    incr totalPassed $p
    incr totalFailed $f
    switch -- $verdict {
        crash { lappend failedFiles "${testFile} (crashed)"; puts "  ✗ CRASHED:"; puts $output }
        fail  { lappend failedFiles $testFile; puts $output }
        skip  { lappend skippedFiles $testFile; puts "  SKIP: odf packages not found (optional)" }
        ok    { puts "  ✓ $p/[expr {$p + $f}] tests passed" }
    }
    puts ""
}

# --- Optionale GUI-Tests ---
if {[info exists ::env(DISPLAY)] && $::env(DISPLAY) ne ""} {
    set wish [wishInterp]
    if {$wish ne ""} {
        foreach testFile $guiTestFiles {
            set testPath [file join $testDir $testFile]
            if {![file exists $testPath]} { continue }
            puts "Running $testFile (GUI/wish)..."
            lassign [runOne $wish $testPath] p f verdict output
            incr totalPassed $p
            incr totalFailed $f
            switch -- $verdict {
                crash { lappend failedFiles "${testFile} (crashed)"; puts "  ✗ CRASHED:"; puts $output }
                fail  { lappend failedFiles $testFile; puts $output }
                skip  { lappend skippedFiles $testFile; puts "  SKIP: odf packages not found (optional)" }
                ok    { puts "  ✓ $p/[expr {$p + $f}] tests passed" }
            }
            puts ""
        }
    }
} else {
    puts "ℹ️  GUI-Tests uebersprungen (kein DISPLAY): $guiTestFiles"
    puts "   -> manuell: wish test-tksource.tcl  (oder xvfb-run -a wish ...)\n"
}

puts [string repeat "=" 40]
puts "Gesamtergebnis:"
puts "  Passed: $totalPassed"
puts "  Failed: $totalFailed"
puts "  Total:  [expr {$totalPassed + $totalFailed}]"
if {[llength $skippedFiles]} {
    puts "  Skipped files (odf missing): [join $skippedFiles {, }]"
}
puts ""

if {[llength $failedFiles] == 0} {
    puts "✓ Alle Tests bestanden!"
    exit 0
} else {
    puts "✗ Fehlgeschlagene Dateien:"
    foreach f $failedFiles { puts "  - $f" }
    exit 1
}
