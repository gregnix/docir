# docir-mdSource-0.2.tm
#
# Mapper: mdparser-0.2 AST  →  DocIR 0.2
#
# 0.2 (2026-10-26), for mdstack::parser 0.9.0 (TIP 700 format):
#   - span: class (the classes, space separated), id and attrs (dict of the
#     other attributes, e.g. type="Tcl_Interp", version="TIP500") are passed
#     on to the span node.
#   - definition list items with blocks (AST field defblocks): the listItem
#     gets `blocks` (paragraphs, lists, code, inner definition lists ...),
#     content keeps the flat text as before for content-only sinks.
#   - heading alias anchors (section references) go to meta alias.
#
# Converts the nested mdparser tree into a flat
# DocIR sequence (depth-first, SAX-like).
#
# Namespace: ::docir::md
# Requires:  mdparser 0.2  (for the AST)
# Tcl 8.6+ / 9.x compatible

package provide docir::mdSource 0.2

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
            part    [if {[dict exists $meta part]} {dict get $meta part} else {lindex ""}]]]

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
        html_block   {
            # Raw block HTML (CommonMark). Same trick as math_block: it rides
            # in a pre node with a kind in meta, so no new core block type and
            # no schema bump is needed. The HTML sink passes it through
            # verbatim, the Markdown sink writes it back out unfenced, and
            # every other sink shows the source in a code block -- honest, and
            # far better than the silent drop before mdstack::parser 0.8.0.
            set txt [dict get $block content]
            return [list [dict create \
                type pre \
                content [list [dict create type text text $txt]] \
                meta [dict create kind html]]]
        }
        math_block   {
            # Mark display math as a pre block with kind=math.
            # HTML-Sink kann es als <div class="math display"> rendern,
            # MD-Sink als $$...$$, TXT-Sink als eingerueckter Text.
            # Content as a text-inline list so the DocIR validator does not
            # complain (content must be an inline list, not a string).
            set txt [dict get $block content]
            return [list [dict create \
                type pre \
                content [list [dict create type text text $txt]] \
                meta [dict create kind math display 1]]]
        }
        default      {
            # Unbekannter Block-Typ (image, video, ...). Wenn er
            # has 'content', as a paragraph with recursively processed
            # Inlines emittieren. Sonst Marker-Text einfuegen.
            #
            # Important: escape the brackets around $t with \[..\], otherwise
            # Tcl triggers command substitution and tries to run the type name
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
    set meta [dict create level $level id $anchor]
    # further anchors of this heading (parser 0.9.0: target of a section
    # reference whose plain anchor an earlier heading has)
    if {[dict exists $block alias]} { dict set meta alias [dict get $block alias] }
    return [dict create \
        type    heading \
        content $inlines \
        meta    $meta]
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

    set loose [expr {[dict exists $block loose] ? [dict get $block loose] : 0}]
    foreach item [dict get $block items] {
        set blocks [dict get $item blocks]
        # Split the item's own paragraphs (rendered inside the <li>) from
        # non-paragraph blocks such as sub-lists (kept as trailing siblings —
        # the existing flat-IR behaviour for nested structures).
        set paras {}
        set mappedBlocks {}
        set taggedRest {}
        foreach b $blocks {
            if {[dict get $b type] eq "paragraph"} {
                set _pn [dict create type paragraph \
                    content [docir::md::_mapInlines [dict get $b content]] meta {}]
                lappend paras $_pn
                lappend mappedBlocks $_pn
            } else {
                foreach _mb [docir::md::_mapBlock $b] {
                    lappend mappedBlocks $_mb
                    set _mm [expr {[dict exists $_mb meta] ? [dict get $_mb meta] : {}}]
                    dict set _mb meta [dict merge $_mm {_listSibling 1}]
                    lappend taggedRest $_mb
                }
            }
        }
        # content carries ALL paragraphs (space-separated) so renderers that do
        # not yet read `blocks` (pdf/roff/odt) still show the full text without
        # data loss. Renderers that understand `blocks` (html) use those for
        # proper per-paragraph <p> separation.
        set descInlines {}
        set firstP 1
        foreach pnode $paras {
            if {$firstP} { set firstP 0 } else {
                lappend descInlines [dict create type text text " "]
            }
            lappend descInlines {*}[dict get $pnode content]
        }

        set itemNode [dict create \
            type    listItem \
            content $descInlines \
            meta    [dict create kind $kind term {}]]
        # Loose / multi-paragraph item: carry the paragraph blocks additively so
        # renderers can emit <p>…</p> per paragraph. Tight single-paragraph items
        # keep only `content` (unchanged, fully backward-compatible).
        if {[llength $mappedBlocks] > 1 || [llength $taggedRest] > 0} {
            dict set itemNode blocks $mappedBlocks
        }
        lappend items $itemNode
        lappend trailing {*}$taggedRest
    }

    set _lmeta [dict create kind $kind indentLevel 0 loose $loose]
    if {[dict exists $block start]} { dict set _lmeta start [dict get $block start] }
    set listNode [dict create \
        type    list \
        content $items \
        meta    $_lmeta]

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
    set id  [if {[dict exists $block id]} {dict get $block id} else {lindex ""}]
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
        # inline nodes (one definition paragraph). Map ALL groups so Pandoc
        # multi-paragraph / continuation definitions are kept (mapping only the
        # first group dropped continuation paragraphs, which then reappeared as
        # indented code blocks elsewhere). Consecutive paragraphs are separated
        # by a blank line (two linebreaks) so they wrap as flowing text.
        set descInlines {}
        set firstGroup 1
        foreach group $defs {
            if {[llength $group] == 0} continue
            if {!$firstGroup} {
                lappend descInlines [dict create type linebreak]
                lappend descInlines [dict create type linebreak]
            }
            set firstGroup 0
            set first [lindex $group 0]
            set ft [if {[dict exists $first type]} {dict get $first type} else {lindex ""}]
            if {$ft in {paragraph heading pre list deflist table blockquote}} {
                set firstBlock 1
                foreach b $group {
                    if {[dict exists $b content]} {
                        if {!$firstBlock} {
                            lappend descInlines [dict create type linebreak]
                            lappend descInlines [dict create type linebreak]
                        }
                        set firstBlock 0
                        foreach m [docir::md::_mapInlines [dict get $b content]] {
                            lappend descInlines $m
                        }
                    }
                }
            } else {
                foreach m [docir::md::_mapInlines $group] {
                    lappend descInlines $m
                }
            }
        }
        set itemNode [dict create \
            type    listItem \
            content $descInlines \
            meta    [dict create kind dl term $term]]
        # Definitions holding blocks (parser 0.9.0, field defblocks): the
        # item carries them as `blocks` -- the full sequence, paragraphs,
        # lists, code, inner definition lists. `content` stays the flat
        # text above, so a sink that reads only content loses nothing.
        if {[dict exists $dl defblocks]} {
            set bl {}
            foreach db [dict get $dl defblocks] {
                foreach b $db {
                    foreach mb [docir::md::_mapBlock $b] {
                        # tagged copies of nested list blocks are for
                        # content-only sinks at the top level; inside
                        # blocks the nested list renders them itself
                        if {[dict exists $mb meta]
                                && [dict exists [dict get $mb meta] _listSibling]} continue
                        lappend bl $mb
                    }
                }
            }
            if {[llength $bl] > 0} { dict set itemNode blocks $bl }
        }
        lappend items $itemNode
    }
    return [list [dict create \
        type    list \
        content $items \
        meta    [dict create kind dl indentLevel 0]]]
}

proc docir::md::_mapTable {block} {
    # Seit A.3 Lesart 2 (2026-05-07):
    # The mdparser AST already emits tables in DocIR form
    # (recursive tableRow/tableCell nodes). The mapper passes the
    # structure through and only maps the inlines per cell onto the
    # DocIR inline schema. Previously the table was built from the flat
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
        set id  [if {[dict exists $fn id]} {dict get $fn id} else {lindex ""}]
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

# Block image: ![alt](url "title") as a standalone block.
# mdparser-AST: {type image alt "..." url "..." [title "..."]?}
# DocIR-Spec: {type image content {} meta {url alt title}}
proc docir::md::_mapImageBlock {block} {
    set alt   [if {[dict exists $block alt]} {dict get $block alt} else {lindex ""}]
    set url   [if {[dict exists $block url]} {dict get $block url} else {lindex ""}]
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
                lappend result {*}[docir::md::_mapWrapped strong $inline]
            }
            emphasis {
                lappend result {*}[docir::md::_mapWrapped emphasis $inline]
            }
            code -
            inline_code {
                set v [_dictDef $inline value ""]
                lappend result [dict create type code text $v]
            }
            link {
                set url   [if {[dict exists $inline url]} {dict get $inline url} else {lindex ""}]
                set label [_dictDef $inline label {}]
                set txt   [docir::md::_astInlinesText $label]
                set title [_dictDef $inline title ""]
                # url-quirk: a title may be packed into the url as: url "title"
                if {$title eq "" && [regexp {^(\S+)\s+"([^"]*)"} $url full u t]} {
                    set url $u
                    set title $t
                }
                set linkDict [dict create type link text $txt name "" section "" href $url]
                if {$title ne ""} { dict set linkDict title $title }
                lappend result $linkDict
            }
            image {
                # Markdown image inline: {type image alt "..." url "..." title "..."?}
                # -> DocIR image inline with text=alt, url, optional title
                set alt   [if {[dict exists $inline alt]} {dict get $inline alt} else {lindex ""}]
                set url   [if {[dict exists $inline url]} {dict get $inline url} else {lindex ""}]
                set title [_dictDef $inline title ""]
                # url kann manchmal "img.png \"Title\"" sein (mdparser-Quirk):
                # separate the title if it is embedded
                if {$title eq "" && [regexp {^(\S+)\s+"([^"]*)"} $url full u t]} {
                    set url $u
                    set title $t
                }
                set inlineDict [dict create type image text $alt url $url]
                if {$title ne ""} { dict set inlineDict title $title }
                lappend result $inlineDict
            }
            linebreak {
                # Hard break: no text field needed in the DocIR spec
                lappend result [dict create type linebreak]
            }
            softbreak {
                # Soft break: html renders "\n", other sinks render a space.
                lappend result [dict create type softbreak]
            }
            strike {
                # mdparser: {type strike content {nested-inlines}}
                # DocIR: one strike inline per text piece (analogous to strong)
                lappend result {*}[docir::md::_mapWrapped strike $inline]
            }
            span {
                # TIP-700: {type span content {nested} class? id? attrs?}
                # class holds all classes, space separated ("carg in").
                # The whole span content becomes the text of ONE span node,
                # with softbreaks turned into spaces. A span split across a
                # source-text line break ([a\nb]{.c}) arrives as
                # text/softbreak/text; flattening it here keeps it a single
                # node for every sink (PDF, HTML, ...), instead of emitting
                # one span per inner inline.
                set cls [_dictDef $inline class ""]
                set id  [if {[dict exists $inline id]} {dict get $inline id} else {lindex ""}]
                set inner [docir::md::_mapInlines \
                    [_dictDef $inline content {}]]
                set buf ""
                foreach i $inner {
                    if {[dict get $i type] eq "softbreak"} {
                        append buf " "
                    } else {
                        append buf [_inlineText $i]
                    }
                }
                set spanDict [dict create type span text [string trim $buf]]
                if {$cls ne ""} { dict set spanDict class $cls }
                if {$id  ne ""} { dict set spanDict id $id }
                # further attributes (parser 0.9.0): {type Tcl_Interp},
                # {version TIP500} -- for sinks that can show them (HTML
                # data-*, Markdown); the others print the text as before
                set attrs [_dictDef $inline attrs {}]
                if {[dict size $attrs] > 0} { dict set spanDict attrs $attrs }
                lappend result $spanDict
            }
            footnote_ref {
                # mdparser: {type footnote_ref id "..." num "..."?}
                # DocIR spec: footnote_ref needs text (=display marker) and id
                set id  [if {[dict exists $inline id]} {dict get $inline id} else {lindex ""}]
                set num [_dictDef $inline num $id]
                lappend result [dict create type footnote_ref text $num id $id]
            }
            math {
                # mdparser: {type math display 0|1 text "..."}
                # DocIR: math inline with a display flag
                set txt [_dictDef $inline text ""]
                set disp [_dictDef $inline display 0]
                lappend result [dict create type math text $txt display $disp]
            }
            default {
                # Unbekannter Inline-Typ (span, strike, mark, ...).
                # If 'content' is present (nested inlines):
                # process recursively — this way we lose the text
                # not. Otherwise take 'value', otherwise the marker text.
                #
                # Important: escape the brackets with \[..\], otherwise
                # Tcl triggers command substitution and tries to run the
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
# Helper: map a wrapping inline (strong/emphasis/strike) to DocIR.
#
# DocIR carries the text on the node itself, so a wrapper spanning several
# inner inlines becomes one node per piece. A softbreak inside the wrapper
# (source text wrapped across a line) must not vanish -- it is the space
# between the two words and is emitted as such. Without this the two pieces
# are glued together: "one word</em><em></em><em>next word".
#
# Compare the `span` branch, which flattens softbreaks the same way.
#
# A span or link inside the wrapper keeps its own node: flattening it to
# {type strong text ...} lost the class (an index marker **[x]{.index}** had
# no index entry and no anchor) and the href of a link. The wrapper goes into
# the optional field `style` (a list, innermost first: ***[x]{.index}*** ->
# style {strong emphasis}); renderers that know the field apply it.
proc docir::md::_mapWrapped {type inline} {
    set out {}
    set inner [docir::md::_mapInlines [_dictDef $inline content {}]]
    foreach i $inner {
        if {[dict get $i type] eq "softbreak"} {
            lappend out [dict create type $type text " "]
        } elseif {[dict get $i type] in {span link}} {
            dict lappend i style $type
            lappend out $i
        } else {
            lappend out [dict create type $type text [_inlineText $i]]
        }
    }
    return $out
}

proc docir::md::_inlineText {inline} {
    if {[dict exists $inline text]} { return [dict get $inline text] }
    return ""
}

# Helper: parser inlines (AST, field `value`) -> plain text, for link labels.
# Own name: the Markdown renderer (md-0.1.tm, same namespace) has a
# _inlinesToText for IR inlines (field `text`). Whichever file was sourced
# last won; with the renderer loaded after this file every link label came
# out empty (seen 2026-10-21 in test-mdstack-bridge).
proc docir::md::_astInlinesText {inlines} {
    set out ""
    foreach i $inlines {
        if {[dict exists $i value]} { append out [dict get $i value] }
        if {[dict exists $i content]} {
            append out [docir::md::_astInlinesText [dict get $i content]]
        }
    }
    return $out
}
