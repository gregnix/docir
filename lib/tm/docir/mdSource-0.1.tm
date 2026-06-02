# docir-md-0.1.tm
#
# Mapper: mdparser-0.2 AST  →  DocIR 0.2
#
# Converts the nested mdparser tree into a flat
# DocIR sequence (depth-first, SAX-like).
#
# Namespace: ::docir::md
# Requires:  mdparser 0.2  (for the AST)
# Tcl 8.6+ / 9.x compatible

package provide docir::mdSource 0.1

namespace eval docir::md {}

# dict lookup with default WITHOUT expr -- expr would evaluate the substituted
# value as an expression, which throws for value strings that look like
# out-of-range numbers (e.g. on math man pages: expr.md, fpclassify.md).
proc docir::md::_dictDef {d k {def ""}} {
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}

# ============================================================
# Public API
# ============================================================

# docir::md::fromAst ast
#   Converts an mdparser-AST (document-Root) to DocIR.
#   Returns a flat list of DocIR-Nodes.
proc docir::md::fromAst {ast} {
    if {![dict exists $ast type] || [dict get $ast type] ne "document"} {
        error "docir::md::fromAst: no document-AST"
    }

    set ir {}

    # doc_meta as the very first block (irSchemaVersion since 0.5)
    lappend ir [dict create \
        type    doc_meta \
        content {} \
        meta    [dict create irSchemaVersion 1]]

    # doc_header from meta (YAML frontmatter)
    set meta [_dictDef $ast meta {}]
    set title [_dictDef $meta title ""]
    lappend ir [dict create \
        type    doc_header \
        content {} \
        meta    [dict create \
            name    $title \
            section "" \
            version [_dictDef $meta version ""] \
            part    [expr {[dict exists $meta part]    ? [dict get $meta part]    : ""}]]]

    # Process blocks
    set blocks [_dictDef $ast blocks {}]
    foreach block $blocks {
        set ir [concat $ir [docir::md::_mapBlock $block]]
    }

    return $ir
}

# ============================================================
# Block-Mapping (internal, recursive)
# ============================================================

proc docir::md::_mapBlock {block} {
    set t [dict get $block type]
    switch $t {
        heading      { return [list [docir::md::_mapHeading $block]] }
        paragraph    { return [list [docir::md::_mapParagraph $block]] }
        code_block   { return [list [docir::md::_mapCodeBlock $block]] }
        list         { return [docir::md::_mapList $block] }
        blockquote   { return [docir::md::_mapBlockquote $block] }
        hr           { return [list [dict create type hr content {} meta {}]] }
        div          { return [docir::md::_mapDiv $block] }
        deflist      { return [docir::md::_mapDeflist $block] }
        table        { return [list [docir::md::_mapTable $block]] }
        image        { return [list [docir::md::_mapImageBlock $block]] }
        footnote_section { return [docir::md::_mapFootnoteSection $block] }
        footnote_def { return {} }
        math_block   {
            # Display-Math als Pre-Block mit kind=math kennzeichnen.
            # HTML-Sink kann es als <div class="math display"> rendern,
            # MD-Sink als $$...$$, TXT-Sink als eingerueckter Text.
            # Content als Text-Inline-Liste, damit DocIR-Validator nicht
            # protestiert (content muss Inline-Liste sein, nicht String).
            set txt [dict get $block content]
            return [list [dict create \
                type pre \
                content [list [dict create type text text $txt]] \
                meta [dict create kind math display 1]]]
        }
        default      {
            # Unbekannter Block-Typ (image, video, ...). Wenn er
            # 'content' hat, als paragraph mit recursiv verarbeiteten
            # Inlines emittieren. Sonst Marker-Text einfuegen.
            #
            # Wichtig: Klammern um $t mit \[..\] escapen, sonst loest
            # Tcl Kommando-Substitution aus und versucht den Typnamen
            # als Befehl auszufuehren ("invalid command name span" /
            # "wrong # args: should be image option ?args?").
            if {[dict exists $block content]} {
                set inlines [docir::md::_mapInlines [dict get $block content]]
                return [list [dict create \
                    type paragraph \
                    content $inlines \
                    meta {class unknown}]]
            }
            return [list [dict create \
                type    paragraph \
                content [list [dict create type text text "\[block:$t\]"]] \
                meta    {class unknown}]]
        }
    }
}

proc docir::md::_mapHeading {block} {
    set level  [dict get $block level]
    set anchor [_dictDef $block anchor ""]
    # content is Inline-list (like paragraph)
    set raw    [_dictDef $block content {}]
    set inlines [docir::md::_mapInlines $raw]
    return [dict create \
        type    heading \
        content $inlines \
        meta    [dict create level $level id $anchor]]
}

proc docir::md::_mapParagraph {block} {
    set inlines [docir::md::_mapInlines [dict get $block content]]
    return [dict create \
        type    paragraph \
        content $inlines \
        meta    {}]
}

proc docir::md::_mapCodeBlock {block} {
    set lang [_dictDef $block language ""]
    set text [_dictDef $block text ""]
    set inlines [list [dict create type text text $text]]
    return [dict create \
        type    pre \
        content $inlines \
        meta    [dict create kind code language $lang]]
}

proc docir::md::_mapList {block} {
    set style [dict get $block style]   ;# unordered | ordered
    set kind  [expr {$style eq "ordered" ? "ol" : "ul"}]
    set items   {}
    set trailing {}

    foreach item [dict get $block items] {
        # list_item has blocks:[] – inline content from first paragraph
        set blocks [dict get $item blocks]
        set descInlines {}
        set restBlocks {}
        if {[llength $blocks] > 0} {
            set first [lindex $blocks 0]
            if {[dict get $first type] eq "paragraph"} {
                set descInlines [docir::md::_mapInlines [dict get $first content]]
                set restBlocks  [lrange $blocks 1 end]
            } else {
                set restBlocks $blocks
            }
        }
        lappend items [dict create \
            type    listItem \
            content $descInlines \
            meta    [dict create kind $kind term {}]]

        # Nested blocks (sub-lists, paragraphs) collected as TRAILING
        # top-level siblings — NOT appended to $items, because
        # list.content must contain only listItem nodes (DocIR schema).
        # The flat representation "list followed by sub-list followed
        # by next item" is awkward but valid; the renderer uses
        # indentLevel/visual cues to suggest nesting.
        foreach sub $restBlocks {
            lappend trailing {*}[docir::md::_mapBlock $sub]
        }
    }

    set listNode [dict create \
        type    list \
        content $items \
        meta    [dict create kind $kind indentLevel 0]]

    return [concat [list $listNode] $trailing]
}

proc docir::md::_mapBlockquote {block} {
    # Blockquote → paragraph with class=blockquote (DocIR has no own type)
    set ir {}
    foreach sub [dict get $block blocks] {
        set nodes [docir::md::_mapBlock $sub]
        foreach n $nodes {
            # set class=blockquote in meta
            if {[dict exists $n meta]} {
                dict set n meta class blockquote
            }
            lappend ir $n
        }
    }
    return $ir
}

proc docir::md::_mapDiv {block} {
    # mdparser: {type div class "..." id "..." blocks {...}}
    # DocIR-Spec: {type div content {block-list} meta {class ... id ...}}
    set cls [_dictDef $block class ""]
    set id  [expr {[dict exists $block id]    ? [dict get $block id]    : ""}]
    set children {}
    foreach sub [dict get $block blocks] {
        set nodes [docir::md::_mapBlock $sub]
        foreach n $nodes {
            lappend children $n
        }
    }
    set meta {}
    if {$cls ne ""} { dict set meta class $cls }
    if {$id  ne ""} { dict set meta id $id }
    return [list [dict create \
        type    div \
        content $children \
        meta    $meta]]
}

proc docir::md::_mapDeflist {block} {
    set items {}
    foreach dl [dict get $block items] {
        set term [docir::md::_mapInlines [dict get $dl term]]
        set defs [_dictDef $dl definitions {}]
        # `definitions` is a list of definition GROUPS; each group is a list of
        # inline nodes (the definition body). Map the first group's inlines.
        set descInlines {}
        if {[llength $defs] > 0} {
            set group [lindex $defs 0]
            if {[llength $group] > 0} {
                set first [lindex $group 0]
                set ft [expr {[dict exists $first type] ? [dict get $first type] : ""}]
                if {$ft in {paragraph heading pre list deflist table blockquote}} {
                    foreach b $group {
                        if {[dict exists $b content]} {
                            foreach m [docir::md::_mapInlines [dict get $b content]] {
                                lappend descInlines $m
                            }
                        }
                    }
                } else {
                    set descInlines [docir::md::_mapInlines $group]
                }
            }
        }
        lappend items [dict create \
            type    listItem \
            content $descInlines \
            meta    [dict create kind dl term $term]]
    }
    return [list [dict create \
        type    list \
        content $items \
        meta    [dict create kind dl indentLevel 0]]]
}

proc docir::md::_mapTable {block} {
    # Seit A.3 Lesart 2 (2026-05-07):
    # Der mdparser-AST emittiert Tabellen bereits in der DocIR-Form
    # (rekursive tableRow/tableCell-Knoten). Der Mapper reicht die
    # Struktur durch und mappt nur die Inlines pro Cell auf das
    # DocIR-Inline-Schema. Vorher wurde die Tabelle aus den flachen
    # headerInlines/rowsInlines neu aufgebaut.
    set rows {}
    foreach row [dict get $block content] {
        set cells {}
        foreach cell [dict get $row content] {
            set cellMeta [_dictDef $cell meta {}]
            lappend cells [dict create \
                type    tableCell \
                content [docir::md::_mapInlines [dict get $cell content]] \
                meta    $cellMeta]
        }
        set rowMeta [_dictDef $row meta {}]
        lappend rows [dict create \
            type    tableRow \
            content $cells \
            meta    $rowMeta]
    }
    set tableMeta [_dictDef $block meta {}]
    return [dict create \
        type    table \
        content $rows \
        meta    $tableMeta]
}

proc docir::md::_mapFootnoteSection {block} {
    # mdparser: {type footnote_section footnotes {{type footnote_def id num content}...}}
    # DocIR-Spec: {type footnote_section content {footnote_def-list} meta {}}
    set defs {}
    set fns [_dictDef $block footnotes {}]
    foreach fn $fns {
        set id  [expr {[dict exists $fn id]  ? [dict get $fn id]  : ""}]
        set num [_dictDef $fn num ""]
        set inlines [docir::md::_mapInlines \
            [_dictDef $fn content {}]]
        lappend defs [dict create \
            type    footnote_def \
            content $inlines \
            meta    [dict create id $id num $num]]
    }
    return [list [dict create \
        type    footnote_section \
        content $defs \
        meta    {}]]
}

# Block-Image: ![alt](url "title") als eigenständiger Block.
# mdparser-AST: {type image alt "..." url "..." [title "..."]?}
# DocIR-Spec: {type image content {} meta {url alt title}}
proc docir::md::_mapImageBlock {block} {
    set alt   [expr {[dict exists $block alt]   ? [dict get $block alt]   : ""}]
    set url   [expr {[dict exists $block url]   ? [dict get $block url]   : ""}]
    set title [_dictDef $block title ""]
    # url-quirk: mdparser packt manchmal Title in url-Feld
    if {$title eq "" && [regexp {^(\S+)\s+"([^"]*)"} $url full u t]} {
        set url $u
        set title $t
    }
    set meta [dict create url $url alt $alt]
    if {$title ne ""} { dict set meta title $title }
    return [dict create \
        type    image \
        content {} \
        meta    $meta]
}

# ============================================================
# Inline-Mapping
# ============================================================
# mdparser-Inlines: {type text value "..."}, {type strong content [...]},
# {type emphasis content [...]}, {type link label [...] url "..."},
# {type image alt "..." url "..."}, {type linebreak}, {type code value "..."},
# {type footnote_ref id "..."}, {type emoji ...}

proc docir::md::_mapInlines {inlines} {
    set result {}
    foreach inline $inlines {
        set t [dict get $inline type]
        switch $t {
            text {
                set v [_dictDef $inline value ""]
                lappend result [dict create type text text $v]
            }
            strong {
                set inner [docir::md::_mapInlines \
                    [_dictDef $inline content {}]]
                foreach i $inner {
                    lappend result [dict create type strong text [_inlineText $i]]
                }
            }
            emphasis {
                set inner [docir::md::_mapInlines \
                    [_dictDef $inline content {}]]
                foreach i $inner {
                    lappend result [dict create type emphasis text [_inlineText $i]]
                }
            }
            code -
            inline_code {
                set v [_dictDef $inline value ""]
                lappend result [dict create type code text $v]
            }
            link {
                set url   [expr {[dict exists $inline url]   ? [dict get $inline url]   : ""}]
                set label [_dictDef $inline label {}]
                set txt   [docir::md::_inlinesToText $label]
                lappend result [dict create type link text $txt name "" section "" href $url]
            }
            image {
                # Markdown image inline: {type image alt "..." url "..." title "..."?}
                # → DocIR image inline mit text=alt, url, optional title
                set alt   [expr {[dict exists $inline alt]   ? [dict get $inline alt]   : ""}]
                set url   [expr {[dict exists $inline url]   ? [dict get $inline url]   : ""}]
                set title [_dictDef $inline title ""]
                # url kann manchmal "img.png \"Title\"" sein (mdparser-Quirk):
                # Title separieren wenn er drin steckt
                if {$title eq "" && [regexp {^(\S+)\s+"([^"]*)"} $url full u t]} {
                    set url $u
                    set title $t
                }
                set inlineDict [dict create type image text $alt url $url]
                if {$title ne ""} { dict set inlineDict title $title }
                lappend result $inlineDict
            }
            linebreak {
                # Hard break: kein text-Feld nötig in DocIR-Spec
                lappend result [dict create type linebreak]
            }
            strike {
                # mdparser: {type strike content {nested-inlines}}
                # DocIR: ein strike-Inline pro Text-Stück (analog zu strong)
                set inner [docir::md::_mapInlines \
                    [_dictDef $inline content {}]]
                foreach i $inner {
                    lappend result [dict create type strike text [_inlineText $i]]
                }
            }
            span {
                # TIP-700: {type span content {nested} class? id?}
                set cls [_dictDef $inline class ""]
                set id  [expr {[dict exists $inline id]    ? [dict get $inline id]    : ""}]
                set inner [docir::md::_mapInlines \
                    [_dictDef $inline content {}]]
                foreach i $inner {
                    set spanDict [dict create type span text [_inlineText $i]]
                    if {$cls ne ""} { dict set spanDict class $cls }
                    if {$id  ne ""} { dict set spanDict id $id }
                    lappend result $spanDict
                }
            }
            footnote_ref {
                # mdparser: {type footnote_ref id "..." num "..."?}
                # DocIR-Spec: footnote_ref braucht text (=display marker) und id
                set id  [expr {[dict exists $inline id]  ? [dict get $inline id]  : ""}]
                set num [_dictDef $inline num $id]
                lappend result [dict create type footnote_ref text $num id $id]
            }
            math {
                # mdparser: {type math display 0|1 text "..."}
                # DocIR: math inline mit display-Flag
                set txt [_dictDef $inline text ""]
                set disp [_dictDef $inline display 0]
                lappend result [dict create type math text $txt display $disp]
            }
            default {
                # Unbekannter Inline-Typ (span, strike, mark, ...).
                # Wenn 'content' vorhanden ist (verschachtelte Inlines):
                # rekursiv verarbeiten — damit verlieren wir den Text
                # nicht. Sonst 'value' nehmen, sonst Marker-Text.
                #
                # Wichtig: Klammern mit \[..\] escapen, sonst loest
                # Tcl Kommando-Substitution aus und versucht den
                # Typnamen als Befehl auszufuehren.
                if {[dict exists $inline content]} {
                    set inner [docir::md::_mapInlines [dict get $inline content]]
                    foreach i $inner { lappend result $i }
                } elseif {[dict exists $inline value]} {
                    lappend result [dict create type text text [dict get $inline value]]
                } else {
                    lappend result [dict create type text text "\[$t\]"]
                }
            }
        }
    }
    return $result
}

# Helper: Extract text from a single DocIR-Inline
proc docir::md::_inlineText {inline} {
    if {[dict exists $inline text]} { return [dict get $inline text] }
    return ""
}

# Helper: All Inlines → plain text (for link-labels etc.)
proc docir::md::_inlinesToText {inlines} {
    set out ""
    foreach i $inlines {
        if {[dict exists $i value]} { append out [dict get $i value] }
        if {[dict exists $i content]} {
            append out [docir::md::_inlinesToText [dict get $i content]]
        }
    }
    return $out
}
