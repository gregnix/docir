# docir-svg-0.1.tm -- DocIR → SVG Renderer
#
# Wandelt eine DocIR-Sequenz in SVG um. Zwei Modi:
#
#   foreignObject (Standard): nutzt docir-html intern und packt das
#                             Ergebnis in ein <foreignObject>-Element.
#                             Renderbar in Browsern, NICHT in Inkscape
#                             oder den meisten SVG→PDF-Tools.
#
#   native: eigenes Layout mit nativen <text>-Elementen. Renderbar in
#           Inkscape, svg2pdf, etc. Konservatives Zeichenbreite-Schaetzen
#           (fontSize * 0.6 fuer sans, * 0.62 fuer mono); Heights
#           akkumulieren je Block-Typ. Auto-Height nach Layout.
#
# Public API:
#   docir::svg::render ir ?options?
#       options: dict mit
#         mode         "foreignObject" (default) | "native"
#         width        Int                 (default 800)
#         height       Int|"auto"          (default "auto" — berechnet)
#         standalone   Bool                (default 1; 0 = nur <svg> ohne <?xml>)
#         title        String              (Standard: aus DocIR ermittelt)
#         cssExtra     String              (zusaetzliches CSS)
#         fontSize     Int                 (default 14)
#         fontFamily   String              (default "sans-serif")
#         monoFamily   String              (default "monospace")
#         padding      Int                 (default 20, Innenabstand)
#       Returns: SVG-String

package provide docir::svg 0.1

# Wir laden docir-html für den foreignObject-Modus
package require docir::html

namespace eval ::docir::svg {
    namespace export render
}

# ============================================================
# Public API
# ============================================================

proc docir::svg::render {ir {options {}}} {
    variable opts
    set opts [dict create \
        mode         "foreignObject" \
        width        800 \
        height       "auto" \
        standalone   1 \
        title        "" \
        cssExtra     "" \
        fontSize     14 \
        fontFamily   "sans-serif" \
        monoFamily   "monospace" \
        padding      20]
    foreach k [dict keys $options] {
        dict set opts $k [dict get $options $k]
    }

    set mode [dict get $opts mode]
    switch $mode {
        foreignObject { return [_renderForeignObject $ir] }
        native        { return [_renderNative $ir] }
        default {
            return -code error "docir::svg::render: unknown mode '$mode' (use foreignObject or native)"
        }
    }
}

# ============================================================
# Mode A: foreignObject (uses docir-html internally)
# ============================================================

proc docir::svg::_renderForeignObject {ir} {
    variable opts
    set width  [dict get $opts width]
    set height [dict get $opts height]
    if {$height eq "auto"} { set height 600 }   ;# foreignObject can't auto-size
    set padding [dict get $opts padding]
    set fontSize [dict get $opts fontSize]
    set fontFamily [dict get $opts fontFamily]
    set cssExtra [dict get $opts cssExtra]
    set standalone [dict get $opts standalone]

    set bodyWidth [expr {$width - 2 * $padding}]

    # HTML-Body via docir-html (body-only)
    set htmlOpts [dict create standalone 0 cssExtra $cssExtra]
    set htmlBody [docir::html::render $ir $htmlOpts]

    set inlineCss [_foreignObjectCss $fontSize $fontFamily $cssExtra]

    set out ""
    if {$standalone} {
        append out "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    }
    append out "<svg xmlns=\"http://www.w3.org/2000/svg\""
    append out " width=\"$width\" height=\"$height\""
    append out " viewBox=\"0 0 $width $height\">\n"
    append out "<foreignObject x=\"$padding\" y=\"$padding\""
    append out " width=\"$bodyWidth\" height=\"[expr {$height - 2 * $padding}]\">\n"
    append out "<div xmlns=\"http://www.w3.org/1999/xhtml\">\n"
    append out "<style>$inlineCss</style>\n"
    append out $htmlBody
    append out "</div>\n"
    append out "</foreignObject>\n"
    append out "</svg>\n"
    return $out
}

proc docir::svg::_foreignObjectCss {fontSize fontFamily cssExtra} {
    return "body, div { margin: 0; padding: 0; font-family: $fontFamily; font-size: ${fontSize}px; line-height: 1.4; color: #222; }
h1 { font-size: 1.4em; margin: 0.5em 0 0.3em; border-bottom: 1px solid #888; }
h2 { font-size: 1.2em; margin: 0.5em 0 0.3em; }
h3 { font-size: 1.05em; margin: 0.4em 0 0.2em; }
p  { margin: 0 0 0.5em; }
pre, code { font-family: monospace; background: #f4f4f4; }
pre { padding: 0.4em 0.6em; border-radius: 3px; }
code { padding: 0 0.2em; border-radius: 2px; }
.docir-doc-header { font-size: 0.8em; color: #666; margin-bottom: 0.8em; }
.docir-list-tp dt { font-weight: bold; margin-top: 0.3em; }
.docir-list-tp dd { margin-left: 1.5em; margin-bottom: 0.3em; }
ul, ol { margin: 0 0 0.5em 1.5em; padding: 0; }
table.docir-table td, table.docir-table th { padding: 0.2em 0.5em; border: 1px solid #ccc; }
$cssExtra"
}

# ============================================================
# Mode B: native SVG (own layout)
# ============================================================

proc docir::svg::_renderNative {ir} {
    variable opts
    set width    [dict get $opts width]
    set padding  [dict get $opts padding]
    set fontSize [dict get $opts fontSize]
    set fontFamily [dict get $opts fontFamily]
    set monoFamily [dict get $opts monoFamily]
    set standalone [dict get $opts standalone]

    set contentWidth [expr {$width - 2 * $padding}]
    set y $padding

    set elements ""
    foreach node $ir {
        set rendered [_layoutBlock $node $padding $y $contentWidth]
        set newY [lindex $rendered 0]
        set svg  [lindex $rendered 1]
        append elements $svg
        set y $newY
    }

    set heightOpt [dict get $opts height]
    if {$heightOpt eq "auto"} {
        set height [expr {$y + $padding}]
    } else {
        set height $heightOpt
    }

    set out ""
    if {$standalone} {
        append out "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    }
    append out "<svg xmlns=\"http://www.w3.org/2000/svg\""
    append out " width=\"$width\" height=\"$height\""
    append out " viewBox=\"0 0 $width $height\""
    append out " font-family=\"$fontFamily\""
    append out " font-size=\"${fontSize}\">\n"
    append out $elements
    append out "</svg>\n"
    return $out
}

# ============================================================
# Native layout — block dispatcher
# Returns: {newY, svgFragment}
# ============================================================

proc docir::svg::_layoutBlock {node x y contentWidth} {
    set t [dict get $node type]
    switch $t {
        doc_header   { return [_layoutDocHeader  $node $x $y $contentWidth] }
        heading      { return [_layoutHeading    $node $x $y $contentWidth] }
        paragraph    { return [_layoutParagraph  $node $x $y $contentWidth] }
        pre          { return [_layoutPre        $node $x $y $contentWidth] }
        list         { return [_layoutList       $node $x $y $contentWidth] }
        listItem     { return [_layoutListItem   $node $x $y $contentWidth] }
        blank        { return [_layoutBlank      $node $x $y $contentWidth] }
        hr           { return [_layoutHr         $node $x $y $contentWidth] }
        table        { return [_layoutTable     $node $x $y $contentWidth] }
        image        { return [_layoutImageBlock $node $x $y $contentWidth] }
        footnote_section { return [_layoutFootnoteSection $node $x $y $contentWidth] }
        footnote_def {
            # top-level footnote_def — als paragraph rendern
            return [_layoutFootnoteDef $node $x $y $contentWidth]
        }
        div          { return [_layoutDiv $node $x $y $contentWidth] }
        tableRow     -
        tableCell    {
            return [_layoutUnknown $node $x $y $contentWidth "stray $t at top"]
        }
        default {
            if {[::docir::isSchemaOnly $t]} { return [list $y ""] }
            return [_layoutUnknown $node $x $y $contentWidth "unknown type: $t"]
        }
    }
}

# ============================================================
# Native layout — measurements (conservative estimates)
# ============================================================

proc docir::svg::_charWidth {fontSize {mono 0}} {
    if {$mono} {
        return [expr {int($fontSize * 0.62)}]
    }
    return [expr {int($fontSize * 0.55)}]
}

proc docir::svg::_lineHeight {fontSize} {
    return [expr {int($fontSize * 1.4)}]
}

# Wraps text into lines that fit within maxWidth (in pixels)
proc docir::svg::_wrap {text maxWidth fontSize {mono 0}} {
    set cw [_charWidth $fontSize $mono]
    if {$cw <= 0} { set cw 1 }
    set maxChars [expr {$maxWidth / $cw}]
    if {$maxChars < 1} { set maxChars 1 }

    set lines {}
    foreach paragraphLine [split $text "\n"] {
        if {[string length $paragraphLine] == 0} {
            lappend lines ""
            continue
        }
        set words [split $paragraphLine " "]
        set current ""
        foreach w $words {
            set candidate [expr {$current eq "" ? $w : "$current $w"}]
            if {[string length $candidate] <= $maxChars} {
                set current $candidate
            } else {
                if {$current ne ""} { lappend lines $current }
                set current $w
                # Wenn ein einzelnes Wort breiter als maxChars ist,
                # einfach so stehen lassen — kein hartes Brechen.
            }
        }
        if {$current ne ""} { lappend lines $current }
    }
    if {[llength $lines] == 0} { set lines [list ""] }
    return $lines
}

proc docir::svg::_inlinesToText {inlines} {
    set out ""
    foreach i $inlines {
        if {[dict exists $i text]} { append out [dict get $i text] }
    }
    return $out
}

# ============================================================
# Native layout — block renderers
# ============================================================

proc docir::svg::_layoutDocHeader {node x y contentWidth} {
    variable opts
    set fontSize [expr {[dict get $opts fontSize] - 2}]
    set lh [_lineHeight $fontSize]

    set m [dict get $node meta]
    set name    [expr {[dict exists $m name]    ? [dict get $m name]    : ""}]
    set section [expr {[dict exists $m section] ? [dict get $m section] : ""}]
    set version [expr {[dict exists $m version] ? [dict get $m version] : ""}]
    set part    [expr {[dict exists $m part]    ? [dict get $m part]    : ""}]

    set parts {}
    if {$name ne ""} {
        if {$section ne ""} {
            lappend parts "${name}(${section})"
        } else {
            lappend parts $name
        }
    }
    if {$part ne ""}    { lappend parts $part }
    if {$version ne ""} { lappend parts $version }
    set txt [join $parts " · "]
    if {$txt eq ""} { return [list $y ""] }

    set svg "<text x=\"$x\" y=\"[expr {$y + $fontSize}]\" font-size=\"${fontSize}\" fill=\"#888\">[_xmlEscape $txt]</text>\n"
    set svg "$svg<line x1=\"$x\" y1=\"[expr {$y + $lh + 2}]\" x2=\"[expr {$x + $contentWidth}]\" y2=\"[expr {$y + $lh + 2}]\" stroke=\"#ddd\" stroke-width=\"1\"/>\n"
    return [list [expr {$y + $lh + 8}] $svg]
}

proc docir::svg::_layoutHeading {node x y contentWidth} {
    variable opts
    set baseFontSize [dict get $opts fontSize]
    set m [dict get $node meta]
    set lv [expr {[dict exists $m level] ? [dict get $m level] : 1}]
    if {$lv < 1} { set lv 1 }
    if {$lv > 6} { set lv 6 }

    # Heading-Sizes: h1 +6, h2 +3, h3 +1, rest 0
    set bonus [list 0 6 3 1 0 0 0]
    set fontSize [expr {$baseFontSize + [lindex $bonus $lv]}]
    set lh [_lineHeight $fontSize]

    set txt [_inlinesToText [dict get $node content]]
    set lines [_wrap $txt $contentWidth $fontSize]
    set yTop [expr {$y + 8}]   ;# extra space above heading

    set svg ""
    set yLine [expr {$yTop + $fontSize}]
    foreach line $lines {
        append svg "<text x=\"$x\" y=\"$yLine\" font-size=\"${fontSize}\" font-weight=\"bold\">[_xmlEscape $line]</text>\n"
        set yLine [expr {$yLine + $lh}]
    }

    if {$lv == 1} {
        # Underline für h1
        set ulY [expr {$yLine - $lh + 4}]
        append svg "<line x1=\"$x\" y1=\"$ulY\" x2=\"[expr {$x + $contentWidth}]\" y2=\"$ulY\" stroke=\"#888\" stroke-width=\"1\"/>\n"
    }

    return [list [expr {$yLine + 4}] $svg]
}

proc docir::svg::_layoutParagraph {node x y contentWidth} {
    variable opts
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set m [dict get $node meta]
    set class [expr {[dict exists $m class] ? [dict get $m class] : ""}]

    # Plaintext rendern (mit minimaler Inline-Formatierung
    # über tspan-Spans wenn nötig). Erstmal: alles als ein Block.
    set txt [_inlinesToText [dict get $node content]]
    set lines [_wrap $txt $contentWidth $fontSize]

    set xText $x
    if {$class eq "blockquote"} {
        # Linker Balken plus Einzug
        set bQTop $y
        set bQBot [expr {$y + [llength $lines] * $lh}]
        set indent 12
        set xText [expr {$x + $indent + 6}]
    }

    set svg ""
    set yLine [expr {$y + $fontSize}]
    foreach line $lines {
        append svg "<text x=\"$xText\" y=\"$yLine\" font-size=\"${fontSize}\">[_xmlEscape $line]</text>\n"
        set yLine [expr {$yLine + $lh}]
    }
    if {$class eq "blockquote"} {
        set bQBot [expr {$yLine - $lh + 4}]
        append svg "<line x1=\"$x\" y1=\"$y\" x2=\"$x\" y2=\"$bQBot\" stroke=\"#ccc\" stroke-width=\"3\"/>\n"
    }

    return [list [expr {$yLine - $lh + $lh + 4}] $svg]
}

proc docir::svg::_layoutPre {node x y contentWidth} {
    variable opts
    set fontSize [dict get $opts fontSize]
    set monoFamily [dict get $opts monoFamily]
    set lh [_lineHeight $fontSize]

    set txt [_inlinesToText [dict get $node content]]
    # In pre: Zeilen am Newline trennen, NICHT umbrechen (wäre semantisch falsch)
    set lines [split $txt "\n"]

    # Hintergrundbox vorbereiten
    set yTop [expr {$y + 4}]
    set yBot [expr {$yTop + [llength $lines] * $lh + 8}]
    set xLeft [expr {$x - 4}]
    set wRect [expr {$contentWidth + 8}]

    set svg "<rect x=\"$xLeft\" y=\"$yTop\" width=\"$wRect\" height=\"[expr {$yBot - $yTop}]\" fill=\"#f4f4f4\" rx=\"3\"/>\n"
    set yLine [expr {$yTop + 4 + $fontSize}]
    foreach line $lines {
        append svg "<text x=\"$x\" y=\"$yLine\" font-size=\"${fontSize}\" font-family=\"$monoFamily\">[_xmlEscape $line]</text>\n"
        set yLine [expr {$yLine + $lh}]
    }

    return [list [expr {$yBot + 4}] $svg]
}

proc docir::svg::_layoutList {node x y contentWidth} {
    variable opts
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set m [dict get $node meta]
    set kind [expr {[dict exists $m kind] ? [dict get $m kind] : "ul"}]

    set svg ""
    set yCur $y

    set ord 1
    foreach item [dict get $node content] {
        set itemType [dict get $item type]
        if {$itemType ne "listItem"} {
            # Schema-Verletzung — Kommentar als <!-- … --> ist in SVG zwar
            # technisch erlaubt, aber wir machen sichtbares Warnzeichen
            set yCur [expr {$yCur + 4}]
            append svg "<text x=\"$x\" y=\"[expr {$yCur + $fontSize}]\" font-size=\"${fontSize}\" fill=\"#a00\">⚠ schema warning: $itemType in list.content</text>\n"
            set yCur [expr {$yCur + $lh}]
            continue
        }

        set itemMeta  [dict get $item meta]
        set itemKind  [expr {[dict exists $itemMeta kind] ? [dict get $itemMeta kind] : $kind}]
        set itemTerm  [expr {[dict exists $itemMeta term] ? [dict get $itemMeta term] : {}}]
        set itemDescInlines [dict get $item content]

        switch $itemKind {
            ol {
                set marker "${ord}. "
                set markerW [expr {[string length $marker] * [_charWidth $fontSize]}]
                set xText [expr {$x + $markerW + 4}]
                set wText [expr {$contentWidth - $markerW - 4}]
                set descTxt [_inlinesToText $itemDescInlines]
                set lines [_wrap $descTxt $wText $fontSize]
                set yLine [expr {$yCur + $fontSize}]
                set firstLine 1
                foreach line $lines {
                    if {$firstLine} {
                        append svg "<text x=\"$x\" y=\"$yLine\" font-size=\"${fontSize}\">[_xmlEscape $marker][_xmlEscape $line]</text>\n"
                        set firstLine 0
                    } else {
                        append svg "<text x=\"$xText\" y=\"$yLine\" font-size=\"${fontSize}\">[_xmlEscape $line]</text>\n"
                    }
                    set yLine [expr {$yLine + $lh}]
                }
                set yCur [expr {$yLine - $lh + $lh}]
                incr ord
            }
            tp - ip - op - ap - dl {
                # Term auf eigener Zeile (fett), description darunter mit Einzug
                set termTxt [_inlinesToText $itemTerm]
                set descTxt [_inlinesToText $itemDescInlines]
                set indent [expr {2 * [_charWidth $fontSize]}]
                set xDesc [expr {$x + $indent}]
                set wDesc [expr {$contentWidth - $indent}]

                if {$termTxt ne ""} {
                    append svg "<text x=\"$x\" y=\"[expr {$yCur + $fontSize}]\" font-size=\"${fontSize}\" font-weight=\"bold\">[_xmlEscape $termTxt]</text>\n"
                    set yCur [expr {$yCur + $lh}]
                }
                if {$descTxt ne ""} {
                    set lines [_wrap $descTxt $wDesc $fontSize]
                    set yLine [expr {$yCur + $fontSize}]
                    foreach line $lines {
                        append svg "<text x=\"$xDesc\" y=\"$yLine\" font-size=\"${fontSize}\">[_xmlEscape $line]</text>\n"
                        set yLine [expr {$yLine + $lh}]
                    }
                    set yCur [expr {$yLine - $lh + $lh}]
                }
                set yCur [expr {$yCur + 2}]
            }
            default {
                # ul oder unknown
                set marker "•"
                set markerW [expr {2 * [_charWidth $fontSize]}]
                set xText [expr {$x + $markerW}]
                set wText [expr {$contentWidth - $markerW}]
                set descTxt [_inlinesToText $itemDescInlines]
                set lines [_wrap $descTxt $wText $fontSize]
                set yLine [expr {$yCur + $fontSize}]
                set firstLine 1
                foreach line $lines {
                    if {$firstLine} {
                        append svg "<text x=\"$x\" y=\"$yLine\" font-size=\"${fontSize}\">$marker</text>\n"
                        append svg "<text x=\"$xText\" y=\"$yLine\" font-size=\"${fontSize}\">[_xmlEscape $line]</text>\n"
                        set firstLine 0
                    } else {
                        append svg "<text x=\"$xText\" y=\"$yLine\" font-size=\"${fontSize}\">[_xmlEscape $line]</text>\n"
                    }
                    set yLine [expr {$yLine + $lh}]
                }
                set yCur [expr {$yLine - $lh + $lh}]
            }
        }
    }
    return [list [expr {$yCur + 4}] $svg]
}

proc docir::svg::_layoutListItem {node x y contentWidth} {
    # Standalone listItem (Schema-Fehler) — wie paragraph rendern
    variable opts
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]
    set txt [_inlinesToText [dict get $node content]]
    set svg "<text x=\"$x\" y=\"[expr {$y + $fontSize}]\" font-size=\"${fontSize}\" fill=\"#a00\">⚠ standalone listItem: [_xmlEscape $txt]</text>\n"
    return [list [expr {$y + $lh + 4}] $svg]
}

proc docir::svg::_layoutBlank {node x y contentWidth} {
    variable opts
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]
    set m [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
    set lines [expr {[dict exists $m lines] ? [dict get $m lines] : 1}]
    if {$lines < 1} { set lines 1 }
    return [list [expr {$y + $lines * $lh / 2}] ""]
}

proc docir::svg::_layoutHr {node x y contentWidth} {
    variable opts
    set lh [_lineHeight [dict get $opts fontSize]]
    set yLine [expr {$y + $lh / 2}]
    set svg "<line x1=\"$x\" y1=\"$yLine\" x2=\"[expr {$x + $contentWidth}]\" y2=\"$yLine\" stroke=\"#ccc\" stroke-width=\"1\"/>\n"
    return [list [expr {$y + $lh}] $svg]
}

proc docir::svg::_layoutTable {node x y contentWidth} {
    variable opts
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set m [dict get $node meta]
    set columns   [expr {[dict exists $m columns]   ? [dict get $m columns]   : 0}]
    set hasHeader [expr {[dict exists $m hasHeader] ? [dict get $m hasHeader] : 0}]

    if {$columns < 1} {
        return [_layoutUnknown $node $x $y $contentWidth "table without columns"]
    }
    set colW [expr {$contentWidth / $columns}]
    set padX 6
    set padY 4

    set svg ""
    set yCur $y
    set rowIndex 0
    foreach row [dict get $node content] {
        if {[dict get $row type] ne "tableRow"} {
            incr rowIndex
            continue
        }
        set rowH [expr {$lh + 2 * $padY}]
        set isHeader [expr {$hasHeader && $rowIndex == 0}]

        # Hintergrund für Header-Zeile
        if {$isHeader} {
            append svg "<rect x=\"$x\" y=\"$yCur\" width=\"$contentWidth\" height=\"$rowH\" fill=\"#f4f4f4\"/>\n"
        }

        set colIndex 0
        foreach cell [dict get $row content] {
            if {[dict get $cell type] ne "tableCell"} {
                incr colIndex
                continue
            }
            set xCell [expr {$x + $colIndex * $colW}]
            set txt [_inlinesToText [dict get $cell content]]
            set xText [expr {$xCell + $padX}]
            set yText [expr {$yCur + $padY + $fontSize}]
            set fw [expr {$isHeader ? "bold" : "normal"}]
            append svg "<text x=\"$xText\" y=\"$yText\" font-size=\"${fontSize}\" font-weight=\"$fw\">[_xmlEscape $txt]</text>\n"
            # vertikaler Strich
            append svg "<line x1=\"$xCell\" y1=\"$yCur\" x2=\"$xCell\" y2=\"[expr {$yCur + $rowH}]\" stroke=\"#ccc\" stroke-width=\"1\"/>\n"
            incr colIndex
        }
        # rechte Außenkante
        append svg "<line x1=\"[expr {$x + $contentWidth}]\" y1=\"$yCur\" x2=\"[expr {$x + $contentWidth}]\" y2=\"[expr {$yCur + $rowH}]\" stroke=\"#ccc\" stroke-width=\"1\"/>\n"
        # untere Linie der Zeile
        append svg "<line x1=\"$x\" y1=\"[expr {$yCur + $rowH}]\" x2=\"[expr {$x + $contentWidth}]\" y2=\"[expr {$yCur + $rowH}]\" stroke=\"#ccc\" stroke-width=\"1\"/>\n"
        if {$rowIndex == 0} {
            append svg "<line x1=\"$x\" y1=\"$yCur\" x2=\"[expr {$x + $contentWidth}]\" y2=\"$yCur\" stroke=\"#ccc\" stroke-width=\"1\"/>\n"
        }

        set yCur [expr {$yCur + $rowH}]
        incr rowIndex
    }
    return [list [expr {$yCur + 8}] $svg]
}

proc docir::svg::_layoutImageBlock {node x y contentWidth} {
    variable opts
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]
    set m [dict get $node meta]
    set url [expr {[dict exists $m url] ? [dict get $m url] : ""}]
    set alt [expr {[dict exists $m alt] ? [dict get $m alt] : ""}]

    # Default-Größe — könnte als Option exposed werden
    set imgW [expr {min($contentWidth, 200)}]
    set imgH 150
    set svg "<image x=\"$x\" y=\"$y\" width=\"$imgW\" height=\"$imgH\" href=\"[_xmlEscape $url]\""
    if {$alt ne ""} {
        append svg " aria-label=\"[_xmlEscape $alt]\""
    }
    append svg "/>\n"

    set newY [expr {$y + $imgH + $lh}]

    if {$alt ne ""} {
        set yLine [expr {$newY + $fontSize}]
        append svg "<text x=\"$x\" y=\"$yLine\" font-size=\"${fontSize}\" font-style=\"italic\" fill=\"#666\">[_xmlEscape $alt]</text>\n"
        set newY [expr {$newY + $lh}]
    }

    return [list $newY $svg]
}

proc docir::svg::_layoutFootnoteSection {node x y contentWidth} {
    variable opts
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set svg ""

    set yLine [expr {$y + 4}]
    append svg "<line x1=\"$x\" y1=\"$yLine\" x2=\"[expr {$x + 100}]\" y2=\"$yLine\" stroke=\"#888\" stroke-width=\"1\"/>\n"
    set yCur [expr {$yLine + $lh}]

    foreach def [dict get $node content] {
        if {[dict get $def type] ne "footnote_def"} continue
        lassign [_layoutFootnoteDef $def $x $yCur $contentWidth] yNew block
        append svg $block
        set yCur $yNew
    }

    return [list $yCur $svg]
}

proc docir::svg::_layoutFootnoteDef {node x y contentWidth} {
    variable opts
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]
    set m [dict get $node meta]
    set num [expr {[dict exists $m num] ? [dict get $m num] : "?"}]

    set body [_inlinesToText [dict get $node content]]
    set fullText "\[$num\] $body"
    set lines [_wrap $fullText $contentWidth $fontSize]

    set svg ""
    set yLine [expr {$y + $fontSize}]
    foreach line $lines {
        append svg "<text x=\"$x\" y=\"$yLine\" font-size=\"${fontSize}\">[_xmlEscape $line]</text>\n"
        set yLine [expr {$yLine + $lh}]
    }
    return [list $yLine $svg]
}

proc docir::svg::_layoutDiv {node x y contentWidth} {
    set svg ""
    set yCur $y
    foreach child [dict get $node content] {
        lassign [_layoutBlock $child $x $yCur $contentWidth] yNew block
        append svg $block
        set yCur $yNew
    }
    return [list $yCur $svg]
}

proc docir::svg::_layoutUnknown {node x y contentWidth reason} {
    variable opts
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]
    set svg "<rect x=\"$x\" y=\"$y\" width=\"$contentWidth\" height=\"[expr {$lh + 8}]\" fill=\"#fff8dc\" stroke=\"#d4b428\"/>\n"
    set svg "$svg<text x=\"[expr {$x + 6}]\" y=\"[expr {$y + 4 + $fontSize}]\" font-size=\"${fontSize}\" fill=\"#666\">[_xmlEscape $reason]</text>\n"
    return [list [expr {$y + $lh + 12}] $svg]
}

# ============================================================
# XML escaping (for native mode text content)
# ============================================================

proc docir::svg::_xmlEscape {s} {
    return [string map {
        "&"  "&amp;"
        "<"  "&lt;"
        ">"  "&gt;"
        "\"" "&quot;"
        "'"  "&#39;"
    } $s]
}
