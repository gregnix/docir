# docir::tilehtml -- DocIR -> 2-spaltiges Tile-HTML
#
# Adaption von docir::tilepdf fuer HTML-Output. Nutzt die gleiche
# DocIR-Stream-Logik (docir::tile-common), rendert aber als HTML mit
# CSS Grid statt PDF.
#
# Vorteile vs tilepdf:
#  - Browserbar, suchbar, kopierbar
#  - Print-CSS: Browser kann das in PDF rendern
#  - Theme-Switching dynamisch (light/dark/auto)
#  - Hyperlinks funktionieren
#  - CSS Grid + break-inside: avoid macht atomare Tiles
#
# API:
#   docir::tilehtml::render irStream outFile ?options?
#
# Optionen:
#   -title    Sheet-Titel-Override
#   -subtitle Subtitel-Override
#   -theme    light (default), dark, auto (folgt Browser-Setting)
#   -lang     html lang-Attribut (default 'de')

package provide docir::tilehtml 0.1
package require docir 0.1
package require docir::tilecommon 0.1

namespace eval docir::tilehtml {
    namespace export render
}

# ---------------------------------------------------------------------------
# HTML-Escaping
# ---------------------------------------------------------------------------

proc docir::tilehtml::_escape {text} {
    return [string map {
        & &amp;
        < &lt;
        > &gt;
        \" &quot;
    } $text]
}

# ---------------------------------------------------------------------------
# Inline-Renderer: Pseudo-Markdown -> HTML
# ---------------------------------------------------------------------------
#
# Die tile-common::inlinesToText liefert Pseudo-Markdown. Wir tokenisieren
# es zu Spans mit den passenden HTML-Tags.

proc docir::tilehtml::_richHtml {text} {
    # Erst Inline-Images herausziehen, dann Links — beide werden NICHT
    # durch tokenize geleitet weil ihre Markdown-Syntax (`![..](..)` und
    # `[..](..)`) nicht in der pseudo-Markdown-Tokenisierung steckt.
    set out ""
    set pos 0
    # Image kommt vor Link weil Image-Regex auch Link-Pattern matcht (mit !)
    set imgRe {!\[([^\]]*)\]\(([^)]+)\)}
    set linkRe {\[([^\]]+)\]\(([^)]+)\)}

    set len [string length $text]
    while {$pos < $len} {
        # Naechster Match: image oder link
        set imgMatch [regexp -indices -start $pos $imgRe $text imIdx imAlt imUrl]
        set linkMatch [regexp -indices -start $pos $linkRe $text lnIdx lnTxt lnUrl]

        # Welches kommt zuerst?
        if {$imgMatch && $linkMatch} {
            set imgStart [lindex $imIdx 0]
            set linkStart [lindex $lnIdx 0]
            # Image wird durch ! VOR der [ erkannt — wenn imgStart == linkStart-1,
            # ist es das Image (linkStart geht ueber den ! Char weg)
            if {$imgStart < $linkStart} {
                set which image
            } else {
                set which link
            }
        } elseif {$imgMatch} {
            set which image
        } elseif {$linkMatch} {
            set which link
        } else {
            # Kein Match mehr — Rest tokenisieren
            append out [_tokenizeAndRender [string range $text $pos end]]
            break
        }

        if {$which eq "image"} {
            lassign $imIdx mStart mEnd
            if {$mStart > $pos} {
                append out [_tokenizeAndRender [string range $text $pos [expr {$mStart-1}]]]
            }
            set alt [string range $text {*}$imAlt]
            set url [string range $text {*}$imUrl]
            append out "<img src=\"[_escape $url]\" alt=\"[_escape $alt]\" class=\"inline-img\">"
            set pos [expr {$mEnd + 1}]
        } else {
            lassign $lnIdx mStart mEnd
            if {$mStart > $pos} {
                append out [_tokenizeAndRender [string range $text $pos [expr {$mStart-1}]]]
            }
            set txt [string range $text {*}$lnTxt]
            set url [string range $text {*}$lnUrl]
            append out "<a href=\"[_escape $url]\">[_escape $txt]</a>"
            set pos [expr {$mEnd + 1}]
        }
    }
    return $out
}

proc docir::tilehtml::_tokenizeAndRender {text} {
    set tokens [::docir::tile::tokenize $text]
    set out ""
    foreach token $tokens {
        lassign $token tType tText
        set escaped [_escape $tText]
        switch $tType {
            bold   { append out "<strong>$escaped</strong>" }
            italic { append out "<em>$escaped</em>" }
            code   { append out "<code>$escaped</code>" }
            default { append out $escaped }
        }
    }
    return $out
}

# ---------------------------------------------------------------------------
# Section-Rendering
# ---------------------------------------------------------------------------

proc docir::tilehtml::_renderSection {section} {
    set title   [dict get $section title]
    set type    [dict get $section type]
    set content [dict get $section content]

    set out "  <section class=\"tile tile-$type\">\n"
    append out "    <h3 class=\"tile-title\">[_escape $title]</h3>\n"
    append out "    <div class=\"tile-body\">\n"

    switch $type {
        table {
            append out "      <table>\n"
            foreach row $content {
                set label [lindex $row 0]
                set value [lindex $row 1]
                append out "        <tr><th>[_richHtml $label]</th><td>[_richHtml $value]</td></tr>\n"
            }
            append out "      </table>\n"
        }
        code {
            append out "      <pre><code>"
            set first 1
            foreach line $content {
                if {!$first} { append out "\n" }
                append out [_escape $line]
                set first 0
            }
            append out "</code></pre>\n"
        }
        code-intro {
            set intro [dict get $section intro]
            foreach line $intro {
                append out "      <p class=\"tile-intro\">[_richHtml $line]</p>\n"
            }
            append out "      <pre><code>"
            set first 1
            foreach line $content {
                if {!$first} { append out "\n" }
                append out [_escape $line]
                set first 0
            }
            append out "</code></pre>\n"
        }
        list {
            append out "      <ul>\n"
            foreach item $content {
                append out "        <li>[_richHtml $item]</li>\n"
            }
            append out "      </ul>\n"
        }
        image {
            # content: Liste von {url alt title}
            foreach img $content {
                lassign $img url alt ttl
                set escUrl [_escape $url]
                set escAlt [_escape $alt]
                set tAttr ""
                if {$ttl ne ""} {
                    set tAttr " title=\"[_escape $ttl]\""
                }
                append out "      <figure><img src=\"$escUrl\" alt=\"$escAlt\"$tAttr></figure>\n"
            }
        }
        hint {
            foreach line $content {
                append out "      <p>[_richHtml $line]</p>\n"
            }
        }
    }

    append out "    </div>\n"
    append out "  </section>\n"
    return $out
}

# ---------------------------------------------------------------------------
# Sheet-Rendering
# ---------------------------------------------------------------------------

proc docir::tilehtml::_slugify {text} {
    # Title -> URL-safe slug. Unicode wird ASCII-foldet wo moeglich.
    set s [string tolower $text]
    # Umlaute via Unicode-Codepoint (encoding-sicher in source-Files)
    set s [string map [list \
        \u00e4 ae \u00f6 oe \u00fc ue \u00df ss \
        \u00c4 ae \u00d6 oe \u00dc ue] $s]
    # Alles was nicht alphanumerisch oder dash ist -> dash
    regsub -all {[^a-z0-9]+} $s - s
    # Trimm leading/trailing dashes
    set s [string trim $s "-"]
    if {$s eq ""} { set s "sheet" }
    return $s
}

proc docir::tilehtml::_renderSheet {sheet sheetIdx} {
    set title    [dict get $sheet title]
    set subtitle [dict get $sheet subtitle]
    set sections [dict get $sheet sections]

    set slug "sheet-$sheetIdx-[_slugify $title]"
    set out "<article class=\"sheet\" id=\"[_escape $slug]\">\n"
    append out "  <header class=\"sheet-header\">\n"
    append out "    <h1>[_escape $title]</h1>\n"
    if {$subtitle ne ""} {
        append out "    <p class=\"sheet-subtitle\">[_escape $subtitle]</p>\n"
    }
    append out "  </header>\n"
    append out "  <div class=\"tile-grid\">\n"
    foreach section $sections {
        append out [_renderSection $section]
    }
    append out "  </div>\n"
    append out "</article>\n"
    return $out
}

proc docir::tilehtml::_renderTOC {sheets} {
    if {[llength $sheets] < 2} { return "" }
    set out "<nav class=\"toc\">\n"
    append out "  <h2>Inhalt</h2>\n"
    append out "  <ul>\n"
    set i 0
    foreach sheet $sheets {
        incr i
        set title [dict get $sheet title]
        set slug "sheet-$i-[_slugify $title]"
        append out "    <li><a href=\"#[_escape $slug]\">[_escape $title]</a></li>\n"
    }
    append out "  </ul>\n"
    append out "</nav>\n"
    return $out
}

# ---------------------------------------------------------------------------
# CSS — pro Theme
# ---------------------------------------------------------------------------

proc docir::tilehtml::_css {theme cols} {
    # Theme als CSS-Variablen — bei "auto" via @media (prefers-color-scheme)
    set lightVars {
        --bg: #ffffff;
        --fg: #000000;
        --header: #1a3380;
        --sec-bg: #e0ecfa;
        --sec-fg: #1a3380;
        --hint-bg: #f5f5e0;
        --code-bg: #f7f7f7;
        --border: #cccccc;
        --subtitle: #666666;
    }
    set darkVars {
        --bg: #1e1e22;
        --fg: #ebebeb;
        --header: #8cbfff;
        --sec-bg: #334066;
        --sec-fg: #d9e8ff;
        --hint-bg: #33332d;
        --code-bg: #2a2a30;
        --border: #4d4d4d;
        --subtitle: #a6a6a6;
    }
    set solarizedVars {
        --bg: #fdf6e3;
        --fg: #586e75;
        --header: #268bd2;
        --sec-bg: #eee8d5;
        --sec-fg: #073642;
        --hint-bg: #f4ecd0;
        --code-bg: #eee8d5;
        --border: #93a1a1;
        --subtitle: #93a1a1;
    }
    set sepiaVars {
        --bg: #f4ecd8;
        --fg: #5b4636;
        --header: #704214;
        --sec-bg: #e8d9b8;
        --sec-fg: #704214;
        --hint-bg: #efe2c2;
        --code-bg: #ebdfc4;
        --border: #c4b394;
        --subtitle: #8a7a5a;
    }
    set themeVars ""
    switch $theme {
        light     { append themeVars ":root {\n$lightVars\n}\n" }
        dark      { append themeVars ":root {\n$darkVars\n}\n" }
        solarized { append themeVars ":root {\n$solarizedVars\n}\n" }
        sepia     { append themeVars ":root {\n$sepiaVars\n}\n" }
        auto {
            append themeVars ":root {\n$lightVars\n}\n"
            append themeVars "@media (prefers-color-scheme: dark) {\n"
            append themeVars "  :root {\n$darkVars\n  }\n"
            append themeVars "}\n"
        }
    }

    return "${themeVars}
* { box-sizing: border-box; }

body {
    margin: 0;
    background: var(--bg);
    color: var(--fg);
    font-family: -apple-system, 'Segoe UI', sans-serif;
    font-size: 9pt;
    line-height: 1.4;
}

.sheet {
    padding: 1em 1.2em;
    max-width: 100%;
}

.sheet-header h1 {
    color: var(--header);
    font-size: 18pt;
    margin: 0 0 0.2em 0;
    font-weight: 700;
}

.sheet-subtitle {
    color: var(--subtitle);
    font-size: 10pt;
    margin: 0 0 1em 0;
}

.tile-grid {
    /* Fallback fuer aeltere Browser ohne Grid-Support */
    column-count: ${cols};
    column-gap: 1em;
    /* Modernes Grid-Layout (ueberschreibt column-count) */
    display: grid;
    grid-template-columns: repeat(${cols}, 1fr);
    gap: 0.6em 1em;
    align-items: start;
}

.tile {
    border-bottom: 1px solid var(--border);
    padding-bottom: 0.4em;
    margin-bottom: 0.4em;
    break-inside: avoid;
    page-break-inside: avoid;
}

.tile-title {
    background: var(--sec-bg);
    color: var(--sec-fg);
    font-size: 11pt;
    font-weight: 700;
    margin: 0 0 0.4em 0;
    padding: 0.3em 0.5em;
    border-radius: 2px;
}

.tile-body {
    padding: 0 0.4em;
}

.tile-body p {
    margin: 0.2em 0;
}

.tile-body p.tile-intro {
    margin-bottom: 0.4em;
    color: var(--subtitle);
}

.tile-body pre {
    background: var(--code-bg);
    padding: 0.3em 0.5em;
    border-radius: 2px;
    margin: 0.2em 0;
    overflow-x: auto;
    font-size: 8.5pt;
    line-height: 1.3;
}

.tile-body code {
    font-family: 'Menlo', 'Consolas', 'Courier New', monospace;
}

.tile-body p code {
    background: var(--code-bg);
    padding: 0.05em 0.3em;
    border-radius: 2px;
    font-size: 8.5pt;
}

.tile-body ul {
    margin: 0.2em 0;
    padding-left: 1.2em;
}

.tile-body ul li {
    margin: 0.15em 0;
}

.tile-body table {
    width: 100%;
    border-collapse: collapse;
    font-size: 8.5pt;
}

.tile-body table th {
    text-align: left;
    color: var(--subtitle);
    font-weight: 700;
    padding: 0.15em 0.5em 0.15em 0;
    vertical-align: top;
    width: 30%;
}

.tile-body table td {
    padding: 0.15em 0;
    vertical-align: top;
}

.tile-body figure {
    margin: 0.3em 0;
    text-align: center;
}

.tile-body figure img {
    max-width: 100%;
    height: auto;
    border-radius: 2px;
}

.tile-body img.inline-img {
    max-height: 1.4em;
    vertical-align: middle;
    display: inline-block;
}

.tile-body a {
    color: var(--header);
    text-decoration: none;
    border-bottom: 1px dotted var(--header);
}

.tile-body a:hover {
    border-bottom-style: solid;
}

.toc {
    padding: 1em 1.2em;
    background: var(--sec-bg);
    border-bottom: 1px solid var(--border);
}

.toc h2 {
    margin: 0 0 0.5em 0;
    font-size: 12pt;
    color: var(--sec-fg);
    font-weight: 700;
}

.toc ul {
    list-style: none;
    padding: 0;
    margin: 0;
    columns: 3;
    column-gap: 1em;
}

.toc li {
    padding: 0.1em 0;
}

.toc a {
    color: var(--header);
    text-decoration: none;
    font-size: 9.5pt;
}

.toc a:hover {
    text-decoration: underline;
}

@media print {
    .toc { page-break-after: always; }
}

.tile-hint {
    background: var(--hint-bg);
}

.tile-hint .tile-body {
    background: var(--hint-bg);
    padding: 0.3em 0.5em;
    border-radius: 2px;
    margin-top: -0.4em;
}

/* Print: jeder Sheet eine Seite */
@media print {
    body { font-size: 8pt; }
    .sheet { page-break-after: always; }
    .sheet:last-child { page-break-after: avoid; }
}

/* Mobile: 1-spaltig */
@media (max-width: 600px) {
    .tile-grid {
        grid-template-columns: 1fr;
    }
}
"
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc docir::tilehtml::render {ir outFile args} {
    array set opts {-title "" -subtitle "" -theme light -lang de -columns 2}
    foreach {k v} $args {
        if {![info exists opts($k)]} {
            return -code error "docir::tilehtml::render: unknown option $k"
        }
        set opts($k) $v
    }

    if {$opts(-theme) ni {light dark auto solarized sepia}} {
        return -code error \
            "docir::tilehtml: unknown theme '$opts(-theme)' (use light, dark, auto, solarized, sepia)"
    }
    if {![string is integer -strict $opts(-columns)] || \
        $opts(-columns) < 1 || $opts(-columns) > 4} {
        return -code error \
            "docir::tilehtml: -columns muss zwischen 1 und 4 sein, war: $opts(-columns)"
    }

    set err [::docir::checkSchemaVersion $ir]
    if {$err ne ""} {
        return -code error "docir::tilehtml: $err"
    }

    set sheets [::docir::tile::streamToSheets $ir $opts(-title) $opts(-subtitle)]
    if {[llength $sheets] == 0} {
        return -code error "docir::tilehtml: keine Sheets im IR-Stream"
    }

    # Title fuer <title>-Tag
    set pageTitle [dict get [lindex $sheets 0] title]
    if {$pageTitle eq ""} { set pageTitle "Tile" }

    set html "<!DOCTYPE html>\n"
    append html "<html lang=\"$opts(-lang)\">\n"
    append html "<head>\n"
    append html "  <meta charset=\"utf-8\">\n"
    append html "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
    append html "  <title>[_escape $pageTitle]</title>\n"
    append html "  <style>\n[_css $opts(-theme) $opts(-columns)]\n  </style>\n"
    append html "</head>\n"
    append html "<body>\n"
    append html [_renderTOC $sheets]
    set sheetIdx 0
    foreach sheet $sheets {
        incr sheetIdx
        append html [_renderSheet $sheet $sheetIdx]
    }
    append html "</body>\n"
    append html "</html>\n"

    set fh [open $outFile w]
    fconfigure $fh -encoding utf-8
    puts -nonewline $fh $html
    close $fh
    return $outFile
}
