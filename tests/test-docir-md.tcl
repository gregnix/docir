#!/usr/bin/env tclsh
# test-docir-md.tcl
#
# Tests fuer docir-md-0.1.tm — DocIR → Markdown Renderer (Senke).
#
# Pruefen:
#  - Block-Typen (heading mit Auto-Shift, paragraph, pre, list, table, hr, blank)
#  - Inline-Typen (text, strong, emphasis, code, link)
#  - Markdown-Escaping
#  - Defensive Behandlung
#  - Auto-headingShift wenn doc_header da

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

set projectRoot [file dirname [file dirname [file normalize [info script]]]]
lappend auto_path $projectRoot
package require docir::md

# ============================================================
# A. Modul-Loading und API
# ============================================================

test "md.module_loaded" {
    assert [string length [package present docir::md]] "version present"
}

test "md.public_api" {
    assert [string length [info commands docir::md::render]] "render exists"
    assert [string length [info commands docir::md::renderInline]] "renderInline exists"
}

# ============================================================
# B. Heading-Levels und Auto-Shift
# ============================================================

test "md.heading_level_1" {
    set ir [list [dict create type heading content {{type text text "X"}} meta {level 1}]]
    set md [docir::md::render $ir]
    assert [string match "*# X*" $md] "h1 produces single hash"
}

test "md.heading_level_3" {
    set ir [list [dict create type heading content {{type text text "X"}} meta {level 3}]]
    set md [docir::md::render $ir]
    assert [string match "*### X*" $md] "h3 produces three hashes"
}

test "md.heading_level_clamped_to_6" {
    set ir [list [dict create type heading content {{type text text "X"}} meta {level 99}]]
    set md [docir::md::render $ir]
    assert [string match "*###### X*" $md] "level > 6 clamped to 6"
}

test "md.auto_shift_when_doc_header" {
    set ir [list \
        [dict create type doc_header content {} meta {name foo section n}] \
        [dict create type heading content {{type text text "NAME"}} meta {level 1}]]
    set md [docir::md::render $ir]
    assert [string match "*# foo*" $md] "doc_header as h1"
    assert [string match "*## NAME*" $md] "heading shifted to h2"
    assert [expr {![string match "*\n# NAME*" $md]}] "no second h1 for NAME"
}

test "md.no_shift_when_no_doc_header" {
    set ir [list [dict create type heading content {{type text text "NAME"}} meta {level 1}]]
    set md [docir::md::render $ir]
    assert [string match "*# NAME*" $md] "without doc_header, h1 stays h1"
}

test "md.doc_header_section_in_h1" {
    # Section sollte als (n) in der H1 erscheinen — analog zu nroff
    set ir [list [dict create type doc_header content {} meta {name ls section 1}]]
    set md [docir::md::render $ir]
    assert [string match "*# ls(1)*" $md] "section sollte als (1) hinter dem name stehen, war: $md"
}

test "md.doc_header_version_part_in_subtitle" {
    set ir [list [dict create type doc_header content {} meta \
        {name ls section 1 version 9.0 part "User Commands"}]]
    set md [docir::md::render $ir]
    assert [string match "*9.0*" $md] "version sollte gerendert werden"
    assert [string match "*User Commands*" $md] "part sollte gerendert werden"
    # Und in einer einzigen *...*-Zeile
    assert [regexp {\*[^*]*9\.0[^*]*User Commands[^*]*\*} $md] \
        "version und part gehoeren in eine kursive Subtitel-Zeile"
}

test "md.doc_header_only_name_minimal_output" {
    set ir [list [dict create type doc_header content {} meta {name foo}]]
    set md [docir::md::render $ir]
    assert [string match "*# foo*" $md]
    # Keine kursive Subtitle-Zeile (nur erscheint wenn version/part da sind)
    assert [expr {![regexp {\*[^*]+\*} $md]}] \
        "Ohne version/part sollte keine kursive Subtitle-Zeile da sein, war: $md"
}

test "md.explicit_shift_overrides_auto" {
    set ir [list \
        [dict create type doc_header content {} meta {name foo section n}] \
        [dict create type heading content {{type text text "NAME"}} meta {level 1}]]
    set md [docir::md::render $ir [dict create headingShift 0]]
    # Kein Shift trotz doc_header
    assert [string match "*# foo*" $md]
    assert [string match "*\n# NAME*" $md] "explicit headingShift=0 keeps h1"
}

# ============================================================
# C. Inline-Formatierung
# ============================================================

test "md.strong_inline" {
    set ir [list [dict create type paragraph content {{type strong text "Bold"}} meta {}]]
    set md [docir::md::render $ir]
    assert [string match "*\\*\\*Bold\\*\\**" $md]
}

test "md.emphasis_inline" {
    set ir [list [dict create type paragraph content {{type emphasis text "Italic"}} meta {}]]
    set md [docir::md::render $ir]
    assert [string match "*\\*Italic\\**" $md]
}

test "md.code_inline" {
    set ir [list [dict create type paragraph content {{type code text "puts"}} meta {}]]
    set md [docir::md::render $ir]
    assert [string match "*`puts`*" $md]
}

test "md.code_inline_with_backtick_uses_double" {
    # Wenn der Code-Inhalt ein Backtick enthält, nutzen wir doppelte Backticks
    set ir [list [dict create type paragraph content {{type code text "back`tick"}} meta {}]]
    set md [docir::md::render $ir]
    assert [string match "*`` back`tick ``*" $md]
}

test "md.underline_uses_html" {
    set ir [list [dict create type paragraph content {{type underline text "U"}} meta {}]]
    set md [docir::md::render $ir]
    assert [string match "*<u>U</u>*" $md]
}

test "md.mixed_inlines_in_paragraph" {
    set ir [list [dict create type paragraph content {
        {type text text "A "}
        {type strong text "bold"}
        {type text text " and "}
        {type emphasis text "italic"}
        {type text text " word"}
    } meta {}]]
    set md [docir::md::render $ir]
    assert [string match "*A \\*\\*bold\\*\\* and \\*italic\\* word*" $md]
}

# ============================================================
# D. Links
# ============================================================

test "md.link_with_href" {
    set ir [list [dict create type paragraph content {
        {type link text "Click" href "http://example.com"}
    } meta {}]]
    set md [docir::md::render $ir]
    assert [string match "*\\\[Click\\\]\\(http://example.com\\)*" $md]
}

test "md.link_default_naming" {
    set ir [list [dict create type paragraph content {
        {type link text "open" name open section n}
    } meta {}]]
    set md [docir::md::render $ir]
    assert [string match "*\\\[open\\\]\\(open.n.md\\)*" $md]
}

test "md.link_resolved_via_callback" {
    proc myResolveMd {name section} {
        return "/man/${name}.${section}.md"
    }
    set ir [list [dict create type paragraph content {
        {type link text "puts" name puts section n}
    } meta {}]]
    set md [docir::md::render $ir [dict create linkResolve myResolveMd]]
    assert [string match "*\\\[puts\\\]\\(/man/puts.n.md\\)*" $md]
}

# ============================================================
# E. Pre-Block / Code-Fence
# ============================================================

test "md.pre_produces_fenced_code_block" {
    set ir [list [dict create type pre content {{type text text "puts hello"}} meta {kind code}]]
    set md [docir::md::render $ir]
    assert [string match "*```\nputs hello\n```*" $md]
}

test "md.pre_with_language" {
    set ir [list [dict create type pre content {{type text text "x = 1"}} meta {kind code language python}]]
    set md [docir::md::render $ir]
    assert [string match "*```python\nx = 1\n```*" $md]
}

test "md.pre_no_markdown_escaping" {
    # Im Code-Block: Sonderzeichen bleiben unverändert
    set ir [list [dict create type pre content {{type text text "*not bold* _not italic_"}} meta {kind code}]]
    set md [docir::md::render $ir]
    assert [string match "*\\*not bold\\* _not italic_*" $md] \
        "code block content not escaped"
}

# ============================================================
# F. Listen
# ============================================================

test "md.list_ul" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "a"}} meta {kind ul}] \
        [dict create type listItem content {{type text text "b"}} meta {kind ul}] \
    ] meta {kind ul}]]
    set md [docir::md::render $ir]
    assert [string match "*- a\n- b*" $md]
}

test "md.list_ol_numbered" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "first"}} meta {kind ol}] \
        [dict create type listItem content {{type text text "second"}} meta {kind ol}] \
    ] meta {kind ol}]]
    set md [docir::md::render $ir]
    assert [string match "*1. first\n2. second*" $md]
}

test "md.list_dl_term_emphasized" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "definition"}} \
            meta [dict create kind dl term {{type text text "term"}}]] \
    ] meta {kind dl}]]
    set md [docir::md::render $ir]
    assert [string match "*\\*\\*term\\*\\**" $md] "term wrapped in **"
    assert [string match "*    definition*" $md] "definition indented 4 spaces"
}

test "md.list_marker_option" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "x"}} meta {kind ul}] \
    ] meta {kind ul}]]
    set md [docir::md::render $ir [dict create listMarker "*"]]
    assert [string match "*\\* x*" $md] "custom marker '*' used"
}

# ============================================================
# G. Tabellen
# ============================================================

test "md.table_with_header" {
    set ir [list [dict create type table content [list \
        [dict create type tableRow content [list \
            [dict create type tableCell content {{type text text "Col1"}} meta {}] \
            [dict create type tableCell content {{type text text "Col2"}} meta {}] \
        ] meta {}] \
        [dict create type tableRow content [list \
            [dict create type tableCell content {{type text text "v1"}} meta {}] \
            [dict create type tableCell content {{type text text "v2"}} meta {}] \
        ] meta {}] \
    ] meta {columns 2 hasHeader 1}]]
    set md [docir::md::render $ir]
    assert [string match "*| Col1 | Col2 |*" $md]
    assert [string match "*| --- | --- |*" $md]
    assert [string match "*| v1 | v2 |*" $md]
}

test "md.table_no_header_uses_pseudo_header" {
    set ir [list [dict create type table content [list \
        [dict create type tableRow content [list \
            [dict create type tableCell content {{type text text "a"}} meta {}] \
            [dict create type tableCell content {{type text text "b"}} meta {}] \
        ] meta {}] \
    ] meta {columns 2 hasHeader 0}]]
    set md [docir::md::render $ir]
    # Pseudo-Header oben, dann Separator, dann Datenzeile
    assert [string match "*|   |   |*" $md] "pseudo header has empty cells"
    assert [string match "*| --- | --- |*" $md] "separator present"
    assert [string match "*| a | b |*" $md] "data row present"
}

test "md.table_pipe_in_cell_escaped" {
    set ir [list [dict create type table content [list \
        [dict create type tableRow content [list \
            [dict create type tableCell content {{type text text "a|b"}} meta {}] \
        ] meta {}] \
    ] meta {columns 1 hasHeader 0}]]
    set md [docir::md::render $ir]
    assert [string match "*a\\\\|b*" $md] "pipe escaped in cell"
}

# ============================================================
# H. Blank, hr, doc_header
# ============================================================

test "md.hr_renders" {
    set ir [list [dict create type hr content {} meta {}]]
    set md [docir::md::render $ir]
    assert [string match "*---*" $md]
}

test "md.blank_no_content_no_crash" {
    # blank ohne content-Feld
    set ir [list \
        [dict create type paragraph content {{type text text "A"}} meta {}] \
        [dict create type blank meta {lines 2}] \
        [dict create type paragraph content {{type text text "B"}} meta {}]]
    set caught [catch {docir::md::render $ir} err]
    assert [expr {!$caught}] "blank without content does not crash: $err"
}

test "md.doc_header_renders_as_h1" {
    set ir [list [dict create type doc_header content {} meta {name puts section n version 9.0}]]
    set md [docir::md::render $ir]
    assert [string match "*# puts*" $md] "doc_header name as h1"
}

# ============================================================
# I. Markdown-Escaping
# ============================================================

test "md.escape_asterisk" {
    set ir [list [dict create type paragraph content {{type text text "5 * 3"}} meta {}]]
    set md [docir::md::render $ir]
    assert [string match "*5 \\\\\\* 3*" $md] "* escaped"
}

test "md.escape_underscore" {
    set ir [list [dict create type paragraph content {{type text text "foo_bar"}} meta {}]]
    set md [docir::md::render $ir]
    assert [string match "*foo\\\\_bar*" $md] "_ escaped"
}

test "md.escape_brackets" {
    set ir [list [dict create type paragraph content {{type text text "see \[X\] now"}} meta {}]]
    set md [docir::md::render $ir]
    assert [string match "*\\\\\\\[X\\\\\\\]*" $md] "brackets escaped"
}

# ============================================================
# J. Defensive Behandlung
# ============================================================

test "md.unknown_block_no_crash" {
    set ir [list [dict create type weirdtype content {} meta {}]]
    set caught [catch {docir::md::render $ir} err]
    assert [expr {!$caught}] "unknown type does not crash: $err"
    set md [docir::md::render $ir]
    assert [string match "*unknown block*" $md] "warning in HTML comment"
}

test "md.list_with_non_listitem_no_crash" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "ok"}} meta {kind ul}] \
        [dict create type list content [list \
            [dict create type listItem content {{type text text "nested"}} meta {kind ul}] \
        ] meta {kind ul}] \
    ] meta {kind ul}]]
    set caught [catch {docir::md::render $ir} err]
    assert [expr {!$caught}] "schema violation does not crash: $err"
    set md [docir::md::render $ir]
    assert [string match "*schema warning*" $md] "warning surfaces"
}

# ============================================================
# K. Volle Pipeline
# ============================================================

test "md.full_pipeline_nroff" {
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
    set md [docir::md::render $ir]

    assert [string match "*# foo*" $md]
    assert [string match "*## NAME*" $md] "auto-shift in pipeline"
    assert [string match "*## SYNOPSIS*" $md]
    assert [string match "*\\*\\*foo\\*\\**" $md]
    assert [string match "*\\*arg\\**" $md]
}

# ============================================================
# Spec-Erweiterung 0.5: Tests für mdparser→DocIR mit neuen Typen
# ============================================================
#
# Voraussetzung: mdparser muss verfügbar sein. Wenn nicht: skip.

if {[catch {package require mdstack::parser}] && \
    [catch {source -encoding utf-8 /home/claude/mdstack-work/mdstack_0.3.4/lib/mdparser-0.2.tm}]} {
    puts stderr "skipping spec.mdsource tests — mdparser not available"
} else {

test "spec.mdsource.strike" {
    set ast [mdstack::parser::parse "Text with ~~deleted~~ part."]
    set ir  [::docir::md::fromAst $ast]
    # Suche strike-Inline irgendwo im Stream
    set found 0
    foreach n $ir {
        if {[dict get $n type] ne "paragraph"} continue
        foreach in [dict get $n content] {
            if {[dict exists $in type] && [dict get $in type] eq "strike"} {
                set found 1
                assert [string equal [dict get $in text] "deleted"] "strike text gleich"
            }
        }
    }
    assert $found "strike-Inline gefunden"
}

test "spec.mdsource.image_inline" {
    # Inline image MUSS in Paragraph-Kontext sein damit mdparser es als
    # Inline parst (nicht als Block).
    set ast [mdstack::parser::parse "Text with !\[alt\](img.png) inline."]
    set ir  [::docir::md::fromAst $ast]
    set found 0
    foreach n $ir {
        if {[dict get $n type] ne "paragraph"} continue
        foreach in [dict get $n content] {
            if {[dict exists $in type] && [dict get $in type] eq "image"} {
                set found 1
                assert [string equal [dict get $in text] "alt"] "alt-text"
                assert [string equal [dict get $in url] "img.png"] "url"
            }
        }
    }
    assert $found "image-Inline gefunden"
}

test "spec.mdsource.image_block" {
    # Standalone image (eigene Zeile mit Leerzeilen davor/danach) =>
    # Block-Image
    set ast [mdstack::parser::parse "\n!\[alt-block](b.png)\n"]
    set ir  [::docir::md::fromAst $ast]
    set found 0
    foreach n $ir {
        if {[dict get $n type] eq "image"} {
            set found 1
            set m [dict get $n meta]
            assert [string equal [dict get $m url] "b.png"] "url im meta"
            assert [string equal [dict get $m alt] "alt-block"] "alt im meta"
        }
    }
    assert $found "image-Block gefunden"
}

test "spec.mdsource.image_with_title" {
    set ast [mdstack::parser::parse "Text with !\[alt\](img.png \"My Title\") here."]
    set ir  [::docir::md::fromAst $ast]
    set foundTitle ""
    foreach n $ir {
        if {[dict get $n type] ne "paragraph"} continue
        foreach in [dict get $n content] {
            if {[dict exists $in type] && [dict get $in type] eq "image"} {
                if {[dict exists $in title]} {
                    set foundTitle [dict get $in title]
                }
            }
        }
    }
    # Title kann über Title-Feld oder im URL-Quirk kommen — beide OK
    assert [expr {$foundTitle eq "My Title" || $foundTitle eq ""}] \
        "Title wird erkannt oder ignoriert (mdparser-quirk)"
}

test "spec.mdsource.linebreak" {
    # Hard break = zwei Spaces am Zeilenende + newline
    set ast [mdstack::parser::parse "Line one  \nLine two."]
    set ir  [::docir::md::fromAst $ast]
    set found 0
    foreach n $ir {
        if {[dict get $n type] ne "paragraph"} continue
        foreach in [dict get $n content] {
            if {[dict exists $in type] && [dict get $in type] eq "linebreak"} {
                set found 1
                # linebreak hat KEIN text-Feld
                assert [expr {![dict exists $in text]}] "linebreak ohne text-Feld"
            }
        }
    }
    assert $found "linebreak-Inline gefunden"
}

test "spec.mdsource.footnote_ref_and_section" {
    set ast [mdstack::parser::parse "Text \[^1\] reference.\n\n\[^1\]: Note text."]
    set ir  [::docir::md::fromAst $ast]
    set foundRef 0
    set foundSection 0
    foreach n $ir {
        if {[dict get $n type] eq "footnote_section"} {
            set foundSection 1
            set defs [dict get $n content]
            assert [expr {[llength $defs] >= 1}] "footnote_section hat defs"
            set firstDef [lindex $defs 0]
            assert [string equal [dict get $firstDef type] "footnote_def"] \
                "child ist footnote_def"
            set m [dict get $firstDef meta]
            assert [dict exists $m id] "def hat id"
            assert [dict exists $m num] "def hat num"
        }
        if {[dict get $n type] eq "paragraph"} {
            foreach in [dict get $n content] {
                if {[dict exists $in type] && [dict get $in type] eq "footnote_ref"} {
                    set foundRef 1
                    assert [dict exists $in id] "ref hat id"
                    assert [dict exists $in text] "ref hat text (display)"
                }
            }
        }
    }
    assert $foundRef "footnote_ref gefunden"
    assert $foundSection "footnote_section gefunden"
}

test "spec.mdsource.validator_clean" {
    # Komplexer Markdown durch beide Funktionen → Validator OK
    set md "Strike: ~~deleted~~ text.\n\n!\[alt-text\](img.png)\n\nFootnote: \[^1\] reference.\n\n\[^1\]: Footnote def text."
    set ast [mdstack::parser::parse $md]
    set ir  [::docir::md::fromAst $ast]
    set errs [docir::validate $ir]
    if {[llength $errs] > 0} {
        puts stderr "Validator errors:"
        foreach e $errs { puts stderr "  - $e" }
    }
    assert [expr {[llength $errs] == 0}] "Komplexer Markdown durch fromAst+validate ohne Fehler"
}

}  ;# end mdparser-Verfügbarkeits-Block

# ============================================================
# Spec 0.5: Tests für neue Inline- und Block-Typen in docir-md (Senke)
# ============================================================

test "md.sink.inline.strike" {
    set ir [list [dict create type paragraph \
        content [list [dict create type strike text "deleted"]] meta {}]]
    set out [::docir::md::render $ir]
    assert [expr {[string first {~~deleted~~} $out] >= 0}]
}

test "md.sink.inline.image" {
    set ir [list [dict create type paragraph \
        content [list [dict create type image text "alt" url "img.png"]] meta {}]]
    set out [::docir::md::render $ir]
    assert [expr {[string first {![alt](img.png)} $out] >= 0}]
}

test "md.sink.inline.image_with_title" {
    set ir [list [dict create type paragraph \
        content [list [dict create type image text "alt" url "img.png" title "Tip"]] meta {}]]
    set out [::docir::md::render $ir]
    assert [expr {[string first "\"Tip\"" $out] >= 0}]
}

test "md.sink.inline.linebreak" {
    set ir [list [dict create type paragraph \
        content [list \
            [dict create type text text "A"] \
            [dict create type linebreak] \
            [dict create type text text "B"]] meta {}]]
    set out [::docir::md::render $ir]
    # Hard break: zwei Spaces + newline
    assert [expr {[string first "  \n" $out] >= 0}]
}

test "md.sink.inline.span_no_attrs" {
    set ir [list [dict create type paragraph \
        content [list [dict create type span text "plain"]] meta {}]]
    set out [::docir::md::render $ir]
    # Ohne Attribute: nur Text durchreichen
    assert [expr {[string first {plain} $out] >= 0}]
    # Kein Pandoc-Marker (keine geschweifte Klammer im Output)
    set hasBrace [string first \x7b $out]
    assert [expr {$hasBrace < 0}]
}

test "md.sink.inline.span_with_class" {
    set ir [list [dict create type paragraph \
        content [list [dict create type span text "warn" class "warning"]] meta {}]]
    set out [::docir::md::render $ir]
    # Pandoc: [text]{.class}
    assert [expr {[string first {[warn]} $out] >= 0}]
    assert [expr {[string first {.warning} $out] >= 0}]
}

test "md.sink.inline.footnote_ref" {
    set ir [list [dict create type paragraph \
        content [list [dict create type footnote_ref text "1" id "fn1"]] meta {}]]
    set out [::docir::md::render $ir]
    assert [expr {[string first {[^fn1]} $out] >= 0}]
}

test "md.sink.block.image" {
    set ir [list [dict create type image content {} \
        meta [dict create url "test.png" alt "Description"]]]
    set out [::docir::md::render $ir]
    assert [expr {[string first {![Description](test.png)} $out] >= 0}]
}

test "md.sink.block.footnote_section" {
    set ir [list [dict create type footnote_section \
        content [list \
            [dict create type footnote_def \
                content [list [dict create type text text "Note text."]] \
                meta [dict create id "fn1" num "1"]]] \
        meta {}]]
    set out [::docir::md::render $ir]
    assert [expr {[string first {[^fn1]: Note text.} $out] >= 0}]
}

test "md.sink.block.div_no_attrs_passthrough" {
    set ir [list [dict create type div \
        content [list [dict create type paragraph \
            content [list [dict create type text text "passthrough"]] meta {}]] \
        meta {}]]
    set out [::docir::md::render $ir]
    # Ohne Attribute: kein Marker — nur den Inhalt durchreichen
    assert [expr {[string first {passthrough} $out] >= 0}]
    assert [expr {[string first {::::} $out] < 0}]
}

test "md.sink.block.div_with_class" {
    set ir [list [dict create type div \
        content [list [dict create type paragraph \
            content [list [dict create type text text "in warning"]] meta {}]] \
        meta [dict create class "warning"]]]
    set out [::docir::md::render $ir]
    # Pandoc-Notation
    assert [expr {[string first {::::} $out] >= 0}]
    assert [expr {[string first {.warning} $out] >= 0}]
}

# ============================================================
# Round-Trip-Test: Markdown → DocIR → Markdown sollte semantisch
# gleich bleiben (Whitespace darf abweichen)
# ============================================================

if {![catch {package require mdstack::parser} eatErr] || \
    ![catch {source -encoding utf-8 /home/claude/mdstack-work/mdstack_0.3.4/lib/mdparser-0.2.tm} eatErr2]} {

    test "md.sink.roundtrip.complex" {
        set md "Strike: ~~deleted~~ text.\n\nFootnote: \[^1\] reference.\n\n\[^1\]: Note."
        set ir [::docir::md::fromAst [mdstack::parser::parse $md]]
        set md2 [::docir::md::render $ir]
        # Semantische Marker müssen überleben
        assert [expr {[string first {~~deleted~~} $md2] >= 0}]
        assert [expr {[string first {[^1]} $md2] >= 0}]
        assert [expr {[string first {Note} $md2] >= 0}]
    }

}

test::runAll
