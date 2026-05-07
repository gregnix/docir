# docir-roff-0.1.tm -- DocIR → nroff (Senke)
#
# Wandelt eine DocIR-Sequenz in nroff-Markup um. Siebte Senke im
# DocIR-Hub. Zielformat: Tcl/Tk-Manpage-Konvention (.TH, .SH, .SS,
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
#   wrapColumn     integer (default 0): wenn > 0, harte Zeilenumbrüche
#                  innerhalb von Paragraphen bei dieser Spalte
#   forceQuoting   bool (default 0): Strings mit Sonderzeichen in .QW
#                  einwickeln (statt inline-Escapes)
#
# Round-Trip-Hinweise:
#   - Soft-Hyphen, Kerning-Hints, manuelle Layout-Anweisungen gehen
#     verloren (DocIR ist semantisch, nicht typographisch)
#   - Whitespace-Normalisierung: aufeinanderfolgende Spaces werden zu
#     einem zusammengefasst (nroff verhalten sich ohnehin so)
#   - Tabellen werden zur Standard-Options-Pattern (.SO/.SE) gemappt
#     wenn meta.kind eq "standardOptions", sonst zu .TS/.TE-Block

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
#   options: dict mit Keys headingShift / wrapColumn / forceQuoting
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
    set m [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
    set name    [expr {[dict exists $m name]    ? [dict get $m name]    : ""}]
    set section [expr {[dict exists $m section] ? [dict get $m section] : ""}]
    set version [expr {[dict exists $m version] ? [dict get $m version] : ""}]
    set part    [expr {[dict exists $m part]    ? [dict get $m part]    : ""}]

    if {$name eq "" && $section eq ""} { return "" }

    set parts [list ".TH"]
    lappend parts [_quoteArg $name]
    lappend parts [_quoteArg $section]
    if {$version ne ""} {
        lappend parts [_quoteArg $version]
    }
    if {$part ne ""} {
        # Wenn version leer ist aber part da, brauchen wir einen
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
    set m  [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
    set lv [expr {[dict exists $m level] ? [dict get $m level] : 1}]
    incr lv [dict get $opts headingShift]
    if {$lv < 1} { set lv 1 }

    set txt [_renderInlines [dict get $node content]]

    # Heading-Texte werden in nroff traditionell GROSSGESCHRIEBEN
    # für .SH (Top-Level). Wir ändern das nicht automatisch — der
    # User-Source liefert es schon so. Wenn nicht, ist das eine
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
# pre → .CS … .CE (Tk-Konvention) ODER .nf/.fi (klassisch)
# ------------------------------------------------------------------

proc ::docir::roff::_renderPre {node} {
    set m    [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
    set kind [expr {[dict exists $m kind] ? [dict get $m kind] : "code"}]

    # Inhalt: pre kann entweder einen text-Inline mit dem Code als
    # text-Feld haben, oder rohe Zeilen.
    set content [dict get $node content]
    set raw ""
    foreach inline $content {
        if {[dict exists $inline text]} {
            append raw [dict get $inline text]
        }
    }

    # Code-Zeilen müssen vor Punkt-am-Zeilenanfang geschützt werden
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
    set m    [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
    set kind [expr {[dict exists $m kind] ? [dict get $m kind] : "tp"}]
    set indentLevel [expr {[dict exists $m indentLevel] ? [dict get $m indentLevel] : 0}]

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

    # Schließe alle .RS mit entsprechend vielen .RE
    for {set i 0} {$i < $indentLevel} {incr i} {
        append out ".RE\n"
    }

    return $out
}

# Ein einzelner listItem im Kontext eines bestimmten Listen-kind
proc ::docir::roff::_renderListItem {item kind itemNum} {
    set itemMeta [expr {[dict exists $item meta] ? [dict get $item meta] : {}}]
    set term     [expr {[dict exists $itemMeta term] ? [dict get $itemMeta term] : {}}]
    set descIr   [dict get $item content]

    set termText [_renderInlines $term]
    set descText [string trimright [_renderInlines $descIr] "\n"]
    set descText [_protectLeadingDot $descText]

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
            # Wir versuchen das Pattern zu erkennen, fallback ist
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
            # cmd hat oft ein literales "-" davor das in nroff
            # geschützt werden muss als "\-"
            if {[string match "-*" $cmd]} {
                set cmd "\\$cmd"
            }
            set out ".OP $cmd $db $cls\n"
            append out $descText "\n"
            return $out
        }
        ap {
            # Argument-Pattern: .AP type name in/out\ndesc
            # Wir haben keine spezifischen Felder im listItem-meta,
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

# Ein listItem auf Top-Level (außerhalb einer list) — selten,
# meist Schema-Verletzung. Wir geben es als Paragraph aus.
proc ::docir::roff::_renderOrphanedListItem {node} {
    set out [_renderUnknown $node "orphaned listItem (outside list)"]
    return $out
}

# ------------------------------------------------------------------
# blank → leere Zeile / .sp
# ------------------------------------------------------------------

proc ::docir::roff::_renderBlank {node} {
    set m     [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
    set lines [expr {[dict exists $m lines] ? [dict get $m lines] : 1}]
    if {$lines < 1} { set lines 1 }

    if {$lines == 1} { return ".sp\n" }
    return ".sp $lines\n"
}

# ------------------------------------------------------------------
# hr → "\(em" Linie als Annäherung — nroff hat keine HR
# ------------------------------------------------------------------

proc ::docir::roff::_renderHr {node} {
    # Beste Annäherung: eine .sp + Linie aus em-Dashes.
    # Aber: das ist semantisch nicht das gleiche. Konservativ:
    # einfach eine extra Leerzeile.
    return ".sp 2\n"
}

# ------------------------------------------------------------------
# table → standard-options pattern (.SO/.SE) oder .TS/.TE
# ------------------------------------------------------------------

proc ::docir::roff::_renderTable {node} {
    set m    [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
    set kind [expr {[dict exists $m kind] ? [dict get $m kind] : ""}]

    if {$kind eq "standardOptions"} {
        return [_renderStandardOptionsTable $node]
    }
    return [_renderGenericTable $node]
}

# Standard-Options-Tabelle: rückwärts-Mapping zur Tk-Konvention
# .SO [classname]
# .SE
#
# Inhalt der Tabelle: tableRows mit tableCells, jede Zelle ein Option.
# Die Tk-Konvention listet nur Options ohne Werte — sie sind
# Cross-Referenzen.
proc ::docir::roff::_renderStandardOptionsTable {node} {
    set m         [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
    set className [expr {[dict exists $m className] ? [dict get $m className] : ""}]

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
                # Optionsnamen brauchen kein -, das wird im Konsumenten
                # erwartet aber traditionell hängt das von der nroff-
                # Quelle ab. Wir geben sie ohne führendes \- aus —
                # die original Tk-Manpages haben sie auch ohne.
                append out "$txt\n"
            }
        }
    }
    append out ".SE\n"
    return $out
}

# Generische Tabelle als .TS/.TE-Block (tbl-Format).
# Vorsicht: nicht jeder nroff-Renderer hat tbl. In Tcl/Tk-Manpages
# wird tbl praktisch nicht genutzt — die Standard-Options sind das
# einzige Tabellen-Pattern. Daher ist generic-table eher Fallback.
proc ::docir::roff::_renderGenericTable {node} {
    set out ".TS\n"
    set rows [dict get $node content]

    # Erste Zeile: Spalten-Spec aus Anzahl Zellen
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
    # nroff kann keine Bilder rendern. Marker als italic-Plain-Text.
    set m [dict get $node meta]
    set url [expr {[dict exists $m url] ? [dict get $m url] : ""}]
    set alt [expr {[dict exists $m alt] ? [dict get $m alt] : ""}]

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
    # Footnotes werden als eigene Sektion mit .SH "FOOTNOTES" gerendert.
    # Jeder footnote_def wird zu .TP "[N]" body
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
    set num [expr {[dict exists $m num] ? [dict get $m num] : "?"}]
    set body [_renderInlines [dict get $node content]]
    set body [_protectLeadingDot $body]

    set out ".TP\n"
    append out "\[[_escapeText $num]\]\n"
    append out "$body\n"
    return $out
}

proc ::docir::roff::_renderDiv {node} {
    # nroff hat kein div-Konzept. Wir rendern children transparent.
    # class und id gehen verloren.
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

    # Liste oder Rohstring?
    set first [lindex $inlines 0]
    if {[catch {dict exists $first type} ok] || !$ok} {
        # Rohstring (sollte nicht passieren bei sauberem DocIR,
        # aber defensive)
        return [_escapeText $inlines]
    }

    foreach inline $inlines {
        if {![dict exists $inline type]} continue
        set itype [dict get $inline type]
        set itext [expr {[dict exists $inline text] ? [dict get $inline text] : ""}]
        switch -- $itype {
            text      { append out [_escapeText $itext] }
            strong    { append out "\\fB[_escapeText $itext]\\fR" }
            emphasis  { append out "\\fI[_escapeText $itext]\\fR" }
            underline { append out "\\fI[_escapeText $itext]\\fR" }
            code      { append out "\\fB[_escapeText $itext]\\fR" }
            strike {
                # nroff hat keine native Strike-Through. Konvention für
                # Tk-Manpages: einfach Plain-Text — der Strike-Effekt
                # geht verloren. Pragmatisch: kursivieren, damit der
                # User wenigstens sieht "das ist anders".
                append out "\\fI[_escapeText $itext]\\fR"
            }
            linebreak {
                # Hard-Break: nroff-Macro .br muss am Zeilenanfang
                # stehen. Wir fügen einen Newline ein, gefolgt von .br
                # und einem weiteren Newline, damit der nächste Inline
                # auf einer neuen Zeile landet.
                append out "\n.br\n"
            }
            span {
                # nroff hat keine class/id-Attribute — Text durchreichen.
                # In manchen nroff-Dialekten gibt es .ds-Strings für
                # User-defined-Macros, aber das ist nicht portabel.
                append out [_escapeText $itext]
            }
            image {
                # nroff kann keine Bilder rendern. Marker als
                # Plain-Text, damit User weiß was gemeint war.
                set url [expr {[dict exists $inline url] ? [dict get $inline url] : ""}]
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
                # Hochzahl-Imitation: \u\sN\d\sR (super) wäre möglich
                # aber nicht portabel. Einfach [N] — die Defs werden
                # später als footnote_section gerendert.
                set marker [expr {[dict exists $inline text] ? [dict get $inline text] : "?"}]
                append out "\[[_escapeText $marker]\]"
            }
            link {
                # In nroff sind Links keine eigene Konstruktion —
                # in Tk-Manpages wird "name(section)" geschrieben.
                set name [expr {[dict exists $inline name] ? [dict get $inline name] : $itext}]
                set sec  [expr {[dict exists $inline section] ? [dict get $inline section] : ""}]
                # Leerer Link → komplett überspringen statt leere
                # Bold-Tags zu schreiben ("\fB\fR" wäre kein gültiger
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

# _escapeText -- escape rohen Text für nroff-Inline-Kontext
#
# Reihenfolge wichtig:
#   1. Backslash → "\\\\" (sonst greifen die anderen Regeln auch
#      auf neu erzeugte Backslashes)
#   2. Hyphen → "\-"  (literal Bindestrich)
#
# Punkt am Zeilenanfang wird NICHT hier behandelt — das macht
# _protectLeadingDot auf Block-Ebene (mit Wissen über Kontext).
proc ::docir::roff::_escapeText {s} {
    # Schritt 1: Backslashes
    set s [string map {"\\" "\\e"} $s]
    # Schritt 2: Hyphens (nur wenn KEIN Teil einer bereits eskapierten
    # Sequenz wie \fB)
    # Wir machen es einfach: alle Hyphens werden \- — das ist
    # konservativ aber korrekt
    set s [string map {"-" "\\-"} $s]
    return $s
}

# _protectLeadingDot -- bei "." oder "'" am Zeilenanfang ein "\&"
# voranstellen, sodass nroff es nicht als Befehl interpretiert.
# Operates auf MULTI-LINE-Strings.
proc ::docir::roff::_protectLeadingDot {s} {
    set lines [split $s "\n"]
    set protected {}
    foreach line $lines {
        # Wenn die Zeile mit "." oder "'" beginnt: \& voranstellen
        if {[regexp {^[.']} $line]} {
            lappend protected "\\&$line"
        } else {
            lappend protected $line
        }
    }
    return [join $protected "\n"]
}

# _quoteArg -- Argument für nroff-Macro quoten
#
# nroff-Macros wie .TH, .SH, .SS nehmen entweder unquoted Wörter oder
# in Doppel-Quotes eingewickelte Strings. Wenn der Text Spaces enthält
# muss er gequotet sein.
proc ::docir::roff::_quoteArg {s} {
    if {$s eq ""} { return {""} }
    # Internal Doppel-Quotes verdoppeln (nroff-Konvention)
    set s [string map {"\"" "\"\""} $s]
    if {[regexp {[[:space:]]} $s]} {
        return "\"$s\""
    }
    return $s
}
