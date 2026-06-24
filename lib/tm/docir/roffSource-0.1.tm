# docir-roff-0.1.tm – Mapper: nroff-AST → DocIR
#
# Converts the AST from nroffparser-0.2 into a DocIR stream.
# No parser rework needed – a pure mapping layer.
#
# Namespace: ::docir::roff
# Tcl 8.6+ / 9.x kompatibel
#
# 2026-06-20: doc_header meta fields are un-escaped (version "0\&.10" →
#   "0.10"); redundant blank nodes after self-separating blocks
#   (paragraph/heading/list/pre/table/...) are discarded, so that `.sp`
#   between SYNOPSIS lines does not lead to triple spacing.

package provide docir::roffSource 0.1
package require Tcl 8.6-
package require docir 0.1

namespace eval ::docir::roff {}

# ============================================================
# docir::roff::fromAst -- Haupteinstiegspunkt
#
# Argumente:
#   ast  - return value of nroffparser::parse
#
# Returns:
#   DocIR stream (list of block nodes)
# ============================================================

proc docir::roff::_dictDef {d k {def ""}} {
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}

proc docir::roff::fromAst {ast} {
    set ir {}
    # doc_meta als allererster Block (irSchemaVersion seit 0.5).
    # Always emitted, even if the nroff AST has no .TH.
    lappend ir [dict create \
        type    doc_meta \
        content {} \
        meta    [dict create irSchemaVersion 1]]
    # Transient flag: the next pre node should be mapped as a table,
    # if possible. Set on .SH STANDARD OPTIONS or similar
    # and cleared again after processing the next pre.
    set expectStdOptionsTable 0

    foreach node $ast {
        set type    [dict get $node type]
        set content [_dictDef $node content {}]
        set meta    [expr {[dict exists $node meta]    ? [dict get $node meta]    : {}}]

        switch $type {

            heading {
                # .TH → doc_header
                # Header meta fields can carry nroff escapes (e.g. doctools
                # writes the version as "0\&.10" to protect the dot) — unescape
                # them like normal text so they don't show up literally.
                lappend ir [dict create \
                    type    doc_header \
                    content {} \
                    meta    [dict create \
                        name    [docir::roff::_unescapeNroff [expr {[dict exists $meta name]    ? [dict get $meta name]    : ""}]] \
                        section [docir::roff::_unescapeNroff [_dictDef $meta section ""]] \
                        version [docir::roff::_unescapeNroff [_dictDef $meta version ""]] \
                        part    [docir::roff::_unescapeNroff [expr {[dict exists $meta part]    ? [dict get $meta part]    : ""}]]]]
            }

            section {
                # .SH → heading level=1
                set txt [docir::roff::_inlinesToText $content]
                set id  [docir::roff::_makeId $txt]
                # Mark: the next pre should be tried as a table,
                # if the section is called "STANDARD OPTIONS" (case-insens.)
                set normTxt [string toupper [string trim $txt]]
                if {$normTxt eq "STANDARD OPTIONS"} {
                    set expectStdOptionsTable 1
                } else {
                    set expectStdOptionsTable 0
                }
                lappend ir [dict create \
                    type    heading \
                    content [docir::roff::_mapInlines $content] \
                    meta    [dict create level 1 id $id]]
            }

            subsection {
                # .SS → heading level=2
                set txt [docir::roff::_inlinesToText $content]
                set id  [docir::roff::_makeId $txt]
                lappend ir [dict create \
                    type    heading \
                    content [docir::roff::_mapInlines $content] \
                    meta    [dict create level 2 id $id]]
            }

            paragraph {
                set inlines [docir::roff::_mapInlines $content]
                if {[llength $inlines] > 0} {
                    lappend ir [dict create \
                        type    paragraph \
                        content $inlines \
                        meta    {}]
                }
            }

            pre {
                set kind [_dictDef $meta kind "code"]

                # If we are right after .SH STANDARD OPTIONS, try
                # to map the pre block as a table. If that does not
                # gelingt (z.B. inkonsistente Spaltenzahl), bleibt's pre.
                set tableNode {}
                if {$expectStdOptionsTable} {
                    set tableNode [docir::roff::_tryStandardOptionsTable $content]
                    set expectStdOptionsTable 0
                }
                if {[llength $tableNode] > 0} {
                    lappend ir $tableNode
                } else {
                    lappend ir [dict create \
                        type    pre \
                        content [docir::roff::_mapInlines $content] \
                        meta    [dict create kind $kind]]
                }
            }

            list {
                set kind [expr {[dict exists $meta kind]        ? [dict get $meta kind]        : "tp"}]
                set il   [_dictDef $meta indentLevel 0]
                set items {}
                foreach item $content {
                    set term [_dictDef $item term {}]
                    set desc [_dictDef $item desc {}]
                    set termIr [docir::roff::_mapInlines $term]
                    set descIr [docir::roff::_mapInlines $desc]
                    # listItem as a complete DocIR node
                    lappend items [dict create \
                        type    listItem \
                        content $descIr \
                        meta    [dict create kind $kind term $termIr]]
                }
                lappend ir [dict create \
                    type    list \
                    content $items \
                    meta    [dict create kind $kind indentLevel $il]]
            }

            blank {
                # `.sp` / blank lines become blank nodes. But most block types
                # (paragraph, heading, list, pre, table, doc_header) already
                # render with a trailing blank line, so an extra blank node on
                # top triples the gap — e.g. SYNOPSIS entries separated by `.sp`.
                # Drop the blank when the previously emitted node already
                # self-separates; keep it only between tight/inline content.
                set prevType ""
                if {[llength $ir]} { set prevType [dict get [lindex $ir end] type] }
                if {$prevType ni {paragraph heading list pre table doc_header blank hr}} {
                    set lines [_dictDef $meta lines 1]
                    lappend ir [dict create \
                        type    blank \
                        content {} \
                        meta    [dict create lines $lines]]
                }
            }

            default {
                # skip unknown types
            }
        }
    }
    return $ir
}

# ============================================================
# Interne Helfer
# ============================================================

# _unescapeNroff -- resolves nroff escape sequences in a raw string.
#
# Needed for text fields that did not go through nroffparser::parseInlines
# — typically .OP terms (format "cmdName|dbName|dbClass"
# as a raw string) and similar list-term strings.
#
# Behandelt:
#   \-   → -    (literal hyphen, the bug trigger)
#   \.   → .    (literal period)
#   \&   →      (zero-width space, removed)
#   \\   → \    (literal backslash)
#   \fB \fI \fR \fP  →  (removed — in a plain string we cannot
#                        track bold/italic states; this is
#                        a documented loss for term strings)
#
# Die Funktion arbeitet konservativ: unbekannte Escape-Sequenzen bleiben
# unchanged (better than a wrong replacement).
proc docir::roff::_unescapeNroff {s} {
    # Order matters: \\  first (otherwise the other
    # rules would also apply to double backslashes)
    set s [string map {
        "\\\\" "\x01"
        "\\-"  "-"
        "\\."  "."
        "\\&"  ""
        "\\fB" ""
        "\\fI" ""
        "\\fR" ""
        "\\fP" ""
        "\\e"  "\\"
    } $s]
    # placeholder for \\\\ → real backslash
    return [string map {"\x01" "\\"} $s]
}

proc docir::roff::_mapInlines {content} {
    # content kann sein:
    #   - list of inline dicts {type text text ...}
    #   - Rohstring (alt, Fallback)
    #   - empty list {}

    if {[llength $content] == 0} { return {} }

    # Check: is the first element a dict with a 'type' key?
    set first [lindex $content 0]
    if {[catch {dict exists $first type} ok] || !$ok} {
        # raw string → text inline. First resolve nroff escapes
        # (z.B. .OP-Terms kommen als Rohstring "\\-autoseparators|...")
        return [list [dict create type text text [_unescapeNroff $content]]]
    }

    # Inline-Dicts: text-Felder ebenfalls von Rohescapes befreien
    # (the parser handled most of it already, but not all paths —
    #  e.g. nroff list items where the term went through parseInlines
    #  but individual inlines still have leftover artifacts).

    # Inline-Dicts mappen
    set result {}
    foreach inline $content {
        if {![dict exists $inline type]} continue
        set itype [dict get $inline type]
        set text  [_dictDef $inline text ""]

        switch $itype {
            text      { lappend result [dict create type text      text $text] }
            strong    { lappend result [dict create type strong    text $text] }
            emphasis  { lappend result [dict create type emphasis  text $text] }
            underline { lappend result [dict create type underline text $text] }
            link {
                set name    [expr {[dict exists $inline name]    ? [dict get $inline name]    : $text}]
                set section [_dictDef $inline section "n"]
                set href [_dictDef $inline href ""]
                lappend result [dict create type link text $text name $name section $section href $href]
            }
            default {
                # take unknown inlines as text
                lappend result [dict create type text text $text]
            }
        }
    }
    return $result
}

proc docir::roff::_inlinesToText {content} {
    set t ""
    if {[llength $content] == 0} { return "" }
    set first [lindex $content 0]
    if {[catch {dict exists $first type} ok] || !$ok} {
        return $content
    }
    foreach i $content {
        if {[dict exists $i text]} { append t [dict get $i text] }
    }
    return $t
}

proc docir::roff::_makeId {text} {
    set id [string tolower $text]
    set id [string map {" " - "/" - "\"" "" "'" "" "(" "" ")" ""} $id]
    set id [regsub -all {[^a-z0-9\-]} $id ""]
    return $id
}

# ============================================================
# _tryStandardOptionsTable -- tries to convert a pre block from a
# .SO/.SE section into a DocIR table node.
#
# Argumente:
#   content - list of inline dicts from the pre block
#
# Returns:
#   table node dict on success, empty list on failure.
#
# Strategie:
#   1. join inlines into plain text.
#   2. An \n in Zeilen splitten.
#   3. split each line at \t into cells.
#   4. check consistency (same column count in each row,
#      at least 2 rows with at least 2 columns).
#   5. tableRow/tableCell-Nodes bauen.
#
# cell content is a plain-text inline. Tk .SO options are
# identifiers like "-background" — we wrap them in strong because
# the nroff source had \fB...\fR around them (which the parser
# pre-Mode aber als plain text durchgereicht wurde — Detail unten).
# ============================================================

proc docir::roff::_tryStandardOptionsTable {content} {
    # build plain text from inlines
    set text ""
    foreach inline $content {
        if {[dict exists $inline text]} {
            append text [dict get $inline text]
        }
    }

    # In Zeilen splitten, Leerzeilen verwerfen
    set rawLines [split $text "\n"]
    set lines {}
    foreach ln $rawLines {
        set ln [string trim $ln]
        if {$ln ne ""} { lappend lines $ln }
    }
    if {[llength $lines] == 0} { return {} }

    # determine the max column count over all rows. Inconsistent
    # Tk manpages (ttk_progressbar etc.) have non-uniform
    # column counts per row — we take the maximum and fill
    # shorter rows with empty cells.
    set numCols 0
    foreach ln $lines {
        set cols [llength [split $ln "\t"]]
        if {$cols > $numCols} { set numCols $cols }
    }
    if {$numCols < 2} { return {} }

    # check all rows: same column count?
    # the last row may have fewer columns (typical in Tk manpages —
    # a "filler" row at the end). Tolerant mode: all rows with
    # fewer columns than firstCols are padded with empty cells.
    set rows {}
    foreach ln $lines {
        set cells [split $ln "\t"]
        # pad if shorter
        while {[llength $cells] < $numCols} {
            lappend cells ""
        }

        set rowCells {}
        foreach cell $cells {
            set cellText [string trim $cell]
            # Tk standard options are identifiers like "-background",
            # in the nroff source as \fB...\fR (bold). We output them
            # as a strong inline, so the renderer displays them
            # appropriately. Empty cells → empty content list.
            if {$cellText eq ""} {
                set inlines {}
            } else {
                set inlines [list [dict create type strong text $cellText]]
            }
            lappend rowCells [dict create \
                type    tableCell \
                content $inlines \
                meta    {}]
        }
        lappend rows [dict create \
            type    tableRow \
            content $rowCells \
            meta    {}]
    }

    return [dict create \
        type    table \
        content $rows \
        meta    [dict create columns $numCols hasHeader 0 source standardOptions]]
}
