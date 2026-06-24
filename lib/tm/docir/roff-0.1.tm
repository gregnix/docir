# docir-roff-0.1.tm -- DocIR -> nroff (sink)
#
# Converts a DocIR sequence into nroff markup. The seventh sink in
# DocIR hub. Target format: Tcl/Tk manpage convention (.TH, .SH, .SS,
# .PP, .CS/.CE, .TP, .IP, .OP, .SO/.SE, .QW).
#
# Naming-Konflikt: docir-roff-source ist die QUELLE (nroff-AST → DocIR
# via ::docir::roff::fromAst). docir-roff ist die SENKE (DocIR → nroff
# via ::docir::roff::render). Beide teilen Namespace ::docir::roff,
# unterscheiden sich in den Funktionen — koexistieren konfliktfrei.
#
# Usage:
#   package require docir-roff
#   set nroff [::docir::roff::render $ir]
#   set nroff [::docir::roff::render $ir [dict create headingShift 0]]
#
# Optionen:
#   headingShift   integer (default 0): zur Verschiebung von Heading-Levels
#   wrapColumn     integer (default 0): if > 0, hard line breaks
#                  within paragraphs at this column
#   forceQuoting   bool (default 0): strings with special characters in .QW
#                  einwickeln (statt inline-Escapes)
#
# Round-Trip-Hinweise:
#   - Soft-Hyphen, Kerning-Hints, manuelle Layout-Anweisungen gehen
#     lost (DocIR is semantic, not typographic)
#   - whitespace normalization: consecutive spaces become
#     einem zusammengefasst (nroff verhalten sich ohnehin so)
#   - tables are mapped to the standard-options pattern (.SO/.SE)
#     if meta.kind eq "standardOptions", otherwise to a .TS/.TE block

package provide docir::roff 0.1
package require docir 0.1

namespace eval ::docir::roff {
    namespace export render
    variable opts {}
}

# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------

# render ir ?options?
#   options: dict with keys headingShift / wrapColumn / forceQuoting
proc docir::roff::_dictDef {d k {def ""}} {
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}

proc ::docir::roff::render {ir {options {}}} {
    variable opts
    set opts [dict create \
        headingShift 0 \
        wrapColumn   0 \
        forceQuoting 0]
    foreach k [dict keys $options] {
        dict set opts $k [dict get $options $k]
    }

    set out ""
    set inList 0
    foreach node $ir {
        append out [_renderBlock $node]
    }
    # Trailing-Newlines normalisieren — genau ein abschliessendes "\n"
    set out [string trimright $out "\n"]
    append out "\n"
    return $out
}

# ------------------------------------------------------------------
# Block-Dispatch
# ------------------------------------------------------------------

proc ::docir::roff::_renderBlock {node} {
    set t [dict get $node type]
    switch -- $t {
        doc_header { return [_renderDocHeader $node] }
        heading    { return [_renderHeading   $node] }
        paragraph  { return [_renderParagraph $node] }
        pre        { return [_renderPre       $node] }
        list       { return [_renderList      $node] }
        blank      { return [_renderBlank     $node] }
        hr         { return [_renderHr        $node] }
        table      { return [_renderTable     $node] }
        image      { return [_renderImageBlock $node] }
        footnote_section { return [_renderFootnoteSection $node] }
        footnote_def     { return [_renderFootnoteDef $node] }
        div        { return [_renderDiv $node] }
        listItem   { return [_renderOrphanedListItem $node] }
        default    {
            if {[::docir::isSchemaOnly $t]} { return "" }
            return [_renderUnknown $node "type=$t unknown"]
        }
    }
}

# ------------------------------------------------------------------
# doc_header → .TH
# ------------------------------------------------------------------
# .TH name section [date] [version] [part]

proc ::docir::roff::_renderDocHeader {node} {
    set m [_dictDef $node meta {}]
    set name    [expr {[dict exists $m name]    ? [dict get $m name]    : ""}]
    set section [_dictDef $m section ""]
    set version [_dictDef $m version ""]
    set part    [expr {[dict exists $m part]    ? [dict get $m part]    : ""}]

    if {$name eq "" && $section eq ""} { return "" }

    set parts [list ".TH"]
    lappend parts [_quoteArg $name]
    lappend parts [_quoteArg $section]
    if {$version ne ""} {
        lappend parts [_quoteArg $version]
    }
    if {$part ne ""} {
        # If version is empty but part is present, we need a
        # Platzhalter dazwischen
        if {$version eq ""} {
            lappend parts {""}
        }
        lappend parts [_quoteArg $part]
    }
    return "[join $parts { }]\n"
}

# ------------------------------------------------------------------
# heading → .SH (level 1) / .SS (level 2+)
# ------------------------------------------------------------------

proc ::docir::roff::_renderHeading {node} {
    variable opts
    set m  [_dictDef $node meta {}]
    set lv [_dictDef $m level 1]
    incr lv [dict get $opts headingShift]
    if {$lv < 1} { set lv 1 }

    set txt [_renderInlines [dict get $node content]]

    # Heading texts are traditionally UPPERCASED in nroff
    # for .SH (top level). We do not change that automatically — the
    # user source already provides it that way. If not, that is a
    # bewusste Entscheidung des Autoren.

    if {$lv == 1} {
        return ".SH [_quoteArg $txt]\n"
    } else {
        return ".SS [_quoteArg $txt]\n"
    }
}

# ------------------------------------------------------------------
# paragraph → .PP + Text
# ------------------------------------------------------------------

proc ::docir::roff::_renderParagraph {node} {
    set txt [_renderInlines [dict get $node content]]
    if {$txt eq ""} { return "" }
    set txt [_protectLeadingDot $txt]
    return ".PP\n$txt\n"
}

# ------------------------------------------------------------------
# pre -> .CS … .CE (Tk convention) OR .nf/.fi (classic)
# ------------------------------------------------------------------

proc ::docir::roff::_renderPre {node} {
    set m    [_dictDef $node meta {}]
    set kind [_dictDef $m kind "code"]

    # content: a pre can either have a text inline with the code as
    # the text field, or raw lines.
    set content [dict get $node content]
    set raw ""
    foreach inline $content {
        if {[dict exists $inline text]} {
            append raw [dict get $inline text]
        }
    }

    # code lines must be protected against a dot at the line start
    set protectedLines {}
    foreach line [split $raw "\n"] {
        lappend protectedLines [_protectLeadingDot $line]
    }
    set body [join $protectedLines "\n"]

    return ".CS\n$body\n.CE\n"
}

# ------------------------------------------------------------------
# list → .TP / .IP / .OP / .RS+.IP nummeriert
# ------------------------------------------------------------------

proc ::docir::roff::_renderList {node} {
    set m    [_dictDef $node meta {}]
    set kind [_dictDef $m kind "tp"]
    set indentLevel [_dictDef $m indentLevel 0]

    set out ""
    # Per Indent-Level ein .RS 4 (relative shift, 4 char)
    for {set i 0} {$i < $indentLevel} {incr i} {
        append out ".RS 4\n"
    }

    set items [dict get $node content]
    set itemNum 0

    foreach item $items {
        incr itemNum
        if {[dict get $item type] ne "listItem"} {
            append out [_renderUnknown $item "non-listItem in list"]
            continue
        }
        append out [_renderListItem $item $kind $itemNum]
    }

    # close all .RS with a matching number of .RE
    for {set i 0} {$i < $indentLevel} {incr i} {
        append out ".RE\n"
    }

    return $out
}

# Ein einzelner listItem im Kontext eines bestimmten Listen-kind
proc ::docir::roff::_renderListItem {item kind itemNum} {
    set itemMeta [_dictDef $item meta {}]
    set term     [_dictDef $itemMeta term {}]
    set descIr   [dict get $item content]

    set termText [_renderInlines $term]
    if {[dict exists $item blocks]} {
        # Loose / multi-paragraph item: one paragraph per block, separated by .sp
        set _parts {}
        foreach _b [dict get $item blocks] {
            lappend _parts [_protectLeadingDot \
                [string trimright [_renderInlines [dict get $_b content]] "\n"]]
        }
        set descText [join $_parts "\n.sp\n"]
    } else {
        set descText [string trimright [_renderInlines $descIr] "\n"]
        set descText [_protectLeadingDot $descText]
    }

    switch -- $kind {
        tp -
        dl {
            # .TP\nterm\ndesc
            set out ".TP\n"
            if {$termText ne ""} {
                append out [_protectLeadingDot $termText] "\n"
            }
            append out $descText "\n"
            return $out
        }
        ip {
            # .IP \(bu\ndesc  (Bullet-List)
            set out ".IP \\(bu\n"
            append out $descText "\n"
            return $out
        }
        ol {
            # .IP [N]\ndesc
            set out ".IP \[$itemNum\]\n"
            append out $descText "\n"
            return $out
        }
        op {
            # .OP cmdName dbName dbClass\ndesc
            # Term ist meist "cmdName|dbName|dbClass" als Text vom
            # docir-roff-source (siehe Bug-Geschichte).
            # we try to recognize the pattern, fallback is
            # cmdName=term, dbName=cmdName, dbClass=term.
            set parts [split $termText "|"]
            if {[llength $parts] >= 3} {
                set cmd [lindex $parts 0]
                set db  [lindex $parts 1]
                set cls [lindex $parts 2]
            } else {
                set cmd $termText
                set db  $termText
                set cls $termText
            }
            # cmd often has a literal "-" before it that in nroff
            # must be protected as "\-"
            if {[string match "-*" $cmd]} {
                set cmd "\\$cmd"
            }
            set out ".OP $cmd $db $cls\n"
            append out $descText "\n"
            return $out
        }
        ap {
            # Argument-Pattern: .AP type name in/out\ndesc
            # we have no specific fields in the listItem meta,
            # daher Fallback auf .TP-Verhalten
            set out ".TP\n"
            if {$termText ne ""} {
                append out [_protectLeadingDot $termText] "\n"
            }
            append out $descText "\n"
            return $out
        }
        ul -
        default {
            # Bullet-List
            set out ".IP \\(bu\n"
            append out $descText "\n"
            return $out
        }
    }
}

# A listItem at the top level (outside a list) — rare,
# usually a schema violation. We output it as a paragraph.
proc ::docir::roff::_renderOrphanedListItem {node} {
    set out [_renderUnknown $node "orphaned listItem (outside list)"]
    return $out
}

# ------------------------------------------------------------------
# blank -> empty line / .sp
# ------------------------------------------------------------------

proc ::docir::roff::_renderBlank {node} {
    set m     [_dictDef $node meta {}]
    set lines [_dictDef $m lines 1]
    if {$lines < 1} { set lines 1 }

    if {$lines == 1} { return ".sp\n" }
    return ".sp $lines\n"
}

# ------------------------------------------------------------------
# hr → "\(em" line as an approximation — nroff has no HR
# ------------------------------------------------------------------

proc ::docir::roff::_renderHr {node} {
    # best approximation: a .sp + line of em dashes.
    # But: this is semantically not the same. Conservative:
    # just an extra empty line.
    return ".sp 2\n"
}

# ------------------------------------------------------------------
# table -> standard-options pattern (.SO/.SE) or .TS/.TE
# ------------------------------------------------------------------

proc ::docir::roff::_renderTable {node} {
    set m    [_dictDef $node meta {}]
    set kind [_dictDef $m kind ""]

    if {$kind eq "standardOptions"} {
        return [_renderStandardOptionsTable $node]
    }
    return [_renderGenericTable $node]
}

# standard-options table: reverse mapping to the Tk convention
# .SO [classname]
# .SE
#
# table content: tableRows with tableCells, each cell an option.
# The Tk convention lists only options without values — they are
# Cross-Referenzen.
proc ::docir::roff::_renderStandardOptionsTable {node} {
    set m         [_dictDef $node meta {}]
    set className [_dictDef $m className ""]

    if {$className ne ""} {
        set out ".SO $className\n"
    } else {
        set out ".SO\n"
    }
    foreach row [dict get $node content] {
        if {[dict get $row type] ne "tableRow"} continue
        foreach cell [dict get $row content] {
            if {[dict get $cell type] ne "tableCell"} continue
            set txt [_renderInlines [dict get $cell content]]
            set txt [string trim $txt]
            if {$txt ne ""} {
                # option names need no -, that is expected in the consumer
                # but traditionally that depends on the nroff
                # source. We output them without a leading \- aus —
                # the original Tk manpages also have them without.
                append out "$txt\n"
            }
        }
    }
    append out ".SE\n"
    return $out
}

# Generische Tabelle als .TS/.TE-Block (tbl-Format).
# Caution: not every nroff renderer has tbl. In Tcl/Tk manpages
# tbl is practically unused — the standard options are the
# einzige Tabellen-Pattern. Daher ist generic-table eher Fallback.
proc ::docir::roff::_renderGenericTable {node} {
    set out ".TS\n"
    set rows [dict get $node content]

    # first row: column spec from the number of cells
    set firstRow [lindex $rows 0]
    if {$firstRow ne "" && [dict exists $firstRow content]} {
        set ncols [llength [dict get $firstRow content]]
        set spec [string repeat "l " $ncols]
        append out [string trim $spec] ".\n"
    }

    foreach row $rows {
        if {[dict get $row type] ne "tableRow"} continue
        set cells {}
        foreach cell [dict get $row content] {
            if {[dict get $cell type] ne "tableCell"} continue
            lappend cells [_renderInlines [dict get $cell content]]
        }
        append out "[join $cells \t]\n"
    }
    append out ".TE\n"
    return $out
}

# ------------------------------------------------------------------
# Unknown — Kommentar + Plain-Text-Fallback
# ------------------------------------------------------------------

proc ::docir::roff::_renderImageBlock {node} {
    # nroff cannot render images. Marker as italic plain text.
    set m [dict get $node meta]
    set url [_dictDef $m url ""]
    set alt [_dictDef $m alt ""]

    set out ".PP\n"
    if {$alt ne "" && $url ne ""} {
        append out "\\fI\[image: [_escapeText $alt] ([_escapeText $url])\]\\fR\n"
    } elseif {$alt ne ""} {
        append out "\\fI\[image: [_escapeText $alt]\]\\fR\n"
    } elseif {$url ne ""} {
        append out "\\fI\[image: [_escapeText $url]\]\\fR\n"
    } else {
        append out "\\fI\[image\]\\fR\n"
    }
    return $out
}

proc ::docir::roff::_renderFootnoteSection {node} {
    # Footnotes are rendered as their own section with .SH "FOOTNOTES".
    # Each footnote_def becomes .TP "[N]" body
    set defs [dict get $node content]
    if {[llength $defs] == 0} { return "" }

    set out ".SH FOOTNOTES\n"
    foreach def $defs {
        if {[dict get $def type] ne "footnote_def"} continue
        append out [_renderFootnoteDef $def]
    }
    return $out
}

proc ::docir::roff::_renderFootnoteDef {node} {
    # .TP "[N]"\nbody
    set m [dict get $node meta]
    set num [_dictDef $m num "?"]
    set body [_renderInlines [dict get $node content]]
    set body [_protectLeadingDot $body]

    set out ".TP\n"
    append out "\[[_escapeText $num]\]\n"
    append out "$body\n"
    return $out
}

proc ::docir::roff::_renderDiv {node} {
    # nroff has no div concept. We render children transparently.
    # class and id are lost.
    set out ""
    foreach child [dict get $node content] {
        append out [_renderBlock $child]
    }
    return $out
}

proc ::docir::roff::_renderUnknown {node reason} {
    set out ".\\\" docir-roff: unknown block — $reason\n"
    if {[dict exists $node content]} {
        set txt [_renderInlines [dict get $node content]]
        if {$txt ne ""} {
            append out [_protectLeadingDot $txt] "\n"
        }
    }
    return $out
}

# ==================================================================
# Inline-Rendering
# ==================================================================

proc ::docir::roff::_renderInlines {inlines} {
    if {[llength $inlines] == 0} { return "" }
    set out ""

    # list or raw string?
    set first [lindex $inlines 0]
    if {[catch {dict exists $first type} ok] || !$ok} {
        # raw string (should not happen with clean DocIR,
        # aber defensive)
        return [_escapeText $inlines]
    }

    foreach inline $inlines {
        if {![dict exists $inline type]} continue
        set itype [dict get $inline type]
        set itext [_dictDef $inline text ""]
        switch -- $itype {
            text      { append out [_escapeText $itext] }
            strong    { append out "\\fB[_escapeText $itext]\\fR" }
            emphasis  { append out "\\fI[_escapeText $itext]\\fR" }
            underline { append out "\\fI[_escapeText $itext]\\fR" }
            code      { append out "\\fB[_escapeText $itext]\\fR" }
            strike {
                # nroff has no native strike-through. Convention for
                # Tk manpages: just plain text — the strike effect
                # is lost. Pragmatic: italicize, so the
                # user at least sees "this is different".
                append out "\\fI[_escapeText $itext]\\fR"
            }
            linebreak {
                # Hard break: the nroff macro .br must be at the line start
                # We insert a newline, followed by .br
                # and another newline, so the next inline
                # lands on a new line.
                append out "\n.br\n"
            }
            softbreak {
                # Soft break: nroff fills paragraphs, so a space is enough.
                append out " "
            }
            span {
                # nroff hat keine class/id-Attribute — Text durchreichen.
                # In some nroff dialects there are .ds strings for
                # user-defined macros, but that is not portable.
                append out [_escapeText $itext]
            }
            image {
                # nroff cannot render images. Marker as
                # plain text, so the user knows what was meant.
                set url [_dictDef $inline url ""]
                if {$itext ne "" && $url ne ""} {
                    append out "\\fI\[image: [_escapeText $itext] ([_escapeText $url])\]\\fR"
                } elseif {$itext ne ""} {
                    append out "\\fI\[image: [_escapeText $itext]\]\\fR"
                } elseif {$url ne ""} {
                    append out "\\fI\[image: [_escapeText $url]\]\\fR"
                } else {
                    append out "\\fI\[image\]\\fR"
                }
            }
            footnote_ref {
                # nroff hat keine bidirektionalen Links. Marker als
                # superscript imitation: \u\sN\d\sR (super) would be possible
                # but not portable. Just [N] — the defs are
                # rendered later as a footnote_section.
                set marker [_dictDef $inline text "?"]
                append out "\[[_escapeText $marker]\]"
            }
            link {
                # In nroff, links are not a separate construct —
                # in Tk manpages "name(section)" is written.
                set name [_dictDef $inline name $itext]
                set sec  [_dictDef $inline section ""]
                # empty link -> skip entirely instead of writing empty
                # bold tags ("\fB\fR" would not be a valid
                # nroff-Output)
                if {$name eq "" && $itext eq ""} { continue }
                if {$name eq ""} { set name $itext }
                if {$sec ne ""} {
                    append out "\\fB[_escapeText $name]\\fR([_escapeText $sec])"
                } else {
                    append out "\\fB[_escapeText $name]\\fR"
                }
            }
            default {
                # Unbekannter Inline-Typ: Plain-Text
                append out [_escapeText $itext]
            }
        }
    }
    return $out
}

# ==================================================================
# Escaping & Helper
# ==================================================================

# _escapeText -- escape raw text for an nroff inline context
#
# Reihenfolge wichtig:
#   1. backslash → "\\\\" (otherwise the other rules also apply
#      auf neu erzeugte Backslashes)
#   2. Hyphen → "\-"  (literal Bindestrich)
#
# a dot at the line start is NOT handled here — that is done by
# _protectLeadingDot at the block level (with knowledge of the context).
proc ::docir::roff::_escapeText {s} {
    # Schritt 1: Backslashes
    set s [string map {"\\" "\\e"} $s]
    # Step 2: hyphens (only if NOT part of an already-escaped
    # sequence like \fB)
    # We keep it simple: all hyphens become \- — that is
    # konservativ aber korrekt
    set s [string map {"-" "\\-"} $s]
    return $s
}

# _protectLeadingDot -- at a leading "." or "'", prepend a "\&"
# so that nroff does not interpret it as a command.
# Operates auf MULTI-LINE-Strings.
proc ::docir::roff::_protectLeadingDot {s} {
    set lines [split $s "\n"]
    set protected {}
    foreach line $lines {
        # If the line starts with "." or "'": prepend \&
        if {[regexp {^[.']} $line]} {
            lappend protected "\\&$line"
        } else {
            lappend protected $line
        }
    }
    return [join $protected "\n"]
}

# _quoteArg -- quote an argument for an nroff macro
#
# nroff macros like .TH, .SH, .SS take either unquoted words or
# strings wrapped in double quotes. If the text contains spaces
# it must be quoted.
proc ::docir::roff::_quoteArg {s} {
    if {$s eq ""} { return {""} }
    # double internal double-quotes (nroff convention)
    set s [string map {"\"" "\"\""} $s]
    if {[regexp {[[:space:]]} $s]} {
        return "\"$s\""
    }
    return $s
}
