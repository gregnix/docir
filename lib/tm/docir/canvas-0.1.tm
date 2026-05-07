# docir-canvas-0.1.tm -- DocIR → Tk-Canvas Renderer
#
# Wandelt eine DocIR-Sequenz in Canvas-Items um. Anwendungsfall:
# Print-Preview, Druck-Vorschau, oder Vektor-Anzeige in einer Tk-App
# die nicht die volle Text-Widget-API will.
#
# Vorteile gegenueber docir-svg native:
#   - Tk Canvas hat eine eingebaute Text-Layout-Engine: -width macht
#     automatisches Wrap. Wir messen die Hoehe per bbox NACH der
#     Erstellung — keine Schaetzung mehr.
#   - Ergebnis ist in Tk direkt sichtbar, kann interaktiv bedient
#     werden (Scrollen, Zoom).
#   - Per `$canvas postscript` als PostScript exportierbar, von dort
#     via ps2pdf/gs in PDF.
#
# Vorteile gegenueber docir-renderer-tk:
#   - Vektor-Items statt Text-Tags — gut fuer Print-Preview
#   - Echte Seiten-Begrenzungen sichtbar machen (Seitenrahmen, Margen)
#
# Public API:
#   docir::canvas::render canvas ir ?options?
#       options: dict mit
#         width        Int     (Canvas-Breite in Pixel; default: aus Canvas)
#         margin       Int     (default 20)
#         fontSize     Int     (default 12)
#         fontFamily   String  (default {TkDefaultFont})
#         monoFamily   String  (default {TkFixedFont})
#         pageMode     Bool    (default 0; wenn 1: Page-Breaks visuell zeichnen)
#         pageHeight   Int     (default 1000; Seitenhoehe wenn pageMode=1)
#       Returns: Liste der erzeugten Canvas-Item-IDs (fuer Cleanup)
#
#   docir::canvas::clear canvas
#       Alle Items entfernen die docir::canvas erzeugt hat (per Tag).

package provide docir::canvas 0.1
package require docir 0.1
package require Tk

namespace eval ::docir::canvas {
    namespace export render clear
    variable st  ;# state-dict
}

# ============================================================
# Public API
# ============================================================

proc docir::canvas::render {canvas ir {options {}}} {
    variable st

    set opts [dict create \
        width      0 \
        margin     20 \
        fontSize   12 \
        fontFamily {TkDefaultFont} \
        monoFamily {TkFixedFont} \
        pageMode   0 \
        pageHeight 1000]
    foreach k [dict keys $options] {
        dict set opts $k [dict get $options $k]
    }

    # Canvas-Breite ermitteln, falls nicht in options
    set width [dict get $opts width]
    if {$width <= 0} {
        update idletasks
        set width [winfo width $canvas]
        if {$width <= 1} {
            set width 600  ;# Fallback
        }
    }

    set margin [dict get $opts margin]
    set contentW [expr {$width - 2 * $margin}]

    set st [dict create \
        canvas    $canvas \
        opts      $opts \
        width     $width \
        margin    $margin \
        contentW  $contentW \
        x         $margin \
        y         $margin \
        topY      $margin \
        items     {}]

    # Eigener Tag fuer alle erzeugten Items
    set tag "docir-canvas"

    foreach node $ir {
        _renderBlock $node $tag

        # Page-Break wenn pageMode aktiv
        if {[dict get $opts pageMode] && [dict get $st y] > [dict get $opts pageHeight]} {
            _drawPageBreak $tag
        }
    }

    # Scroll-Region setzen damit alles sichtbar ist
    set bbox [$canvas bbox $tag]
    if {$bbox ne ""} {
        $canvas configure -scrollregion $bbox
    }

    return [dict get $st items]
}

proc docir::canvas::clear {canvas} {
    $canvas delete docir-canvas
}

# ============================================================
# State helpers
# ============================================================

proc docir::canvas::_advanceY {dy} {
    variable st
    dict set st y [expr {[dict get $st y] + $dy}]
}

proc docir::canvas::_recordItem {id} {
    variable st
    dict lappend st items $id
}

proc docir::canvas::_font {style} {
    variable st
    set opts [dict get $st opts]
    set base [dict get $opts fontFamily]
    set mono [dict get $opts monoFamily]
    set sz   [dict get $opts fontSize]

    switch $style {
        bold        { return [list $base $sz bold] }
        italic      { return [list $base $sz italic] }
        bolditalic  { return [list $base $sz bold italic] }
        mono        { return [list $mono $sz] }
        monobold    { return [list $mono $sz bold] }
        h1          { return [list $base [expr {$sz + 6}] bold] }
        h2          { return [list $base [expr {$sz + 4}] bold] }
        h3          { return [list $base [expr {$sz + 2}] bold] }
        h4          { return [list $base [expr {$sz + 1}] bold] }
        h5          -
        h6          { return [list $base $sz bold] }
        small       { return [list $base [expr {$sz - 2}] italic] }
        default     { return [list $base $sz] }
    }
}

# ============================================================
# Helpers
# ============================================================

proc docir::canvas::_inlinesToText {inlines} {
    set out ""
    foreach i $inlines {
        if {[dict exists $i text]} { append out [dict get $i text] }
    }
    return $out
}

# Erzeugt ein Text-Item mit max-width Wrap und gibt die Hoehe zurueck.
# Wraps bei Bedarf via Canvas eingebauter Layout-Engine.
proc docir::canvas::_drawText {x y text font width tag {extraOpts {}}} {
    variable st
    set canvas [dict get $st canvas]
    set createOpts [list \
        -text $text -font $font -anchor nw -width $width -tags [list $tag]]
    foreach {k v} $extraOpts {
        lappend createOpts $k $v
    }
    set id [$canvas create text $x $y {*}$createOpts]
    _recordItem $id

    set bbox [$canvas bbox $id]
    if {$bbox eq ""} { return [list $id 0] }
    lassign $bbox bx1 by1 bx2 by2
    return [list $id [expr {$by2 - $by1}]]
}

# ============================================================
# Block dispatcher
# ============================================================

proc docir::canvas::_renderBlock {node tag} {
    set t [dict get $node type]
    switch $t {
        doc_header   { _renderDocHeader $node $tag }
        heading      { _renderHeading   $node $tag }
        paragraph    { _renderParagraph $node $tag }
        pre          { _renderPre       $node $tag }
        list         { _renderList      $node $tag }
        listItem     { _renderListItem  $node $tag }
        blank        { _renderBlank     $node $tag }
        hr           { _renderHr        $node $tag }
        table        { _renderTable     $node $tag }
        image        { _renderImageBlock     $node $tag }
        footnote_section { _renderFootnoteSection $node $tag }
        footnote_def     { _renderFootnoteDef     $node $tag }
        div          { _renderDiv       $node $tag }
        tableRow     -
        tableCell    {
            _renderUnknown $node $tag "stray $t at top level"
        }
        default      {
            if {[::docir::isSchemaOnly $t]} { return }
            _renderUnknown $node $tag "unknown block: $t"
        }
    }
}

# ============================================================
# Block renderers
# ============================================================

proc docir::canvas::_renderDocHeader {node tag} {
    variable st
    set canvas [dict get $st canvas]
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
    set txt [join $parts "  ·  "]
    if {$txt eq ""} { return }

    set x [dict get $st margin]
    set y [dict get $st y]
    lassign [_drawText $x $y $txt [_font small] [dict get $st contentW] $tag \
        [list -fill #888]] _ h
    _advanceY [expr {$h + 2}]

    # Trennlinie
    set y2 [dict get $st y]
    set xR [expr {$x + [dict get $st contentW]}]
    set lineId [$canvas create line $x $y2 $xR $y2 \
        -fill "#ddd" -width 1 -tags [list $tag]]
    _recordItem $lineId
    _advanceY 6
}

proc docir::canvas::_renderHeading {node tag} {
    variable st
    set canvas [dict get $st canvas]
    set m [dict get $node meta]
    set lv [expr {[dict exists $m level] ? [dict get $m level] : 1}]
    if {$lv < 1} { set lv 1 }
    if {$lv > 6} { set lv 6 }

    set txt [_inlinesToText [dict get $node content]]
    if {$txt eq ""} { return }

    _advanceY 6  ;# extra space above

    set x [dict get $st margin]
    set y [dict get $st y]
    lassign [_drawText $x $y $txt [_font "h$lv"] [dict get $st contentW] $tag] \
        _ h
    _advanceY $h

    if {$lv == 1} {
        # Linie unter h1
        set y2 [dict get $st y]
        set xR [expr {$x + [dict get $st contentW]}]
        set lineId [$canvas create line $x $y2 $xR $y2 \
            -fill "#888" -width 1 -tags [list $tag]]
        _recordItem $lineId
        _advanceY 4
    } else {
        _advanceY 2
    }
}

proc docir::canvas::_renderParagraph {node tag} {
    variable st
    set canvas [dict get $st canvas]
    set m [dict get $node meta]
    set class [expr {[dict exists $m class] ? [dict get $m class] : ""}]
    set txt [_inlinesToText [dict get $node content]]
    if {$txt eq ""} { return }

    set indent 0
    if {$class eq "blockquote"} { set indent 16 }
    set x [expr {[dict get $st margin] + $indent}]
    set wText [expr {[dict get $st contentW] - $indent}]
    set yTop [dict get $st y]

    lassign [_drawText $x $yTop $txt [_font ""] $wText $tag] _ h
    _advanceY $h

    if {$class eq "blockquote"} {
        # Linker Balken
        set xBar [dict get $st margin]
        set yBot [dict get $st y]
        set barId [$canvas create line $xBar $yTop $xBar $yBot \
            -fill "#ccc" -width 3 -tags [list $tag]]
        _recordItem $barId
    }
    _advanceY 4
}

proc docir::canvas::_renderPre {node tag} {
    variable st
    set canvas [dict get $st canvas]
    set txt [_inlinesToText [dict get $node content]]
    if {$txt eq ""} { return }

    # Im pre: kein Wrap, Newlines bleiben — width=0 deaktiviert Tk-Wrap
    set x [expr {[dict get $st margin] + 4}]
    set yTop [dict get $st y]

    set padding 4
    _advanceY $padding

    set xText $x
    set yText [dict get $st y]
    lassign [_drawText $xText $yText $txt [_font mono] 0 $tag] _ h

    # Hintergrund-Rect ermitteln (mit padding)
    set yBot [expr {$yText + $h + $padding}]
    set xLeft [expr {[dict get $st margin]}]
    set xRight [expr {$xLeft + [dict get $st contentW]}]
    set rectId [$canvas create rectangle $xLeft $yTop $xRight $yBot \
        -fill "#f4f4f4" -outline "" -tags [list $tag]]
    _recordItem $rectId
    # Rect MUSS unter den Text — also nach hinten setzen
    $canvas lower $rectId

    _advanceY [expr {$h + $padding}]
    _advanceY 4
}

proc docir::canvas::_renderList {node tag} {
    variable st
    set canvas [dict get $st canvas]
    set opts [dict get $st opts]
    set fontSize [dict get $opts fontSize]

    set m [dict get $node meta]
    set kind [expr {[dict exists $m kind] ? [dict get $m kind] : "ul"}]

    set ord 1
    foreach item [dict get $node content] {
        set itemType [dict get $item type]
        if {$itemType ne "listItem"} {
            # Schema-Verletzung — sichtbar machen
            _renderUnknown $item $tag "schema warning: $itemType in list.content"
            continue
        }

        set itemMeta [dict get $item meta]
        set itemKind [expr {[dict exists $itemMeta kind] ? [dict get $itemMeta kind] : $kind}]
        set itemTerm [expr {[dict exists $itemMeta term] ? [dict get $itemMeta term] : {}}]
        set itemDescInlines [dict get $item content]
        set descTxt [_inlinesToText $itemDescInlines]
        set termTxt [_inlinesToText $itemTerm]

        switch $itemKind {
            ol {
                _renderListItemMarker "${ord}. " $descTxt $tag
                incr ord
            }
            tp - ip - op - ap - dl {
                _renderListItemTerm $termTxt $descTxt $tag
            }
            default {
                # ul oder unknown — Bullet via Unicode \u2022 funktioniert
                # in Tk-Canvas zuverlaessiger als in pdf4tcl WinAnsi
                _renderListItemMarker "\u2022  " $descTxt $tag
            }
        }
    }
    _advanceY 4
}

proc docir::canvas::_renderListItemMarker {marker descTxt tag} {
    variable st
    set canvas [dict get $st canvas]

    # Marker als eigenes Text-Item (kein Wrap)
    set xBase [dict get $st margin]
    set yBase [dict get $st y]
    set markerId [$canvas create text $xBase $yBase \
        -text $marker -font [_font ""] -anchor nw -tags [list $tag]]
    _recordItem $markerId
    set markerBbox [$canvas bbox $markerId]
    lassign $markerBbox _ _ markerR _
    set markerW [expr {$markerR - $xBase}]

    # Description mit Hang-Indent
    set xText [expr {$xBase + $markerW}]
    set wText [expr {[dict get $st contentW] - $markerW}]
    if {$descTxt ne ""} {
        lassign [_drawText $xText $yBase $descTxt [_font ""] $wText $tag] _ h
        _advanceY $h
    } else {
        # Marker hat eigene Hoehe
        set h [expr {[lindex $markerBbox 3] - [lindex $markerBbox 1]}]
        _advanceY $h
    }
}

proc docir::canvas::_renderListItemTerm {termTxt descTxt tag} {
    variable st
    set canvas [dict get $st canvas]
    set opts [dict get $st opts]
    set fontSize [dict get $opts fontSize]
    set xBase [dict get $st margin]

    if {$termTxt ne ""} {
        set y [dict get $st y]
        lassign [_drawText $xBase $y $termTxt [_font bold] [dict get $st contentW] $tag] _ h
        _advanceY $h
    }

    if {$descTxt ne ""} {
        # Einrueckung 2 em (~ 2 * fontSize)
        set indent [expr {2 * $fontSize}]
        set xDesc [expr {$xBase + $indent}]
        set wDesc [expr {[dict get $st contentW] - $indent}]
        set y [dict get $st y]
        lassign [_drawText $xDesc $y $descTxt [_font ""] $wDesc $tag] _ h
        _advanceY $h
    }
    _advanceY 2
}

proc docir::canvas::_renderListItem {node tag} {
    # Standalone listItem (Schema-Fehler)
    _renderUnknown $node $tag "standalone listItem"
}

proc docir::canvas::_renderBlank {node tag} {
    variable st
    set opts [dict get $st opts]
    set fontSize [dict get $opts fontSize]
    set m [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
    set lines [expr {[dict exists $m lines] ? [dict get $m lines] : 1}]
    if {$lines < 1} { set lines 1 }
    _advanceY [expr {$fontSize * $lines / 2}]
}

proc docir::canvas::_renderHr {node tag} {
    variable st
    set canvas [dict get $st canvas]
    set opts [dict get $st opts]
    set fontSize [dict get $opts fontSize]

    _advanceY [expr {$fontSize / 2}]
    set y [dict get $st y]
    set xL [dict get $st margin]
    set xR [expr {$xL + [dict get $st contentW]}]
    set lineId [$canvas create line $xL $y $xR $y \
        -fill "#ccc" -width 1 -tags [list $tag]]
    _recordItem $lineId
    _advanceY [expr {$fontSize / 2 + 4}]
}

proc docir::canvas::_renderTable {node tag} {
    variable st
    set canvas [dict get $st canvas]
    set opts [dict get $st opts]
    set fontSize [dict get $opts fontSize]

    set m [dict get $node meta]
    set columns   [expr {[dict exists $m columns]   ? [dict get $m columns]   : 0}]
    set hasHeader [expr {[dict exists $m hasHeader] ? [dict get $m hasHeader] : 0}]

    if {$columns < 1} {
        _renderUnknown $node $tag "table without columns"
        return
    }

    set colW [expr {[dict get $st contentW] / $columns}]
    set padX 4
    set padY 3

    set rowIndex 0
    foreach row [dict get $node content] {
        if {[dict get $row type] ne "tableRow"} {
            incr rowIndex
            continue
        }
        set isHeader [expr {$hasHeader && $rowIndex == 0}]
        set yTop [dict get $st y]

        # Erst alle Zellen rendern um die maximale Hoehe zu bekommen
        set cellIds {}
        set cellHeights {}
        set colIndex 0
        foreach cell [dict get $row content] {
            if {[dict get $cell type] ne "tableCell"} {
                incr colIndex
                continue
            }
            set xCell [expr {[dict get $st margin] + $colIndex * $colW}]
            set txt [_inlinesToText [dict get $cell content]]
            set xText [expr {$xCell + $padX}]
            set yText [expr {$yTop + $padY}]
            set font [expr {$isHeader ? [_font bold] : [_font ""]}]
            set id [$canvas create text $xText $yText \
                -text $txt -font $font -anchor nw \
                -width [expr {$colW - 2 * $padX}] \
                -tags [list $tag]]
            _recordItem $id
            set bbox [$canvas bbox $id]
            lassign $bbox _ _ _ y2
            lappend cellIds $id
            lappend cellHeights [expr {$y2 - $yText}]
            incr colIndex
        }

        # Maximale Hoehe finden + Zeilenhoehe daraus
        set maxH 0
        foreach ch $cellHeights {
            if {$ch > $maxH} { set maxH $ch }
        }
        set rowH [expr {$maxH + 2 * $padY}]
        set yBot [expr {$yTop + $rowH}]

        # Header-Hintergrund (vor allen Items, also hinter den Texten)
        if {$isHeader} {
            set xL [dict get $st margin]
            set xR [expr {$xL + [dict get $st contentW]}]
            set bgId [$canvas create rectangle $xL $yTop $xR $yBot \
                -fill "#f4f4f4" -outline "" -tags [list $tag]]
            _recordItem $bgId
            $canvas lower $bgId
        }

        # Zellen-Linien
        set colIndex 0
        for {set ci 0} {$ci <= $columns} {incr ci} {
            set x [expr {[dict get $st margin] + $ci * $colW}]
            set lineId [$canvas create line $x $yTop $x $yBot \
                -fill "#ccc" -width 1 -tags [list $tag]]
            _recordItem $lineId
        }

        # Untere Linie
        set xL [dict get $st margin]
        set xR [expr {$xL + [dict get $st contentW]}]
        set lineId [$canvas create line $xL $yBot $xR $yBot \
            -fill "#ccc" -width 1 -tags [list $tag]]
        _recordItem $lineId

        # Bei erster Zeile auch obere Linie
        if {$rowIndex == 0} {
            set lineId [$canvas create line $xL $yTop $xR $yTop \
                -fill "#ccc" -width 1 -tags [list $tag]]
            _recordItem $lineId
        }

        _advanceY $rowH
        incr rowIndex
    }
    _advanceY 4
}

proc docir::canvas::_renderImageBlock {node tag} {
    variable st
    set canvas [dict get $st canvas]
    set opts [dict get $st opts]
    set fontSize [dict get $opts fontSize]

    set m [dict get $node meta]
    set url [expr {[dict exists $m url] ? [dict get $m url] : ""}]
    set alt [expr {[dict exists $m alt] ? [dict get $m alt] : ""}]

    # Bild laden wenn möglich
    set imgLoaded 0
    if {$url ne "" && [file exists $url] && [file readable $url]} {
        if {[catch {image create photo -file $url} imgName] == 0} {
            set imgLoaded 1
        }
    }

    set x [dict get $st margin]
    set y [dict get $st y]

    if {$imgLoaded} {
        # Skalieren wenn größer als contentW
        set imgW [image width $imgName]
        set imgH [image height $imgName]
        set maxW [dict get $st contentW]
        if {$imgW > $maxW} {
            set scale [expr {$imgW / $maxW + 1}]
            set imgScaled [image create photo]
            $imgScaled copy $imgName -subsample $scale
            set imgName $imgScaled
            set imgW [image width $imgName]
            set imgH [image height $imgName]
        }
        set imgId [$canvas create image $x $y -image $imgName \
            -anchor nw -tags [list $tag]]
        _recordItem $imgId
        _advanceY [expr {$imgH + $fontSize / 2}]
    } else {
        # Fallback-Marker
        set txt "\[image: $alt"
        if {$url ne ""} { append txt " ($url)" }
        append txt "\]"
        lassign [_drawText $x $y $txt [_font italic] [dict get $st contentW] $tag \
            [list -fill "#666"]] _ h
        _advanceY [expr {$h + 4}]
    }

    # Caption (alt) drunter wenn nicht-trivial
    if {$alt ne "" && $imgLoaded} {
        set y [dict get $st y]
        lassign [_drawText $x $y $alt [_font italic] [dict get $st contentW] $tag \
            [list -fill "#666"]] _ h
        _advanceY [expr {$h + 4}]
    }
}

proc docir::canvas::_renderFootnoteSection {node tag} {
    variable st
    set canvas [dict get $st canvas]
    set opts [dict get $st opts]
    set fontSize [dict get $opts fontSize]

    # Trennlinie (kürzer als HR)
    _advanceY [expr {$fontSize / 2}]
    set y [dict get $st y]
    set xL [dict get $st margin]
    set xR [expr {$xL + 100}]
    set lineId [$canvas create line $xL $y $xR $y \
        -fill "#888" -width 1 -tags [list $tag]]
    _recordItem $lineId
    _advanceY [expr {$fontSize / 2 + 4}]

    foreach def [dict get $node content] {
        if {[dict get $def type] ne "footnote_def"} continue
        _renderFootnoteDef $def $tag
    }
}

proc docir::canvas::_renderFootnoteDef {node tag} {
    variable st
    set canvas [dict get $st canvas]
    set opts [dict get $st opts]
    set fontSize [dict get $opts fontSize]

    set m [dict get $node meta]
    set num [expr {[dict exists $m num] ? [dict get $m num] : "?"}]

    set body [_inlinesToText [dict get $node content]]
    set fullText "\[$num\] $body"

    set x [dict get $st margin]
    set y [dict get $st y]
    lassign [_drawText $x $y $fullText [_font normal] [dict get $st contentW] $tag] _ h
    _advanceY [expr {$h + 2}]
}

proc docir::canvas::_renderDiv {node tag} {
    # div ist transparent — children rendern.
    # Tag-Erweiterung mit class-Suffix wäre möglich, aber für 0.5
    # reicht es transparent zu sein.
    foreach child [dict get $node content] {
        _renderBlock $child $tag
    }
}

proc docir::canvas::_renderUnknown {node tag reason} {
    variable st
    set canvas [dict get $st canvas]

    set x [dict get $st margin]
    set y [dict get $st y]
    set txt "\u26A0 $reason"
    lassign [_drawText $x $y $txt [_font italic] [dict get $st contentW] $tag \
        [list -fill "#a00"]] _ h
    _advanceY [expr {$h + 4}]
}

# ============================================================
# Page-break visualisation (pageMode option)
# ============================================================

proc docir::canvas::_drawPageBreak {tag} {
    variable st
    set canvas [dict get $st canvas]
    set y [dict get $st y]
    set xL [dict get $st margin]
    set xR [expr {[dict get $st width] - [dict get $st margin]}]

    set lineId [$canvas create line $xL $y $xR $y \
        -fill "#aaa" -dash {4 4} -tags [list $tag]]
    _recordItem $lineId

    # Label neben der Linie
    set labelId [$canvas create text $xR $y \
        -text " — page break — " -font [_font small] \
        -anchor e -fill "#888" -tags [list $tag]]
    _recordItem $labelId

    _advanceY 12
}
