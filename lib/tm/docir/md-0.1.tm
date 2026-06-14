# docir-md-0.1.tm -- DocIR → Markdown Renderer (Senke)
#
# Wandelt eine DocIR-Sequenz in eine Markdown-Datei um. Sechste Senke
# im DocIR-Hub (neben tk, html, svg, pdf, canvas).
#
# Verhaeltnis zu docir::mdSource: dies hier ist die SENKE (DocIR -> MD,
# `docir::md::render`). Die QUELLE (MD-AST -> DocIR, `docir::md::fromAst`)
# lebt im separaten Paket `docir::mdSource`. Beide Module schreiben in
# den gleichen Namespace `::docir::md::*`, aber mit unterschiedlichen
# Procs -- sie koennen problemlos GLEICHZEITIG geladen werden:
#
#   package require docir::md          ;# Sink (DocIR -> MD)
#   package require docir::mdSource    ;# Source (MD-AST -> DocIR)
#
# Ein Roundtrip Markdown -> DocIR -> Markdown ist damit moeglich.
#
# Public API:
#   docir::md::render ir ?options?
#       options: dict mit
#         linkResolve  Tcl-Cmd-Praefix     (optional, fuer link-Inlines mit name/section)
#         listMarker   "-" | "+" | "*"     (default "-")
#         strongStyle  "**" | "__"          (default "**")
#         emphStyle    "*" | "_"             (default "*")
#       Returns: Markdown-String
#
#   docir::md::renderInline inlines
#       Wandelt Inline-Liste in Markdown-Fragment um (ohne Block-Wrap).
#
# Defensive Behandlung:
#   - blank-Nodes ohne content → mehrfache Leerzeile
#   - unbekannte Block-Typen → HTML-Kommentar als Marker, content
#     wird als Inline-Text gerendert (kein Crash)
#   - Schema-Verletzungen in list.content / table.content → HTML-
#     Kommentar als Warnung
#   - Markdown-Escaping fuer text-Inlines (\*, \_, \`, \[, \])

package provide docir::md 0.1
package require docir 0.1

namespace eval ::docir::md {
    namespace export render renderInline
    variable opts
}

# ============================================================
# Public API
# ============================================================

proc docir::md::_dictDef {d k {def ""}} {
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}

proc docir::md::render {ir {options {}}} {
    variable opts
    set opts [dict create \
        linkResolve "" \
        listMarker  "-" \
        strongStyle "**" \
        emphStyle   "*" \
        headingShift "auto"]
    foreach k [dict keys $options] {
        dict set opts $k [dict get $options $k]
    }

    # Auto-Shift: wenn ein doc_header im IR ist und headingShift="auto",
    # shifte alle headings um +1 — so wird "# title" das einzige h1,
    # alle .SH-Headings werden h2 (konsistent mit ast2md-Output und
    # allgemein besseres Markdown).
    if {[dict get $opts headingShift] eq "auto"} {
        set shift 0
        foreach node $ir {
            if {[dict get $node type] eq "doc_header"} {
                set shift 1
                break
            }
        }
        dict set opts headingShift $shift
    }

    set out ""
    foreach node $ir {
        append out [_renderBlock $node]
    }
    return "[string trimright $out]\n"
}

proc docir::md::renderInline {inlines} {
    variable opts
    if {![info exists opts] || $opts eq ""} {
        set opts [dict create linkResolve "" listMarker "-" \
                   strongStyle "**" emphStyle "*"]
    }
    return [_renderInlines $inlines]
}

# ============================================================
# Block dispatcher
# ============================================================

proc docir::md::_renderBlock {node} {
    set t [dict get $node type]
    switch $t {
        doc_header   { return [_renderDocHeader $node] }
        heading      { return [_renderHeading $node] }
        paragraph    { return [_renderParagraph $node] }
        pre          { return [_renderPre $node] }
        list         { return [_renderList $node] }
        listItem     { return [_renderListItem $node] }
        blank        { return [_renderBlank $node] }
        hr           { return "---\n\n" }
        table        { return [_renderTable $node] }
        image        { return [_renderImageBlock $node] }
        footnote_section { return [_renderFootnoteSection $node] }
        footnote_def {
            # Top-level footnote_def — shouldn't happen but handle gracefully
            return [_renderFootnoteDef $node]
        }
        div          { return [_renderDiv $node] }
        tableRow     -
        tableCell    {
            return "<!-- stray $t at top level -->\n\n"
        }
        default      {
            if {[::docir::isSchemaOnly $t]} { return "" }
            return [_renderUnknown $node "unknown block: $t"]
        }
    }
}

# ============================================================
# Block renderers
# ============================================================

proc docir::md::_renderDocHeader {node} {
    set m [dict get $node meta]
    set name    [expr {[dict exists $m name]    ? [dict get $m name]    : ""}]
    set section [_dictDef $m section ""]
    set version [_dictDef $m version ""]
    set part    [expr {[dict exists $m part]    ? [dict get $m part]    : ""}]
    if {$name eq ""} { return "" }

    # H1 ist der Name. Untertitel mit zusaetzlichen Feldern.
    set out "# [_escapeMd $name]"
    if {$section ne ""} {
        # nroff-Style: name(section) — z.B. "ls(1)"
        append out "([_escapeMd $section])"
    }
    append out "\n\n"

    # Subtitel-Zeile mit version/part, falls vorhanden.
    set subtitle {}
    if {$version ne ""} { lappend subtitle [_escapeMd $version] }
    if {$part    ne ""} { lappend subtitle [_escapeMd $part] }
    if {[llength $subtitle] > 0} {
        append out "*[join $subtitle { · }]*\n\n"
    }
    return $out
}

proc docir::md::_renderHeading {node} {
    variable opts
    set m [dict get $node meta]
    set lv [_dictDef $m level 1]
    set lv [expr {$lv + [dict get $opts headingShift]}]
    if {$lv < 1} { set lv 1 }
    if {$lv > 6} { set lv 6 }
    set hashes [string repeat "#" $lv]
    set txt [_renderInlines [dict get $node content]]
    return "$hashes $txt\n\n"
}

proc docir::md::_renderParagraph {node} {
    set m [dict get $node meta]
    set class [_dictDef $m class ""]
    set txt [_renderInlines [dict get $node content]]
    if {$txt eq ""} { return "" }

    if {$class eq "blockquote"} {
        # > prefix für jede Zeile
        set lines [split $txt "\n"]
        set out ""
        foreach line $lines {
            append out "> $line\n"
        }
        return "$out\n"
    }
    return "$txt\n\n"
}

proc docir::md::_renderPre {node} {
    set m [dict get $node meta]
    set kind [_dictDef $m kind ""]
    set lang [_dictDef $m language ""]

    # Im Code-Block: Inline-Liste als plain text (kein Markdown-Escaping)
    set content [dict get $node content]
    if {[string is list $content] && [llength $content] > 0 \
            && [catch {dict get [lindex $content 0] type}] == 0} {
        set txt [_inlinesToText $content]
    } else {
        # Reiner String (z.B. von math_block via mdSource)
        set txt $content
    }

    # Math-Display-Block als $$...$$ ausgeben
    if {$kind eq "math"} {
        return "\$\$\n$txt\n\$\$\n\n"
    }

    return "```$lang\n$txt\n```\n\n"
}

proc docir::md::_renderList {node} {
    variable opts
    set m [dict get $node meta]
    set kind [_dictDef $m kind "ul"]
    set indentLevel [_dictDef $m indentLevel 0]
    # Per Indent-Level: 2 Spaces vor jedem Item (Markdown-Konvention)
    set indent [string repeat "  " $indentLevel]

    set out ""
    set ord 1
    foreach item [dict get $node content] {
        set itemType [dict get $item type]
        if {$itemType ne "listItem"} {
            append out "<!-- schema warning: '$itemType' in list.content -->\n"
            continue
        }

        set itemMeta [dict get $item meta]
        set itemKind [_dictDef $itemMeta kind $kind]
        set itemTerm [_dictDef $itemMeta term {}]
        set itemDescInlines [dict get $item content]

        set descMd [_renderInlines $itemDescInlines]

        switch $itemKind {
            ol {
                # Wenn descMd Newlines enthält: weitere Zeilen einrücken
                set descMd [_indentContinuationLines $descMd 4]
                append out "${indent}${ord}. $descMd\n"
                incr ord
            }
            tp - ip - op - ap - dl {
                # Term fett auf eigener Zeile, desc darunter mit 4-Space-Einzug
                set termMd [_renderInlines $itemTerm]
                if {$termMd ne ""} {
                    append out "${indent}[dict get $opts strongStyle]${termMd}[dict get $opts strongStyle]\n\n"
                }
                if {$descMd ne ""} {
                    set lines [split $descMd "\n"]
                    foreach line $lines {
                        if {$line eq ""} {
                            append out "\n"
                        } else {
                            append out "${indent}    $line\n"
                        }
                    }
                    append out "\n"
                }
            }
            default {
                # ul + unknown
                set marker [dict get $opts listMarker]
                set descMd [_indentContinuationLines $descMd [expr {[string length $marker] + 1}]]
                append out "${indent}$marker $descMd\n"
            }
        }
    }
    return "$out\n"
}

proc docir::md::_renderListItem {node} {
    # Standalone listItem (Schema-Fehler) — als ul rendern
    variable opts
    set txt [_renderInlines [dict get $node content]]
    return "<!-- standalone listItem -->\n[dict get $opts listMarker] $txt\n\n"
}

proc docir::md::_renderBlank {node} {
    set m [_dictDef $node meta {}]
    set lines [_dictDef $m lines 1]
    if {$lines < 1} { set lines 1 }
    return [string repeat "\n" $lines]
}

proc docir::md::_renderTable {node} {
    set m [dict get $node meta]
    set columns   [expr {[dict exists $m columns]   ? [dict get $m columns]   : 0}]
    set hasHeader [_dictDef $m hasHeader 0]
    set alignments [_dictDef $m alignments {}]

    if {$columns < 1} {
        return "<!-- table without columns -->\n\n"
    }

    # Separator-Zeile mit Per-Spalten-Alignment.
    # Markdown-Syntax: ` --- ` (default), `:---` (left), `:---:` (center), `---:` (right).
    set sep "|"
    for {set i 0} {$i < $columns} {incr i} {
        set a ""
        if {$i < [llength $alignments]} {
            set a [lindex $alignments $i]
        }
        switch -- $a {
            left   { append sep " :--- |" }
            center { append sep " :---: |" }
            right  { append sep " ---: |" }
            default { append sep " --- |" }
        }
    }

    # Pseudo-Header wenn hasHeader=0
    set pseudo "|"
    for {set i 0} {$i < $columns} {incr i} {
        append pseudo "   |"
    }

    set out ""
    set rowIndex 0
    foreach row [dict get $node content] {
        if {[dict get $row type] ne "tableRow"} {
            append out "<!-- schema warning: '[dict get $row type]' in table.content -->\n"
            incr rowIndex
            continue
        }

        # Vor erster Zeile: Pseudo-Header wenn hasHeader=0
        if {$rowIndex == 0 && !$hasHeader} {
            append out "$pseudo\n$sep\n"
        }

        set rowMd "|"
        foreach cell [dict get $row content] {
            if {[dict get $cell type] ne "tableCell"} { continue }
            set cellMd [_renderInlines [dict get $cell content]]
            # Pipes und Newlines im Zelleninhalt escapen / mappen
            set cellMd [string map [list "|" "\\|" "\n" " "] $cellMd]
            append rowMd " $cellMd |"
        }
        append out "$rowMd\n"

        # Separator nach erster Zeile wenn echter Header
        if {$rowIndex == 0 && $hasHeader} {
            append out "$sep\n"
        }
        incr rowIndex
    }
    return "$out\n"
}

proc docir::md::_renderImageBlock {node} {
    set m [dict get $node meta]
    set url [_dictDef $m url ""]
    set alt [_dictDef $m alt ""]
    set title [_dictDef $m title ""]
    set out "!\[$alt\]($url"
    if {$title ne ""} {
        append out " \"$title\""
    }
    append out ")\n\n"
    return $out
}

proc docir::md::_renderFootnoteSection {node} {
    # Markdown rendert footnote-defs einfach als [^id]: text
    # (sie erscheinen am Doc-Ende; mdparser sammelt sie in eine Section)
    set out ""
    foreach def [dict get $node content] {
        if {[dict get $def type] ne "footnote_def"} continue
        append out [_renderFootnoteDef $def]
    }
    return $out
}

proc docir::md::_renderFootnoteDef {node} {
    set m [dict get $node meta]
    set id [_dictDef $m id ""]
    # Inhalt der Definition als Inlines rendern
    set body [_renderInlines [dict get $node content]]
    return "\[^$id\]: $body\n\n"
}

proc docir::md::_renderDiv {node} {
    # TIP-700 div — Pandoc-Notation: ::: {.class #id} ... :::
    set m [dict get $node meta]
    set cls [_dictDef $m class ""]
    set id  [expr {[dict exists $m id]    ? [dict get $m id]    : ""}]

    set attrs ""
    if {$cls ne ""} { append attrs ".$cls " }
    if {$id  ne ""} { append attrs "#$id " }
    set attrs [string trimright $attrs]

    if {$attrs eq ""} {
        # Ohne Attribute: rein durchreichen ohne Marker
        set body ""
        foreach child [dict get $node content] {
            append body [_renderBlock $child]
        }
        return $body
    }

    set out ":::: \{$attrs\}\n\n"
    foreach child [dict get $node content] {
        append out [_renderBlock $child]
    }
    append out "::::\n\n"
    return $out
}

proc docir::md::_renderUnknown {node reason} {
    set t [dict get $node type]
    set inner ""
    if {[dict exists $node content]} {
        set c [dict get $node content]
        if {[catch {_renderInlines $c} txt]} {
            set inner ""
        } else {
            set inner $txt
        }
    }
    if {$inner ne ""} {
        return "<!-- $reason -->\n$inner\n\n"
    }
    return "<!-- $reason -->\n\n"
}

# ============================================================
# Inline rendering
# ============================================================

proc docir::md::_renderInlines {inlines} {
    set out ""
    foreach i $inlines {
        append out [_renderInline $i]
    }
    return $out
}

proc docir::md::_renderInline {inline} {
    variable opts
    set t [dict get $inline type]
    set txt [_dictDef $inline text ""]
    set escTxt [_escapeMd $txt]

    switch $t {
        text       { return $escTxt }
        strong     {
            set s [dict get $opts strongStyle]
            return "${s}${escTxt}${s}"
        }
        emphasis   {
            set e [dict get $opts emphStyle]
            return "${e}${escTxt}${e}"
        }
        underline  { return "<u>$escTxt</u>" }
        strike     { return "~~${escTxt}~~" }
        code       {
            # Code-Inlines: kein Markdown-Escaping; aber Backticks im Text
            # erfordern doppelte Backticks außen
            if {[string first "`" $txt] >= 0} {
                return "`` $txt ``"
            }
            return "`$txt`"
        }
        link       { return [_renderLinkInline $inline] }
        image {
            # ![alt](url "title"?)
            set url [_dictDef $inline url ""]
            set out "!\[$escTxt\]($url"
            if {[dict exists $inline title] && [dict get $inline title] ne ""} {
                set title [dict get $inline title]
                append out " \"$title\""
            }
            append out ")"
            return $out
        }
        linebreak {
            # Hard break: zwei Spaces + Newline. In Markdown wird zur
            # Erleichterung des Lesens auch ein <br/>-Tag akzeptiert,
            # aber die "echte" Markdown-Form sind zwei trailing Spaces.
            return "  \n"
        }
        softbreak {
            # Soft break: a plain newline keeps the lines separate in the
            # Markdown source while rendering as a space downstream.
            return "\n"
        }
        span {
            # TIP-700 span — Markdown hat keine Standard-Notation.
            # Wir nutzen die Pandoc-Erweiterung [text]{.class #id}
            set cls [_dictDef $inline class ""]
            set id  [expr {[dict exists $inline id]    ? [dict get $inline id]    : ""}]
            if {$cls eq "" && $id eq ""} {
                # Ohne Attribute ist span ein No-Op — nur den Text zurückgeben
                return $escTxt
            }
            set attrs ""
            if {$cls ne ""} { append attrs ".$cls " }
            if {$id  ne ""} { append attrs "#$id " }
            return "\[$escTxt\]\{[string trimright $attrs]\}"
        }
        footnote_ref {
            # [^id] in Markdown
            set id [_dictDef $inline id ""]
            return "\[^$id\]"
        }
        math {
            # Pandoc-Style math: $...$ (inline) oder $$...$$ (display)
            set disp [_dictDef $inline display 0]
            if {$disp} {
                return "\$\$${txt}\$\$"
            }
            return "\$${txt}\$"
        }
        default {
            # Unbekannter Inline-Typ — Text bewahren mit HTML-Kommentar-Marker
            return "<!--$t-->$escTxt"
        }
    }
}

proc docir::md::_renderLinkInline {inline} {
    variable opts
    set txt [_dictDef $inline text ""]
    set escTxt [_escapeMd $txt]

    set href ""
    # Nur ein NICHT-LEERES href-Feld nehmen — DocIR-Knoten haben
    # manchmal href="" plus name/section (vom roff-Mapper)
    if {[dict exists $inline href] && [dict get $inline href] ne ""} {
        set href [dict get $inline href]
    } elseif {[dict exists $inline name]} {
        set name    [dict get $inline name]
        set section [_dictDef $inline section ""]
        set lr [dict get $opts linkResolve]
        if {$lr ne ""} {
            if {[catch {{*}$lr $name $section} resolved]} {
                set href ""
            } else {
                set href $resolved
            }
        } else {
            # Default: name(section).md
            if {$section ne ""} {
                set href "${name}.${section}.md"
            } else {
                set href "${name}.md"
            }
        }
    }
    if {$href eq ""} {
        return $escTxt
    }
    return "\[$escTxt\]($href)"
}

# ============================================================
# Helpers
# ============================================================

proc docir::md::_inlinesToText {inlines} {
    set out ""
    foreach i $inlines {
        if {[dict exists $i text]} { append out [dict get $i text] }
    }
    return $out
}

# Markdown-Escaping fuer text-Inlines.
# Wir escapen die schmerzhaftesten Sonderzeichen. Nicht alle weil das
# den Output haesslich macht — Markdown-Parser sind tolerant gegenueber
# nicht-escapten Zeichen wenn der Kontext klar ist.
proc docir::md::_escapeMd {s} {
    return [string map {
        "\\" "\\\\"
        "*"  "\\*"
        "_"  "\\_"
        "`"  "\\`"
        "\[" "\\\["
        "\]" "\\\]"
    } $s]
}

# Hängt Continuation-Lines (Newlines im Text) auf gleichbleibender
# Einrueckung — nuetzlich fuer Listen mit mehrzeiligem Inhalt.
proc docir::md::_indentContinuationLines {text indent} {
    set lines [split $text "\n"]
    if {[llength $lines] <= 1} { return $text }
    set spaces [string repeat " " $indent]
    set out [lindex $lines 0]
    foreach line [lrange $lines 1 end] {
        append out "\n${spaces}${line}"
    }
    return $out
}
