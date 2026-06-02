## odtSource-0.4.tm  --  ODT -> DocIR
## Convention: docir::FORMATSource (source). Produces a flat, semantic
## DocIR block list from an .odt file.
##
## Backend: odf (odf::Package + odf::Text), no odtread. Loading, style
## registry and style resolution all go through odf; node walking stays on
## plain tdom (childNodes / localName / getElementsByTagName), so no implicit
## selectNodes namespace registration is relied upon.
##
## Mapping (semantic, not visual):
##   text:h outline-level N        -> heading level N (1..6)
##   text:p monospace style        -> pre (kind code)
##   text:p empty                  -> blank
##   text:p otherwise              -> paragraph
##   span font-weight=bold         -> strong   (order: code > strong > emphasis)
##   span font-style=italic        -> emphasis
##   span monospace                -> code
##   span with other style         -> span (class = style name)
##   text:line-break               -> linebreak
##   text:a                        -> link (href)
##   text-align (center/right)     -> dropped (DocIR has no alignment)
##
## Style props returned by odf::Text resolveStyle are grouped+prefixed; we
## flatten them to local-name keys (font-weight, font-style, font-family,
## text-align) to match the lookups below.

package require odf::text
package require odf::style
package require tdom

namespace eval docir::odtSource {
    namespace export fromOdt
    variable MonoRe {(?i)courier|mono|consol|menlo|code}
    # context, set for the duration of fromOdt
    variable Txt ""
    variable Reg {}
    variable Sty ""
}

## ---- low-level node helpers (plain tdom) ------------------------------

## Read a prefix-independent attribute by its local name. content.xml is
## parsed without namespace awareness, so attribute names keep their literal
## prefix; we probe the prefixes that actually occur, then the bare name.
proc docir::odtSource::_attr {node local {default -}} {
    foreach pfx {text table xlink draw svg fo style} {
        if {[$node hasAttribute "$pfx:$local"]} { return [$node getAttribute "$pfx:$local"] }
    }
    if {[$node hasAttribute $local]} { return [$node getAttribute $local] }
    return $default
}

## Inline text of a node: text content with line-break -> \n, tab -> \t and
## text:s -> spaces (so <pre> keeps its layout). Mirrors odtread::_inlineText.
proc docir::odtSource::_inlineText {node} {
    set out ""
    foreach c [$node childNodes] {
        switch -- [$c nodeType] {
            TEXT_NODE { append out [$c nodeValue] }
            ELEMENT_NODE {
                switch -- [$c localName] {
                    line-break { append out "\n" }
                    tab        { append out "\t" }
                    s          { append out [string repeat " " [_attr $c c 1]] }
                    default    { append out [_inlineText $c] }
                }
            }
        }
    }
    return $out
}

## ---- style resolution (via odf) ---------------------------------------

proc docir::odtSource::_prop {props key {default ""}} {
    expr {[dict exists $props $key] ? [dict get $props $key] : $default}
}

## Flatten odf's grouped+prefixed style props ({group {prefix:attr val}}) to
## a flat dict keyed by attribute local name -- the form the lookups expect.
proc docir::odtSource::_flatten {grouped} {
    set flat [dict create]
    dict for {grp attrs} $grouped {
        dict for {k v} $attrs {
            dict set flat [lindex [split $k :] end] $v
        }
    }
    return $flat
}

proc docir::odtSource::_styleProps {node} {
    variable Txt
    variable Reg
    set sn [_attr $node style-name -]
    if {$sn in {- None ""}} { return {} }
    return [_flatten [$Txt resolveStyle $sn $Reg]]
}

proc docir::odtSource::_isMono {node} {
    variable MonoRe
    set sn [_attr $node style-name -]
    if {[regexp $MonoRe $sn]} { return 1 }
    set fam [_prop [_styleProps $node] font-family ""]
    return [regexp $MonoRe $fam]
}

proc docir::odtSource::_slug {text} {
    set s [string tolower [string trim $text]]
    set s [regsub -all {[^a-z0-9]+} $s -]
    return [string trim $s -]
}

## ---- inline mapping ---------------------------------------------------

## span -> inline type
proc docir::odtSource::_spanInline {node} {
    set sn    [_attr $node style-name -]
    set props [_styleProps $node]
    set txt   [_inlineText $node]
    if {[_isMono $node]} { return [dict create type code text $txt] }
    if {[_prop $props font-weight] eq "bold"}   { return [dict create type strong   text $txt] }
    if {[_prop $props font-style]  eq "italic"} { return [dict create type emphasis text $txt] }
    if {$sn ni {- None ""}} { return [dict create type span text $txt class $sn] }
    return [dict create type text text $txt]
}

## inline list of an h/p node
proc docir::odtSource::_mapInlines {node} {
    set out {}
    foreach c [$node childNodes] {
        switch -- [$c nodeType] {
            TEXT_NODE { lappend out [dict create type text text [$c nodeValue]] }
            ELEMENT_NODE {
                switch -- [$c localName] {
                    span       { lappend out [_spanInline $c] }
                    line-break { lappend out [dict create type linebreak] }
                    tab        { lappend out [dict create type text text "\t"] }
                    s          { lappend out [dict create type text text [string repeat " " [_attr $c c 1]]] }
                    a          {
                        lappend out [dict create type link \
                            text [_inlineText $c] name "" section "" \
                            href [_attr $c href ""]]
                    }
                    bookmark - bookmark-start - bookmark-end { }
                    frame - image { }
                    default { lappend out [dict create type text text [_inlineText $c]] }
                }
            }
        }
    }
    return $out
}

## does the paragraph host a frame/image? (lifted out as image block)
proc docir::odtSource::_hostsFrame {node} {
    foreach c [$node childNodes] {
        if {[$c nodeType] eq "ELEMENT_NODE" && [$c localName] in {frame image}} { return 1 }
    }
    return 0
}

proc docir::odtSource::_mapBlock {node} {
    switch -- [$node localName] {
        h {
            set lvl [_attr $node outline-level 1]
            if {![string is integer -strict $lvl]} { set lvl 1 }
            if {$lvl < 1} { set lvl 1 } elseif {$lvl > 6} { set lvl 6 }
            set inl [_mapInlines $node]
            set title [_inlineText $node]
            return [list [dict create type heading content $inl \
                meta [dict create level $lvl id [_slug $title]]]]
        }
        p {
            if {[_hostsFrame $node]} { return [_mapImages $node] }
            set txt [string trim [_inlineText $node]]
            if {$txt eq ""} {
                return [list [dict create type blank content {} meta [dict create lines 1]]]
            }
            if {[_isMono $node]} {
                return [list [dict create type pre \
                    content [list [dict create type text text [_inlineText $node]]] \
                    meta [dict create kind code]]]
            }
            return [list [dict create type paragraph content [_mapInlines $node] meta {}]]
        }
        frame - image { return [_mapImages $node] }
        list  { return [_mapList $node 0] }
        table { return [_mapTable $node] }
        default { return {} }
    }
}

## --- images: every draw:image under the node as a standalone block ---
proc docir::odtSource::_mapImages {node} {
    set out {}
    # descendant-or-self::draw:image without selectNodes namespaces
    set imgs {}
    if {[$node nodeName] eq "draw:image"} { lappend imgs $node }
    foreach i [$node getElementsByTagName draw:image] { lappend imgs $i }
    foreach img $imgs {
        set url [_attr $img href ""]
        if {$url eq ""} continue
        # alt: svg:title/desc of the enclosing frame, else empty
        set alt ""
        set frame [$img parentNode]
        if {$frame ne ""} {
            foreach tag {svg:title svg:desc} {
                foreach t [$frame getElementsByTagName $tag] {
                    set a [_inlineText $t]
                    if {$a ne ""} { set alt $a; break }
                }
                if {$alt ne ""} break
            }
        }
        lappend out [dict create type image content {} meta [dict create url $url alt $alt]]
    }
    return $out
}

## --- cell/item: inlines of all contained paragraphs, joined by linebreak ---
proc docir::odtSource::_blockInlines {node} {
    set out {}; set first 1
    foreach c [$node childNodes] {
        if {[$c nodeType] ne "ELEMENT_NODE"} continue
        if {[$c localName] ni {p h}} continue
        if {!$first} { lappend out [dict create type linebreak] }
        set first 0
        foreach inl [_mapInlines $c] { lappend out $inl }
    }
    return $out
}

## --- table ---
proc docir::odtSource::_mapTable {node} {
    set rows {}
    # collect rows, descending into table:table-header-rows
    set rowNodes {}
    foreach c [$node childNodes] {
        if {[$c nodeType] ne "ELEMENT_NODE"} continue
        switch -- [$c localName] {
            table-row { lappend rowNodes [list $c body] }
            table-header-rows {
                foreach hr [$c childNodes] {
                    if {[$hr nodeType] eq "ELEMENT_NODE" && [$hr localName] eq "table-row"} {
                        lappend rowNodes [list $hr header]
                    }
                }
            }
        }
    }
    set hasHeader 0
    set cols 0
    set built {}
    foreach rk $rowNodes {
        lassign $rk r kind
        if {$kind eq "header"} { set hasHeader 1 }
        set cells {}
        foreach cell [$r childNodes] {
            if {[$cell nodeType] ne "ELEMENT_NODE"} continue
            if {[$cell localName] ne "table-cell"} continue   ;# skip covered cells
            lappend cells [dict create type tableCell content [_blockInlines $cell] meta {}]
        }
        if {[llength $cells] > $cols} { set cols [llength $cells] }
        lappend built [list $cells $kind]
    }
    # header heuristic: without explicit table:table-header-rows the first row
    # counts as header (practically always true for ODF tables).
    if {!$hasHeader && [llength $built] > 0} {
        lassign [lindex $built 0] cells0 _kind0
        lset built 0 [list $cells0 header]
        set hasHeader 1
    }
    # pad rows to column count and finalise
    foreach b $built {
        lassign $b cells kind
        while {[llength $cells] < $cols} {
            lappend cells [dict create type tableCell content {} meta {}]
        }
        set rowMeta [expr {$kind eq "header" ? [dict create kind header] : {}}]
        lappend rows [dict create type tableRow content $cells meta $rowMeta]
    }
    if {$cols == 0} { return {} }
    set aligns {}
    for {set i 0} {$i < $cols} {incr i} { lappend aligns left }
    return [list [dict create type table content $rows \
        meta [dict create columns $cols alignments $aligns hasHeader $hasHeader]]]
}

## --- list (nested sublists as trailing blocks with higher indentLevel) ---
proc docir::odtSource::_mapList {node depth {inheritKind ""} {inheritFmt ""}} {
    variable Sty
    # Resolve the list's kind from its text:style-name. LibreOffice often omits
    # text:style-name on nested lists (they inherit the parent's style), so when
    # it is absent/unknown we inherit the kind/format from the enclosing list.
    set kind [expr {$inheritKind ne "" ? $inheritKind : "ul"}]
    set numFormat [expr {$inheritFmt ne "" ? $inheritFmt : "1"}]
    if {$Sty ne ""} {
        set sn [$node getAttribute text:style-name ""]
        if {$sn ne ""} {
            set k [$Sty listStyleKind $sn]
            if {$k eq "ordered"} {
                set kind ol
                set f [$Sty listStyleFormat $sn]
                if {$f ne ""} { set numFormat $f }
            } elseif {$k eq "bullet"} {
                set kind ul
            }
            # k eq "" (unknown): keep inherited/default
        }
    }
    set items {}
    set trailing {}
    foreach c [$node childNodes] {
        if {[$c nodeType] ne "ELEMENT_NODE" || [$c localName] ne "list-item"} continue
        # desc = inlines of the item's first paragraph
        set desc {}
        foreach k [$c childNodes] {
            if {[$k nodeType] eq "ELEMENT_NODE" && [$k localName] in {p h}} {
                set desc [_mapInlines $k]; break
            }
        }
        lappend items [dict create type listItem content $desc \
            meta [dict create kind $kind term {}]]
        # nested lists inside the item -> trailing with indentLevel+1, inheriting kind/format
        foreach k [$c childNodes] {
            if {[$k nodeType] eq "ELEMENT_NODE" && [$k localName] eq "list"} {
                foreach n [_mapList $k [expr {$depth+1}] $kind $numFormat] { lappend trailing $n }
            }
        }
    }
    set meta [dict create kind $kind indentLevel $depth]
    if {$kind eq "ol"} { dict set meta numFormat $numFormat }
    set listNode [dict create type list content $items meta $meta]
    return [concat [list $listNode] $trailing]
}

proc docir::odtSource::fromOdt {path} {
    variable Txt
    variable Reg
    variable Sty
    set pkg [odf::Package new $path]
    try {
        set Txt [odf::Text new $pkg]   ;# errors if no office:text -> not an ODT text doc
        set Reg [$Txt styleRegistry]
        set Sty [odf::Styles new $pkg] ;# classify list styles (ordered vs bullet)

        set ir {}
        lappend ir [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]]
        foreach child [$Txt blocks] {
            set ir [concat $ir [_mapBlock $child]]
        }
        return $ir
    } finally {
        if {$Txt ne ""} { catch {$Txt destroy} }
        if {$Sty ne ""} { catch {$Sty destroy} }
        $pkg destroy
        set Txt ""; set Reg {}; set Sty ""
    }
}

package provide docir::odtSource 0.4
