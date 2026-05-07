# docir-roff-0.1.tm – Mapper: nroff-AST → DocIR
#
# Wandelt den AST von nroffparser-0.2 in einen DocIR-Stream um.
# Kein Parser-Umbau nötig – reiner Mapping-Layer.
#
# Namespace: ::docir::roff
# Tcl 8.6+ / 9.x kompatibel

package provide docir::roffSource 0.1
package require Tcl 8.6-
package require docir 0.1

namespace eval ::docir::roff {}

# ============================================================
# docir::roff::fromAst -- Haupteinstiegspunkt
#
# Argumente:
#   ast  - Rückgabe von nroffparser::parse
#
# Rückgabe:
#   DocIR-Stream (Liste von Block-Nodes)
# ============================================================

proc docir::roff::fromAst {ast} {
    set ir {}
    # doc_meta als allererster Block (irSchemaVersion seit 0.5).
    # Wird IMMER emittiert, auch wenn der nroff-AST kein .TH hat.
    lappend ir [dict create \
        type    doc_meta \
        content {} \
        meta    [dict create irSchemaVersion 1]]
    # Transient-Flag: nächster pre-Node soll als Tabelle gemappt werden,
    # falls möglich. Wird bei .SH STANDARD OPTIONS oder ähnlich gesetzt
    # und nach Verarbeitung des nächsten pre wieder gelöscht.
    set expectStdOptionsTable 0

    foreach node $ast {
        set type    [dict get $node type]
        set content [expr {[dict exists $node content] ? [dict get $node content] : {}}]
        set meta    [expr {[dict exists $node meta]    ? [dict get $node meta]    : {}}]

        switch $type {

            heading {
                # .TH → doc_header
                lappend ir [dict create \
                    type    doc_header \
                    content {} \
                    meta    [dict create \
                        name    [expr {[dict exists $meta name]    ? [dict get $meta name]    : ""}] \
                        section [expr {[dict exists $meta section] ? [dict get $meta section] : ""}] \
                        version [expr {[dict exists $meta version] ? [dict get $meta version] : ""}] \
                        part    [expr {[dict exists $meta part]    ? [dict get $meta part]    : ""}]]]
            }

            section {
                # .SH → heading level=1
                set txt [docir::roff::_inlinesToText $content]
                set id  [docir::roff::_makeId $txt]
                # Markiere: nächster pre soll als Tabelle versucht werden,
                # wenn die Section "STANDARD OPTIONS" heißt (case-insens.)
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
                set kind [expr {[dict exists $meta kind] ? [dict get $meta kind] : "code"}]

                # Wenn wir gerade nach .SH STANDARD OPTIONS sind, versuche
                # den pre-Block als Tabelle zu mappen. Wenn das nicht
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
                set il   [expr {[dict exists $meta indentLevel] ? [dict get $meta indentLevel] : 0}]
                set items {}
                foreach item $content {
                    set term [expr {[dict exists $item term] ? [dict get $item term] : {}}]
                    set desc [expr {[dict exists $item desc] ? [dict get $item desc] : {}}]
                    set termIr [docir::roff::_mapInlines $term]
                    set descIr [docir::roff::_mapInlines $desc]
                    # listItem als vollständiger DocIR-Node
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
                set lines [expr {[dict exists $meta lines] ? [dict get $meta lines] : 1}]
                lappend ir [dict create \
                    type    blank \
                    content {} \
                    meta    [dict create lines $lines]]
            }

            default {
                # Unbekannte Typen überspringen
            }
        }
    }
    return $ir
}

# ============================================================
# Interne Helfer
# ============================================================

# _unescapeNroff -- löst nroff-Escape-Sequenzen in einem Rohstring auf.
#
# Wird für Textfelder benötigt, die nicht durch nroffparser::parseInlines
# gegangen sind — typisch sind .OP-Terms (Format "cmdName|dbName|dbClass"
# als Rohstring) und ähnliche Listen-Term-Strings.
#
# Behandelt:
#   \-   → -    (literal hyphen, der Bug-Auslöser)
#   \.   → .    (literal period)
#   \&   →      (zero-width space, wird entfernt)
#   \\   → \    (literal backslash)
#   \fB \fI \fR \fP  →  (entfernt — wir können in einem Plain-String
#                        keine Bold/Italic-Zustände tracken; das ist
#                        ein dokumentierter Verlust für Term-Strings)
#
# Die Funktion arbeitet konservativ: unbekannte Escape-Sequenzen bleiben
# unverändert (besser als falsches Ersetzen).
proc docir::roff::_unescapeNroff {s} {
    # Reihenfolge wichtig: \\ zuerst (sonst greifen die anderen
    # Regeln auch auf Doppel-Backslashes)
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
    # Platzhalter für \\\\ → echter Backslash
    return [string map {"\x01" "\\"} $s]
}

proc docir::roff::_mapInlines {content} {
    # content kann sein:
    #   - Liste von Inline-Dicts {type text text ...}
    #   - Rohstring (alt, Fallback)
    #   - Leere Liste {}

    if {[llength $content] == 0} { return {} }

    # Prüfen: erstes Element ein Dict mit 'type'-Schlüssel?
    set first [lindex $content 0]
    if {[catch {dict exists $first type} ok] || !$ok} {
        # Rohstring → text-Inline. Vorher nroff-Escapes auflösen
        # (z.B. .OP-Terms kommen als Rohstring "\\-autoseparators|...")
        return [list [dict create type text text [_unescapeNroff $content]]]
    }

    # Inline-Dicts: text-Felder ebenfalls von Rohescapes befreien
    # (Parser hat das meiste schon erledigt, aber nicht alle Pfade —
    #  z.B. nroff-Listen-Items wo der Term durch parseInlines ging
    #  aber einzelne Inlines noch Resterzeugnisse haben).

    # Inline-Dicts mappen
    set result {}
    foreach inline $content {
        if {![dict exists $inline type]} continue
        set itype [dict get $inline type]
        set text  [expr {[dict exists $inline text] ? [dict get $inline text] : ""}]

        switch $itype {
            text      { lappend result [dict create type text      text $text] }
            strong    { lappend result [dict create type strong    text $text] }
            emphasis  { lappend result [dict create type emphasis  text $text] }
            underline { lappend result [dict create type underline text $text] }
            link {
                set name    [expr {[dict exists $inline name]    ? [dict get $inline name]    : $text}]
                set section [expr {[dict exists $inline section] ? [dict get $inline section] : "n"}]
                set href [expr {[dict exists $inline href] ? [dict get $inline href] : ""}]
                lappend result [dict create type link text $text name $name section $section href $href]
            }
            default {
                # Unbekannte Inlines als text übernehmen
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
# _tryStandardOptionsTable -- versucht einen pre-Block aus einer
# .SO/.SE-Sektion in einen DocIR-table-Node umzuwandeln.
#
# Argumente:
#   content - Liste von Inline-Dicts aus dem pre-Block
#
# Rückgabe:
#   table-Node-Dict bei Erfolg, leere Liste bei Misserfolg.
#
# Strategie:
#   1. Inlines zu Klartext zusammenfügen.
#   2. An \n in Zeilen splitten.
#   3. Jede Zeile an \t in Zellen splitten.
#   4. Konsistenz prüfen (gleiche Spaltenzahl in jeder Zeile,
#      mindestens 2 Zeilen mit mindestens 2 Spalten).
#   5. tableRow/tableCell-Nodes bauen.
#
# Zellen-Inhalt ist Plain-Text-Inline. Tk-.SO-Optionen sind
# Bezeichner wie "-background" — wir wickeln sie in strong, weil
# die nroff-Quelle \fB...\fR um sie hatte (was beim Parser im
# pre-Mode aber als plain text durchgereicht wurde — Detail unten).
# ============================================================

proc docir::roff::_tryStandardOptionsTable {content} {
    # Klartext aus Inlines zusammenbauen
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

    # Maximale Spaltenzahl über alle Zeilen ermitteln. Inkonsistente
    # Tk-Manpages (ttk_progressbar etc.) haben uneinheitliche
    # Spalten-Anzahl pro Zeile — wir nehmen das Maximum und füllen
    # kürzere Zeilen mit leeren Zellen auf.
    set numCols 0
    foreach ln $lines {
        set cols [llength [split $ln "\t"]]
        if {$cols > $numCols} { set numCols $cols }
    }
    if {$numCols < 2} { return {} }

    # Alle Zeilen prüfen: gleiche Spaltenzahl?
    # Letzte Zeile darf weniger Spalten haben (typisch in Tk-Manpages —
    # "Lückenfüller"-Zeile am Ende). Toleranter Modus: alle Zeilen mit
    # weniger Spalten als firstCols werden mit leeren Zellen aufgefüllt.
    set rows {}
    foreach ln $lines {
        set cells [split $ln "\t"]
        # Auffüllen falls kürzer
        while {[llength $cells] < $numCols} {
            lappend cells ""
        }

        set rowCells {}
        foreach cell $cells {
            set cellText [string trim $cell]
            # Tk-Standard-Options sind Bezeichner wie "-background",
            # in der nroff-Quelle als \fB...\fR (bold). Wir geben sie
            # als strong-Inline aus, damit der Renderer sie passend
            # darstellt. Leere Zellen → leere content-Liste.
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
