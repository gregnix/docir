# docir-txt-0.1.tm -- DocIR -> plain text renderer (sink)
#
# Converts a DocIR sequence into a plain text string. The seventh
# sink in the DocIR hub (next to tk, html, md, svg, pdf, canvas).
#
# Use cases:
#   - CLI output of doc tools (for pagers like less/more)
#   - email body, log inserts, README plain-text copy
#   - inputs for non-Markdown-capable tools (grep, awk, etc.)
#
# Public API:
#   docir::txt::render ir ?options?
#       options: dict with
#         lineWidth   Integer (default 78)        word wrap width
#         bulletChar  "-" | "*" | "+"             (default "-")
#         orderedDot  "."                          (default ".")
#         codeIndent  Integer (default 4)         spaces for code blocks
#         quotePrefix String                       (default "> ")
#         hrChar      "-" | "=" | "*"              (default "-")
#         heading1Underline Char (default "=")    Setext style for H1
#         heading2Underline Char (default "-")    Setext style for H2
#         showImageUrls 0|1 (default 0)           [image: alt] vs [image: alt (url)]
#         linkStyle   "inline" | "footnote"        (default "inline" -> "text (url)")
#       Returns: plain text string with newlines
#
#   docir::txt::renderInline inlines ?options?
#       Converts an inline list into a text fragment (without block wrap).
#
# Verhalten bei Sonderfaellen:
#   - blank-Nodes ohne content -> Leerzeile
#   - Unbekannte Block-Types     -> als Paragraph fallback
#   - Tables                     -> ASCII table with | and -
#   - Code blocks                -> indented with codeIndent spaces
#   - Footnote section           -> at the end, numbered list

package provide docir::txt 0.1
package require Tcl 8.6-
package require docir 0.1

namespace eval ::docir::txt {
    namespace export render renderInline
    variable opts {}
}

# ============================================================
# Public API
# ============================================================

proc docir::txt::render {ir {options {}}} {
    variable opts
    set opts [dict merge \
        [dict create \
            lineWidth        78 \
            bulletChar       "-" \
            orderedDot       "." \
            codeIndent       4 \
            quotePrefix      "> " \
            hrChar           "-" \
            heading1Underline "=" \
            heading2Underline "-" \
            showImageUrls    0 \
            linkStyle        "inline"] \
        $options]

    set out ""
    foreach node $ir {
        append out [_renderBlock $node]
    }
    # Trailing whitespace normalisieren
    set out [string trimright $out "\n"]
    append out "\n"
    return $out
}

proc docir::txt::renderInline {inlines {options {}}} {
    variable opts
    if {$options ne ""} {
        set opts [dict merge $opts $options]
    } elseif {![info exists opts] || $opts eq ""} {
        set opts [dict create linkStyle "inline" showImageUrls 0]
    }
    return [_renderInlines $inlines]
}

# ============================================================
# Block dispatcher
# ============================================================

proc docir::txt::_renderBlock {node} {
    set t [dict get $node type]
    switch $t {
        doc_header       { return [_renderDocHeader $node] }
        heading          { return [_renderHeading $node] }
        paragraph        { return [_renderParagraph $node] }
        pre              { return [_renderPre $node] }
        list             { return [_renderList $node 0] }
        listItem         { return [_renderListItem $node 0] }
        blank            { return "\n" }
        hr               { return [_renderHr] }
        table            { return [_renderTable $node] }
        image            { return [_renderImageBlock $node] }
        footnote_section { return [_renderFootnoteSection $node] }
        footnote_def     { return [_renderFootnoteDef $node 0] }
        div              { return [_renderDiv $node] }
        tableRow -
        tableCell {
            return ""
        }
        default {
            if {[::docir::isSchemaOnly $t]} { return "" }
            # Fallback: treat as a paragraph if content is present
            if {[dict exists $node content]} {
                return [_renderParagraph $node]
            }
            return ""
        }
    }
}

# ============================================================
# Block renderers
# ============================================================

proc docir::txt::_renderDocHeader {node} {
    variable opts
    set meta [dict get $node meta]
    set parts {}
    set hasContent 0
    if {[dict exists $meta name] && [dict get $meta name] ne ""} {
        lappend parts [dict get $meta name]
        set hasContent 1
    }
    if {[dict exists $meta section] && [dict get $meta section] ne ""} {
        lappend parts "([dict get $meta section])"
        set hasContent 1
    }
    if {[dict exists $meta version] && [dict get $meta version] ne ""} {
        lappend parts "v[dict get $meta version]"
        set hasContent 1
    }
    if {!$hasContent} { return "" }
    set line [join $parts " "]
    set under [string repeat [dict get $opts heading1Underline] [string length $line]]
    return "$line\n$under\n\n"
}

proc docir::txt::_renderHeading {node} {
    variable opts
    set level [_metaGet $node level 1]
    set inlines [dict get $node content]
    set text [_renderInlines $inlines]
    set width [dict get $opts lineWidth]

    if {$level == 1} {
        # ALL CAPS + underline ===
        set text [string toupper $text]
        set under [string repeat [dict get $opts heading1Underline] \
            [string length $text]]
        return "$text\n$under\n\n"
    } elseif {$level == 2} {
        # Title-case + underline ---
        set under [string repeat [dict get $opts heading2Underline] \
            [string length $text]]
        return "$text\n$under\n\n"
    } else {
        # Level 3+: simply with dots at the end
        set prefix [string repeat "  " [expr {$level - 3}]]
        return "${prefix}${text}\n\n"
    }
}

proc docir::txt::_renderParagraph {node} {
    variable opts
    set inlines [dict get $node content]
    set text [_renderInlines $inlines]
    set width [dict get $opts lineWidth]
    set wrapped [_wordWrap $text $width]

    # Blockquote-Klasse?
    set meta [_dictGet $node meta {}]
    if {[dict exists $meta class] && [dict get $meta class] eq "blockquote"} {
        set prefix [dict get $opts quotePrefix]
        set lines {}
        foreach ln [split $wrapped "\n"] {
            lappend lines "${prefix}${ln}"
        }
        set wrapped [join $lines "\n"]
    }
    return "${wrapped}\n\n"
}

proc docir::txt::_renderPre {node} {
    variable opts
    set meta [_dictGet $node meta {}]
    set kind [_dictGet $meta kind ""]
    set indent [string repeat " " [dict get $opts codeIndent]]
    set text [_dictGet $node content ""]
    # If content is an inline list (instead of a string), flatten
    if {[string is list $text] && [llength $text] > 0 \
            && [catch {dict get [lindex $text 0] type}] == 0} {
        set text [_renderInlines $text]
    }
    if {$text eq ""} { return "\n" }
    # Math block: keep $$...$$ (no indent)
    if {$kind eq "math"} {
        return "\$\$\n${text}\n\$\$\n\n"
    }
    set lines {}
    foreach ln [split $text "\n"] {
        lappend lines "${indent}${ln}"
    }
    return "[join $lines \n]\n\n"
}

proc docir::txt::_renderList {node depth} {
    variable opts
    set items [_dictGet $node content {}]
    set meta [_dictGet $node meta {}]
    set kind [_dictGet $meta kind "ul"]

    set out ""
    set counter 1
    foreach item $items {
        append out [_renderListItem $item $depth $kind $counter]
        incr counter
    }
    if {$depth == 0} { append out "\n" }
    return $out
}

proc docir::txt::_renderListItem {node depth {kind ul} {counter 1}} {
    variable opts
    set indent [string repeat "  " $depth]
    set meta [_dictGet $node meta {}]

    # Marker
    switch $kind {
        ol      { set marker "${counter}[dict get $opts orderedDot]" }
        dl -
        tp -
        ip -
        op -
        ap      { set marker "" }
        default { set marker [dict get $opts bulletChar] }
    }

    set out ""

    # term (for dl/tp/ip/op/ap)
    if {[dict exists $meta term] && [dict get $meta term] ne ""} {
        set termText [_renderInlines [dict get $meta term]]
        if {$marker ne ""} {
            append out "${indent}${marker} ${termText}\n"
        } else {
            append out "${indent}${termText}\n"
        }
        # desc als eingerueckter Folgeblock
        set descIndent "${indent}  "
        set descText [_renderInlinesOrBlocks [dict get $node content]]
        foreach ln [split [string trimright $descText "\n"] "\n"] {
            append out "${descIndent}${ln}\n"
        }
    } else {
        # Einfacher Listeneintrag
        set descText [_renderInlinesOrBlocks [dict get $node content]]
        set first 1
        foreach ln [split [string trimright $descText "\n"] "\n"] {
            if {$first} {
                if {$marker ne ""} {
                    append out "${indent}${marker} ${ln}\n"
                } else {
                    append out "${indent}${ln}\n"
                }
                set first 0
            } else {
                set pad [string repeat " " [expr {[string length $marker] + 1}]]
                append out "${indent}${pad}${ln}\n"
            }
        }
    }
    return $out
}

proc docir::txt::_renderHr {} {
    variable opts
    set width [dict get $opts lineWidth]
    return "[string repeat [dict get $opts hrChar] $width]\n\n"
}

proc docir::txt::_renderTable {node} {
    variable opts
    set rows [_dictGet $node content {}]
    set meta [_dictGet $node meta {}]
    set hasHeader [_dictGet $meta hasHeader 0]

    # collect cell text and column widths
    set matrix {}
    set widths {}
    foreach row $rows {
        if {[dict get $row type] ne "tableRow"} continue
        set cells {}
        set colIdx 0
        foreach cell [dict get $row content] {
            if {[dict get $cell type] ne "tableCell"} continue
            set txt [_renderInlines [dict get $cell content]]
            # Newlines in Zellen vermeiden
            set txt [string map {"\n" " "} $txt]
            lappend cells $txt
            set w [string length $txt]
            if {$colIdx >= [llength $widths]} {
                lappend widths $w
            } else {
                set cur [lindex $widths $colIdx]
                if {$w > $cur} { lset widths $colIdx $w }
            }
            incr colIdx
        }
        lappend matrix $cells
    }

    if {[llength $matrix] == 0} { return "" }

    # Render
    set out ""
    set rowIdx 0
    foreach cells $matrix {
        set parts {}
        set ci 0
        foreach c $cells {
            lappend parts [format "%-*s" [lindex $widths $ci] $c]
            incr ci
        }
        append out "| [join $parts " | "] |\n"
        if {$rowIdx == 0 && $hasHeader} {
            set seps {}
            foreach w $widths {
                lappend seps [string repeat "-" $w]
            }
            append out "|-[join $seps -|-]-|\n"
        }
        incr rowIdx
    }
    append out "\n"
    return $out
}

proc docir::txt::_renderImageBlock {node} {
    variable opts
    set meta [_dictGet $node meta {}]
    set alt [_dictGet $meta alt ""]
    set url [_dictGet $meta url ""]
    if {[dict get $opts showImageUrls] && $url ne ""} {
        return "\[image: $alt ($url)\]\n\n"
    }
    return "\[image: $alt\]\n\n"
}

proc docir::txt::_renderFootnoteSection {node} {
    variable opts
    set defs [_dictGet $node content {}]
    if {[llength $defs] == 0} { return "" }
    set out "\n---\n\n"
    foreach d $defs {
        append out [_renderFootnoteDef $d 0]
    }
    return $out
}

proc docir::txt::_renderFootnoteDef {node depth} {
    set meta [_dictGet $node meta {}]
    set num [_dictGet $meta num "*"]
    set id [_dictGet $meta id "?"]
    set inlines [_dictGet $node content {}]
    set text [_renderInlines $inlines]
    return "\[${num}\] ${text}\n"
}

proc docir::txt::_renderDiv {node} {
    set inner [_dictGet $node content {}]
    set out ""
    foreach b $inner {
        append out [_renderBlock $b]
    }
    return $out
}

# ============================================================
# Inline rendering
# ============================================================

proc docir::txt::_renderInlines {inlines} {
    variable opts
    if {[string is list $inlines] && [llength $inlines] == 0} {
        return ""
    }
    set out ""
    foreach inline $inlines {
        append out [_renderInline $inline]
    }
    return $out
}

proc docir::txt::_renderInline {inline} {
    variable opts
    if {[catch {dict get $inline type} t]} {
        # Plain string (fallback)
        return $inline
    }
    switch $t {
        text       { return [_dictGet $inline text ""] }
        strong     { return "*[_dictGet $inline text [_renderInlines [_dictGet $inline content {}]]]*" }
        emphasis   { return "_[_dictGet $inline text [_renderInlines [_dictGet $inline content {}]]]_" }
        underline  { return "_[_dictGet $inline text [_renderInlines [_dictGet $inline content {}]]]_" }
        strike     { return "[_dictGet $inline text [_renderInlines [_dictGet $inline content {}]]]" }
        code       { return "[_dictGet $inline text [_dictGet $inline content ""]]" }
        linebreak  { return "\n" }
        softbreak  { return " " }
        link {
            set text [_dictGet $inline text [_renderInlines [_dictGet $inline content {}]]]
            set url  [_dictGet $inline url ""]
            if {$url eq "" && [dict exists $inline name]} {
                set url [dict get $inline name]
                if {[dict exists $inline section]} {
                    append url "([dict get $inline section])"
                }
            }
            if {[dict get $opts linkStyle] eq "footnote" || $url eq ""} {
                return $text
            }
            if {$text eq $url} { return $url }
            return "$text ($url)"
        }
        image {
            set alt [_dictGet $inline alt [_dictGet $inline text ""]]
            return "\[image: $alt\]"
        }
        span {
            return [_renderInlines [_dictGet $inline content {}]]
        }
        footnote_ref {
            set id [_dictGet $inline id "?"]
            return "\[^${id}\]"
        }
        math {
            return [_dictGet $inline text [_dictGet $inline content ""]]
        }
        default {
            # best effort: text, then content
            if {[dict exists $inline text]} { return [dict get $inline text] }
            if {[dict exists $inline content]} {
                set c [dict get $inline content]
                if {[string is list $c]} { return [_renderInlines $c] }
                return $c
            }
            return ""
        }
    }
}

# helper: renders content that is either an inline list or a block list
proc docir::txt::_renderInlinesOrBlocks {content} {
    if {[llength $content] == 0} { return "" }
    set first [lindex $content 0]
    if {[catch {dict get $first type} t]} {
        return [_renderInlines $content]
    }
    # If first.type is a block type, render as blocks
    if {$t in {paragraph heading list pre blockquote table hr image}} {
        set out ""
        foreach b $content {
            append out [_renderBlock $b]
        }
        return [string trimright $out "\n"]
    }
    return [_renderInlines $content]
}

# ============================================================
# Helpers
# ============================================================

proc docir::txt::_dictGet {d key {default ""}} {
    if {[dict exists $d $key]} { return [dict get $d $key] }
    return $default
}

proc docir::txt::_metaGet {node key {default ""}} {
    set m [_dictGet $node meta {}]
    return [_dictGet $m $key $default]
}

# word wrap to the given width
proc docir::txt::_wordWrap {text width} {
    if {$width <= 0} { return $text }
    set out ""
    foreach line [split $text "\n"] {
        if {[string length $line] <= $width} {
            append out "$line\n"
            continue
        }
        set words [split $line " "]
        set current ""
        foreach w $words {
            if {$current eq ""} {
                set current $w
                continue
            }
            if {[string length "$current $w"] > $width} {
                append out "$current\n"
                set current $w
            } else {
                append current " $w"
            }
        }
        if {$current ne ""} { append out "$current\n" }
    }
    return [string trimright $out "\n"]
}
