#!/usr/bin/env tclsh
# test-docir-renderer-frame.tcl -- docir::rendererTk "tablemode frame"
#
# Variant B of the Tk renderer embeds a real frame/grid table (ttk widgets)
# instead of the monospace box. Tk-dependent: skips itself when there is no
# display / no Tk.

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

set hasTk [expr {![catch {package require Tk}]}]
set hasRenderer [expr {![catch {package require docir::rendererTk}]}]

# a small 2x2 table IR (header row + data row), right-aligned 2nd column
set tableIr [list \
    [dict create type table content {
        {type tableRow content {
            {type tableCell content {{type text text "Head A"}} meta {}}
            {type tableCell content {{type text text "Head B"}} meta {}}
        } meta {kind header}}
        {type tableRow content {
            {type tableCell content {{type text text "a1"}} meta {}}
            {type tableCell content {{type text text "b1"}} meta {}}
        } meta {}}
    } meta {columns 2 alignments {left right} hasHeader 1}]]

if {!$hasTk} {
    test "rendererTk.frame_skipped_no_tk" { skip "Tk not available (no display)" }
} elseif {!$hasRenderer} {
    test "rendererTk.frame_skipped_no_renderer" { skip "docir::rendererTk not available" }
} else {
    test "rendererTk.frame_embeds_table_widget" {
        set w .rt[clock clicks]
        text $w
        docir::renderer::tk::render $w $tableIr [dict create tablemode frame]
        set wins [$w window names]
        assert {[llength $wins] >= 1} "frame mode embeds an in-text window"
        set tf [lindex $wins 0]
        assert {[winfo exists $tf] && [winfo class $tf] eq "Frame"} "embedded window is a frame"
        # 2 rows x 2 cols -> 4 cell labels
        assert {[llength [winfo children $tf]] == 4} \
            "2x2 table -> 4 cells, got [llength [winfo children $tf]]"
        destroy $w
    }

    test "rendererTk.frame_honours_alignment" {
        set w .rt[clock clicks]a
        text $w
        docir::renderer::tk::render $w $tableIr [dict create tablemode frame]
        set tf [lindex [$w window names] 0]
        # column 1 cells are right-aligned -> anchor ne
        set rightCell $tf.c1_1
        assert {[winfo exists $rightCell]} "data cell (row1,col1) exists"
        assert {[$rightCell cget -anchor] eq "ne"} \
            "right-aligned column uses anchor ne, got [$rightCell cget -anchor]"
        destroy $w
    }

    test "rendererTk.ascii_default_no_window" {
        set w .rt[clock clicks]b
        text $w
        docir::renderer::tk::render $w $tableIr   ;# no tablemode -> ascii default
        assert {[llength [$w window names]] == 0} "ascii mode embeds no window"
        assert {[string match "*\u2502*" [$w get 1.0 end]]} "ascii mode draws box chars"
        destroy $w
    }
}

test::runAll
