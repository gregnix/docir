#!/usr/bin/env tclsh
# Minimal Test Framework for nroffparser/renderer tests

namespace eval test {
    variable tests {}
    variable passed 0
    variable failed 0
    variable skipped 0
    variable currentTest ""
    variable erwartet ""     ;# Soll-Zahl aus ::test::expect, leer = nicht gesetzt

    # Register a test
    proc test {name body} {
        lappend ::test::tests [list $name $body]
    }

    # Wie viele Tests diese Datei hat, wenn alles da ist.
    #
    # Der Grund, gemessen am 27.09.2026: test-docir-md.tcl meldete 67 Tests
    # ohne mdstack::parser und 92 mit ihm -- und beide Male "All tests
    # passed!". Ein Waechter der Form
    #
    #     if {[catch {package require X}]} { puts stderr "skipping" } else { ... }
    #
    # meldet die Tests im else-Zweig gar nicht erst an. Sie sind dann nicht
    # uebersprungen, sondern unsichtbar: der Skipped-Zaehler sieht sie nicht,
    # weil skip nur INNERHALB eines angemeldeten Tests wirkt. 51 Tests standen
    # in drei Dateien hinter solchen ifs.
    #
    # Diese Zeile ist das Soll. Weicht die angemeldete Zahl ab, sagt der Lauf
    # es -- und mit DOCIR_STRICT=1 (Freigabelauf) bricht er ab. Der
    # Entwicklerlauf bleibt gruen, aber nicht mehr stumm.
    proc expect {n} {
        variable erwartet
        set erwartet $n
    }

    # Skip the current test (e.g. an optional dependency is absent). Counted
    # as skipped, never as failed.
    proc skip {reason} { return -code error -errorcode DOCIR_SKIP $reason }
    
    # Assert that condition is true
    proc assert {condition {message ""}} {
        if {!$condition} {
            puts "  ✗ FAIL: $message"
            incr ::test::failed
            return 0
        }
        incr ::test::passed
        return 1
    }
    
    # Assert equality
    proc assertEqual {expected actual {message ""}} {
        if {$expected ne $actual} {
            puts "  ✗ FAIL: $message"
            puts "    Expected: $expected"
            puts "    Actual:   $actual"
            incr ::test::failed
            return 0
        }
        incr ::test::passed
        return 1
    }
    
    # Assert that list contains element
    proc assertContains {list element {message ""}} {
        set found [expr {[lsearch -exact $list $element] >= 0}]
        if {!$found} {
            puts "  ✗ FAIL: $message"
            puts "    List: $list"
            puts "    Missing: $element"
            incr ::test::failed
            return 0
        }
        incr ::test::passed
        return 1
    }
    
    # Assert AST node type
    proc assertNodeType {node expectedType {message ""}} {
        set actualType [dict get $node type]
        return [::test::assertEqual $expectedType $actualType "Node type: $message"]
    }
    
    # Assert that string contains substring
    proc assertContains {string substring {message ""}} {
        set found [expr {[string first $substring $string] >= 0}]
        if {!$found} {
            puts "  ✗ FAIL: $message"
            puts "    String: $string"
            puts "    Missing: $substring"
            incr ::test::failed
            return 0
        }
        incr ::test::passed
        return 1
    }
    
    # Run all tests
    proc runAll {} {
        variable tests
        variable passed
        variable failed
        variable skipped
        variable currentTest
        
        set passed 0
        set failed 0
        set skipped 0
        
        puts "Running [llength $tests] test(s)...\n"
        
        foreach testCase $tests {
            lassign $testCase name body
            set currentTest $name
            puts "Test: $name"
            
            if {[catch {
                uplevel 1 $body
            } err]} {
                if {[lindex $::errorCode 0] eq "DOCIR_SKIP"} {
                    puts "  ⊘ SKIP: $err"
                    incr skipped
                } else {
                    puts "  ✗ ERROR: $err"
                    puts "    $::errorInfo"
                    incr failed
                }
            }
            puts ""
        }
        
        variable erwartet
        set fehlen 0
        if {$erwartet ne "" && [llength $tests] < $erwartet} {
            set fehlen [expr {$erwartet - [llength $tests]}]
        }

        puts "=== Test Results ==="
        puts "Passed: $passed"
        puts "Failed: $failed"
        if {$skipped > 0} { puts "Skipped: $skipped" }
        puts "Total:  [expr {$passed + $failed}]"
        if {$fehlen} {
            puts "Nicht angemeldet: $fehlen von $erwartet -- ein Block fiel hinter\
                    einem if weg (fehlendes Modul?). Diese Tests sind NICHT gelaufen."
        }

        set streng [expr {[info exists ::env(DOCIR_STRICT)]
                && $::env(DOCIR_STRICT) ni {0 ""}}]

        if {$failed != 0} {
            puts "\n✗ Some tests failed!"
            return 1
        }
        # Bewusst nicht "$passed Tests": passed zaehlt Zusicherungen, nicht
        # Tests. Die Zahl, die hier zaehlt, ist die der nicht gelaufenen Tests.
        if {$fehlen && $streng} {
            puts "\n✗ keine Fehler, aber $fehlen Test(s) nicht gelaufen\
                    (DOCIR_STRICT)."
            return 1
        }
        if {$fehlen} {
            puts "\n✓ keine Fehler -- aber $fehlen Test(s) nicht gelaufen."
            return 0
        }
        puts "\n✓ All tests passed!"
        return 0
    }
    
    # Run a specific test suite
    proc runSuite {suiteName} {
        variable tests
        
        set suiteTests {}
        foreach testCase $tests {
            lassign $testCase name body
            if {[string match "$suiteName*" $name]} {
                lappend suiteTests $testCase
            }
        }
        
        if {[llength $suiteTests] == 0} {
            puts "No tests found for suite: $suiteName"
            return 1
        }
        
        set ::test::tests $suiteTests
        return [runAll]
    }
}

# Convenience aliases
proc test {name body} {
    ::test::test $name $body
}

proc skip {reason} { return -code error -errorcode DOCIR_SKIP $reason }

proc assert {condition {message ""}} {
    ::test::assert [uplevel 1 [list expr $condition]] $message
}

proc assertEqual {expected actual {message ""}} {
    ::test::assertEqual $expected $actual $message
}
