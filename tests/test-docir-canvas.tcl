#!/usr/bin/env tclsh
# test-docir-canvas.tcl
#
# Tests fuer docir-canvas-0.1.tm — DocIR → Tk-Canvas Renderer.
#
# Tk-abhaengig: skippt sich selbst wenn keine Display-Verbindung
# moeglich ist (CI ohne Display).
#
# Pruefen:
#  - Render erzeugt Canvas-Items
#  - Block-Coverage (heading, paragraph, pre, list, table, hr, blank)
#  - Tag-basiertes Cleanup via clear
#  - Schema-Verletzungen werden sichtbar (kein Crash)

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

set projectRoot [file dirname [file dirname [file normalize [info script]]]]
lappend auto_path $projectRoot

# Tk laden — wenn kein Display da ist, alle Tests skippen
set hasTk [expr {![catch {package require Tk}]}]
if {!$hasTk} {
    puts "Note: Tk not available (no display) — canvas tests will be skipped"
    test::runAll
    exit 0
}

package require docir::canvas

# Ein Top-Level-Canvas fuer alle Tests
set tw [toplevel .docirCanvasTest]
wm withdraw $tw
set ::testCanvas [canvas $tw.c -width 600 -height 800 -bg white]
pack $::testCanvas

proc resetCanvas {} {
    docir::canvas::clear $::testCanvas
}

# ============================================================
# A. Modul-Loading und API
# ============================================================

test "canvas.module_loaded" {
    assert [string length [package present docir::canvas]] "version present"
}

test "canvas.public_api_present" {
    assert [string length [info commands docir::canvas::render]] "render exists"
    assert [string length [info commands docir::canvas::clear]] "clear exists"
}

# ============================================================
# B. Grundlegendes Rendering
# ============================================================

test "canvas.render_returns_item_ids" {
    resetCanvas
    set ir [list [dict create type heading content {{type text text "Hi"}} meta {level 1}]]
    set items [docir::canvas::render $::testCanvas $ir [dict create width 600]]
    assert [expr {[llength $items] > 0}] "items returned"
}

test "canvas.heading_creates_text_item" {
    resetCanvas
    set ir [list [dict create type heading content {{type text text "Hello"}} meta {level 1}]]
    set items [docir::canvas::render $::testCanvas $ir [dict create width 600]]
    set hasText 0
    foreach id $items {
        if {[$::testCanvas type $id] eq "text"} {
            set hasText 1
            break
        }
    }
    assert $hasText "heading produced text item"
}

test "canvas.heading_text_visible_in_canvas" {
    resetCanvas
    set ir [list [dict create type heading content {{type text text "TitleX"}} meta {level 1}]]
    docir::canvas::render $::testCanvas $ir [dict create width 600]
    set found 0
    foreach id [$::testCanvas find withtag docir-canvas] {
        if {[$::testCanvas type $id] eq "text"} {
            if {[$::testCanvas itemcget $id -text] eq "TitleX"} {
                set found 1
                break
            }
        }
    }
    assert $found "heading text TitleX present"
}

test "canvas.h1_has_underline" {
    resetCanvas
    set ir [list [dict create type heading content {{type text text "X"}} meta {level 1}]]
    docir::canvas::render $::testCanvas $ir [dict create width 600]
    set lineCount 0
    foreach id [$::testCanvas find withtag docir-canvas] {
        if {[$::testCanvas type $id] eq "line"} { incr lineCount }
    }
    assert [expr {$lineCount >= 1}] "h1 has at least one line"
}

test "canvas.h3_has_no_underline" {
    resetCanvas
    set ir [list [dict create type heading content {{type text text "X"}} meta {level 3}]]
    docir::canvas::render $::testCanvas $ir [dict create width 600]
    set lineCount 0
    foreach id [$::testCanvas find withtag docir-canvas] {
        if {[$::testCanvas type $id] eq "line"} { incr lineCount }
    }
    assert [expr {$lineCount == 0}] "h3 has no underline"
}

test "canvas.paragraph_creates_text_item" {
    resetCanvas
    set ir [list [dict create type paragraph content {{type text text "para"}} meta {}]]
    set items [docir::canvas::render $::testCanvas $ir [dict create width 600]]
    assert [expr {[llength $items] >= 1}] "paragraph produced items"
}

test "canvas.pre_has_background_rect" {
    resetCanvas
    set ir [list [dict create type pre content {{type text text "code line"}} meta {kind code}]]
    docir::canvas::render $::testCanvas $ir [dict create width 600]
    set rectCount 0
    foreach id [$::testCanvas find withtag docir-canvas] {
        if {[$::testCanvas type $id] eq "rectangle"} { incr rectCount }
    }
    assert [expr {$rectCount >= 1}] "pre has a rectangle (background)"
}

test "canvas.hr_creates_line" {
    resetCanvas
    set ir [list [dict create type hr content {} meta {}]]
    docir::canvas::render $::testCanvas $ir [dict create width 600]
    set lineCount 0
    foreach id [$::testCanvas find withtag docir-canvas] {
        if {[$::testCanvas type $id] eq "line"} { incr lineCount }
    }
    assert [expr {$lineCount == 1}] "hr produces one line"
}

# ============================================================
# C. Listen
# ============================================================

test "canvas.list_ul_has_two_markers_and_two_descs" {
    resetCanvas
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "a"}} meta {kind ul}] \
        [dict create type listItem content {{type text text "b"}} meta {kind ul}] \
    ] meta {kind ul}]]
    docir::canvas::render $::testCanvas $ir [dict create width 600]
    set textCount 0
    foreach id [$::testCanvas find withtag docir-canvas] {
        if {[$::testCanvas type $id] eq "text"} { incr textCount }
    }
    # Zwei Items, jeweils Marker + Desc = 4 Text-Items minimum
    assert [expr {$textCount >= 4}] "ul produces at least 4 text items (got $textCount)"
}

test "canvas.list_ol_uses_number_markers" {
    resetCanvas
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "first"}} meta {kind ol}] \
    ] meta {kind ol}]]
    docir::canvas::render $::testCanvas $ir [dict create width 600]
    set found 0
    foreach id [$::testCanvas find withtag docir-canvas] {
        if {[$::testCanvas type $id] eq "text"} {
            if {[string match "1.*" [$::testCanvas itemcget $id -text]]} {
                set found 1
                break
            }
        }
    }
    assert $found "ol uses '1.' marker"
}

# ============================================================
# D. Tabellen
# ============================================================

test "canvas.table_renders_cells_and_grid" {
    resetCanvas
    set ir [list [dict create type table content [list \
        [dict create type tableRow content [list \
            [dict create type tableCell content {{type text text "a"}} meta {}] \
            [dict create type tableCell content {{type text text "b"}} meta {}] \
        ] meta {}] \
    ] meta {columns 2 hasHeader 0}]]
    docir::canvas::render $::testCanvas $ir [dict create width 600]
    set textCount 0
    set lineCount 0
    foreach id [$::testCanvas find withtag docir-canvas] {
        switch [$::testCanvas type $id] {
            text { incr textCount }
            line { incr lineCount }
        }
    }
    assert [expr {$textCount >= 2}] "two cell texts"
    assert [expr {$lineCount >= 4}] "grid lines (got $lineCount)"
}

test "canvas.table_header_has_background_rect" {
    resetCanvas
    set ir [list [dict create type table content [list \
        [dict create type tableRow content [list \
            [dict create type tableCell content {{type text text "h"}} meta {}] \
        ] meta {}] \
        [dict create type tableRow content [list \
            [dict create type tableCell content {{type text text "v"}} meta {}] \
        ] meta {}] \
    ] meta {columns 1 hasHeader 1}]]
    docir::canvas::render $::testCanvas $ir [dict create width 600]
    set rectCount 0
    foreach id [$::testCanvas find withtag docir-canvas] {
        if {[$::testCanvas type $id] eq "rectangle"} { incr rectCount }
    }
    assert [expr {$rectCount >= 1}] "header row has rectangle"
}

# ============================================================
# E. Tag-basiertes Cleanup
# ============================================================

test "canvas.clear_removes_all_docir_items" {
    resetCanvas
    set ir [list \
        [dict create type heading content {{type text text "X"}} meta {level 1}] \
        [dict create type paragraph content {{type text text "Y"}} meta {}]]
    docir::canvas::render $::testCanvas $ir [dict create width 600]
    set before [llength [$::testCanvas find withtag docir-canvas]]
    docir::canvas::clear $::testCanvas
    set after [llength [$::testCanvas find withtag docir-canvas]]
    assert [expr {$before > 0}] "items present before clear"
    assert [expr {$after == 0}] "no docir items after clear"
}

test "canvas.clear_preserves_other_items" {
    resetCanvas
    # Ein Item das NICHT zu docir-canvas gehoert
    set otherId [$::testCanvas create rectangle 0 0 10 10 -tags other]
    set ir [list [dict create type paragraph content {{type text text "X"}} meta {}]]
    docir::canvas::render $::testCanvas $ir [dict create width 600]
    docir::canvas::clear $::testCanvas
    # otherId muss noch existieren
    set kept [$::testCanvas find withtag other]
    assert [expr {[lsearch $kept $otherId] >= 0}] "non-docir item preserved"
    $::testCanvas delete other
}

# ============================================================
# F. Defensive Behandlung
# ============================================================

test "canvas.unknown_block_no_crash" {
    resetCanvas
    set ir [list [dict create type weirdtype content {} meta {}]]
    set caught [catch {docir::canvas::render $::testCanvas $ir [dict create width 600]} err]
    assert [expr {!$caught}] "unknown type does not crash: $err"
}

test "canvas.blank_no_content_field_no_crash" {
    resetCanvas
    set ir [list [dict create type blank meta {lines 1}]]
    set caught [catch {docir::canvas::render $::testCanvas $ir [dict create width 600]} err]
    assert [expr {!$caught}] "blank without content does not crash"
}

test "canvas.list_with_non_listitem_no_crash" {
    resetCanvas
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "ok"}} meta {kind ul}] \
        [dict create type list content {} meta {kind ul}] \
    ] meta {kind ul}]]
    set caught [catch {docir::canvas::render $::testCanvas $ir [dict create width 600]} err]
    assert [expr {!$caught}] "schema violation does not crash: $err"
}

# ============================================================
# G. Auto-scrollregion
# ============================================================

test "canvas.scrollregion_is_set" {
    resetCanvas
    set ir [list \
        [dict create type heading content {{type text text "X"}} meta {level 1}] \
        [dict create type paragraph content {{type text text "Y Y Y"}} meta {}]]
    docir::canvas::render $::testCanvas $ir [dict create width 600]
    set sr [$::testCanvas cget -scrollregion]
    assert [expr {$sr ne ""}] "scrollregion set"
    assert [expr {[llength $sr] == 4}] "scrollregion has 4 values"
}

# ============================================================
# H. Volle Pipeline
# ============================================================

test "canvas.full_pipeline_nroff" {
    package require nroffparser
    package require docir::roffSource

    set nroff {.TH foo n 1.0 Test
.SH NAME
foo \- a test
.SH DESCRIPTION
This is a description paragraph for testing.
}
    set ast [nroffparser::parse $nroff]
    set ir  [docir::roff::fromAst $ast]

    resetCanvas
    set items [docir::canvas::render $::testCanvas $ir [dict create width 600]]
    assert [expr {[llength $items] >= 4}] "pipeline produced multiple items"

    # Suche nach "NAME" im Canvas
    set hasName 0
    foreach id [$::testCanvas find withtag docir-canvas] {
        if {[$::testCanvas type $id] eq "text"} {
            if {[string match "*NAME*" [$::testCanvas itemcget $id -text]]} {
                set hasName 1
                break
            }
        }
    }
    assert $hasName "pipeline produced NAME heading"
}

# ============================================================
# Spec 0.5: Tests für neue Block-Typen in docir-canvas
# ============================================================

test "spec.canvas.block.image_fallback" {
    # Image mit nicht-existenter URL → Plain-Text-Fallback
    set ir [list [dict create type image content {} \
        meta [dict create url "/nonexistent.png" alt "Test"]]]
    set rc [catch {
        set canvas [canvas .imgC -width 400 -height 300]
        ::docir::canvas::render $canvas $ir
        set items [$canvas find all]
        destroy $canvas
        set items
    } items]
    assert [expr {$rc == 0}] "image_fallback rendert ohne Crash"
    assert [expr {[llength $items] >= 1}] "Mindestens ein Item (Fallback-Text)"
}

test "spec.canvas.block.footnote_section" {
    set ir [list [dict create type footnote_section \
        content [list \
            [dict create type footnote_def \
                content [list [dict create type text text "Note text."]] \
                meta [dict create id "fn1" num "1"]]] \
        meta {}]]
    set rc [catch {
        set canvas [canvas .fnC -width 400 -height 300]
        ::docir::canvas::render $canvas $ir
        set items [$canvas find all]
        destroy $canvas
        set items
    } items]
    assert [expr {$rc == 0}] "footnote_section rendert ohne Crash"
    assert [expr {[llength $items] >= 2}] "Trennlinie + Footnote-Text"
}

test "spec.canvas.block.div_transparent" {
    set ir [list [dict create type div \
        content [list \
            [dict create type heading \
                content [list [dict create type text text "In Div"]] \
                meta [dict create level 1]] \
            [dict create type paragraph \
                content [list [dict create type text text "Body."]] meta {}]] \
        meta [dict create class "warning"]]]
    set rc [catch {
        set canvas [canvas .divC -width 400 -height 300]
        ::docir::canvas::render $canvas $ir
        set items [$canvas find all]
        destroy $canvas
        set items
    } items]
    assert [expr {$rc == 0}] "div rendert ohne Crash"
    assert [expr {[llength $items] >= 2}] "Children werden transparent gerendert"
}

test::runAll
