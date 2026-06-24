# docir-html-0.1.tm -- DocIR → HTML Renderer
#
# Converts a flat DocIR sequence (list of type/content/meta dicts)
# in ein vollstaendiges HTML5-Dokument um. Komplementaer zu
# docir-renderer-tk (Tk output) and docir-roff (nroff input).
#
# Public API:
#   docir::html::render ir ?options?
#       options: dict with
#         title       String         (default: from doc_header or the first heading)
#         standalone  Bool           (default 1; 0 = only <body> content without an <html> wrapper)
#         indentSize  Int            (Standard 2; Einzug pro Verschachtelungsebene)
#         lang        String         (Standard "en"; <html lang="...">)
#         theme       String         (default "default"; "manpage" for nroff style)
#         viewport    Bool           (default 1; insert <meta name="viewport">)
#         includeToc  Bool           (default 0; table of contents from headings)
#         linkMode    String         (Standard "local"; how to resolve link inlines)
#         linkResolve Tcl cmd prefix   (optional, for link inlines with name/section)
#         cssExtra    String         (additional CSS at the end of the <style> block)
#         cssFile     Path           (path to an external CSS file; its content is
#                                     anstelle des theme-CSS eingebettet)
#         part        String         (manpage-Stil: Section-Untertitel)
#       Returns: HTML-String
#
#   docir::html::renderInline inlines
#       Converts an inline list into an HTML fragment (without a block wrapper).
#       Useful for consumers that do their own block wrapping.
#
# Defensive Behandlung (analog zu docir-renderer-tk):
#   - blank nodes with missing content are OK
#   - unknown block types are rendered as <div class="docir-unknown">
#     with a data-docir-type attribute
#   - list.content that contains non-listItem nodes is rendered with a
#     <!-- schema warning --> comment (no crash)
#   - unknown inline types are rendered as <span data-docir-type=...>
#     gerendert; ihr Text bleibt erhalten

package provide docir::html 0.1
package require docir 0.1
package require docir::diag
package require docir::diagram

namespace eval ::docir::html {
    namespace export render renderInline

    # Subject-index collection, filled while rendering and consumed by
    # _buildIndex. Reset at the start of every render call.
    variable indexEntries {}
    variable indexCounter 0
    variable currentSectionTitle ""
    variable currentSectionId ""
}

# ============================================================
# Public API
# ============================================================

proc docir::html::_dictDef {d k {def ""}} {
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}

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
        includeIndex 0 \
        indexTitle  "Index" \
        linkMode    "local" \
        enableMermaid 0 \
        enableMath  0 \
        nativeDiagrams "" \
        part        ""]
    foreach k [dict keys $options] {
        dict set opts $k [dict get $options $k]
    }

    # Reset the subject-index collection for this render run.
    variable indexEntries
    variable indexCounter
    variable currentSectionTitle
    variable currentSectionId
    set indexEntries {}
    set indexCounter 0
    set currentSectionTitle ""
    set currentSectionId ""

    # Title bestimmen
    set title [dict get $opts title]
    if {$title eq ""} {
        set title [_extractTitle $ir]
    }

    # take auto-part from doc_header if not explicitly set
    # (for linkMode=online: determines TkCmd vs TclCmd)
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

    # build the TOC if requested
    set toc ""
    if {[dict get $opts includeToc]} {
        set toc [_buildToc $ir]
    }

    # Body rendern (fuellt waehrenddessen die Index-Sammlung)
    set body ""
    foreach node $ir {
        append body [_renderBlock $node 0]
    }

    # append the subject index if requested (uses the ones collected during
    # collected [term]{.index} occurrences).
    if {[dict get $opts includeIndex]} {
        append body [_buildIndex]
    }

    if {![dict get $opts standalone]} {
        # body-only: TOC before the body if present
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
            set section [_dictDef $m section ""]
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

# Generate a safe anchor ID from the heading text.
# Lowercase, Sonderzeichen → "-", Mehrfach-"-" zusammen, trim "-".
proc docir::html::_makeId {text} {
    set id [string tolower $text]
    set id [regsub -all {[^a-z0-9]+} $id "-"]
    set id [string trim $id "-"]
    if {$id eq ""} { set id "section" }
    return $id
}

# Build the TOC from the heading nodes in the IR.
# Returns an HTML string with <nav class="toc">, or empty if there are no headings.
proc docir::html::_buildToc {ir} {
    set items {}
    foreach node $ir {
        if {[dict get $node type] ne "heading"} { continue }
        set m [dict get $node meta]
        set lv [_dictDef $m level 1]
        if {$lv < 1} { set lv 1 }
        if {$lv > 6} { set lv 6 }
        set txt [_inlinesToText [dict get $node content]]
        if {$txt eq ""} { continue }
        set id [_dictDef $m id [_makeId $txt]]
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

# Builds the subject index from the entries collected during rendering
# [term]{.index} occurrences: terms alphabetically, per term links to
# all occurrences. Link text is the section title; multiple occurrences in the
# same section are merged into one link. Without a surrounding
# section, a running number is used as the link text.
proc docir::html::_buildIndex {} {
    variable opts
    variable indexEntries
    if {[llength $indexEntries] == 0} { return "" }

    set indexTitle [_dictDef $opts indexTitle "Index"]

    # term -> ordered list of {anchor label}, deduplicated per section.
    set byTerm [dict create]
    set seen   [dict create]
    foreach e $indexEntries {
        lassign $e term anchor secTitle secId
        set key "$term\u0000[expr {$secId ne "" ? $secId : $anchor}]"
        if {[dict exists $seen $key]} { continue }
        dict set seen $key 1
        dict lappend byTerm $term [list $anchor $secTitle]
    }

    set out "<nav class=\"index\">\n<h2>[_escapeHtml $indexTitle]</h2>\n<ul>\n"
    foreach term [lsort -dictionary [dict keys $byTerm]] {
        set links {}
        set n 0
        foreach occ [dict get $byTerm $term] {
            incr n
            lassign $occ anchor label
            if {$label eq ""} { set label $n }
            lappend links "<a href=\"#[_escapeAttr $anchor]\">[_escapeHtml $label]</a>"
        }
        append out "  <li><span class=\"index-term\">[_escapeHtml $term]</span>:\
                    [join $links {, }]</li>\n"
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
    set cssFile  [_dictDef $opts cssFile ""]
    set escTitle [_escapeHtml $title]

    # CSS source: cssFile takes precedence over theme. cssFile is embedded inline
    # (no <link rel>, because DocIR HTML should be standalone).
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

    # Optional: Mermaid + Math via CDN scripts. Strictly opt-in so
    # docir::html does not reach the network "on its own". The user must
    # enableMermaid=1 / enableMath=1 setzen.
    set extraScripts ""
    if {[dict get $opts enableMermaid]} {
        append extraScripts \
            "<script src=\"https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js\"></script>\n"
        append extraScripts \
            "<script>mermaid.initialize({startOnLoad:true});</script>\n"
    }
    if {[dict get $opts enableMath]} {
        append extraScripts \
            "<link rel=\"stylesheet\" href=\"https://cdn.jsdelivr.net/npm/katex/dist/katex.min.css\"/>\n"
        append extraScripts \
            "<script defer src=\"https://cdn.jsdelivr.net/npm/katex/dist/katex.min.js\"></script>\n"
        append extraScripts \
            "<script defer src=\"https://cdn.jsdelivr.net/npm/katex/dist/contrib/auto-render.min.js\"\n"
        append extraScripts \
            "    onload=\"renderMathInElement(document.body, {delimiters:\[\n"
        append extraScripts \
            "        {left:'\$\$',right:'\$\$',display:true},\n"
        append extraScripts \
            "        {left:'\$',right:'\$',display:false}\n"
        append extraScripts \
            "    \]});\"></script>\n"
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
${extraScripts}</head>
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
            # footnote_def at the top level is a schema violation —
            # it belongs in footnote_section. We render it anyway,
            # with a warning, so the output does not crash.
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
    set section [_dictDef $m section ""]
    set version [_dictDef $m version ""]
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
    set lv [_dictDef $m level 1]
    if {$lv < 1} { set lv 1 }
    if {$lv > 6} { set lv 6 }
    set inner [_renderInlines [dict get $node content]]

    # ID: from meta if present, otherwise generated from the plain text
    set id [_dictDef $m id ""]
    set txt [_inlinesToText [dict get $node content]]
    if {$id eq "" && $txt ne ""} {
        set id [_makeId $txt]
    }

    # remember the current section for the index link text.
    variable currentSectionTitle
    variable currentSectionId
    set currentSectionTitle $txt
    set currentSectionId $id

    set ind [_indent $level]
    if {$id ne ""} {
        return "$ind<h$lv id=\"[_escapeAttr $id]\">$inner</h$lv>\n"
    }
    return "$ind<h$lv>$inner</h$lv>\n"
}

proc docir::html::_renderParagraph {node level} {
    set m [dict get $node meta]
    set class [_dictDef $m class ""]
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
    variable opts
    set m [dict get $node meta]
    set kind [_dictDef $m kind ""]
    set lang [_dictDef $m language ""]
    set ind [_indent $level]

    # In <pre>, an inline list is rendered as plain text (no <strong>
    # etc. — that is the convention for code blocks). But: if the
    # content consists of real formatted inlines, we keep the
    # Tags. Fuer "kind=code" purer Text.
    if {$kind eq "math"} {
        # Display-Math: <div class="math display">$$...$$</div>
        # Browser laedt KaTeX/MathJax separat.
        set content [dict get $node content]
        if {[string is list $content] && [llength $content] > 0 \
                && [catch {dict get [lindex $content 0] type}] == 0} {
            set txt [_inlinesToText $content]
        } else {
            set txt $content
        }
        set escTxt [_escapeHtml $txt]
        return "$ind<div class=\"math display\">\$\$${escTxt}\$\$</div>\n"
    }
    if {$kind eq "code" || $kind eq "example"} {
        set txt [_inlinesToText [dict get $node content]]
        set escTxt [_escapeHtml $txt]
        # tuflow flow-diagram: render server-side to inline SVG (no JS needed).
        # A failure here is reported through docir::diag (warn/strict/silent),
        # then we fall through to plain code / mermaid rendering. preferNative
        # also covers a ```mermaid``` block whose inner type renders more
        # reliably via the facade (e.g. architecture-beta); on failure it falls
        # through to the <pre class="mermaid"> path below (mermaid.js fallback).
        if {[docir::diagram::preferNative $lang $txt [_dictDef $opts nativeDiagrams ""]]} {
            try {
                set _svg [docir::diagram::renderSvg $txt $lang]
                return "$ind<div class=\"docir-diagram\">$_svg</div>\n"
            } on error {_m _o} {
                docir::diag::report [dict get $_o -errorcode] "diagram/$lang: $_m"
            }
        }
        # Mermaid: <pre class="mermaid"> -- erlaubt einbettung von
        # mermaid.js for diagram rendering in the browser.
        if {[docir::diagram::isBrowserPreferred $lang]} {
            return "$ind<pre class=\"mermaid\">$escTxt</pre>\n"
        }
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
    set kind [_dictDef $m kind "ul"]
    set indentLevel [_dictDef $m indentLevel 0]
    set ind [_indent $level]

    # Welcher HTML-Tag + Klasse?
    switch $kind {
        ol      { set tag ol; set itemTag li; set wrapClass docir-list-ol }
        ul      { set tag ul; set itemTag li; set wrapClass docir-list-ul }
        ip      {
            # IP list: ul with the iplist class (mvmantohtml convention)
            set tag ul; set itemTag li
            set wrapClass "docir-list-ip iplist"
        }
        dl      -
        tp      -
        op      -
        ap      { set tag dl; set itemTag dt; set wrapClass "docir-list-$kind" }
        default { set tag ul; set itemTag li; set wrapClass docir-list-unknown }
    }

    # append the indent-N class if indentLevel > 0
    if {$indentLevel > 0 && $indentLevel <= 4} {
        append wrapClass " indent-$indentLevel"
    }

    set lmeta [dict get $node meta]
    set loose [expr {[dict exists $lmeta loose] ? [dict get $lmeta loose] : 0}]

    set out "$ind<$tag class=\"$wrapClass\">\n"

    foreach item [dict get $node content] {
        set itemType [dict get $item type]
        if {$itemType ne "listItem"} {
            # Schema-Verletzung — kommentieren statt crashen
            append out "$ind  <!-- schema warning: list.content has type='$itemType' (expected listItem) -->\n"
            append out [_renderBlock $item [expr {$level + 1}]]
            continue
        }
        append out [_renderListItemInside $item $tag $itemTag [expr {$level + 1}] $loose]
    }

    append out "$ind</$tag>\n"
    return $out
}

proc docir::html::_renderListItemInside {item parentTag itemTag level {loose 0}} {
    set m [dict get $item meta]
    set term  [_dictDef $m term {}]
    set descInlines [dict get $item content]
    set ind [_indent $level]

    if {$parentTag eq "dl"} {
        # term + desc
        set termHtml [_renderInlines $term]
        set descHtml [_renderInlines $descInlines]
        return "$ind<dt>$termHtml</dt>\n$ind<dd>$descHtml</dd>\n"
    }

    # Multi-paragraph (loose) item: render each paragraph as its own <p>.
    if {[dict exists $item blocks]} {
        set body ""
        foreach b [dict get $item blocks] {
            append body "$ind  <p>[_renderInlines [dict get $b content]]</p>\n"
        }
        return "$ind<$itemTag>\n$body$ind</$itemTag>\n"
    }
    # Loose list, single-paragraph item: wrap the content in <p>.
    if {$loose} {
        return "$ind<$itemTag>\n$ind  <p>[_renderInlines $descInlines]</p>\n$ind</$itemTag>\n"
    }
    # Tight item: inline content (unchanged).
    set inner [_renderInlines $descInlines]
    return "$ind<$itemTag>$inner</$itemTag>\n"
}

proc docir::html::_renderListItem {item level} {
    # If a listItem appears as a top-level block: render
    # defensively, this is really a schema error.
    set ind [_indent $level]
    set inner [_renderInlines [dict get $item content]]
    return "$ind<!-- schema warning: standalone listItem -->\n$ind<div class=\"docir-list-orphan\">$inner</div>\n"
}

proc docir::html::_renderBlank {node level} {
    set m [_dictDef $node meta {}]
    set lines [_dictDef $m lines 1]
    if {$lines < 1} { set lines 1 }
    set ind [_indent $level]
    set out ""
    for {set i 0} {$i < $lines} {incr i} {
        # self-closing form (<br/>) so XML-strict contexts (e.g. SVG
        # foreignObject with an XHTML namespace) can parse the markup.
        # Im normalen HTML5-Kontext ist die Self-closing-Form ebenfalls
        # valid and semantically equivalent.
        append out "$ind<br/>\n"
    }
    return $out
}

proc docir::html::_renderTable {node level} {
    set m [dict get $node meta]
    set columns   [expr {[dict exists $m columns]   ? [dict get $m columns]   : 0}]
    set hasHeader [_dictDef $m hasHeader 0]
    set source    [expr {[dict exists $m source]    ? [dict get $m source]    : ""}]
    set alignments [_dictDef $m alignments {}]
    set ind [_indent $level]

    set tableClass docir-table
    if {$source ne ""} {
        # source als zusaetzliche Klasse aufnehmen (z.B. standardOptions)
        append tableClass " docir-[_escapeAttr $source]"
    }

    set out "$ind<table class=\"$tableClass\">\n"

    # per-column alignment via colgroup. Spec: alignments list with
    # values left/center/right/none per column. Everything else is
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
            # per-cell alignment via style — works even when the colgroup
            # variant is overridden by the CSS reset.
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
    set url [_dictDef $m url ""]
    set alt [_dictDef $m alt ""]
    set title [_dictDef $m title ""]
    set escUrl [_escapeAttr $url]
    set escAlt [_escapeAttr $alt]

    set out "${ind}<figure class=\"docir-image\">\n"
    append out "${ind}  <img src=\"$escUrl\" alt=\"$escAlt\""
    if {$title ne ""} {
        append out " title=\"[_escapeAttr $title]\""
    }
    append out "/>\n"
    # figcaption if the alt text is non-trivial
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
    set id [_dictDef $m id ""]
    set escId [_escapeAttr $id]

    # content of the footnote as rendered inlines
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
    set cls [_dictDef $m class ""]
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
    # Tolerate a single inline dict passed where a list of inline dicts is
    # expected (a flattened table cell): {type text text "x"} is treated as
    # {{type text text "x"}}. A proper inline list's first element is itself a
    # dict, so its string value is never the bare word "type" -- this makes the
    # check unambiguous.
    if {[lindex $inlines 0] eq "type"} { set inlines [list $inlines] }
    set out ""
    foreach i $inlines {
        # Skip anything that is not a well-formed inline dict, so one malformed
        # cell degrades instead of crashing the whole export -- the Tk preview is
        # tolerant in the same way.
        if {[catch {dict get $i type}]} continue
        append out [_renderInline $i]
    }
    return $out
}

proc docir::html::_renderInline {inline} {
    set t [dict get $inline type]
    set txt [_dictDef $inline text ""]
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
            set url [_dictDef $inline url ""]
            set escUrl [_escapeAttr $url]
            set out "<img src=\"$escUrl\" alt=\"[_escapeAttr $txt]\""
            if {[dict exists $inline title]} {
                append out " title=\"[_escapeAttr [dict get $inline title]]\""
            }
            append out "/>"
            return $out
        }
        linebreak  { return "<br/>" }
        softbreak  { return "\n" }
        span {
            # <span class="..." id="...">text</span> — class/id optional.
            # A span with class "index" is also captured as a subject-index entry
            # and gets a jump anchor (if it has no id of its own).
            set cls [_dictDef $inline class ""]
            set spanId [_dictDef $inline id ""]
            if {[lsearch -exact [split $cls] index] >= 0} {
                variable indexEntries
                variable indexCounter
                variable currentSectionTitle
                variable currentSectionId
                incr indexCounter
                if {$spanId eq ""} { set spanId "idx-$indexCounter" }
                lappend indexEntries \
                    [list $txt $spanId $currentSectionTitle $currentSectionId]
            }
            set attrs ""
            if {$cls ne ""} {
                append attrs " class=\"[_escapeAttr $cls]\""
            }
            if {$spanId ne ""} {
                append attrs " id=\"[_escapeAttr $spanId]\""
            }
            return "<span$attrs>$escTxt</span>"
        }
        footnote_ref {
            # <sup><a href="#fn-ID">TEXT</a></sup> with ID = the id field
            set id [_dictDef $inline id ""]
            set escId [_escapeAttr $id]
            return "<sup class=\"footnote-ref\"><a href=\"#fn-$escId\" id=\"fnref-$escId\">$escTxt</a></sup>"
        }
        math {
            # Pandoc convention for KaTeX/MathJax integration:
            # <span class="math inline">$...$</span> bzw.
            # <span class="math display">$$...$$</span>
            # The browser loads KaTeX/MathJax separately and renders them.
            set disp [_dictDef $inline display 0]
            set raw [_dictDef $inline text ""]
            set escRaw [_escapeHtml $raw]
            if {$disp} {
                return "<span class=\"math display\">\$\$${escRaw}\$\$</span>"
            }
            return "<span class=\"math inline\">\$${escRaw}\$</span>"
        }
        default {
            # unknown inline type — preserve the text with a data attribute
            return "<span data-docir-inline=\"[_escapeAttr $t]\">$escTxt</span>"
        }
    }
}

# CommonMark-style URL encoding for link/image destinations: percent-encode
# unsafe bytes (UTF-8), preserve existing %XX sequences and a safe set of
# characters. Note: this is the HTML href encoding; & is HTML-escaped later by
# _escapeAttr (so "a&b" -> "a&amp;b", "a b" -> "a%20b").
proc docir::html::_encodeUrl {url} {
    set safe {-_.~!*'();:@&=+$,/?#[]}
    set bytes [encoding convertto utf-8 $url]
    set n [string length $bytes]
    set out ""
    for {set i 0} {$i < $n} {incr i} {
        set ch [string index $bytes $i]
        # Preserve an existing percent-encoded sequence %XX.
        if {$ch eq "%" && $i + 2 < $n
            && [string match {[0-9A-Fa-f]} [string index $bytes [expr {$i+1}]]]
            && [string match {[0-9A-Fa-f]} [string index $bytes [expr {$i+2}]]]} {
            append out $ch
            continue
        }
        scan $ch %c b
        if {($b >= 0x30 && $b <= 0x39) || ($b >= 0x41 && $b <= 0x5A)
            || ($b >= 0x61 && $b <= 0x7A) || [string first $ch $safe] >= 0} {
            append out $ch
        } else {
            append out [format %%%02X $b]
        }
    }
    return $out
}

proc docir::html::_renderLinkInline {inline escTxt} {
    variable opts
    set name    [_dictDef $inline name ""]
    set hasHref [dict exists $inline href]
    set href    ""
    if {$name ne ""} {
        # Manpage cross-reference: resolve name (+section) into an href.
        set section [_dictDef $inline section ""]
        set lr [dict get $opts linkResolve]
        if {$lr ne ""} {
            if {[catch {{*}$lr $name $section} resolved]} {
                set href ""
            } else {
                set href $resolved
            }
        } else {
            set linkMode [dict get $opts linkMode]
            set part [dict get $opts part]
            switch $linkMode {
                online {
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
        # An unresolvable manpage reference degrades to plain text.
        if {$href eq ""} { return $escTxt }
    } elseif {$hasHref} {
        # A regular link. An explicit (even empty) href is rendered as an
        # anchor -- CommonMark allows <a href="">.
        set href [_encodeUrl [dict get $inline href]]
    } else {
        # Neither a manpage ref nor an href field: emit plain text.
        return $escTxt
    }
    set titleAttr ""
    set title [_dictDef $inline title ""]
    if {$title ne ""} {
        set titleAttr " title=\"[_escapeAttr $title]\""
    }
    return "<a href=\"[_escapeAttr $href]\"$titleAttr>$escTxt</a>"
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
    } $s]
}

proc docir::html::_escapeAttr {s} {
    return [string map {
        "&"  "&amp;"
        "<"  "&lt;"
        ">"  "&gt;"
        "\"" "&quot;"
    } $s]
}
