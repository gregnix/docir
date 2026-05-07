# docir-renderer-tk-0.1.tm – DocIR → Tk Text Widget Renderer
#
# Feature-gleich mit nroffrenderer-0.1.tm.
# Rendert einen DocIR-Stream in ein Tk text-Widget.
# Tag-Namen kompatibel mit nroffrenderer.
#
# Namespace: ::docir::renderer::tk
# Tcl/Tk 8.6+ / 9.x kompatibel

package provide docir::rendererTk 0.1
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
    set fontFamily [expr {[dict exists $options fontFamily] ? [dict get $options fontFamily] : "TkDefaultFont"}]
    set monoFamily [expr {[dict exists $options monoFamily] ? [dict get $options monoFamily] : "TkFixedFont"}]
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
        set content [expr {[dict exists $node content] ? [dict get $node content] : {}}]
        set meta    [expr {[dict exists $node meta]    ? [dict get $node meta]    : {}}]

        switch $type {

            doc_header {
                set name    [expr {[dict exists $meta name]    ? [dict get $meta name]    : ""}]
                set section [expr {[dict exists $meta section] ? [dict get $meta section] : ""}]
                set version [expr {[dict exists $meta version] ? [dict get $meta version] : ""}]
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
                set lvl [expr {[dict exists $meta level] ? [dict get $meta level] : 1}]
                set tag "heading$lvl"
                set startIdx [$textWidget index "end"]
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
                $textWidget insert end "  " normal
                docir::renderer::tk::_insertInlines $textWidget $content
                $textWidget insert end "\n\n" normal
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
                set il   [expr {[dict exists $meta indentLevel] ? [dict get $meta indentLevel] : 0}]
                set lvl  [expr {min($il, 4)}]
                set itemTag [expr {$lvl > 0 ? "ipItem$lvl" : "ipItem"}]

                foreach item $content {
                    # listItem-Node (neu) oder legacy {term desc}
                    if {[dict exists $item type] && [dict get $item type] eq "listItem"} {
                        set itemMeta [dict get $item meta]
                        set term [expr {[dict exists $itemMeta term] ? [dict get $itemMeta term] : {}}]
                        set desc [dict get $item content]
                        set itemKind [expr {[dict exists $itemMeta kind] ? [dict get $itemMeta kind] : $kind}]
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
                        ul {
                            # Unordered list: Bullet + Text
                            $textWidget insert end "  • " listTerm
                            if {[llength $desc] > 0} {
                                docir::renderer::tk::_insertInlines $textWidget $desc
                            }
                            $textWidget insert end "\n" normal
                        }
                        ol {
                            # Ordered list: Nummer wird vom Aufrufer erwartet,
                            # hier Bullet als Platzhalter
                            $textWidget insert end "  • " listTerm
                            if {[llength $desc] > 0} {
                                docir::renderer::tk::_insertInlines $textWidget $desc
                            }
                            $textWidget insert end "\n" normal
                        }
                        dl {
                            # Definition list: Term fett, Definition eingerückt
                            if {[llength $term] > 0} {
                                $textWidget insert end "  " normal
                                docir::renderer::tk::_insertInlines $textWidget $term listTerm
                                $textWidget insert end "\n" normal
                            }
                            if {[llength $desc] > 0} {
                                $textWidget insert end "      " normal
                                docir::renderer::tk::_insertInlines $textWidget $desc
                                $textWidget insert end "\n" normal
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
                set url [expr {[dict exists $meta url] ? [dict get $meta url] : ""}]
                set alt [expr {[dict exists $meta alt] ? [dict get $meta alt] : ""}]
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
                    set num [expr {[dict exists $defMeta num] ? [dict get $defMeta num] : "?"}]
                    $textWidget insert end "\[$num\] " footnoteSection
                    docir::renderer::tk::_insertInlines $textWidget [dict get $def content] footnoteSection
                    $textWidget insert end "\n" normal
                }
                $textWidget insert end "\n" normal
            }

            footnote_def {
                # top-level footnote_def (selten — meist innerhalb section)
                set num [expr {[dict exists $meta num] ? [dict get $meta num] : "?"}]
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
                # Tabelle als ausgerichtete Spalten im Text-Widget rendern.
                # Tk-text hat keine echten Tabellen — wir bauen eine
                # monospaced-Repräsentation mit gleicher Spaltenbreite,
                # damit die Spalten optisch ausgerichtet sind.
                set rows [dict get $node content]
                set numCols [expr {[dict exists $meta columns] ? [dict get $meta columns] : 1}]

                # 1) Spaltenbreiten berechnen (Plain-Text-Länge pro Zelle)
                set colWidths [lrepeat $numCols 0]
                foreach row $rows {
                    set ci 0
                    foreach cell [dict get $row content] {
                        if {$ci >= $numCols} break
                        set txt ""
                        foreach inl [dict get $cell content] {
                            if {[dict exists $inl text]} { append txt [dict get $inl text] }
                        }
                        set len [string length $txt]
                        if {$len > [lindex $colWidths $ci]} {
                            lset colWidths $ci $len
                        }
                        incr ci
                    }
                }

                # 2) Zeilen rendern. Zellen-Inhalte werden mit ihren
                #    Inline-Tags (z.B. strong) eingefügt, das Auffüll-
                #    Padding kommt als Plain-Text danach.
                $textWidget insert end "\n" normal
                foreach row $rows {
                    $textWidget insert end "  " normal
                    set ci 0
                    foreach cell [dict get $row content] {
                        if {$ci >= $numCols} break
                        # Plain-Text der Zelle für Längen-Berechnung
                        set cellTxt ""
                        foreach inl [dict get $cell content] {
                            if {[dict exists $inl text]} { append cellTxt [dict get $inl text] }
                        }
                        # Zelle inklusive Inline-Formatting einfügen
                        docir::renderer::tk::_insertInlines $textWidget [dict get $cell content]
                        # Padding bis zur Spaltenbreite + Trenn-Spaces.
                        # Letzte Spalte braucht kein Padding.
                        if {$ci < $numCols - 1} {
                            set padLen [expr {[lindex $colWidths $ci] - [string length $cellTxt] + 3}]
                            if {$padLen < 1} { set padLen 1 }
                            $textWidget insert end [string repeat " " $padLen] normal
                        }
                        incr ci
                    }
                    $textWidget insert end "\n" normal
                }
                $textWidget insert end "\n" normal
            }

            default {
                # Schema-only Marker (z.B. doc_meta) silent skippen.
                if {[::docir::isSchemaOnly $type]} {
                    continue
                }
                # paragraph mit class=blockquote
                set cls [expr {[dict exists $meta class] ? [dict get $meta class] : ""}]
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

proc docir::renderer::tk::_insertInlines {textWidget inlines {defaultTag normal}} {
    variable linkCallback
    variable linkTagCounter
    variable currentLinkFg

    foreach inline $inlines {
        if {![dict exists $inline type]} continue
        set itype [dict get $inline type]
        set text  [expr {[dict exists $inline text] ? [dict get $inline text] : ""}]

        switch $itype {
            text      { $textWidget insert end $text $defaultTag }
            strong    { $textWidget insert end $text strong }
            emphasis  { $textWidget insert end $text emphasis }
            underline { $textWidget insert end $text underline }
            strike    { $textWidget insert end $text strike }
            code      { $textWidget insert end $text pre }
            linebreak { $textWidget insert end "\n" $defaultTag }
            span {
                # span: zeigt Text mit class als Tag-Name "span_class".
                # Wir konfigurieren keinen speziellen Style — kann der
                # Konsument tun via $textWidget tag configure span_FOO.
                set cls [expr {[dict exists $inline class] ? [dict get $inline class] : ""}]
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
                set url [expr {[dict exists $inline url] ? [dict get $inline url] : ""}]
                set alt [expr {[dict exists $inline text] ? [dict get $inline text] : ""}]
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
                set id [expr {[dict exists $inline id] ? [dict get $inline id] : ""}]
                set num [expr {[dict exists $inline text] ? [dict get $inline text] : "?"}]
                $textWidget insert end "\[$num\]" footnoteRef
            }
            link {
                set name    [expr {[dict exists $inline name]    ? [dict get $inline name]    : $text}]
                set section [expr {[dict exists $inline section] ? [dict get $inline section] : "n"}]
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
    set headFg [expr {[dict exists $colors headFg] ? [dict get $colors headFg] : \
                     ($darkMode ? "#9cdcfe" : "#003366")}]
    set codeBg [expr {[dict exists $colors codeBg] ? [dict get $colors codeBg] : \
                     ($darkMode ? "#2d2d2d" : "#f0f0f0")}]
    set linkFg [expr {[dict exists $colors linkFg] ? [dict get $colors linkFg] : \
                     ($darkMode ? "#4ec9b0" : "#0066cc")}]

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
    $w tag configure link      -foreground $linkFg -underline 1

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

    # Blockquote: linker Balken + Einrückung
    $w tag configure blockquoteBar \
        -foreground $headFg \
        -font [list $fontFamily $fontSize bold]
    $w tag configure blockquote \
        -lmargin1 20 -lmargin2 20 \
        -foreground [expr {$fg}]

    # ul/ol Bullets: leichte Einrückung
    $w tag configure bullet \
        -lmargin1 10 -lmargin2 25
}
