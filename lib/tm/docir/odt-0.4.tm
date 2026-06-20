## odt-0.4.tm  --  DocIR -> ODT (sink), built on the odf library
## Convention: docir-FORMAT (sink). Writes a .odt file from a DocIR block list.
##
##   docir::odt::write $ir $path ?options?
##   options: media   dict url->bytes  (image bytes, e.g. from extractParts)
##
## Backend: odf (odf::newTextDoc + odf::Styles + odf::Text + Package save).
## The conformance details (mimetype-first/stored + valid DOS timestamp,
## namespace binding, automatic-styles placement, style:style child order,
## draw:frame order, manifest media types) all live in odf and are exercised
## by its test suite -- this sink only maps DocIR blocks/inlines onto odf's
## builder API. No hand-rolled XML, no own ZIP writer.
##
## Block types: doc_meta/doc_header/hr (skipped), heading, paragraph, pre,
## blank, list (nested), table, image. Inlines: text, strong, emphasis, code,
## underline, strike, span (class=style), link, linebreak. Embedded "\n"/"\t"
## inside a run become text:line-break / text:tab.
##
## Named styles written to styles.xml (so docir::odtSource resolves them back
## to the same bold/italic/mono classification on round-trip):
##   Heading_1..6, Code (paragraph); Bold, Italic, Mono, Underline, Strike (text).

package require Tcl 8.6 9
package require odf::text
package require odf::style

namespace eval docir::odt {
    namespace export write
    variable _flowCnt 0
}

## ---------- helpers ----------

## Image media type from magic bytes (PNG/JPEG/GIF), extension as fallback.
## Explicit -- the manifest entry must carry a correct type or LibreOffice
## shows nothing (see odf-erzeugen-fallen.md).
proc docir::odt::_dictDef {d k {def ""}} {
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}
proc docir::odt::_mediaType {bytes url} {
    if {[string range $bytes 1 3] eq "PNG"}        { return image/png }
    if {[string range $bytes 0 1] eq "\xFF\xD8"}   { return image/jpeg }
    if {[string range $bytes 0 2] eq "GIF"}        { return image/gif }
    switch -- [string tolower [file extension $url]] {
        .jpg - .jpeg { return image/jpeg }
        .gif         { return image/gif }
        default      { return image/png }
    }
}

## First text:p child of a node (the cell/item paragraph odf created).
proc docir::odt::_firstP {node} {
    foreach c [$node childNodes] {
        if {[$c nodeType] eq "ELEMENT_NODE" && [$c nodeName] eq "text:p"} { return $c }
    }
    return ""
}

## Emit a plain string into $node, turning embedded "\n" into text:line-break
## and "\t" into text:tab (the rest as text nodes).
proc docir::odt::_emit {txt node s} {
    set buf ""
    foreach ch [split $s ""] {
        switch -- $ch {
            "\n" { if {$buf ne ""} { $txt addText $node $buf; set buf "" }; $txt addBreak $node }
            "\t" { if {$buf ne ""} { $txt addText $node $buf; set buf "" }; $txt addTab   $node }
            default { append buf $ch }
        }
    }
    if {$buf ne ""} { $txt addText $node $buf }
}

## Render an inline list into paragraph/heading/span node $p.
proc docir::odt::_inlines {txt p inlines} {
    foreach inl $inlines {
        set type [dict get $inl type]
        set str  [_dictDef $inl text ""]
        switch -- $type {
            linebreak { $txt addBreak $p }
            softbreak { _emit $txt $p " " }
            text      { _emit $txt $p $str }
            link {
                set href [_dictDef $inl href ""]
                $txt addLink $p $str $href
            }
            strong - emphasis - code - underline - strike - span {
                switch -- $type {
                    strong    { set style Bold }
                    emphasis  { set style Italic }
                    code      { set style Mono }
                    underline { set style Underline }
                    strike    { set style Strike }
                    span      { set style [_dictDef $inl class ""] }
                }
                # empty span, then emit text (keeps embedded breaks/tabs inside it)
                set sp [$txt addSpan $p "" $style]
                _emit $txt $sp $str
            }
            default { }
        }
    }
}

# Render a definition list (meta.kind == dl): each item as a bold term
# paragraph followed by an indented definition paragraph (no bullets).
proc docir::odt::_fillDeflist {txt listsVar iVar} {
    upvar 1 $listsVar lists $iVar i
    set node [lindex $lists $i]
    incr i
    foreach it [dict get $node content] {
        set term [_dictDef [_dictDef $it meta {}] term {}]
        set tp [$txt appendParagraph "" DefTerm]
        if {[llength $term]} { _inlines $txt $tp $term }
        set body [dict get $it content]
        if {[llength $body]} {
            _inlines $txt [$txt appendParagraph "" DefBody] $body
        }
    }
}

proc docir::odt::_listStyle {node} {
    set m [_dictDef $node meta {}]
    set kind [_dictDef $m kind "ul"]
    if {$kind ne "ol"} { return docir_ul }
    switch -- [_dictDef $m numFormat "1"] {
        a       { return docir_ol_a }
        A       { return docir_ol_A }
        i       { return docir_ol_i }
        I       { return docir_ol_I }
        default { return docir_ol }
    }
}
proc docir::odt::_listLevel {node} {
    set m [_dictDef $node meta {}]
    return [_dictDef $m indentLevel 0]
}

## Fill an already-attached text:list element from a run of consecutive flat
## list blocks: the items of the current block, then any following blocks of
## deeper indentLevel are hung off the LAST item as sublists -- so odtSource
## reads them back to the same flat indentLevel sequence. Mirrors the old
## _renderListAt nesting. Advances the shared index i past the whole run.
proc docir::odt::_fillList {txt listEl listsVar iVar L} {
    upvar 1 $listsVar lists $iVar i
    set node  [lindex $lists $i]
    set items [dict get $node content]
    incr i
    set n  [llength $lists]
    set ni [llength $items]
    set lastItem ""
    for {set k 0} {$k < $ni} {incr k} {
        set it   [lindex $items $k]
        set item [$txt addListItem $listEl "" ListItem]
        _inlines $txt [_firstP $item] [dict get $it content]
        set lastItem $item
    }
    if {$ni == 0} { set lastItem [$txt addListItem $listEl "" ListItem] }
    while {$i < $n && [_listLevel [lindex $lists $i]] > $L} {
        set subL [_listLevel [lindex $lists $i]]
        set sub  [$txt addSublist $lastItem [_listStyle [lindex $lists $i]]]
        _fillList $txt $sub lists i $subL
    }
}

## One non-list block onto the body via $txt; image blocks embed bytes into $pkg.
## Render a tuflow flow-diagram block to a PNG, add it as a package part and
## reference it. Returns 1 on success, 0 to fall back to a Code paragraph.
proc docir::odt::_emitFlow {txt pkg node mediaOutVar} {
    upvar 1 $mediaOutVar mediaOut
    variable _flowCnt
    set src ""
    foreach i [dict get $node content] {
        if {[dict exists $i text]} { append src [dict get $i text] }
    }
    if {[catch {
        package require tclutils::tuflow
        set png [::tclutils::tudiagram::toPng [::tclutils::tuflow::parse $src]]
    }]} { return 0 }
    set name "Pictures/flow[incr _flowCnt].png"
    if {[catch {
        $pkg addpart $name $png [_mediaType $png $name]
        dict set mediaOut $name $png
        $txt appendImageFit $name -name img -anchor as-char
    }]} { return 0 }
    return 1
}

proc docir::odt::_block {txt pkg node mediaInVar mediaOutVar} {
    upvar 1 $mediaInVar mediaIn $mediaOutVar mediaOut
    set type [dict get $node type]
    set meta [_dictDef $node meta {}]
    switch -- $type {
        doc_meta - doc_header - hr { }
        heading {
            set lvl [_dictDef $meta level 1]
            _inlines $txt [$txt appendHeading "" $lvl "Heading_$lvl"] [dict get $node content]
        }
        paragraph {
            _inlines $txt [$txt appendParagraph "" Body] [dict get $node content]
        }
        pre {
            set lang [_dictDef $meta language ""]
            if {[string tolower $lang] in {flow tuflow mermaid} \
                    && [_emitFlow $txt $pkg $node mediaOut]} {
                # embedded as a diagram image
            } else {
                _inlines $txt [$txt appendParagraph "" Code] [dict get $node content]
            }
        }
        blank {
            $txt appendParagraph "" ""
        }
        table {
            set cols [_dictDef $meta columns 1]
            set tab  [$txt appendTable $cols]
            foreach row [dict get $node content] {
                set rmeta    [_dictDef $row meta {}]
                set isHeader [expr {[dict exists $rmeta kind] && [dict get $rmeta kind] eq "header"}]
                set cellsIR  [dict get $row content]
                set blanks   [lrepeat [llength $cellsIR] ""]
                set r [expr {$isHeader ? [$txt addHeaderRow $tab $blanks] : [$txt addRow $tab $blanks]}]
                foreach cn [$txt rowCells $r] ci $cellsIR {
                    _inlines $txt [_firstP $cn] [dict get $ci content]
                }
            }
        }
        image {
            set url [_dictDef $meta url ""]
            if {$url eq "" || ![dict exists $mediaIn $url]} { return }
            set bytes [dict get $mediaIn $url]
            $pkg addpart $url $bytes [_mediaType $bytes $url]
            dict set mediaOut $url $bytes
            # size from the embedded pixels; inline (as-char) like the old sink
            $txt appendImageFit $url -name img -anchor as-char
        }
        default { }
    }
}

## Named styles in styles.xml. Property keys are prefixed (fo:.. / style:..);
## odtSource flattens them to local names (font-weight/font-style/font-family)
## for its bold/italic/mono classification.
proc docir::odt::_defineStyles {pkg} {
    set st [odf::Styles new $pkg]
    foreach {lvl size} {1 20pt 2 16pt 3 14pt 4 13pt 5 12pt 6 11pt} {
        $st defineParagraph Heading_$lvl \
            -text      [list fo:font-weight bold fo:font-size $size fo:color "#1a1a2e"] \
            -paragraph [list fo:margin-top "0.20in" fo:margin-bottom "0.06in" fo:keep-with-next "always"]
    }
    $st defineParagraph Body \
        -paragraph [list fo:margin-bottom "0.09in" fo:line-height "118%"]
    $st defineParagraph Code \
        -text      [list fo:font-family "Courier New" fo:font-size 9.5pt] \
        -paragraph [list fo:background-color "#f4f4f4" fo:margin-left "0.25in" \
                         fo:margin-top "0.04in" fo:margin-bottom "0.09in" fo:padding "0.05in"]
    $st defineParagraph DefTerm \
        -text      [list fo:font-weight bold] \
        -paragraph [list fo:margin-top "0.13in" fo:margin-bottom "0.02in" fo:keep-with-next "always"]
    $st defineParagraph DefBody \
        -paragraph [list fo:margin-left "0.32in" fo:margin-bottom "0.07in"]
    $st defineParagraph ListItem \
        -paragraph [list fo:margin-bottom "0.05in"]
    $st defineText Bold      [list fo:font-weight bold]
    $st defineText Italic    [list fo:font-style italic]
    $st defineText Mono      [list fo:font-family "Courier New"]
    $st defineText Underline [list style:text-underline-style solid]
    $st defineText Strike    [list style:text-line-through-style solid]
    $st defineListStyle docir_ol   -kind ordered -numFormat 1
    $st defineListStyle docir_ol_a -kind ordered -numFormat a
    $st defineListStyle docir_ol_A -kind ordered -numFormat A
    $st defineListStyle docir_ol_i -kind ordered -numFormat i
    $st defineListStyle docir_ol_I -kind ordered -numFormat I
    $st defineListStyle docir_ul   -kind bullet
    $st flush
    $st destroy
}

## ---------- public API ----------
proc docir::odt::write {ir path {options {}}} {
    set mediaIn  [_dictDef $options media {}]
    set mediaOut {}

    set pkg [odf::newTextDoc]
    _defineStyles $pkg
    set txt [odf::Text new $pkg]
    try {
        set n [llength $ir]
        for {set i 0} {$i < $n} {} {
            set node [lindex $ir $i]
            if {[dict get $node type] eq "list"} {
                if {[_dictDef [_dictDef $node meta {}] kind ""] eq "dl"} {
                    _fillDeflist $txt ir i
                } else {
                    _fillList $txt [$txt appendList [_listStyle $node]] ir i [_listLevel $node]
                }
            } else {
                _block $txt $pkg $node mediaIn mediaOut
                incr i
            }
        }
        $txt flush
        $pkg save $path
    } finally {
        $txt destroy
        $pkg destroy
    }
    return $path
}

package provide docir::odt 0.4
