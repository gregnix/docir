# docir-pdf-0.2.tm -- DocIR → PDF Renderer
#
# Wandelt eine DocIR-Sequenz in ein PDF-Dokument um. Nutzt
# pdf4tcl (>=0.9) als Low-Level-Backend und pdf4tcllib (>=0.2)
# für Font-Embedding (TTF), Unicode-Sanitization und
# Page-Helpers (Header/Footer).
#
# Public API:
#   docir::pdf::render ir outputPath ?options?
#       options: dict mit
#         paper          a4|letter|...      (default a4)
#         margin         Int (pt)           (default 56 ≈ 20mm)
#         fontSize       Int                (default 11)
#         title          String             (default: aus DocIR)
#         author         String             (default "")
#         sansFont       Pfad zu TTF        (optional, sonst pdf4tcllib-Default)
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
#         indexLevel     Int    (default 3) Heading-Level der als Index-Eintrag gilt
#         bookmarks      Bool   (default 1) PDF-Outline-Bookmarks bei Headings
#       Returns: nichts (schreibt nach outputPath)
#
#   docir::pdf::renderToHandle pdfHandle ir ?options?
#       Schreibt in einen vorhandenen pdf4tcl-Handle.
#       Caller ist verantwortlich fuer pdf4tcl::new / startPage / write / destroy.
#       Nuetzlich um DocIR in einen vorhandenen PDF-Workflow einzuspeisen
#       (z.B. mehrere Dokumente in eine Datei oder mit Header/Footer).
#
# Architektur fuer TOC + Index (0.2):
#   - Single-Pass-Rendering
#   - Headings werden waehrend des Renders in st(headingsSeen) gesammelt
#     mit Seitennummer und y-Position
#   - Bei -bookmarks 1: pdf bookmarkAdd direkt beim Heading-Render (Sidebar)
#   - Bei -generateToc 1: TOC-Block wird VOR den Hauptteil gerendert
#       Limitation Single-Pass: TOC-Eintraege haben keine Seitenzahlen
#       (klickbare Sidebar-Bookmarks kompensieren das)
#   - Bei -generateIndex 1: Index-Block wird NACH dem Hauptteil gerendert
#       Index-Eintraege haben Seitenzahlen (sind dann bekannt)

package provide docir::pdf 0.2
package require docir 0.1

# pdf4tcl + pdf4tcllib werden lazy beim ersten render-Aufruf geladen,
# nicht beim Modul-Source. So kann das Modul auch auf Systemen ohne
# diese Backends geparst werden
# (z.B. fuer Tests die nur _wrap o.ae. testen wuerden, oder fuer
# package-Inventarisierung).

namespace eval ::docir::pdf {
    namespace export render renderToHandle
    variable _pdf4tclLoaded 0
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
    set opts [_normalizeOptions $options]

    _initFonts

    set pdf [pdf4tcl::new %AUTO% -paper [dict get $opts paper] -orient true]
    if {[dict get $opts title]  ne ""} { $pdf metadata -title  [dict get $opts title]  }
    if {[dict get $opts author] ne ""} { $pdf metadata -author [dict get $opts author] }

    $pdf startPage
    _renderInto $pdf $ir

    $pdf write -file $outputPath
    $pdf destroy
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
        sansFont           "" \
        sansBoldFont       "" \
        sansItalicFont     "" \
        sansBoldItalicFont "" \
        monoFont           "" \
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
        bookmarks          1]
    foreach k [dict keys $options] {
        dict set opts $k [dict get $options $k]
    }

    # Theme-Optionen anwenden (override defaults wenn gesetzt)
    set themeName [dict get $opts theme]
    if {$themeName ne ""} {
        if {![catch {package require mdstack::theme}]} {
            if {![catch {set thopts [::mdstack::theme::toPdfOpts $themeName]}]} {
                # mdstack::theme::toPdfOpts liefert: fontsize, margin, colorLink, colorCode
                if {[dict exists $thopts fontsize]} {
                    dict set opts fontSize [dict get $thopts fontsize]
                }
                if {[dict exists $thopts margin]} {
                    dict set opts margin [dict get $thopts margin]
                }
                # Farben übernehmen — Theme-Werte sind Hex-Strings (#0066cc).
                # Wir speichern sie als-is und konvertieren bei Verwendung
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

# Initialisiert pdf4tcllib::fonts mit TTF-Pfaden aus opts.
# Muss EINMAL pro pdf-Lifecycle vor dem ersten setFont gerufen werden.
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
    # Wenn fontArgs leer: pdf4tcllib::fonts::init nutzt seine
    # eingebauten Defaults (Standard-PDF-Fonts ohne Embedding)
    ::pdf4tcllib::fonts::init {*}$fontArgs
}

# Konvertiert einen Hex-Color-String wie "#0066cc" oder "#06c"
# in pdf4tcl-kompatible RGB-Floats (0..1).
# Returns: list {r g b}, jeweils 0..1.
# Bei ungültigem Input: {0 0 0} (schwarz).
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
# sondern als Segmente mit eigenem Style. Pipeline:
#
#   Inlines → _inlinesToSegments → liste{(text, style, url?)}
#          → _wrapStyledSegments → liste{liste{(text, style, url?)}}
#          → _renderStyledLine    → setFont + draw + strike + hyperlink
#
# Style-Werte: normal, bold, italic, bolditalic, code, url, strike, break

# Liefert den passenden Font-Namen für einen Style.
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

# Wandelt eine docir-IR Inline-Liste in Segmente um.
# Jedes Segment: {text style url}.  url ist nur bei link-Inlines gesetzt.
proc docir::pdf::_inlinesToSegments {inlines {parentStyle normal}} {
    set segs {}
    foreach inline $inlines {
        if {![dict exists $inline type]} continue
        set type [dict get $inline type]
        set text [expr {[dict exists $inline text] ? [dict get $inline text] : ""}]
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
            span {
                # TIP-700 span: text durchreichen mit parentStyle
                lappend segs [list $text $parentStyle ""]
            }
            footnote_ref {
                set marker [expr {[dict exists $inline text] ? [dict get $inline text] : "?"}]
                lappend segs [list "\[$marker\]" $parentStyle ""]
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

# Wraps styled segments in Lines mit echter Font-Breite via getStringWidth.
proc docir::pdf::_wrapStyledSegments {segments maxW fontSize} {
    variable st
    set pdf [dict get $st pdf]

    # 1. Wörter extrahieren
    set words {}
    set prevTrailing 0
    foreach seg $segments {
        set text  [lindex $seg 0]
        set style [lindex $seg 1]
        set url   [lindex $seg 2]
        if {$style eq "break"} {
            lappend words [list "\n" "break" 0 ""]
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
            lappend words [list $w $style $spaced $url]
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
        lassign $word w style spaced url
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
            set curLine [list [list $w $style $url]]
            set curWidth $wordW
        } else {
            set prefix [expr {$needSpace ? " " : ""}]
            if {[llength $curLine] > 0} {
                set lastSeg [lindex $curLine end]
                set lastStyle [lindex $lastSeg 1]
                set lastUrl   [lindex $lastSeg 2]
                if {$lastStyle eq $style && $lastUrl eq $url} {
                    set curLine [lreplace $curLine end end \
                        [list "[lindex $lastSeg 0]${prefix}${w}" $style $url]]
                } else {
                    lappend curLine [list "${prefix}${w}" $style $url]
                }
            } else {
                lappend curLine [list $w $style $url]
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

# Rendert eine Line mit Font-Wechsel + Strike + Hyperlinks.
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
# State-Variablen werden bei jedem _renderInto-Aufruf zurueckgesetzt.
# Y in pdf4tcl: 0 = oben links (y waechst nach unten).
#

namespace eval ::docir::pdf {
    variable st  ;# state-dict
}

proc docir::pdf::_initState {pdf} {
    variable opts
    variable st

    # getDrawableArea liefert {width height} der bedruckbaren Fläche
    # nach Abzug der pdf4tcl-internen Margins.
    # (Hinweis: einige Doku-Quellen behaupten {x y w h} — das stimmt
    # mit der echten pdf4tcl-Implementierung nicht ueberein.)
    lassign [$pdf getDrawableArea] pageW pageH
    set margin [dict get $opts margin]

    set headerTemplate [dict get $opts header]
    set footerTemplate [dict get $opts footer]

    # Wenn Header/Footer aktiv: topY und bottomY müssen Platz machen.
    # Header sitzt bei y = margin*0.5, braucht etwa 1.5em darunter.
    # Footer sitzt bei y = pageH - margin*0.5.
    set fontSize [dict get $opts fontSize]
    set topY $margin
    set bottomY [expr {$pageH - $margin}]
    if {$headerTemplate ne ""} {
        # Header-Zone reservieren: kleine Schrift ($fontSize - 1) plus
        # ein bisschen Luft. Wir verschieben topY ein Stück nach unten.
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
        headingsSeen   {}]
    # headingsSeen: Liste von dicts {level, text, page, anchor, isIndexEntry}
    # Wird von _renderHeading bei jedem Heading befuellt. Spaeter
    # ausgewertet von _renderToc (Vorab) und _renderIndex (Nach Hauptteil).
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

    # Footer für aktuelle Page schreiben (vor endPage)
    _writeFooter

    # pdf4tcl: kein 'newPage' — endPage + startPage
    $pdf endPage
    $pdf startPage

    # Page-Counter erhöhen
    dict set st pageNo [expr {[dict get $st pageNo] + 1}]
    dict set st y [dict get $st topY]

    # Header für neue Page
    _writeHeader
}

# ============================================================
# Render driver
# ============================================================

proc docir::pdf::_renderInto {pdf ir} {
    variable opts
    _initState $pdf
    # Header für die erste Page
    _writeHeader

    # TOC vor dem Hauptteil rendern (Single-Pass: ohne Seitenzahlen)
    if {[info exists opts] && [dict exists $opts generateToc] \
            && [dict get $opts generateToc]} {
        set tocHeadings [_scanHeadings $ir]
        if {[llength $tocHeadings] > 0} {
            _renderToc $tocHeadings
        }
    }

    # Hauptteil — befuellt nebenbei st(headingsSeen) mit Seitenzahlen
    foreach node $ir {
        _renderBlock $node
    }

    # Index am Ende (Single-Pass: kennt jetzt alle Seitenzahlen)
    if {[info exists opts] && [dict exists $opts generateIndex] \
            && [dict get $opts generateIndex]} {
        _renderIndex
    }

    # Footer für die letzte Page (kein _newPage am Ende)
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
    # liefern entweder den TTF-Namen (wenn pdf4tcllib::fonts::init
    # gerufen wurde mit TTF-Pfaden) oder die Standard-PDF-Schriftnamen
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
    set lv [expr {[dict exists $m level] ? [dict get $m level] : 1}]
    if {$lv < 1} { set lv 1 }
    if {$lv > 6} { set lv 6 }
    set bonus [list 0 6 4 2 1 0 0]
    set fontSize [expr {$baseFontSize + [lindex $bonus $lv]}]
    set lh [_lineHeight $fontSize]

    # Per-Inline-Pipeline mit baseStyle "bold" (Heading ist von Natur fett)
    # Inline-Strong/Emphasis innerhalb wird zu bolditalic etc.
    set inlines [dict get $node content]
    set segs    [_inlinesToSegments $inlines "bold"]
    set lines   [_wrapStyledSegments $segs [dict get $st contentW] $fontSize]

    # extra space above
    _advanceY 6
    _ensureSpace [expr {[llength $lines] * $lh + 4}]

    # Heading-Text als Plain-String fuer Bookmark + Tracking
    set plainText [_inlinesToText $inlines]

    # PDF-Outline-Bookmark setzen wenn aktiviert (zeigt auf aktuelle Seite)
    # pdf4tcl-Konvention: Level 0 = Top-Level, Level 1 = Child eines L0,
    # usw. Daher `lv - 1` (H1 in Markdown = Level 0 in pdf4tcl-Outline).
    if {[dict get $opts bookmarks]} {
        set bmLevel [expr {$lv - 1}]
        if {$bmLevel < 0} { set bmLevel 0 }
        if {[catch {$pdf bookmarkAdd -title $plainText -level $bmLevel}]} {
            # bookmarkAdd nicht verfuegbar oder fehlerhaft — silently
            # ignorieren, damit der Render trotzdem laeuft.
        }
    }

    # Heading in headingsSeen registrieren (fuer TOC + Index)
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
    set class [expr {[dict exists $m class] ? [dict get $m class] : ""}]

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

proc docir::pdf::_renderPre {node} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set txt [_inlinesToText [dict get $node content]]
    set lines [split $txt "\n"]

    # Hintergrund-Box
    _setFont $fontSize mono
    set x [dict get $st margin]
    set padding 4

    set yTop [dict get $st y]
    set rectH [expr {[llength $lines] * $lh + 2 * $padding}]
    _ensureSpace $rectH
    set yTop [dict get $st y]

    # Code-Block-Hintergrund: Theme-Farbe oder Default
    lassign [_hexToRgb [dict get $opts colorCode]] cr cg cb
    $pdf setFillColor $cr $cg $cb
    $pdf rectangle $x $yTop [dict get $st contentW] $rectH -filled true -stroke false
    $pdf setFillColor 0 0 0

    _advanceY $padding
    foreach line $lines {
        # Im pre: kein Wrap — sollte vom Autor schon richtig formatiert sein
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
    set kind [expr {[dict exists $m kind] ? [dict get $m kind] : "ul"}]
    set indentLevel [expr {[dict exists $m indentLevel] ? [dict get $m indentLevel] : 0}]
    # Indent: 12pt pro Level (Standard fuer geschachtelte Listen)
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
        set itemKind [expr {[dict exists $itemMeta kind] ? [dict get $itemMeta kind] : $kind}]
        set itemTerm [expr {[dict exists $itemMeta term] ? [dict get $itemMeta term] : {}}]
        set itemDescInlines [dict get $item content]

        switch $itemKind {
            ol {
                set marker "${ord}. "
                _setFont $fontSize
                set markerW [$pdf getStringWidth $marker]
                _renderListItemMarker $marker $itemDescInlines $markerW $indentX
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
                _renderListItemMarker $marker $itemDescInlines $markerW $indentX
            }
        }
    }
    _advanceY 4
}

# Render an item as "MARKER  text..." — marker on first line,
# subsequent lines hang-indented to the marker's right edge.
proc docir::pdf::_renderListItemMarker {marker descInlines markerW {indentX 0}} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set xBase [expr {[dict get $st margin] + $indentX}]
    set xText [expr {$xBase + $markerW}]
    set wText [expr {[dict get $st contentW] - $markerW - $indentX}]

    # Per-Inline-Pipeline für die Beschreibung
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
}

# Render an item with a term on a separate line and indented description
proc docir::pdf::_renderListItemTerm {termInlines descInlines {indentX 0}} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set x [expr {[dict get $st margin] + $indentX}]

    # Term in bold rendern (auch mit per-inline-Pipeline für nested style)
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

    # Description eingerückt + per-inline
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
    # sollte nicht vorkommen)
    _renderUnknown $node "standalone listItem"
}

proc docir::pdf::_renderBlank {node} {
    variable opts
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]
    set m [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
    set lines [expr {[dict exists $m lines] ? [dict get $m lines] : 1}]
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
    set hasHeader [expr {[dict exists $m hasHeader] ? [dict get $m hasHeader] : 0}]

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

        # PASS 1: Pre-process Zellen — klassifizieren + Bild-Höhe ermitteln
        # cellsInfo ist liste{dict mit type, text-or-images, height}
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

        # Effektive Row-Höhe: max(text-line-height, image-höhe) + padding
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
                    # Bilder mittig vertikal+horizontal in der Zelle platzieren
                    _renderCellImages $info $xCell $yTop $colW $rowH
                }
                text {
                    # Text vertikal mittig in der Zelle platzieren.
                    # baseline-y = yTop + (rowH + fontSize) / 2
                    # Damit liegen Text und ggf. Bilder in benachbarten Cells
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
        # rechte Außenkante
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

# Klassifiziert eine Tabellen-Zelle:
# - "images" wenn nur image-Inlines (lädt Bilder, skaliert auf Spaltenbreite)
# - "text"   wenn keine Bilder
# - "mixed"  wenn Mix (Text-Fallback mit [image: alt]-Markern)
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
            set txt [expr {[dict exists $inl text] ? [dict get $inl text] : ""}]
            if {[string trim $txt] ne ""} {
                set hasNonImage 1
            }
        } else {
            set hasNonImage 1
        }
    }

    if {[llength $imageInlines] == 0} {
        # Keine Bilder → text
        return [dict create type text text [_inlinesToText $inlines]]
    }

    if {$hasNonImage} {
        # Mixed → Text mit [image: alt]-Marker (Fallback)
        return [dict create type mixed text [_inlinesToText $inlines]]
    }

    # Nur Bilder → laden, skalieren
    # Verfügbare Breite für ALLE Bilder zusammen
    set availW [expr {$colW - 2 * $padX}]
    set nImages [llength $imageInlines]
    # Pro Bild verfügbare Breite (mit kleinem Spacing zwischen)
    set perImgW [expr {($availW - ($nImages - 1) * 2) / $nImages}]
    if {$perImgW < 1} { set perImgW 1 }

    # Max-Höhe für Bilder in Zellen: 1.75 Zeilen-Höhen
    # (bei fontSize 11: ~26pt — Icons 32x32 werden auf 26x26 skaliert,
    # Widgets 84x64 auf ca. 34x26)
    set maxImgH [expr {int(1.75 * $lh)}]

    set images {}
    set totalW 0
    set maxH 0
    foreach inl $imageInlines {
        set url [expr {[dict exists $inl url] ? [dict get $inl url] : ""}]
        set alt [expr {[dict exists $inl alt] ? [dict get $inl alt] : ""}]
        set resolved [_resolveImagePath $url]
        if {$resolved eq "" || ![file exists $resolved] || ![file readable $resolved]} {
            # Kann nicht laden — alt-text als fallback
            lappend images [dict create kind text text "\[$alt\]" w 0 h $lh]
            continue
        }
        if {[catch {$pdf addImage $resolved} imgId]} {
            lappend images [dict create kind text text "\[$alt\]" w 0 h $lh]
            continue
        }
        lassign [$pdf getImageSize $imgId] origW origH

        # Skalierung: respektiere perImgW UND maxImgH
        set scaleW [expr {double($perImgW) / $origW}]
        set scaleH [expr {double($maxImgH) / $origH}]
        # Nicht hoch-skalieren über Original (Pixel-perfekt für Icons)
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

# Rendert die Bilder einer Zelle, mittig vertikal + horizontal
proc docir::pdf::_renderCellImages {info xCell yTop colW rowH} {
    variable st
    set pdf [dict get $st pdf]
    set images [dict get $info images]

    # Berechne gesamte Breite der Bilder + Zwischenräume
    set spacing 2
    set totalW 0
    foreach img $images {
        incr totalW [dict get $img w]
    }
    incr totalW [expr {([llength $images] - 1) * $spacing}]

    # Horizontal mittig in der Zelle
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
    # Block-Image. pdf4tcl::addImage lädt die Datei direkt von Disk
    # (PNG/JPG ohne Tk-Dependency). Wir lösen relative Pfade gegen
    # opts.root auf. Bei Fehler: Fallback auf [image: alt]-Marker.
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set lh [_lineHeight $fontSize]

    set m [dict get $node meta]
    set url [expr {[dict exists $m url] ? [dict get $m url] : ""}]
    set alt [expr {[dict exists $m alt] ? [dict get $m alt] : ""}]

    # Pfad gegen opts.root auflösen
    set resolvedPath [_resolveImagePath $url]
    set canLoad [expr {$resolvedPath ne "" && \
                       [file exists $resolvedPath] && \
                       [file readable $resolvedPath]}]

    if {$canLoad && [catch {$pdf addImage $resolvedPath} imgId] == 0} {
        # Bild geladen via pdf4tcl::addImage (kein Tk nötig)
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

# Löst einen Image-URL relativ zur opts.root auf.
# - Absolute Pfade (file:// oder /...) bleiben unverändert
# - HTTP/HTTPS-URLs sind nicht ladbar — return ""
# - Relative Pfade werden gegen opts.root aufgelöst
proc docir::pdf::_resolveImagePath {url} {
    variable opts
    if {$url eq ""} { return "" }

    # http(s) wird nicht über file-system geladen
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

    # Relativ — gegen opts.root auflösen
    set root [dict get $opts root]
    if {$root ne ""} {
        return [file join $root $url]
    }
    # Sonst: gegen cwd
    return $url
}

proc docir::pdf::_renderImageFallback {url alt} {
    # Wenn Bild nicht ladbar: textueller Marker
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
    # Trennlinie + alle footnote_defs als kleine Paragraphen
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
    set num [expr {[dict exists $m num] ? [dict get $m num] : "?"}]

    set body [_inlinesToText [dict get $node content]]
    set fullText "\[$num\] $body"
    set lines [_wrap $fullText [dict get $st contentW]]

    _setFont $fontSize
    foreach line $lines {
        _ensureSpace $lh
        set y [expr {[dict get $st y] + $fontSize}]
        $pdf text $line -x [dict get $st margin] -y $y
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
# TOC und Index (neu in 0.2)
# ============================================================
#
# Beide procs arbeiten auf st(headingsSeen), das vom _renderHeading
# waehrend des normalen Render-Laufs befuellt wird.
#
# _renderToc wird VOR dem Hauptteil aufgerufen — zu diesem Zeitpunkt
# ist headingsSeen noch LEER. Daher generiert _renderToc keinen
# Inhalt aus tatsaechlich gesehenen Headings, sondern aus einer
# vorab-gescannten Liste. Wir pre-scannen die DocIR-Sequenz im
# render-Wrapper und reichen die Heading-Liste durch.
#
# _renderIndex wird NACH dem Hauptteil aufgerufen — zu diesem Zeitpunkt
# enthaelt headingsSeen alle Headings mit korrekten Seitenzahlen.

# Helper: scannt DocIR-Sequenz und sammelt alle Headings als
# Liste von dicts {level, text} (ohne page/anchor — die kommen erst
# beim Render).
proc docir::pdf::_scanHeadings {ir} {
    set out {}
    foreach node $ir {
        if {[dict get $node type] eq "heading"} {
            set m [dict get $node meta]
            set lv [expr {[dict exists $m level] ? [dict get $m level] : 1}]
            set text [_inlinesToText [dict get $node content]]
            lappend out [dict create level $lv text $text]
        }
    }
    return $out
}

# Rendert das TOC vor dem Hauptteil. Eingabe: vorgescannte Heading-Liste.
# Ohne Seitenzahlen (Single-Pass-Limitation), aber hierarchisch eingerueckt.
proc docir::pdf::_renderToc {tocHeadings} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set tocDepth [dict get $opts tocDepth]
    set tocTitle [dict get $opts tocTitle]

    # TOC-Header (gross, fett)
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

    # TOC-Eintraege rendern
    set lh [_lineHeight $fontSize]
    foreach h $tocHeadings {
        set lv [dict get $h level]
        if {$lv > $tocDepth} continue

        _ensureSpace $lh

        # Indent nach Level: Level 1 = 0pt, Level 2 = 12pt, ...
        set indent [expr {($lv - 1) * 14}]
        set entryX [expr {[dict get $st margin] + $indent}]

        # Schriftgroesse: leicht reduziert mit Level
        set entryFontSize [expr {$fontSize + (2 - $lv)}]
        if {$entryFontSize < $fontSize - 1} { set entryFontSize [expr {$fontSize - 1}] }

        if {$lv == 1} {
            _setFont $entryFontSize bold
        } else {
            _setFont $entryFontSize ""
        }

        set sanitized [::pdf4tcllib::unicode::sanitize [dict get $h text]]

        # Wrap falls noetig
        set maxW [expr {[dict get $st contentW] - $indent}]
        set wrappedLines [_wrap $sanitized $maxW]
        foreach wline $wrappedLines {
            _ensureSpace $lh
            set wy [expr {[dict get $st y] + $entryFontSize}]
            $pdf text $wline -x $entryX -y $wy
            _advanceY $lh
        }
    }

    # Seitenumbruch nach TOC
    _newPage
}

# Rendert den Index am Ende. Wird AUFGERUFEN nach dem Hauptteil —
# headingsSeen ist dann komplett mit korrekten Seitenzahlen.
proc docir::pdf::_renderIndex {} {
    variable opts
    variable st
    set pdf [dict get $st pdf]
    set fontSize [dict get $opts fontSize]
    set indexTitle [dict get $opts indexTitle]

    # Nur Index-Eintraege (Begriffe auf indexLevel)
    set entries {}
    foreach h [dict get $st headingsSeen] {
        if {[dict get $h isIndexEntry]} {
            lappend entries [list \
                [dict get $h text] \
                [dict get $h page]]
        }
    }
    if {[llength $entries] == 0} {
        return
    }

    # Alphabetisch sortieren (case-insensitive)
    set entries [lsort -dictionary -index 0 $entries]

    # Neue Seite fuer Index
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

    # Bookmark fuer Index selbst (Top-Level)
    if {[dict get $opts bookmarks]} {
        catch {$pdf bookmarkAdd -title $indexTitle -level 0}
    }

    # Eintraege rendern, gruppiert nach Anfangsbuchstaben
    set lh [_lineHeight $fontSize]
    set lastInitial ""

    # Spaltenbreite fuer Seitennummer: rechtsbuendig
    set pageColW 32

    foreach e $entries {
        lassign $e text page

        # Anfangsbuchstabe (mit Umlaut-Normalisierung)
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
            $pdf text $initial -x $x -y $hy
            _advanceY [expr {$lh + 2}]
            set lastInitial $initial
        }

        _ensureSpace $lh

        # Eintrag: Text links, Seitennummer rechts mit gepunkteter Fuehrungslinie
        _setFont $fontSize ""

        set sanitized [::pdf4tcllib::unicode::sanitize $text]
        set ey [expr {[dict get $st y] + $fontSize}]
        set entryX [expr {$x + 8}]

        # Maximalbreite fuer Text (Seitennummer-Spalte freihalten)
        set maxTextW [expr {[dict get $st contentW] - $pageColW - 12}]

        # Bei zu langem Text: kuerzen mit "..."
        set displayText $sanitized
        set tw [$pdf getStringWidth $displayText]
        if {$tw > $maxTextW} {
            while {$tw > $maxTextW && [string length $displayText] > 4} {
                set displayText [string range $displayText 0 end-2]
                set tw [$pdf getStringWidth "${displayText}..."]
            }
            set displayText "${displayText}..."
        }

        $pdf text $displayText -x $entryX -y $ey

        # Seitennummer rechtsbuendig
        set pageX [expr {$x + [dict get $st contentW] - $pageColW}]
        set pageStr "$page"
        $pdf text $pageStr -x [expr {$pageX + $pageColW}] -y $ey -align right

        _advanceY $lh
    }
}

# ============================================================
# Render-Wrapper mit TOC + Index Unterstuetzung
# ============================================================

# Patch: render und renderToHandle erweitert um TOC + Index Phasen.
# Bei -generateToc wird _renderToc vor _renderInto gerufen
# (mit pre-scanned Heading-Liste).
# Bei -generateIndex wird _renderIndex nach _renderInto gerufen
# (nutzt die im Render gesammelten Headings + Seitenzahlen).
