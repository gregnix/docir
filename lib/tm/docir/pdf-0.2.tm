# docir-pdf-0.2.tm -- DocIR → PDF Renderer
# BUILD-ID: pdf-0.2 seam+heightfit+logicalsize 2026-06-21 id=5f4d4dc4867621fe
# Converts a DocIR sequence into a PDF document. Uses
# pdf4tcl (>=0.9) as the low-level backend and pdf4tcllib (>=0.2)
# for font embedding (TTF), Unicode sanitization and
# Page-Helpers (Header/Footer).
#
# Public API:
#   docir::pdf::render ir outputPath ?options?
#       options: dict with
#         paper          a4|letter|...      (default a4)
#         margin         Int (pt)           (default 56 ≈ 20mm)
#         fontSize       Int                (default 11)
#         title          String             (default: from DocIR)
#         author         String             (default "")
#         subtitle       String             (default ""; title page only)
#         date           String             (default ""; title page only)
#         titlePage      Bool   (default 0)  eigene Titelseite vor dem TOC
#         sansFont       path to TTF        (optional, else pdf4tcllib default)
#         sansBoldFont, sansItalicFont, sansBoldItalicFont, monoFont
#         header         String             (Header-Template, %p = Pagenumber)
#         footer         String             (Footer-Template, %p = Pagenumber)
#         theme          Theme-Name         (optional, via mdstack::theme::toPdfOpts)
#
#         # NEU in 0.2:
#         generateToc    Bool   (default 0) Inhaltsverzeichnis am Anfang
#         tocTitle       String (default "Inhaltsverzeichnis")
#         tocDepth       Int    (default 2) Heading-Level bis zu welchem TOC-Eintraege
#         generateIndex  Bool   (default 0) Stichwortverzeichnis am Ende
#         indexTitle     String (default "Stichwortverzeichnis")
#         indexLevel     Int    (default 3) heading level that counts as an index entry
#         bookmarks      Bool   (default 1) PDF-Outline-Bookmarks bei Headings
#       Returns: nichts (schreibt nach outputPath)
#
#   docir::pdf::renderToHandle pdfHandle ir ?options?
#       Writes into an existing pdf4tcl handle.
#       The caller is responsible for pdf4tcl::new / startPage / write / destroy.
#       Useful to feed DocIR into an existing PDF workflow
#       (e.g. several documents into one file, or with header/footer).
#
# Architecture for TOC + index (0.2):
#   - Single-Pass-Rendering
#   - headings are collected during rendering in st(headingsSeen)
#     with page number and y position
#   - Bei -bookmarks 1: pdf bookmarkAdd direkt beim Heading-Render (Sidebar)
#   - with -generateToc 1: the TOC block is rendered BEFORE the main body
#       single-pass limitation: TOC entries have no page numbers
#       (clickable sidebar bookmarks compensate for this)
#   - with -generateIndex 1: the index block is rendered AFTER the main body
#       index entries have page numbers (which are known by then)

package provide docir::pdf 0.2
package require docir 0.1
package require docir::diag
package require docir::diagram

# pdf4tcl + pdf4tcllib are loaded lazily on the first render call,
# not at module source time. This way the module can be parsed even on
# systems without these backends
# (e.g. for tests that would only test _wrap or similar, or for
# package-Inventarisierung).

namespace eval ::docir::pdf {
    namespace export render renderToHandle
    variable _pdf4tclLoaded 0
}

proc docir::pdf::_dictDef {d k {def ""}} {
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}

proc docir::pdf::_ensurePdf4tcl {} {
    variable _pdf4tclLoaded
    if {$_pdf4tclLoaded} { return }
    if {[catch {package require pdf4tcl} err]} {
        return -code error "docir-pdf requires pdf4tcl: $err"
    }
    if {[catch {package require pdf4tcllib} err]} {
        return -code error "docir-pdf requires pdf4tcllib: $err"
    }
    set _pdf4tclLoaded 1
}

# ============================================================
# Public API
# ============================================================

proc docir::pdf::render {ir outputPath {options {}}} {
    _ensurePdf4tcl
    variable opts
    variable st
    set opts [_normalizeOptions $options]

    _initFonts

    set genToc [expr {[dict exists $opts generateToc] && [dict get $opts generateToc]}]

    if {!$genToc} {
        # Single-pass render (unchanged behaviour when no TOC is requested).
        set pdf [pdf4tcl::new %AUTO% -paper [dict get $opts paper] -orient true]
        if {[dict get $opts title]  ne ""} { $pdf metadata -title  [dict get $opts title]  }
        if {[dict get $opts author] ne ""} { $pdf metadata -author [dict get $opts author] }
        $pdf startPage
        _renderInto $pdf $ir
        $pdf write -file $outputPath
        $pdf destroy
        return
    }

    # Two-pass TOC with page numbers.
    #
    # The page number of a heading is only known after a full render, and the
    # TOC itself shifts every page that follows it. We therefore render the
    # whole document repeatedly, feeding the heading pages observed in one
    # iteration back into the next, until the page list is stable. Because the
    # page number is placed right-aligned on the heading's own line, the TOC
    # page count does not change once numbers are added, so this normally
    # converges after the second iteration.
    #
    # _renderToc reads opts(_tocPageList): a list of page numbers indexed in
    # heading document order (same order as st(headingsSeen)). Empty on the
    # first iteration -> TOC laid out without numbers.
    set tocPageList {}
    set maxIter 6
    set finalPdf ""
    for {set iter 1} {$iter <= $maxIter} {incr iter} {
        dict set opts _tocPageList $tocPageList
        set pdf [pdf4tcl::new %AUTO% -paper [dict get $opts paper] -orient true]
        if {[dict get $opts title]  ne ""} { $pdf metadata -title  [dict get $opts title]  }
        if {[dict get $opts author] ne ""} { $pdf metadata -author [dict get $opts author] }
        $pdf startPage
        _renderInto $pdf $ir

        # Collect heading pages in document order from the freshly built state.
        set newList {}
        foreach h [dict get $st headingsSeen] { lappend newList [dict get $h page] }

        if {$newList eq $tocPageList} {
            set finalPdf $pdf
            break
        }
        set tocPageList $newList
        if {$iter < $maxIter} {
            $pdf destroy
        } else {
            set finalPdf $pdf
            puts stderr "docir::pdf: TOC page numbers did not stabilise after\
                         $maxIter iterations; using last result."
        }
    }

    $finalPdf write -file $outputPath
    $finalPdf destroy
    return
}

proc docir::pdf::renderToHandle {pdf ir {options {}}} {
    _ensurePdf4tcl
    variable opts
    set opts [_normalizeOptions $options]
    _initFonts
    _renderInto $pdf $ir
    return
}

proc docir::pdf::_normalizeOptions {options} {
    set opts [dict create \
        paper              a4 \
        margin             56 \
        fontSize           11 \
        title              "" \
        author             "" \
        subtitle           "" \
        date               "" \
        titlePage          0 \
        sansFont           "" \
        sansBoldFont       "" \
        sansItalicFont     "" \
        sansBoldItalicFont "" \
        monoFont           "" \
        flowFont           "" \
        header             "" \
        footer             "" \
        theme              "" \
        colorLink          "#0066cc" \
        colorCode          "#e8e8e8" \
        root               "" \
        \
        generateToc        0 \
        tocTitle           "Inhaltsverzeichnis" \
        tocDepth           2 \
        generateIndex      0 \
        indexTitle         "Stichwortverzeichnis" \
        indexLevel         3 \
        bookmarks          1 \
        cid                0]
    foreach k [dict keys $options] {
        dict set opts $k [dict get $options $k]
    }

    # apply theme options (override defaults if set)
    set themeName [dict get $opts theme]
    if {$themeName ne ""} {
        if {![catch {package require mdstack::theme}]} {
            if {![catch {set thopts [::mdstack::theme::toPdfOpts $themeName]}]} {
                # mdstack::theme::toPdfOpts returns: fontsize, margin, colorLink, colorCode
                if {[dict exists $thopts fontsize]} {
                    dict set opts fontSize [dict get $thopts fontsize]
                }
                if {[dict exists $thopts margin]} {
                    dict set opts margin [dict get $thopts margin]
                }
                # take over colors — theme values are hex strings (#0066cc).
                # we store them as-is and convert on use
                # in pdf4tcl-RGB-Tripel (0..1).
                if {[dict exists $thopts colorLink]} {
                    dict set opts colorLink [dict get $thopts colorLink]
                }
                if {[dict exists $thopts colorCode]} {
                    dict set opts colorCode [dict get $thopts colorCode]
                }
            }
        }
    }

    return $opts
}

# Initializes pdf4tcllib::fonts with TTF paths from opts.
# Must be called ONCE per pdf lifecycle before the first setFont.
proc docir::pdf::_initFonts {} {
    variable opts
    set fontArgs {}
    foreach {optKey argKey} {
        sansFont           -sans
        sansBoldFont       -sansBold
        sansItalicFont     -sansItalic
        sansBoldItalicFont -sansBoldItalic
        monoFont           -mono
    } {
        set v [dict get $opts $optKey]
        if {$v ne ""} {
            lappend fontArgs $argKey $v
        }
    }
    # CID-Modus: volles Unicode-Subset (Greek, Math, Cyrillic, Pfeile ...)
    # instead of the 256-character encoding. Only glyphs the font actually
    # has are rendered; missing ones (e.g. CJK in DejaVu) stay .notdef/?.
    if {[dict exists $opts cid] && [dict get $opts cid]} {
        lappend fontArgs -cid 1
    }
    # if fontArgs is empty: pdf4tcllib::fonts::init uses its
    # eingebauten Defaults (Standard-PDF-Fonts ohne Embedding)
    ::pdf4tcllib::fonts::init {*}$fontArgs
}

# Converts a hex color string like "#0066cc" or "#06c"
# in pdf4tcl-kompatible RGB-Floats (0..1).
# Returns: list {r g b}, jeweils 0..1.
# on invalid input: {0 0 0} (black).
proc docir::pdf::_hexToRgb {hex} {
    set hex [string trimleft $hex "#"]
    set len [string length $hex]
    if {$len == 3} {
        # Kurzform: #abc → #aabbcc
        set r [string index $hex 0]
        set g [string index $hex 1]
        set b [string index $hex 2]
        set hex "$r$r$g$g$b$b"
        set len 6
    }
    if {$len != 6} { return {0 0 0} }
    if {[scan $hex %2x%2x%2x ri gi bi] != 3} { return {0 0 0} }
    return [list \
        [expr {$ri / 255.0}] \
        [expr {$gi / 255.0}] \
        [expr {$bi / 255.0}]]
}

# ============================================================
# Per-Inline Rendering: Style-Wechsel mitten im Paragraph
# ============================================================
#
# docir-pdf rendert Inlines NICHT mehr flach (via _inlinesToText) —
# but as segments with their own style. Pipeline:
#
#   Inlines → _inlinesToSegments → liste{(text, style, url?)}
#          → _wrapStyledSegments → liste{liste{(text, style, url?)}}
#          → _renderStyledLine    → setFont + draw + strike + hyperlink
#
# Style-Werte: normal, bold, italic, bolditalic, code, url, strike, break

# Returns the matching font name for a style.
proc docir::pdf::_styleToFont {style} {
    switch $style {
        normal     { return [::pdf4tcllib::fonts::fontSans] }
        bold       { return [::pdf4tcllib::fonts::fontSansBold] }
        italic     { return [::pdf4tcllib::fonts::fontSansItalic] }
        bolditalic { return [::pdf4tcllib::fonts::fontSansBoldItalic] }
        code       { return [::pdf4tcllib::fonts::fontMono] }
        strike     { return [::pdf4tcllib::fonts::fontSans] }
        url        { return [::pdf4tcllib::fonts::fontSans] }
        default    { return [::pdf4tcllib::fonts::fontSans] }
    }
}

# Merges directly consecutive index spans back into a single term. A
# bracketed span split across a source-text line break is emitted by the
# parser as several adjacent index spans (e.g. "intermediate" / "" /
# "representation"); without this they would be recorded as separate index
# entries. Spans separated by any non-index inline (normal text, even a
# single space) are left untouched, so distinct markers stay distinct.
proc docir::pdf::_coalesceIndexSpans {inlines} {
    set out {}
    set runParts {}
    set inRun 0
    foreach inline $inlines {
        set isIdx 0
        if {[dict exists $inline type] && [dict get $inline type] eq "span"} {
            if {[lsearch -exact [split [_dictDef $inline class ""]] index] >= 0} {
                set isIdx 1
            }
        }
        if {$isIdx} {
            set t [string trim [_dictDef $inline text ""]]
            if {$t ne ""} { lappend runParts $t }
            set inRun 1
        } else {
            if {$inRun} {
                lappend out [dict create type span class index \
                    text [join $runParts " "]]
                set runParts {}
                set inRun 0
            }
            lappend out $inline
        }
    }
    if {$inRun} {
        lappend out [dict create type span class index text [join $runParts " "]]
    }
    return $out
}

# Converts a docir-IR inline list into segments.
# Each segment: {text style url}.  url is set only for link inlines.
proc docir::pdf::_inlinesToSegments {inlines {parentStyle normal}} {
    set inlines [_coalesceIndexSpans $inlines]
    set segs {}
    foreach inline $inlines {
        if {![dict exists $inline type]} continue
        set type [dict get $inline type]
        set text [_dictDef $inline text ""]
        switch $type {
            text {
                lappend segs [list $text $parentStyle ""]
            }
            strong {
                set s [expr {$parentStyle in {italic bolditalic} ? "bolditalic" : "bold"}]
                lappend segs [list $text $s ""]
            }
            emphasis {
                set s [expr {$parentStyle in {bold bolditalic} ? "bolditalic" : "italic"}]
                lappend segs [list $text $s ""]
            }
            underline {
                # nroff-Style underline: in PDF als italic (mdpdf-Konvention)
                lappend segs [list $text "italic" ""]
            }
            strike {
                lappend segs [list $text "strike" ""]
            }
            code {
                lappend segs [list $text "code" ""]
            }
            link {
                # text=Label, href=URL
                set url ""
                if {[dict exists $inline href]} {
                    set url [dict get $inline href]
                }
                if {$text eq "" && $url ne ""} {
                    set text $url
                }
                lappend segs [list $text "url" $url]
            }
            image {
                set alt $text
                if {$alt ne ""} {
                    lappend segs [list "\[image: $alt\]" "italic" ""]
                } else {
                    lappend segs [list "\[image\]" "italic" ""]
                }
            }
            linebreak {
                lappend segs [list "" "break" ""]
            }
            softbreak {
                lappend segs [list " " $parentStyle ""]
            }
            span {
                # TIP-700 span: pass text through with parentStyle. A span
                # with the class "index" marks a subject-index term:
                # the term stays visible and is captured via the fourth
                # Segment-Feld bis _renderStyledLine getragen, wo die finale
                # page (see _renderIndex).
                set cls [_dictDef $inline class ""]
                set idxTerm ""
                if {[lsearch -exact [split $cls] index] >= 0} {
                    set idxTerm [string trim $text]
                }
                lappend segs [list $text $parentStyle "" $idxTerm]
            }
            footnote_ref {
                set marker [_dictDef $inline text "?"]
                lappend segs [list "\[$marker\]" $parentStyle ""]
            }
            math {
                # Inline-Math: $...$ als monospace, raw LaTeX
                # (no PDF-LaTeX rendering without an external engine).
                set txt [_dictDef $inline text ""]
                set disp [_dictDef $inline display 0]
                if {$disp} {
                    lappend segs [list "\$\$${txt}\$\$" code ""]
                } else {
                    lappend segs [list "\$${txt}\$" code ""]
                }
            }
            default {
                if {$text ne ""} {
                    lappend segs [list $text $parentStyle ""]
                }
            }
        }
    }
    return $segs
}

# Wraps styled segments into lines with real font width via getStringWidth.
proc docir::pdf::_wrapStyledSegments {segments maxW fontSize} {
    variable st
    set pdf [dict get $st pdf]

    # 1. extract words
    set words {}
    set prevTrailing 0
    foreach seg $segments {
        set text  [lindex $seg 0]
        set style [lindex $seg 1]
        set url   [lindex $seg 2]
        set idx   [lindex $seg 3]
        if {$style eq "break"} {
            lappend words [list "\n" "break" 0 "" ""]
            set prevTrailing 0
            continue
        }
        if {$text eq ""} continue
        set hasLeading  [expr {[string index $text 0] eq " "}]
        set hasTrailing [expr {[string index $text end] eq " "}]
        set text [string trim $text]
        if {$text eq ""} {
            set prevTrailing 1
            continue
        }
        set parts [split $text " "]
        for {set i 0} {$i < [llength $parts]} {incr i} {
            set w [lindex $parts $i]
            if {$w eq ""} continue
            if {$i == 0} {
                set spaced [expr {$hasLeading || $prevTrailing}]
            } else {
                set spaced 1
            }
            if {[string index $w 0] in {, . : ; ! ? )}} { set spaced 0 }
            # Index term only on the first word of the span, so the term is
            # captured once at its starting position.
            set wIdx [expr {$i == 0 ? $idx : ""}]
            lappend words [list $w $style $spaced $url $wIdx]
        }
        set prevTrailing $hasTrailing
    }

    if {[llength $words] == 0} {
        return [list [list [list "" "normal" ""]]]
    }

    # 2. Akkumulieren
    $pdf setFont $fontSize [::pdf4tcllib::fonts::fontSans]
    set spaceW [$pdf getStringWidth " "]
    set lines {}
    set curLine {}
    set curWidth 0.0

    foreach word $words {
        lassign $word w style spaced url wIdx
        if {$style eq "break"} {
            lappend lines $curLine
            set curLine {}
            set curWidth 0.0
            continue
        }
        set fontName [_styleToFont $style]
        $pdf setFont $fontSize $fontName
        set wordW [$pdf getStringWidth $w]
        set needSpace [expr {[llength $curLine] > 0 && $spaced}]
        set extraW [expr {$needSpace ? $spaceW : 0.0}]

        if {$curWidth + $extraW + $wordW > $maxW && [llength $curLine] > 0} {
            lappend lines $curLine
            set curLine [list [list $w $style $url $wIdx]]
            set curWidth $wordW
        } else {
            set prefix [expr {$needSpace ? " " : ""}]
            if {[llength $curLine] > 0} {
                set lastSeg [lindex $curLine end]
                set lastStyle [lindex $lastSeg 1]
                set lastUrl   [lindex $lastSeg 2]
                set lastIdx   [lindex $lastSeg 3]
                # Only merge when neither segment carries an index term, so an
                # index word stays an isolated segment (term captured once).
                if {$lastStyle eq $style && $lastUrl eq $url \
                        && $lastIdx eq "" && $wIdx eq ""} {
                    set curLine [lreplace $curLine end end \
                        [list "[lindex $lastSeg 0]${prefix}${w}" $style $url ""]]
                } else {
                    lappend curLine [list "${prefix}${w}" $style $url $wIdx]
                }
            } else {
                lappend curLine [list $w $style $url $wIdx]
            }
            set curWidth [expr {$curWidth + $extraW + $wordW}]
        }
    }

    if {[llength $curLine] > 0} { lappend lines $curLine }
    if {[llength $lines] == 0} {
        return [list [list [list "" "normal" ""]]]
    }
    return $lines
}

# Renders a line with font switching + strike + hyperlinks.
proc docir::pdf::_renderStyledLine {lineSegments y x0 fontSize} {
    variable st
    variable opts
    set pdf [dict get $st pdf]
    lassign [_hexToRgb [dict get $opts colorLink]] lr lg lb

    set x $x0
    foreach seg $lineSegments {
        set text  [lindex $seg 0]
        set style [lindex $seg 1]
        set url   [lindex $seg 2]
        set idxTerm [lindex $seg 3]
        if {$text eq ""} continue

        set fontName [_styleToFont $style]
        $pdf setFont $fontSize $fontName

        if {$style eq "url"} {
            $pdf setFillColor $lr $lg $lb
        }
        set sanitized [::pdf4tcllib::unicode::sanitize $text]
        $pdf text $sanitized -x $x -y $y
        if {$style eq "url"} {
            $pdf setFillColor 0 0 0
        }

        # Index term: record it with the page it is actually rendered on.
        # pageNo is final here because _ensureSpace/_newPage runs before the
        # line is rendered.
        if {$idxTerm ne ""} {
            dict lappend st indexEntries [list $idxTerm [dict get $st pageNo]]
        }

        set w [$pdf getStringWidth $sanitized]

        if {$style eq "strike"} {
            set strikeY [expr {$y - int($fontSize * 0.35)}]
            $pdf setLineWidth 0.6
            $pdf line $x $strikeY [expr {$x + $w}] $strikeY
        }

        if {$url ne "" && ![string match "mailto:*" $url]} {
            set linkH [expr {int($fontSize * 1.1)}]
            set linkY [expr {$y - int($fontSize * 0.8)}]
            catch {
                $pdf hyperlinkAdd $x $linkY $w $linkH $url
            }
        }
        set x [expr {$x + $w}]
    }
}

# ============================================================
# Layout state — page geometry
# ============================================================
#
# State variables are reset on every _renderInto call.
# Y in pdf4tcl: 0 = oben links (y waechst nach unten).
#

namespace eval ::docir::pdf {
    variable st  ;# state-dict
}

proc docir::pdf::_initState {pdf} {
    variable opts
    variable st

    # getDrawableArea returns {width height} of the printable area
    # after subtracting pdf4tcl-internal margins.
    # (note: some doc sources claim {x y w h} — that does not
    # match the real pdf4tcl implementation.)
    lassign [$pdf getDrawableArea] pageW pageH
    set margin [dict get $opts margin]

    set headerTemplate [dict get $opts header]
    set footerTemplate [dict get $opts footer]

    # if header/footer active: topY and bottomY must make room.
    # Header sits at y = margin*0.5, needs about 1.5em below it.
    # Footer sits at y = pageH - margin*0.5.
    set fontSize [dict get $opts fontSize]
    set topY $margin
    set bottomY [expr {$pageH - $margin}]
    if {$headerTemplate ne ""} {
        # Header-Zone reservieren: kleine Schrift ($fontSize - 1) plus
        # a bit of air. We shift topY down a little.
        set topY [expr {$margin + ($fontSize + 4)}]
    }
    if {$footerTemplate ne ""} {
        set bottomY [expr {$pageH - $margin - ($fontSize + 4)}]
    }

    set st [dict create \
        pdf            $pdf \
        margin         $margin \
        pageW          $pageW \
        pageH          $pageH \
        contentW       [expr {$pageW  - 2 * $margin}] \
        x              $margin \
        y              $topY \
        topY           $topY \
        bottomY        $bottomY \
        pageNo         1 \
        headerTemplate $headerTemplate \
        footerTemplate $footerTemplate \
        headingsSeen   {} \
        indexEntries   {}]
    # headingsSeen: list of dicts {level, text, page, anchor, isIndexEntry}
    # Wird von _renderHeading bei jedem Heading befuellt. Spaeter
    # evaluated by _renderToc (beforehand) and _renderIndex (after the main body).
}

proc docir::pdf::_advanceY {dy} {
    variable st
    dict set st y [expr {[dict get $st y] + $dy}]
}

proc docir::pdf::_ensureSpace {needed} {
    variable st
    if {[dict get $st y] + $needed > [dict get $st bottomY]} {
        _newPage
    }
}

# Renders a dedicated title page: title (large), optional subtitle, author
# and date, centred horizontally in the upper-middle of the page. No header
# or footer is placed on the title page. Afterwards a fresh page is started
# (counts as a page) so the body begins on its own page.
proc docir::pdf::_renderTitlePage {} {
    variable opts
    variable st
    set pdf      [dict get $st pdf]
    set pageW    [dict get $st pageW]
    set pageH    [dict get $st pageH]
    set fontSize [dict get $opts fontSize]

    set title    [dict get $opts title]
    set subtitle [_dictDef $opts subtitle ""]
    set author   [dict get $opts author]
    set date     [_dictDef $opts date ""]

    set cx [expr {$pageW / 2.0}]
    set y  [expr {$pageH * 0.32}]

    if {$title ne ""} {
        set fs [expr {$fontSize * 2.2}]
        $pdf setFont $fs [::pdf4tcllib::fonts::fontSansBold]
        $pdf text [::pdf4tcllib::unicode::sanitize $title] \
            -x $cx -y $y -align center
        set y [expr {$y + $fs * 1.6}]
    }
    if {$subtitle ne ""} {
        set fs [expr {$fontSize * 1.3}]
        $pdf setFont $fs [::pdf4tcllib::fonts::fontSans]
        $pdf text [::pdf4tcllib::unicode::sanitize $subtitle] \
            -x $cx -y $y -align center
        set y [expr {$y + $fs * 2.2}]
    }
    if {$author ne ""} {
        set fs [expr {$fontSize * 1.1}]
        $pdf setFont $fs [::pdf4tcllib::fonts::fontSans]
        $pdf text [::pdf4tcllib::unicode::sanitize $author] \
            -x $cx -y $y -align center
        set y [expr {$y + $fs * 1.8}]
    }
    if {$date ne ""} {
        $pdf setFont $fontSize [::pdf4tcllib::fonts::fontSans]
        $pdf text [::pdf4tcllib::unicode::sanitize $date] \
            -x $cx -y $y -align center
    }

    # Fresh page for the body; no footer on the title page.
    $pdf endPage
    $pdf startPage
    dict set st pageNo [expr {[dict get $st pageNo] + 1}]
    dict set st y [dict get $st topY]
}

proc docir::pdf::_writeHeader {} {
    variable opts
    variable st
    set tpl [dict get $st headerTemplate]
    if {$tpl eq ""} { return }

    set pdf      [dict get $st pdf]
    set margin   [dict get $st margin]
    set pageNo   [dict get $st pageNo]
    set fontSize [dict get $opts fontSize]

    # Template-Substitution: %p = Pagenumber
    set text [string map [list %p $pageNo] $tpl]
    set text [::pdf4tcllib::unicode::sanitize $text]

    set headerY [expr {$margin * 0.5}]
    $pdf setFont [expr {$fontSize - 1}] [::pdf4tcllib::fonts::fontSans]
    $pdf text $text -x $margin -y $headerY
}

proc docir::pdf::_writeFooter {} {
    variable opts
    variable st
    set tpl [dict get $st footerTemplate]
    if {$tpl eq ""} { return }

    set pdf      [dict get $st pdf]
    set margin   [dict get $st margin]
    set pageW    [dict get $st pageW]
    set pageH    [dict get $st pageH]
    set pageNo   [dict get $st pageNo]
    set fontSize [dict get $opts fontSize]

    set text [string map [list %p $pageNo] $tpl]
    set text [::pdf4tcllib::unicode::sanitize $text]

    set footerY [expr {$pageH - $margin * 0.5}]
    set footerX [expr {$pageW - $margin}]
    $pdf setFont [expr {$fontSize - 2}] [::pdf4tcllib::fonts::fontSans]
    $pdf text $text -x $footerX -y $footerY -align right
}

proc docir::pdf::_newPage {} {
    variable st
    set pdf [dict get $st pdf]

    # write the footer for the current page (before endPage)
    _writeFooter

    # pdf4tcl: no 'newPage' — endPage + startPage
    $pdf endPage
    $pdf startPage

    # increment the page counter
    dict set st pageNo [expr {[dict get $st pageNo] + 1}]
    dict set st y [dict get $st topY]

    # header for the new page
    _writeHeader
}

# ============================================================
# Render driver
# ============================================================

proc docir::pdf::_renderInto {pdf ir} {
    variable opts
    _initState $pdf

    # Optional title page first (no header/footer on it), then the body
    # starts on a fresh page. Counts as a page, so TOC/bookmark page numbers
    # reflect the real PDF pages.
    if {[info exists opts] && [dict exists $opts titlePage] \
            && [dict get $opts titlePage]} {
        _renderTitlePage
    }

    # header for the first page
    _writeHeader

    # TOC vor dem Hauptteil rendern (Single-Pass: ohne Seitenzahlen)
    if {[info exists opts] && [dict exists $opts generateToc] \
            && [dict get $opts generateToc]} {
        set tocHeadings [_scanHeadings $ir]
        if {[llength $tocHeadings] > 0} {
            _renderToc $tocHeadings
        }
    }

    # main body — fills st(headingsSeen) with page numbers along the way
    foreach node $ir {
        _renderBlock $node
    }

    # index at the end (single-pass: now knows all page numbers)
    if {[info exists opts] && [dict exists $opts generateIndex] \
            && [dict get $opts generateIndex]} {
        _renderIndex
    }

    # footer for the last page (no _newPage at the end)
    _writeFooter
}

proc docir::pdf::_renderBlock {node} {
    set t [dict get $node type]
    switch $t {
        doc_header   { _renderDocHeader  $node }
        heading      { _renderHeading    $node }
        paragraph    { _renderParagraph  $node }
        pre          { _renderPre        $node }
        list         { _renderList       $node }
        listItem     { _renderListItem   $node }
        blank        { _renderBlank      $node }
        hr           { _renderHr         $node }
        table        { _renderTable      $node }
        image        { _renderImageBlock $node }
        footnote_section { _renderFootnoteSection $node }
        footnote_def {
            # top-level fallback: as paragraph with footnote prefix
            _renderFootnoteDef $node
        }
        div          { _renderDiv $node }
        tableRow     -
        tableCell    {
            _renderUnknown $node "stray $t at top level"
        }
        default      {
            if {[::docir::isSchemaOnly $t]} { return }
            _renderUnknown $node "unknown block: $t"
        }
    }
}

# ============================================================
# Helpers — text inline collapse + width-aware wrap
# ============================================================

proc docir::pdf::_inlinesToText {inlines} {
    set out ""
    foreach i $inlines {
        if {[dict exists $i text]} { append out [dict get $i text] }
    }
    return $out
}

# Wraps text at maxWidth using $pdf getStringWidth in current font.
# Returns: list of lines.
proc docir::pdf::_wrap {text maxWidth} {
    variable st
    set pdf [dict get $st pdf]

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
            set wWidth [$pdf getStringWidth $candidate]
            if {$wWidth <= $maxWidth} {
                set current $candidate
            } else {
                if {$current ne ""} { lappend lines $current }
                set current $w
            }
        }
        if {$current ne ""} { lappend lines $current }
    }
    if {[llength $lines] == 0} { set lines [list ""] }
    return $lines
}

proc docir::pdf::_setFont {size {style ""}} {
    variable st
    # Font-Namen kommen jetzt von pdf4tcllib::fonts. Diese Helper
    # return either the TTF name (if pdf4tcllib::fonts::init
    # was called with TTF paths) or the standard PDF font names
    # als Fallback.
    switch $style {
        bold        { set name [::pdf4tcllib::fonts::fontSansBold] }
        italic      { set name [::pdf4tcllib::fonts::fontSansItalic] }
        bolditalic  { set name [::pdf4tcllib::fonts::fontSansBoldItalic] }
        mono        { set name [::pdf4tcllib::fonts::fontMono] }
        monobold    { set name [::pdf4tcllib::fonts::fontMono] }
        default     { set name [::pdf4tcllib::fonts::fontSans] }
    }
    [dict get $st pdf] setFont $size $name
}

proc docir::pdf::_lineHeight {fontSize} {
    return [expr {int($fontSize * 1.4)}]
}

# ============================================================
# Block renderers
# ============================================================

proc docir::pdf::_renderDocHeader {node} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [expr {[dict get $opts fontSize] - 2}]
    set lh [_lineHeight $fontSize]

    set m [dict get $node meta]
    set name    [expr {[dict exists $m name]    ? [dict get $m name]    : ""}]
    set section [_dictDef $m section ""]
    set version [_dictDef $m version ""]
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

    _ensureSpace [expr {$lh + 8}]
    _setFont $fontSize italic
    set x [dict get $st margin]
    set y [expr {[dict get $st y] + $fontSize}]
    $pdf text [::pdf4tcllib::unicode::sanitize $txt] -x $x -y $y
    _advanceY [expr {$lh + 4}]

    # Trennlinie
    $pdf setStrokeColor 0.7 0.7 0.7
    $pdf setLineWidth 0.5
    $pdf line $x [dict get $st y] [expr {$x + [dict get $st contentW]}] [dict get $st y]
    $pdf setStrokeColor 0 0 0
    _advanceY 6
}

proc docir::pdf::_renderHeading {node} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set baseFontSize [dict get $opts fontSize]

    set m [dict get $node meta]
    set lv [_dictDef $m level 1]
    if {$lv < 1} { set lv 1 }
    if {$lv > 6} { set lv 6 }
    set bonus [list 0 6 4 2 1 0 0]
    set fontSize [expr {$baseFontSize + [lindex $bonus $lv]}]
    set lh [_lineHeight $fontSize]

    # per-inline pipeline with baseStyle "bold" (a heading is bold by nature)
    # inline strong/emphasis within becomes bolditalic etc.
    set inlines [dict get $node content]
    set segs    [_inlinesToSegments $inlines "bold"]
    set lines   [_wrapStyledSegments $segs [dict get $st contentW] $fontSize]

    # extra space above
    _advanceY 6
    _ensureSpace [expr {[llength $lines] * $lh + 4}]

    # heading text as a plain string for bookmark + tracking
    set plainText [_inlinesToText $inlines]

    # set the PDF outline bookmark if enabled (points to the current page)
    # pdf4tcl-Konvention: Level 0 = Top-Level, Level 1 = Child eines L0,
    # usw. Daher `lv - 1` (H1 in Markdown = Level 0 in pdf4tcl-Outline).
    if {[dict get $opts bookmarks]} {
        set bmLevel [expr {$lv - 1}]
        if {$bmLevel < 0} { set bmLevel 0 }
        if {[catch {$pdf bookmarkAdd -title $plainText -level $bmLevel}]} {
            # bookmarkAdd not available or faulty — silently
            # ignore, so the render still runs.
        }
    }

    # register the heading in headingsSeen (for TOC + index)
    set indexLv [dict get $opts indexLevel]
    set anchorIdx [llength [dict get $st headingsSeen]]
    set entry [dict create \
        level         $lv \
        text          $plainText \
        page          [dict get $st pageNo] \
        anchor        "h-$anchorIdx" \
        isIndexEntry  [expr {$lv == $indexLv}]]
    dict lappend st headingsSeen $entry

    set x [dict get $st margin]
    foreach lineSegs $lines {
        set y [expr {[dict get $st y] + $fontSize}]
        _renderStyledLine $lineSegs $y $x $fontSize
        _advanceY $lh
    }

    if {$lv == 1} {
        # Linie unter h1
        $pdf setStrokeColor 0.5 0.5 0.5
        $pdf setLineWidth 0.5
        $pdf line $x [dict get $st y] [expr {$x + [dict get $st contentW]}] [dict get $st y]
        $pdf setStrokeColor 0 0 0
        _advanceY 4
    }
}

proc docir::pdf::_renderParagraph {node} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set m [dict get $node meta]
    set class [_dictDef $m class ""]

    set indent 0
    set baseStyle "normal"
    if {$class eq "blockquote"} {
        set indent 16
        set baseStyle "italic"
    }
    set x [expr {[dict get $st margin] + $indent}]
    set wText [expr {[dict get $st contentW] - $indent}]

    # Per-Inline-Pipeline: Segments → Wrapped Lines → Render
    set inlines [dict get $node content]
    set segs    [_inlinesToSegments $inlines $baseStyle]
    set lines   [_wrapStyledSegments $segs $wText $fontSize]

    set blockTopY [dict get $st y]
    foreach lineSegs $lines {
        _ensureSpace $lh
        set y [expr {[dict get $st y] + $fontSize}]
        _renderStyledLine $lineSegs $y $x $fontSize
        _advanceY $lh
    }

    if {$class eq "blockquote"} {
        # vertikaler Balken links
        $pdf setStrokeColor 0.7 0.7 0.7
        $pdf setLineWidth 2
        set xBar [dict get $st margin]
        $pdf line $xBar $blockTopY $xBar [dict get $st y]
        $pdf setStrokeColor 0 0 0
        $pdf setLineWidth 1
    }
    _advanceY 4
}

# Render a tuflow flow-diagram block to a PNG and place it like an image.
# Returns 1 on success, 0 to signal the caller to fall back to a code box.
proc docir::pdf::_renderFlowBlock {txt lang} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set lh [_lineHeight [dict get $opts fontSize]]
    try {
        set ff [expr {[dict exists $opts flowFont] ? [dict get $opts flowFont] : ""}]
        set fontOpt [expr {$ff eq "" ? {} : [list -fontfile $ff]}]
        set renderScale 3
        set png [docir::diagram::renderPng $txt $lang -scale $renderScale {*}$fontOpt]
        set ch  [file tempfile tmp]
        fconfigure $ch -translation binary
        puts -nonewline $ch $png
        close $ch
        set imgId [$pdf addImage $tmp -type png]
        lassign [$pdf getImageSize $imgId] pxW pxH
        # The PNG is oversampled by renderScale for crisp output. Embed it at
        # its logical (scale-1) point size instead of placing the pixels 1:1 as
        # points -- otherwise every diagram is renderScale-times too large and
        # gets pushed onto its own page. The fit-to-page step below still
        # shrinks genuinely oversized diagrams.
        set imgW [expr {$pxW / double($renderScale)}]
        set imgH [expr {$pxH / double($renderScale)}]
        set maxW [dict get $st contentW]
        set maxH [expr {[dict get $st bottomY] - [dict get $st topY]}]
        set sW [expr {$imgW > $maxW ? double($maxW) / $imgW : 1.0}]
        set sH [expr {$imgH > $maxH ? double($maxH) / $imgH : 1.0}]
        set scale [expr {min($sW, $sH)}]
        if {$scale < 1.0} {
            set imgW [expr {int($imgW * $scale)}]
            set imgH [expr {int($imgH * $scale)}]
        }
        _ensureSpace [expr {$imgH + $lh}]
        $pdf putImage $imgId [dict get $st margin] [dict get $st y] \
            -width $imgW -height $imgH
        _advanceY $imgH
        _advanceY 4
        catch {file delete $tmp}
        return 1
    } on error {m o} {
        catch {file delete $tmp}
        docir::diag::report [dict get $o -errorcode] "diagram/$lang: $m"
        return 0
    }
}

proc docir::pdf::_renderPre {node} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    # math block: raw LaTeX with $$...$$ wrapper -- no PDF-LaTeX rendering
    # without an external engine. We mark with $$ to set the math content off visually
    # vom normalen Code-Block zu trennen.
    set m [dict get $node meta]
    set kind [_dictDef $m kind ""]
    if {$kind eq "math"} {
        set content [dict get $node content]
        if {[string is list $content] && [llength $content] > 0 \
                && [catch {dict get [lindex $content 0] type}] == 0} {
            set txt [_inlinesToText $content]
        } else {
            set txt $content
        }
        # Try rendered display math via pdf4tcllib::math::renderLatex; on any
        # error fall back to the raw $$...$$ text rendering so PDF export can
        # never break on an unsupported construct.
        set latex [string trim [regsub -all {\s+} $txt " "]]
        set rendered 0
        if {$latex ne "" \
                && [llength [info commands ::pdf4tcllib::math::renderLatex]]} {
            set mathFont [::pdf4tcllib::fonts::fontSans]
            set msize [expr {$fontSize + 2}]
            if {[catch {
                lassign [::pdf4tcllib::math::measureLatex $pdf $latex \
                            -size $msize -font $mathFont] mw mh mdp
                set padding 6
                set blockH [expr {$mh + $mdp + 2 * $padding}]
                _ensureSpace $blockH
                set yTop [dict get $st y]
                $pdf setFillColor 0.95 0.94 0.88
                $pdf rectangle [dict get $st margin] $yTop \
                    [dict get $st contentW] $blockH -filled true -stroke false
                $pdf setFillColor 0 0 0
                set cx [expr {[dict get $st margin] \
                        + ([dict get $st contentW] - $mw) / 2.0}]
                if {$cx < [expr {[dict get $st margin] + 4}]} {
                    set cx [expr {[dict get $st margin] + 4}]
                }
                set baseY [expr {$yTop + $padding + $mh}]
                ::pdf4tcllib::math::renderLatex $pdf $cx $baseY $latex \
                    -size $msize -font $mathFont
                _advanceY $blockH
                _advanceY 4
                set rendered 1
            } err]} {
                set rendered 0
            }
        }
        if {$rendered} { return }
        # Fallback: raw $$...$$ as monospace text
        set lines [concat {$$} [split $txt "\n"] {$$}]
        _setFont $fontSize mono
        set x [dict get $st margin]
        set padding 4
        set rectH [expr {[llength $lines] * $lh + 2 * $padding}]
        _ensureSpace $rectH
        set yTop [dict get $st y]
        # Math-Block-Hintergrund: leicht andere Farbe als Code
        $pdf setFillColor 0.95 0.94 0.88
        $pdf rectangle $x $yTop [dict get $st contentW] $rectH \
            -filled true -stroke false
        $pdf setFillColor 0 0 0
        _advanceY $padding
        foreach line $lines {
            set y [expr {[dict get $st y] + $fontSize}]
            $pdf text [::pdf4tcllib::unicode::sanitize $line] -x [expr {$x + 4}] -y $y
            _advanceY $lh
        }
        _advanceY $padding
        _advanceY 4
        return
    }

    set txt [_inlinesToText [dict get $node content]]
    # tuflow flow-diagram: render to PNG and place it like an image block.
    # Lazy + defensive: missing tuflow or unparsable source falls through to
    # the normal code box, so PDF export never breaks on a flow block.
    set lang [_dictDef $m language ""]
    if {[docir::diagram::isDiagram $lang]} {
        if {[_renderFlowBlock $txt $lang]} { return }
    }
    set lines [split $txt "\n"]

    # Hintergrund-Box
    _setFont $fontSize mono
    set x [dict get $st margin]
    set padding 4

    set yTop [dict get $st y]
    set rectH [expr {[llength $lines] * $lh + 2 * $padding}]
    _ensureSpace $rectH
    set yTop [dict get $st y]

    # code block background: theme color or default
    lassign [_hexToRgb [dict get $opts colorCode]] cr cg cb
    $pdf setFillColor $cr $cg $cb
    $pdf rectangle $x $yTop [dict get $st contentW] $rectH -filled true -stroke false
    $pdf setFillColor 0 0 0

    _advanceY $padding
    foreach line $lines {
        # in pre: no wrap — should already be formatted correctly by the author
        set y [expr {[dict get $st y] + $fontSize}]
        $pdf text [::pdf4tcllib::unicode::sanitize $line] -x [expr {$x + 4}] -y $y
        _advanceY $lh
    }
    _advanceY $padding
    _advanceY 4
}

proc docir::pdf::_renderList {node} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set m [dict get $node meta]
    set kind [_dictDef $m kind "ul"]
    set indentLevel [_dictDef $m indentLevel 0]
    # indent: 12pt per level (standard for nested lists)
    set indentX [expr {$indentLevel * 12}]

    set ord 1
    foreach item [dict get $node content] {
        set itemType [dict get $item type]
        if {$itemType ne "listItem"} {
            _ensureSpace $lh
            _setFont $fontSize italic
            $pdf setFillColor 0.7 0.0 0.0
            set x [expr {[dict get $st margin] + $indentX}]
            set y [expr {[dict get $st y] + $fontSize}]
            $pdf text "\[!\] schema warning: $itemType in list.content" -x $x -y $y
            $pdf setFillColor 0 0 0
            _advanceY $lh
            continue
        }

        set itemMeta [dict get $item meta]
        set itemKind [_dictDef $itemMeta kind $kind]
        set itemTerm [_dictDef $itemMeta term {}]
        set itemDescInlines [dict get $item content]
        set itemExtras {}
        if {[dict exists $item blocks]} {
            set _bl [dict get $item blocks]
            set itemDescInlines [dict get [lindex $_bl 0] content]
            foreach _b [lrange $_bl 1 end] { lappend itemExtras [dict get $_b content] }
        }

        switch $itemKind {
            ol {
                set marker "${ord}. "
                _setFont $fontSize
                set markerW [$pdf getStringWidth $marker]
                _renderListItemMarker $marker $itemDescInlines $markerW $indentX $itemExtras
                incr ord
            }
            tp - ip - op - ap - dl {
                _renderListItemTerm $itemTerm $itemDescInlines $indentX
            }
            default {
                # ul + unknown → bullet
                set marker "- "
                _setFont $fontSize
                set markerW [$pdf getStringWidth $marker]
                _renderListItemMarker $marker $itemDescInlines $markerW $indentX $itemExtras
            }
        }
    }
    _advanceY 4
}

# Render an item as "MARKER  text..." — marker on first line,
# subsequent lines hang-indented to the marker's right edge.
proc docir::pdf::_renderListItemMarker {marker descInlines markerW {indentX 0} {extraParas {}}} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set xBase [expr {[dict get $st margin] + $indentX}]
    set xText [expr {$xBase + $markerW}]
    set wText [expr {[dict get $st contentW] - $markerW - $indentX}]

    # per-inline pipeline for the description
    set segs  [_inlinesToSegments $descInlines "normal"]
    set lines [_wrapStyledSegments $segs $wText $fontSize]

    set firstLine 1
    foreach lineSegs $lines {
        _ensureSpace $lh
        set y [expr {[dict get $st y] + $fontSize}]
        if {$firstLine} {
            # Marker in normalem Sans
            $pdf setFont $fontSize [::pdf4tcllib::fonts::fontSans]
            $pdf text [::pdf4tcllib::unicode::sanitize $marker] -x $xBase -y $y
            _renderStyledLine $lineSegs $y $xText $fontSize
            set firstLine 0
        } else {
            _renderStyledLine $lineSegs $y $xText $fontSize
        }
        _advanceY $lh
    }

    # Loose / multi-paragraph item: render each further paragraph hang-indented
    # to the text column, with a small gap before it.
    foreach para $extraParas {
        _advanceY [expr {$lh * 0.4}]
        set pSegs  [_inlinesToSegments $para "normal"]
        set pLines [_wrapStyledSegments $pSegs $wText $fontSize]
        foreach lineSegs $pLines {
            _ensureSpace $lh
            set y [expr {[dict get $st y] + $fontSize}]
            _renderStyledLine $lineSegs $y $xText $fontSize
            _advanceY $lh
        }
    }
}

# Render an item with a term on a separate line and indented description
proc docir::pdf::_renderListItemTerm {termInlines descInlines {indentX 0}} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set x [expr {[dict get $st margin] + $indentX}]

    # render the term in bold (also with per-inline pipeline for nested style)
    if {[llength $termInlines] > 0} {
        set termSegs [_inlinesToSegments $termInlines "bold"]
        set termLines [_wrapStyledSegments $termSegs \
            [expr {[dict get $st contentW] - $indentX}] $fontSize]
        foreach lineSegs $termLines {
            _ensureSpace $lh
            set y [expr {[dict get $st y] + $fontSize}]
            _renderStyledLine $lineSegs $y $x $fontSize
            _advanceY $lh
        }
    }

    # description indented + per-inline
    if {[llength $descInlines] > 0} {
        $pdf setFont $fontSize [::pdf4tcllib::fonts::fontSans]
        set indent [expr {2 * [$pdf getStringWidth "X"]}]
        set xDesc [expr {$x + $indent}]
        set wDesc [expr {[dict get $st contentW] - $indent - $indentX}]
        set descSegs [_inlinesToSegments $descInlines "normal"]
        set descLines [_wrapStyledSegments $descSegs $wDesc $fontSize]
        foreach lineSegs $descLines {
            _ensureSpace $lh
            set y [expr {[dict get $st y] + $fontSize}]
            _renderStyledLine $lineSegs $y $xDesc $fontSize
            _advanceY $lh
        }
    }
    _advanceY 2
}

proc docir::pdf::_renderListItem {node} {
    # Standalone listItem als Paragraph rendern (schema-fehlhaft,
    # should not happen)
    _renderUnknown $node "standalone listItem"
}

proc docir::pdf::_renderBlank {node} {
    variable opts
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]
    set m [_dictDef $node meta {}]
    set lines [_dictDef $m lines 1]
    if {$lines < 1} { set lines 1 }
    _advanceY [expr {$lh * $lines / 2}]
}

proc docir::pdf::_renderHr {node} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set lh [_lineHeight [dict get $opts fontSize]]
    _ensureSpace $lh

    set y [expr {[dict get $st y] + $lh / 2}]
    set xL [dict get $st margin]
    set xR [expr {$xL + [dict get $st contentW]}]
    $pdf setStrokeColor 0.7 0.7 0.7
    $pdf setLineWidth 0.5
    $pdf line $xL $y $xR $y
    $pdf setStrokeColor 0 0 0
    _advanceY $lh
}

proc docir::pdf::_renderTable {node} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]
    set padX 4
    set padY 3

    set m [dict get $node meta]
    set columns   [expr {[dict exists $m columns]   ? [dict get $m columns]   : 0}]
    set hasHeader [_dictDef $m hasHeader 0]

    if {$columns < 1} {
        _renderUnknown $node "table without columns"
        return
    }

    set colW [expr {[dict get $st contentW] / $columns}]
    set rowIndex 0
    foreach row [dict get $node content] {
        if {[dict get $row type] ne "tableRow"} {
            incr rowIndex
            continue
        }

        # PASS 1: pre-process cells — classify + determine image height
        # cellsInfo is a list{dict with type, text-or-images, height}
        set cellsInfo {}
        set maxImgH 0
        foreach cell [dict get $row content] {
            if {[dict get $cell type] ne "tableCell"} {
                lappend cellsInfo [dict create type empty]
                continue
            }
            set info [_classifyCell $cell $colW $padX $lh]
            lappend cellsInfo $info
            if {[dict get $info type] eq "images"} {
                set h [dict get $info height]
                if {$h > $maxImgH} { set maxImgH $h }
            }
        }

        # effective row height: max(text line height, image height) + padding
        set contentH [expr {$maxImgH > $lh ? $maxImgH : $lh}]
        set rowH [expr {$contentH + 2 * $padY}]
        _ensureSpace $rowH

        set isHeader [expr {$hasHeader && $rowIndex == 0}]
        set yTop [dict get $st y]

        if {$isHeader} {
            lassign [_hexToRgb [dict get $opts colorCode]] cr cg cb
            $pdf setFillColor $cr $cg $cb
            $pdf rectangle [dict get $st margin] $yTop [dict get $st contentW] $rowH -filled true -stroke false
            $pdf setFillColor 0 0 0
        }

        if {$isHeader} {
            _setFont $fontSize bold
        } else {
            _setFont $fontSize
        }

        # PASS 2: Zellen rendern
        set colIndex 0
        foreach info $cellsInfo {
            set xCell [expr {[dict get $st margin] + $colIndex * $colW}]
            set xText [expr {$xCell + $padX}]

            switch [dict get $info type] {
                images {
                    # place images centered vertically+horizontally in the cell
                    _renderCellImages $info $xCell $yTop $colW $rowH
                }
                text {
                    # place text vertically centered in the cell.
                    # baseline-y = yTop + (rowH + fontSize) / 2
                    # this way text and possibly images in adjacent cells
                    # auf gleicher visuellem Mittelpunkt.
                    set yText [expr {$yTop + ($rowH + $fontSize) / 2}]
                    $pdf text [::pdf4tcllib::unicode::sanitize [dict get $info text]] \
                        -x $xText -y $yText
                }
                default {
                    # mixed/empty — Text-Fallback, ebenfalls mittig
                    set yText [expr {$yTop + ($rowH + $fontSize) / 2}]
                    if {[dict exists $info text]} {
                        $pdf text [::pdf4tcllib::unicode::sanitize [dict get $info text]] \
                            -x $xText -y $yText
                    }
                }
            }

            # vertikaler Strich (links)
            $pdf setStrokeColor 0.7 0.7 0.7
            $pdf line $xCell $yTop $xCell [expr {$yTop + $rowH}]
            $pdf setStrokeColor 0 0 0
            incr colIndex
        }
        # right outer edge
        $pdf setStrokeColor 0.7 0.7 0.7
        set xR [expr {[dict get $st margin] + [dict get $st contentW]}]
        $pdf line $xR $yTop $xR [expr {$yTop + $rowH}]
        # untere Linie
        $pdf line [dict get $st margin] [expr {$yTop + $rowH}] $xR [expr {$yTop + $rowH}]
        if {$rowIndex == 0} {
            $pdf line [dict get $st margin] $yTop $xR $yTop
        }
        $pdf setStrokeColor 0 0 0

        _advanceY $rowH
        incr rowIndex
    }
    _advanceY 4
}

# Classifies a table cell:
# - "images" if only image inlines (loads images, scales to column width)
# - "text"   if no images
# - "mixed"  if mixed (text fallback with [image: alt] markers)
proc docir::pdf::_classifyCell {cell colW padX lh} {
    variable st
    set pdf [dict get $st pdf]
    set inlines [dict get $cell content]

    # Klassifizieren
    set imageInlines {}
    set hasNonImage 0
    foreach inl $inlines {
        if {![dict exists $inl type]} continue
        set t [dict get $inl type]
        if {$t eq "image"} {
            lappend imageInlines $inl
        } elseif {$t eq "text"} {
            # Whitespace-only counts not as non-image
            set txt [_dictDef $inl text ""]
            if {[string trim $txt] ne ""} {
                set hasNonImage 1
            }
        } else {
            set hasNonImage 1
        }
    }

    if {[llength $imageInlines] == 0} {
        # no images -> text
        return [dict create type text text [_inlinesToText $inlines]]
    }

    if {$hasNonImage} {
        # mixed -> text with [image: alt] marker (fallback)
        return [dict create type mixed text [_inlinesToText $inlines]]
    }

    # only images -> load, scale
    # available width for ALL images together
    set availW [expr {$colW - 2 * $padX}]
    set nImages [llength $imageInlines]
    # available width per image (with small spacing between)
    set perImgW [expr {($availW - ($nImages - 1) * 2) / $nImages}]
    if {$perImgW < 1} { set perImgW 1 }

    # max height for images in cells: 1.75 line heights
    # (at fontSize 11: ~26pt — icons 32x32 are scaled to 26x26,
    # Widgets 84x64 auf ca. 34x26)
    set maxImgH [expr {int(1.75 * $lh)}]

    set images {}
    set totalW 0
    set maxH 0
    foreach inl $imageInlines {
        set url [_dictDef $inl url ""]
        set alt [_dictDef $inl alt ""]
        set resolved [_resolveImagePath $url]
        if {$resolved eq "" || ![file exists $resolved] || ![file readable $resolved]} {
            # cannot load — alt text as fallback
            lappend images [dict create kind text text "\[$alt\]" w 0 h $lh]
            continue
        }
        if {[catch {$pdf addImage $resolved} imgId]} {
            lappend images [dict create kind text text "\[$alt\]" w 0 h $lh]
            continue
        }
        lassign [$pdf getImageSize $imgId] origW origH

        # scaling: respect perImgW AND maxImgH
        set scaleW [expr {double($perImgW) / $origW}]
        set scaleH [expr {double($maxImgH) / $origH}]
        # do not upscale beyond the original (pixel-perfect for icons)
        set scale [expr {min($scaleW, $scaleH, 1.0)}]
        set w [expr {int($origW * $scale)}]
        set h [expr {int($origH * $scale)}]
        if {$w < 1} { set w 1 }
        if {$h < 1} { set h 1 }

        lappend images [dict create kind image id $imgId w $w h $h]
        if {$h > $maxH} { set maxH $h }
    }

    return [dict create type images images $images height $maxH]
}

# Renders the images of a cell, centered vertically + horizontally
proc docir::pdf::_renderCellImages {info xCell yTop colW rowH} {
    variable st
    set pdf [dict get $st pdf]
    set images [dict get $info images]

    # compute total width of the images + gaps
    set spacing 2
    set totalW 0
    foreach img $images {
        incr totalW [dict get $img w]
    }
    incr totalW [expr {([llength $images] - 1) * $spacing}]

    # horizontally centered in the cell
    set xStart [expr {$xCell + ($colW - $totalW) / 2}]
    if {$xStart < $xCell + 2} { set xStart [expr {$xCell + 2}] }

    # Vertikal mittig: yTop + (rowH - imgH) / 2
    set x $xStart
    foreach img $images {
        set w [dict get $img w]
        set h [dict get $img h]
        set y [expr {$yTop + ($rowH - $h) / 2}]
        if {[dict get $img kind] eq "image"} {
            $pdf putImage [dict get $img id] $x $y -width $w -height $h
        } else {
            # text-Fallback (alt-text)
            set fontSize [dict get $::docir::pdf::opts fontSize]
            set yText [expr {$yTop + ($rowH + $fontSize) / 2}]
            $pdf text [::pdf4tcllib::unicode::sanitize [dict get $img text]] \
                -x $x -y $yText
        }
        set x [expr {$x + $w + $spacing}]
    }
}

proc docir::pdf::_renderImageBlock {node} {
    # block image. pdf4tcl::addImage loads the file directly from disk
    # (PNG/JPG without a Tk dependency). We resolve relative paths against
    # opts.root auf. Bei Fehler: Fallback auf [image: alt]-Marker.
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set m [dict get $node meta]
    set url [_dictDef $m url ""]
    set alt [_dictDef $m alt ""]

    # resolve the path against opts.root
    set resolvedPath [_resolveImagePath $url]
    set canLoad [expr {$resolvedPath ne "" && \
                       [file exists $resolvedPath] && \
                       [file readable $resolvedPath]}]

    if {$canLoad && [catch {$pdf addImage $resolvedPath} imgId] == 0} {
        # image loaded via pdf4tcl::addImage (no Tk needed)
        if {[catch {
            lassign [$pdf getImageSize $imgId] imgW imgH

            # Skalieren auf max contentW
            set maxW [dict get $st contentW]
            if {$imgW > $maxW} {
                set scale [expr {double($maxW) / $imgW}]
                set imgW [expr {int($imgW * $scale)}]
                set imgH [expr {int($imgH * $scale)}]
            }
            _ensureSpace [expr {$imgH + $lh}]
            set x [dict get $st margin]
            set y [dict get $st y]
            $pdf putImage $imgId $x $y -width $imgW -height $imgH
            _advanceY $imgH
        } imgErr]} {
            # putImage scheitert (z.B. unsupportetes Format)
            _renderImageFallback $url $alt
        } else {
            # Caption (alt) drunter
            if {$alt ne ""} {
                _setFont $fontSize italic
                set y [expr {[dict get $st y] + $fontSize}]
                $pdf setFillColor 0.4 0.4 0.4
                $pdf text [::pdf4tcllib::unicode::sanitize $alt] -x [dict get $st margin] -y $y
                $pdf setFillColor 0 0 0
                _advanceY [expr {$lh + 4}]
            }
        }
    } else {
        _renderImageFallback $url $alt
    }
}

# Resolves an image URL relative to opts.root.
# - absolute paths (file:// or /...) stay unchanged
# - HTTP/HTTPS URLs are not loadable — return ""
# - relative paths are resolved against opts.root
proc docir::pdf::_resolveImagePath {url} {
    variable opts
    if {$url eq ""} { return "" }

    # http(s) is not loaded via the file system
    if {[string match "http://*" $url] || [string match "https://*" $url]} {
        return ""
    }

    # file:// prefix entfernen
    if {[string match "file://*" $url]} {
        set url [string range $url 7 end]
    }

    # Schon absolut?
    if {[file pathtype $url] eq "absolute"} {
        return $url
    }

    # relative — resolve against opts.root
    set root [dict get $opts root]
    if {$root ne ""} {
        return [file join $root $url]
    }
    # Sonst: gegen cwd
    return $url
}

proc docir::pdf::_renderImageFallback {url alt} {
    # if the image is not loadable: textual marker
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]
    _ensureSpace $lh
    _setFont $fontSize italic
    $pdf setFillColor 0.4 0.4 0.4
    set msg "\[image: $alt"
    if {$url ne ""} { append msg " ($url)" }
    append msg "\]"
    set x [dict get $st margin]
    set y [expr {[dict get $st y] + $fontSize}]
    $pdf text [::pdf4tcllib::unicode::sanitize $msg] -x $x -y $y
    $pdf setFillColor 0 0 0
    _advanceY [expr {$lh + 2}]
}

proc docir::pdf::_renderFootnoteSection {node} {
    # separator line + all footnote_defs as small paragraphs
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    # Trennlinie
    _ensureSpace [expr {$lh * 2}]
    set y [expr {[dict get $st y] + $lh / 2}]
    set xL [dict get $st margin]
    set xR [expr {$xL + 100}]
    $pdf setStrokeColor 0.5 0.5 0.5
    $pdf setLineWidth 0.5
    $pdf line $xL $y $xR $y
    $pdf setStrokeColor 0 0 0
    _advanceY $lh

    foreach def [dict get $node content] {
        if {[dict get $def type] ne "footnote_def"} continue
        _renderFootnoteDef $def
    }
}

proc docir::pdf::_renderFootnoteDef {node} {
    # [N] content... als kleines Paragraph
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [expr {[dict get $opts fontSize] - 1}]  ;# leicht kleiner
    set lh [_lineHeight $fontSize]

    set m [dict get $node meta]
    set num [_dictDef $m num "?"]

    set body [_inlinesToText [dict get $node content]]
    set fullText "\[$num\] $body"
    set lines [_wrap $fullText [dict get $st contentW]]

    _setFont $fontSize
    foreach line $lines {
        _ensureSpace $lh
        set y [expr {[dict get $st y] + $fontSize}]
        $pdf text [::pdf4tcllib::unicode::sanitize $line] -x [dict get $st margin] -y $y
        _advanceY $lh
    }
    _advanceY 2
}

proc docir::pdf::_renderDiv {node} {
    # div ist transparent — children rendern
    foreach child [dict get $node content] {
        _renderBlock $child
    }
}

proc docir::pdf::_renderUnknown {node reason} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]
    _ensureSpace $lh

    _setFont $fontSize italic
    $pdf setFillColor 0.4 0.4 0.4
    set x [dict get $st margin]
    set y [expr {[dict get $st y] + $fontSize}]
    $pdf text "\[!\] $reason" -x $x -y $y
    $pdf setFillColor 0 0 0
    _advanceY [expr {$lh + 2}]
}

# ============================================================
# TOC and index (new in 0.2)
# ============================================================
#
# Both procs work on st(headingsSeen), which is filled by _renderHeading
# during the normal render run.
#
# _renderToc is called BEFORE the main body — at this point
# headingsSeen is still EMPTY. Therefore _renderToc generates no
# content from actually seen headings, but from a
# pre-scanned list. We pre-scan the DocIR sequence in the
# render wrapper and pass the heading list through.
#
# _renderIndex is called AFTER the main body — at this point
# headingsSeen contains all headings with correct page numbers.

# helper: scans the DocIR sequence and collects all headings as
# a list of dicts {level, text} (without page/anchor — those come
# beim Render).
proc docir::pdf::_scanHeadings {ir} {
    set out {}
    foreach node $ir {
        if {[dict get $node type] eq "heading"} {
            set m [dict get $node meta]
            set lv [_dictDef $m level 1]
            set text [_inlinesToText [dict get $node content]]
            lappend out [dict create level $lv text $text]
        }
    }
    return $out
}

# Renders the TOC before the main body. Input: pre-scanned heading list.
# Ohne Seitenzahlen (Single-Pass-Limitation), aber hierarchisch eingerueckt.
proc docir::pdf::_renderToc {tocHeadings} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set tocDepth [dict get $opts tocDepth]
    set tocTitle [dict get $opts tocTitle]

    # TOC header (large, bold)
    set titleSize [expr {$fontSize + 8}]
    set titleLh [_lineHeight $titleSize]
    _ensureSpace [expr {$titleLh * 2}]

    _setFont $titleSize bold
    set x [dict get $st margin]
    set y [expr {[dict get $st y] + $titleSize}]
    $pdf text [::pdf4tcllib::unicode::sanitize $tocTitle] -x $x -y $y
    _advanceY [expr {$titleLh + 6}]

    # Linie unter Titel
    $pdf setStrokeColor 0.5 0.5 0.5
    $pdf setLineWidth 0.5
    $pdf line $x [dict get $st y] [expr {$x + [dict get $st contentW]}] [dict get $st y]
    $pdf setStrokeColor 0 0 0
    _advanceY 8

    # render TOC entries. If opts(_tocPageList) is filled (second
    # render pass), the page number is set right-aligned per entry.
    # The index runs over ALL scanned headings (also those skipped after
    # tocDepth), so that it matches st(headingsSeen)/_tocPageList.
    set pageList [expr {[dict exists $opts _tocPageList] ? [dict get $opts _tocPageList] : {}}]
    set showPages [expr {[llength $pageList] > 0}]
    set rightEdge [expr {[dict get $st margin] + [dict get $st contentW]}]

    set lh [_lineHeight $fontSize]
    set idx -1
    foreach h $tocHeadings {
        incr idx
        set lv [dict get $h level]
        if {$lv > $tocDepth} continue

        _ensureSpace $lh

        # Indent nach Level: Level 1 = 0pt, Level 2 = 12pt, ...
        set indent [expr {($lv - 1) * 14}]
        set entryX [expr {[dict get $st margin] + $indent}]

        # font size: slightly reduced with level
        set entryFontSize [expr {$fontSize + (2 - $lv)}]
        if {$entryFontSize < $fontSize - 1} { set entryFontSize [expr {$fontSize - 1}] }

        if {$lv == 1} {
            _setFont $entryFontSize bold
        } else {
            _setFont $entryFontSize ""
        }

        # page number right-aligned — width reserves the space at the right
        # edge, so the title does not run into the number. getStringWidth measures
        # im gerade gesetzten Eintrags-Font.
        set pageStr ""
        set pageW 0
        if {$showPages} {
            set pageStr [lindex $pageList $idx]
            if {$pageStr ne ""} { set pageW [expr {[$pdf getStringWidth $pageStr] + 8}] }
        }

        set sanitized [::pdf4tcllib::unicode::sanitize [dict get $h text]]

        # wrap if needed — subtract space for the page number on the right.
        set maxW [expr {[dict get $st contentW] - $indent - $pageW}]
        set wrappedLines [_wrap $sanitized $maxW]
        set firstLine 1
        foreach wline $wrappedLines {
            _ensureSpace $lh
            set wy [expr {[dict get $st y] + $entryFontSize}]
            $pdf text [::pdf4tcllib::unicode::sanitize $wline] -x $entryX -y $wy
            if {$firstLine && $pageStr ne ""} {
                set px [expr {$rightEdge - [$pdf getStringWidth $pageStr]}]
                $pdf text $pageStr -x $px -y $wy
                set firstLine 0
            }
            _advanceY $lh
        }
    }

    # Seitenumbruch nach TOC
    _newPage
}

# Rendert den Index am Ende. Wird AUFGERUFEN nach dem Hauptteil —
# headingsSeen is then complete with correct page numbers.
proc docir::pdf::_renderIndex {} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set indexTitle [dict get $opts indexTitle]

    # subject index from [term]{.index} markers (st indexEntries):
    # term -> list of pages. Fallback (no markers present): the
    # fruehere Heading-Index (Ueberschriften auf indexLevel), kompatibel.
    set byTerm [dict create]
    foreach e [dict get $st indexEntries] {
        lassign $e term page
        dict lappend byTerm $term $page
    }
    if {[dict size $byTerm] == 0} {
        foreach h [dict get $st headingsSeen] {
            if {[dict get $h isIndexEntry]} {
                dict lappend byTerm [dict get $h text] [dict get $h page]
            }
        }
    }
    if {[dict size $byTerm] == 0} {
        return
    }

    # terms alphabetically; pages per term deduplicated + numerically sorted.
    set entries {}
    foreach term [lsort -dictionary [dict keys $byTerm]] {
        lappend entries [list $term [lsort -integer -unique [dict get $byTerm $term]]]
    }

    # new page for the index
    _newPage

    # Index-Titel
    set titleSize [expr {$fontSize + 8}]
    set titleLh [_lineHeight $titleSize]
    _ensureSpace [expr {$titleLh * 2}]

    _setFont $titleSize bold
    set x [dict get $st margin]
    set y [expr {[dict get $st y] + $titleSize}]
    $pdf text [::pdf4tcllib::unicode::sanitize $indexTitle] -x $x -y $y
    _advanceY [expr {$titleLh + 6}]

    # Linie unter Titel
    $pdf setStrokeColor 0.5 0.5 0.5
    $pdf setLineWidth 0.5
    $pdf line $x [dict get $st y] [expr {$x + [dict get $st contentW]}] [dict get $st y]
    $pdf setStrokeColor 0 0 0
    _advanceY 8

    # bookmark for the index itself (top level)
    if {[dict get $opts bookmarks]} {
        catch {$pdf bookmarkAdd -title $indexTitle -level 0}
    }

    # Eintraege rendern, gruppiert nach Anfangsbuchstaben
    set lh [_lineHeight $fontSize]
    set lastInitial ""
    set rightEdge [expr {$x + [dict get $st contentW]}]

    foreach e $entries {
        lassign $e text pages

        # initial letter (with umlaut normalization)
        set initial [string toupper [string index $text 0]]
        switch -- $initial {
            "Ä" { set initial "A" }
            "Ö" { set initial "O" }
            "Ü" { set initial "U" }
        }

        # Buchstaben-Header bei Wechsel
        if {$initial ne $lastInitial} {
            _advanceY 4
            _ensureSpace [expr {$lh * 2}]
            _setFont [expr {$fontSize + 2}] bold
            set hy [expr {[dict get $st y] + $fontSize + 2}]
            $pdf text [::pdf4tcllib::unicode::sanitize $initial] -x $x -y $hy
            _advanceY [expr {$lh + 2}]
            set lastInitial $initial
        }

        _ensureSpace $lh
        _setFont $fontSize ""

        set ey [expr {[dict get $st y] + $fontSize}]
        set entryX [expr {$x + 8}]

        # page list right-aligned (e.g. "3, 7, 12"); width via getStringWidth.
        set pageStr [join $pages ", "]
        set pageW [$pdf getStringWidth $pageStr]
        set pageX [expr {$rightEdge - $pageW}]

        # term on the left; truncate if needed so the page column stays free.
        set maxTextW [expr {[dict get $st contentW] - 8 - $pageW - 12}]
        set displayText [::pdf4tcllib::unicode::sanitize $text]
        set tw [$pdf getStringWidth $displayText]
        if {$maxTextW > 0 && $tw > $maxTextW} {
            while {$tw > $maxTextW && [string length $displayText] > 4} {
                set displayText [string range $displayText 0 end-2]
                set tw [$pdf getStringWidth "${displayText}..."]
            }
            set displayText "${displayText}..."
        }

        $pdf text $displayText -x $entryX -y $ey
        $pdf text $pageStr -x $pageX -y $ey

        _advanceY $lh
    }
}

# ============================================================
# Render wrapper with TOC + index support
# ============================================================

# Patch: render and renderToHandle extended with TOC + index phases.
# with -generateToc, _renderToc is called before _renderInto
# (with pre-scanned heading list).
# with -generateIndex, _renderIndex is called after _renderInto
# (uses the headings + page numbers collected during the render).
