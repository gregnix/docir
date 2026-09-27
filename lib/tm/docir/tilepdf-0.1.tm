# docir::tilepdf -- DocIR -> 2-spaltiges Tile-PDF
#
# Adaptation of greg's cheatsheet-0.1.tm layout logic for arbitrary
# DocIR streams. Source is DocIR (typically from mdSource), sink is
# A4 landscape PDF with a 2-column tile layout.
#
# Mapping DocIR -> Tile:
#   heading level=1   -> sheet title (in the page header)
#   heading level=2+  -> Tile-Section-Titel (startet neue Tile)
#   paragraph         -> hint-like tile row
#   pre               -> code-Tile-Zeilen
#   list              -> list-Tile (Bullet-Items)
#   table             -> table-Tile (label/value)
#
# Layout rules (like cheatsheet):
#   - sections are atomic: does not fit in the current column -> the other
#   - fits in no column -> new page
#   - section larger than a whole page: is forced onto a new page
#     anyway and overflows (the user should structure the MD differently)
#
# API:
#   docir::tilepdf::render irStream outFile ?options?
#
# Optionen:
#   -title    sheet title override (default: from the first doc_header or H1)
#   -subtitle Subtitel-Override
#   -theme    light | dark
#   -lang     BCP-47 (default de-DE)
#   -tagged   1|0 (default 1)
#
# package require Tcl 8.6-

package provide docir::tilepdf 0.1
package require docir 0.1
package require docir::tilecommon 0.1
package require pdf4tcl

namespace eval docir::tilepdf {

    # Style configuration: fontMode decides what happens when a TTF
    # is not loadable (strict=throw, warn=stderr+fallback, silent=fallback).
    # Default warn -- a missing Unicode font should not block
    # rendering. The cheatsheets workflow sets strict when Unicode fonts
    # are strictly required.
    variable Style
    array set Style {fontMode warn}

    # Font-Mapping (gefuellt von _setupFonts).
    # F(prop)/F(propBold)/F(propOblique)/F(mono) zeigen entweder auf
    # Unicode TTF (UniSans/UniSansBold/UniSansOblique/UniMono) or
    # Standard-Fonts (Helvetica/Helvetica-Bold/Helvetica-Oblique/Courier).
    variable F
    array set F {
        prop        Helvetica
        propBold    Helvetica-Bold
        propOblique Helvetica-Oblique
        mono        Courier
    }

    # Layout constants — 1:1 from cheatsheet-0.1.tm (A4 portrait, 2 columns)
    variable C
    array set C {
        col1_x    8
        col2_x    302
        col_w     284
        val_off   85
        y_start   50
        y_max     822
        row_h     12
        code_h    10
        sec_h     20
        sep_h     8
        page_w    595
        page_h    842
        div_x     297
    }

    # Themes: light (default) and dark
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

    # current color map (set during render)
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

proc docir::tilepdf::_dictDef {d k {def ""}} {
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}

proc docir::tilepdf::_inlinesToText {inlines} {
    return [docir::tile::inlinesToText $inlines]
}
# ---------------------------------------------------------------------------
# DocIR stream -> sheets list (sheet = {title, subtitle, sections})
# ---------------------------------------------------------------------------
#
# Aufteilung:
#   - doc_header or the first heading level=1 -> sheet title
#   - Weitere heading level=1 -> neue Sheets
#   - heading level>=2 -> startet neue Section in aktuellem Sheet
#   - block without a preceding heading -> section "Übersicht" (only if there is content)

proc docir::tilepdf::_streamToSheets {ir titleOverride subtitleOverride} {
    return [docir::tile::streamToSheets $ir $titleOverride $subtitleOverride]
}
# Analyze the section content and pack it into {title, type, content} form.
# If the section contains only a single block type, Tile uses
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
# Mini tokenizer + mixed-font renderer for inline markup
# ---------------------------------------------------------------------------
#
# Recognizes **bold**, *italic*, `code` in a text and renders the
# pieces with the matching fonts. Word wrap at the column width.

# _tokenize: parst pseudo-markdown in {type text}-Tokens
proc docir::tilepdf::_tokenize {text} {
    return [docir::tile::tokenize $text]
}
# _fontFor: maps a token type to a pdf4tcl font name (via the F array, which
# is filled with Unicode TTF during _setupFonts if available).
proc docir::tilepdf::_fontFor {type} {
    variable F
    switch $type {
        bold    { return $F(propBold)    }
        italic  { return $F(propOblique) }
        code    { return $F(mono)        }
        default { return $F(prop)        }
    }
}

proc docir::tilepdf::_text {pdf txt args} {
    if {[llength [info commands ::pdf4tcllib::unicode::safeText]]} {
        ::pdf4tcllib::unicode::safeText $pdf $txt {*}$args
        return
    }
    $pdf text $txt {*}$args
}

proc docir::tilepdf::_box {pdf x y w h txt args} {
    if {[llength [info commands ::pdf4tcllib::unicode::sanitize]]} {
        set txt [::pdf4tcllib::unicode::sanitize $txt]
    }
    $pdf drawTextBox $x $y $w $h $txt {*}$args
}

proc docir::tilepdf::_withTag {pdf type body} {
    if {[llength [info commands ::pdf4tcllib::tag::begin]]} {
        ::pdf4tcllib::tag::begin $pdf $type
        set rc [catch {uplevel 1 $body} err opts]
        ::pdf4tcllib::tag::end $pdf
        if {$rc} { return -options $opts $err }
        return
    }
    set ok [expr {![catch {$pdf tagBegin $type}]}]
    set rc [catch {uplevel 1 $body} err opts]
    if {$ok} { catch {$pdf tagEnd} }
    if {$rc} { return -options $opts $err }
}

proc docir::tilepdf::_withArtifact {pdf body} {
    if {[llength [info commands ::pdf4tcllib::tag::artifact]]} {
        ::pdf4tcllib::tag::artifact $pdf
        set rc [catch {uplevel 1 $body} err opts]
        ::pdf4tcllib::tag::artifactEnd $pdf
        if {$rc} { return -options $opts $err }
        return
    }
    set ok [expr {![catch {$pdf tagArtifact}]}]
    set rc [catch {uplevel 1 $body} err opts]
    if {$ok} { catch {$pdf tagArtifactEnd} }
    if {$rc} { return -options $opts $err }
}
# _drawRichLine: renders a line with mixed fonts, with word wrap.
# Returns y after the rendered line(s).
proc docir::tilepdf::_drawRichLine {pdf text x y maxWidth fontSize lineHeight} {
    variable COL
    set tokens [_tokenize $text]
    set curX $x
    set curY $y
    set lineUsed 0

    foreach token $tokens {
        lassign $token tType tText
        set font [_fontFor $tType]

        # split the token into words, check per word whether it still fits
        # We preserve whitespace between words explicitly.
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
                    _text $pdf " "
                    set curX [expr {$curX + $spaceW}]
                }
            }
            incr partIdx
            if {$part eq ""} continue

            $pdf setFont $fontSize $font
            $pdf setFillColor $COL(fg_r) $COL(fg_g) $COL(fg_b)
            set partW [$pdf getStringWidth $part]

            # wrap if the word does not fit
            if {$curX + $partW > $x + $maxWidth && $curX > $x} {
                incr curY $lineHeight
                set curX $x
                set lineUsed 1
            }
            $pdf setTextPosition $curX [expr {$curY + $fontSize}]
            _text $pdf $part
            set curX [expr {$curX + $partW}]
            set lineUsed 1
        }
    }
    # Returns y after the line break (height of the line block + 2px spacing)
    if {$lineUsed} {
        return [expr {$curY + $lineHeight + 1}]
    }
    return $curY
}

proc docir::tilepdf::_header {pdf title subtitle} {
    variable C
    variable COL
    variable F
    _withTag $pdf H1 {
        $pdf setFillColor $COL(header_r) $COL(header_g) $COL(header_b)
        $pdf setFont 16 $F(propBold)
        $pdf setTextPosition $C(col1_x) 30
        _text $pdf $title
    }
    if {$subtitle ne ""} {
        _withTag $pdf P {
            $pdf setFont 10 $F(prop)
            $pdf setFillColor $COL(sub_r) $COL(sub_g) $COL(sub_b)
            $pdf setTextPosition $C(col1_x) 44
            _text $pdf $subtitle
        }
    }
}

proc docir::tilepdf::_divider {pdf} {
    variable C
    variable COL
    _withArtifact $pdf {
        $pdf setStrokeColor $COL(div_r) $COL(div_g) $COL(div_b)
        $pdf setLineStyle 0.5
        $pdf line $C(div_x) $C(y_start) $C(div_x) $C(y_max)
    }
}

proc docir::tilepdf::_section {pdf title y col} {
    variable C
    variable COL
    variable F
    _withArtifact $pdf {
        $pdf setFillColor $COL(sec_r) $COL(sec_g) $COL(sec_b)
        $pdf rectangle $col $y $C(col_w) $C(sec_h) -filled 1
    }
    _withTag $pdf H2 {
        $pdf setFillColor $COL(sec_txt_r) $COL(sec_txt_g) $COL(sec_txt_b)
        $pdf setFont 11 $F(propBold)
        $pdf setTextPosition [expr {$col + 6}] [expr {$y + 14}]
        _text $pdf $title
    }
    return [expr {$y + $C(sec_h) + 2}]
}

# Wrap at spaces, then at the last hyphen or slash that still fits.
# An unbreakable token (German compound, command name) stays on one line
# unless splitLong is set — then it may break by character as a last resort.
# Font must already be set on $pdf.
proc docir::tilepdf::_wrapToWidth {pdf text width {splitLong 0}} {
    if {$text eq ""} { return [list ""] }
    set lines {}
    foreach paragraphLine [split $text "\n"] {
        if {$paragraphLine eq ""} {
            lappend lines ""
            continue
        }
        set words [split $paragraphLine " "]
        set current ""
        foreach w $words {
            set candidate [expr {$current eq "" ? $w : "$current $w"}]
            if {[$pdf getStringWidth $candidate] <= $width} {
                set current $candidate
                continue
            }
            if {$current ne ""} {
                lappend lines $current
                set current ""
            }
            set rest $w
            while {$rest ne ""} {
                set n [_prefixFit $pdf $rest $width $splitLong]
                if {$n >= [string length $rest]} {
                    set current $rest
                    set rest ""
                    break
                }
                if {$n < 1} { set n 1 }
                lappend lines [string range $rest 0 [expr {$n - 1}]]
                set rest [string range $rest $n end]
            }
        }
        if {$current ne ""} { lappend lines $current }
    }
    if {[llength $lines] == 0} { set lines [list ""] }
    return $lines
}

proc docir::tilepdf::_prefixFit {pdf text width splitLong} {
    set n [string length $text]
    if {$n == 0} { return 0 }
    if {[$pdf getStringWidth $text] <= $width} { return $n }
    set best 0
    for {set i 0} {$i < $n} {incr i} {
        set ch [string index $text $i]
        if {$ch eq "-" || $ch eq "/"} {
            set pref [string range $text 0 $i]
            if {[$pdf getStringWidth $pref] <= $width} {
                set best [expr {$i + 1}]
            }
        }
    }
    if {$best > 0} { return $best }
    if {!$splitLong} { return $n }
    set fit 1
    for {set i 1} {$i <= $n} {incr i} {
        set pref [string range $text 0 [expr {$i - 1}]]
        if {[$pdf getStringWidth $pref] <= $width} {
            set fit $i
        } else {
            break
        }
    }
    return $fit
}

proc docir::tilepdf::_tokenWidth {pdf text} {
    set maxW 0.0
    foreach word [split $text " "] {
        if {$word eq ""} continue
        set start 0
        set n [string length $word]
        for {set i 0} {$i < $n} {incr i} {
            set ch [string index $word $i]
            if {$ch eq "-" || $ch eq "/"} {
                set chunk [string range $word $start $i]
                set w [$pdf getStringWidth $chunk]
                if {$w > $maxW} { set maxW $w }
                set start [expr {$i + 1}]
            }
        }
        set chunk [string range $word $start end]
        if {$chunk ne ""} {
            set w [$pdf getStringWidth $chunk]
            if {$w > $maxW} { set maxW $w }
        }
    }
    return $maxW
}

# Label column grows to the longest label that still leaves 100pt for
# values. If a label is wider than that, it wraps at spaces/hyphens.
proc docir::tilepdf::_tableValOff {pdf labels} {
    variable C
    variable F
    $pdf setFont 8 $F(propBold)
    set maxOff [expr {int($C(col_w) - 100)}]
    set maxW 0.0
    foreach label $labels {
        set full [$pdf getStringWidth $label]
        set tok  [_tokenWidth $pdf $label]
        set w $full
        if {$w > $maxOff} { set w $tok }
        if {$w > $maxW} { set maxW $w }
    }
    set off [expr {int(ceil($maxW + 10))}]
    if {$off < $C(val_off)} { set off $C(val_off) }
    if {$off > $maxOff} { set off $maxOff }
    return $off
}

proc docir::tilepdf::_rowHeight {pdf label value {mono 0} {valOff ""}} {
    variable C
    variable F
    if {$valOff eq ""} { set valOff $C(val_off) }
    set lw [expr {$valOff - 6}]
    set vw [expr {$C(col_w) - $valOff - 4}]
    $pdf setFont 8 $F(propBold)
    set nL [llength [_wrapToWidth $pdf $label $lw]]
    if {$mono} {
        $pdf setFont 8 $F(mono)
    } else {
        $pdf setFont 8 $F(prop)
    }
    set nV [llength [_wrapToWidth $pdf $value $vw 1]]
    set n [expr {max($nL, $nV, 1)}]
    return [expr {max($C(row_h), $n * 10 + 1)}]
}

proc docir::tilepdf::_row {pdf label value y col {mono 0} {valOff ""}} {
    variable C
    variable COL
    variable F
    if {$valOff eq ""} { set valOff $C(val_off) }
    set fs 8
    set lh 10
    set lx [expr {$col + 4}]
    set lw [expr {$valOff - 6}]
    set vx [expr {$col + $valOff}]
    set vw [expr {$C(col_w) - $valOff - 4}]

    $pdf setFont $fs $F(propBold)
    $pdf setFillColor $COL(lbl_r) $COL(lbl_g) $COL(lbl_b)
    set labelLines [_wrapToWidth $pdf $label $lw]
    set ly $y
    foreach line $labelLines {
        $pdf setTextPosition $lx [expr {$ly + $fs}]
        _text $pdf $line
        incr ly $lh
    }

    if {$mono} {
        $pdf setFont $fs $F(mono)
    } else {
        $pdf setFont $fs $F(prop)
    }
    $pdf setFillColor $COL(fg_r) $COL(fg_g) $COL(fg_b)
    set valueLines [_wrapToWidth $pdf $value $vw 1]
    set vy $y
    foreach line $valueLines {
        $pdf setTextPosition $vx [expr {$vy + $fs}]
        _text $pdf $line
        incr vy $lh
    }

    set n [expr {max([llength $labelLines], [llength $valueLines], 1)}]
    set h [expr {max($C(row_h), $n * $lh + 1)}]
    return [expr {$y + $h}]
}

proc docir::tilepdf::_codeHeight {pdf line} {
    variable C
    variable F
    set vw [expr {$C(col_w) - 8}]
    $pdf setFont 8 $F(mono)
    set n [llength [_wrapToWidth $pdf $line $vw 1]]
    if {$n < 1} { set n 1 }
    return [expr {max($C(code_h), $n * 10 + 1)}]
}

proc docir::tilepdf::_code {pdf line y col} {
    variable C
    variable COL
    variable F
    set fs 8
    set lh 10
    $pdf setFont $fs $F(mono)
    $pdf setFillColor $COL(fg_r) $COL(fg_g) $COL(fg_b)
    set vx [expr {$col + 4}]
    set vw [expr {$C(col_w) - 8}]
    set lines [_wrapToWidth $pdf $line $vw 1]
    set ly $y
    foreach ln $lines {
        $pdf setTextPosition $vx [expr {$ly + $fs}]
        _text $pdf $ln
        incr ly $lh
    }
    set n [llength $lines]
    if {$n < 1} { set n 1 }
    set h [expr {max($C(code_h), $n * $lh + 1)}]
    return [expr {$y + $h}]
}

proc docir::tilepdf::_hint {pdf text y col} {
    variable C
    set vx [expr {$col + 4}]
    set vw [expr {$C(col_w) - 8}]
    return [_drawRichLine $pdf $text $vx $y $vw 8 10]
}

proc docir::tilepdf::_listHeight {pdf text} {
    variable C
    variable F
    set vw [expr {$C(col_w) - 12}]
    $pdf setFont 8 $F(prop)
    set n [llength [_wrapToWidth $pdf "• $text" $vw]]
    if {$n < 1} { set n 1 }
    return [expr {max($C(row_h), $n * 10 + 1)}]
}

proc docir::tilepdf::_listItem {pdf text y col} {
    variable C
    variable COL
    variable F
    set fs 8
    set lh 10
    $pdf setFont $fs $F(prop)
    $pdf setFillColor $COL(fg_r) $COL(fg_g) $COL(fg_b)
    set vx [expr {$col + 8}]
    set vw [expr {$C(col_w) - 12}]
    set lines [_wrapToWidth $pdf "• $text" $vw]
    set ly $y
    foreach ln $lines {
        $pdf setTextPosition $vx [expr {$ly + $fs}]
        _text $pdf $ln
        incr ly $lh
    }
    set n [llength $lines]
    if {$n < 1} { set n 1 }
    set h [expr {max($C(row_h), $n * $lh + 1)}]
    return [expr {$y + $h}]
}

proc docir::tilepdf::_sep {pdf y col} {
    variable C
    variable COL
    _withArtifact $pdf {
        $pdf setStrokeColor $COL(sep_r) $COL(sep_g) $COL(sep_b)
        $pdf setLineStyle 0.3
        $pdf line [expr {$col+4}] [expr {$y+3}] \
            [expr {$col+$C(col_w)-4}] [expr {$y+3}]
    }
    return [expr {$y + $C(sep_h)}]
}

# Column switch: if the current column is full or used at all,
# switch to the other column. If both were full -> new page.
proc docir::tilepdf::_col {pdf yIn colVar title subtitle} {
    variable C
    upvar $colVar col

    if {$yIn > $C(y_max)} {
        if {$col == $C(col1_x)} {
            # switch to column 2
            set col $C(col2_x)
            return $C(y_start)
        } else {
            # both columns full -> new page
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

# Estimate the height of a section (for atomic placement)
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
            set intro [_dictDef $section intro {}]
            incr h [expr {[llength $intro] * $C(row_h)}]
            incr h [expr {[llength $content] * $C(code_h)}]
        }
        hint    { incr h [expr {[llength $content] * $C(row_h)}] }
        list    { incr h [expr {[llength $content] * $C(row_h)}] }
        image   {
            # Schaetzung: pro Bild ~120pt (skaliert auf col-width).
            # real height depends on the image dimensions.
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

    # URL/path: only local files supported. URL -> fallback text marker.
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

    # alt text as a small caption below (optional, only if present)
    set newY [expr {$y + $drawH + 2}]
    if {$alt ne ""} {
        $pdf setFont 7 $F(propOblique)
        $pdf setFillColor $COL(sub_r) $COL(sub_g) $COL(sub_b)
        _box $pdf $vx [expr {$newY+1}] $vw 30 $alt -align center -linesvar capL
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
            set labels {}
            foreach row $content { lappend labels [lindex $row 0] }
            set valOff [_tableValOff $pdf $labels]
            foreach row $content {
                set label [lindex $row 0]
                set value [lindex $row 1]
                set m 0
                if {[llength $row] >= 3} { set m [lindex $row 2] }
                set rowH [_rowHeight $pdf $label $value $m $valOff]
                if {$y + $rowH > $C(y_max)} {
                    set y [_col $pdf [expr {$C(y_max)+1}] col $title $subtitle]
                    set y [_section $pdf "$secTitle (cont.)" $y $col]
                }
                set y [_row $pdf $label $value $y $col $m $valOff]
            }
        }
        code {
            foreach line $content {
                set lineH [_codeHeight $pdf $line]
                if {$y + $lineH > $C(y_max)} {
                    set y [_col $pdf [expr {$C(y_max)+1}] col $title $subtitle]
                    set y [_section $pdf "$secTitle (cont.)" $y $col]
                }
                set y [_code $pdf $line $y $col]
            }
        }
        code-intro {
            # intro with Helvetica (hint style), code with Courier
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
                set lineH [_codeHeight $pdf $line]
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
                set itemH [_listHeight $pdf $item]
                if {$y + $itemH > $C(y_max)} {
                    set y [_col $pdf [expr {$C(y_max)+1}] col $title $subtitle]
                    set y [_section $pdf "$secTitle (cont.)" $y $col]
                }
                set y [_listItem $pdf $item $y $col]
            }
        }
        image {
            # content: list of {url alt title}
            foreach img $content {
                lassign $img url alt ttl
                # images hard to measure in advance -- conservative: reserve 80px
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
# Unicode font pipeline
# ---------------------------------------------------------------------------
#
# Prefer pdf4tcllib::fonts::init -cid 1 (search path for Linux/Windows/macOS).
# Fall back to the old hardcoded TTF list when pdf4tcllib is missing.
#
# Mode (Style(fontMode)):
#   strict -- bei Fehler: Exception werfen
#   warn   -- bei Fehler: stderr-Warnung + Fallback
#   silent -- bei Fehler: still Fallback

proc docir::tilepdf::_setupFonts {pdf} {
    variable F
    variable Style

    array set F {
        prop        Helvetica
        propBold    Helvetica-Bold
        propOblique Helvetica-Oblique
        mono        Courier
    }

    set mode warn
    if {[info exists Style(fontMode)]} { set mode $Style(fontMode) }

    if {![catch {package require pdf4tcllib 0.6}]} {
        if {[catch {::pdf4tcllib::fonts::init -cid 1 -force 1} err]} {
            _fontProblem $mode "pdf4tcllib::fonts::init: $err"
            return
        }
        set F(prop)        [::pdf4tcllib::fonts::fontSans]
        set F(propBold)    [::pdf4tcllib::fonts::fontSansBold]
        set F(propOblique) [::pdf4tcllib::fonts::fontSansItalic]
        set F(mono)        [::pdf4tcllib::fonts::fontMono]
        return
    }

    set missingApis {}
    if {[info commands ::pdf4tcl::loadBaseTrueTypeFont] eq ""} {
        lappend missingApis "loadBaseTrueTypeFont"
    }
    if {[info commands ::pdf4tcl::createFontSpecCID] eq ""} {
        lappend missingApis "createFontSpecCID"
    }
    if {[llength $missingApis] > 0} {
        _fontProblem $mode \
            "pdf4tcl-API fuer Unicode-Fonts unvollstaendig (fehlt: [join $missingApis {, }]); Fallback auf Standard-PDF-Fonts"
        return
    }

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
# On problems it throws (strict), warns (warn)
# or silently falls back (silent), depending on $mode.
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

# Render a sheet (= 1 page with a title)
proc docir::tilepdf::_renderSheet {pdf sheet} {
    variable C
    variable COL
    set title    [dict get $sheet title]
    set subtitle [dict get $sheet subtitle]
    set sections [dict get $sheet sections]

    $pdf startPage
    catch {$pdf bookmarkAdd -title $title -level 0}

    # fill the background if the theme is not white
    if {$COL(bg_r) < 0.99 || $COL(bg_g) < 0.99 || $COL(bg_b) < 0.99} {
        _withArtifact $pdf {
            $pdf setFillColor $COL(bg_r) $COL(bg_g) $COL(bg_b)
            $pdf rectangle 0 0 $C(page_w) $C(page_h) -filled 1
        }
    }

    _header $pdf $title $subtitle
    _divider $pdf

    set y   $C(y_start)
    set col $C(col1_x)

    foreach section $sections {
        set need [_sectionHeight $section]
        # the section header should go into the same column with at least
        # some content; if even that does not fit, switch column right away.
        # If the whole section does not fit in one column, no problem
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
    array set opts {-title "" -subtitle "" -theme light -lang de-DE -tagged 1}
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

    return [renderSheets $sheets $outFile -theme $opts(-theme) \
        -lang $opts(-lang) -tagged $opts(-tagged)]
}

# renderSheets: alternative public API -- takes a ready-made sheets list
# (e.g. from docir::csd::toSheets). Bypasses the DocIR schema check and
# the streamToSheets classification -- the caller is already in the
# Sheet-Format.
proc docir::tilepdf::renderSheets {sheets outFile args} {
    array set opts {-theme light -lang de-DE -tagged 1}
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
    if {$opts(-tagged)} {
        catch {$pdf tagged 1 -lang $opts(-lang)}
    }
    _setupFonts $pdf
    set first [lindex $sheets 0]
    set metaTitle [dict get $first title]
    set metaSub   [dict get $first subtitle]
    catch {
        $pdf metadata \
            -title $metaTitle \
            -subject $metaSub \
            -creator cheatsheets \
            -producer "docir::tilepdf / pdf4tcl"
    }
    catch {$pdf viewerPreferences -pagemode UseOutlines}
    foreach sheet $sheets {
        _renderSheet $pdf $sheet
    }
    $pdf write -file $outFile
    $pdf destroy
    return $outFile
}
