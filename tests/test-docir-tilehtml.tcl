#!/usr/bin/env tclsh
# test-docir-tilehtml.tcl -- Smoke-Tests fuer docir::tilehtml

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]
package require docir::tilehtml

# Helper: minimales DocIR
proc minimalIr {} {
    return [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "Test Sheet" meta {}]] \
            meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "Section A" meta {}]] \
            meta [dict create level 2]] \
        [dict create type pre content [list \
            [dict create type text text "set x 1" meta {}]] meta {}] \
        [dict create type heading content [list \
            [dict create type text text "Section B" meta {}]] \
            meta [dict create level 2]] \
        [dict create type list content [list \
            [dict create type listItem content [list \
                [dict create type text text "item one" meta {}]] meta {}] \
            [dict create type listItem content [list \
                [dict create type text text "item two" meta {}]] meta {}] \
        ] meta {kind ul indentLevel 0}]]
}

set tmpDir [file join [pwd] tmp-tilehtml-tests]
file mkdir $tmpDir

# ============================================================
# A. Render: HTML wird erzeugt
# ============================================================

test "tilehtml.render.creates_html_file" {
    set out [file join $tmpDir test1.html]
    file delete -force $out
    ::docir::tilehtml::render [minimalIr] $out
    assert [file exists $out] "HTML-Datei wurde nicht erzeugt"
    set sz [file size $out]
    assert [expr {$sz > 1000}] "HTML zu klein ($sz bytes)"
}

test "tilehtml.render.contains_doctype_and_html_lang" {
    set out [file join $tmpDir lang.html]
    ::docir::tilehtml::render [minimalIr] $out -lang en
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "<!DOCTYPE html>*" $html] "DOCTYPE muss vorne stehen"
    assert [string match "*<html lang=\"en\">*" $html] "lang-Attribut sollte 'en' sein"
}

test "tilehtml.render.contains_sheet_title" {
    set out [file join $tmpDir title.html]
    ::docir::tilehtml::render [minimalIr] $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*<title>Test Sheet</title>*" $html] "title-Tag sollte Sheet-Titel haben"
    assert [string match "*<h1>Test Sheet</h1>*" $html] "h1 sollte Sheet-Titel haben"
}

test "tilehtml.render.section_titles_as_h3" {
    set out [file join $tmpDir h3.html]
    ::docir::tilehtml::render [minimalIr] $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*<h3 class=\"tile-title\">Section A</h3>*" $html] \
        "Section A sollte als h3 gerendert sein"
    assert [string match "*<h3 class=\"tile-title\">Section B</h3>*" $html] \
        "Section B sollte als h3 gerendert sein"
}

test "tilehtml.render.code_section_uses_pre_code" {
    set out [file join $tmpDir code.html]
    ::docir::tilehtml::render [minimalIr] $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*<pre><code>set x 1*" $html] \
        "code-Section sollte <pre><code> nutzen"
}

test "tilehtml.render.list_section_uses_ul" {
    set out [file join $tmpDir list.html]
    ::docir::tilehtml::render [minimalIr] $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*<ul>*<li>item one</li>*" $html] \
        "list-Section sollte <ul>/<li> nutzen"
}

# ============================================================
# B. Theme-Support
# ============================================================

test "tilehtml.theme.light_creates_light_css" {
    set out [file join $tmpDir light.html]
    ::docir::tilehtml::render [minimalIr] $out -theme light
    set fh [open $out r]
    set html [read $fh]
    close $fh
    # Light theme: weisser bg
    assert [string match "*--bg: #ffffff*" $html] "light theme sollte weissen bg haben"
}

test "tilehtml.theme.dark_creates_dark_css" {
    set out [file join $tmpDir dark.html]
    ::docir::tilehtml::render [minimalIr] $out -theme dark
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*--bg: #1e1e22*" $html] "dark theme sollte dunklen bg haben"
}

test "tilehtml.theme.auto_uses_prefers_color_scheme" {
    set out [file join $tmpDir auto.html]
    ::docir::tilehtml::render [minimalIr] $out -theme auto
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*prefers-color-scheme: dark*" $html] \
        "auto theme sollte @media-Query nutzen"
}

test "tilehtml.theme.unknown_theme_rejected" {
    set caught 0
    if {[catch {::docir::tilehtml::render [minimalIr] [file join $tmpDir x.html] -theme purple} err]} {
        set caught 1
        assert [string match "*unknown theme*" $err] "Fehler sollte unknown theme nennen"
    }
    assert $caught "render mit unknown theme sollte fail"
}

# ============================================================
# C. HTML-Escaping
# ============================================================

test "tilehtml.escape.special_chars" {
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "<Test> & \"X\"" meta {}]] \
            meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "S" meta {}]] \
            meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text text "x < 5 & y > 3" meta {}]] meta {}]]
    set out [file join $tmpDir escape.html]
    ::docir::tilehtml::render $ir $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    # Title sollte escaped sein
    assert [string match "*&lt;Test&gt; &amp; &quot;X&quot;*" $html] \
        "<>& sollten escaped sein"
    assert [string match "*x &lt; 5 &amp; y &gt; 3*" $html] \
        "Inline <>& sollten escaped sein"
}

# ============================================================
# D. Inline-Markup im Body
# ============================================================

test "tilehtml.inline.bold_italic_code" {
    # Wir simulieren bold/italic/code via content in Pseudo-Markdown-Form,
    # aber DocIR-Inlines sind explicit. Wir nutzen strong/emphasis/code direkt.
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "Title" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "S" meta {}]] meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text text "use " meta {}] \
            [dict create type strong text "bold" meta {}] \
            [dict create type text text " and " meta {}] \
            [dict create type code text "mono" meta {}] \
        ] meta {}]]
    set out [file join $tmpDir inline.html]
    ::docir::tilehtml::render $ir $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*<strong>bold</strong>*" $html] "bold sollte als <strong>"
    assert [string match "*<code>mono</code>*" $html] "code sollte als <code>"
}

# ============================================================
# E. Bilder
# ============================================================

proc imageBlockIr {} {
    return [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "Img Test" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "Pic" meta {}]] meta [dict create level 2]] \
        [dict create type image content {} meta [dict create url /tmp/test.png alt "Alt Text" title "Tip"]]]
}

test "tilehtml.image.block_creates_figure_with_img" {
    set out [file join $tmpDir img-block.html]
    ::docir::tilehtml::render [imageBlockIr] $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*<figure><img src=\"/tmp/test.png\"*" $html] \
        "Block-image sollte <figure><img> rendern"
    assert [string match "*alt=\"Alt Text\"*" $html] "alt-Attribut"
    assert [string match "*title=\"Tip\"*" $html] "title-Attribut"
}

test "tilehtml.image.inline_in_paragraph_renders_as_img" {
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "T" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "S" meta {}]] meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text text "before " meta {}] \
            [dict create type image text "alt" url "/tmp/x.png"] \
            [dict create type text text " after" meta {}] \
        ] meta {}]]
    set out [file join $tmpDir img-inline.html]
    ::docir::tilehtml::render $ir $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*<img src=\"/tmp/x.png\" alt=\"alt\" class=\"inline-img\">*" $html] \
        "inline-image sollte als <img class=\"inline-img\"> rendern"
}

# ============================================================
# F. Columns Option
# ============================================================

test "tilehtml.columns.default_is_2" {
    set out [file join $tmpDir cols2.html]
    ::docir::tilehtml::render [minimalIr] $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*column-count: 2*" $html] "default cols=2 in CSS"
    assert [string match "*repeat(2, 1fr)*" $html] "default cols=2 grid"
}

test "tilehtml.columns.3_cols_in_css" {
    set out [file join $tmpDir cols3.html]
    ::docir::tilehtml::render [minimalIr] $out -columns 3
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*column-count: 3*" $html] "cols=3 in CSS"
    assert [string match "*repeat(3, 1fr)*" $html] "cols=3 grid"
}

test "tilehtml.columns.invalid_value_rejected" {
    set caught 0
    if {[catch {::docir::tilehtml::render [minimalIr] [file join $tmpDir x.html] -columns 0} err]} {
        set caught 1
    }
    assert $caught "render mit columns=0 sollte fail"

    set caught 0
    if {[catch {::docir::tilehtml::render [minimalIr] [file join $tmpDir x.html] -columns 5} err]} {
        set caught 1
    }
    assert $caught "render mit columns=5 sollte fail"
}

# ============================================================
# G. Links als <a href>
# ============================================================

test "tilehtml.link.markdown_link_becomes_anchor" {
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "T" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "S" meta {}]] meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text text "see " meta {}] \
            [dict create type link content [list \
                [dict create type text text "Tcl Wiki" meta {}]] \
                meta [dict create url "https://wiki.tcl-lang.org"]] \
            [dict create type text text " for more" meta {}] \
        ] meta {}]]
    set out [file join $tmpDir link.html]
    ::docir::tilehtml::render $ir $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*<a href=\"https://wiki.tcl-lang.org\">Tcl Wiki</a>*" $html] \
        "Link sollte als <a href> rendern, war: [regexp -inline {<a href[^>]*>[^<]*</a>} $html]"
}

# ============================================================
# H. Anchors fuer Sheets + TOC
# ============================================================

test "tilehtml.anchor.sheet_has_id" {
    set out [file join $tmpDir anchor.html]
    ::docir::tilehtml::render [minimalIr] $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*<article class=\"sheet\" id=\"sheet-1-test-sheet\">*" $html] \
        "Sheet sollte id=sheet-N-slug haben"
}

test "tilehtml.toc.single_sheet_no_toc" {
    set out [file join $tmpDir no-toc.html]
    ::docir::tilehtml::render [minimalIr] $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [expr {![string match "*<nav class=\"toc\">*" $html]}] \
        "Single-Sheet sollte KEIN TOC haben"
}

test "tilehtml.toc.multi_sheet_has_toc" {
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "Sheet One" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "S" meta {}]] meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text text "x" meta {}]] meta {}] \
        [dict create type heading content [list \
            [dict create type text text "Sheet Two" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "T" meta {}]] meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text text "y" meta {}]] meta {}]]
    set out [file join $tmpDir multi-toc.html]
    ::docir::tilehtml::render $ir $out
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*<nav class=\"toc\">*" $html] "Multi-Sheet sollte TOC haben"
    assert [string match "*<a href=\"#sheet-1-sheet-one\">Sheet One</a>*" $html] \
        "TOC-Link auf Sheet 1"
    assert [string match "*<a href=\"#sheet-2-sheet-two\">Sheet Two</a>*" $html] \
        "TOC-Link auf Sheet 2"
}

test "tilehtml.slugify.umlauts_to_ascii" {
    assertEqual "uebersicht" [::docir::tilehtml::_slugify "\u00dcbersicht"]
    assertEqual "fuer-grosse-aepfel" [::docir::tilehtml::_slugify "F\u00fcr gro\u00dfe \u00c4pfel"]
    assertEqual "sheet" [::docir::tilehtml::_slugify ""]
    assertEqual "sheet" [::docir::tilehtml::_slugify "!!!"]
}

# ============================================================
# I. Mehr Themes
# ============================================================

test "tilehtml.theme.solarized_has_solarized_colors" {
    set out [file join $tmpDir sol.html]
    ::docir::tilehtml::render [minimalIr] $out -theme solarized
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*--bg: #fdf6e3*" $html] "solarized sollte fdf6e3 bg haben"
}

test "tilehtml.theme.sepia_has_sepia_colors" {
    set out [file join $tmpDir sep.html]
    ::docir::tilehtml::render [minimalIr] $out -theme sepia
    set fh [open $out r]
    set html [read $fh]
    close $fh
    assert [string match "*--bg: #f4ecd8*" $html] "sepia sollte f4ecd8 bg haben"
}

test::runAll
file delete -force $tmpDir
