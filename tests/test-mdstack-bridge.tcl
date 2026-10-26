#!/usr/bin/env tclsh
# test-mdstack-bridge.tcl
#
# Tests die DocIR-Kompatibilität zur mdstack-Brücke.
#
# Hintergrund: mdstack/lib/docir-md-0.1.tm produziert DocIR-Output
# der durch unser docir::validate laufen können muss. Diese Tests
# stellen sicher, dass Änderungen an unserem Validator oder am
# DocIR-Schema die mdstack-Brücke nicht versehentlich brechen.
#
# Skipt sich selbst, wenn mdstack nicht auffindbar ist.

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

# docir-md-source ist jetzt im docir-Repo selbst (vorher war es
# das mdstack-docir-md mit dem identischen Funktionsnamen).
# test-setup.tcl hat es bereits gesourced. Nur der mdparser kommt
# weiter aus mdstack — den brauchen wir fuer End-to-end-Bridge-Tests.
if {![haveParser mdstack::parser]} {
    puts "Skipping test-mdstack-bridge.tcl: mdparser not found."
    puts "  (mdstack als Sibling-Repo plazieren)"
    exit [test::runAll]
    return
}

# Helper: parse + map + validate
proc bridgeRender {md} {
    set ast [mdstack::parser::parse $md]
    set ir  [docir::md::fromAst $ast]
    set errs [docir::validate $ir]
    return [list $ir $errs]
}

# ============================================================
# A. Trivialfälle
# ============================================================

test "bridge.empty_document" {
    lassign [bridgeRender ""] ir errs
    assertEqual {} $errs "leeres Dokument valid"
    # mindestens doc_header
    assert [expr {[llength $ir] >= 1}] "wenigstens doc_header"
}

test "bridge.heading_only" {
    lassign [bridgeRender "# Title\n"] ir errs
    assertEqual {} $errs "heading-only valid"
    set hasHeading 0
    foreach n $ir {
        if {[dict get $n type] eq "heading"} {
            set hasHeading 1
            assertEqual 1 [dict get [dict get $n meta] level] "level=1"
        }
    }
    assertEqual 1 $hasHeading "heading-Knoten erzeugt"
}

# ============================================================
# B. Inline-Typen — alle die unser Validator akzeptiert
# ============================================================

test "bridge.inline_text_strong_emphasis" {
    set md "Plain **bold** *italic* text.\n"
    lassign [bridgeRender $md] ir errs
    assertEqual {} $errs "Mix von Inlines valid"
}

test "bridge.inline_code" {
    set md "Inline ``code`` example.\n"
    lassign [bridgeRender $md] ir errs
    assertEqual {} $errs "code-Inline valid"
}

test "bridge.inline_link" {
    set md "See \[Tcl\](https://tcl.tk) for more.\n"
    lassign [bridgeRender $md] ir errs
    assertEqual {} $errs "link-Inline valid"
    # Link sollte im DocIR auftauchen
    set hasLink 0
    foreach n $ir {
        if {[dict get $n type] eq "paragraph"} {
            foreach inl [dict get $n content] {
                if {[dict get $inl type] eq "link"} { set hasLink 1 }
            }
        }
    }
    assertEqual 1 $hasLink "link-Inline im DocIR"
}

# ============================================================
# C. Block-Typen
# ============================================================

test "bridge.code_block" {
    set md "```tcl\nputs hello\n```\n"
    lassign [bridgeRender $md] ir errs
    assertEqual {} $errs "code-block valid"
    set hasPre 0
    foreach n $ir {
        if {[dict get $n type] eq "pre"} { set hasPre 1 }
    }
    assertEqual 1 $hasPre "pre-Knoten erzeugt"
}

test "bridge.unordered_list" {
    set md "- item 1\n- item 2\n- item 3\n"
    lassign [bridgeRender $md] ir errs
    assertEqual {} $errs "ul-list valid"
}

test "bridge.ordered_list" {
    set md "1. first\n2. second\n3. third\n"
    lassign [bridgeRender $md] ir errs
    assertEqual {} $errs "ol-list valid"
}

test "bridge.blockquote" {
    set md "> A quote here.\n"
    lassign [bridgeRender $md] ir errs
    assertEqual {} $errs "blockquote valid"
}

# ============================================================
# D. Komplexes Dokument
# ============================================================

test "bridge.full_document" {
    set md "---\ntitle: Test\n---\n\n"
    append md "# Heading\n\nA paragraph with **bold** and *italic*.\n\n"
    append md "## Sub\n\n- item 1\n- item 2\n\n"
    append md "```tcl\nputs hi\n```\n\n"
    append md "> A quote\n\n"
    append md "See \[example\](https://example.com).\n"

    lassign [bridgeRender $md] ir errs
    assertEqual {} $errs "voller Mix valid"

    # Seit irSchemaVersion: erster Block ist doc_meta, dann doc_header.
    set meta0 [lindex $ir 0]
    assertEqual doc_meta [dict get $meta0 type] "erster Knoten doc_meta"
    assertEqual 1 [dict get [dict get $meta0 meta] irSchemaVersion] "irSchemaVersion=1"
    # YAML-Frontmatter title soll im doc_header landen (zweiter Block)
    set firstNode [lindex $ir 1]
    assertEqual doc_header [dict get $firstNode type] "zweiter Knoten doc_header"
    set hdrMeta [dict get $firstNode meta]
    assertEqual Test [dict get $hdrMeta name] "doc_header.name aus YAML title"
}

# ============================================================
# E. Schema-Konformität
# ============================================================

test "bridge.all_nodes_have_required_fields" {
    set md "# A\n\nP\n\n## B\n\n- x\n- y\n\n```\ncode\n```\n"
    lassign [bridgeRender $md] ir errs
    assertEqual {} $errs "Validator OK"
    # Manuell prüfen: jeder Block hat type+content+meta (außer blank)
    foreach n $ir {
        set t [dict get $n type]
        assert [dict exists $n type] "type-Feld da"
        assert [dict exists $n meta] "meta-Feld da"
        if {$t ne "blank"} {
            assert [dict exists $n content] "content-Feld da (type=$t)"
        }
    }
}

test "bridge.heading_levels_in_range" {
    set md "# H1\n\n## H2\n\n### H3\n\n#### H4\n\n##### H5\n\n###### H6\n"
    lassign [bridgeRender $md] ir errs
    assertEqual {} $errs "alle 6 heading-Levels valid"
    foreach n $ir {
        if {[dict get $n type] eq "heading"} {
            set lvl [dict get [dict get $n meta] level]
            assert [expr {$lvl >= 1 && $lvl <= 6}] "level $lvl im Range 1..6"
        }
    }
}

# ============================================================
# F. Vormals-bekannte Schema-Verletzungen aus mdstack-Output
#
# 2026-05-05 erste Welle: docir-md (mdstack) produzierte bei
# nested Listen einen 'list'-Knoten direkt im list.content statt
# im content des listItem-Vorgaengers. Der Validator meldete
# das, der Renderer crashte.
#
# 2026-05-05 zweite Welle: docir-md gefixt — nested lists kommen
# jetzt als Top-Level-Geschwister-Nodes raus, nicht im list.content.
# Test aktualisiert: prueft jetzt dass die Verletzung weg ist.
# ============================================================

test "bridge.nested_list_no_schema_violation" {
    set md "- outer\n  - nested 1\n  - nested 2\n- another\n"
    lassign [bridgeRender $md] ir errs
    # Validator MUSS jetzt sauber durchlaufen
    assertEqual {} $errs "nested list darf keine Schema-Verletzung melden"

    # Strukturpruefung: zwei list-Knoten als Top-Level-Geschwister
    set listCount 0
    foreach n $ir {
        if {[dict get $n type] eq "list"} { incr listCount }
    }
    assert [expr {$listCount >= 2}] \
        "nested list erzeugt mehrere list-Knoten auf Top-Level"

    # Kein list-Knoten im content eines anderen list-Knotens
    foreach n $ir {
        if {[dict get $n type] eq "list"} {
            foreach item [dict get $n content] {
                set itype [dict get $item type]
                assertEqual listItem $itype \
                    "list.content darf nur listItem enthalten, nicht $itype"
            }
        }
    }
}

# ============================================================
# Index marker and link inside emphasis (2026-10-21)
# ============================================================
# **[x]{.index}** was flattened to {type strong text x}: no index entry, no
# anchor (three places in "Debian unter Linux"). The span now keeps its node
# and carries the emphasis in the optional field `style`.

proc bridgePara {md} {
    lassign [bridgeRender $md] ir errs
    foreach n $ir {
        if {[dict get $n type] eq "paragraph"} { return [list [dict get $n content] $errs] }
    }
    return [list {} $errs]
}

test "bridge.index_in_strong_keeps_span" {
    lassign [bridgePara "a **\[adduser\]{.index}** b\n"] c errs
    assertEqual {} $errs "valid"
    set sp [lindex $c 1]
    assertEqual span [dict get $sp type] "span bleibt"
    assertEqual index [dict get $sp class] "class index"
    assertEqual adduser [dict get $sp text] "text"
    assertEqual strong [dict get $sp style] "style strong"
}

test "bridge.index_in_strong_emphasis_style_order" {
    lassign [bridgePara "a ***\[z\]{.index}*** b\n"] c errs
    assertEqual {} $errs "valid"
    assertEqual {strong emphasis} [dict get [lindex $c 1] style] "innen zuerst"
}

test "bridge.link_in_strong_keeps_href" {
    lassign [bridgePara "a **\[Tcl\](https://tcl-lang.org)** b\n"] c errs
    assertEqual {} $errs "valid"
    set l [lindex $c 1]
    assertEqual link [dict get $l type] "link bleibt"
    assertEqual https://tcl-lang.org [dict get $l href] "href"
    assertEqual Tcl [dict get $l text] "text"
    assertEqual strong [dict get $l style] "style"
}

test "bridge.index_in_strong_html_entry_and_anchor" {
    package require docir::html
    lassign [bridgeRender "a **\[adduser\]{.index}** b\n"] ir errs
    set h [docir::html::render $ir]
    ::test::assertContains $h {<strong><span class="index" id="idx-1">adduser</span></strong>} \
        "fett, mit Anker"
}

test "bridge.index_in_strong_md_roundtrip" {
    package require docir::md
    lassign [bridgeRender "a **\[adduser\]{.index}** b\n"] ir errs
    ::test::assertContains [docir::md::render $ir] {**[adduser]{.index}**} "Markdown zurück"
}

# ============================================================
# TIP 700 format (mdstack::parser 0.9.0, mdSource 0.2)
# ============================================================

test "bridge.span_attrs_to_ir" {
    lassign [bridgePara "a \[\\*interp\]{.carg .in type=\"Tcl_Interp\"} \[t\]{version=\"TIP500\"} b\n"] c errs
    assertEqual {} $errs "valid"
    set sp [lindex $c 1]
    assertEqual span [dict get $sp type] "span"
    assertEqual "*interp" [dict get $sp text] "text without markup"
    assertEqual "carg in" [dict get $sp class] "all classes"
    assertEqual {type Tcl_Interp} [dict get $sp attrs] "attrs"
    set sp2 [lindex $c 3]
    assertEqual span [dict get $sp2 type] "attribute-only span"
    assert [expr {![dict exists $sp2 class]}] "no class key"
    assertEqual TIP500 [dict get $sp2 attrs version] "version"
}

test "bridge.span_attrs_html" {
    package require docir::html 0.2
    lassign [bridgeRender "\[x\]{.cmd version=\"TIP735\"} \[\\*i\]{.carg .in type=\"int\"}\n"] ir errs
    set h [docir::html::render $ir [dict create standalone 0]]
    ::test::assertContains $h {<span class="cmd" data-version="TIP735" title="TIP735">x</span>} "data-version + title"
    ::test::assertContains $h {<span class="carg in" data-type="int">*i</span>} "two classes, data-type"
}

test "bridge.span_attrs_md_roundtrip" {
    package require docir::md 0.2
    set src "\[x\]{.carg .in type=\"Tcl_Interp\"} and \[y\]{version=\"TIP500\"}"
    lassign [bridgeRender "$src\n"] ir errs
    set md [docir::md::render $ir]
    ::test::assertContains $md {[x]{.carg .in type="Tcl_Interp"}} "classes and attribute back"
    ::test::assertContains $md {[y]{version="TIP500"}} "attribute-only span back"
}

test "bridge.span_txt_prints_text" {
    package require docir::txt 0.2
    lassign [bridgeRender "\[lfilter\]{.cmd version=\"TIP735\"} \[p\]{.carg .in type=\"int\"}\n"] ir errs
    set t [docir::txt::render $ir]
    ::test::assertContains $t "lfilter p" "txt prints span text"
}

set ::tipDl "\[base64\]{.cmd}\n: The encoding.\n\n    During encoding:\n\n    \[-maxlen\]{.lit} \[length\]{.arg}\n    : Split lines.\n\n\n    1. one\n    2. two\n\n    ```\n    code 1\n    ```\n\n**hex**\n: Hex only.\n"

test "bridge.deflist_blocks_to_ir" {
    lassign [bridgeRender $::tipDl] ir errs
    assertEqual {} $errs "valid"
    set lst {}
    foreach n $ir { if {[dict get $n type] eq "list"} { set lst $n; break } }
    set it [lindex [dict get $lst content] 0]
    assert [dict exists $it blocks] "item with blocks"
    assertEqual {paragraph paragraph list list pre} [lmap b [dict get $it blocks] {dict get $b type}] "block types"
    set inner [lindex [dict get $it blocks] 2]
    assertEqual dl [dict get $inner meta kind] "inner definition list"
    assertEqual ol [dict get [lindex [dict get $it blocks] 3] meta kind] "ordered list"
    # content keeps the flat text for content-only sinks
    assert [expr {[string first "Split lines" [docir::md::_inlinesToText [dict get $it content]]] >= 0}] "flat content kept"
    set it2 [lindex [dict get $lst content] 1]
    assert [expr {![dict exists $it2 blocks]}] "plain definition without blocks"
}

test "bridge.deflist_blocks_html" {
    package require docir::html 0.2
    lassign [bridgeRender $::tipDl] ir errs
    set h [docir::html::render $ir [dict create standalone 0]]
    assert [regexp {<dd>\s*<p>The encoding.</p>\s*<p>During encoding:</p>\s*<dl[^>]*>\s*<dt><span class="lit">-maxlen</span>} $h] "inner <dl> inside <dd>: $h"
    assert [regexp {</dl>\s*<ol[^>]*>\s*<li>one</li>} $h] "list inside <dd>"
    assert [regexp {<pre><code>code 1</code></pre>\s*</dd>} $h] "code inside <dd>"
}

test "bridge.deflist_blocks_md_roundtrip" {
    package require docir::md 0.2
    lassign [bridgeRender $::tipDl] ir errs
    set md [docir::md::render $ir]
    ::test::assertContains $md "\n    \[-maxlen\]{.lit} \[length\]{.arg}\n    : Split lines." "inner list indented"
    ::test::assertContains $md "\n    1. one\n" "ordered list indented"
    # read back: same structure
    lassign [bridgeRender $md] ir2 errs2
    assertEqual {} $errs2 "valid again"
    assertEqual [docir::md::render $ir] [docir::md::render $ir2] "stable round trip"
}

test "bridge.deflist_blocks_txt" {
    package require docir::txt 0.2
    lassign [bridgeRender $::tipDl] ir errs
    set t [docir::txt::render $ir]
    assert [regexp {\n  During encoding:} $t] "paragraph indented under the term: $t"
    assert [regexp {\n  -maxlen length\n    Split lines\.} $t] "inner term and its description: $t"
    assert [regexp {\n  1\. one\n  2\. two} $t] "list lines: $t"
}

test "bridge.section_ref_link_and_alias" {
    lassign [bridgeRender "# a\n\n## Examples\n\nA.\n\n# b\n\nSee \[Examples\].\n\n## Examples\n\nB.\n"] ir errs
    assertEqual {} $errs "valid"
    set heads [lmap n $ir {if {[dict get $n type] ne "heading"} continue; set n}]
    assertEqual examples-1 [dict get [lindex $heads 3] meta alias] "alias at the second Examples"
    set link {}
    foreach n $ir {
        if {[dict get $n type] eq "paragraph"} {
            foreach i [dict get $n content] { if {[dict get $i type] eq "link"} { set link $i } }
        }
    }
    assertEqual "#examples-1" [dict get $link href] "reference points to its own page"
    assertEqual Examples [dict get $link text] "link text"
    package require docir::html 0.2
    ::test::assertContains [docir::html::render $ir] {<span id="examples-1"></span>Examples} "HTML anchor"
}

exit [test::runAll]
