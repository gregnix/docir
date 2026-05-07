#!/usr/bin/env tclsh
# test-docir-svg.tcl
#
# Tests fuer docir-svg-0.1.tm — DocIR → SVG Renderer.
#
# Pruefen:
#  - Beide Modi: foreignObject und native
#  - SVG-Wrapper (xmlns, viewBox, width/height)
#  - foreignObject enthaelt HTML-Body
#  - Native: Block-Coverage (heading, paragraph, pre, list, table, hr, blank)
#  - Auto-Height-Berechnung
#  - XML-Escaping
#  - Defensive Behandlung

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

set projectRoot [file dirname [file dirname [file normalize [info script]]]]
lappend auto_path $projectRoot
package require docir::svg

# ============================================================
# A. SVG-Wrapper
# ============================================================

test "svg.wrapper_has_xmlns" {
    set ir [list [dict create type heading content {{type text text Hi}} meta {level 1}]]
    set out [docir::svg::render $ir]
    assert [string match "*xmlns=\"http://www.w3.org/2000/svg\"*" $out]
}

test "svg.standalone_has_xml_decl" {
    set ir [list [dict create type heading content {{type text text Hi}} meta {level 1}]]
    set out [docir::svg::render $ir]
    assert [string match "*<?xml version=*" $out] "xml declaration when standalone"
}

test "svg.no_xml_decl_when_not_standalone" {
    set ir [list [dict create type heading content {{type text text Hi}} meta {level 1}]]
    set out [docir::svg::render $ir [dict create standalone 0]]
    assert [expr {![string match "*<?xml*" $out]}] "no xml decl when standalone=0"
}

test "svg.viewBox_matches_dimensions" {
    set ir [list [dict create type heading content {{type text text Hi}} meta {level 1}]]
    set out [docir::svg::render $ir [dict create width 1000 height 500 mode native]]
    assert [string match "*width=\"1000\"*" $out]
    assert [string match "*height=\"500\"*" $out]
    assert [string match "*viewBox=\"0 0 1000 500\"*" $out]
}

test "svg.unknown_mode_errors" {
    set ir [list [dict create type heading content {{type text text Hi}} meta {level 1}]]
    set caught [catch {docir::svg::render $ir [dict create mode foobar]} err]
    assert $caught "unknown mode raises error"
    assert [string match "*foobar*" $err] "error message mentions bad mode"
}

# ============================================================
# B. foreignObject mode
# ============================================================

test "svg.foreignObject_has_foreignObject_element" {
    set ir [list [dict create type paragraph content {{type text text "hello"}} meta {}]]
    set out [docir::svg::render $ir]
    assert [string match "*<foreignObject*" $out]
}

test "svg.foreignObject_has_xhtml_namespace" {
    set ir [list [dict create type paragraph content {{type text text "hello"}} meta {}]]
    set out [docir::svg::render $ir]
    assert [string match "*xmlns=\"http://www.w3.org/1999/xhtml\"*" $out]
}

test "svg.foreignObject_contains_html_paragraph" {
    set ir [list [dict create type paragraph content {{type text text "hello"}} meta {}]]
    set out [docir::svg::render $ir]
    assert [string match "*<p>hello</p>*" $out] "html-paragraph in foreignObject"
}

test "svg.foreignObject_includes_style" {
    set ir [list [dict create type paragraph content {{type text text "x"}} meta {}]]
    set out [docir::svg::render $ir]
    assert [string match "*<style>*" $out] "style block present"
}

# ============================================================
# C. Native mode
# ============================================================

test "svg.native_no_foreignObject" {
    set ir [list [dict create type paragraph content {{type text text "hello"}} meta {}]]
    set out [docir::svg::render $ir [dict create mode native]]
    assert [expr {![string match "*<foreignObject*" $out]}] "no foreignObject in native"
    assert [expr {![string match "*xhtml*" $out]}] "no xhtml namespace"
}

test "svg.native_paragraph_uses_text_element" {
    set ir [list [dict create type paragraph content {{type text text "hello"}} meta {}]]
    set out [docir::svg::render $ir [dict create mode native]]
    assert [string match "*<text*hello*" $out] "native uses <text> element"
}

test "svg.native_heading_is_bold" {
    set ir [list [dict create type heading content {{type text text H}} meta {level 1}]]
    set out [docir::svg::render $ir [dict create mode native]]
    assert [string match "*font-weight=\"bold\"*" $out] "heading text bold"
}

test "svg.native_h1_has_underline" {
    set ir [list [dict create type heading content {{type text text H}} meta {level 1}]]
    set out [docir::svg::render $ir [dict create mode native]]
    # h1 hat eine line nach dem Text
    set lineCount [regexp -all "<line " $out]
    assert [expr {$lineCount >= 1}] "h1 has underline element"
}

test "svg.native_h3_no_underline" {
    set ir [list [dict create type heading content {{type text text H}} meta {level 3}]]
    set out [docir::svg::render $ir [dict create mode native]]
    # h3 hat KEINE underline
    assert [expr {![string match "*<line *" $out]}] "h3 no underline"
}

test "svg.native_pre_has_background" {
    set ir [list [dict create type pre content {{type text text "code line"}} meta {kind code}]]
    set out [docir::svg::render $ir [dict create mode native]]
    assert [string match "*<rect*fill=\"#f4f4f4\"*" $out] "pre has bg rect"
    assert [string match "*<text*code line*" $out] "pre text rendered"
}

test "svg.native_pre_uses_mono_font" {
    set ir [list [dict create type pre content {{type text text "x"}} meta {kind code}]]
    set out [docir::svg::render $ir [dict create mode native monoFamily "Courier"]]
    assert [string match "*font-family=\"Courier\"*" $out]
}

test "svg.native_hr_has_line" {
    set ir [list [dict create type hr content {} meta {}]]
    set out [docir::svg::render $ir [dict create mode native]]
    assert [string match "*<line *" $out] "hr produces line"
}

test "svg.native_list_ul_has_bullets" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "a"}} meta {kind ul}] \
        [dict create type listItem content {{type text text "b"}} meta {kind ul}] \
    ] meta {kind ul}]]
    set out [docir::svg::render $ir [dict create mode native]]
    # Bullet ist UTF-8 \u2022 (•). Pruefe ueber den Codepoint.
    set bullet "\u2022"
    set bulletCount [regexp -all $bullet $out]
    assert [expr {$bulletCount == 2}] "two bullet markers for two items (got $bulletCount)"
}

test "svg.native_list_ol_has_numbers" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "first"}} meta {kind ol}] \
        [dict create type listItem content {{type text text "second"}} meta {kind ol}] \
    ] meta {kind ol}]]
    set out [docir::svg::render $ir [dict create mode native]]
    assert [string match "*1. *" $out] "first item has '1.' marker"
    assert [string match "*2. *" $out] "second item has '2.' marker"
}

test "svg.native_list_dl_term_bold" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "definition"}} \
            meta [dict create kind dl term {{type text text "term"}}]] \
    ] meta {kind dl}]]
    set out [docir::svg::render $ir [dict create mode native]]
    # term ist fett, definition normal
    assert [string match "*font-weight=\"bold\"*term*" $out]
    assert [string match "*definition*" $out]
}

test "svg.native_table_renders_cells" {
    set ir [list [dict create type table content [list \
        [dict create type tableRow content [list \
            [dict create type tableCell content {{type text text "a"}} meta {}] \
            [dict create type tableCell content {{type text text "b"}} meta {}] \
        ] meta {}] \
    ] meta {columns 2 hasHeader 0}]]
    set out [docir::svg::render $ir [dict create mode native]]
    assert [string match "*<text*>a*" $out]
    assert [string match "*<text*>b*" $out]
}

test "svg.native_table_header_has_background" {
    set ir [list [dict create type table content [list \
        [dict create type tableRow content [list \
            [dict create type tableCell content {{type text text "h"}} meta {}] \
        ] meta {}] \
        [dict create type tableRow content [list \
            [dict create type tableCell content {{type text text "v"}} meta {}] \
        ] meta {}] \
    ] meta {columns 1 hasHeader 1}]]
    set out [docir::svg::render $ir [dict create mode native]]
    # rect mit fill für header-row
    assert [string match "*<rect*fill=\"#f4f4f4\"*" $out]
}

# ============================================================
# D. Auto-height-Berechnung
# ============================================================

test "svg.native_autoheight_grows_with_content" {
    set ir1 [list [dict create type paragraph content {{type text text "x"}} meta {}]]
    set ir2 [list \
        [dict create type paragraph content {{type text text "x"}} meta {}] \
        [dict create type paragraph content {{type text text "y"}} meta {}] \
        [dict create type paragraph content {{type text text "z"}} meta {}]]
    set h1 [_extractHeight [docir::svg::render $ir1 [dict create mode native]]]
    set h2 [_extractHeight [docir::svg::render $ir2 [dict create mode native]]]
    assert [expr {$h2 > $h1}] "more content → larger height ($h2 > $h1)"
}

test "svg.native_explicit_height_respected" {
    set ir [list [dict create type paragraph content {{type text text "x"}} meta {}]]
    set out [docir::svg::render $ir [dict create mode native height 999]]
    assert [string match "*height=\"999\"*" $out]
}

# Helper: Höhe aus SVG-Output extrahieren
proc _extractHeight {svg} {
    if {[regexp {height="(\d+)"} $svg -> h]} { return $h }
    return 0
}

# ============================================================
# E. XML-Escaping
# ============================================================

test "svg.native_escapes_lt_gt" {
    set ir [list [dict create type paragraph content {{type text text "a<b>c"}} meta {}]]
    set out [docir::svg::render $ir [dict create mode native]]
    assert [string match "*a&lt;b&gt;c*" $out]
}

test "svg.native_escapes_amp" {
    set ir [list [dict create type paragraph content {{type text text "x & y"}} meta {}]]
    set out [docir::svg::render $ir [dict create mode native]]
    assert [string match "*x &amp; y*" $out]
}

test "svg.foreignObject_escapes_too" {
    # foreignObject geht durch docir-html — Escaping kommt von dort
    set ir [list [dict create type paragraph content {{type text text "a<b>"}} meta {}]]
    set out [docir::svg::render $ir]
    assert [string match "*a&lt;b&gt;*" $out]
}

# ============================================================
# F. Defensive Behandlung
# ============================================================

test "svg.native_unknown_block_no_crash" {
    set ir [list [dict create type weirdtype content {} meta {}]]
    set out [docir::svg::render $ir [dict create mode native]]
    assert [string match "*unknown type: weirdtype*" $out]
}

test "svg.native_blank_no_content_field" {
    set ir [list [dict create type blank meta {lines 1}]]
    set caught [catch {docir::svg::render $ir [dict create mode native]} err]
    assert [expr {!$caught}] "blank without content does not crash: $err"
}

test "svg.native_schema_violation_no_crash" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "ok"}} meta {kind ul}] \
        [dict create type list content {} meta {kind ul}] \
    ] meta {kind ul}]]
    set caught [catch {docir::svg::render $ir [dict create mode native]} err]
    assert [expr {!$caught}] "list-in-list-content does not crash: $err"
    set out [docir::svg::render $ir [dict create mode native]]
    assert [string match "*schema warning*" $out] "warning surfaces in output"
}

# ============================================================
# G. Volle Pipeline
# ============================================================

test "svg.full_pipeline_nroff_native" {
    package require nroffparser
    package require docir::roffSource

    set nroff {.TH foo n 1.0 Test
.SH NAME
foo \- a test
.SH SYNOPSIS
\fBfoo\fR \fIarg\fR
}
    set ast [nroffparser::parse $nroff]
    set ir  [docir::roff::fromAst $ast]
    set out [docir::svg::render $ir [dict create mode native width 600]]

    assert [string match "*<svg*" $out]
    assert [string match "*NAME*" $out]
    assert [string match "*SYNOPSIS*" $out]
}

test "svg.full_pipeline_nroff_foreignObject" {
    package require nroffparser
    package require docir::roffSource

    set nroff {.TH foo n 1.0 Test
.SH NAME
foo \- test
}
    set ast [nroffparser::parse $nroff]
    set ir  [docir::roff::fromAst $ast]
    set out [docir::svg::render $ir [dict create width 600 height 300]]

    assert [string match "*<foreignObject*" $out]
    assert [string match "*<h1*NAME*" $out]
}

# ============================================================
# Spec 0.5: Tests für neue Block-Typen in docir-svg
# ============================================================
#
# Hinweis: Inline-Typen werden im SVG-Native-Mode flach gerendert
# (das war für strong/emphasis schon immer so). Die Inline-
# Erweiterungen (strike, image, etc.) werden im foreignObject-Mode
# automatisch via docir-html korrekt behandelt — getestet dort.

test "svg.block.image_native_mode" {
    set ir [list [dict create type image content {} \
        meta [dict create url "test.png" alt "Test caption"]]]
    set svg [::docir::svg::render $ir [dict create mode native standalone 0]]
    # SVG sollte ein <image>-Element haben
    assert [expr {[string first {<image} $svg] >= 0}]
    # Caption als Text-Element drunter
    assert [expr {[string first {Test caption} $svg] >= 0}]
}

test "svg.block.footnote_section_native" {
    set ir [list [dict create type footnote_section \
        content [list \
            [dict create type footnote_def \
                content [list [dict create type text text "Note text."]] \
                meta [dict create id "fn1" num "1"]]] \
        meta {}]]
    set svg [::docir::svg::render $ir [dict create mode native standalone 0]]
    # Footnote-Number + Body als Text
    assert [expr {[string first {[1]} $svg] >= 0}]
    assert [expr {[string first {Note text.} $svg] >= 0}]
}

test "svg.block.div_transparent_native" {
    # div sollte children transparent durchreichen
    set ir [list [dict create type div \
        content [list [dict create type paragraph \
            content [list [dict create type text text "in div"]] meta {}]] \
        meta [dict create class "warning"]]]
    set svg [::docir::svg::render $ir [dict create mode native standalone 0]]
    assert [expr {[string first {in div} $svg] >= 0}]
}

test "svg.foreignObject_inherits_html" {
    # Im foreignObject-Mode kommt ALLES vom docir-html
    set ir [list [dict create type paragraph \
        content [list [dict create type strike text "deleted"]] meta {}]]
    set svg [::docir::svg::render $ir [dict create standalone 0]]
    # foreignObject embeddet HTML — <s>-Tag muss drin sein
    assert [expr {[string first {<s>deleted</s>} $svg] >= 0}]
}

test::runAll
