# docir::tilemd -- DocIR -> Tile-strukturiertes Markdown
#
# Markdown ist ein lineares Format — keine 2-Spalten-Layout moeglich.
# tilemd nutzt aber dieselbe DocIR-zu-Sheets/Tiles-Logik wie tilepdf/tilehtml,
# rendert die Tile-Sections als linearen, KLAR STRUKTURIERTEN Markdown:
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
#   - TOC am Anfang (Liste mit MD-Anchors `#sheet-titel`)
#   - Sheets durch Page-Break-Marker `<!-- pagebreak -->` getrennt
#     (manche Renderer nutzen das fuer Print)
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
    set s [string tolower $text]
    set s [string map [list \
        \u00e4 ae \u00f6 oe \u00fc ue \u00df ss \
        \u00c4 ae \u00d6 oe \u00dc ue] $s]
    regsub -all {[^a-z0-9]+} $s - s
    set s [string trim $s "-"]
    if {$s eq ""} { set s "sheet" }
    return $s
}

# Inline-Text (von tilecommon::inlinesToText) ist bereits Pseudo-Markdown
# (** ` etc). Fuer tilemd ist das genau was wir wollen — einfach durchreichen.
# Wir muessen nur sicherstellen dass die existing inline-image-Syntax
# `![alt](url)` und link-Syntax `[text](url)` korrekt beibehalten werden,
# weil das valide MD ist.

# ---------------------------------------------------------------------------
# Section-Rendering
# ---------------------------------------------------------------------------

proc docir::tilemd::_renderSection {section opts} {
    set title   [dict get $section title]
    set type    [dict get $section type]
    set content [dict get $section content]

    set out "## $title\n\n"

    switch $type {
        table {
            # 2-spalten label/value als MD-Tabelle
            append out "| | |\n"
            append out "|---|---|\n"
            foreach row $content {
                set label [lindex $row 0]
                set value [lindex $row 1]
                # Pipe in cells escapen
                set label [string map {| {\|} \n { }} $label]
                set value [string map {| {\|} \n { }} $value]
                append out "| $label | $value |\n"
            }
            append out "\n"
        }
        code {
            append out "```\n"
            foreach line $content {
                append out "$line\n"
            }
            append out "```\n\n"
        }
        code-intro {
            set intro [dict get $section intro]
            foreach line $intro {
                append out "$line\n"
            }
            append out "\n```\n"
            foreach line $content {
                append out "$line\n"
            }
            append out "```\n\n"
        }
        list {
            foreach item $content {
                append out "- $item\n"
            }
            append out "\n"
        }
        hint {
            # blockquote so dass es visuell hervorsticht
            foreach line $content {
                append out "> $line\n"
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

    set out "# $title\n\n"
    if {$subtitle ne ""} {
        append out "*$subtitle*\n\n"
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
        append out "- \[$title\](#$slug)\n"
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

# renderSheets: alternative Public API -- fertige Sheets-Liste, schreibt MD.
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

    # TOC-Entscheidung: auto = wenn 2+ Sheets
    set showToc 0
    if {$opts(-toc) eq "auto"} {
        set showToc [expr {[llength $sheets] >= 2}]
    } elseif {$opts(-toc) in {true 1 yes on}} {
        set showToc 1
    }

    # opts in dict-Form fuer _renderSection
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
