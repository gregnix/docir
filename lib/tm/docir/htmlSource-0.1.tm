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

package require Tcl 8.6-
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
            # <a name="x">...</a> ist nur ein Sprungziel, kein Link (BWidget);
            # vorher ein Link mit leerem Ziel, docir::md machte "(.md)" daraus
            if {$href eq ""} { return [_inlines $n] }
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
            if {$nt eq "dt"} {
                set term [_inlines $n]
                set tid [_anchorId $n]
            } else {
                set it [_item $n $kind $term $indent]
                # id des <dt> (Sprungziel, h2md)
                if {[info exists tid] && $tid ne ""} { dict set it meta id $tid }
                lappend items $it
                set term {}; set tid ""
            }
        }
    } else {
        foreach li [_childElems $node {li}] {
            # inlines of the li WITHOUT nested lists; collect nested lists.
            # Other block children (<pre>, <blockquote>, <p>, <table>) become
            # listItem.blocks. Up to 2026-10-22 they were flattened into the
            # line: "Implement the procedure ckbtnCmd as follows: proc
            # ckbtnCmd {tbl row col} { ... }" (Tablelist guide, <pre> in a
            # <blockquote> in an <li>).
            variable blockTags
            set inl {}
            set bl {}
            set seenBlock 0
            foreach n [$li childNodes] {
                set nn ""
                if {[$n nodeType] eq "ELEMENT_NODE"} { set nn [string tolower [$n nodeName]] }
                if {$nn in {ul ol dl}} {
                    lappend trailing $n
                } elseif {$nn in $blockTags} {
                    set run [_mergeText $inl]
                    if {[string trim [_inlinesText $run]] ne ""} {
                        lappend bl [dict create type paragraph content [_trimInl $run] meta {}]
                    }
                    set inl {}
                    # <blockquote> around nothing but a <pre>: the code itself
                    set kids {}
                    foreach k [$n childNodes] {
                        if {[$k nodeType] eq "ELEMENT_NODE"} { lappend kids $k }
                    }
                    if {$nn eq "blockquote" && [llength $kids] == 1
                            && [string tolower [[lindex $kids 0] nodeName]] eq "pre"
                            && [string trim [$n asText]] eq [string trim [[lindex $kids 0] asText]]} {
                        set n [lindex $kids 0]
                    }
                    lappend bl {*}[_block $n [expr {$indent + 1}]]
                    set seenBlock 1
                } else {
                    lappend inl {*}[_inlineOf $n]
                }
            }
            if {!$seenBlock} {
                lappend items [dict create type listItem content [_mergeText $inl] meta [dict create kind $kind term {}]]
                continue
            }
            set run [_mergeText $inl]
            if {[string trim [_inlinesText $run]] ne ""} {
                lappend bl [dict create type paragraph content [_trimInl $run] meta {}]
            }
            set first {}
            if {[llength $bl] && [dict get [lindex $bl 0] type] eq "paragraph"} {
                set first [dict get [lindex $bl 0] content]
            }
            lappend items [dict create type listItem content $first \
                meta [dict create kind $kind term {}] blocks $bl]
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
        lappend ir {*}[_block $n $depth]
    }
    return $ir
}

# one block-level element -> list of DocIR blocks
proc docir::htmlSource::_block {n depth} {
    set ir {}
    set tag [string tolower [$n nodeName]]
    switch -- $tag {
        h1 - h2 - h3 - h4 - h5 - h6 {
            set lv [string index $tag 1]
            set id [_anchorId $n]
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
                # id="..." bleibt als meta.id (Sprungziel, h2md)
                set pm {}
                set pid [_anchorId $n]
                if {$pid ne ""} { dict set pm id $pid }
                lappend ir [dict create type paragraph content [_inlines $n] meta $pm]
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
            # HTML drops the line break right after <pre> (HTML spec, "pre
            # element"); hand-written pages also end with one before </pre>.
            # Both came out as empty first and last lines of every code box.
            set t [_elemText $src]
            regsub {^\r?\n} $t "" t
            regsub {(?:\r?\n[ \t]*)+$} $t "" t
            lappend ir [dict create type pre content [list [dict create type text text $t]] meta $meta]
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
    return $ir
}

# Block elements, as opposed to inline ones, inside a <dd> or <li>.
namespace eval docir::htmlSource {
    variable blockTags {p div dl ul ol pre table blockquote h1 h2 h3 h4 h5 h6 hr section article figure}
}

# Content of a <dd>/<li> that holds blocks (paragraphs, nested lists, code):
# inline runs become paragraphs, block elements go through _block. Before
# 2026-10-22 everything was flattened into one inline line -- the command
# reference of tablelistWidget.html (a <dl> inside a <dd>) came out as one
# paragraph of 100 KB.
proc docir::htmlSource::_flow {node depth} {
    variable blockTags
    set ir {}
    set run {}
    foreach n [$node childNodes] {
        if {[$n nodeType] eq "ELEMENT_NODE" && [string tolower [$n nodeName]] in $blockTags} {
            set run [_mergeText $run]
            if {[string trim [_inlinesText $run]] ne ""} {
                lappend ir [dict create type paragraph content [_trimInl $run] meta {}]
            }
            set run {}
            lappend ir {*}[_block $n $depth]
        } else {
            lappend run {*}[_inlineOf $n]
        }
    }
    set run [_mergeText $run]
    if {[string trim [_inlinesText $run]] ne ""} {
        lappend ir [dict create type paragraph content [_trimInl $run] meta {}]
    }
    return $ir
}
proc docir::htmlSource::_inlinesText {inl} {
    set s ""
    foreach i $inl { if {[dict exists $i text]} { append s [dict get $i text] } }
    return $s
}
# leading/trailing whitespace of a paragraph run
proc docir::htmlSource::_trimInl {inl} {
    if {[llength $inl] && [dict get [lindex $inl 0] type] eq "text"} {
        set f [lindex $inl 0]; dict set f text [string trimleft [dict get $f text]]; lset inl 0 $f
    }
    if {[llength $inl] && [dict get [lindex $inl end] type] eq "text"} {
        set f [lindex $inl end]; dict set f text [string trimright [dict get $f text]]; lset inl end $f
    }
    return $inl
}
proc docir::htmlSource::_hasBlocks {node} {
    variable blockTags
    foreach n [$node childNodes] {
        if {[$n nodeType] eq "ELEMENT_NODE" && [string tolower [$n nodeName]] in $blockTags} { return 1 }
    }
    return 0
}

# listItem from a <dd>/<li>: tight -> content only; with blocks -> content =
# first paragraph, blocks = all blocks (DocIR spec, listItem.blocks)
proc docir::htmlSource::_item {node kind term depth} {
    if {![_hasBlocks $node]} {
        return [dict create type listItem content [_inlines $node] meta [dict create kind $kind term $term]]
    }
    set bl [_flow $node [expr {$depth + 1}]]
    set first {}
    if {[llength $bl] && [dict get [lindex $bl 0] type] eq "paragraph"} {
        set first [dict get [lindex $bl 0] content]
    }
    return [dict create type listItem content $first meta [dict create kind $kind term $term] blocks $bl]
}

# Repairs tag soup so that tdom's -html parser accepts it (fallback, only
# used when the first parse fails):
#   - end tags that close nothing are dropped ("</dd>" after an already
#     closed <dd>; tablelistWidget.html of Tablelist 7.12),
#   - elements left open are closed explicitly: by an implied end (a new
#     <dd> ends the open <dd>, <li> the <li>, a block element the <p>), by
#     the end tag of an enclosing element, and at the end of the document
#     (BWidget's BWman/*.html: "</table></dd>" with open <tr>/<td>,
#     "</body></html>" with an open <dl>),
#   - end tags are written plainly ("</dl COMPACT>" -> "</dl>").
# tdom stopped with "Unterminated element ...", "Unexpected end" or
# "Missing '>'".
# Sprungziel eines Elements: eigenes id, sonst das erste <a name=...> oder
# <a id=...> darin (alte Seiten, BWidget: <dt><a name="-width">...)
proc docir::htmlSource::_anchorId {node} {
    if {![catch {$node getAttribute id} v] && $v ne ""} { return $v }
    foreach a [$node getElementsByTagName a] {
        foreach att {name id} {
            if {![catch {$a getAttribute $att} v] && $v ne ""} { return $v }
        }
    }
    return ""
}

proc docir::htmlSource::_implied {tag} {
    switch -- $tag {
        dd - dt     { return {dd dt p} }
        li          { return {li p} }
        tr          { return {tr td th} }
        td - th     { return {td th} }
        option      { return {option} }
        p - div - dl - ul - ol - table - pre - blockquote - h1 - h2 - h3 - h4 - h5 - h6 - hr {
            return {p}
        }
    }
    return {}
}

proc docir::htmlSource::_balance {html} {
    set void {area base br col embed hr img input link meta param source track wbr}
    set stack {}
    set out ""
    set pos 0
    set re {<!--.*?-->|<(/?)([A-Za-z][A-Za-z0-9]*)(?:\s[^>]*)?(/?)>}
    while {[regexp -indices -start $pos $re $html m slash name self]} {
        lassign $m a b
        append out [string range $html $pos [expr {$a - 1}]]
        set tag [string range $html $a $b]
        set pos [expr {$b + 1}]
        if {[lindex $name 0] < 0} { append out $tag; continue }   ;# comment
        set n [string tolower [string range $html {*}$name]]
        if {[lindex $slash 0] <= [lindex $slash 1]} {
            # innermost open element of that name; </dd>, </li>, </td> ...
            # do not reach past the enclosing list or table
            set hit -1
            for {set k [expr {[llength $stack] - 1}]} {$k >= 0} {incr k -1} {
                set t [lindex $stack $k]
                if {$t eq $n} { set hit $k; break }
                if {$n in {dd dt li td th tr p} && $t in {dl ul ol table}} break
            }
            if {$hit < 0} continue                                ;# stray: drop
            # close what is still open inside, then this one
            foreach t [lreverse [lrange $stack $hit end]] { append out "</$t>" }
            set stack [lrange $stack 0 [expr {$hit - 1}]]
            continue
        }
        if {$n ni $void && [lindex $self 0] > [lindex $self 1]} {
            # <td> ohne offenes <tr> in der Tabelle (BWidget: "<TD>..</TR>"
            # schliesst die Zeile, die naechste <TD> steht frei): <tr> davor
            if {$n in {td th}} {
                set inTr 0
                for {set k [expr {[llength $stack] - 1}]} {$k >= 0} {incr k -1} {
                    set t [lindex $stack $k]
                    if {$t eq "tr"} { set inTr 1; break }
                    if {$t eq "table"} break
                }
                if {!$inTr && "table" in $stack} { append out "<tr>"; lappend stack tr }
            }
            set closes [_implied $n]
            if {[llength $closes]} {
                for {set k [expr {[llength $stack] - 1}]} {$k >= 0} {incr k -1} {
                    set t [lindex $stack $k]
                    if {$t in $closes} {
                        foreach u [lreverse [lrange $stack $k end]] { append out "</$u>" }
                        set stack [lrange $stack 0 [expr {$k - 1}]]
                        break
                    }
                    if {$t in {dl ul ol table thead tbody tfoot tr div blockquote body}} break
                }
            }
            lappend stack $n
        }
        append out $tag
    }
    append out [string range $html $pos end]
    foreach t [lreverse $stack] { append out "</$t>" }
    return $out
}

proc docir::htmlSource::fromHtml {html} {
    if {[catch {dom parse -html -keepEmpties $html} doc]} {
        set doc [dom parse -html -keepEmpties [_balance $html]]
    }
    set root [$doc documentElement]
    set body [lindex [$root getElementsByTagName body] 0]
    if {$body eq ""} { set body $root }
    set ir [list [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]]]
    lappend ir {*}[_blocks $body 0]
    $doc delete
    return $ir
}

package provide docir::htmlSource 0.1
