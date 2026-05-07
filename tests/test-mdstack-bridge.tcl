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
    test::runAll
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

test::runAll
