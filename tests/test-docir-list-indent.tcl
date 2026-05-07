#!/usr/bin/env tclsh
# test-docir-list-indent.tcl -- list.indentLevel Coverage in Sinks
#
# Hintergrund: Spec dokumentiert list.indentLevel. Sinks werden in zwei
# Klassen geteilt:
#   - "ehrliche" Sinks (md, pdf, roff, html, rendererTk): respektieren
#     indentLevel mit messbarem Output-Unterschied
#   - "visuelle" Sinks (canvas, svg, tilepdf): best-effort, ignorieren
#     indentLevel (Layout passt nicht zu beliebigen Tiefen)

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

# Helper: minimale list-IR mit gegebenem indentLevel
proc listIr {indentLevel kind} {
    return [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type list content [list \
            [dict create type listItem content [list \
                [dict create type text text "First Item" meta {}]] meta {}] \
            [dict create type listItem content [list \
                [dict create type text text "Second Item" meta {}]] meta {}] \
        ] meta [dict create kind $kind indentLevel $indentLevel]]]
}

# ============================================================
# md-Sink: indentLevel als 2-Space-Prefix pro Level
# ============================================================

if {[catch {package require docir::md}] == 0} {
    test "md.list.indent_0_no_prefix" {
        set md [::docir::md::render [listIr 0 ul]]
        assert [regexp {^- First Item} $md] "indent=0 sollte ohne Prefix sein"
    }

    test "md.list.indent_1_two_spaces" {
        set md [::docir::md::render [listIr 1 ul]]
        assert [regexp {^  - First Item} $md] \
            "indent=1 sollte mit 2 Spaces beginnen, war: [string range $md 0 30]"
    }

    test "md.list.indent_3_six_spaces" {
        set md [::docir::md::render [listIr 3 ul]]
        assert [regexp {^      - First Item} $md] \
            "indent=3 sollte mit 6 Spaces beginnen"
    }

    test "md.list.indent_ol_numbered" {
        set md [::docir::md::render [listIr 2 ol]]
        assert [regexp {^    1\. First Item} $md] \
            "ol indent=2 sollte '    1. First Item' sein"
    }
}

if {[catch {package require pdf4tcl}]    == 0 && \
    [catch {package require pdf4tcllib}] == 0 && \
    [catch {package require docir::pdf}] == 0} {
    test "pdf.list.indent_renders_no_error" {
        set tmpDir [file join [pwd] tmp-pdf-indent]
        file mkdir $tmpDir
        set out [file join $tmpDir indent.pdf]
        ::docir::pdf::render [listIr 2 ul] $out
        assert [file exists $out] "PDF wurde erzeugt"
        assert [expr {[file size $out] > 500}] "PDF nicht trivially leer"
        file delete -force $tmpDir
    }
}

if {[catch {package require docir::roff}] == 0} {
    test "roff.list.indent_0_no_rs" {
        set roff [::docir::roff::render [listIr 0 tp]]
        assert [expr {![regexp {\.RS} $roff]}] "indent=0 sollte kein .RS haben"
    }

    test "roff.list.indent_2_two_rs_pairs" {
        set roff [::docir::roff::render [listIr 2 tp]]
        set rsCount [regexp -all {\.RS } $roff]
        set reCount [regexp -all {\.RE} $roff]
        assertEqual 2 $rsCount
        assertEqual 2 $reCount
    }

    test "roff.list.indent_3_three_rs_pairs" {
        set roff [::docir::roff::render [listIr 3 tp]]
        set rsCount [regexp -all {\.RS } $roff]
        assertEqual 3 $rsCount
    }
}

if {[catch {package require docir::html}] == 0} {
    test "html.list.indent_2_uses_indent_class" {
        set html [::docir::html::render [listIr 2 ul]]
        assert [regexp {indent-2} $html] "html mit indent=2 sollte 'indent-2' Klasse haben"
    }
}

test::runAll
