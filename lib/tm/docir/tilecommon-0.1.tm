# docir::tile-common -- Gemeinsame DocIR -> Sheets/Tiles-Logik
#
# Extrahiert aus tilepdf-0.1.tm. Wird von tilepdf und tilehtml genutzt.
# Konvertiert einen DocIR-Stream in eine Liste von Sheets, jedes Sheet
# enthält Sections mit klassifizierten Typen.
#
# Public API:
#   docir::tile::streamToSheets ir ?titleOverride? ?subtitleOverride?
#       -> Liste von Sheets {title subtitle sections}
#
#   docir::tile::tokenize text
#       -> Liste von Tokens {type text} (plain/bold/italic/code)
#
#   docir::tile::inlinesToText inlines
#       -> String mit pseudo-markdown
#
# Mapping:
#   heading level=1   -> Sheet-Titel
#   heading level=2+  -> Tile-Section-Titel
#   pre               -> code-Tile
#   list              -> list-Tile
#   table             -> table-Tile (label/value)
#   paragraph         -> hint-Tile
#   paragraph + pre   -> code-intro Section (Intro+Code)
#   gemischt          -> hint mit Markern

package provide docir::tilecommon 0.1
package require docir 0.1

namespace eval docir::tile {
    namespace export streamToSheets packSection tokenize inlinesToText fontFor
}

# ---------------------------------------------------------------------------
# Inlines -> Pseudo-Markdown-Text
# ---------------------------------------------------------------------------

proc docir::tile::inlinesToText {inlines} {
    set out ""
    foreach inline $inlines {
        if {![dict exists $inline type]} continue
        set t [dict get $inline type]
        # Text-Wert extrahieren (mdparser nutzt 'value', andere nutzen 'text')
        set v ""
        if {[dict exists $inline value]} {
            set v [dict get $inline value]
        } elseif {[dict exists $inline text]} {
            set v [dict get $inline text]
        }
        switch $t {
            text     { append out $v }
            strong   { append out "**$v**" }
            emphasis { append out "*$v*" }
            underline { append out "_${v}_" }
            strike   { append out "~~${v}~~" }
            code     { append out "`$v`" }
            link {
                set linkText ""
                if {[dict exists $inline content]} {
                    set linkText [inlinesToText [dict get $inline content]]
                } else {
                    set linkText $v
                }
                set url ""
                if {[dict exists $inline meta]} {
                    set m [dict get $inline meta]
                    if {[dict exists $m url]} { set url [dict get $m url] }
                }
                if {$url ne ""} {
                    append out "\[$linkText\]($url)"
                } else {
                    append out $linkText
                }
            }
            linebreak { append out " " }
            image {
                set alt ""
                set url ""
                # alt: aus inline.text oder meta.alt
                if {[dict exists $inline text]} {
                    set alt [dict get $inline text]
                }
                # url: aus inline.url oder meta.url
                if {[dict exists $inline url]} {
                    set url [dict get $inline url]
                }
                if {[dict exists $inline meta]} {
                    set m [dict get $inline meta]
                    if {$alt eq "" && [dict exists $m alt]} { set alt [dict get $m alt] }
                    if {$url eq "" && [dict exists $m url]} { set url [dict get $m url] }
                }
                if {$alt eq ""} { set alt "image" }
                if {$url ne ""} {
                    append out "!\[$alt\]($url)"
                } else {
                    append out "!\[$alt\]"
                }
            }
            footnote_ref {
                set num "?"
                if {[dict exists $inline meta]} {
                    set m [dict get $inline meta]
                    if {[dict exists $m num]} { set num [dict get $m num] }
                }
                append out "\[^$num\]"
            }
            default { append out $v }
        }
    }
    return $out
}

# ---------------------------------------------------------------------------
# Mini-Tokenizer fuer Inline-Markup (**bold**, *italic*, `code`)
# ---------------------------------------------------------------------------

proc docir::tile::tokenize {text} {
    set tokens {}
    set state plain
    set buf ""
    set i 0
    set len [string length $text]
    while {$i < $len} {
        set c [string index $text $i]
        set c2 [string index $text [expr {$i+1}]]
        if {$c eq "*" && $c2 eq "*"} {
            if {$buf ne ""} { lappend tokens [list $state $buf]; set buf "" }
            if {$state eq "bold"} { set state plain } else { set state bold }
            incr i 2
            continue
        }
        if {$c eq "*" && $c2 ne "*"} {
            if {$buf ne ""} { lappend tokens [list $state $buf]; set buf "" }
            if {$state eq "italic"} { set state plain } else { set state italic }
            incr i
            continue
        }
        if {$c eq "`"} {
            if {$buf ne ""} { lappend tokens [list $state $buf]; set buf "" }
            if {$state eq "code"} { set state plain } else { set state code }
            incr i
            continue
        }
        append buf $c
        incr i
    }
    if {$buf ne ""} { lappend tokens [list $state $buf] }
    return $tokens
}

# ---------------------------------------------------------------------------
# Token-Type -> Font-Familie (fuer PDF: Helvetica-Bold etc.)
# ---------------------------------------------------------------------------

proc docir::tile::fontFor {type} {
    switch $type {
        bold    { return Helvetica-Bold }
        italic  { return Helvetica-Oblique }
        code    { return Courier }
        default { return Helvetica }
    }
}

# ---------------------------------------------------------------------------
# DocIR-Stream -> Sheets-Liste
# ---------------------------------------------------------------------------

proc docir::tile::streamToSheets {ir {titleOverride ""} {subtitleOverride ""}} {
    set sheets {}
    set curSheet [dict create title "" subtitle "" sections {}]
    set curSection ""
    set curSectionContent {}

    set h1Count 0

    foreach node $ir {
        set type [dict get $node type]
        if {[::docir::isSchemaOnly $type]} continue

        switch $type {
            doc_header {
                set m [dict get $node meta]
                if {[dict exists $m name] && [dict get $m name] ne ""} {
                    dict set curSheet title [dict get $m name]
                }
                if {[dict exists $m section] && [dict get $m section] ne ""} {
                    set sec [dict get $m section]
                    if {[dict get $curSheet title] ne ""} {
                        dict set curSheet title "[dict get $curSheet title]($sec)"
                    }
                }
                set subParts {}
                if {[dict exists $m version] && [dict get $m version] ne ""} {
                    lappend subParts [dict get $m version]
                }
                if {[dict exists $m part] && [dict get $m part] ne ""} {
                    lappend subParts [dict get $m part]
                }
                if {[llength $subParts] > 0} {
                    dict set curSheet subtitle [join $subParts " . "]
                }
            }
            heading {
                set m [dict get $node meta]
                set level 1
                if {[dict exists $m level]} { set level [dict get $m level] }
                set txt [inlinesToText [dict get $node content]]

                if {$level == 1} {
                    incr h1Count
                    if {$h1Count == 1} {
                        if {[dict get $curSheet title] eq ""} {
                            dict set curSheet title $txt
                        }
                    } else {
                        # 2. H1+ = neues Sheet
                        if {$curSection ne ""} {
                            set sections [dict get $curSheet sections]
                            lappend sections [packSection $curSection $curSectionContent]
                            dict set curSheet sections $sections
                            set curSection ""
                            set curSectionContent {}
                        }
                        lappend sheets $curSheet
                        set curSheet [dict create title $txt subtitle "" sections {}]
                    }
                } else {
                    # H2+: neue Section
                    if {$curSection ne ""} {
                        set sections [dict get $curSheet sections]
                        lappend sections [packSection $curSection $curSectionContent]
                        dict set curSheet sections $sections
                    }
                    set curSection $txt
                    set curSectionContent {}
                }
            }
            default {
                if {$curSection eq ""} {
                    set curSection "Übersicht"
                }
                lappend curSectionContent $node
            }
        }
    }

    # Letzte Section + Sheet abschliessen
    if {$curSection ne ""} {
        set sections [dict get $curSheet sections]
        lappend sections [packSection $curSection $curSectionContent]
        dict set curSheet sections $sections
    }
    if {[llength [dict get $curSheet sections]] > 0 || \
        [dict get $curSheet title] ne ""} {
        lappend sheets $curSheet
    }

    if {[llength $sheets] > 0 && $titleOverride ne ""} {
        set sheets [lreplace $sheets 0 0 \
            [dict replace [lindex $sheets 0] title $titleOverride]]
    }
    if {[llength $sheets] > 0 && $subtitleOverride ne ""} {
        set sheets [lreplace $sheets 0 0 \
            [dict replace [lindex $sheets 0] subtitle $subtitleOverride]]
    }

    return $sheets
}

# ---------------------------------------------------------------------------
# Section-Inhalt klassifizieren -> {title type content [intro]}
# ---------------------------------------------------------------------------

proc docir::tile::packSection {title content} {
    if {[llength $content] == 0} {
        return [dict create title $title type hint content {}]
    }

    # hr/blank entfernen — sie sind Trenner, keine Inhalts-Bloecke
    set filtered {}
    foreach b $content {
        set t [dict get $b type]
        if {$t in {hr blank}} continue
        lappend filtered $b
    }
    set content $filtered
    if {[llength $content] == 0} {
        return [dict create title $title type hint content {}]
    }

    # Klassifizieren: welche Block-Typen sind in der Section?
    set types {}
    foreach b $content {
        set t [dict get $b type]
        if {$t ni $types} { lappend types $t }
    }

    # Single-Type Sections
    if {[llength $types] == 1} {
        set onlyType [lindex $types 0]
        switch $onlyType {
            image {
                # image-Section: Liste von {url alt title} Tripeln
                set images {}
                foreach b $content {
                    set bm [dict get $b meta]
                    set url [expr {[dict exists $bm url] ? [dict get $bm url] : ""}]
                    set alt [expr {[dict exists $bm alt] ? [dict get $bm alt] : ""}]
                    set ttl [expr {[dict exists $bm title] ? [dict get $bm title] : ""}]
                    if {$url ne ""} {
                        lappend images [list $url $alt $ttl]
                    }
                }
                return [dict create title $title type image content $images]
            }
            pre {
                set lines {}
                foreach b $content {
                    set inlineText [inlinesToText [dict get $b content]]
                    foreach line [split $inlineText "\n"] {
                        lappend lines $line
                    }
                }
                return [dict create title $title type code content $lines]
            }
            list {
                set items {}
                foreach b $content {
                    foreach item [dict get $b content] {
                        if {[dict get $item type] ne "listItem"} continue
                        lappend items [inlinesToText [dict get $item content]]
                    }
                }
                return [dict create title $title type list content $items]
            }
            table {
                set rows {}
                foreach b $content {
                    foreach row [dict get $b content] {
                        if {[dict get $row type] ne "tableRow"} continue
                        set cells [dict get $row content]
                        set label ""
                        set value ""
                        if {[llength $cells] >= 1} {
                            set label [inlinesToText \
                                [dict get [lindex $cells 0] content]]
                        }
                        if {[llength $cells] >= 2} {
                            set value [inlinesToText \
                                [dict get [lindex $cells 1] content]]
                        }
                        if {$label ne "" || $value ne ""} {
                            lappend rows [list $label $value]
                        }
                    }
                }
                return [dict create title $title type table content $rows]
            }
            paragraph {
                set lines {}
                foreach b $content {
                    set txt [inlinesToText [dict get $b content]]
                    if {$txt ne ""} { lappend lines $txt }
                }
                return [dict create title $title type hint content $lines]
            }
        }
    }

    # Sonderfall: Intro-Para + Code -> code-intro Section
    set paragraphs 0
    set pres 0
    foreach b $content {
        set t [dict get $b type]
        switch $t {
            paragraph { incr paragraphs }
            pre       { incr pres }
        }
    }
    if {$paragraphs <= 2 && $pres >= 1 && \
        [llength $types] == [expr {($paragraphs > 0) + ($pres > 0)}]} {
        set introLines {}
        set codeLines {}
        foreach b $content {
            set t [dict get $b type]
            switch $t {
                paragraph {
                    set txt [inlinesToText [dict get $b content]]
                    if {$txt ne ""} { lappend introLines $txt }
                }
                pre {
                    set txt [inlinesToText [dict get $b content]]
                    foreach line [split $txt "\n"] {
                        lappend codeLines $line
                    }
                }
            }
        }
        if {[llength $introLines] == 0} {
            return [dict create title $title type code content $codeLines]
        }
        return [dict create title $title type code-intro \
            content $codeLines intro $introLines]
    }

    # Fallback: gemischter Inhalt -> hint mit Markern
    set lines {}
    foreach b $content {
        set t [dict get $b type]
        switch $t {
            paragraph {
                set txt [inlinesToText [dict get $b content]]
                if {$txt ne ""} { lappend lines $txt }
            }
            pre {
                set txt [inlinesToText [dict get $b content]]
                foreach line [split $txt "\n"] {
                    if {$line ne ""} { lappend lines "» $line" }
                }
            }
            list {
                foreach item [dict get $b content] {
                    if {[dict get $item type] ne "listItem"} continue
                    lappend lines "• [inlinesToText [dict get $item content]]"
                }
            }
            blank - hr {}
            default {
                set txt [inlinesToText [dict get $b content]]
                if {$txt ne ""} { lappend lines $txt }
            }
        }
    }
    return [dict create title $title type hint content $lines]
}
