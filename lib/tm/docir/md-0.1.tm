# docir-md-0.1.tm -- DocIR -> Markdown renderer (sink)
#
# Converts a DocIR sequence into a Markdown file. The sixth sink
# im DocIR-Hub (neben tk, html, svg, pdf, canvas).
#
# Relation to docir::mdSource: this here is the SINK (DocIR -> MD,
# `docir::md::render`). Die QUELLE (MD-AST -> DocIR, `docir::md::fromAst`)
# lebt im separaten Paket `docir::mdSource`. Beide Module schreiben in
# the same namespace `::docir::md::*`, but with different
# procs -- they can be loaded SIMULTANEOUSLY without problems:
#
#   package require docir::md          ;# Sink (DocIR -> MD)
#   package require docir::mdSource    ;# Source (MD-AST -> DocIR)
#
# A round trip Markdown -> DocIR -> Markdown is therefore possible.
#
# Public API:
#   docir::md::render ir ?options?
#       options: dict with
#         linkResolve  Tcl cmd prefix       (optional, for link inlines with name/section)
#         listMarker   "-" | "+" | "*"     (default "-")
#         strongStyle  "**" | "__"          (default "**")
#         emphStyle    "*" | "_"             (default "*")
#       Returns: Markdown-String
#
#   docir::md::renderInline inlines
#       Converts an inline list into a Markdown fragment (without block wrap).
#
# Defensive Behandlung:
#   - blank-Nodes ohne content → mehrfache Leerzeile
#   - unbekannte Block-Typen → HTML-Kommentar als Marker, content
#     is rendered as inline text (no crash)
#   - Schema-Verletzungen in list.content / table.content → HTML-
#     Kommentar als Warnung
#   - Markdown escaping for text inlines (\*, \_, \`, \[, \])

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

    # Auto-shift: if there is a doc_header in the IR and headingShift="auto",
    # shift all headings by +1 — so "# title" becomes the only h1,
    # all .SH headings become h2 (consistent with ast2md output and
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

    # H1 is the name. Subtitle with additional fields.
    set out "# [_escapeMd $name]"
    if {$section ne ""} {
        # nroff-Style: name(section) — z.B. "ls(1)"
        append out "([_escapeMd $section])"
    }
    append out "\n\n"

    # subtitle line with version/part, if present.
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
        # > prefix for each line
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

    # In a code block: inline list as plain text (no Markdown escaping)
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
                # If descMd contains newlines: indent the further lines
                set descMd [_indentContinuationLines $descMd 4]
                append out "${indent}${ord}. $descMd\n"
                incr ord
            }
            tp - ip - op - ap - dl {
                # term bold on its own line, desc below with a 4-space indent
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

    # separator line with per-column alignment.
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

    # pseudo header if hasHeader=0
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

        # before the first row: pseudo header if hasHeader=0
        if {$rowIndex == 0 && !$hasHeader} {
            append out "$pseudo\n$sep\n"
        }

        set rowMd "|"
        foreach cell [dict get $row content] {
            if {[dict get $cell type] ne "tableCell"} { continue }
            set cellMd [_renderInlines [dict get $cell content]]
            # escape / map pipes and newlines in the cell content
            set cellMd [string map [list "|" "\\|" "\n" " "] $cellMd]
            append rowMd " $cellMd |"
        }
        append out "$rowMd\n"

        # separator after the first row if it is a real header
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
    # (they appear at the end of the doc; mdparser collects them into a section)
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
    # render the content of the definition as inlines
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
            # code inlines: no Markdown escaping; but backticks in the text
            # require double backticks on the outside
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
            # Hard break: two spaces + newline. In Markdown, for
            # easier reading a <br/> tag is also accepted,
            # but the "real" Markdown form is two trailing spaces.
            return "  \n"
        }
        softbreak {
            # Soft break: a plain newline keeps the lines separate in the
            # Markdown source while rendering as a space downstream.
            return "\n"
        }
        span {
            # TIP-700 span — Markdown hat keine Standard-Notation.
            # We use the Pandoc extension [text]{.class #id}
            set cls [_dictDef $inline class ""]
            set id  [expr {[dict exists $inline id]    ? [dict get $inline id]    : ""}]
            if {$cls eq "" && $id eq ""} {
                # Without attributes, span is a no-op — just return the text
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
            # Pandoc-style math: $...$ (inline) or $$...$$ (display)
            set disp [_dictDef $inline display 0]
            if {$disp} {
                return "\$\$${txt}\$\$"
            }
            return "\$${txt}\$"
        }
        default {
            # unknown inline type — preserve the text with an HTML comment marker
            return "<!--$t-->$escTxt"
        }
    }
}

proc docir::md::_renderLinkInline {inline} {
    variable opts
    set txt [_dictDef $inline text ""]
    set escTxt [_escapeMd $txt]

    set href ""
    # take only a NON-EMPTY href field — DocIR nodes have
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

# Markdown escaping for text inlines.
# We escape the most painful special characters. Not all, because that
# makes the output ugly — Markdown parsers are tolerant of
# non-escaped characters when the context is clear.
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

# Appends continuation lines (newlines in the text) at a constant
# indentation — useful for lists with multi-line content.
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
