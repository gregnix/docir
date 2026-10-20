# docir-block-0.1.tm -- place a DocIR fragment into a rectangle
#
# The difference to docir::pdf: there a whole document flows across pages.
# Here a fragment is assigned a fixed rectangle given in millimetres, which
# is what a label or form layout needs.
#
#   docir::block::pdf $pdf $ir -x 3 -y 39 -w 30 -h 14 ?-option value ...?
#       -> dict: used <mm> lines <n> overflow <0|1> truncated <n>
#
#   docir::block::measure $pdf $ir -w 30 ?...?     ;# measures, draws nothing
#       -> same dict; "used" is the height the fragment needs
#
# UNITS. Geometry in millimetres, font sizes in points. Internally everything
# is computed in points because pdf4tcl reads the font size in the unit that
# is CONFIGURED on the object: with `-unit mm`, `setFont 9` means nine
# millimetres, not nine points. The renderer therefore requires a pdf4tcl
# object in the default unit (points) and checks for it.
#
# IMAGES. The `image` block embeds PNG and JPEG via pdf4tcl. SVG is NOT
# handled here on purpose: rasterizing it would require Tk, and this module
# stays Tk-free so its tests run headless. Callers that want SVG rasterize it
# first (Tk 9: `image create photo -format svg`, then write a PNG) and pass
# the resulting file.
#
# Copyright (c) 2026. BSD 2-Clause.

package require Tcl 8.6-
package require docir 0.1
package require pdf4tcl 0.9

package provide docir::block 0.1

namespace eval ::docir::block {
    variable version 0.1

    # mm -> pt
    variable MM 2.8346456692913385      ;# 72/25.4

    variable defaults {
        -x          0
        -y          0
        -w          50
        -h          0
        -size       9
        -font       Helvetica
        -mono       Courier
        -leading    1.25
        -align      left
        -paraskip   0.35
        -clip       1
        -dryrun     0
        -headscale  {1 1.6  2 1.4  3 1.25  4 1.1  5 1.0  6 1.0}
        -bullet     "\u2022 "
        -indent     4
    }
}

proc ::docir::block::mm2pt {mm} { variable MM ; expr {$mm * $MM} }
proc ::docir::block::pt2mm {pt} { variable MM ; expr {$pt / $MM} }

# --------------------------------------------------------------------- Fonts
# Derive the pdf4tcl font name from a style. The base fonts follow the
# naming convention Family[-Bold][-Oblique]; Courier and Helvetica use
# "Oblique" while Times uses "Italic" -- hence the special case.
proc ::docir::block::fontName {style base mono} {
    set fam [expr {[dict get $style mono] ? $mono : $base}]
    set b [dict get $style bold]
    set i [dict get $style italic]
    if {!$b && !$i} { return $fam }
    if {[string match -nocase "Times*" $fam]} {
        if {$b && $i} { return "Times-BoldItalic" }
        if {$b}       { return "Times-Bold" }
        return "Times-Italic"
    }
    if {$b && $i} { return "${fam}-BoldOblique" }
    if {$b}       { return "${fam}-Bold" }
    return "${fam}-Oblique"
}

proc ::docir::block::newStyle {} {
    return [dict create bold 0 italic 0 underline 0 strike 0 mono 0]
}

# ------------------------------------------------------------------- Inlines
# Inlines -> flat list of runs {text style}. The IR is flat
# (`{type strong text "bold"}`), but some producers emit nested `content`
# lists -- both forms are accepted.
proc ::docir::block::runs {inlines {style {}}} {
    if {$style eq ""} { set style [newStyle] }
    set out {}
    foreach in $inlines {
        if {![dict exists $in type]} { continue }
        set t [dict get $in type]
        set st $style
        switch -- $t {
            strong    { dict set st bold 1 }
            emphasis  { dict set st italic 1 }
            underline { dict set st underline 1 }
            strike    { dict set st strike 1 }
            code      { dict set st mono 1 }
            link      { dict set st underline 1 }
        }
        # span/link from inside ** or *: optional field `style`
        foreach w [expr {[dict exists $in style] ? [dict get $in style] : {}}] {
            switch -- $w {
                strong   { dict set st bold 1 }
                emphasis { dict set st italic 1 }
                strike   { dict set st strike 1 }
            }
        }
        switch -- $t {
            linebreak { lappend out [list "\n" $style] ; continue }
            softbreak { lappend out [list " "  $style] ; continue }
            image {
                # Inline images are not drawn inside a text run. The spec
                # asks sinks that cannot render them to emit `[image: alt]`.
                set a [expr {[dict exists $in text] ? [dict get $in text] : ""}]
                lappend out [list "\[image: $a\]" $style] ; continue
            }
            footnote_ref - math {
                # Not renderable inside a text block. Leave a visible marker
                # instead of dropping it silently.
                lappend out [list "\[$t\]" $style] ; continue
            }
        }
        if {[dict exists $in content] && [llength [dict get $in content]] > 0
            && [lindex [dict get $in content] 0] ne ""} {
            # nested form
            set inner [dict get $in content]
            if {[llength $inner] && [dict exists [lindex $inner 0] type]} {
                lappend out {*}[runs $inner $st]
                continue
            }
        }
        if {[dict exists $in text]} {
            lappend out [list [dict get $in text] $st]
        }
    }
    return $out
}

# ---------------------------------------------------------------- Line break
# Break runs into lines. Every word is measured in the very font it will be
# drawn in -- measuring in another font makes the line overflow.
proc ::docir::block::wrap {pdf runs wpt size base mono} {
    set lines {}
    set cur {} ; set curw 0.0
    foreach run $runs {
        lassign $run text st
        # Split on explicit newlines. The comparison must be positional, not
        # by value: a run that IS a newline splits into two empty strings,
        # and comparing them by value loses the break entirely.
        set parts [split $text "\n"]
        set first 1
        foreach part $parts {
            if {!$first} {
                lappend lines $cur ; set cur {} ; set curw 0.0
            }
            set first 0
            $pdf setFont $size [fontName $st $base $mono]
            foreach word [regexp -all -inline {\S+\s*|\s+} $part] {
                set ww [$pdf getStringWidth $word]
                if {$curw + $ww > $wpt && [llength $cur]} {
                    # Line is full. Trailing blanks do not move to the next.
                    lappend lines $cur
                    set cur {} ; set curw 0.0
                    set word [string trimleft $word]
                    if {$word eq ""} { continue }
                    set ww [$pdf getStringWidth $word]
                }
                lappend cur [list $word $st $ww]
                set curw [expr {$curw + $ww}]
            }
        }
    }
    if {[llength $cur]} { lappend lines $cur }
    return $lines
}

proc ::docir::block::lineWidth {line} {
    set w 0.0
    foreach it $line { set w [expr {$w + [lindex $it 2]}] }
    return $w
}

# Draw one line. y is the baseline in points, measured from the top.
proc ::docir::block::drawLine {pdf line xpt ypt wpt align size base mono} {
    set lw [lineWidth $line]
    switch -- $align {
        center  { set x [expr {$xpt + ($wpt-$lw)/2.0}] }
        right   { set x [expr {$xpt + $wpt-$lw}] }
        default { set x $xpt }
    }
    foreach it $line {
        lassign $it word st ww
        set fn [fontName $st $base $mono]
        $pdf setFont $size $fn
        $pdf text $word -x $x -y $ypt
        if {[dict get $st underline]} {
            $pdf setLineWidth [expr {$size*0.05}]
            $pdf line $x [expr {$ypt+$size*0.12}] [expr {$x+$ww}] [expr {$ypt+$size*0.12}]
        }
        if {[dict get $st strike]} {
            $pdf setLineWidth [expr {$size*0.05}]
            $pdf line $x [expr {$ypt-$size*0.28}] [expr {$x+$ww}] [expr {$ypt-$size*0.28}]
        }
        set x [expr {$x + $ww}]
    }
}

# -------------------------------------------------------------------- Blocks
proc ::docir::block::pdf {pdfobj ir args} {
    variable defaults
    set o [dict merge $defaults $args]

    if {[$pdfobj cget -unit] ne "p"} {
        return -code error -errorcode {DOCIRBLOCK UNIT} \
            "pdf4tcl object must use the default unit (points),\
             found: [$pdfobj cget -unit]. Font sizes would otherwise be\
             read as millimetres."
    }

    set xpt  [mm2pt [dict get $o -x]]
    set ytop [mm2pt [dict get $o -y]]
    set wpt  [mm2pt [dict get $o -w]]
    set hpt  [expr {[dict get $o -h] > 0 ? [mm2pt [dict get $o -h]] : 0}]
    set base [dict get $o -font]
    set mono [dict get $o -mono]
    set bs   [dict get $o -size]
    set lead [dict get $o -leading]
    set dry  [dict get $o -dryrun]
    set clip [dict get $o -clip]

    set y $ytop
    set nlines 0 ; set overflow 0 ; set truncated 0

    foreach blk $ir {
        if {![dict exists $blk type]} { continue }
        set type [dict get $blk type]
        set meta [expr {[dict exists $blk meta] ? [dict get $blk meta] : {}}]
        set content [expr {[dict exists $blk content] ? [dict get $blk content] : {}}]

        set size $bs
        set align [dict get $o -align]
        set indent 0
        set prefix ""
        set forceMono 0

        switch -- $type {
            heading {
                set lvl [expr {[dict exists $meta level] ? [dict get $meta level] : 1}]
                set sc [dict get $o -headscale]
                set f [expr {[dict exists $sc $lvl] ? [dict get $sc $lvl] : 1.0}]
                set size [expr {$bs * $f}]
            }
            pre       { set forceMono 1 ; set size [expr {$bs*0.9}] }
            blank     { set y [expr {$y + $bs*$lead}] ; continue }
            hr {
                set y [expr {$y + $bs*$lead*0.5}]
                if {!$dry} {
                    $pdfobj setLineWidth [expr {$bs*0.04}]
                    $pdfobj line $xpt $y [expr {$xpt+$wpt}] $y
                }
                set y [expr {$y + $bs*$lead*0.5}]
                continue
            }
            list {
                foreach item $content {
                    if {![dict exists $item type]} { continue }
                    set ic [expr {[dict exists $item content] ? [dict get $item content] : {}}]
                    # Pass the remaining height down. Without it a list item
                    # can never overflow and the box wrongly reports that
                    # everything fits.
                    set resth [expr {$hpt > 0 ? [pt2mm [expr {$hpt - ($y-$ytop)}]] : 0}]
                    if {$resth < 0} { set resth 0.01 }
                    set sub [pdf $pdfobj [list [dict create type paragraph content $ic meta {}]] \
                        {*}[dict merge $o [dict create \
                            -x [expr {[dict get $o -x] + [dict get $o -indent]}] \
                            -y [pt2mm $y] \
                            -w [expr {[dict get $o -w] - [dict get $o -indent]}] \
                            -h $resth -dryrun $dry]]]
                    if {[dict get $sub overflow]} {
                        set overflow 1
                        incr truncated [dict get $sub truncated]
                    }
                    # Bullet goes on the first line
                    if {!$dry && [dict get $sub lines] > 0} {
                        $pdfobj setFont $bs $base
                        $pdfobj text [dict get $o -bullet] -x $xpt \
                            -y [expr {$y + $bs}]
                    }
                    set y [expr {$y + [mm2pt [dict get $sub used]]}]
                    incr nlines [dict get $sub lines]
                }
                set y [expr {$y + $bs*[dict get $o -paraskip]}]
                continue
            }
            image {
                # Standalone image block. meta: url, alt, title.
                # Scaled to fit -w, aspect preserved; if -h is set and the
                # scaled image would be taller, it is scaled down to -h
                # instead. PNG and JPEG only -- see the note on SVG below.
                set url [expr {[dict exists $meta url] ? [dict get $meta url] : ""}]
                set alt [expr {[dict exists $meta alt] ? [dict get $meta alt] : ""}]
                if {$url eq "" || ![file readable $url]} {
                    # Missing file must be visible, not silently skipped:
                    # on a label a blank space looks like a design decision.
                    set rr [runs [list [dict create type text \
                        text "\[image: [expr {$alt ne "" ? $alt : $url}]\]"]] [newStyle]]
                    set lines [wrap $pdfobj $rr $wpt $bs $base $mono]
                    foreach line $lines {
                        if {!$dry} {
                            drawLine $pdfobj $line $xpt [expr {$y+$bs}] \
                                $wpt $align $bs $base $mono
                        }
                        set y [expr {$y + $bs*$lead}]
                        incr nlines
                    }
                    set y [expr {$y + $bs*[dict get $o -paraskip]}]
                    continue
                }
                if {[catch {
                    set iid [$pdfobj addImage $url]
                    lassign [$pdfobj getImageSize $iid] ipx ipy
                } err]} {
                    return -code error -errorcode {DOCIRBLOCK IMAGE} \
                        "cannot load image '$url': $err"
                }
                set zw $wpt
                set zh [expr {$zw * $ipy / double($ipx)}]
                if {$hpt > 0} {
                    set rest [expr {$hpt - ($y - $ytop)}]
                    if {$zh > $rest} {
                        if {$rest <= 0} {
                            set overflow 1 ; incr truncated ; continue
                        }
                        set zh $rest
                        set zw [expr {$zh * $ipx / double($ipy)}]
                        set overflow 1
                    }
                }
                if {!$dry} {
                    switch -- $align {
                        center  { set ix [expr {$xpt + ($wpt-$zw)/2.0}] }
                        right   { set ix [expr {$xpt + $wpt-$zw}] }
                        default { set ix $xpt }
                    }
                    $pdfobj putImage $iid $ix $y -width $zw -height $zh
                }
                set y [expr {$y + $zh + $bs*[dict get $o -paraskip]}]
                continue
            }
            doc_meta - doc_header { continue }
        }

        set st [newStyle]
        if {$forceMono} { dict set st mono 1 }
        if {$type eq "heading"} { dict set st bold 1 }
        set rr [runs $content $st]
        if {[llength $rr] == 0} { set y [expr {$y + $size*$lead}] ; continue }

        set lines [wrap $pdfobj $rr $wpt $size $base $mono]
        foreach line $lines {
            set baseline [expr {$y + $size}]
            # Check the BOTTOM of the line, not the baseline. Otherwise the
            # last line always seems to fit: its baseline is still above the
            # box edge while its descenders and the leading are not.
            set unten [expr {$y + $size*$lead}]
            if {$hpt > 0 && ($unten - $ytop) > $hpt} {
                set overflow 1
                incr truncated
                if {$clip} { continue }
            }
            if {!$dry} {
                drawLine $pdfobj $line $xpt $baseline $wpt $align $size $base $mono
            }
            set y [expr {$y + $size*$lead}]
            incr nlines
        }
        set y [expr {$y + $size*[dict get $o -paraskip]}]
    }

    return [dict create \
        used      [format %.3f [pt2mm [expr {$y - $ytop}]]] \
        lines     $nlines \
        overflow  $overflow \
        truncated $truncated]
}

# Measure without drawing. NOTE: this still calls `setFont` on the object,
# because a word can only be measured in the font it will be drawn in. As a
# side effect pdf4tcl registers those fonts in the document's resource table,
# so a measured document is a few hundred bytes larger than an untouched one.
# No content is emitted -- but "dry run changes nothing at all" would be too
# strong a promise.
proc ::docir::block::measure {pdfobj ir args} {
    return [pdf $pdfobj $ir {*}$args -dryrun 1]
}
