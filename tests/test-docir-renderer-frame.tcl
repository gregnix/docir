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

# ============================================================
# math_block -- typeset since rendererTk 0.4
#
# 0.2 and earlier: math_block fell through the default branch and vanished.
# 0.3: shown as its source.
# 0.4: typeset on an embedded canvas via pdf4tcllib::math (canvasBackend),
#      with the source as fallback when the engine is not there.
# ============================================================

set hasMath [expr {![catch {package require pdf4tcllib 0.5}]
                   && [llength [info commands ::pdf4tcllib::math::canvasBackend]] > 0}]

if {!$hasTk} {
    test "rendererTk.math_block_skipped_no_tk" { skip "Tk not available (no display)" }
} elseif {!$hasRenderer} {
    test "rendererTk.math_block_skipped_no_renderer" { skip "docir::rendererTk not available" }
} else {

    set mathIr [list \
        [dict create type paragraph meta {} content [list \
            [dict create type text text "Davor."]]] \
        [dict create type math_block meta {kind math} content [list \
            [dict create type text text "\\frac{a}{b}"]]] \
        [dict create type paragraph meta {} content [list \
            [dict create type text text "Danach."]]]]

    test "rendererTk.math_block_typeset_on_canvas" {
        if {!$::hasMath} { skip "pdf4tcllib 0.5 (math canvasBackend) not available" }
        set w [text .tmath1]
        ::docir::renderer::tk::render $w $::mathIr
        set wins [$w window names]
        assert {[llength $wins] == 1} "genau ein eingebettetes Fenster"
        set c [lindex $wins 0]
        assertEqual "Canvas" [winfo class $c] "die Formel steckt auf einem Canvas"
        set types {}
        foreach id [$c find all] { lappend types [$c type $id] }
        assert {"line" in $types} "der Bruchstrich ist gezeichnet"
        assert {"text" in $types} "Zaehler/Nenner sind gezeichnet"
        assert {[string first "Davor." [$w get 1.0 end]] >= 0} "Text davor bleibt"
        assert {[string first "Danach." [$w get 1.0 end]] >= 0} "Text danach bleibt"
        destroy $w
    }

    test "rendererTk.math_block_falls_back_to_source" {
        if {!$::hasMath} { skip "pdf4tcllib 0.5 (math canvasBackend) not available" }
        # Ohne Engine muss der Quelltext erscheinen -- nicht nichts.
        rename ::pdf4tcllib::math::canvasBackend ::pdf4tcllib::math::_cbSaved
        set w [text .tmath2]
        set rc [catch {::docir::renderer::tk::render $w $::mathIr} err]
        set txt [$w get 1.0 end]
        set wins [$w window names]
        destroy $w
        rename ::pdf4tcllib::math::_cbSaved ::pdf4tcllib::math::canvasBackend
        assert {$rc == 0} "render laeuft ohne Engine durch ($err)"
        assert {[llength $wins] == 0} "kein Canvas ohne Engine"
        assert {[string first "\\frac{a}{b}" $txt] >= 0} "Quelltext als Rueckfall"
    }

    test "rendererTk.math_block_source_carries_math_style" {
        if {!$::hasMath} { skip "pdf4tcllib 0.5 (math canvasBackend) not available" }
        rename ::pdf4tcllib::math::canvasBackend ::pdf4tcllib::math::_cbSaved
        set w [text .tmath3]
        ::docir::renderer::tk::render $w $::mathIr
        set idx     [$w search "frac" 1.0 end]
        set tags    [expr {$idx eq "" ? {} : [$w tag names $idx]}]
        set justify [$w tag cget mathBlock -justify]
        destroy $w
        rename ::pdf4tcllib::math::_cbSaved ::pdf4tcllib::math::canvasBackend
        assert {[lsearch -exact $tags mathBlock] >= 0} "Rueckfall traegt das mathBlock-Tag"
        assertEqual "center" $justify "Rueckfall-Block ist zentriert"
    }

    test "rendererTk.math_block_accepts_plain_content" {
        set w [text .tmath4]
        set ir [list [dict create type math_block meta {kind math} content "a + b"]]
        ::docir::renderer::tk::render $w $ir
        set ok [expr {[llength [$w window names]] == 1
                      || [string first "a + b" [$w get 1.0 end]] >= 0}]
        destroy $w
        assert {$ok} "String-Content wird gesetzt oder als Quelltext gezeigt"
    }

    test "rendererTk.math_block_empty_is_silent" {
        set w [text .tmath5]
        set ir [list [dict create type math_block meta {kind math} content ""]]
        ::docir::renderer::tk::render $w $ir
        set txt [string trim [$w get 1.0 end]]
        set wins [$w window names]
        destroy $w
        assertEqual "" $txt "leere Formel erzeugt keinen Text"
        assert {[llength $wins] == 0} "leere Formel erzeugt keinen Canvas"
    }

    # Definitions with blocks (rendererTk 0.6): blocks as blocks, indented
    # per depth; spans with several classes get one tag per class
    test "rendererTk.dl_blocks_rendered_as_blocks" {
        set w [text .tdl1]
        set inner [dict create type list meta {kind dl indentLevel 0} content [list \
            [dict create type listItem meta [dict create kind dl \
                term [list [dict create type text text InnerT]]] \
                content [list [dict create type text text InnerD]]]]]
        set item [dict create type listItem \
            meta [dict create kind dl term [list [dict create type text text OuterT]]] \
            content [list [dict create type text text "FLAT"]] \
            blocks [list \
                [dict create type paragraph meta {} content [list [dict create type text text ParaA]]] \
                [dict create type pre meta {kind code} content [list [dict create type text text "codeX"]]] \
                $inner]]
        ::docir::renderer::tk::render $w [list [dict create type list meta {kind dl indentLevel 0} content [list $item]]]
        set txt [$w get 1.0 end]
        assert {[string first FLAT $txt] < 0} "blocks, not the flat content"
        foreach x {OuterT ParaA codeX InnerT InnerD} {
            assert {[string first $x $txt] >= 0} "$x shown"
        }
        set iP [$w search ParaA 1.0]
        set iC [$w search codeX 1.0]
        set iD [$w search InnerD 1.0]
        assert {"dlBlk1" ni [$w tag names [$w search OuterT 1.0]]} "term not indented as block"
        assert {"dlBlk1" in [$w tag names $iP]} "paragraph at depth 1"
        assert {"pre" in [$w tag names $iC] && "dlBlk1" in [$w tag names $iC]} "code block, indented"
        assert {"dlBlk2" in [$w tag names $iD]} "inner description at depth 2"
        assert {[$w tag cget dlBlk2 -lmargin1] > [$w tag cget dlBlk1 -lmargin1]} "deeper is further in"
        destroy $w
    }

    test "rendererTk.span_multi_class_tags" {
        set w [text .tsp1]
        ::docir::renderer::tk::render $w [list [dict create type paragraph meta {} content [list \
            [dict create type span text "*interp" class "carg in" attrs {type Tcl_Interp}]]]]
        set i [$w search "*interp" 1.0]
        set tags [$w tag names $i]
        destroy $w
        assert {"span_carg" in $tags && "span_in" in $tags} "one tag per class: $tags"
        assert {"in" ni $tags} "no bare class tag"
    }
}

#test::runAll
exit [test::runAll]
