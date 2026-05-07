#!/usr/bin/env tclsh
# test-docir-html.tcl
#
# Tests fuer docir-html-0.1.tm — DocIR → HTML Renderer.
#
# Pruefen:
#  - Block-Typen (heading, paragraph, pre, list, table, hr, blank)
#  - Inline-Typen (text, strong, emphasis, code, link)
#  - HTML-Escaping (Sonderzeichen sicher escapt)
#  - Defensive Behandlung (unbekannte Typen, Schema-Verletzungen)
#  - Standalone-Mode vs Body-only

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

# docir-html laden
set projectRoot [file dirname [file dirname [file normalize [info script]]]]
lappend auto_path $projectRoot
package require docir::html

# ============================================================
# A. Standalone-Output und Document-Wrapping
# ============================================================

test "html.standalone_has_doctype_and_html_tags" {
    set ir [list [dict create type heading content {{type text text Hello}} meta {level 1}]]
    set out [docir::html::render $ir]
    assert [string match "*<!DOCTYPE html>*" $out] "doctype present"
    assert [string match "*<html lang=\"en\">*" $out] "html opening tag"
    assert [string match "*</html>*" $out] "html closing tag"
    assert [string match "*<body>*" $out] "body opening tag"
}

test "html.body_only_no_html_wrapper" {
    set ir [list [dict create type heading content {{type text text Hello}} meta {level 1}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [expr {![string match "*<!DOCTYPE*" $out]}] "no doctype in body-only"
    assert [expr {![string match "*<html*" $out]}] "no html tag in body-only"
    assert [string match "*<h1*>Hello</h1>*" $out] "heading still rendered"
}

test "html.title_from_doc_header" {
    set ir [list \
        [dict create type doc_header content {} meta {name puts section n version 9.0 part Tcl}] \
        [dict create type heading content {{type text text NAME}} meta {level 1}]]
    set out [docir::html::render $ir]
    assert [string match "*<title>puts(n)</title>*" $out] "title from doc_header"
}

test "html.title_from_first_heading_when_no_doc_header" {
    set ir [list [dict create type heading content {{type text text "My Page"}} meta {level 1}]]
    set out [docir::html::render $ir]
    assert [string match "*<title>My Page</title>*" $out] "title from first heading"
}

test "html.title_explicit_overrides" {
    set ir [list [dict create type heading content {{type text text NAME}} meta {level 1}]]
    set out [docir::html::render $ir [dict create title "Explicit Title"]]
    assert [string match "*<title>Explicit Title</title>*" $out] "explicit title used"
}

# ============================================================
# B. Heading-Levels und IDs
# ============================================================

test "html.heading_level_1" {
    set ir [list [dict create type heading content {{type text text Foo}} meta {level 1}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<h1*>Foo</h1>*" $out]
}

test "html.heading_level_3" {
    set ir [list [dict create type heading content {{type text text Foo}} meta {level 3}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<h3*>Foo</h3>*" $out]
}

test "html.heading_level_clamped_to_6" {
    set ir [list [dict create type heading content {{type text text Foo}} meta {level 99}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<h6*>Foo</h6>*" $out] "level > 6 clamped to 6"
}

test "html.heading_with_id" {
    set ir [list [dict create type heading content {{type text text Foo}} meta {level 1 id foo}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<h1 id=\"foo\">Foo</h1>*" $out]
}

# ============================================================
# C. Inline-Formatierung
# ============================================================

test "html.inline_strong" {
    set ir [list [dict create type paragraph content {{type strong text Bold}} meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<strong>Bold</strong>*" $out]
}

test "html.inline_emphasis" {
    set ir [list [dict create type paragraph content {{type emphasis text Italic}} meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<em>Italic</em>*" $out]
}

test "html.inline_code" {
    set ir [list [dict create type paragraph content {{type code text foo()}} meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<code>foo()</code>*" $out]
}

test "html.inline_underline" {
    set ir [list [dict create type paragraph content {{type underline text Under}} meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<u>Under</u>*" $out]
}

test "html.inline_mixed_in_paragraph" {
    set ir [list [dict create type paragraph content {
        {type text text "A "}
        {type strong text bold}
        {type text text " and "}
        {type emphasis text italic}
        {type text text " word"}
    } meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*A <strong>bold</strong> and <em>italic</em> word*" $out]
}

# ============================================================
# D. Link-Inlines
# ============================================================

test "html.link_with_explicit_href" {
    set ir [list [dict create type paragraph content {
        {type link text "Click" href "http://example.com"}
    } meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<a href=\"http://example.com\">Click</a>*" $out]
}

test "html.link_resolved_via_callback" {
    proc myResolve {name section} {
        return "/man/${name}.${section}.html"
    }
    set ir [list [dict create type paragraph content {
        {type link text "puts" name puts section n}
    } meta {}]]
    set out [docir::html::render $ir [dict create standalone 0 linkResolve myResolve]]
    assert [string match "*<a href=\"/man/puts.n.html\">puts</a>*" $out]
}

test "html.link_default_naming_no_callback" {
    set ir [list [dict create type paragraph content {
        {type link text "open" name open section n}
    } meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<a href=\"open.n.html\">open</a>*" $out]
}

# ============================================================
# E. Listen
# ============================================================

test "html.list_unordered" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "a"}} meta {kind ul}] \
        [dict create type listItem content {{type text text "b"}} meta {kind ul}] \
    ] meta {kind ul}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<ul class=\"docir-list-ul\">*" $out]
    assert [string match "*<li>a</li>*" $out]
    assert [string match "*<li>b</li>*" $out]
}

test "html.list_ordered" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "first"}} meta {kind ol}] \
    ] meta {kind ol}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<ol class=\"docir-list-ol\">*" $out]
    assert [string match "*<li>first</li>*" $out]
}

test "html.list_dl_with_term" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "definition"}} \
            meta [dict create kind dl term {{type text text "term"}}]] \
    ] meta {kind dl}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<dl*" $out]
    assert [string match "*<dt>term</dt>*" $out]
    assert [string match "*<dd>definition</dd>*" $out]
}

# ============================================================
# F. Code-Blöcke / pre
# ============================================================

test "html.pre_code_block" {
    set ir [list [dict create type pre content {{type text text "puts hello"}} meta {kind code}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<pre><code>puts hello</code></pre>*" $out]
}

test "html.pre_code_block_with_language" {
    set ir [list [dict create type pre content {{type text text "puts hello"}} meta {kind code language tcl}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<code class=\"language-tcl\">*" $out]
}

# ============================================================
# G. Tabellen
# ============================================================

test "html.table_basic" {
    set ir [list [dict create type table content [list \
        [dict create type tableRow content [list \
            [dict create type tableCell content {{type text text "a"}} meta {}] \
            [dict create type tableCell content {{type text text "b"}} meta {}] \
        ] meta {}] \
    ] meta {columns 2 hasHeader 0}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<table*" $out]
    assert [string match "*<td>a</td>*" $out]
    assert [string match "*<td>b</td>*" $out]
}

test "html.table_with_header" {
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
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<th>Col1</th>*" $out] "header row uses th"
    assert [string match "*<td>v1</td>*" $out] "data row uses td"
}

test "html.table_source_class" {
    set ir [list [dict create type table content [list \
        [dict create type tableRow content [list \
            [dict create type tableCell content {{type strong text "-bg"}} meta {}] \
        ] meta {}] \
    ] meta {columns 1 hasHeader 0 source standardOptions}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*class=\"docir-table docir-standardOptions\"*" $out]
}

# ============================================================
# H. Blank, hr, doc_header
# ============================================================

test "html.hr_renders" {
    set ir [list [dict create type hr content {} meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<hr/>*" $out]
}

test "html.blank_renders_br" {
    set ir [list [dict create type blank content {} meta {lines 2}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<br/>*" $out]
}

test "html.blank_no_content_field" {
    # blank-Nodes muessen ohne content-Feld funktionieren
    set ir [list [dict create type blank meta {lines 1}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<br/>*" $out] "blank without content rendered"
}

test "html.doc_header_renders" {
    set ir [list [dict create type doc_header content {} meta {name puts section n version 9.0}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<header class=\"manpage-header\">*" $out]
    assert [string match "*<h1>puts(n)*" $out] "name(section) als h1"
    assert [string match "*9.0*" $out]
}

# ============================================================
# I. Defensive Behandlung
# ============================================================

test "html.unknown_block_type_no_crash" {
    set ir [list [dict create type weirdtype content {} meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*docir-unknown*" $out] "unknown block has unknown class"
    assert [string match "*data-docir-type=\"weirdtype\"*" $out] "type captured in data attr"
}

test "html.unknown_inline_type_keeps_text" {
    set ir [list [dict create type paragraph content {
        {type text text "Some "}
        {type weirdinline text "weird"}
        {type text text " text"}
    } meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*Some *" $out]
    assert [string match "*weird*" $out] "unknown inline text preserved"
    assert [string match "* text*" $out]
    assert [string match "*data-docir-inline=\"weirdinline\"*" $out]
}

test "html.list_with_non_listitem_no_crash" {
    # Schema-Verletzung: list.content enthaelt Nicht-listItem
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "ok"}} meta {kind ul}] \
        [dict create type list content [list \
            [dict create type listItem content {{type text text "nested"}} meta {kind ul}] \
        ] meta {kind ul}] \
    ] meta {kind ul}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*ok*" $out]
    assert [string match "*nested*" $out]
    assert [string match "*schema warning*" $out] "warning in HTML comment"
}

# ============================================================
# J. HTML-Escaping
# ============================================================

test "html.text_escapes_lt_gt" {
    set ir [list [dict create type paragraph content {{type text text "a<b>c"}} meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*a&lt;b&gt;c*" $out] "< and > escaped"
}

test "html.text_escapes_amp" {
    set ir [list [dict create type paragraph content {{type text text "a & b"}} meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*a &amp; b*" $out] "& escaped"
}

test "html.text_escapes_quote" {
    set ir [list [dict create type paragraph content {{type text text "say \"hi\""}} meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*say &quot;hi&quot;*" $out] "quotes escaped"
}

test "html.attr_escaping_in_id" {
    set ir [list [dict create type heading content {{type text text X}} meta {level 1 id "a&b"}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*id=\"a&amp;b\"*" $out] "id attribute escaped"
}

# ============================================================
# K. Volle Pipeline-Tests
# ============================================================

test "html.full_pipeline_nroff_produces_valid_html" {
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
    set out [docir::html::render $ir]

    assert [string match "*<!DOCTYPE html>*" $out]
    assert [string match "*<title>foo(n)</title>*" $out]
    assert [string match "*<h1*>NAME*" $out]
    assert [string match "*<strong>foo</strong>*" $out]
    assert [string match "*<em>arg</em>*" $out]
}

test "html.body_only_can_be_embedded" {
    # Ein body-only Output sollte sich problemlos in einen anderen
    # HTML-Kontext einbetten lassen (kein doctype, kein html-Tag)
    set ir [list \
        [dict create type heading content {{type text text Hello}} meta {level 2}] \
        [dict create type paragraph content {{type text text World}} meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]

    assert [expr {![string match "*<!DOCTYPE*" $out]}]
    assert [expr {![string match "*<html*" $out]}]
    assert [expr {![string match "*<body*" $out]}]
    assert [string match "*<h2*>Hello</h2>*" $out]
    assert [string match "*<p>World</p>*" $out]
}

# ============================================================
# L. mvmantohtml-Parität: lang, viewport, themes
# ============================================================

test "html.lang_option" {
    set ir [list [dict create type paragraph content {{type text text "x"}} meta {}]]
    set out [docir::html::render $ir [dict create lang "de"]]
    assert [string match "*<html lang=\"de\">*" $out]
}

test "html.lang_default_is_en" {
    set ir [list [dict create type paragraph content {{type text text "x"}} meta {}]]
    set out [docir::html::render $ir]
    assert [string match "*<html lang=\"en\">*" $out]
}

test "html.viewport_meta_present_by_default" {
    set ir [list [dict create type paragraph content {{type text text "x"}} meta {}]]
    set out [docir::html::render $ir]
    assert [string match "*viewport*" $out]
    assert [string match "*width=device-width*" $out]
}

test "html.viewport_can_be_disabled" {
    set ir [list [dict create type paragraph content {{type text text "x"}} meta {}]]
    set out [docir::html::render $ir [dict create viewport 0]]
    assert [expr {![string match "*viewport*" $out]}]
}

test "html.theme_default" {
    set ir [list [dict create type paragraph content {{type text text "x"}} meta {}]]
    set out [docir::html::render $ir]
    # Default theme: sans-serif, 50em
    assert [string match "*-apple-system*" $out]
    assert [string match "*max-width: 50em*" $out]
}

test "html.theme_manpage" {
    set ir [list [dict create type paragraph content {{type text text "x"}} meta {}]]
    set out [docir::html::render $ir [dict create theme manpage]]
    # Manpage theme: Georgia, 900px
    assert [string match "*Georgia*" $out]
    assert [string match "*900px*" $out]
    assert [expr {![string match "*-apple-system*" $out]}] "no default sans"
}

test "html.theme_none" {
    set ir [list [dict create type paragraph content {{type text text "x"}} meta {}]]
    set out [docir::html::render $ir [dict create theme none]]
    # Keine Default-CSS, nur cssExtra falls da
    assert [expr {![string match "*-apple-system*" $out]}] "no default sans"
    assert [expr {![string match "*Georgia*" $out]}] "no manpage theme either"
    # Trotzdem <style> Block (ggf. leer)
    assert [string match "*<style>*" $out]
}

test "html.cssExtra_appended_to_theme" {
    set ir [list [dict create type paragraph content {{type text text "x"}} meta {}]]
    set out [docir::html::render $ir [dict create cssExtra ".my-class { color: red; }"]]
    assert [string match "*.my-class \\{ color: red; \\}*" $out]
    # Default theme is also still there
    assert [string match "*-apple-system*" $out]
}

# ============================================================
# M. mvmantohtml-Parität: header-Block + maninfo
# ============================================================

test "html.doc_header_uses_header_tag" {
    set ir [list [dict create type doc_header content {} meta {name puts section n version 9.0 part Tcl}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<header class=\"manpage-header\">*" $out]
    assert [string match "*</header>*" $out]
}

test "html.doc_header_has_h1_with_name_section" {
    set ir [list [dict create type doc_header content {} meta {name puts section n}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<h1>puts(n)</h1>*" $out]
}

test "html.doc_header_has_maninfo_span" {
    set ir [list [dict create type doc_header content {} meta {name puts section n version 9.0 part Tcl}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<span class=\"maninfo\">*" $out]
    assert [string match "*<span class=\"part\">Tcl</span>*" $out]
    assert [string match "*<span class=\"version\">9.0</span>*" $out]
}

# ============================================================
# N. mvmantohtml-Parität: TOC (Inhaltsverzeichnis)
# ============================================================

test "html.toc_off_by_default" {
    set ir [list \
        [dict create type heading content {{type text text NAME}} meta {level 1}] \
        [dict create type heading content {{type text text SYNOPSIS}} meta {level 1}]]
    set out [docir::html::render $ir]
    assert [expr {![string match "*<nav class=\"toc\">*" $out]}] "no TOC by default"
}

test "html.toc_includes_all_headings" {
    set ir [list \
        [dict create type heading content {{type text text NAME}} meta {level 1}] \
        [dict create type heading content {{type text text SYNOPSIS}} meta {level 1}] \
        [dict create type heading content {{type text text DESCRIPTION}} meta {level 1}]]
    set out [docir::html::render $ir [dict create includeToc 1]]
    assert [string match "*<nav class=\"toc\">*" $out]
    assert [string match "*<a href=\"#name\">NAME</a>*" $out]
    assert [string match "*<a href=\"#synopsis\">SYNOPSIS</a>*" $out]
    assert [string match "*<a href=\"#description\">DESCRIPTION</a>*" $out]
}

test "html.toc_uses_explicit_id_when_present" {
    set ir [list \
        [dict create type heading content {{type text text NAME}} meta {level 1 id custom-id}]]
    set out [docir::html::render $ir [dict create includeToc 1]]
    assert [string match "*<a href=\"#custom-id\">NAME</a>*" $out]
}

test "html.toc_levels_use_class" {
    set ir [list \
        [dict create type heading content {{type text text Top}} meta {level 1}] \
        [dict create type heading content {{type text text Sub}} meta {level 2}]]
    set out [docir::html::render $ir [dict create includeToc 1]]
    assert [string match "*toc-level-1*" $out]
    assert [string match "*toc-level-2*" $out]
}

test "html.headings_get_auto_id" {
    set ir [list [dict create type heading content {{type text text "Multi Word Title"}} meta {level 1}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    # Auto-ID aus Text: lowercase, Sonderzeichen → "-"
    assert [string match "*id=\"multi-word-title\"*" $out]
}

test "html.headings_keep_explicit_id" {
    set ir [list [dict create type heading content {{type text text "Foo"}} meta {level 1 id explicit}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*id=\"explicit\"*" $out]
    assert [expr {![string match "*id=\"foo\"*" $out]}]
}

# ============================================================
# O. mvmantohtml-Parität: linkMode (online/anchor/local)
# ============================================================

test "html.linkMode_local_default" {
    set ir [list [dict create type paragraph content {
        {type link text "puts" name puts section n}
    } meta {}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*<a href=\"puts.n.html\">puts</a>*" $out]
}

test "html.linkMode_anchor" {
    set ir [list [dict create type paragraph content {
        {type link text "puts" name puts section n}
    } meta {}]]
    set out [docir::html::render $ir [dict create standalone 0 linkMode anchor]]
    assert [string match "*<a href=\"#man-puts\">puts</a>*" $out]
}

test "html.linkMode_online_tcl" {
    set ir [list [dict create type paragraph content {
        {type link text "puts" name puts section n}
    } meta {}]]
    set out [docir::html::render $ir [dict create standalone 0 linkMode online part Tcl]]
    assert [string match "*https://www.tcl.tk/man/tcl9.0/TclCmd/puts.htm*" $out]
}

test "html.linkMode_online_tk" {
    set ir [list [dict create type paragraph content {
        {type link text "canvas" name canvas section n}
    } meta {}]]
    set out [docir::html::render $ir [dict create standalone 0 linkMode online part Tk]]
    assert [string match "*https://www.tcl.tk/man/tcl9.0/TkCmd/canvas.htm*" $out]
}

test "html.linkMode_part_auto_from_doc_header" {
    # Wenn doc_header.part="Tk" im IR ist und kein expliziter part
    # in options, soll der part aus dem doc_header verwendet werden.
    set ir [list \
        [dict create type doc_header content {} meta {name canvas section n part Tk}] \
        [dict create type paragraph content {
            {type link text "canvas" name canvas section n}
        } meta {}]]
    set out [docir::html::render $ir [dict create linkMode online]]
    assert [string match "*TkCmd*" $out] "auto-part aus doc_header"
}

test "html.linkResolve_overrides_linkMode" {
    proc myCustomResolve {name section} {
        return "custom-${name}.html"
    }
    set ir [list [dict create type paragraph content {
        {type link text "x" name x section n}
    } meta {}]]
    set out [docir::html::render $ir [dict create standalone 0 \
        linkMode online linkResolve myCustomResolve]]
    # linkResolve hat Vorrang vor linkMode
    assert [string match "*custom-x.html*" $out]
    assert [expr {![string match "*tcl.tk*" $out]}]
}

# ============================================================
# P. mvmantohtml-Parität: iplist + indent-N
# ============================================================

test "html.list_ip_uses_iplist_class" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "x"}} meta {kind ip}] \
    ] meta {kind ip}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*iplist*" $out]
    # IP-Listen sind ul (nicht dl) — Tk-Konvention aus mvmantohtml
    assert [string match "*<ul class=\"docir-list-ip iplist\">*" $out]
    assert [string match "*<li>x</li>*" $out]
}

test "html.list_indent_class" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "x"}} meta {kind ul}] \
    ] meta {kind ul indentLevel 2}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    assert [string match "*indent-2*" $out]
}

test "html.list_indent_level_clamped" {
    set ir [list [dict create type list content [list \
        [dict create type listItem content {{type text text "x"}} meta {kind ul}] \
    ] meta {kind ul indentLevel 99}]]
    set out [docir::html::render $ir [dict create standalone 0]]
    # > 4 → keine Klasse
    assert [expr {![string match "*indent-99*" $out]}]
    assert [expr {![string match "*indent-5*" $out]}]
}

# ============================================================
# Spec 0.5: Tests für neue Inline- und Block-Typen in docir-html
# ============================================================

test "html.inline.strike" {
    set ir [list [dict create type paragraph \
        content [list [dict create type strike text "deleted"]] meta {}]]
    set out [::docir::html::render $ir [dict create standalone 0]]
    assert [expr {[string first {<s>deleted</s>} $out] >= 0}]
}

test "html.inline.image" {
    set ir [list [dict create type paragraph \
        content [list [dict create type image text "alt" url "img.png"]] meta {}]]
    set out [::docir::html::render $ir [dict create standalone 0]]
    assert [expr {[string first {<img src="img.png" alt="alt"/>} $out] >= 0}]
}

test "html.inline.image_with_title" {
    set ir [list [dict create type paragraph \
        content [list [dict create type image text "alt" url "img.png" title "Tip"]] meta {}]]
    set out [::docir::html::render $ir [dict create standalone 0]]
    assert [expr {[string first {title="Tip"} $out] >= 0}]
}

test "html.inline.linebreak" {
    set ir [list [dict create type paragraph \
        content [list \
            [dict create type text text "Line one"] \
            [dict create type linebreak] \
            [dict create type text text "Line two"]] meta {}]]
    set out [::docir::html::render $ir [dict create standalone 0]]
    assert [expr {[string first {<br/>} $out] >= 0}]
}

test "html.inline.span_with_class" {
    set ir [list [dict create type paragraph \
        content [list [dict create type span text "marked" class "highlight"]] meta {}]]
    set out [::docir::html::render $ir [dict create standalone 0]]
    assert [expr {[string first {<span class="highlight">marked</span>} $out] >= 0}]
}

test "html.inline.footnote_ref" {
    set ir [list [dict create type paragraph \
        content [list [dict create type footnote_ref text "1" id "fn1"]] meta {}]]
    set out [::docir::html::render $ir [dict create standalone 0]]
    assert [expr {[string first {<sup class="footnote-ref">} $out] >= 0}]
    assert [expr {[string first {href="#fn-fn1"} $out] >= 0}]
    assert [expr {[string first {id="fnref-fn1"} $out] >= 0}]
}

test "html.block.image" {
    set ir [list [dict create type image content {} \
        meta [dict create url "test.png" alt "Description"]]]
    set out [::docir::html::render $ir [dict create standalone 0]]
    assert [expr {[string first {<figure class="docir-image">} $out] >= 0}]
    assert [expr {[string first {<img src="test.png" alt="Description"} $out] >= 0}]
    assert [expr {[string first {<figcaption>Description</figcaption>} $out] >= 0}]
}

test "html.block.footnote_section" {
    set ir [list [dict create type footnote_section \
        content [list \
            [dict create type footnote_def \
                content [list [dict create type text text "Note text."]] \
                meta [dict create id "fn1" num "1"]]] \
        meta {}]]
    set out [::docir::html::render $ir [dict create standalone 0]]
    assert [expr {[string first {<section class="footnotes">} $out] >= 0}]
    assert [expr {[string first {<li id="fn-fn1">} $out] >= 0}]
    assert [expr {[string first {Note text.} $out] >= 0}]
    # Back-link generated automatically
    assert [expr {[string first {href="#fnref-fn1"} $out] >= 0}]
}

test "html.block.div" {
    set ir [list [dict create type div \
        content [list [dict create type paragraph \
            content [list [dict create type text text "inside div"]] meta {}]] \
        meta [dict create class "warning" id "warn1"]]]
    set out [::docir::html::render $ir [dict create standalone 0]]
    assert [expr {[string first {<div class="warning" id="warn1">} $out] >= 0}]
    assert [expr {[string first {inside div} $out] >= 0}]
}

test "html.block.div_no_attrs" {
    set ir [list [dict create type div \
        content [list [dict create type paragraph \
            content [list [dict create type text text "no class"]] meta {}]] \
        meta {}]]
    set out [::docir::html::render $ir [dict create standalone 0]]
    # div ohne Attribute ist trotzdem ein div
    assert [expr {[string first {<div>} $out] >= 0}]
}

test::runAll
