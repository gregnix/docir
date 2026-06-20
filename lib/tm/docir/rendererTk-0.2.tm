# docir-renderer-tk-0.2.tm – DocIR → Tk Text Widget Renderer
#
# 0.2 (2026-06-20): math inline ($...$ / $$...$$); blockquote styling (indent +
#   background, inline styles preserved); deflist hanging indent (multi-def);
#   multi-paragraph list items from `blocks` + ul/ol hanging indent (bulletCont);
#   nested ul/ol indent by list indentLevel (bulletL$n); `tableframemax` option
#   (large tables fall back to fast ASCII even in `tablemode frame`).
#
# Feature-gleich mit nroffrenderer-0.1.tm.
# Rendert einen DocIR-Stream in ein Tk text-Widget.
# Tag-Namen kompatibel mit nroffrenderer.
#
# Namespace: ::docir::renderer::tk
# Tcl/Tk 8.6+ / 9.x kompatibel

package provide docir::rendererTk 0.2
package require docir 0.1
package require Tcl 8.6-
catch {package require docir 0.1}

namespace eval ::docir::renderer::tk {
    variable linkCallback    {}
    variable linkTagCounter  0
    variable currentLinkFg   "#0066cc"
    variable headingCallback {}
}

# ============================================================
# docir::renderer::tk::setHeadingCallback
#   cmd – proc die als: cmd text level markName aufgerufen wird
#   Wird beim Rendern jedes heading-Nodes aufgerufen.
#   Ermöglicht dem Aufrufer TOC-Aufbau und Anchor-Marks.
# ============================================================

proc docir::renderer::tk::_dictDef {d k {def ""}} {
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}

proc docir::renderer::tk::setHeadingCallback {cmd} {
    set ::docir::renderer::tk::headingCallback $cmd
}

# ============================================================
# docir::renderer::tk::setLinkCallback
#   cmd – proc die als: cmd name section aufgerufen wird
# ============================================================

proc docir::renderer::tk::setLinkCallback {cmd} {
    set ::docir::renderer::tk::linkCallback $cmd
}

# ============================================================
# docir::renderer::tk::render
#
#   textWidget  – Tk text Widget
#   ir          – DocIR-Stream
#   options     – Dict: linkCmd, fontSize, fontFamily, monoFamily,
#                        darkMode, colors
# ============================================================

proc docir::renderer::tk::render {textWidget ir {options {}}} {
    variable linkCallback
    variable linkTagCounter
    variable headingCallback

    set fontSize   [expr {[dict exists $options fontSize]   ? [dict get $options fontSize]   : 12}]
    set fontFamily [_dictDef $options fontFamily "TkDefaultFont"]
    set monoFamily [_dictDef $options monoFamily "TkFixedFont"]
    # A named font like "TkFixedFont" used as a family in a {family size} list
    # mis-resolves to the proportional default (Tk quirk), which breaks code
    # blocks, inline code, math and ASCII tables. Resolve it to the real
    # monospace family once. A real family name passes through unchanged.
    catch {set monoFamily [font actual $monoFamily -family]}
    set darkMode   [expr {[dict exists $options darkMode]   ? [dict get $options darkMode]   : 0}]
    set colors     [expr {[dict exists $options colors]     ? [dict get $options colors]     : {}}]

    # linkCmd als einmaliger Override
    if {[dict exists $options linkCmd]} {
        set linkCallback [dict get $options linkCmd]
    }

    # Tags konfigurieren
    docir::renderer::tk::_configureTags \
        $textWidget $fontSize $fontFamily $monoFamily $darkMode $colors

    $textWidget configure -state normal
    $textWidget delete 1.0 end

    docir::renderer::tk::_renderBlocks $textWidget $ir $options

    $textWidget configure -state disabled
    # Scroll to top
    $textWidget yview moveto 0
}

# _renderBlocks – iteriert über Blocks ohne textWidget zu resetten.
# Wird intern von render() aufgerufen, plus rekursiv für div-Container.
proc docir::renderer::tk::_renderBlocks {textWidget ir options} {
    variable linkCallback
    variable linkTagCounter
    variable headingCallback

    foreach node $ir {
        set type    [dict get $node type]
        set content [_dictDef $node content {}]
        set meta    [expr {[dict exists $node meta]    ? [dict get $node meta]    : {}}]

        switch $type {

            doc_header {
                set name    [expr {[dict exists $meta name]    ? [dict get $meta name]    : ""}]
                set section [_dictDef $meta section ""]
                set version [_dictDef $meta version ""]
                set part    [expr {[dict exists $meta part]    ? [dict get $meta part]    : ""}]
                if {$name ne ""} {
                    set title $name
                    if {$section ne ""} { append title "($section)" }
                    $textWidget insert end "$title" heading0
                    if {$version ne ""} {
                        $textWidget insert end "   $version" normal
                    }
                    $textWidget insert end "\n" normal
                    if {$part ne ""} {
                        $textWidget insert end "$part\n" normal
                    }
                    $textWidget insert end "\n" normal
                }
            }

            heading {
                set lvl [_dictDef $meta level 1]
                set tag "heading$lvl"
                set startIdx [$textWidget index "end-1c"]
                # Mark für TOC-Navigation setzen
                set headText ""
                foreach inline $content {
                    if {[dict exists $inline text]} { append headText [dict get $inline text] }
                }
                set markName "anchor_[regsub -all {[^a-zA-Z0-9]} $headText _]_[llength [$textWidget mark names]]"
                $textWidget mark set $markName $startIdx
                $textWidget mark gravity $markName left
                docir::renderer::tk::_insertInlines $textWidget $content
                $textWidget insert end "\n" normal
                # Tag auf die eingefügte Zeile setzen
                set endIdx [$textWidget index "end - 1 char"]
                $textWidget tag add $tag $startIdx $endIdx
                $textWidget insert end "\n" normal
                # TOC-Callback aufrufen
                if {$headingCallback ne ""} {
                    catch {uplevel #0 $headingCallback [list $headText $lvl $markName]}
                }
            }

            paragraph {
                if {[_dictDef $meta class ""] eq "blockquote"} {
                    set bqStart [$textWidget index "end - 1 char"]
                    $textWidget insert end "  " normal
                    docir::renderer::tk::_insertInlines $textWidget $content
                    $textWidget insert end "\n\n" normal
                    # Apply the blockquote tag over the whole paragraph so the
                    # margin/background covers inline-tagged spans too.
                    $textWidget tag add blockquote $bqStart "end - 1 char"
                } else {
                    $textWidget insert end "  " normal
                    docir::renderer::tk::_insertInlines $textWidget $content
                    $textWidget insert end "\n\n" normal
                }
            }

            pre {
                set txt ""
                foreach inline $content {
                    if {[dict exists $inline text]} { append txt [dict get $inline text] }
                }
                # Tab-Expansion
                set txt [string map {"\t" "        "} $txt]
                $textWidget insert end "\n" normal
                $textWidget insert end "$txt\n" pre
                $textWidget insert end "\n" normal
            }

            list {
                set kind [expr {[dict exists $meta kind]        ? [dict get $meta kind]        : "tp"}]
                set il   [_dictDef $meta indentLevel 0]
                set lvl  [expr {min($il, 4)}]
                set itemTag [expr {$lvl > 0 ? "ipItem$lvl" : "ipItem"}]

                foreach item $content {
                    # listItem-Node (neu) oder legacy {term desc}
                    if {[dict exists $item type] && [dict get $item type] eq "listItem"} {
                        set itemMeta [dict get $item meta]
                        set term [_dictDef $itemMeta term {}]
                        set itemKind [_dictDef $itemMeta kind $kind]
                        # Prefer per-paragraph `blocks` (multi-paragraph items),
                        # joining paragraphs with a blank line so the structure
                        # survives; fall back to the flattened `content`.
                        if {[dict exists $item blocks]} {
                            set desc {}
                            set firstPB 1
                            foreach pb [dict get $item blocks] {
                                if {![dict exists $pb content]} continue
                                if {$firstPB} { set firstPB 0 } else {
                                    lappend desc [dict create type linebreak]
                                    lappend desc [dict create type linebreak]
                                }
                                lappend desc {*}[dict get $pb content]
                            }
                        } else {
                            set desc [dict get $item content]
                        }
                    } elseif {[dict exists $item type]} {
                        # Schema-Verletzung: getypter Knoten der nicht listItem ist.
                        # Häufigster Fall: nested 'list' direkt im list.content
                        # (mdparser-typisch). Statt zu crashen: sichtbarer
                        # Hinweis im Output und nächstes Item.
                        set badType [dict get $item type]
                        $textWidget insert end \
                            "  ⚠ list.content enthält '$badType' statt 'listItem' (Schema-Verletzung)\n" \
                            normal
                        continue
                    } elseif {[dict exists $item term] && [dict exists $item desc]} {
                        # Legacy-Form: {term desc} ohne type-Feld
                        set term [dict get $item term]
                        set desc [dict get $item desc]
                        set itemKind $kind
                    } else {
                        # Unbekannte Form: weder listItem-Node noch legacy.
                        $textWidget insert end \
                            "  ⚠ Unbekannte Form für list-Item (kein type-Feld, kein term/desc)\n" \
                            normal
                        continue
                    }

                    switch $itemKind {
                        op {
                            # OP: dreispaltig – term sind Inline-Dicts mit | getrennt
                            # Im DocIR sind cmd/db/class bereits als separates Dict gespeichert
                            # (falls noch Pipe-Format: extrahieren)
                            set termText ""
                            if {[llength $term] > 0} {
                                foreach i $term {
                                    if {[dict exists $i text]} { append termText [dict get $i text] }
                                }
                            }
                            set parts [split $termText "|"]
                            $textWidget insert end "  Command-Line Name:\t" normal
                            $textWidget insert end "[lindex $parts 0]\n" strong
                            $textWidget insert end "  Database Name:\t"    normal
                            $textWidget insert end "[lindex $parts 1]\n" strong
                            $textWidget insert end "  Database Class:\t"   normal
                            $textWidget insert end "[lindex $parts 2]\n" strong
                            if {[llength $desc] > 0} {
                                $textWidget insert end "    " normal
                                docir::renderer::tk::_insertInlines $textWidget $desc
                                $textWidget insert end "\n" normal
                            }
                        }
                        ip {
                            # IP: term TAB desc – hanging indent
                            set termText ""
                            foreach i $term {
                                if {[dict exists $i text]} { append termText [dict get $i text] }
                            }
                            if {$termText eq ""} { set termText " " }
                            $textWidget insert end $termText $itemTag
                            if {[llength $desc] > 0} {
                                $textWidget insert end "\t" $itemTag
                                docir::renderer::tk::_insertInlines $textWidget $desc $itemTag
                            }
                            $textWidget insert end "\n" normal
                        }
                        ul -
                        ol {
                            # Bullet (ul) / placeholder bullet (ol) with a real
                            # hanging indent. Multi-paragraph items: first para
                            # follows the bullet; continuation paras align under
                            # the text via the bulletCont tag.
                            set ulStart [$textWidget index "end - 1 char"]
                            $textWidget insert end "• " listTerm
                            if {[dict exists $item blocks]} {
                                set firstPara 1
                                foreach pb [dict get $item blocks] {
                                    if {![dict exists $pb content]} continue
                                    if {$firstPara} {
                                        set firstPara 0
                                        docir::renderer::tk::_insertInlines \
                                            $textWidget [dict get $pb content]
                                    } else {
                                        $textWidget insert end "\n\n" normal
                                        set cStart [$textWidget index "end - 1 char"]
                                        docir::renderer::tk::_insertInlines \
                                            $textWidget [dict get $pb content]
                                        $textWidget tag add bulletContL$lvl \
                                            $cStart "end - 1 char"
                                    }
                                }
                            } elseif {[llength $desc] > 0} {
                                docir::renderer::tk::_insertInlines $textWidget $desc
                            }
                            $textWidget insert end "\n" normal
                            $textWidget tag add bulletL$lvl $ulStart "end - 1 char"
                        }
                        dl {
                            # Definition list: Term fett, Definition eingerückt
                            if {[llength $term] > 0} {
                                $textWidget insert end "  " normal
                                docir::renderer::tk::_insertInlines $textWidget $term listTerm
                                $textWidget insert end "\n" normal
                            }
                            if {[llength $desc] > 0} {
                                set dlStart [$textWidget index "end - 1 char"]
                                docir::renderer::tk::_insertInlines $textWidget $desc
                                $textWidget insert end "\n" normal
                                # Hanging indent across all definition lines.
                                $textWidget tag add dlDesc $dlStart "end - 1 char"
                            }
                        }
                        default {
                            # TP / AP: term auf eigener Zeile, desc eingerückt
                            if {[llength $term] > 0} {
                                $textWidget insert end "  " normal
                                docir::renderer::tk::_insertInlines $textWidget $term listTerm
                                $textWidget insert end "\n" normal
                            }
                            if {[llength $desc] > 0} {
                                $textWidget insert end "    " normal
                                docir::renderer::tk::_insertInlines $textWidget $desc
                                $textWidget insert end "\n" normal
                            }
                        }
                    }
                    $textWidget insert end "\n" normal
                }
            }

            blank {
                $textWidget insert end "\n" normal
            }

            hr {
                $textWidget insert end "[string repeat "─" 60]\n" normal
            }

            image {
                # Block-Image: image insert + caption
                set url [_dictDef $meta url ""]
                set alt [_dictDef $meta alt ""]
                if {$url ne "" && [file exists $url] && [file readable $url]} {
                    if {[catch {image create photo -file $url} imgName] == 0} {
                        $textWidget insert end "\n" normal
                        $textWidget image create end -image $imgName -align center
                        $textWidget insert end "\n" normal
                        if {$alt ne ""} {
                            $textWidget insert end "$alt\n" blockImageCaption
                        }
                        $textWidget insert end "\n" normal
                    } else {
                        $textWidget insert end "\[image: $alt\]\n\n" blockImageCaption
                    }
                } else {
                    $textWidget insert end "\[image: $alt\]\n\n" blockImageCaption
                }
            }

            footnote_section {
                # Trennlinie + alle defs
                $textWidget insert end "\n" normal
                $textWidget insert end "[string repeat "─" 30]\n\n" normal
                foreach def [dict get $node content] {
                    if {[dict get $def type] ne "footnote_def"} continue
                    set defMeta [dict get $def meta]
                    set num [_dictDef $defMeta num "?"]
                    $textWidget insert end "\[$num\] " footnoteSection
                    docir::renderer::tk::_insertInlines $textWidget [dict get $def content] footnoteSection
                    $textWidget insert end "\n" normal
                }
                $textWidget insert end "\n" normal
            }

            footnote_def {
                # top-level footnote_def (selten — meist innerhalb section)
                set num [_dictDef $meta num "?"]
                $textWidget insert end "\[$num\] " footnoteSection
                docir::renderer::tk::_insertInlines $textWidget $content footnoteSection
                $textWidget insert end "\n" normal
            }

            div {
                # div ist transparent — children rekursiv rendern.
                # Wichtig: _renderBlocks (NICHT render) nutzen, sonst
                # würde das Widget komplett gelöscht.
                docir::renderer::tk::_renderBlocks $textWidget $content $options
            }

            table {
                set _tmode [_dictDef $options tablemode "ascii"]
                # Native frame tables create one widget per cell, which is slow
                # for large tables (grid layout is O(rows*cols)). Tables with
                # more rows than `tableframemax` (default 30) fall back to the
                # fast ASCII renderer even in frame mode. `tableframemax 0` (or
                # negative) = no limit (always frame).
                set _tfmax  [_dictDef $options tableframemax 30]
                set _nrows  [llength [dict get $node content]]
                if {$_tmode eq "frame" && ($_tfmax <= 0 || $_nrows <= $_tfmax)} {
                    docir::renderer::tk::_renderTableFrame $textWidget $node $meta $options
                } else {
                # Variante A: Monospace-Tabelle mit Box-Rahmen. Tk-text hat
                # keine echten Tabellen; in Monospace stimmt die Ausrichtung,
                # Box-Zeichen geben Rahmen, Kopfzeile fett. Inline-Formatting
                # in Zellen wird zugunsten der Ausrichtung zu Plain-Text.
                set rows    [dict get $node content]
                set numCols [_dictDef $meta columns 1]
                if {$numCols < 1} { set numCols 1 }

                # Plain-Text-Gitter + Header-Flags
                set grid {}
                foreach row $rows {
                    set cells {}
                    set ci 0
                    foreach cell [dict get $row content] {
                        if {$ci >= $numCols} break
                        set t ""
                        foreach inl [dict get $cell content] {
                            if {[dict exists $inl text]} { append t [dict get $inl text] }
                        }
                        lappend cells [string map [list \n " " \t " "] $t]
                        incr ci
                    }
                    while {[llength $cells] < $numCols} { lappend cells "" }
                    set rmeta [_dictDef $row meta {}]
                    set isHead [expr {[dict exists $rmeta kind] && [dict get $rmeta kind] eq "header"}]
                    lappend grid [list $isHead $cells]
                }

                # Spaltenbreiten (Zeichen)
                set colW [lrepeat $numCols 1]
                foreach g $grid {
                    set ci 0
                    foreach c [lindex $g 1] {
                        if {[string length $c] > [lindex $colW $ci]} { lset colW $ci [string length $c] }
                        incr ci
                    }
                }

                # Monospace-Font aus dem pre-Tag ableiten (+ fette Variante)
                set mf [$textWidget tag cget pre -font]
                if {$mf eq ""} { set mf TkFixedFont }
                # monoFamily is resolved to a real family at render setup, so the
                # pre/code font ($mf, e.g. {DejaVu Sans Mono} 12) is genuine
                # monospace. Use it directly for the table so columns align with
                # code blocks. Monospace bold keeps the same advance width, so the
                # bold header stays aligned; only append "bold" when we have a
                # {family size} form to insert into.
                $textWidget tag configure tableBox -font $mf
                if {[llength $mf] >= 2} {
                    $textWidget tag configure tableHead -font [linsert $mf 2 bold]
                } else {
                    $textWidget tag configure tableHead -font $mf
                }

                # Rahmenlinien
                set top "\u250c"; set sep "\u251c"; set bot "\u2514"
                for {set i 0} {$i < $numCols} {incr i} {
                    set bar [string repeat "\u2500" [expr {[lindex $colW $i] + 2}]]
                    append top $bar; append sep $bar; append bot $bar
                    if {$i < $numCols - 1} {
                        append top "\u252c"; append sep "\u253c"; append bot "\u2534"
                    } else {
                        append top "\u2510"; append sep "\u2524"; append bot "\u2518"
                    }
                }

                set ind "  "
                $textWidget insert end "\n" normal
                $textWidget insert end "$ind$top\n" tableBox
                set prevHead 0; set first 1
                foreach g $grid {
                    lassign $g isHead cells
                    if {!$first && $prevHead && !$isHead} {
                        $textWidget insert end "$ind$sep\n" tableBox
                    }
                    set tag [expr {$isHead ? "tableHead" : "tableBox"}]
                    $textWidget insert end "$ind\u2502" tableBox
                    set ci 0
                    foreach c $cells {
                        set w [lindex $colW $ci]
                        $textWidget insert end " [format "%-${w}s" $c] " $tag
                        $textWidget insert end "\u2502" tableBox
                        incr ci
                    }
                    $textWidget insert end "\n" normal
                    set prevHead $isHead; set first 0
                }
                $textWidget insert end "$ind$bot\n" tableBox
                $textWidget insert end "\n" normal
                }
            }

            default {
                # Schema-only Marker (z.B. doc_meta) silent skippen.
                if {[::docir::isSchemaOnly $type]} {
                    continue
                }
                # paragraph mit class=blockquote
                set cls [_dictDef $meta class ""]
                if {$cls eq "blockquote"} {
                    $textWidget insert end "  │ " blockquoteBar
                    docir::renderer::tk::_insertInlines $textWidget $content blockquote
                    $textWidget insert end "\n" normal
                }
                # Andere unbekannte Typen: ignorieren
            }
        }
    }
}

# ============================================================
# _insertInlines – Inline-Sequenz in Text-Widget einfügen
# ============================================================

# Forward mouse-wheel events from an embedded widget and all its descendants
# to the text widget. Without this, the embedded table grabs the wheel event,
# so scrolling stops while the pointer is over the table. Mirrors the fix in
# mdstack::viewer. Prefers tkutils::tkuwheel::redirect when available, else
# falls back to local recursive bindings (no hard tkutils dependency).
proc docir::renderer::tk::_wheelToText {t w} {
    if {![catch {package require tkutils::tkuwheel}]} {
        ::tkutils::tkuwheel::redirect $t $w
        return
    }
    bind $w <MouseWheel> "$t yview scroll \[expr {-%D/30}] units"
    bind $w <Button-4>   "$t yview scroll -3 units"
    bind $w <Button-5>   "$t yview scroll 3 units"
    foreach child [winfo children $w] { docir::renderer::tk::_wheelToText $t $child }
}

# Variant B: a real embedded Tk table (ttk widgets in a grid) instead of the
# monospace box. Enabled via options "tablemode frame". Cell content is reduced
# to plain text (same tradeoff as the box variant); column alignments from
# meta.alignments are honoured. Grid lines come from a 1px container background
# showing through between cells.
proc docir::renderer::tk::_renderTableFrame {textWidget node meta options} {
    variable tableCounter
    if {![info exists tableCounter]} { set tableCounter 0 }
    set rows    [dict get $node content]
    set numCols [_dictDef $meta columns 1]
    if {$numCols < 1} { set numCols 1 }
    set aligns  [_dictDef $meta alignments {}]

    # theme: reuse the text widget's own colours so light/dark match
    set bodyBg [$textWidget cget -background]
    set fg     [$textWidget cget -foreground]
    set line   [expr {[dict exists $options darkMode] && [dict get $options darkMode] ? "#555555" : "#bbbbbb"}]
    set headBg [expr {[dict exists $options darkMode] && [dict get $options darkMode] ? "#2d2d2d" : "#f0f0f0"}]
    set fontSize   [expr {[dict exists $options fontSize]   ? [dict get $options fontSize]   : 12}]
    set fontFamily [_dictDef $options fontFamily "TkDefaultFont"]
    set cellFont [list $fontFamily $fontSize]
    set headFont [list $fontFamily $fontSize bold]

    set tf $textWidget.tbl[incr tableCounter]
    catch {destroy $tf}
    # container background = grid-line colour; cells leave a 1px gap to show it
    frame $tf -background $line -borderwidth 0

    set r 0
    foreach row $rows {
        set rmeta [_dictDef $row meta {}]
        set isHead [expr {[dict exists $rmeta kind] && [dict get $rmeta kind] eq "header"}]
        set c 0
        foreach cell [dict get $row content] {
            if {$c >= $numCols} break
            set txt ""
            foreach inl [dict get $cell content] {
                if {[dict exists $inl text]} { append txt [dict get $inl text] }
            }
            set txt [string map [list \t " "] $txt]
            switch -- [lindex $aligns $c] {
                center  { set anchor n;  set just center }
                right   { set anchor ne; set just right }
                default { set anchor nw; set just left }
            }
            set lbl $tf.c${r}_${c}
            label $lbl -text $txt -justify $just -anchor $anchor -wraplength 360 \
                -padx 6 -pady 3 -background [expr {$isHead ? $headBg : $bodyBg}] \
                -foreground $fg -font [expr {$isHead ? $headFont : $cellFont}]
            grid $lbl -row $r -column $c -sticky nsew -padx 1 -pady 1
            incr c
        }
        # pad short rows so the grid stays rectangular
        while {$c < $numCols} {
            set lbl $tf.c${r}_${c}
            label $lbl -text "" -background [expr {$isHead ? $headBg : $bodyBg}] -padx 6 -pady 3
            grid $lbl -row $r -column $c -sticky nsew -padx 1 -pady 1
            incr c
        }
        incr r
    }
    for {set c 0} {$c < $numCols} {incr c} { grid columnconfigure $tf $c -weight 1 }

    $textWidget insert end "\n" normal
    $textWidget window create end -window $tf -padx 2 -pady 2
    # keep wheel scrolling working while the pointer is over the embedded table
    docir::renderer::tk::_wheelToText $textWidget $tf
    $textWidget insert end "\n\n" normal
    return
}

proc docir::renderer::tk::_insertInlines {textWidget inlines {defaultTag normal}} {
    variable linkCallback
    variable linkTagCounter
    variable currentLinkFg

    foreach inline $inlines {
        if {![dict exists $inline type]} continue
        set itype [dict get $inline type]
        set text  [_dictDef $inline text ""]

        switch $itype {
            text      { $textWidget insert end $text $defaultTag }
            strong    { $textWidget insert end $text strong }
            emphasis  { $textWidget insert end $text emphasis }
            underline { $textWidget insert end $text underline }
            strike    { $textWidget insert end $text strike }
            code      { $textWidget insert end $text pre }
            linebreak { $textWidget insert end "\n" $defaultTag }
            softbreak { $textWidget insert end " " $defaultTag }
            span {
                # span: zeigt Text mit class als Tag-Name "span_class".
                # Wir konfigurieren keinen speziellen Style — kann der
                # Konsument tun via $textWidget tag configure span_FOO.
                set cls [_dictDef $inline class ""]
                set spanTag $defaultTag
                if {$cls ne ""} {
                    set spanTag "span_$cls"
                }
                $textWidget insert end $text $spanTag
            }
            image {
                # Inline-Image. Tk-Text kann Bilder via image create einbetten.
                # Wir versuchen das Bild lokal zu laden; bei Fehlschlag
                # fallback auf "[image: alt]" Plain-Text.
                set url [_dictDef $inline url ""]
                set alt [_dictDef $inline text ""]
                if {$url ne "" && [file exists $url] && [file readable $url]} {
                    if {[catch {image create photo -file $url} imgName] == 0} {
                        $textWidget image create end -image $imgName -align center
                        # Image-Name speichern für Cleanup
                        $textWidget tag add docir-image-track end-2c end-1c
                    } else {
                        $textWidget insert end "\[image: $alt\]" $defaultTag
                    }
                } else {
                    $textWidget insert end "\[image: $alt\]" $defaultTag
                }
            }
            footnote_ref {
                # Hochgestellt mit kleinerer Schrift via footnoteRef-Tag.
                # Format: [N]
                set id [_dictDef $inline id ""]
                set num [_dictDef $inline text "?"]
                $textWidget insert end "\[$num\]" footnoteRef
            }
            link {
                set name    [expr {[dict exists $inline name]    ? [dict get $inline name]    : $text}]
                set section [_dictDef $inline section "n"]
                set href    [expr {[dict exists $inline href]    ? [dict get $inline href]    : ""}]
                # Eindeutiger Tag-Counter (ein Link kann mehrfach vorkommen)
                set tagName "link_[incr linkTagCounter]"
                $textWidget tag configure $tagName \
                    -foreground $currentLinkFg \
                    -underline 1
                $textWidget insert end $text $tagName
                $textWidget tag bind $tagName <Enter> \
                    [list $textWidget configure -cursor hand2]
                $textWidget tag bind $tagName <Leave> \
                    [list $textWidget configure -cursor {}]
                if {$href ne ""} {
                    # URL-Link: xdg-open (Linux) oder open (macOS)
                    set opener [expr {$::tcl_platform(os) eq "Darwin" ? "open" : "xdg-open"}]
                    $textWidget tag bind $tagName <ButtonRelease-1> \
                        [list catch [list exec $opener $href &]]
                } elseif {$linkCallback ne {}} {
                    $textWidget tag bind $tagName <ButtonRelease-1> \
                        [list {*}$linkCallback $name $section]
                }
            }
            math {
                # Tk cannot typeset LaTeX; show the source with Pandoc-style
                # delimiters ($...$ inline, $$...$$ display) in the math tag.
                set disp [_dictDef $inline display 0]
                set d [expr {[string is true -strict $disp] || $disp == 1 ? "\$\$" : "\$"}]
                $textWidget insert end "$d$text$d" math
            }
            default { $textWidget insert end $text $defaultTag }
        }
    }
}

# ============================================================
# _configureTags – Text-Widget Tags einrichten
# ============================================================

proc docir::renderer::tk::_configureTags {w fontSize fontFamily monoFamily darkMode {colors {}}} {
    # Farben aus colors-Dict (Dark-Mode-Support) oder Defaults
    set bg     [expr {[dict exists $colors bg]     ? [dict get $colors bg]     : \
                     ($darkMode ? "#1e1e1e" : "#ffffff")}]
    set fg     [expr {[dict exists $colors fg]     ? [dict get $colors fg]     : \
                     ($darkMode ? "#d4d4d4" : "#000000")}]
    set headFg [_dictDef $colors headFg [expr {$darkMode ? "#9cdcfe" : "#003366"}]]
    set codeBg [_dictDef $colors codeBg [expr {$darkMode ? "#2d2d2d" : "#f0f0f0"}]]
    set linkFg [_dictDef $colors linkFg [expr {$darkMode ? "#4ec9b0" : "#0066cc"}]]

    # Link-Farbe in Namespace-Variable speichern (für renderInlines)
    set ::docir::renderer::tk::currentLinkFg $linkFg

    $w configure -background $bg -foreground $fg

    $w tag configure normal    -font [list $fontFamily $fontSize]              -foreground $fg
    $w tag configure heading0  -font [list $fontFamily [expr {$fontSize+4}] bold] -foreground $headFg
    $w tag configure heading1  -font [list $fontFamily [expr {$fontSize+2}] bold] -foreground $headFg
    $w tag configure heading2  -font [list $fontFamily [expr {$fontSize+1}] bold] -foreground $headFg
    $w tag configure strong    -font [list $fontFamily $fontSize bold]
    $w tag configure emphasis  -font [list $fontFamily $fontSize italic]
    $w tag configure underline -font [list $fontFamily $fontSize] -underline 1
    $w tag configure strike    -font [list $fontFamily $fontSize] -overstrike 1
    $w tag configure pre       -font [list $monoFamily $fontSize] -background $codeBg
    $w tag configure listTerm  -font [list $fontFamily $fontSize bold]
    # Definition-list description: real hanging indent via margins, so that
    # multi-paragraph definitions and wrapped lines all stay indented (a leading
    # space prefix only indents the first line).
    $w tag configure dlDesc     -lmargin1 36 -lmargin2 36
    $w tag configure link      -foreground $linkFg -underline 1

    # Math: rendered as its source between $...$ delimiters (Tk cannot render
    # LaTeX), in the mono family + italic so it reads as a formula.
    $w tag configure math      -font [list $monoFamily $fontSize italic] \
        -foreground [_dictDef $colors mathFg [expr {$darkMode ? "#c586c0" : "#6f42c1"}]]

    # Footnote-Reference: hochgestellt + kleiner
    set fnSize [expr {max(8, $fontSize - 3)}]
    $w tag configure footnoteRef -font [list $fontFamily $fontSize] \
        -offset [expr {$fontSize / 2}] -foreground $linkFg

    # Footnote-Section: kleinerer Font für die Definitionen
    $w tag configure footnoteSection -font [list $fontFamily $fnSize] \
        -lmargin1 0 -lmargin2 20

    # Block-Image: italic Caption-Style
    $w tag configure blockImageCaption \
        -font [list $fontFamily [expr {max(9, $fontSize - 2)}] italic] \
        -foreground "#666666"

    # Div-Container: einfaches default-Tag, kann via tag configure
    # vom Konsumenten gestyled werden (z.B. div_warning)

    # IP-Item Tags: bis Level 4
    $w tag configure ipItem \
        -lmargin1 20 -lmargin2 80 \
        -tabs {80}
    for {set i 1} {$i <= 4} {incr i} {
        set lm  [expr {$i * 20}]
        set lm2 [expr {$lm + 60}]
        $w tag configure ipItem$i \
            -lmargin1 $lm -lmargin2 $lm2 \
            -tabs [list $lm2]
    }

    # Blockquote: linker Balken + Einrückung + leichter Hintergrund.
    # (Kein -font, damit Inline-Fett/Kursiv/Links im Zitat erhalten bleiben.)
    $w tag configure blockquoteBar \
        -foreground $headFg \
        -font [list $fontFamily $fontSize bold]
    $w tag configure blockquote \
        -lmargin1 25 -lmargin2 25 -rmargin 15 \
        -foreground [_dictDef $colors quoteFg [expr {$darkMode ? "#b0b0b0" : "#555555"}]] \
        -background [_dictDef $colors quoteBg [expr {$darkMode ? "#262626" : "#f6f6f6"}]]

    # ul/ol Bullets: leichte Einrückung. bulletL$n / bulletContL$n staffeln je
    # indentLevel (20px pro Stufe, wie ipItem), damit verschachtelte Listen
    # optisch tiefer einrücken. bullet/bulletCont bleiben als Level-0-Alias.
    $w tag configure bullet \
        -lmargin1 10 -lmargin2 25
    # Continuation paragraphs of a bullet item: same indent on first + wrapped
    # lines (lmargin1 == lmargin2), so they align under the bullet's text
    # instead of resetting to the first-line margin.
    $w tag configure bulletCont \
        -lmargin1 25 -lmargin2 25
    for {set i 0} {$i <= 4} {incr i} {
        set base [expr {$i * 20}]
        $w tag configure bulletL$i \
            -lmargin1 [expr {$base + 10}] -lmargin2 [expr {$base + 25}]
        $w tag configure bulletContL$i \
            -lmargin1 [expr {$base + 25}] -lmargin2 [expr {$base + 25}]
    }
}
