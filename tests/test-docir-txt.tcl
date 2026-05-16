#!/usr/bin/env tclsh
# test-docir-txt.tcl -- Smoke-tests fuer docir::txt
#
# Run: tclsh test-docir-txt.tcl

if {![info exists ::_setup_done]} {
    lappend ::auto_path [file normalize [file join [file dirname [info script]] .. lib tm]]
    ::tcl::tm::path add [file normalize [file join [file dirname [info script]] .. lib tm]]
    set ::_setup_done 1
}

package require tcltest
namespace import ::tcltest::*

package require docir 0.1
package require docir::txt 0.1

# --- Helpers ---

proc heading {level text} {
    return [dict create type heading content \
        [list [dict create type text text $text]] \
        meta [dict create level $level]]
}

proc paragraph {text} {
    return [dict create type paragraph content \
        [list [dict create type text text $text]] \
        meta {}]
}

# --- Basic ---

test txt-1 "heading level 1 ALLCAPS underline" -body {
    set ir [list [heading 1 "Title"]]
    set out [docir::txt::render $ir]
    # First two lines: TITLE and ===
    set lines [split $out "\n"]
    list [lindex $lines 0] [lindex $lines 1]
} -result {TITLE =====}

test txt-2 "heading level 2 underline ---" -body {
    set ir [list [heading 2 "Sub"]]
    set out [docir::txt::render $ir]
    set lines [split $out "\n"]
    list [lindex $lines 0] [lindex $lines 1]
} -result {Sub ---}

test txt-3 "paragraph plain text" -body {
    set ir [list [paragraph "Hello world."]]
    set out [docir::txt::render $ir]
    string trim $out
} -result {Hello world.}

test txt-4 "strong/emphasis inline markers" -body {
    set ir [list [dict create type paragraph content [list \
        [dict create type text text "A "] \
        [dict create type strong text "bold"] \
        [dict create type text text " and "] \
        [dict create type emphasis text "soft"] \
        [dict create type text text " word."]] meta {}]]
    string trim [docir::txt::render $ir]
} -result {A *bold* and _soft_ word.}

test txt-5 "link as 'text (url)'" -body {
    set ir [list [dict create type paragraph content [list \
        [dict create type text text "See "] \
        [dict create type link text "site" url "https://example.com"] \
        [dict create type text text "."]] meta {}]]
    string trim [docir::txt::render $ir]
} -result "See site (https://example.com)."

test txt-6 "ul list with bullets" -body {
    set items {}
    foreach t {one two three} {
        lappend items [dict create type listItem content \
            [list [dict create type text text $t]] \
            meta [dict create kind ul]]
    }
    set ir [list [dict create type list content $items \
        meta [dict create kind ul]]]
    set lines [split [string trim [docir::txt::render $ir]] "\n"]
    set lines
} -result {{- one} {- two} {- three}}

test txt-7 "ol list with numbers" -body {
    set items {}
    foreach t {alpha beta} {
        lappend items [dict create type listItem content \
            [list [dict create type text text $t]] \
            meta [dict create kind ol]]
    }
    set ir [list [dict create type list content $items \
        meta [dict create kind ol]]]
    set lines [split [string trim [docir::txt::render $ir]] "\n"]
    set lines
} -result {{1. alpha} {2. beta}}

test txt-8 "code block indented" -body {
    set ir [list [dict create type pre \
        content "set x 1\nputs \$x" \
        meta [dict create kind code language tcl]]]
    string trimright [docir::txt::render $ir] "\n"
} -result "    set x 1\n    puts \$x"

test txt-9 "math block as dollar-dollar" -body {
    set ir [list [dict create type pre \
        content "x = y + z" \
        meta [dict create kind math display 1]]]
    string trim [docir::txt::render $ir]
} -result "\$\$\nx = y + z\n\$\$"

test txt-10 "empty doc_header skipped" -body {
    set ir [list \
        [dict create type doc_meta content {} \
            meta [dict create irSchemaVersion 1]] \
        [dict create type doc_header content {} \
            meta [dict create name {} section {} version {} part {}]] \
        [paragraph "Body."]]
    string trim [docir::txt::render $ir]
} -result {Body.}

test txt-11 "hr renders as line" -body {
    set ir [list [dict create type hr content {} meta {}]]
    set lines [split [string trim [docir::txt::render $ir]] "\n"]
    # First line should be all dashes
    set first [lindex $lines 0]
    regexp {^-+$} $first
} -result {1}

test txt-12 "table renders as ASCII" -body {
    set ir [list [dict create type table content [list \
        [dict create type tableRow content [list \
            [dict create type tableCell content [list \
                [dict create type text text "A"]] meta {}] \
            [dict create type tableCell content [list \
                [dict create type text text "B"]] meta {}]] meta {}] \
        [dict create type tableRow content [list \
            [dict create type tableCell content [list \
                [dict create type text text "1"]] meta {}] \
            [dict create type tableCell content [list \
                [dict create type text text "22"]] meta {}]] meta {}]] \
        meta [dict create hasHeader 1]]]
    set out [docir::txt::render $ir]
    # Check that pipes + separator are there (column widths from max)
    expr {[string match "*| A | B  |*" $out] \
       && [string match "*| 1 | 22 |*" $out] \
       && [string match "*|---|----|*" $out]}
} -result {1}

test txt-13 "math inline" -body {
    set ir [list [dict create type paragraph content [list \
        [dict create type text text "Use "] \
        [dict create type math text "x+y" display 0] \
        [dict create type text text " here."]] meta {}]]
    string trim [docir::txt::render $ir]
} -result {Use x+y here.}

test txt-14 "footnote_ref renders" -body {
    set ir [list [dict create type paragraph content [list \
        [dict create type text text "Claim"] \
        [dict create type footnote_ref id "1" text "1"]] meta {}]]
    string trim [docir::txt::render $ir]
} -result "Claim\[^1\]"

test txt-15 "image inline" -body {
    set ir [list [dict create type paragraph content [list \
        [dict create type text text "See "] \
        [dict create type image alt "diagram"]] meta {}]]
    string trim [docir::txt::render $ir]
} -result {See [image: diagram]}

cleanupTests
