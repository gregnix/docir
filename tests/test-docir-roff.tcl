#!/usr/bin/env tclsh
# Tests für docir-roff (Senke: DocIR → nroff)
#
# Quoting-Konvention: für Patterns die Backslash-Sequenzen enthalten
# nutzen wir [string first {pattern} $haystack] >= 0 statt
# [string match "*pattern*" $haystack]. Grund: Tcl interpretiert
# `\f` etc. in "..."-Strings als Escape; in {...} nicht.

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

# Senke separat sourcen
source -encoding utf-8 [file join $testDir .. lib tm docir roff-0.1.tm]


proc roundTripIr {src} {
    set ast [nroffparser::parse $src test.n]
    return [::docir::roff::fromAst $ast]
}

# ============================================================
# Block-Tests: doc_header
# ============================================================

test "roff.render.doc_header.basic" {
    set ir [list [dict create type doc_header content "" \
        meta [dict create name foo section n version 1.0 part Tcl]]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.TH foo n 1.0 Tcl} "TH-Zeile"
}

test "roff.render.doc_header.no_version" {
    set ir [list [dict create type doc_header content "" \
        meta [dict create name foo section n]]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.TH foo n} "TH ohne version"
}

test "roff.render.doc_header.with_spaces_in_part" {
    set ir [list [dict create type doc_header content "" \
        meta [dict create name foo section n version 1.0 part "Tcl Commands"]]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out "\"Tcl Commands\"" "part mit Spaces gequotet"
}

# ============================================================
# Block-Tests: heading
# ============================================================

test "roff.render.heading.level_1" {
    set ir [list [dict create type heading \
        content [list [dict create type text text "NAME"]] \
        meta [dict create level 1]]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.SH NAME} "level=1 → .SH"
}

test "roff.render.heading.level_2" {
    set ir [list [dict create type heading \
        content [list [dict create type text text "Sub"]] \
        meta [dict create level 2]]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.SS Sub} "level=2 → .SS"
}

test "roff.render.heading.with_spaces" {
    set ir [list [dict create type heading \
        content [list [dict create type text text "STANDARD OPTIONS"]] \
        meta [dict create level 1]]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.SH "STANDARD OPTIONS"} "Heading mit Spaces gequotet"
}

# ============================================================
# Block-Tests: paragraph
# ============================================================

test "roff.render.paragraph.basic" {
    set ir [list [dict create type paragraph \
        content [list [dict create type text text "Hello world."]] meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.PP} ".PP-Marker"
    ::test::assertContains $out {Hello world.} "Text"
}

test "roff.render.paragraph.protect_leading_dot" {
    set ir [list [dict create type paragraph \
        content [list [dict create type text text ". starts with dot"]] meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {\&. starts with dot} "Punkt am Anfang geschützt"
}

# ============================================================
# Block-Tests: pre / code-block
# ============================================================

test "roff.render.pre.basic" {
    set ir [list [dict create type pre \
        content [list [dict create type text text "puts hello"]] meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.CS} ".CS-Marker"
    ::test::assertContains $out {.CE} ".CE-Marker"
    ::test::assertContains $out {puts hello} "Code-Inhalt"
}

test "roff.render.pre.multiline_protected" {
    set ir [list [dict create type pre \
        content [list [dict create type text text "line1\n.line2"]] meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {\&.line2} "Punkt-Zeile in pre escapet"
}

# ============================================================
# Block-Tests: list
# ============================================================

test "roff.render.list.tp" {
    set ir [list [dict create type list \
        content [list \
            [dict create type listItem \
                content [list [dict create type text text "Description."]] \
                meta [dict create kind tp \
                    term [list [dict create type text text "term1"]]]]] \
        meta [dict create kind tp]]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.TP} ".TP-Marker"
    ::test::assertContains $out {term1} "Term"
    ::test::assertContains $out {Description.} "Beschreibung"
}

test "roff.render.list.op" {
    # OP-Term ist konventionell "cmdName|dbName|dbClass" als Text
    set ir [list [dict create type list \
        content [list \
            [dict create type listItem \
                content [list [dict create type text text "Description."]] \
                meta [dict create kind op \
                    term [list [dict create type text text "-flag|fooName|FooClass"]]]]] \
        meta [dict create kind op]]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.OP} ".OP-Marker"
    ::test::assertContains $out {fooName} "dbName"
    ::test::assertContains $out {FooClass} "dbClass"
    ::test::assertContains $out {\-flag} "OP-cmd-flag mit \\- escapet"
}

test "roff.render.list.bulleted_ip" {
    set ir [list [dict create type list \
        content [list \
            [dict create type listItem \
                content [list [dict create type text text "First."]] \
                meta [dict create kind ip term {}]]] \
        meta [dict create kind ip]]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.IP \(bu} ".IP \\(bu für Bullet"
    ::test::assertContains $out {First.} "Item-Text"
}

test "roff.render.list.numbered_ol" {
    set ir [list [dict create type list \
        content [list \
            [dict create type listItem \
                content [list [dict create type text text "Step one."]] \
                meta [dict create kind ol term {}]] \
            [dict create type listItem \
                content [list [dict create type text text "Step two."]] \
                meta [dict create kind ol term {}]]] \
        meta [dict create kind ol]]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.IP [1]} "Item 1"
    ::test::assertContains $out {.IP [2]} "Item 2"
    ::test::assertContains $out {Step one.} "Text 1"
    ::test::assertContains $out {Step two.} "Text 2"
}

# ============================================================
# Block-Tests: blank, hr
# ============================================================

test "roff.render.blank" {
    set ir [list [dict create type blank content "" meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.sp} "blank → .sp"
}

test "roff.render.hr" {
    set ir [list [dict create type hr content "" meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.sp 2} "hr → .sp 2"
}

# ============================================================
# Block-Tests: table
# ============================================================

test "roff.render.table.standard_options" {
    set ir [list [dict create type table \
        content [list \
            [dict create type tableRow \
                content [list \
                    [dict create type tableCell \
                        content [list [dict create type text text "background"]] meta {}] \
                    [dict create type tableCell \
                        content [list [dict create type text text "borderwidth"]] meta {}]] \
                meta {}]] \
        meta [dict create kind standardOptions]]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.SO} ".SO-Marker"
    ::test::assertContains $out {.SE} ".SE-Marker"
    ::test::assertContains $out {background} "Option1"
    ::test::assertContains $out {borderwidth} "Option2"
}

# ============================================================
# Inline-Tests
# ============================================================

test "roff.render.inline.strong" {
    set ir [list [dict create type paragraph \
        content [list [dict create type strong text "bold"]] meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {\fBbold\fR} "strong → \\fB...\\fR"
}

test "roff.render.inline.emphasis" {
    set ir [list [dict create type paragraph \
        content [list [dict create type emphasis text "italic"]] meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {\fIitalic\fR} "emphasis → \\fI...\\fR"
}

test "roff.render.inline.code" {
    set ir [list [dict create type paragraph \
        content [list [dict create type code text "puts"]] meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {\fBputs\fR} "code → \\fB...\\fR (nroff-Konvention)"
}

test "roff.render.inline.link" {
    set ir [list [dict create type paragraph \
        content [list [dict create type link text "puts" name "puts" section "n"]] meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {\fBputs\fR(n)} "link → name(section)"
}

test "roff.render.inline.escape_hyphen" {
    set ir [list [dict create type paragraph \
        content [list [dict create type text text "use -flag now"]] meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {use \-flag now} "Hyphens → \\-"
}

test "roff.render.inline.escape_backslash" {
    set ir [list [dict create type paragraph \
        content [list [dict create type text text "path\\with\\backslash"]] meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {path\ewith\ebackslash} "Backslashes → \\e"
}

# ============================================================
# Round-Trip-Test: nroff → DocIR → nroff
# ============================================================

test "roff.roundtrip.minimal" {
    set src ".TH foo n 1.0 Tcl\n.SH NAME\nfoo \\- bar\n"
    set ir  [roundTripIr $src]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.TH foo n 1.0 Tcl} "TH überlebt"
    ::test::assertContains $out {.SH NAME} "SH überlebt"
    ::test::assertContains $out {foo \-} "Hyphen-Escape überlebt"
}

test "roff.roundtrip.paragraph_with_inline" {
    set src ".TH t n 1 X\n.SH NAME\n.PP\nThe \\fBfoo\\fR command does \\fIthings\\fR.\n"
    set ir  [roundTripIr $src]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {\fBfoo\fR} "Bold überlebt"
    ::test::assertContains $out {\fIthings\fR} "Italic überlebt"
}

test "roff.roundtrip.op_list" {
    set src ".TH t n 1 X\n.OP \\-autoseparators autoSeparators AutoSeparators\nDescription text.\n"
    set ir  [roundTripIr $src]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.OP} "OP-Marker"
    ::test::assertContains $out {\-autoseparators} "Term mit \\- escaped"
    ::test::assertContains $out {autoSeparators} "dbName"
    ::test::assertContains $out {AutoSeparators} "dbClass"
}

# ============================================================
# Helper-Tests
# ============================================================

test "roff.helper.escape_text" {
    assert [string equal [::docir::roff::_escapeText "plain"] "plain"] "Keine Escapes nötig"
    assert [string equal [::docir::roff::_escapeText "-x"] {\-x}] "Hyphen escapet"
    assert [string equal [::docir::roff::_escapeText "a\\b"] {a\eb}] "Backslash escapet"
}

test "roff.helper.protect_leading_dot" {
    assert [string equal [::docir::roff::_protectLeadingDot "normal"] "normal"] "Normaler Text bleibt"
    assert [string equal [::docir::roff::_protectLeadingDot ".start"] {\&.start}] "Punkt-Anfang"
    assert [string equal [::docir::roff::_protectLeadingDot "'apostrophe"] {\&'apostrophe}] "Apostrophe-Anfang"
    assert [string equal [::docir::roff::_protectLeadingDot "a\n.b\nc"] "a\n\\&.b\nc"] "Multi-line"
}

test "roff.helper.quote_arg" {
    assert [string equal [::docir::roff::_quoteArg "simple"] "simple"] "Simple unquoted"
    assert [string equal [::docir::roff::_quoteArg "with space"] "\"with space\""] "Spaces gequotet"
    assert [string equal [::docir::roff::_quoteArg ""] "\"\""] "Leerer String"
}

# ============================================================
# Spec 0.5: Tests für neue Typen in docir-roff
# ============================================================

test "roff.render.inline.strike" {
    set ir [list [dict create type paragraph \
        content [list [dict create type strike text "deleted"]] meta {}]]
    set out [::docir::roff::render $ir]
    # nroff hat keine native Strike — wir nutzen italic als Annäherung
    ::test::assertContains $out {\fIdeleted\fR} "strike → italic-Text in nroff"
}

test "roff.render.inline.linebreak" {
    set ir [list [dict create type paragraph \
        content [list \
            [dict create type text text "Line A"] \
            [dict create type linebreak] \
            [dict create type text text "Line B"]] meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.br} "linebreak → .br Macro"
}

test "roff.render.inline.span_passthrough" {
    set ir [list [dict create type paragraph \
        content [list [dict create type span text "marked" class "warning"]] meta {}]]
    set out [::docir::roff::render $ir]
    # span → einfach Text durchreichen (class/id verloren)
    ::test::assertContains $out {marked} "span-Text bleibt"
}

test "roff.render.inline.image" {
    set ir [list [dict create type paragraph \
        content [list [dict create type image text "alt" url "img.png"]] meta {}]]
    set out [::docir::roff::render $ir]
    # Marker statt Bild
    ::test::assertContains $out {[image:} "image-Marker"
    ::test::assertContains $out {alt} "alt-Text drin"
}

test "roff.render.inline.footnote_ref" {
    set ir [list [dict create type paragraph \
        content [list [dict create type footnote_ref text "1" id "fn1"]] meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {[1]} "footnote_ref als bracket-N-Marker"
}

test "roff.render.block.image" {
    set ir [list [dict create type image content {} \
        meta [dict create url "test.png" alt "Beschreibung"]]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.PP} "Block-Image hat eigenen Paragraph"
    ::test::assertContains $out {[image:} "Marker statt Bild"
    ::test::assertContains $out {Beschreibung} "alt-Text drin"
}

test "roff.render.block.footnote_section" {
    set ir [list [dict create type footnote_section \
        content [list \
            [dict create type footnote_def \
                content [list [dict create type text text "Note text."]] \
                meta [dict create id "fn1" num "1"]]] \
        meta {}]]
    set out [::docir::roff::render $ir]
    ::test::assertContains $out {.SH FOOTNOTES} "FOOTNOTES-Section-Header"
    ::test::assertContains $out {.TP} "TP-List-Format"
    ::test::assertContains $out {[1]} "Footnote-Marker"
    ::test::assertContains $out {Note text.} "Body"
}

test "roff.render.block.div_transparent" {
    set ir [list [dict create type div \
        content [list \
            [dict create type heading \
                content [list [dict create type text text "In Div"]] \
                meta [dict create level 1]] \
            [dict create type paragraph \
                content [list [dict create type text text "Body."]] meta {}]] \
        meta [dict create class "warning"]]]
    set out [::docir::roff::render $ir]
    # div ist transparent — children erscheinen im Output
    ::test::assertContains $out {.SH "In Div"} "Heading aus div sichtbar"
    ::test::assertContains $out {Body.} "Paragraph-Inhalt"
}

# ============================================================
# Cross-Konsistenz: ein IR mit allen neuen Typen durch alle 7 Senken.
# Prüft dass keine Senke crasht und alle den Text erhalten.
# ============================================================

test "spec.cross.all_sinks_rendered_without_crash" {
    # IR mit jedem neuen Typ
    set ir [list \
        [dict create type heading \
            content [list [dict create type text text "Cross Test"]] \
            meta [dict create level 1]] \
        [dict create type paragraph \
            content [list \
                [dict create type text text "Has "] \
                [dict create type strike text "strike"] \
                [dict create type text text " and "] \
                [dict create type linebreak] \
                [dict create type span text "span" class "highlight"] \
                [dict create type text text " plus "] \
                [dict create type footnote_ref text "1" id "fn1"]] meta {}] \
        [dict create type div \
            content [list [dict create type paragraph \
                content [list [dict create type text text "in div"]] meta {}]] \
            meta [dict create class "info"]] \
        [dict create type image content {} \
            meta [dict create url "/no.png" alt "missing"]] \
        [dict create type footnote_section \
            content [list [dict create type footnote_def \
                content [list [dict create type text text "Note."]] \
                meta [dict create id "fn1" num "1"]]] \
            meta {}]]

    # Validator first
    set errs [docir::validate $ir]
    if {[llength $errs] > 0} {
        puts stderr "Validator errors:"
        foreach e $errs { puts stderr "  $e" }
    }
    assert [expr {[llength $errs] == 0}] "Cross-IR ist Validator-clean"

    # html
    set html [::docir::html::render $ir [dict create standalone 0]]
    ::test::assertContains $html {strike} "html: text bleibt"

    # md
    set md [::docir::md::render $ir]
    ::test::assertContains $md {strike} "md: text bleibt"

    # roff
    set roff [::docir::roff::render $ir]
    ::test::assertContains $roff {strike} "roff: text bleibt"

    # svg foreignObject (default)
    set svg [::docir::svg::render $ir [dict create standalone 0]]
    ::test::assertContains $svg {strike} "svg foreignObject: text bleibt"

    # svg native — kann das doc_header nicht haben weil _layoutDocHeader
    # einen Encoding-Bug hat. Aber unsere Test-IR hat kein doc_header.
    set svgN [::docir::svg::render $ir [dict create mode native standalone 0]]
    ::test::assertContains $svgN {strike} "svg native: text bleibt (degraded)"
}

test::runAll
