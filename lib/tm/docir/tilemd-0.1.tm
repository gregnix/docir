# docir::tilemd -- DocIR -> Tile-strukturiertes Markdown
#
# Markdown is a linear format — no 2-column layout possible.
# tilemd uses the same DocIR-to-sheets/tiles logic as tilepdf/tilehtml, but
# renders the tile sections as linear, CLEARLY STRUCTURED Markdown:
#
#   H1 Sheet-Titel
#   ===
#
#   ## Tile-Section-Titel
#
#   Body je nach type:
#     code        -> ```...```
#     code-intro  -> Intro-Para + ```...```
#     hint        -> > blockquote
#     list        -> - bullets
#     table       -> | label | value | tabelle
#     image       -> ![alt](url)
#
#   ---  (hr nach jeder section)
#
# Bei Multi-Sheet:
#   - TOC at the top (list with MD anchors `#sheet-title`)
#   - Sheets durch Page-Break-Marker `<!-- pagebreak -->` getrennt
#     (some renderers use this for print)
#
# API:
#   docir::tilemd::render irStream outFile ?options?
#
# Optionen:
#   -title    Sheet-Titel-Override
#   -subtitle Subtitel-Override
#   -toc      true/false (default: bei Multi-Sheet auto)
#   -hr       hr nach Sections (default true)

package provide docir::tilemd 0.1
package require docir 0.1
package require docir::tilecommon 0.1

namespace eval docir::tilemd {
    namespace export render renderSheets
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc docir::tilemd::_slugify {text} {
    # same rule as mdstack::parser::anchorize, so the TOC links hit the
    # anchors mdserver/mdstack give the headings (umlauts are dropped there)
    set s [string tolower $text]
    regsub -all {[^a-z0-9]+} $s - s
    set s [string trim $s "-"]
    if {$s eq ""} { set s "sheet" }
    return $s
}

# Inline text from CSD/tilecommon is pseudo-markdown (**bold**, *italic*,
# `code`, [text](url), ![alt](url)) as read by docir::tile::tokenize --
# the same reading tilehtml uses. Everything else is literal text and must
# be escaped, or mdstack reads it as markup: `$` starts math, `*` and `_`
# emphasis, `[` links, `<` HTML, `|` ends a table cell. Up to 2026-10-21
# all of it was passed through; a Bash sheet lost ${#var}, [[ ]] and the
# pipes in "a|b)". Table cells follow tilepdf: label and value are literal
# (no markup), a mono value becomes a code span.

# literal text -> Markdown text
proc docir::tilemd::_esc {text {inTable 0}} {
    set out [string map [list \\ \\\\ * \\* _ \\_ ` \\` \[ \\\[ \] \\\] \
        < \\< \$ \\\$ ~ \\~ \n { }] $text]
    if {$inTable} { set out [string map [list | \\|] $out] }
    return $out
}

# code span with a fence longer than any backtick run inside
proc docir::tilemd::_code {text {inTable 0}} {
    set text [string map [list \n { }] $text]
    set n 0
    foreach run [regexp -all -inline {`+} $text] {
        if {[string length $run] > $n} { set n [string length $run] }
    }
    set f [string repeat ` [expr {$n + 1}]]
    set pad ""
    if {[string index $text 0] eq "`" || [string index $text end] eq "`"} { set pad " " }
    if {$inTable} { set text [string map [list | \\|] $text] }
    return "$f$pad$text$pad$f"
}

# pseudo-markdown (tilehtml reading) -> Markdown
proc docir::tilemd::_rich {text {inTable 0}} {
    set out ""
    set re {(!?)\[([^\]]*)\]\(([^)]+)\)}
    set pos 0
    while {[regexp -indices -start $pos $re $text m bang lbl url]} {
        lassign $m a b
        append out [_tokens [string range $text $pos [expr {$a - 1}]] $inTable]
        set l [_esc [string range $text {*}$lbl] $inTable]
        set u [string map {( %28 ) %29 " " %20} [string range $text {*}$url]]
        if {[lindex $bang 1] >= [lindex $bang 0]} {
            append out "!\[$l\]($u)"
        } else {
            append out "\[$l\]($u)"
        }
        set pos [expr {$b + 1}]
    }
    append out [_tokens [string range $text $pos end] $inTable]
    return $out
}
proc docir::tilemd::_tokens {text inTable} {
    set out ""
    foreach t [::docir::tile::tokenize $text] {
        lassign $t type str
        switch $type {
            bold    { append out "**[_esc $str $inTable]**" }
            italic  { append out "*[_esc $str $inTable]*" }
            code    { append out [_code $str $inTable] }
            default { append out [_esc $str $inTable] }
        }
    }
    return $out
}

# fenced block: fence longer than any backtick run at a line start
proc docir::tilemd::_fence {lines} {
    set n 2
    foreach line $lines {
        if {[regexp {^\s*(`{3,})} $line -> run] && [string length $run] > $n} {
            set n [string length $run]
        }
    }
    return [string repeat ` [expr {$n + 1}]]
}

# ---------------------------------------------------------------------------
# Section-Rendering
# ---------------------------------------------------------------------------

proc docir::tilemd::_renderSection {section opts} {
    set title   [dict get $section title]
    set type    [dict get $section type]
    set content [dict get $section content]

    set out "## [_esc $title]\n\n"

    switch $type {
        table {
            # 2-spalten label/value als MD-Tabelle
            append out "| | |\n"
            append out "|---|---|\n"
            foreach row $content {
                set label [_esc [lindex $row 0] 1]
                set value [lindex $row 1]
                if {[lindex $row 2] eq "1"} {
                    set value [_code $value 1]
                } else {
                    set value [_esc $value 1]
                }
                append out "| $label | $value |\n"
            }
            append out "\n"
        }
        code {
            set f [_fence $content]
            append out "$f\n"
            foreach line $content {
                append out "$line\n"
            }
            append out "$f\n\n"
        }
        code-intro {
            set intro [dict get $section intro]
            foreach line $intro {
                append out "[_rich $line]\n"
            }
            set f [_fence $content]
            append out "\n$f\n"
            foreach line $content {
                append out "$line\n"
            }
            append out "$f\n\n"
        }
        list {
            foreach item $content {
                append out "- [_rich $item]\n"
            }
            append out "\n"
        }
        hint {
            # blockquote so that it stands out visually
            foreach line $content {
                append out "> [_rich $line]\n"
            }
            append out "\n"
        }
        image {
            foreach img $content {
                lassign $img url alt ttl
                if {$ttl ne ""} {
                    append out "!\[$alt\]($url \"$ttl\")\n\n"
                } else {
                    append out "!\[$alt\]($url)\n\n"
                }
            }
        }
    }

    if {[dict get $opts -hr]} {
        append out "---\n\n"
    }
    return $out
}

proc docir::tilemd::_renderSheet {sheet opts} {
    set title    [dict get $sheet title]
    set subtitle [dict get $sheet subtitle]
    set sections [dict get $sheet sections]

    set out "# [_esc $title]\n\n"
    if {$subtitle ne ""} {
        append out "*[_esc $subtitle]*\n\n"
    }
    foreach section $sections {
        append out [_renderSection $section $opts]
    }
    return $out
}

proc docir::tilemd::_renderTOC {sheets} {
    if {[llength $sheets] < 2} { return "" }
    set out "## Inhalt\n\n"
    foreach sheet $sheets {
        set title [dict get $sheet title]
        set slug [_slugify $title]
        append out "- \[[_esc $title]\](#$slug)\n"
    }
    append out "\n---\n\n"
    return $out
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc docir::tilemd::render {ir outFile args} {
    array set opts {-title "" -subtitle "" -toc auto -hr true}
    foreach {k v} $args {
        if {![info exists opts($k)]} {
            return -code error "docir::tilemd::render: unknown option $k"
        }
        set opts($k) $v
    }

    set err [::docir::checkSchemaVersion $ir]
    if {$err ne ""} {
        return -code error "docir::tilemd: $err"
    }

    set sheets [::docir::tile::streamToSheets $ir $opts(-title) $opts(-subtitle)]
    if {[llength $sheets] == 0} {
        return -code error "docir::tilemd: keine Sheets im IR-Stream"
    }

    return [renderSheets $sheets $outFile -toc $opts(-toc) -hr $opts(-hr)]
}

# renderSheets: alternative public API -- ready-made sheets list, writes MD.
proc docir::tilemd::renderSheets {sheets outFile args} {
    array set opts {-toc auto -hr true}
    foreach {k v} $args {
        if {![info exists opts($k)]} {
            return -code error "docir::tilemd::renderSheets: unknown option $k"
        }
        set opts($k) $v
    }

    if {[llength $sheets] == 0} {
        return -code error "docir::tilemd::renderSheets: leere Sheets-Liste"
    }

    # TOC decision: auto = when 2+ sheets
    set showToc 0
    if {$opts(-toc) eq "auto"} {
        set showToc [expr {[llength $sheets] >= 2}]
    } elseif {$opts(-toc) in {true 1 yes on}} {
        set showToc 1
    }

    # opts in dict form for _renderSection
    set rOpts [dict create -hr [expr {$opts(-hr) in {true 1 yes on}}]]

    set md ""
    if {$showToc} {
        append md [_renderTOC $sheets]
    }
    set first 1
    foreach sheet $sheets {
        if {!$first} {
            append md "\n<!-- pagebreak -->\n\n"
        }
        append md [_renderSheet $sheet $rOpts]
        set first 0
    }

    set fh [open $outFile w]
    fconfigure $fh -encoding utf-8
    puts -nonewline $fh $md
    close $fh
    return $outFile
}
