## htmlSource-0.1.tm  --  HTML -> DocIR  (source)
##
## docir::htmlSource::fromHtml $html   -> DocIR
##
## Reads HTML via tdom (dom parse -html) and maps the document semantics
## onto DocIR -- in the same spirit as odtSource: semantic, no CSS/layout.
## Wrappers (div/section/article/figure) are transparent; non-document
## elements (script/style/nav/footer/aside/head) are skipped.
##
## Passt insbesondere als Umkehrung von docir::html (Round-Trip):
##   docir-list-XXX -> kind, indent-N -> indentLevel, <colgroup> ->
##   alignments, <th> -> header. Works with foreign HTML too
##   (then best-effort: anything non-document is dropped).

package require Tcl 8.6
package require tdom

namespace eval docir::htmlSource {
    namespace export fromHtml
}

# ---- Inline-Ebene -------------------------------------------------

proc docir::htmlSource::_elemText {node} {
    # concatenated text content of all text descendants (tdom returns decoded)
    set s ""
    foreach n [$node childNodes] {
        switch -- [$n nodeType] {
            TEXT_NODE { append s [$n nodeValue] }
            ELEMENT_NODE { append s [_elemText $n] }
        }
    }
    return $s
}

proc docir::htmlSource::_mergeText {inlines} {
    set out {}
    foreach inl $inlines {
        if {[llength $out] && [dict get $inl type] eq "text" && [dict get [lindex $out end] type] eq "text"} {
            set p [lindex $out end]; dict set p text "[dict get $p text][dict get $inl text]"; lset out end $p
        } else { lappend out $inl }
    }
    return $out
}

# a single node (text/element) -> list of inlines (0..n)
proc docir::htmlSource::_ws {s} {
    # HTML-Whitespace-Regel im Inline-Fluss: Folgen von Whitespace -> 1 Space.
    # (Do not use for pre -- pre uses _elemText directly.)
    return [regsub -all {[ \t\r\n]+} $s " "]
}
proc docir::htmlSource::_inlineOf {n} {
    switch -- [$n nodeType] {
        TEXT_NODE {
            set v [_ws [$n nodeValue]]
            if {$v ne ""} { return [list [dict create type text text $v]] }
            return {}
        }
        ELEMENT_NODE {}
        default { return {} }
    }
    set tag [string tolower [$n nodeName]]
    set txt [_ws [_elemText $n]]
    switch -- $tag {
        strong - b   { return [list [dict create type strong    text $txt]] }
        em - i       { return [list [dict create type emphasis  text $txt]] }
        u            { return [list [dict create type underline text $txt]] }
        s - strike - del { return [list [dict create type strike text $txt]] }
        code         { return [list [dict create type code      text $txt]] }
        br           { return [list [dict create type linebreak]] }
        a {
            set href ""; catch {set href [$n getAttribute href]}
            return [list [dict create type link text $txt name "" section "" href $href]]
        }
        span {
            set cls ""; catch {set cls [$n getAttribute class]}
            if {[string match "math *" $cls]} {
                set raw [string trim $txt {$}]
                set disp [expr {[string match "*display*" $cls] ? 1 : 0}]
                return [list [dict create type math text $raw display $disp]]
            }
            set d [dict create type span text $txt class $cls]
            set id ""; catch {set id [$n getAttribute id]}
            if {$id ne ""} { dict set d id $id }
            return [list $d]
        }
        sup {
            set cls ""; catch {set cls [$n getAttribute class]}
            if {$cls eq "footnote-ref"} {
                set id ""; catch {set id [$n getAttribute id]}
                regsub {^fnref-} $id "" id
                return [list [dict create type footnote_ref text $txt id $id]]
            }
            return [list [dict create type text text $txt]]
        }
        img {
            set src ""; set alt ""
            catch {set src [$n getAttribute src]}; catch {set alt [$n getAttribute alt]}
            return [list [dict create type image text $alt url $src]]
        }
        default { return [list [dict create type text text $txt]] }
    }
}

# childNodes -> inline list (nested ul/ol are NOT handled here)
proc docir::htmlSource::_inlines {node} {
    set out {}
    foreach n [$node childNodes] { lappend out {*}[_inlineOf $n] }
    return [_mergeText $out]
}

# ---- Block-Ebene --------------------------------------------------

proc docir::htmlSource::_slug {text} {
    set s [regsub -all {[^a-z0-9]+} [string tolower [string trim $text]] -]
    return [string trim $s -]
}
proc docir::htmlSource::_class {node} {
    set c ""; catch {set c [$node getAttribute class]}; return $c
}
proc docir::htmlSource::_childElems {node tags} {
    set out {}
    foreach n [$node childNodes] {
        if {[$n nodeType] eq "ELEMENT_NODE" && [string tolower [$n nodeName]] in $tags} { lappend out $n }
    }
    return $out
}
proc docir::htmlSource::_onlyImg {node} {
    # returns the img element if the node (aside from whitespace) contains only an img
    set img ""; set other 0
    foreach n [$node childNodes] {
        switch -- [$n nodeType] {
            ELEMENT_NODE { if {[string tolower [$n nodeName]] eq "img"} { set img $n } else { incr other } }
            TEXT_NODE    { if {[string trim [$n nodeValue]] ne ""} { incr other } }
        }
    }
    if {$img ne "" && $other == 0} { return $img }
    return ""
}

# a list (ul/ol/dl) -> [list-block] + nested ones as trailing (indentLevel+1)
proc docir::htmlSource::_list {node depth} {
    set tag [string tolower [$node nodeName]]
    set cls [_class $node]
    # kind: from docir-list-XXX, otherwise from the tag
    set kind $tag
    foreach tok [split $cls] { if {[string match "docir-list-*" $tok]} { set kind [string range $tok 11 end] } }
    if {$kind eq ""} { set kind $tag }
    # indentLevel: from indent-N, otherwise the recursion depth
    set indent $depth
    foreach tok [split $cls] { if {[regexp {^indent-([0-9]+)$} $tok -> n]} { set indent $n } }

    set items {}; set trailing {}
    if {$tag eq "dl"} {
        set term {}
        foreach n [_childElems $node {dt dd}] {
            set nt [string tolower [$n nodeName]]
            if {$nt eq "dt"} { set term [_inlines $n] } else {
                lappend items [dict create type listItem content [_inlines $n] meta [dict create kind $kind term $term]]
                set term {}
            }
        }
    } else {
        foreach li [_childElems $node {li}] {
            # inlines of the li WITHOUT nested lists; collect nested lists
            set inl {}
            foreach n [$li childNodes] {
                if {[$n nodeType] eq "ELEMENT_NODE" && [string tolower [$n nodeName]] in {ul ol dl}} {
                    lappend trailing $n
                } else {
                    lappend inl {*}[_inlineOf $n]
                }
            }
            lappend items [dict create type listItem content [_mergeText $inl] meta [dict create kind $kind term {}]]
        }
    }
    set blocks [list [dict create type list content $items meta [dict create kind $kind indentLevel $indent]]]
    foreach sub $trailing { lappend blocks {*}[_list $sub [expr {$indent + 1}]] }
    return $blocks
}

proc docir::htmlSource::_table {node} {
    # alignments from colgroup
    set aligns {}
    set cg [lindex [_childElems $node {colgroup}] 0]
    if {$cg ne ""} {
        foreach col [_childElems $cg {col}] {
            set st ""; catch {set st [$col getAttribute style]}
            if {[regexp {text-align:\s*(left|center|right)} $st -> a]} { lappend aligns $a } else { lappend aligns none }
        }
    }
    # collect rows (also in thead/tbody)
    set rowsNodes {}
    foreach sec [concat [list $node] [_childElems $node {thead tbody tfoot}]] {
        foreach tr [_childElems $sec {tr}] { lappend rowsNodes $tr }
    }
    set rows {}; set columns 0; set hasHeader 0; set ri 0
    foreach tr $rowsNodes {
        set cells {}; set isHead 0
        foreach c [_childElems $tr {th td}] {
            if {[string tolower [$c nodeName]] eq "th"} { set isHead 1 }
            lappend cells [dict create type tableCell content [_inlines $c] meta {}]
        }
        if {[llength $cells] > $columns} { set columns [llength $cells] }
        set rmeta {}
        if {$isHead} { set rmeta [dict create kind header]; set hasHeader 1 }
        lappend rows [dict create type tableRow content $cells meta $rmeta]
        incr ri
    }
    set meta [dict create columns $columns alignments $aligns hasHeader $hasHeader]
    return [dict create type table content $rows meta $meta]
}

# childNodes of a container -> block list
proc docir::htmlSource::_blocks {node depth} {
    set ir {}
    foreach n [$node childNodes] {
        set nt [$n nodeType]
        if {$nt eq "TEXT_NODE"} {
            set v [string trim [$n nodeValue]]
            if {$v ne ""} { lappend ir [dict create type paragraph content [list [dict create type text text $v]] meta {}] }
            continue
        }
        if {$nt ne "ELEMENT_NODE"} continue
        set tag [string tolower [$n nodeName]]
        switch -- $tag {
            h1 - h2 - h3 - h4 - h5 - h6 {
                set lv [string index $tag 1]
                set id ""; catch {set id [$n getAttribute id]}
                set inl [_inlines $n]
                if {$id eq ""} { set id [_slug [_elemText $n]] }
                lappend ir [dict create type heading content $inl meta [dict create level $lv id $id]]
            }
            p {
                set img [_onlyImg $n]
                if {$img ne ""} {
                    set src ""; set alt ""
                    catch {set src [$img getAttribute src]}; catch {set alt [$img getAttribute alt]}
                    lappend ir [dict create type image content {} meta [dict create url $src alt $alt]]
                } else {
                    lappend ir [dict create type paragraph content [_inlines $n] meta {}]
                }
            }
            pre {
                set code [lindex [_childElems $n {code}] 0]
                set src [expr {$code ne "" ? $code : $n}]
                set meta [dict create kind code]
                if {$code ne ""} {
                    set cc [_class $code]
                    if {[regexp {language-(\S+)} $cc -> lang]} { dict set meta lang $lang }
                }
                lappend ir [dict create type pre content [list [dict create type text text [_elemText $src]]] meta $meta]
            }
            ul - ol - dl { lappend ir {*}[_list $n $depth] }
            table        { lappend ir [_table $n] }
            hr           { lappend ir [dict create type hr content {} meta {}] }
            img {
                set src ""; set alt ""
                catch {set src [$n getAttribute src]}; catch {set alt [$n getAttribute alt]}
                lappend ir [dict create type image content {} meta [dict create url $src alt $alt]]
            }
            blockquote - div - section - article - main - figure {
                lappend ir {*}[_blocks $n $depth]
            }
            script - style - nav - header - footer - aside - head - title - meta - link - colgroup - figcaption {
                # non-document / handled elsewhere -> skip
            }
            default { lappend ir {*}[_blocks $n $depth] }
        }
    }
    return $ir
}

proc docir::htmlSource::fromHtml {html} {
    set doc [dom parse -html -keepEmpties $html]
    set root [$doc documentElement]
    set body [lindex [$root getElementsByTagName body] 0]
    if {$body eq ""} { set body $root }
    set ir [list [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]]]
    lappend ir {*}[_blocks $body 0]
    $doc delete
    return $ir
}

package provide docir::htmlSource 0.1
