# docir-html-0.1.tm -- DocIR → HTML Renderer
#
# Wandelt eine flache DocIR-Sequenz (Liste von type/content/meta-Dicts)
# in ein vollstaendiges HTML5-Dokument um. Komplementaer zu
# docir-renderer-tk (Tk-Output) und docir-roff (nroff-Input).
#
# Public API:
#   docir::html::render ir ?options?
#       options: dict mit
#         title       String         (Standard: aus doc_header oder erstes heading)
#         standalone  Bool           (Standard 1; 0 = nur <body>-Inhalt ohne <html>-Wrapper)
#         indentSize  Int            (Standard 2; Einzug pro Verschachtelungsebene)
#         lang        String         (Standard "en"; <html lang="...">)
#         theme       String         (Standard "default"; "manpage" für nroff-Stil)
#         viewport    Bool           (Standard 1; <meta name="viewport"> einfügen)
#         includeToc  Bool           (Standard 0; Inhaltsverzeichnis aus headings)
#         linkMode    String         (Standard "local"; how to resolve link inlines)
#         linkResolve Tcl-Cmd-Praefix (optional, für link-Inlines mit name/section)
#         cssExtra    String         (zusätzliches CSS am Ende des <style>-Blocks)
#         cssFile     Path           (Pfad zu externer CSS-Datei; ihr Inhalt wird
#                                     anstelle des theme-CSS eingebettet)
#         part        String         (manpage-Stil: Section-Untertitel)
#       Returns: HTML-String
#
#   docir::html::renderInline inlines
#       Wandelt eine Inline-Liste in HTML-Fragment um (ohne Block-Wrapper).
#       Nuetzlich fuer Konsumenten die Block-Wrapping selbst machen.
#
# Defensive Behandlung (analog zu docir-renderer-tk):
#   - blank-Nodes mit fehlendem content sind OK
#   - unbekannte Block-Typen werden als <div class="docir-unknown">
#     mit data-docir-type-Attribut gerendert
#   - list.content das nicht-listItem-Knoten enthaelt wird mit einem
#     <!-- schema warning -->-Kommentar gerendert (kein Crash)
#   - unbekannte Inline-Typen werden als <span data-docir-type=...>
#     gerendert; ihr Text bleibt erhalten

package provide docir::html 0.1
package require docir 0.1

namespace eval ::docir::html {
    namespace export render renderInline
}

# ============================================================
# Public API
# ============================================================

proc docir::html::render {ir {options {}}} {
    variable opts
    set opts [dict create \
        title       "" \
        cssExtra    "" \
        standalone  1 \
        linkResolve "" \
        indentSize  2 \
        lang        "en" \
        theme       "default" \
        viewport    1 \
        includeToc  0 \
        linkMode    "local" \
        part        ""]
    foreach k [dict keys $options] {
        dict set opts $k [dict get $options $k]
    }

    # Title bestimmen
    set title [dict get $opts title]
    if {$title eq ""} {
        set title [_extractTitle $ir]
    }

    # Auto-Part aus doc_header übernehmen wenn nicht explizit gesetzt
    # (für linkMode=online: bestimmt TkCmd vs TclCmd)
    if {[dict get $opts part] eq ""} {
        foreach node $ir {
            if {[dict get $node type] eq "doc_header"} {
                set m [dict get $node meta]
                if {[dict exists $m part]} {
                    dict set opts part [dict get $m part]
                }
                break
            }
        }
    }

    # TOC aufbauen wenn gewünscht
    set toc ""
    if {[dict get $opts includeToc]} {
        set toc [_buildToc $ir]
    }

    # Body rendern
    set body ""
    foreach node $ir {
        append body [_renderBlock $node 0]
    }

    if {![dict get $opts standalone]} {
        # Body-only: TOC vor dem Body wenn vorhanden
        if {$toc ne ""} { return "${toc}${body}" }
        return $body
    }

    return [_wrapDocument $title $toc $body]
}

proc docir::html::renderInline {inlines} {
    return [_renderInlines $inlines]
}

# ============================================================
# Title extraction
# ============================================================

proc docir::html::_extractTitle {ir} {
    foreach node $ir {
        set t [dict get $node type]
        if {$t eq "doc_header"} {
            set m [dict get $node meta]
            set name    [expr {[dict exists $m name]    ? [dict get $m name]    : ""}]
            set section [expr {[dict exists $m section] ? [dict get $m section] : ""}]
            if {$name ne ""} {
                if {$section ne ""} { return "${name}(${section})" }
                return $name
            }
        }
        if {$t eq "heading"} {
            return [_inlinesToText [dict get $node content]]
        }
    }
    return "DocIR document"
}

proc docir::html::_inlinesToText {inlines} {
    set out ""
    foreach i $inlines {
        if {[dict exists $i text]} { append out [dict get $i text] }
    }
    return $out
}

# Sichere Anchor-ID aus Heading-Text generieren.
# Lowercase, Sonderzeichen → "-", Mehrfach-"-" zusammen, trim "-".
proc docir::html::_makeId {text} {
    set id [string tolower $text]
    set id [regsub -all {[^a-z0-9]+} $id "-"]
    set id [string trim $id "-"]
    if {$id eq ""} { set id "section" }
    return $id
}

# TOC aus den heading-Knoten im IR aufbauen.
# Liefert HTML-String mit <nav class="toc"> oder leer wenn keine Headings.
proc docir::html::_buildToc {ir} {
    set items {}
    foreach node $ir {
        if {[dict get $node type] ne "heading"} { continue }
        set m [dict get $node meta]
        set lv [expr {[dict exists $m level] ? [dict get $m level] : 1}]
        if {$lv < 1} { set lv 1 }
        if {$lv > 6} { set lv 6 }
        set txt [_inlinesToText [dict get $node content]]
        if {$txt eq ""} { continue }
        set id [expr {[dict exists $m id] ? [dict get $m id] : [_makeId $txt]}]
        lappend items [list $lv $txt $id]
    }
    if {[llength $items] == 0} { return "" }

    set out "<nav class=\"toc\">\n<ul>\n"
    foreach item $items {
        lassign $item lv txt id
        set escTxt [_escapeHtml $txt]
        set escId  [_escapeAttr $id]
        append out "  <li class=\"toc-level-$lv\"><a href=\"#$escId\">$escTxt</a></li>\n"
    }
    append out "</ul>\n</nav>\n"
    return $out
}

# ============================================================
# Document wrapper
# ============================================================

proc docir::html::_wrapDocument {title toc body} {
    variable opts
    set cssExtra [dict get $opts cssExtra]
    set lang     [dict get $opts lang]
    set viewport [dict get $opts viewport]
    set theme    [dict get $opts theme]
    set cssFile  [expr {[dict exists $opts cssFile] ? [dict get $opts cssFile] : ""}]
    set escTitle [_escapeHtml $title]

    # CSS-Quelle: cssFile hat Vorrang vor theme. cssFile wird inline
    # eingebettet (kein <link rel>, weil DocIR-HTML soll standalone sein).
    if {$cssFile ne "" && [file exists $cssFile]} {
        set fh [open $cssFile r]
        fconfigure $fh -encoding utf-8
        set themeCss [read $fh]
        close $fh
    } else {
        set themeCss [_themeCss $theme]
    }

    set viewportMeta ""
    if {$viewport} {
        set viewportMeta "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"/>\n"
    }

    set head "<!DOCTYPE html>
<html lang=\"[_escapeAttr $lang]\">
<head>
<meta charset=\"utf-8\"/>
${viewportMeta}<title>$escTitle</title>
<style>
$themeCss
$cssExtra
</style>
</head>
<body>
"
    set tail "
</body>
</html>
"
    return "$head$toc$body$tail"
}

proc docir::html::_themeCss {theme} {
    switch $theme {
        manpage { return [_manpageCss] }
        none    { return "" }
        default { return [_defaultCss] }
    }
}

proc docir::html::_defaultCss {} {
    return {body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
       max-width: 50em; margin: 2em auto; padding: 0 1em;
       line-height: 1.5; color: #222; }
h1 { font-size: 1.6em; border-bottom: 2px solid #888; padding-bottom: 0.2em; }
h2 { font-size: 1.3em; border-bottom: 1px solid #ccc; padding-bottom: 0.15em; }
h3 { font-size: 1.1em; }
h4, h5, h6 { font-size: 1.0em; }
.docir-doc-header { font-size: 0.85em; color: #666; margin-bottom: 1.5em;
                    border-bottom: 1px solid #ddd; padding-bottom: 0.5em; }
.docir-doc-header .name { font-weight: bold; }
header.manpage-header { margin-bottom: 1.5em; border-bottom: 1px solid #ddd; padding-bottom: 0.5em; }
header.manpage-header h1 { display: inline; border: none; padding: 0; }
.maninfo { display: inline; color: #666; font-size: 0.9em; margin-left: 1em; }
.version, .part { color: #666; font-size: 0.85em; }
nav.toc { background: #f9f9f9; border: 1px solid #ddd; border-radius: 4px;
          padding: 0.6em 1em; margin: 1em 0 1.5em; font-size: 0.9em; }
nav.toc ul { margin: 0; padding-left: 1.2em; }
nav.toc li { margin: 0.15em 0; }
nav.toc li.toc-level-2 { padding-left: 1em; }
nav.toc li.toc-level-3 { padding-left: 2em; }
pre { background: #f4f4f4; padding: 0.6em 0.9em; border-radius: 4px;
      overflow-x: auto; font-size: 0.92em; }
code { background: #f4f4f4; padding: 0.1em 0.3em; border-radius: 3px;
       font-size: 0.92em; }
pre code { background: none; padding: 0; }
blockquote { border-left: 3px solid #ccc; padding-left: 1em;
             color: #555; margin: 0 0 1em 0; }
.docir-list-tp dt { font-weight: bold; margin-top: 0.5em; }
.docir-list-tp dd { margin-left: 2em; margin-bottom: 0.5em; }
.docir-list-ip { padding-left: 2em; }
ul.iplist { list-style: disc; margin-left: 2em; padding-left: 0; }
ul.iplist li { margin: 0.3em 0; }
.indent-1 { margin-left: 2em; }
.indent-2 { margin-left: 4em; }
.indent-3 { margin-left: 6em; }
.indent-4 { margin-left: 8em; }
hr { border: none; border-top: 1px solid #ccc; margin: 1.5em 0; }
table { border-collapse: collapse; margin: 1em 0; }
table.docir-standard-options td { padding: 0.15em 1em 0.15em 0;
                                   font-family: monospace; }
table.docir-table td, table.docir-table th { padding: 0.3em 0.7em;
                                              border: 1px solid #ccc; }
table.docir-table th { background: #f4f4f4; text-align: left; }
.docir-unknown { background: #fff8dc; padding: 0.3em 0.6em;
                 border-left: 3px solid #d4b428; margin: 0.5em 0;
                 font-size: 0.85em; color: #666; }
.docir-blank { line-height: 1.0; }
a { color: #0055aa; }
a:hover { text-decoration: underline; }
}
}

proc docir::html::_manpageCss {} {
    # Theme angelehnt an mvmantohtml: Georgia-Schrift, max-width 900px,
    # Helvetica-Headings, Courier-Code, dezente Farben
    return {body { font-family: Georgia, 'Times New Roman', serif;
       max-width: 900px; margin: 2em auto; padding: 0 1em;
       line-height: 1.5; color: #222; }
h1, h2, h3, h4, h5, h6 { font-family: Helvetica, Arial, sans-serif; }
h1 { font-size: 1.8em; border-bottom: 2px solid #333; padding-bottom: 0.3em; }
h2 { font-size: 1.3em; border-bottom: 1px solid #ccc; margin-top: 1.8em; }
h3 { font-size: 1.1em; margin-top: 1.2em; }
header.manpage-header { margin-bottom: 1.5em; }
header.manpage-header h1 { display: inline; border: none; padding: 0; }
.maninfo { display: inline; color: #666; font-size: 0.9em; margin-left: 1em; }
.version, .part { color: #666; font-size: 0.85em; margin: 0.2em 0; }
.docir-doc-header { font-size: 0.85em; color: #666; margin-bottom: 1.5em; }
nav.toc { background: #f9f9f9; border: 1px solid #ddd; border-radius: 4px;
          padding: 0.6em 1em; margin: 1em 0 1.5em; font-size: 0.95em; }
nav.toc ul { margin: 0; padding-left: 1.2em; list-style: none; }
nav.toc li { margin: 0.15em 0; }
nav.toc li.toc-level-2 { padding-left: 1em; }
nav.toc li.toc-level-3 { padding-left: 2em; }
pre, code { font-family: 'Courier New', Courier, monospace; font-size: 0.92em; }
pre  { background: #f5f5f5; border: 1px solid #ddd; padding: 0.8em 1em;
       overflow-x: auto; border-radius: 3px; }
code { background: #f5f5f5; padding: 0.1em 0.3em; border-radius: 2px; }
pre code { background: none; padding: 0; }
blockquote { border-left: 3px solid #ccc; padding-left: 1em;
             color: #555; margin: 0 0 1em 0; }
dl   { margin: 0.5em 0 0.5em 1em; }
dt   { font-weight: bold; margin-top: 0.8em; }
dd   { margin-left: 2em; margin-top: 0.2em; }
ul.iplist { list-style: disc; margin-left: 2em; padding-left: 0; }
ul.iplist li { margin: 0.3em 0; }
.indent-1 { margin-left: 2em; }
.indent-2 { margin-left: 4em; }
.indent-3 { margin-left: 6em; }
.indent-4 { margin-left: 8em; }
.docir-list-tp dt { font-weight: bold; margin-top: 0.5em; }
.docir-list-tp dd { margin-left: 2em; margin-bottom: 0.5em; }
.docir-list-ip { padding-left: 2em; }
hr { border: none; border-top: 1px solid #ccc; margin: 1.5em 0; }
table { border-collapse: collapse; margin: 1em 0; }
table.docir-standard-options td { padding: 0.15em 1em 0.15em 0;
                                   font-family: monospace; }
table.docir-table td, table.docir-table th { padding: 0.3em 0.7em;
                                              border: 1px solid #ccc; }
table.docir-table th { background: #f4f4f4; text-align: left; }
.docir-unknown { background: #fff8dc; padding: 0.3em 0.6em;
                 border-left: 3px solid #d4b428; margin: 0.5em 0;
                 font-size: 0.85em; color: #666; }
a { color: #0055aa; }
a:hover { text-decoration: underline; }
}
}

# ============================================================
# Block rendering
# ============================================================

proc docir::html::_renderBlock {node level} {
    set t [dict get $node type]
    switch $t {
        doc_header   { return [_renderDocHeader $node $level] }
        heading      { return [_renderHeading $node $level] }
        paragraph    { return [_renderParagraph $node $level] }
        pre          { return [_renderPre $node $level] }
        list         { return [_renderList $node $level] }
        listItem     { return [_renderListItem $node $level] }
        blank        { return [_renderBlank $node $level] }
        hr           { return "[_indent $level]<hr/>\n" }
        table        { return [_renderTable $node $level] }
        image        { return [_renderImageBlock $node $level] }
        footnote_section { return [_renderFootnoteSection $node $level] }
        footnote_def {
            # footnote_def auf Top-Level ist eine Schema-Verletzung —
            # gehört in footnote_section. Wir rendern es trotzdem,
            # mit Warnung, damit der Output nicht crasht.
            return [_renderFootnoteDef $node $level]
        }
        div          { return [_renderDiv $node $level] }
        tableRow     -
        tableCell    {
            # These should only appear inside a table — if they are at
            # top-level, render them as standalone snippets for
            # debugging
            return [_renderUnknown $node $level "stray $t at top level"]
        }
        default      {
            if {[::docir::isSchemaOnly $t]} { return "" }
            return [_renderUnknown $node $level "unknown block type: $t"]
        }
    }
}

proc docir::html::_indent {level} {
    variable opts
    return [string repeat " " [expr {$level * [dict get $opts indentSize]}]]
}

proc docir::html::_renderDocHeader {node level} {
    set m [dict get $node meta]
    set name    [expr {[dict exists $m name]    ? [dict get $m name]    : ""}]
    set section [expr {[dict exists $m section] ? [dict get $m section] : ""}]
    set version [expr {[dict exists $m version] ? [dict get $m version] : ""}]
    set part    [expr {[dict exists $m part]    ? [dict get $m part]    : ""}]

    if {$name eq "" && $section eq "" && $part eq ""} { return "" }

    set ind [_indent $level]
    set out "$ind<header class=\"manpage-header\">\n"
    if {$name ne ""} {
        set h1Text [_escapeHtml $name]
        if {$section ne ""} {
            append h1Text "([_escapeHtml $section])"
        }
        append out "$ind  <h1>$h1Text</h1>\n"
    }
    set info {}
    if {$part ne ""}    { lappend info "<span class=\"part\">[_escapeHtml $part]</span>" }
    if {$version ne ""} { lappend info "<span class=\"version\">[_escapeHtml $version]</span>" }
    if {[llength $info] > 0} {
        append out "$ind  <span class=\"maninfo\">[join $info { · }]</span>\n"
    }
    append out "$ind</header>\n"
    return $out
}

proc docir::html::_renderHeading {node level} {
    set m [dict get $node meta]
    set lv [expr {[dict exists $m level] ? [dict get $m level] : 1}]
    if {$lv < 1} { set lv 1 }
    if {$lv > 6} { set lv 6 }
    set inner [_renderInlines [dict get $node content]]

    # ID: aus meta wenn da, sonst aus dem reinen Text generieren
    set id [expr {[dict exists $m id] ? [dict get $m id] : ""}]
    if {$id eq ""} {
        set txt [_inlinesToText [dict get $node content]]
        if {$txt ne ""} {
            set id [_makeId $txt]
        }
    }

    set ind [_indent $level]
    if {$id ne ""} {
        return "$ind<h$lv id=\"[_escapeAttr $id]\">$inner</h$lv>\n"
    }
    return "$ind<h$lv>$inner</h$lv>\n"
}

proc docir::html::_renderParagraph {node level} {
    set m [dict get $node meta]
    set class [expr {[dict exists $m class] ? [dict get $m class] : ""}]
    set inner [_renderInlines [dict get $node content]]
    set ind [_indent $level]

    if {$class eq "blockquote"} {
        return "$ind<blockquote><p>$inner</p></blockquote>\n"
    }
    if {$class eq "unknown"} {
        return "$ind<p class=\"docir-unknown\">$inner</p>\n"
    }
    if {$class ne ""} {
        return "$ind<p class=\"[_escapeAttr $class]\">$inner</p>\n"
    }
    return "$ind<p>$inner</p>\n"
}

proc docir::html::_renderPre {node level} {
    set m [dict get $node meta]
    set kind [expr {[dict exists $m kind] ? [dict get $m kind] : ""}]
    set lang [expr {[dict exists $m language] ? [dict get $m language] : ""}]
    set ind [_indent $level]

    # In <pre> rendert man Inline-Liste als reinen Text (kein <strong>
    # u.s.w. — das ist Konvention für code-Blöcke). Aber: wenn der
    # Inhalt aus echten formatierten Inlines besteht, behalten wir die
    # Tags. Fuer "kind=code" purer Text.
    if {$kind eq "code" || $kind eq "example"} {
        set txt [_inlinesToText [dict get $node content]]
        set escTxt [_escapeHtml $txt]
        if {$lang ne ""} {
            return "$ind<pre><code class=\"language-[_escapeAttr $lang]\">$escTxt</code></pre>\n"
        }
        return "$ind<pre><code>$escTxt</code></pre>\n"
    }

    # Generischer Pre-Block: erlaubt Inline-Formatierung
    set inner [_renderInlines [dict get $node content]]
    return "$ind<pre>$inner</pre>\n"
}

proc docir::html::_renderList {node level} {
    set m [dict get $node meta]
    set kind [expr {[dict exists $m kind] ? [dict get $m kind] : "ul"}]
    set indentLevel [expr {[dict exists $m indentLevel] ? [dict get $m indentLevel] : 0}]
    set ind [_indent $level]

    # Welcher HTML-Tag + Klasse?
    switch $kind {
        ol      { set tag ol; set itemTag li; set wrapClass docir-list-ol }
        ul      { set tag ul; set itemTag li; set wrapClass docir-list-ul }
        ip      {
            # IP-Liste: ul mit iplist-Klasse (mvmantohtml-Konvention)
            set tag ul; set itemTag li
            set wrapClass "docir-list-ip iplist"
        }
        dl      -
        tp      -
        op      -
        ap      { set tag dl; set itemTag dt; set wrapClass "docir-list-$kind" }
        default { set tag ul; set itemTag li; set wrapClass docir-list-unknown }
    }

    # indent-N Klasse anhängen wenn indentLevel > 0
    if {$indentLevel > 0 && $indentLevel <= 4} {
        append wrapClass " indent-$indentLevel"
    }

    set out "$ind<$tag class=\"$wrapClass\">\n"

    foreach item [dict get $node content] {
        set itemType [dict get $item type]
        if {$itemType ne "listItem"} {
            # Schema-Verletzung — kommentieren statt crashen
            append out "$ind  <!-- schema warning: list.content has type='$itemType' (expected listItem) -->\n"
            append out [_renderBlock $item [expr {$level + 1}]]
            continue
        }
        append out [_renderListItemInside $item $tag $itemTag [expr {$level + 1}]]
    }

    append out "$ind</$tag>\n"
    return $out
}

proc docir::html::_renderListItemInside {item parentTag itemTag level} {
    set m [dict get $item meta]
    set term  [expr {[dict exists $m term] ? [dict get $m term] : {}}]
    set descInlines [dict get $item content]
    set ind [_indent $level]

    if {$parentTag eq "dl"} {
        # term + desc
        set termHtml [_renderInlines $term]
        set descHtml [_renderInlines $descInlines]
        return "$ind<dt>$termHtml</dt>\n$ind<dd>$descHtml</dd>\n"
    }

    set inner [_renderInlines $descInlines]
    return "$ind<$itemTag>$inner</$itemTag>\n"
}

proc docir::html::_renderListItem {item level} {
    # Wenn ein listItem als Top-Level-Block auftaucht: defensiv
    # rendern, das ist eigentlich ein Schema-Fehler.
    set ind [_indent $level]
    set inner [_renderInlines [dict get $item content]]
    return "$ind<!-- schema warning: standalone listItem -->\n$ind<div class=\"docir-list-orphan\">$inner</div>\n"
}

proc docir::html::_renderBlank {node level} {
    set m [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
    set lines [expr {[dict exists $m lines] ? [dict get $m lines] : 1}]
    if {$lines < 1} { set lines 1 }
    set ind [_indent $level]
    set out ""
    for {set i 0} {$i < $lines} {incr i} {
        # Self-closing form (<br/>) damit XML-strict-Kontexte (z.B. SVG
        # foreignObject mit XHTML-Namespace) das Markup parsen koennen.
        # Im normalen HTML5-Kontext ist die Self-closing-Form ebenfalls
        # gueltig und semantisch gleich.
        append out "$ind<br/>\n"
    }
    return $out
}

proc docir::html::_renderTable {node level} {
    set m [dict get $node meta]
    set columns   [expr {[dict exists $m columns]   ? [dict get $m columns]   : 0}]
    set hasHeader [expr {[dict exists $m hasHeader] ? [dict get $m hasHeader] : 0}]
    set source    [expr {[dict exists $m source]    ? [dict get $m source]    : ""}]
    set alignments [expr {[dict exists $m alignments] ? [dict get $m alignments] : {}}]
    set ind [_indent $level]

    set tableClass docir-table
    if {$source ne ""} {
        # source als zusaetzliche Klasse aufnehmen (z.B. standardOptions)
        append tableClass " docir-[_escapeAttr $source]"
    }

    set out "$ind<table class=\"$tableClass\">\n"

    # Per-Spalten-Alignment via colgroup. Spec: alignments-Liste mit
    # Werten left/center/right/none pro Spalte. Alles andere wird
    # ignoriert (none = no styling).
    if {[llength $alignments] > 0} {
        append out "$ind  <colgroup>\n"
        foreach a $alignments {
            switch -- $a {
                left   { append out "$ind    <col style=\"text-align:left\"/>\n" }
                center { append out "$ind    <col style=\"text-align:center\"/>\n" }
                right  { append out "$ind    <col style=\"text-align:right\"/>\n" }
                default { append out "$ind    <col/>\n" }
            }
        }
        append out "$ind  </colgroup>\n"
    }

    set rowIndex 0
    foreach row [dict get $node content] {
        set rowType [dict get $row type]
        if {$rowType ne "tableRow"} {
            append out "$ind  <!-- schema warning: table.content has '$rowType' -->\n"
            incr rowIndex
            continue
        }
        set isHeaderRow [expr {$hasHeader && $rowIndex == 0}]
        set cellTag [expr {$isHeaderRow ? "th" : "td"}]

        append out "$ind  <tr>\n"
        set colIndex 0
        foreach cell [dict get $row content] {
            set cellType [dict get $cell type]
            if {$cellType ne "tableCell"} {
                append out "$ind    <!-- schema warning: tableRow.content has '$cellType' -->\n"
                incr colIndex
                continue
            }
            set inner [_renderInlines [dict get $cell content]]
            # Per-Cell-Alignment via style — wirkt auch wenn colgroup-
            # Variante vom CSS-Reset ueberschrieben wird.
            set align ""
            if {$colIndex < [llength $alignments]} {
                set a [lindex $alignments $colIndex]
                if {$a in {left center right}} {
                    set align " style=\"text-align:$a\""
                }
            }
            append out "$ind    <$cellTag$align>$inner</$cellTag>\n"
            incr colIndex
        }
        append out "$ind  </tr>\n"
        incr rowIndex
    }
    append out "$ind</table>\n"
    return $out
}

proc docir::html::_renderImageBlock {node level} {
    set ind [_indent $level]
    set m [dict get $node meta]
    set url [expr {[dict exists $m url] ? [dict get $m url] : ""}]
    set alt [expr {[dict exists $m alt] ? [dict get $m alt] : ""}]
    set title [expr {[dict exists $m title] ? [dict get $m title] : ""}]
    set escUrl [_escapeAttr $url]
    set escAlt [_escapeAttr $alt]

    set out "${ind}<figure class=\"docir-image\">\n"
    append out "${ind}  <img src=\"$escUrl\" alt=\"$escAlt\""
    if {$title ne ""} {
        append out " title=\"[_escapeAttr $title]\""
    }
    append out "/>\n"
    # figcaption wenn alt-text non-trivial ist
    if {$alt ne ""} {
        append out "${ind}  <figcaption>[_escapeHtml $alt]</figcaption>\n"
    }
    append out "${ind}</figure>\n"
    return $out
}

proc docir::html::_renderFootnoteSection {node level} {
    set ind [_indent $level]
    set defs [dict get $node content]
    if {[llength $defs] == 0} { return "" }

    set out "${ind}<section class=\"footnotes\">\n"
    append out "${ind}  <hr/>\n"
    append out "${ind}  <ol>\n"
    foreach def $defs {
        if {[dict get $def type] ne "footnote_def"} continue
        append out [_renderFootnoteDef $def [expr {$level + 2}]]
    }
    append out "${ind}  </ol>\n"
    append out "${ind}</section>\n"
    return $out
}

proc docir::html::_renderFootnoteDef {node level} {
    set ind [_indent $level]
    set m [dict get $node meta]
    set id [expr {[dict exists $m id] ? [dict get $m id] : ""}]
    set escId [_escapeAttr $id]

    # Inhalt der Footnote als gerenderte Inlines
    set content [_renderInlines [dict get $node content]]

    # <li id="fn-ID">CONTENT <a href="#fnref-ID" class="back">↩</a></li>
    set out "${ind}<li id=\"fn-$escId\">"
    append out "$content"
    append out " <a href=\"#fnref-$escId\" class=\"footnote-back\">&#8617;</a>"
    append out "</li>\n"
    return $out
}

proc docir::html::_renderDiv {node level} {
    set ind [_indent $level]
    set m [dict get $node meta]
    set cls [expr {[dict exists $m class] ? [dict get $m class] : ""}]
    set id  [expr {[dict exists $m id]    ? [dict get $m id]    : ""}]

    set attrs ""
    if {$cls ne ""} { append attrs " class=\"[_escapeAttr $cls]\"" }
    if {$id  ne ""} { append attrs " id=\"[_escapeAttr $id]\"" }

    set out "${ind}<div$attrs>\n"
    foreach child [dict get $node content] {
        append out [_renderBlock $child [expr {$level + 1}]]
    }
    append out "${ind}</div>\n"
    return $out
}

proc docir::html::_renderUnknown {node level reason} {
    set t [dict get $node type]
    set ind [_indent $level]
    set inner ""
    if {[dict exists $node content] && [llength [dict get $node content]] > 0} {
        # Versuche content als Inlines zu rendern
        set c [dict get $node content]
        if {[catch {_renderInlines $c} txt]} {
            set inner [_escapeHtml $reason]
        } else {
            set inner $txt
        }
    } else {
        set inner [_escapeHtml $reason]
    }
    return "$ind<div class=\"docir-unknown\" data-docir-type=\"[_escapeAttr $t]\">$inner</div>\n"
}

# ============================================================
# Inline rendering
# ============================================================

proc docir::html::_renderInlines {inlines} {
    set out ""
    foreach i $inlines {
        append out [_renderInline $i]
    }
    return $out
}

proc docir::html::_renderInline {inline} {
    set t [dict get $inline type]
    set txt [expr {[dict exists $inline text] ? [dict get $inline text] : ""}]
    set escTxt [_escapeHtml $txt]

    switch $t {
        text       { return $escTxt }
        strong     { return "<strong>$escTxt</strong>" }
        emphasis   { return "<em>$escTxt</em>" }
        underline  { return "<u>$escTxt</u>" }
        strike     { return "<s>$escTxt</s>" }
        code       { return "<code>$escTxt</code>" }
        link       { return [_renderLinkInline $inline $escTxt] }
        image {
            # Inline-Image: <img src="url" alt="text" title="title"?>
            set url [expr {[dict exists $inline url] ? [dict get $inline url] : ""}]
            set escUrl [_escapeAttr $url]
            set out "<img src=\"$escUrl\" alt=\"[_escapeAttr $txt]\""
            if {[dict exists $inline title]} {
                append out " title=\"[_escapeAttr [dict get $inline title]]\""
            }
            append out "/>"
            return $out
        }
        linebreak  { return "<br/>" }
        span {
            # <span class="..." id="...">text</span> — class/id optional
            set attrs ""
            if {[dict exists $inline class] && [dict get $inline class] ne ""} {
                append attrs " class=\"[_escapeAttr [dict get $inline class]]\""
            }
            if {[dict exists $inline id] && [dict get $inline id] ne ""} {
                append attrs " id=\"[_escapeAttr [dict get $inline id]]\""
            }
            return "<span$attrs>$escTxt</span>"
        }
        footnote_ref {
            # <sup><a href="#fn-ID">TEXT</a></sup> mit ID = id-Feld
            set id [expr {[dict exists $inline id] ? [dict get $inline id] : ""}]
            set escId [_escapeAttr $id]
            return "<sup class=\"footnote-ref\"><a href=\"#fn-$escId\" id=\"fnref-$escId\">$escTxt</a></sup>"
        }
        default {
            # Unbekannter Inline-Typ — Text bewahren mit data-Attribut
            return "<span data-docir-inline=\"[_escapeAttr $t]\">$escTxt</span>"
        }
    }
}

proc docir::html::_renderLinkInline {inline escTxt} {
    variable opts
    set href ""
    # Nur ein NICHT-LEERES href-Feld nehmen — DocIR-Knoten haben
    # manchmal href="" plus name/section (vom roff-Mapper)
    if {[dict exists $inline href] && [dict get $inline href] ne ""} {
        set href [dict get $inline href]
    } elseif {[dict exists $inline name]} {
        # name + section : link auflösen
        set name    [dict get $inline name]
        set section [expr {[dict exists $inline section] ? [dict get $inline section] : ""}]
        set lr [dict get $opts linkResolve]
        if {$lr ne ""} {
            # Externer Resolver hat Vorrang
            if {[catch {{*}$lr $name $section} resolved]} {
                set href ""
            } else {
                set href $resolved
            }
        } else {
            # linkMode-basiertes Mapping
            set linkMode [dict get $opts linkMode]
            set part [dict get $opts part]
            switch $linkMode {
                online {
                    # TkCmd für Tk-Befehle (part enthält "Tk"),
                    # TclCmd für alles andere
                    set subdir [expr {[string match -nocase "*tk*" $part] ? "TkCmd" : "TclCmd"}]
                    set href "https://www.tcl.tk/man/tcl9.0/${subdir}/${name}.htm"
                }
                anchor {
                    set href "#man-${name}"
                }
                local -
                default {
                    if {$section ne ""} {
                        set href "${name}.${section}.html"
                    } else {
                        set href "${name}.html"
                    }
                }
            }
        }
    }
    if {$href eq ""} {
        return $escTxt
    }
    return "<a href=\"[_escapeAttr $href]\">$escTxt</a>"
}

# ============================================================
# HTML escaping
# ============================================================

proc docir::html::_escapeHtml {s} {
    return [string map {
        "&"  "&amp;"
        "<"  "&lt;"
        ">"  "&gt;"
        "\"" "&quot;"
        "'"  "&#39;"
    } $s]
}

proc docir::html::_escapeAttr {s} {
    return [string map {
        "&"  "&amp;"
        "<"  "&lt;"
        ">"  "&gt;"
        "\"" "&quot;"
        "'"  "&#39;"
    } $s]
}
