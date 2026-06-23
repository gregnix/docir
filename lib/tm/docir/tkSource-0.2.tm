## tkSource-0.2.tm  --  Tk text widget -> DocIR (source) + image bytes
##
## docir::tkSource::fromWidget $w ?i1 i2?   (range possible, like in ttd)
##
## Reads a text-widget dump and builds DocIR from it. Recognizes the tags
## that docir::renderer::tk assigns:
##   heading$N -> heading (level N) | pre -> pre/code | strong/emphasis/
##   underline/strike/span_$cls/link_$n -> Inlines | eingebettete Bilder.
##
## LIMITS (deliberate, = the ttd-vs-DocIR boundary): the renderer shows tables
## and lists as monospaced text/bullets; the widget does not retain their
## structure. A dump therefore returns them as paragraph/pre,
## not as table/list. Link targets (href) and image URLs are not reliably
## stored in the widget and are filled best-effort.

package require Tcl 8.6

namespace eval docir::tkSource {
    namespace export fromWidget media
    variable _media {}   ;# url -> PNG bytes (from the last fromWidget)
    variable _imgN  0
}

## Image to portable url -> returns media bytes (file or via photo write)
proc docir::tkSource::media {} {
    variable _media
    return $_media
}
proc docir::tkSource::_photoBytes {img} {
    set f ""; catch {set f [$img cget -file]}
    if {$f ne "" && [file readable $f]} {
        set fh [open $f rb]; set b [read $fh]; close $fh; return $b
    }
    # nur im Speicher -> ueber temporaeres PNG
    if {[catch {set ch [file tempfile tmp]}]} { return "" }
    close $ch
    if {[catch {$img write $tmp -format png}]} { catch {file delete $tmp}; return "" }
    set fh [open $tmp rb]; set b [read $fh]; close $fh
    catch {file delete $tmp}
    return $b
}

proc docir::tkSource::_slug {text} {
    set s [string tolower [string trim $text]]
    set s [regsub -all {[^a-z0-9]+} $s -]
    return [string trim $s -]
}

## merge + fuehrende/abschliessende Renderer-Leerzeichen entfernen
proc docir::tkSource::_finalizePara {inlines} {
    set m [_mergeInlines $inlines]
    if {[llength $m]} {
        set f [lindex $m 0]
        if {[dict get $f type] eq "text"} { dict set f text [string trimleft [dict get $f text] " \t"]; lset m 0 $f }
        set l [lindex $m end]
        if {[dict get $l type] eq "text"} { dict set l text [string trimright [dict get $l text] " \t"]; lset m end $l }
    }
    return $m
}

## Tag-Set eines Segments -> Inline-Dict
proc docir::tkSource::_segInline {tags text} {
    foreach t $tags { if {[regexp {^link_} $t]} { return [dict create type link text $text name "" section "" href ""] } }
    if {"pre"       in $tags} { return [dict create type code      text $text] }
    if {"strong"    in $tags} { return [dict create type strong    text $text] }
    if {"emphasis"  in $tags} { return [dict create type emphasis  text $text] }
    if {"underline" in $tags} { return [dict create type underline text $text] }
    if {"strike"    in $tags} { return [dict create type strike    text $text] }
    foreach t $tags { if {[string match span_* $t]} { return [dict create type span text $text class [string range $t 5 end]] } }
    return [dict create type text text $text]
}

## benachbarte gleichartige text-Inlines zusammenfassen
proc docir::tkSource::_mergeInlines {inlines} {
    set out {}
    foreach inl $inlines {
        if {[llength $out] && [dict get $inl type] eq "text" && [dict get [lindex $out end] type] eq "text"} {
            set prev [lindex $out end]
            dict set prev text "[dict get $prev text][dict get $inl text]"
            lset out end $prev
        } else {
            lappend out $inl
        }
    }
    return $out
}

## Line class: heading level (or -1), or whether it is a pure pre line
proc docir::tkSource::_headingLevel {line} {
    foreach atom $line {
        if {[lindex $atom 0] ne "SEG"} continue
        foreach t [lindex $atom 1] {
            if {[regexp {^heading([0-9]+)$} $t -> n]} { return $n }
        }
    }
    return -1
}
proc docir::tkSource::_isPreLine {line} {
    set any 0
    foreach atom $line {
        if {[lindex $atom 0] ne "SEG"} continue
        set any 1
        if {"pre" ni [lindex $atom 1]} { return 0 }
    }
    return $any
}
proc docir::tkSource::_lineText {line} {
    set s ""
    foreach atom $line { if {[lindex $atom 0] eq "SEG"} { append s [lindex $atom 2] } }
    return $s
}
proc docir::tkSource::_lineInlines {line} {
    set inl {}
    foreach atom $line {
        if {[lindex $atom 0] ne "SEG"} continue
        lappend inl [_segInline [lindex $atom 1] [lindex $atom 2]]
    }
    return [_mergeInlines $inl]
}
proc docir::tkSource::_lineImage {line} {
    # returns IMG name if the line consists only of an image
    set imgs {}; set segs 0
    foreach atom $line {
        switch -- [lindex $atom 0] {
            IMG { lappend imgs [lindex $atom 1] }
            SEG { if {[string trim [lindex $atom 2]] ne ""} { incr segs } }
        }
    }
    if {[llength $imgs] == 1 && $segs == 0} { return [lindex $imgs 0] }
    return ""
}

proc docir::tkSource::fromWidget {w {i1 1.0} {i2 end}} {
    variable _media; variable _imgN
    set _media {}; set _imgN 0
    # 1) Dump -> Segmentstrom (SEG/NL/IMG)
    set segs {}
    set active {}
    foreach {key val idx} [$w dump -all $i1 $i2] {
        switch -- $key {
            tagon  { lappend active $val }
            tagoff { set active [lsearch -all -inline -not -exact $active $val] }
            text {
                set parts [split $val "\n"]
                set np [llength $parts]
                for {set k 0} {$k < $np} {incr k} {
                    set piece [lindex $parts $k]
                    if {$piece ne ""} { lappend segs [list SEG $active $piece] }
                    if {$k < $np - 1} { lappend segs NL }
                }
            }
            image  { lappend segs [list IMG $val] }
            default { }
        }
    }
    # 2) in Zeilen gruppieren
    set lines {}; set cur {}
    foreach s $segs {
        if {$s eq "NL"} { lappend lines $cur; set cur {} } else { lappend cur $s }
    }
    lappend lines $cur

    # 3) Zeilen -> Bloecke
    set ir [list [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]]]
    set para {}; set preBuf {}; set inPre 0
    set flushPara {
        if {[llength $para]} {
            lappend ir [dict create type paragraph content [_finalizePara $para] meta {}]
            set para {}
        }
    }
    set flushPre {
        if {$inPre} {
            lappend ir [dict create type pre \
                content [list [dict create type text text [join $preBuf "\n"]]] \
                meta [dict create kind code]]
            set preBuf {}; set inPre 0
        }
    }
    foreach line $lines {
        if {[llength $line] == 0} {                 ;# Leerzeile -> Trenner
            eval $flushPara; eval $flushPre; continue
        }
        set img [_lineImage $line]
        if {$img ne ""} {
            eval $flushPara; eval $flushPre
            incr ::docir::tkSource::_imgN
            set url "Pictures/tkimg$::docir::tkSource::_imgN.png"
            set bytes [_photoBytes $img]
            if {$bytes ne ""} { dict set ::docir::tkSource::_media $url $bytes }
            lappend ir [dict create type image content {} meta [dict create url $url alt ""]]
            continue
        }
        set hl [_headingLevel $line]
        if {$hl >= 0} {
            eval $flushPara; eval $flushPre
            if {$hl < 1} { set hl 1 } elseif {$hl > 6} { set hl 6 }
            lappend ir [dict create type heading content [_lineInlines $line] \
                meta [dict create level $hl id [_slug [_lineText $line]]]]
            continue
        }
        if {[_isPreLine $line]} {
            eval $flushPara
            lappend preBuf [_lineText $line]; set inPre 1
            continue
        }
        # Absatzzeile: ggf. mehrzeilig -> linebreak zwischen den Zeilen
        eval $flushPre
        if {[llength $para]} { lappend para [dict create type linebreak] }
        foreach inl [_lineInlines $line] { lappend para $inl }
    }
    eval $flushPara; eval $flushPre
    return $ir
}

package provide docir::tkSource 0.2
