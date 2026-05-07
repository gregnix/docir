# docir-0.1.tm – DocIR Intermediate Representation
# Validator, Pretty-Dump, Diff
# Spec: doc/docir-spec.md
#
# Namespace: ::docir
# Tcl 8.6+ / 9.x kompatibel

package provide docir 0.1
package require Tcl 8.6-

namespace eval ::docir {
    # Gültige Block-Typen
    variable blockTypes {
        doc_meta doc_header heading paragraph pre list listItem blank hr
        table tableRow tableCell
        image footnote_section footnote_def div
    }
    # Gültige Inline-Typen
    variable inlineTypes {
        text strong emphasis underline strike code link
        image linebreak span footnote_ref
    }
    # IR-Schema-Versionen die dieser Validator/Hub verarbeiten kann.
    # Wird von docir::schemaVersion / docir::checkSchemaVersion benutzt.
    # Renderer können selbst engere Mengen definieren.
    variable SUPPORTED_SCHEMA_VERSIONS {1}

    # Block-Typen die zwar gültiger Teil des IR sind, aber von Senken
    # NICHT als Inhalt gerendert werden. Sie tragen nur Schema-/Meta-
    # Information, die Validator und Hub auswerten (z.B. Schema-Version).
    # Senken sollen diese Typen silent skippen — anstatt eine "unknown
    # block"-Warnung auszulösen.
    #
    # Eintrag hier ergänzen ist die einzige Stelle, die geändert werden
    # muss, wenn ein neuer Schema-Marker-Block-Typ eingeführt wird.
    variable SCHEMA_ONLY_BLOCKS {doc_meta}
}

# ============================================================
# docir::isSchemaOnly -- prüft ob ein Block-Typ zur "Schema-only"-
# Klasse gehört, die Senken silent skippen sollen.
# Renderer rufen das im default-Case ihres Block-Switches auf,
# bevor sie eine "unknown"-Warnung ausgeben.
# ============================================================

proc docir::isSchemaOnly {type} {
    variable SCHEMA_ONLY_BLOCKS
    return [expr {$type in $SCHEMA_ONLY_BLOCKS}]
}

# ============================================================
# docir::validate -- Prüft einen DocIR-Stream
# Gibt {} zurück wenn OK, sonst Liste von Fehlermeldungen
# ============================================================

proc docir::validate {ir} {
    variable blockTypes
    variable inlineTypes
    set errors {}
    set i 0
    foreach node $ir {
        incr i
        # Pflichtfelder
        foreach field {type content meta} {
            if {![dict exists $node $field]} {
                lappend errors "Node $i: Pflichtfeld '$field' fehlt"
            }
        }
        if {[llength $errors] > 0} continue

        set type    [dict get $node type]
        set content [dict get $node content]
        set meta    [dict get $node meta]

        # Block-Typ bekannt?
        if {$type ni $blockTypes} {
            lappend errors "Node $i: Unbekannter Block-Typ '$type'"
        }

        # Typ-spezifische Prüfungen
        switch $type {
            doc_meta {
                # content muss leer sein
                if {$content ne {}} {
                    lappend errors "Node $i (doc_meta): content muss {} sein"
                }
                # irSchemaVersion ist Pflichtfeld in meta
                if {![dict exists $meta irSchemaVersion]} {
                    lappend errors "Node $i (doc_meta): meta.irSchemaVersion fehlt"
                } else {
                    set v [dict get $meta irSchemaVersion]
                    if {![string is integer -strict $v] || $v < 1} {
                        lappend errors "Node $i (doc_meta): meta.irSchemaVersion muss Integer >= 1 sein, ist '$v'"
                    }
                }
                # Mehrfach-Vorkommen ist Schema-Verletzung
                if {[info exists docMetaSeen]} {
                    lappend errors "Node $i (doc_meta): doc_meta darf nur einmal vorkommen (zuvor an Node $docMetaSeen)"
                } else {
                    set docMetaSeen $i
                }
            }
            doc_header {
                # content muss leer sein
                if {$content ne {}} {
                    lappend errors "Node $i (doc_header): content muss {} sein"
                }
            }
            heading {
                if {![dict exists $meta level]} {
                    lappend errors "Node $i (heading): meta.level fehlt"
                } else {
                    set lvl [dict get $meta level]
                    if {![string is integer $lvl] || $lvl < 1 || $lvl > 6} {
                        lappend errors "Node $i (heading): level muss 1..6 sein, ist '$lvl'"
                    }
                }
                # content: Inline-Liste
                set errors [concat $errors [docir::_validateInlines $i heading $content]]
            }
            paragraph {
                set errors [concat $errors [docir::_validateInlines $i paragraph $content]]
            }
            pre {
                set errors [concat $errors [docir::_validateInlines $i pre $content]]
            }
            list {
                if {![dict exists $meta kind]} {
                    lappend errors "Node $i (list): meta.kind fehlt"
                }
                # Items: müssen listItem-Nodes sein. Legacy-Form {term desc}
                # wird nur akzeptiert wenn KEIN type-Feld da ist (sonst war's
                # gemeint als typed-Node und ist falsch eingebettet — z.B.
                # ein 'list'-Knoten direkt in list.content statt im listItem
                # eines vorherigen Items).
                set j 0
                foreach item $content {
                    incr j
                    if {[dict exists $item type]} {
                        set itype [dict get $item type]
                        if {$itype eq "listItem"} {
                            # Neue Form: vollständiger DocIR-Node
                            if {![dict exists $item content]} {
                                lappend errors "Node $i, Item $j (listItem): 'content' fehlt"
                            }
                            if {![dict exists $item meta] || ![dict exists [dict get $item meta] term]} {
                                lappend errors "Node $i, Item $j (listItem): meta.term fehlt"
                            }
                        } else {
                            # Schema-Verletzung: getypter Knoten der nicht
                            # listItem ist. Häufiger Fall: nested 'list'-Node
                            # direkt im content statt im listItem.content
                            # eines vorherigen Items (mdparser-typischer Bug).
                            lappend errors "Node $i, Item $j: list.content darf nur listItem-Knoten enthalten, fand type='$itype' (nested lists müssen im content des listItem-Vorgängers liegen oder als separate list-Nodes auf Top-Level)"
                        }
                    } else {
                        # Legacy-Form ohne type-Feld: {term desc}
                        foreach field {term desc} {
                            if {![dict exists $item $field]} {
                                lappend errors "Node $i, Item $j (legacy listItem): Feld '$field' fehlt"
                            }
                        }
                    }
                }
            }
            listItem {
                # listItem kann auch top-level vorkommen (z.B. in Tests)
                if {![dict exists $meta kind]} {
                    lappend errors "Node $i (listItem): meta.kind fehlt"
                }
                if {![dict exists $meta term]} {
                    lappend errors "Node $i (listItem): meta.term fehlt"
                }
                set errors [concat $errors [docir::_validateInlines $i listItem $content]]
            }
            blank {
                if {[dict exists $meta lines]} {
                    set l [dict get $meta lines]
                    if {![string is integer $l] || $l < 1} {
                        lappend errors "Node $i (blank): meta.lines muss >= 1 sein"
                    }
                }
            }
            table {
                # content ist Liste von tableRow-Nodes
                if {![dict exists $meta columns]} {
                    lappend errors "Node $i (table): meta.columns fehlt"
                } else {
                    set cols [dict get $meta columns]
                    if {![string is integer $cols] || $cols < 1} {
                        lappend errors "Node $i (table): meta.columns muss >= 1 sein"
                    }
                }
                set j 0
                foreach row $content {
                    incr j
                    if {![dict exists $row type] || [dict get $row type] ne "tableRow"} {
                        lappend errors "Node $i, Row $j: muss type tableRow haben"
                    }
                }
            }
            tableRow {
                # content ist Liste von tableCell-Nodes
                set j 0
                foreach cell $content {
                    incr j
                    if {![dict exists $cell type] || [dict get $cell type] ne "tableCell"} {
                        lappend errors "Node $i (tableRow), Cell $j: muss type tableCell haben"
                    }
                }
            }
            tableCell {
                # content ist Inline-Liste
                set errors [concat $errors [docir::_validateInlines $i tableCell $content]]
            }
            image {
                # Block-Image: content {}, meta.url required
                if {$content ne {}} {
                    lappend errors "Node $i (image block): content muss {} sein (meta hat alt/url/title)"
                }
                if {![dict exists $meta url]} {
                    lappend errors "Node $i (image block): meta.url fehlt"
                }
            }
            footnote_section {
                # content ist Liste von footnote_def-Nodes
                set j 0
                foreach fnDef $content {
                    incr j
                    if {![dict exists $fnDef type] || [dict get $fnDef type] ne "footnote_def"} {
                        lappend errors "Node $i (footnote_section), Item $j: muss type footnote_def haben"
                    }
                }
            }
            footnote_def {
                # content = Inline-Liste der Definition
                # meta.id required, meta.num optional Display-Marker
                if {![dict exists $meta id]} {
                    lappend errors "Node $i (footnote_def): meta.id fehlt"
                }
                set errors [concat $errors [docir::_validateInlines $i footnote_def $content]]
            }
            div {
                # TIP-700 Container: content = Liste von Block-Nodes
                # meta.class und meta.id sind optional
                # Wir validieren nicht rekursiv (sonst würde es kompliziert);
                # docir::validate sollte für alle Top-Level-Blocks aufgerufen
                # werden. Aber mindestens prüfen dass content eine Liste ist.
                if {![string is list $content]} {
                    lappend errors "Node $i (div): content muss eine Block-Liste sein"
                }
            }
        }
    }
    return $errors
}

proc docir::_validateInlines {nodeIdx nodeType inlines} {
    variable inlineTypes
    set errors {}
    set j 0
    foreach inline $inlines {
        incr j
        if {![dict exists $inline type]} {
            lappend errors "Node $nodeIdx ($nodeType), Inline $j: 'type' fehlt"
            continue
        }
        set itype [dict get $inline type]
        if {$itype ni $inlineTypes} {
            lappend errors "Node $nodeIdx ($nodeType), Inline $j: Unbekannter Inline-Typ '$itype'"
            continue
        }
        # Pro-Typ Required-Field-Prüfung
        switch -- $itype {
            link {
                # link braucht: text, name, section
                foreach f {name section} {
                    if {![dict exists $inline $f]} {
                        lappend errors "Node $nodeIdx, Inline $j (link): Feld '$f' fehlt"
                    }
                }
                if {![dict exists $inline text]} {
                    lappend errors "Node $nodeIdx, Inline $j (link): Feld 'text' fehlt"
                }
            }
            image {
                # image braucht: text (alt), url
                if {![dict exists $inline text]} {
                    lappend errors "Node $nodeIdx, Inline $j (image): Feld 'text' (= alt) fehlt"
                }
                if {![dict exists $inline url]} {
                    lappend errors "Node $nodeIdx, Inline $j (image): Feld 'url' fehlt"
                }
            }
            linebreak {
                # linebreak hat keine Required-Fields — kein text nötig
            }
            footnote_ref {
                # footnote_ref braucht: text, id
                if {![dict exists $inline text]} {
                    lappend errors "Node $nodeIdx, Inline $j (footnote_ref): Feld 'text' fehlt"
                }
                if {![dict exists $inline id]} {
                    lappend errors "Node $nodeIdx, Inline $j (footnote_ref): Feld 'id' fehlt"
                }
            }
            default {
                # text, strong, emphasis, underline, strike, code, span:
                # alle brauchen 'text'
                if {![dict exists $inline text]} {
                    lappend errors "Node $nodeIdx ($nodeType), Inline $j ($itype): Feld 'text' fehlt"
                }
            }
        }
    }
    return $errors
}

# ============================================================
# docir::schemaVersion -- Liest die IR-Schema-Version aus dem Stream
#
# Sucht den ersten doc_meta-Block und gibt dessen meta.irSchemaVersion
# zurück. Wenn kein doc_meta-Block vorkommt, wird 0 zurückgegeben
# ("unversioniert", entspricht IRs aus Zeit vor irSchemaVersion).
#
# Der Validator akzeptiert IRs ohne doc_meta weiterhin (lenient mode).
# Renderer können mit checkSchemaVersion eine eigene Strict-Prüfung
# machen.
# ============================================================

proc docir::schemaVersion {ir} {
    foreach node $ir {
        if {![dict exists $node type]} continue
        if {[dict get $node type] ne "doc_meta"} continue
        set meta [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
        if {[dict exists $meta irSchemaVersion]} {
            return [dict get $meta irSchemaVersion]
        }
        return 0
    }
    return 0
}

# ============================================================
# docir::checkSchemaVersion -- Prüft IR gegen erlaubte Versionen
#
# Args:
#   ir         -- DocIR-Stream
#   supported  -- Liste erlaubter Versionen. Default: alle die der
#                 Hub kennt (::docir::SUPPORTED_SCHEMA_VERSIONS).
#                 Renderer können enger sein, z.B. {1}.
#   strict     -- 0 (default): unversionierte IRs (Version 0) werden
#                 toleriert. 1: Version 0 ist Fehler.
#
# Rückgabe:
#   {} wenn ok, sonst Fehler-String.
# ============================================================

proc docir::checkSchemaVersion {ir {supported {}} {strict 0}} {
    variable SUPPORTED_SCHEMA_VERSIONS
    if {$supported eq ""} {
        set supported $SUPPORTED_SCHEMA_VERSIONS
    }
    set v [docir::schemaVersion $ir]
    if {$v == 0} {
        if {$strict} {
            return "DocIR ohne doc_meta-Block (irSchemaVersion fehlt) im strict-Modus abgelehnt; erlaubt: $supported"
        }
        return ""
    }
    if {$v in $supported} {
        return ""
    }
    return "DocIR-Schema-Version $v wird nicht unterstützt; erlaubt: $supported"
}

# ============================================================
# docir::dump -- Pretty-Print eines DocIR-Streams
# ============================================================

proc docir::dump {ir {indent 0}} {
    set pad [string repeat "  " $indent]
    set out ""
    set i 0
    foreach node $ir {
        incr i
        set type    [dict get $node type]
        set content [dict get $node content]
        set meta    [dict get $node meta]

        switch $type {
            doc_meta {
                set v [expr {[dict exists $meta irSchemaVersion] ? [dict get $meta irSchemaVersion] : "?"}]
                append out "${pad}\[doc_meta\] irSchemaVersion=$v\n"
            }
            doc_header {
                set name    [expr {[dict exists $meta name]    ? [dict get $meta name]    : "?"}]
                set section [expr {[dict exists $meta section] ? [dict get $meta section] : ""}]
                set part    [expr {[dict exists $meta part]    ? [dict get $meta part]    : ""}]
                append out "${pad}[doc_header] $name($section) $part\n"
            }
            heading {
                set lvl  [expr {[dict exists $meta level] ? [dict get $meta level] : "?"}]
                set txt  [docir::_inlinesToText $content]
                set hdr  [string repeat "#" $lvl]
                append out "${pad}${hdr} $txt\n"
            }
            paragraph {
                set txt [docir::_inlinesToText $content]
                set preview [string range $txt 0 60]
                if {[string length $txt] > 60} { append preview "…" }
                append out "${pad}[paragraph] «$preview»\n"
                append out [docir::_dumpInlines $content "${pad}  "]
            }
            pre {
                set kind [expr {[dict exists $meta kind] ? " ($meta)" : ""}]
                set txt  [docir::_inlinesToText $content]
                set preview [string range $txt 0 50]
                append out "${pad}[pre$kind] «$preview»\n"
            }
            list {
                set kind [expr {[dict exists $meta kind]        ? [dict get $meta kind]        : "?"}]
                set il   [expr {[dict exists $meta indentLevel] ? [dict get $meta indentLevel] : 0}]
                append out "${pad}[list kind=$kind indent=$il items=[llength $content]]\n"
                foreach item $content {
                    set term [docir::_inlinesToText [dict get $item term]]
                    set desc [docir::_inlinesToText [dict get $item desc]]
                    set tprev [string range $term 0 30]
                    set dprev [string range $desc 0 40]
                    append out "${pad}  • «$tprev» → «$dprev»\n"
                }
            }
            blank {
                set l [expr {[dict exists $meta lines] ? [dict get $meta lines] : 1}]
                append out "${pad}[blank lines=$l]\n"
            }
            hr {
                append out "${pad}[hr]\n"
            }
            table {
                set cols [expr {[dict exists $meta columns] ? [dict get $meta columns] : "?"}]
                set rows [llength $content]
                append out "${pad}\[table cols=$cols rows=$rows\]\n"
            }
            tableRow -
            tableCell {
                # Sollten nur in einer Tabelle vorkommen — auf Top-Level
                # nur als Debugging-Hinweis ausgeben
                append out "${pad}[$type] (orphan, normalerweise innerhalb table)\n"
            }
            image {
                set url [expr {[dict exists $meta url] ? [dict get $meta url] : "?"}]
                set alt [expr {[dict exists $meta alt] ? [dict get $meta alt] : ""}]
                append out "${pad}\[image\] $url alt=«$alt»\n"
            }
            footnote_section {
                append out "${pad}\[footnote_section\] [llength $content] defs\n"
                foreach fnDef $content {
                    set fnMeta [dict get $fnDef meta]
                    set id  [expr {[dict exists $fnMeta id]  ? [dict get $fnMeta id]  : "?"}]
                    set num [expr {[dict exists $fnMeta num] ? [dict get $fnMeta num] : ""}]
                    set txt [docir::_inlinesToText [dict get $fnDef content]]
                    set preview [string range $txt 0 40]
                    append out "${pad}  \[$num\] id=$id «$preview»\n"
                }
            }
            footnote_def {
                # Sollte normalerweise innerhalb footnote_section sein
                set id [expr {[dict exists $meta id] ? [dict get $meta id] : "?"}]
                set txt [docir::_inlinesToText $content]
                set preview [string range $txt 0 40]
                append out "${pad}\[footnote_def id=$id\] «$preview»\n"
            }
            div {
                set cls [expr {[dict exists $meta class] ? [dict get $meta class] : ""}]
                set id  [expr {[dict exists $meta id]    ? [dict get $meta id]    : ""}]
                set attrs ""
                if {$cls ne ""} { append attrs " class=$cls" }
                if {$id  ne ""} { append attrs " id=$id" }
                append out "${pad}\[div$attrs\] [llength $content] children\n"
                # Rekursiv die child-blocks dumpen
                append out [docir::dump $content [expr {$indent + 1}]]
            }
            default {
                append out "${pad}[$type] (unbekannt)\n"
            }
        }
    }
    return $out
}

proc docir::_inlinesToText {inlines} {
    set t ""
    foreach i $inlines {
        if {[dict exists $i text]} { append t [dict get $i text] }
    }
    return $t
}

proc docir::_dumpInlines {inlines pad} {
    set out ""
    foreach i $inlines {
        set type [dict get $i type]
        if {$type eq "text"} continue  ;# text-Inlines nicht einzeln zeigen
        set text [expr {[dict exists $i text] ? [dict get $i text] : ""}]
        append out "${pad}<$type> «$text»\n"
    }
    return $out
}

# ============================================================
# docir::diff -- Vergleicht zwei DocIR-Streams
# Gibt Liste von Unterschieden zurück
# ============================================================

proc docir::diff {irA irB {label ""}} {
    set diffs {}
    set lenA [llength $irA]
    set lenB [llength $irB]

    if {$lenA != $lenB} {
        lappend diffs "Länge verschieden: A=$lenA B=$lenB"
    }

    set n [expr {min($lenA, $lenB)}]
    for {set i 0} {$i < $n} {incr i} {
        set nA [lindex $irA $i]
        set nB [lindex $irB $i]
        set tA [dict get $nA type]
        set tB [dict get $nB type]
        if {$tA ne $tB} {
            lappend diffs "Node [expr {$i+1}]: Typ A=$tA B=$tB"
        } else {
            # Meta-Vergleich
            set mA [dict get $nA meta]
            set mB [dict get $nB meta]
            if {$mA ne $mB} {
                lappend diffs "Node [expr {$i+1}] ($tA): meta verschieden\n  A: $mA\n  B: $mB"
            }
            # Inline-Textvergleich
            set txtA [docir::_inlinesToText [docir::_contentInlines $nA]]
            set txtB [docir::_inlinesToText [docir::_contentInlines $nB]]
            if {$txtA ne $txtB} {
                set pA [string range $txtA 0 40]
                set pB [string range $txtB 0 40]
                lappend diffs "Node [expr {$i+1}] ($tA): Text verschieden\n  A: «$pA»\n  B: «$pB»"
            }
        }
    }
    return $diffs
}

proc docir::_contentInlines {node} {
    set type    [dict get $node type]
    set content [dict get $node content]
    switch $type {
        paragraph - heading - pre { return $content }
        default                   { return {} }
    }
}

# ============================================================
# docir::typeSeq -- Nur die Typ-Sequenz (für Tests)
# ============================================================

proc docir::typeSeq {ir} {
    set seq {}
    foreach node $ir { lappend seq [dict get $node type] }
    return $seq
}
