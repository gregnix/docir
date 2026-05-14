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

    # Style-Konfiguration: fontMode entscheidet was passiert wenn TTF
    # nicht ladbar (strict=throw, warn=stderr+fallback, silent=fallback).
    variable Style
    array set Style {fontMode strict}

    # Font-Mapping (gefuellt von _setupFonts).
    # F(prop)/F(propBold)/F(propOblique)/F(mono) zeigen entweder auf
    # Unicode-TTF (UniSans/UniSansBold/UniSansOblique/UniMono) oder
    # Standard-Fonts (Helvetica/Helvetica-Bold/Helvetica-Oblique/Courier).
    variable F
    array set F {
        prop        Helvetica
        propBold    Helvetica-Bold
        propOblique Helvetica-Oblique
        mono        Courier
    }

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

    namespace export render renderSheets
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
# _fontFor: mapped Token-Type auf pdf4tcl Font-Namen (via F-Array, das
# bei _setupFonts mit Unicode-TTF gefuellt wird falls verfuegbar).
proc docir::tilepdf::_fontFor {type} {
    variable F
    switch $type {
        bold    { return $F(propBold)    }
        italic  { return $F(propOblique) }
        code    { return $F(mono)        }
        default { return $F(prop)        }
    }
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
    variable F
    $pdf setFillColor $COL(header_r) $COL(header_g) $COL(header_b)
    $pdf setFont 16 $F(propBold)
    $pdf setTextPosition $C(col1_x) 30
    $pdf text $title
    if {$subtitle ne ""} {
        $pdf setFont 10 $F(prop)
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
    variable F
    $pdf setFillColor $COL(sec_r) $COL(sec_g) $COL(sec_b)
    $pdf rectangle $col $y $C(col_w) $C(sec_h) -filled 1
    $pdf setFillColor $COL(sec_txt_r) $COL(sec_txt_g) $COL(sec_txt_b)
    $pdf setFont 11 $F(propBold)
    $pdf setTextPosition [expr {$col + 6}] [expr {$y + 14}]
    $pdf text $title
    return [expr {$y + $C(sec_h) + 2}]
}

proc docir::tilepdf::_row {pdf label value y col {mono 0}} {
    variable C
    variable COL
    variable F
    $pdf setFont 8 $F(propBold)
    $pdf setFillColor $COL(lbl_r) $COL(lbl_g) $COL(lbl_b)
    set lx [expr {$col + 4}]
    $pdf drawTextBox $lx [expr {$y+1}] [expr {$C(val_off)-6}] 200 \
        $label -align left -linesvar nlinesL
    if {![info exists nlinesL] || $nlinesL < 1} { set nlinesL 1 }

    set vx [expr {$col + $C(val_off)}]
    set vw [expr {$C(col_w) - $C(val_off) - 4}]
    if {$mono} {
        $pdf setFont 8 $F(mono)
    } else {
        $pdf setFont 8 $F(prop)
    }
    $pdf setFillColor $COL(fg_r) $COL(fg_g) $COL(fg_b)
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
    variable F
    $pdf setFont 8 $F(mono)
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
    variable F
    $pdf setFont 8 $F(prop)
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
    variable F

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
        $pdf setFont 7 $F(propOblique)
        $pdf setFillColor $COL(sub_r) $COL(sub_g) $COL(sub_b)
        $pdf drawTextBox $vx [expr {$newY+1}] $vw 30 $alt -align center -linesvar capL
        if {![info exists capL] || $capL < 1} { set capL 1 }
        set newY [expr {$newY + $capL * 9 + 1}]
    }
    return $newY
}

proc docir::tilepdf::_renderSection {pdf section yVar colVar title subtitle} {
    variable C
    upvar 1 $yVar y
    upvar 1 $colVar col

    set secTitle [dict get $section title]
    set type     [dict get $section type]
    set content  [dict get $section content]

    set y [_section $pdf $secTitle $y $col]

    switch $type {
        table {
            foreach row $content {
                set label [lindex $row 0]
                set value [lindex $row 1]
                set m 0
                if {[llength $row] >= 3} { set m [lindex $row 2] }
                # Pre-measure und Spalte wechseln wenn n\u00f6tig
                set est [expr {max(1, int(ceil([string length $value] / 42.0)))}]
                set rowH [expr {max($C(row_h), $est * 10 + 3)}]
                if {$y + $rowH > $C(y_max)} {
                    set y [_col $pdf [expr {$C(y_max)+1}] col $title $subtitle]
                    set y [_section $pdf "$secTitle (cont.)" $y $col]
                }
                set y [_row $pdf $label $value $y $col $m]
            }
        }
        code {
            foreach line $content {
                set est [expr {max(1, int(ceil([string length $line] / 48.0)))}]
                set lineH [expr {max($C(code_h), $est * 10 + 2)}]
                if {$y + $lineH > $C(y_max)} {
                    set y [_col $pdf [expr {$C(y_max)+1}] col $title $subtitle]
                    set y [_section $pdf "$secTitle (cont.)" $y $col]
                }
                set y [_code $pdf $line $y $col]
            }
        }
        code-intro {
            # Intro mit Helvetica (hint-Style), Code mit Courier
            set intro [dict get $section intro]
            foreach line $intro {
                set est [expr {max(1, int(ceil([string length $line] / 35.0)))}]
                set hintH [expr {$est * 10 + 10}]
                if {$y + $hintH > $C(y_max)} {
                    set y [_col $pdf [expr {$C(y_max)+1}] col $title $subtitle]
                    set y [_section $pdf "$secTitle (cont.)" $y $col]
                }
                set y [_hint $pdf $line $y $col]
            }
            foreach line $content {
                set est [expr {max(1, int(ceil([string length $line] / 48.0)))}]
                set lineH [expr {max($C(code_h), $est * 10 + 2)}]
                if {$y + $lineH > $C(y_max)} {
                    set y [_col $pdf [expr {$C(y_max)+1}] col $title $subtitle]
                    set y [_section $pdf "$secTitle (cont.)" $y $col]
                }
                set y [_code $pdf $line $y $col]
            }
        }
        hint {
            foreach line $content {
                set est [expr {max(1, int(ceil([string length $line] / 35.0)))}]
                set hintH [expr {$est * 10 + 10}]
                if {$y + $hintH > $C(y_max)} {
                    set y [_col $pdf [expr {$C(y_max)+1}] col $title $subtitle]
                    set y [_section $pdf "$secTitle (cont.)" $y $col]
                }
                set y [_hint $pdf $line $y $col]
            }
        }
        list {
            foreach item $content {
                set est [expr {max(1, int(ceil(([string length $item] + 2) / 40.0)))}]
                set itemH [expr {max($C(row_h), $est * 10)}]
                if {$y + $itemH > $C(y_max)} {
                    set y [_col $pdf [expr {$C(y_max)+1}] col $title $subtitle]
                    set y [_section $pdf "$secTitle (cont.)" $y $col]
                }
                set y [_listItem $pdf $item $y $col]
            }
        }
        image {
            # content: Liste von {url alt title}
            foreach img $content {
                lassign $img url alt ttl
                # Bilder schwer vorab zu vermessen -- konservativ: 80px reservieren
                if {$y + 80 > $C(y_max)} {
                    set y [_col $pdf [expr {$C(y_max)+1}] col $title $subtitle]
                    set y [_section $pdf "$secTitle (cont.)" $y $col]
                }
                set y [_image $pdf $url $alt $y $col]
            }
        }
    }
    set y [_sep $pdf $y $col]
    return $y
}

# ---------------------------------------------------------------------------
# Unicode-Font-Pipeline (portiert aus cheatsheet-0.1.tm, 2026-05-13)
# ---------------------------------------------------------------------------
#
# Versucht UniSans/UniSansBold/UniSansOblique/UniMono als CID-Fonts zu
# registrieren. Bei Erfolg werden im F-Array die Slots auf die
# Unicode-Namen umgestellt; bei Misserfolg fallback auf die Standard-
# Helvetica/Courier (kein Unicode, aber immer da).
#
# Mode (Style(fontMode)):
#   strict (default) -- bei Fehler: Exception werfen
#   warn             -- bei Fehler: stderr-Warnung + Fallback
#   silent           -- bei Fehler: still Fallback

proc docir::tilepdf::_setupFonts {pdf} {
    variable F
    variable Style

    # Defaults: Standard-PDF-Fonts (kein Unicode, aber immer verfuegbar).
    array set F {
        prop        Helvetica
        propBold    Helvetica-Bold
        propOblique Helvetica-Oblique
        mono        Courier
    }

    set mode strict
    if {[info exists Style(fontMode)]} { set mode $Style(fontMode) }

    set propCandidates {
        /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
        /usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf
        /usr/share/fonts/TTF/DejaVuSans.ttf
        /Library/Fonts/Arial.ttf
        c:/windows/fonts/arial.ttf
    }
    set boldCandidates {
        /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
        /usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf
        /usr/share/fonts/TTF/DejaVuSans-Bold.ttf
        /Library/Fonts/Arial Bold.ttf
        c:/windows/fonts/arialbd.ttf
    }
    set obliqueCandidates {
        /usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf
        /usr/share/fonts/truetype/liberation/LiberationSans-Italic.ttf
        /usr/share/fonts/TTF/DejaVuSans-Oblique.ttf
    }
    set monoCandidates {
        /usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf
        /usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf
        /usr/share/fonts/TTF/DejaVuSansMono.ttf
        c:/windows/fonts/cour.ttf
    }

    _tryLoadFont $mode prop        UniSans        $propCandidates
    _tryLoadFont $mode propBold    UniSansBold    $boldCandidates
    _tryLoadFont $mode propOblique UniSansOblique $obliqueCandidates
    _tryLoadFont $mode mono        UniMono        $monoCandidates
}

# Versucht ein Font-Mapping zu setzen. pdf4tcl-Pipeline:
#   1. loadBaseTrueTypeFont <BaseName> <ttf-pfad>
#   2. createFontSpecCID    <BaseName> <SpecName>
# Bei Problemen wird je nach $mode geworfen (strict), gewarnt (warn)
# oder still gefallen-back (silent).
proc docir::tilepdf::_tryLoadFont {mode slot fontName candidates} {
    variable F

    set path ""
    foreach p $candidates {
        if {[file exists $p] && [file readable $p]} {
            set path $p
            break
        }
    }
    if {$path eq ""} {
        _fontProblem $mode "kein TTF gefunden fuer slot=$slot (probiert: [join $candidates {, }])"
        return
    }

    set baseName "${fontName}Base"

    if {[catch {::pdf4tcl::loadBaseTrueTypeFont $baseName $path} err]} {
        _fontProblem $mode "loadBaseTrueTypeFont $baseName aus $path schlug fehl: $err"
        return
    }

    if {[catch {::pdf4tcl::createFontSpecCID $baseName $fontName} err]} {
        _fontProblem $mode "createFontSpecCID $baseName $fontName schlug fehl: $err"
        return
    }

    set F($slot) $fontName
}

proc docir::tilepdf::_fontProblem {mode msg} {
    switch -- $mode {
        strict { error "docir::tilepdf font setup (strict): $msg" }
        warn   { puts stderr "docir::tilepdf: WARN -- $msg" }
        silent { }
        default { error "docir::tilepdf font setup: unbekannter mode=$mode (erwartet strict|warn|silent)" }
    }
}

# ---------------------------------------------------------------------------
# Sheet-Rendering
# ---------------------------------------------------------------------------

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
        # Section header sollte mit mindestens etwas Content in dieselbe
        # Spalte; wenn nichtmal das passt, gleich Spalte wechseln.
        # Wenn die ganze Section nicht in eine Spalte passt, kein Problem
        # -- _renderSection splittet jetzt automatisch via upvar y col.
        set minNeed [expr {min($need, $C(sec_h) + 40)}]
        if {$y + $minNeed > $C(y_max)} {
            set y [_col $pdf [expr {$C(y_max)+1}] col $title $subtitle]
        }
        _renderSection $pdf $section y col $title $subtitle
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

    set sheets [_streamToSheets $ir $opts(-title) $opts(-subtitle)]
    if {[llength $sheets] == 0} {
        return -code error "docir::tilepdf: keine Sheets im IR-Stream"
    }

    return [renderSheets $sheets $outFile -theme $opts(-theme)]
}

# renderSheets: alternative Public API -- nimmt eine fertige Sheets-Liste
# (z.B. von docir::csd::toSheets). Bypass des DocIR-Schema-Checks und
# der streamToSheets-Klassifizierung -- der Aufrufer ist schon im
# Sheet-Format.
proc docir::tilepdf::renderSheets {sheets outFile args} {
    array set opts {-theme light}
    foreach {k v} $args {
        if {![info exists opts($k)]} {
            return -code error "docir::tilepdf::renderSheets: unknown option $k"
        }
        set opts($k) $v
    }

    if {[llength $sheets] == 0} {
        return -code error "docir::tilepdf::renderSheets: leere Sheets-Liste"
    }

    _setTheme $opts(-theme)

    set pdf [::pdf4tcl::new %AUTO% -paper a4 -orient true]
    _setupFonts $pdf
    foreach sheet $sheets {
        _renderSheet $pdf $sheet
    }
    $pdf write -file $outFile
    $pdf destroy
    return $outFile
}
