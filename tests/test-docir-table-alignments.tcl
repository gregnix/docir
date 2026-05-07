#!/usr/bin/env tclsh
# test-docir-table-alignments.tcl
#
# Regression-Tests fuer A.4 / Drift-Fix: alignments-Feld in
# table-Block muss in HTML- und MD-Renderer verarbeitet werden.

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

# Helper: minimale Tabelle mit 3 Spalten und alignments
proc tableWithAlignments {alignments} {
    set row1 [dict create type tableRow content [list \
        [dict create type tableCell content [list [dict create type text value "A" meta {}]] meta {}] \
        [dict create type tableCell content [list [dict create type text value "B" meta {}]] meta {}] \
        [dict create type tableCell content [list [dict create type text value "C" meta {}]] meta {}] \
    ] meta {}]
    set row2 [dict create type tableRow content [list \
        [dict create type tableCell content [list [dict create type text value "1" meta {}]] meta {}] \
        [dict create type tableCell content [list [dict create type text value "2" meta {}]] meta {}] \
        [dict create type tableCell content [list [dict create type text value "3" meta {}]] meta {}] \
    ] meta {}]
    return [list \
        [dict create type table content [list $row1 $row2] meta [dict create \
            columns 3 \
            alignments $alignments \
            hasHeader 1]]]
}

# ============================================================
# A. HTML — alignments via colgroup + style
# ============================================================

test "html.alignments.colgroup_emitted" {
    set ir [tableWithAlignments {left center right}]
    set html [::docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<colgroup>*" $html] "colgroup-Element fehlt"
    assert [string match "*text-align:left*" $html] "left alignment fehlt"
    assert [string match "*text-align:center*" $html] "center alignment fehlt"
    assert [string match "*text-align:right*" $html] "right alignment fehlt"
}

test "html.alignments.cell_style_inline" {
    set ir [tableWithAlignments {left center right}]
    set html [::docir::html::render $ir [dict create standalone 0]]
    # Per-Cell-Alignment-Style sollte auch in <th>/<td> sein
    set leftCount [regexp -all {style="text-align:left"} $html]
    assert [expr {$leftCount >= 2}] "left-aligned Cells: erwartet >=2 (Header+Body), got $leftCount"
}

test "html.alignments.empty_list_no_colgroup" {
    set ir [tableWithAlignments {}]
    set html [::docir::html::render $ir [dict create standalone 0]]
    assert [expr {[string first "<colgroup>" $html] == -1}] \
        "Bei leerer alignments-Liste sollte kein colgroup emittiert werden"
}

test "html.alignments.partial_list" {
    # Nur 2 Werte fuer 3 Spalten — der Rest bleibt unstyled
    set ir [tableWithAlignments {center right}]
    set html [::docir::html::render $ir [dict create standalone 0]]
    assert [string match "*text-align:center*" $html] "center fehlt"
    assert [string match "*text-align:right*" $html] "right fehlt"
}

test "html.alignments.unknown_value_falls_back" {
    set ir [tableWithAlignments {left bogus right}]
    set html [::docir::html::render $ir [dict create standalone 0]]
    assert [string match "*text-align:left*" $html] "left fehlt"
    assert [string match "*text-align:right*" $html] "right fehlt"
    # bogus sollte als plain <col/> ohne style erscheinen
    assert [string match "*<col/>*" $html] "fallback <col/> fehlt fuer unbekannten Wert"
}

# ============================================================
# B. MD — alignments via :---: Syntax
# ============================================================

test "md.alignments.left_syntax" {
    set ir [tableWithAlignments {left left left}]
    set md [::docir::md::render $ir]
    assert [string match "*:---*" $md] "left alignment :--- fehlt"
}

test "md.alignments.center_syntax" {
    set ir [tableWithAlignments {center center center}]
    set md [::docir::md::render $ir]
    assert [string match "*:---:*" $md] "center alignment :---: fehlt"
}

test "md.alignments.right_syntax" {
    set ir [tableWithAlignments {right right right}]
    set md [::docir::md::render $ir]
    assert [string match "*---:*" $md] "right alignment ---: fehlt"
}

test "md.alignments.mixed" {
    set ir [tableWithAlignments {left center right}]
    set md [::docir::md::render $ir]
    # Erwartet: | :--- | :---: | ---: |
    assert [string match "*:---*:---:*---:*" $md] \
        "Mixed alignments-Reihenfolge in Separator falsch: $md"
}

test "md.alignments.empty_falls_back_to_default" {
    set ir [tableWithAlignments {}]
    set md [::docir::md::render $ir]
    # Erwartet: | --- | --- | --- | (default)
    assert [string match "*--- |*" $md] "default --- separator fehlt"
    assert [expr {[string first ":---" $md] == -1}] \
        "Bei leerer alignments-Liste sollten keine :--- vorkommen"
}

test "md.alignments.unknown_value_falls_back" {
    set ir [tableWithAlignments {left bogus right}]
    set md [::docir::md::render $ir]
    assert [string match "*:--- |*" $md] "left :--- fehlt"
    assert [string match "*---: |*" $md] "right ---: fehlt"
    # bogus → " --- |" (plain default)
}

test::runAll
