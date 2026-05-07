# docir::tilepdf -- DocIR -> 2-spaltiges Tile-PDF
#
# Adaption von gregs cheatsheet-0.1.tm-Layout-Logik fuer beliebige
# DocIR-Streams. Quelle ist DocIR (typisch aus mdSource), Senke ist
# A4-quer-PDF mit 2-Spalten-Tile-Layout.
#
# Mapping DocIR -> Tile:
#   heading level=1   -> Sheet-Titel (auf Header der Seite)
#   heading level=2+  -> Tile-Section-Titel (startet neue Tile)
#   paragraph         -> hint-artige Tile-Zeile
#   pre               -> code-Tile-Zeilen
#   list              -> list-Tile (Bullet-Items)
#   table             -> table-Tile (label/value)
#
# Layout-Regeln (wie cheatsheet):
#   - Sections sind atomar: passt nicht in aktuelle Spalte -> andere
#   - Passt in keine Spalte -> neue Seite
#   - Section groesser als ganze Seite: wird trotzdem auf neue Seite
#     gezwungen und ueberlaeuft (User soll MD anders strukturieren)
#
# API:
#   docir::tilepdf::render irStream outFile ?options?
#
# Optionen:
#   -title   Sheet-Titel-Override (default: aus erstem doc_header oder H1)
#   -subtitle Subtitel-Override
#
# package require Tcl 8.6-

package provide docir::tilepdf 0.1
package require docir 0.1
package require docir::tilecommon 0.1
package require pdf4tcl

namespace eval docir::tilepdf {

    # Layout-Konstanten — 1:1 aus cheatsheet-0.1.tm (A4 Portrait, 2 Spalten)
    variable C
    array set C {
        col1_x    8
        col2_x    302
        col_w     284
        val_off   85
        y_start   50
        y_max     650
        row_h     12
        code_h    10
        sec_h     20
        sep_h     8
        page_w    595
        page_h    842
        div_x     297
        max_iter  24
    }

    # Themes: light (default) und dark
    variable THEMES
    array set THEMES {
        light:bg          "1.0 1.0 1.0"
        light:fg          "0.0 0.0 0.0"
        light:header      "0.1 0.2 0.5"
        light:sec         "0.88 0.92 0.98"
        light:sec_txt     "0.1 0.2 0.5"
        light:hint        "0.95 0.95 0.88"
        light:lbl         "0.35 0.35 0.35"
        light:sep         "0.80 0.80 0.80"
        light:div         "0.75 0.75 0.75"
        light:subtitle    "0.4 0.4 0.4"

        dark:bg           "0.12 0.12 0.14"
        dark:fg           "0.92 0.92 0.92"
        dark:header       "0.55 0.75 1.0"
        dark:sec          "0.20 0.25 0.35"
        dark:sec_txt      "0.85 0.92 1.0"
        dark:hint         "0.20 0.20 0.18"
        dark:lbl          "0.70 0.70 0.70"
        dark:sep          "0.30 0.30 0.30"
        dark:div          "0.30 0.30 0.30"
        dark:subtitle     "0.65 0.65 0.65"
    }

    # Aktuelle Color-Map (wird bei render gesetzt)
    variable COL
    array set COL {
        header_r   0.1   header_g  0.2   header_b  0.5
        sec_r      0.88  sec_g     0.92  sec_b     0.98
        sec_txt_r  0.1   sec_txt_g 0.2   sec_txt_b 0.5
        hint_r     0.95  hint_g    0.95  hint_b    0.88
        lbl_r      0.35  lbl_g     0.35  lbl_b     0.35
        sep_r      0.80  sep_g     0.80  sep_b     0.80
        div_r      0.75  div_g     0.75  div_b     0.75
        bg_r       1.0   bg_g      1.0   bg_b      1.0
        fg_r       0.0   fg_g      0.0   fg_b      0.0
        sub_r      0.4   sub_g     0.4   sub_b     0.4
    }

    # Aktuelles Theme
    variable currentTheme light

    namespace export render
}

# ---------------------------------------------------------------------------
# Inline-Renderer: DocIR-Inlines -> Plain-Text (PDF-tauglich)
# ---------------------------------------------------------------------------

proc docir::tilepdf::_inlinesToText {inlines} {
    return [docir::tile::inlinesToText $inlines]
}
# ---------------------------------------------------------------------------
# DocIR-Stream -> Sheets-Liste (Sheet = {title, subtitle, sections})
# ---------------------------------------------------------------------------
#
# Aufteilung:
#   - doc_header oder erstes heading level=1 -> Sheet-Titel
#   - Weitere heading level=1 -> neue Sheets
#   - heading level>=2 -> startet neue Section in aktuellem Sheet
#   - Block ohne heading davor -> Section "Übersicht" (nur wenn Inhalt da)

proc docir::tilepdf::_streamToSheets {ir titleOverride subtitleOverride} {
    return [docir::tile::streamToSheets $ir $titleOverride $subtitleOverride]
}
# Section-Inhalt analysieren und in {title, type, content}-Form packen.
# Wenn die Section nur einen einzigen Block-Typ enthaelt, nutzt Tile
# den passenden Typ. Bei gemischten Inhalten -> "hint"-artiger Mix.
proc docir::tilepdf::_packSection {title content} {
    return [docir::tile::packSection $title $content]
}
# ---------------------------------------------------------------------------
# Theme-Aktivierung
# ---------------------------------------------------------------------------

# _setTheme: aktiviert ein Theme (light|dark) — befuellt COL.
proc docir::tilepdf::_setTheme {theme} {
    variable THEMES
    variable COL
    variable currentTheme

    if {$theme ni {light dark}} {
        return -code error "docir::tilepdf: unknown theme '$theme' (use light or dark)"
    }
    set currentTheme $theme

    foreach {key short} {
        bg          bg
        fg          fg
        header      header
        sec         sec
        sec_txt     sec_txt
        hint        hint
        lbl         lbl
        sep         sep
        div         div
        subtitle    sub
    } {
        lassign $THEMES(${theme}:${key}) r g b
        set COL(${short}_r) $r
        set COL(${short}_g) $g
        set COL(${short}_b) $b
    }
}

# ---------------------------------------------------------------------------
# Mini-Tokenizer + Mixed-Font-Renderer fuer Inline-Markup
# ---------------------------------------------------------------------------
#
# Erkennt **bold**, *italic*, `code` in einem Text und rendert die
# Stuecke mit den passenden Fonts. Word-Wrap auf Spaltenbreite.

# _tokenize: parst pseudo-markdown in {type text}-Tokens
proc docir::tilepdf::_tokenize {text} {
    return [docir::tile::tokenize $text]
}
# _fontFor: mapped Token-Type auf pdf4tcl Font-Namen
proc docir::tilepdf::_fontFor {type} {
    return [docir::tile::fontFor $type]
}
# _drawRichLine: rendert eine Zeile mit Mixed-Fonts, mit Word-Wrap.
# Returns y nach der gerenderten Zeile(n).
proc docir::tilepdf::_drawRichLine {pdf text x y maxWidth fontSize lineHeight} {
    variable COL
    set tokens [_tokenize $text]
    set curX $x
    set curY $y
    set lineUsed 0

    foreach token $tokens {
        lassign $token tType tText
        set font [_fontFor $tType]

        # Token in Worte splitten, pro Wort prüfen ob es noch passt
        # Wir erhalten Whitespace zwischen Wörtern explizit.
        set parts [split $tText " "]
        set partIdx 0
        foreach part $parts {
            if {$partIdx > 0} {
                # Vorheriges Whitespace rendern
                $pdf setFont $fontSize $font
                $pdf setFillColor $COL(fg_r) $COL(fg_g) $COL(fg_b)
                set spaceW [$pdf getStringWidth " "]
                if {$curX + $spaceW > $x + $maxWidth} {
                    incr curY $lineHeight
                    set curX $x
                    set lineUsed 1
                } else {
                    $pdf setTextPosition $curX [expr {$curY + $fontSize}]
                    $pdf text " "
                    set curX [expr {$curX + $spaceW}]
                }
            }
            incr partIdx
            if {$part eq ""} continue

            $pdf setFont $fontSize $font
            $pdf setFillColor $COL(fg_r) $COL(fg_g) $COL(fg_b)
            set partW [$pdf getStringWidth $part]

            # Wrap wenn Word nicht passt
            if {$curX + $partW > $x + $maxWidth && $curX > $x} {
                incr curY $lineHeight
                set curX $x
                set lineUsed 1
            }
            $pdf setTextPosition $curX [expr {$curY + $fontSize}]
            $pdf text $part
            set curX [expr {$curX + $partW}]
            set lineUsed 1
        }
    }
    # Returns y nach Zeilenwechsel (Höhe der Zeilen-Block + 2px Spacing)
    if {$lineUsed} {
        return [expr {$curY + $lineHeight + 1}]
    }
    return $curY
}

proc docir::tilepdf::_header {pdf title subtitle} {
    variable C
    variable COL
    $pdf setFillColor $COL(header_r) $COL(header_g) $COL(header_b)
    $pdf setFont 16 Helvetica-Bold
    $pdf setTextPosition $C(col1_x) 30
    $pdf text $title
    if {$subtitle ne ""} {
        $pdf setFont 10 Helvetica
        $pdf setFillColor $COL(sub_r) $COL(sub_g) $COL(sub_b)
        $pdf setTextPosition $C(col1_x) 44
        $pdf text $subtitle
    }
}

proc docir::tilepdf::_divider {pdf} {
    variable C
    variable COL
    $pdf setStrokeColor $COL(div_r) $COL(div_g) $COL(div_b)
    $pdf setLineStyle 0.5
    $pdf line $C(div_x) $C(y_start) $C(div_x) $C(y_max)
}

proc docir::tilepdf::_section {pdf title y col} {
    variable C
    variable COL
    $pdf setFillColor $COL(sec_r) $COL(sec_g) $COL(sec_b)
    $pdf rectangle $col $y $C(col_w) $C(sec_h) -filled 1
    $pdf setFillColor $COL(sec_txt_r) $COL(sec_txt_g) $COL(sec_txt_b)
    $pdf setFont 11 Helvetica-Bold
    $pdf setTextPosition [expr {$col + 6}] [expr {$y + 14}]
    $pdf text $title
    return [expr {$y + $C(sec_h) + 2}]
}

proc docir::tilepdf::_row {pdf label value y col {mono 0}} {
    variable C
    variable COL
    $pdf setFont 8 Helvetica-Bold
    $pdf setFillColor $COL(lbl_r) $COL(lbl_g) $COL(lbl_b)
    set lx [expr {$col + 4}]
    $pdf drawTextBox $lx [expr {$y+1}] [expr {$C(val_off)-6}] 200 \
        $label -align left -linesvar nlinesL
    if {![info exists nlinesL] || $nlinesL < 1} { set nlinesL 1 }

    set vx [expr {$col + $C(val_off)}]
    set vw [expr {$C(col_w) - $C(val_off) - 4}]
    if {$mono} {
        $pdf setFont 8 Courier
    } else {
        $pdf setFont 8 Helvetica
    }
    variable COL; $pdf setFillColor $COL(fg_r) $COL(fg_g) $COL(fg_b)
    $pdf drawTextBox $vx [expr {$y+1}] $vw 200 \
        $value -align left -linesvar nlinesV
    if {![info exists nlinesV] || $nlinesV < 1} { set nlinesV 1 }

    set lines [expr {max($nlinesL, $nlinesV)}]
    set h [expr {max($C(row_h), $lines * 10 + 1)}]
    return [expr {$y + $h}]
}

proc docir::tilepdf::_code {pdf line y col} {
    variable C
    variable COL
    $pdf setFont 8 Courier
    $pdf setFillColor $COL(fg_r) $COL(fg_g) $COL(fg_b)
    set vx [expr {$col + 4}]
    set vw [expr {$C(col_w) - 8}]
    $pdf drawTextBox $vx [expr {$y+1}] $vw 200 \
        $line -align left -linesvar nlines
    if {![info exists nlines] || $nlines < 1} { set nlines 1 }
    set h [expr {max($C(code_h), $nlines * 10 + 1)}]
    return [expr {$y + $h}]
}

proc docir::tilepdf::_hint {pdf text y col} {
    variable C
    set vx [expr {$col + 4}]
    set vw [expr {$C(col_w) - 8}]
    return [_drawRichLine $pdf $text $vx $y $vw 8 10]
}

proc docir::tilepdf::_listItem {pdf text y col} {
    variable C
    variable COL
    $pdf setFont 8 Helvetica
    $pdf setFillColor $COL(fg_r) $COL(fg_g) $COL(fg_b)
    set vx [expr {$col + 8}]
    set vw [expr {$C(col_w) - 12}]
    $pdf drawTextBox $vx [expr {$y+1}] $vw 200 \
        "• $text" -align left -linesvar nlines
    if {![info exists nlines] || $nlines < 1} { set nlines 1 }
    set h [expr {max($C(row_h), $nlines * 10 + 1)}]
    return [expr {$y + $h}]
}

proc docir::tilepdf::_sep {pdf y col} {
    variable C
    variable COL
    $pdf setStrokeColor $COL(sep_r) $COL(sep_g) $COL(sep_b)
    $pdf setLineStyle 0.3
    $pdf line [expr {$col+4}] [expr {$y+3}] \
        [expr {$col+$C(col_w)-4}] [expr {$y+3}]
    return [expr {$y + $C(sep_h)}]
}

# Spaltenwechsel: Wenn aktuelle Spalte voll oder ueberhaupt benutzt,
# wechsle zur anderen Spalte. Wenn beide voll waren -> neue Seite.
proc docir::tilepdf::_col {pdf yIn colVar title subtitle} {
    variable C
    upvar $colVar col

    if {$yIn > $C(y_max)} {
        if {$col == $C(col1_x)} {
            # Wechsel zu Spalte 2
            set col $C(col2_x)
            return $C(y_start)
        } else {
            # Beide Spalten voll -> neue Seite
            $pdf endPage
            $pdf startPage
            _header $pdf $title $subtitle
            _divider $pdf
            set col $C(col1_x)
            return $C(y_start)
        }
    }
    return $yIn
}

# Hoehe einer Section schaetzen (fuer atomare Platzierung)
proc docir::tilepdf::_sectionHeight {section} {
    variable C
    set type [dict get $section type]
    set content [dict get $section content]
    set h $C(sec_h)
    incr h 2
    switch $type {
        table   { incr h [expr {[llength $content] * $C(row_h)}] }
        code    { incr h [expr {[llength $content] * $C(code_h)}] }
        code-intro {
            set intro [expr {[dict exists $section intro] ? [dict get $section intro] : {}}]
            incr h [expr {[llength $intro] * $C(row_h)}]
            incr h [expr {[llength $content] * $C(code_h)}]
        }
        hint    { incr h [expr {[llength $content] * $C(row_h)}] }
        list    { incr h [expr {[llength $content] * $C(row_h)}] }
        image   {
            # Schaetzung: pro Bild ~120pt (skaliert auf col-width).
            # Echte Hoehe haengt von Bild-Dim ab.
            incr h [expr {[llength $content] * 120}]
        }
    }
    incr h $C(sep_h)
    return $h
}

proc docir::tilepdf::_image {pdf url alt y col} {
    variable C
    variable COL

    set vx [expr {$col + 4}]
    set vw [expr {$C(col_w) - 8}]

    # URL/Pfad: nur lokale Files supported. URL -> Fallback Text-Marker.
    set isLocal 1
    if {[regexp {^https?://} $url]} { set isLocal 0 }
    if {[regexp {^file://} $url]} {
        set url [string range $url 7 end]
    }

    if {!$isLocal || ![file exists $url]} {
        # Fallback: als Hint-Text "[image: alt]"
        return [_hint $pdf "\[image: $alt — $url\]" $y $col]
    }

    # Image laden + Groesse abfragen
    if {[catch {$pdf addImage $url} imgId]} {
        return [_hint $pdf "\[image error: $alt\]" $y $col]
    }
    set imgW [$pdf getImageWidth $imgId]
    set imgH [$pdf getImageHeight $imgId]

    # Skalieren auf max-width = vw, Aspekt erhalten
    set scale 1.0
    if {$imgW > $vw} {
        set scale [expr {double($vw) / $imgW}]
    }
    set drawW [expr {$imgW * $scale}]
    set drawH [expr {$imgH * $scale}]

    # Center horizontal
    set drawX [expr {$vx + ($vw - $drawW) / 2}]
    # Image rendert von y oben nach y+drawH unten
    $pdf putImage $imgId $drawX $y -width $drawW -height $drawH

    # Alt-Text als kleine Caption darunter (optional, nur wenn vorhanden)
    set newY [expr {$y + $drawH + 2}]
    if {$alt ne ""} {
        $pdf setFont 7 Helvetica-Oblique
        $pdf setFillColor $COL(sub_r) $COL(sub_g) $COL(sub_b)
        $pdf drawTextBox $vx [expr {$newY+1}] $vw 30 $alt -align center -linesvar capL
        if {![info exists capL] || $capL < 1} { set capL 1 }
        set newY [expr {$newY + $capL * 9 + 1}]
    }
    return $newY
}

proc docir::tilepdf::_renderSection {pdf section y col} {
    set title   [dict get $section title]
    set type    [dict get $section type]
    set content [dict get $section content]

    set y [_section $pdf $title $y $col]

    switch $type {
        table {
            foreach row $content {
                set label [lindex $row 0]
                set value [lindex $row 1]
                set y [_row $pdf $label $value $y $col 0]
            }
        }
        code {
            foreach line $content {
                set y [_code $pdf $line $y $col]
            }
        }
        code-intro {
            # Intro mit Helvetica (hint-Style), Code mit Courier
            set intro [dict get $section intro]
            foreach line $intro {
                set y [_hint $pdf $line $y $col]
            }
            foreach line $content {
                set y [_code $pdf $line $y $col]
            }
        }
        hint {
            foreach line $content {
                set y [_hint $pdf $line $y $col]
            }
        }
        list {
            foreach item $content {
                set y [_listItem $pdf $item $y $col]
            }
        }
        image {
            # content: Liste von {url alt title}
            foreach img $content {
                lassign $img url alt ttl
                set y [_image $pdf $url $alt $y $col]
            }
        }
    }
    set y [_sep $pdf $y $col]
    return $y
}

# Ein Sheet (= 1 Page mit Titel) rendern
proc docir::tilepdf::_renderSheet {pdf sheet} {
    variable C
    variable COL
    set title    [dict get $sheet title]
    set subtitle [dict get $sheet subtitle]
    set sections [dict get $sheet sections]

    $pdf startPage

    # Background fuellen wenn Theme nicht weiss
    if {$COL(bg_r) < 0.99 || $COL(bg_g) < 0.99 || $COL(bg_b) < 0.99} {
        $pdf setFillColor $COL(bg_r) $COL(bg_g) $COL(bg_b)
        $pdf rectangle 0 0 $C(page_w) $C(page_h) -filled 1
    }

    _header $pdf $title $subtitle
    _divider $pdf

    set y   $C(y_start)
    set col $C(col1_x)

    foreach section $sections {
        set need [_sectionHeight $section]
        # Wenn die Section nicht in die aktuelle Spalte passt -> wechsel
        for {set i 0} {$i < $C(max_iter) && $y + $need > $C(y_max)} {incr i} {
            set y [_col $pdf [expr {$C(y_max)+1}] col $title $subtitle]
        }
        set y [_renderSection $pdf $section $y $col]
    }

    $pdf endPage
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# render: konvertiert DocIR zu Tile-PDF
proc docir::tilepdf::render {ir outFile args} {
    array set opts {-title "" -subtitle "" -theme light}
    foreach {k v} $args {
        if {![info exists opts($k)]} {
            return -code error "docir::tilepdf::render: unknown option $k"
        }
        set opts($k) $v
    }

    # IR validieren (Standard-Schema-Check)
    set err [::docir::checkSchemaVersion $ir]
    if {$err ne ""} {
        return -code error "docir::tilepdf: $err"
    }

    # Theme aktivieren (befuellt COL)
    _setTheme $opts(-theme)

    set sheets [_streamToSheets $ir $opts(-title) $opts(-subtitle)]
    if {[llength $sheets] == 0} {
        return -code error "docir::tilepdf: keine Sheets im IR-Stream"
    }

    set pdf [::pdf4tcl::new %AUTO% -paper a4 -orient true]
    foreach sheet $sheets {
        _renderSheet $pdf $sheet
    }
    $pdf write -file $outFile
    $pdf destroy
    return $outFile
}
