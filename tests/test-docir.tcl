#!/usr/bin/env tclsh
# Tests für DocIR: Validator, Mapper, Dump

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

# ============================================================
# Hilfsfunktionen
# ============================================================

proc makeIr {src} {
    set ast [nroffparser::parse $src test.n]
    return [docir::roff::fromAst $ast]
}

# ============================================================
# Tests: docir::validate
# ============================================================

test "docir.validate.empty" {
    set errors [docir::validate {}]
    assert [expr {[llength $errors] == 0}] "Leerer Stream: keine Fehler"
}

test "docir.validate.valid_paragraph" {
    set ir [list [dict create \
        type    paragraph \
        content [list [dict create type text text "Hello"]] \
        meta    {}]]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] == 0}] "Valider Paragraph: keine Fehler"
}

test "docir.validate.missing_type" {
    set ir [list [dict create content {} meta {}]]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] > 0}] "Fehlendes 'type' wird erkannt"
}

test "docir.validate.unknown_block_type" {
    set ir [list [dict create type foobar content {} meta {}]]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] > 0}] "Unbekannter Block-Typ wird erkannt"
}

test "docir.validate.heading_no_level" {
    set ir [list [dict create \
        type    heading \
        content [list [dict create type text text "NAME"]] \
        meta    {}]]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] > 0}] "heading ohne level: Fehler"
}

test "docir.validate.heading_valid" {
    set ir [list [dict create \
        type    heading \
        content [list [dict create type text text "NAME"]] \
        meta    [dict create level 1]]]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] == 0}] "Valides heading: keine Fehler"
}

test "docir.validate.list_no_kind" {
    set ir [list [dict create \
        type    list \
        content [list [dict create term {} desc {}]] \
        meta    {}]]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] > 0}] "list ohne kind: Fehler"
}

# ============================================================
# Tests: docir::typeSeq
# ============================================================

test "docir.typeSeq.basic" {
    set ir [makeIr ".TH t n\n.SH NAME\ntest\n.SH DESCRIPTION\ndesc\n"]
    set seq [docir::typeSeq $ir]
    assert [expr {"doc_header" in $seq}]  "doc_header in Sequenz"
    assert [expr {"heading"    in $seq}]  "heading in Sequenz"
    assert [expr {"paragraph"  in $seq}]  "paragraph in Sequenz"
}

# ============================================================
# Tests: Mapper roffAst → DocIR
# ============================================================

test "docir.mapper.doc_header" {
    set ir [makeIr ".TH canvas n 8.3 Tk\n"]
    # Seit irSchemaVersion: erster Block ist doc_meta, zweiter ist doc_header
    set meta0 [lindex $ir 0]
    assertEqual "doc_meta" [dict get $meta0 type] "Erster Node: doc_meta (irSchemaVersion)"
    assertEqual 1 [dict get [dict get $meta0 meta] irSchemaVersion] "irSchemaVersion=1"
    set first [lindex $ir 1]
    assertEqual "doc_header" [dict get $first type] "Zweiter Node: doc_header"
    set meta [dict get $first meta]
    assertEqual "canvas" [dict get $meta name]    "name=canvas"
    assertEqual "n"      [dict get $meta section] "section=n"
    assertEqual "Tk"     [dict get $meta part]    "part=Tk"
}

test "docir.mapper.section_to_heading" {
    set ir [makeIr ".TH t n\n.SH DESCRIPTION\ntext\n"]
    # Suche heading-Node
    set h {}
    foreach n $ir { if {[dict get $n type] eq "heading"} { set h $n; break } }
    assert [expr {$h ne ""}] "heading-Node vorhanden"
    set meta [dict get $h meta]
    assertEqual 1 [dict get $meta level] "level=1"
    assert [expr {[dict exists $meta id]}] "id vorhanden"
}

test "docir.mapper.paragraph_inlines" {
    set ir [makeIr ".TH t n\n.SH D\n\\fBbold\\fR normal\n"]
    set p {}
    foreach n $ir { if {[dict get $n type] eq "paragraph"} { set p $n; break } }
    assert [expr {$p ne ""}] "paragraph vorhanden"
    set types {}
    foreach i [dict get $p content] { lappend types [dict get $i type] }
    assert [expr {"strong" in $types}] "strong-Inline vorhanden"
    assert [expr {"text"   in $types}] "text-Inline vorhanden"
}

test "docir.mapper.list_kind" {
    set ir [makeIr ".TH t n\n.SH D\n.TP\n\\fBarg\\fR\nDescription\n"]
    set l {}
    foreach n $ir { if {[dict get $n type] eq "list"} { set l $n; break } }
    assert [expr {$l ne ""}] "list vorhanden"
    assertEqual "tp" [dict get [dict get $l meta] kind] "kind=tp"
}

test "docir.mapper.list_indentLevel" {
    set ir [makeIr ".TH t n\n.SH D\n.IP outer\ntext\n.RS\n.IP inner\ntext\n.RE\n"]
    set lists {}
    foreach n $ir { if {[dict get $n type] eq "list"} { lappend lists $n } }
    assert [expr {[llength $lists] == 2}] "2 Listen (outer + inner)"
    # Innere Liste hat indentLevel 1
    set innerMeta [dict get [lindex $lists 0] meta]
    assertEqual 1 [dict get $innerMeta indentLevel] "innere Liste: indentLevel=1"
}

test "docir.mapper.link_inline" {
    set ir [makeIr ".TH t n\n.SH \"SEE ALSO\"\ncanvas(n)\n"]
    set p {}
    foreach n $ir { if {[dict get $n type] eq "paragraph"} { set p $n } }
    set types {}
    foreach i [dict get $p content] { lappend types [dict get $i type] }
    assert [expr {"link" in $types}] "link-Inline in SEE ALSO"
}

test "docir.mapper.pre" {
    set ir [makeIr ".TH t n\n.SH D\n.CS\nputs hello\n.CE\n"]
    set p {}
    foreach n $ir { if {[dict get $n type] eq "pre"} { set p $n; break } }
    assert [expr {$p ne ""}] "pre-Node vorhanden"
    set txt [docir::_inlinesToText [dict get $p content]]
    assert [expr {[string match "*puts hello*" $txt]}] "Code-Inhalt"
}

# ============================================================
# Tests: docir::diff
# ============================================================

test "docir.diff.identical" {
    set ir [makeIr ".TH t n\n.SH NAME\ntext\n"]
    set diffs [docir::diff $ir $ir]
    assert [expr {[llength $diffs] == 0}] "Identische Streams: keine Diffs"
}

test "docir.diff.different_length" {
    set irA [makeIr ".TH t n\n.SH NAME\ntext\n"]
    set irB [makeIr ".TH t n\n"]
    set diffs [docir::diff $irA $irB]
    assert [expr {[llength $diffs] > 0}] "Verschiedene Länge: Diffs erkannt"
}

# ============================================================
# Tests: Validator auf gemappted IR
# ============================================================

test "docir.roundtrip.validate" {
    set ir [makeIr ".TH canvas n 8.3 Tk\n.SH NAME\ncanvas\n.SH DESCRIPTION\ntext\n.TP\n\\fBarg\\fR\ndesc\n"]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] == 0}] \
        "Vollständige Manpage: IR valide ([llength $errors] Fehler: $errors)"
}

# ============================================================

# ============================================================
# Tests: listItem-Nodes
# ============================================================

test "docir.listItem.is_node" {
    # Items müssen jetzt type=listItem haben
    set ir [makeIr ".TH t n
.SH D
.TP
\\fBarg\\fR
Description
"]
    set l {}
    foreach n $ir { if {[dict get $n type] eq "list"} { set l $n; break } }
    assert [expr {$l ne ""}] "list vorhanden"
    set items [dict get $l content]
    assert [expr {[llength $items] > 0}] "items nicht leer"
    set item [lindex $items 0]
    assertEqual "listItem" [dict get $item type] "item hat type=listItem"
}

test "docir.listItem.has_content_meta" {
    set ir [makeIr ".TH t n
.SH D
.TP
\\fBarg\\fR
Description of arg.
"]
    set item {}
    foreach n $ir {
        if {[dict get $n type] eq "list"} {
            set item [lindex [dict get $n content] 0]
            break
        }
    }
    assert [expr {[dict exists $item content]}] "listItem hat content"
    assert [expr {[dict exists $item meta]}]    "listItem hat meta"
    set m [dict get $item meta]
    assert [expr {[dict exists $m term]}]       "meta hat term"
    assert [expr {[dict exists $m kind]}]       "meta hat kind"
}

test "docir.listItem.term_inlines" {
    set ir [makeIr ".TH t n
.SH D
.TP
\\fBarg\\fR
Description.
"]
    set item {}
    foreach n $ir {
        if {[dict get $n type] eq "list"} { set item [lindex [dict get $n content] 0]; break }
    }
    set term [dict get [dict get $item meta] term]
    assert [expr {[llength $term] > 0}] "term nicht leer"
    set types {}
    foreach i $term { lappend types [dict get $i type] }
    assert [expr {"strong" in $types}] "term enthält strong-Inline"
}

test "docir.listItem.desc_inlines" {
    set ir [makeIr ".TH t n
.SH D
.TP
\\fBarg\\fR
The description text.
"]
    set item {}
    foreach n $ir {
        if {[dict get $n type] eq "list"} { set item [lindex [dict get $n content] 0]; break }
    }
    set desc [dict get $item content]
    assert [expr {[llength $desc] > 0}] "desc nicht leer"
    set allText ""
    foreach i $desc { if {[dict exists $i text]} { append allText [dict get $i text] } }
    assert [expr {[string match "*description*" [string tolower $allText]]}] "desc-Text korrekt"
}

test "docir.listItem.kind_tp" {
    set ir [makeIr ".TH t n
.SH D
.TP
term
desc
"]
    set item {}
    foreach n $ir {
        if {[dict get $n type] eq "list"} { set item [lindex [dict get $n content] 0]; break }
    }
    assertEqual "tp" [dict get [dict get $item meta] kind] "kind=tp"
}

test "docir.listItem.kind_ip" {
    set ir [makeIr ".TH t n
.SH D
.IP bullet 4
text
"]
    set item {}
    foreach n $ir {
        if {[dict get $n type] eq "list"} { set item [lindex [dict get $n content] 0]; break }
    }
    assertEqual "ip" [dict get [dict get $item meta] kind] "kind=ip"
}

test "docir.listItem.validate_ok" {
    set ir [makeIr ".TH t n
.SH D
.TP
\\fBarg\\fR
Description.
"]
    set errs [docir::validate $ir]
    assertEqual {} $errs "Keine Validierungsfehler"
}

test "docir.listItem.roundtrip" {
    # Ganzes canvas-ähnliches Dokument mit mehreren TP-Items
    set src ".TH t n
.SH OPTIONS
.TP
\\fB-width\\fR
Sets width.
.TP
\\fB-height\\fR
Sets height.
"
    set ir [makeIr $src]
    set errs [docir::validate $ir]
    assertEqual {} $errs "Kein Validierungsfehler"
    set l {}
    foreach n $ir { if {[dict get $n type] eq "list"} { set l $n; break } }
    assertEqual 2 [llength [dict get $l content]] "2 listItem-Nodes"
}

# ============================================================
# Tests: table (.SO/.SE Standard Options als Tabelle)
# ============================================================

test "docir.table.so_se_creates_table" {
    set src ".TH t n\n.SH \"STANDARD OPTIONS\"\n.SO\n-foo\t-bar\t-baz\n-one\t-two\t-three\n.SE\n"
    set ir [makeIr $src]
    set tbl {}
    foreach n $ir { if {[dict get $n type] eq "table"} { set tbl $n; break } }
    assert [expr {[dict size $tbl] > 0}] ".SO/.SE-Block produziert table-Node"
}

test "docir.table.columns_meta" {
    set src ".TH t n\n.SH \"STANDARD OPTIONS\"\n.SO\n-a\t-b\t-c\n-d\t-e\t-f\n.SE\n"
    set ir [makeIr $src]
    set tbl {}
    foreach n $ir { if {[dict get $n type] eq "table"} { set tbl $n; break } }
    set meta [dict get $tbl meta]
    assertEqual 3 [dict get $meta columns] "columns=3 in meta"
    assertEqual standardOptions [dict get $meta source] "source=standardOptions"
}

test "docir.table.row_count" {
    set src ".TH t n\n.SH \"STANDARD OPTIONS\"\n.SO\n-a\t-b\t-c\n-d\t-e\t-f\n.SE\n"
    set ir [makeIr $src]
    set tbl {}
    foreach n $ir { if {[dict get $n type] eq "table"} { set tbl $n; break } }
    assertEqual 2 [llength [dict get $tbl content]] "2 rows"
}

test "docir.table.cell_content_strong" {
    set src ".TH t n\n.SH \"STANDARD OPTIONS\"\n.SO\n-foo\t-bar\n.SE\n"
    set ir [makeIr $src]
    set tbl {}
    foreach n $ir { if {[dict get $n type] eq "table"} { set tbl $n; break } }
    set firstRow  [lindex [dict get $tbl content] 0]
    set firstCell [lindex [dict get $firstRow content] 0]
    set firstInl  [lindex [dict get $firstCell content] 0]
    assertEqual strong [dict get $firstInl type] "Zelle ist strong"
    assertEqual "-foo" [dict get $firstInl text] "Zelle text=-foo"
}

test "docir.table.last_row_pad_short" {
    set src ".TH t n\n.SH \"STANDARD OPTIONS\"\n.SO\n-a\t-b\t-c\n-d\t-e\n.SE\n"
    set ir [makeIr $src]
    set tbl {}
    foreach n $ir { if {[dict get $n type] eq "table"} { set tbl $n; break } }
    assertEqual 2 [llength [dict get $tbl content]] "2 Rows trotz kürzerer letzter"
    set secondRow [lindex [dict get $tbl content] 1]
    assertEqual 3 [llength [dict get $secondRow content]] "letzte Row hat 3 Cells"
    set lastCell [lindex [dict get $secondRow content] 2]
    assertEqual 0 [llength [dict get $lastCell content]] "letzte Cell ist leer"
}

test "docir.table.fallback_to_pre_when_one_column" {
    set src ".TH t n\n.SH \"STANDARD OPTIONS\"\n.SO\n-justOne\n.SE\n"
    set ir [makeIr $src]
    set hasTable 0
    foreach n $ir { if {[dict get $n type] eq "table"} { set hasTable 1 } }
    assertEqual 0 $hasTable "single-column → kein table-Node"
}

test "docir.table.normal_pre_unaffected" {
    set src ".TH t n\n.SH OTHER\n.CS\nfoo\tbar\nbaz\tqux\n.CE\n"
    set ir [makeIr $src]
    set hasTable 0
    set hasPre 0
    foreach n $ir {
        switch [dict get $n type] {
            table { set hasTable 1 }
            pre   { set hasPre 1 }
        }
    }
    assertEqual 0 $hasTable "kein table außerhalb STANDARD OPTIONS"
    assertEqual 1 $hasPre   "pre-Block bleibt pre"
}

test "docir.table.validate_ok" {
    set src ".TH t n\n.SH \"STANDARD OPTIONS\"\n.SO\n-a\t-b\n-c\t-d\n.SE\n"
    set ir [makeIr $src]
    set errs [docir::validate $ir]
    assertEqual {} $errs "Validator akzeptiert table-Struktur"
}

test "docir.table.so_without_outer_section" {
    # .SO/.SE braucht keinen vorgeschalteten .SH-Header — der Parser
    # baut selbst eine STANDARD-OPTIONS-Section. Trotzdem soll der
    # Mapper die Tabelle erkennen.
    set src ".TH t n\n.SO\n-a\t-b\n.SE\n"
    set ir [makeIr $src]
    set hasTable 0
    foreach n $ir { if {[dict get $n type] eq "table"} { set hasTable 1 } }
    assertEqual 1 $hasTable ".SO ohne vorhergehenden .SH erkannt"
}


# ============================================================
# Schema-Verletzungen mit klaren Meldungen (2026-05-05)
#
# Hintergrund: User-Bug-Report — beim Render einer .md-Datei mit
# nested lists kam aus dem Renderer "key 'term' not known in
# dictionary". Stille Fehler-Kategorie: ein 'list'-Knoten direkt
# im list.content (statt in listItem.content) ist Schema-
# Verletzung. Vorher meldete der Validator nur "Feld 'term' fehlt"
# (irreführend), Renderer crashte. Jetzt: klare Meldung +
# defensiver Renderer.
# ============================================================

test "docir.validate.nested_list_in_list_content" {
    # Schema-Verletzung: list direkt in list.content
    set ir [list \
        [dict create type list content [list \
            [dict create type listItem content {} meta {kind ul term {}}] \
            [dict create type list content {} meta {kind ul indentLevel 0}] \
        ] meta {kind ul indentLevel 0}]]

    set errs [docir::validate $ir]
    assert [expr {[llength $errs] > 0}] "Validator meldet Fehler"
    # Klare Meldung muss type='list' explizit nennen
    set found 0
    foreach e $errs {
        if {[string match "*list.content darf nur listItem*" $e]
            && [string match "*type='list'*" $e]} {
            set found 1
        }
    }
    assert $found "Klare Meldung: list.content darf nur listItem, fand type='list'"
}

test "docir.validate.unknown_typed_node_in_list_content" {
    # Auch andere getypte Knoten: type='paragraph' im list.content
    set ir [list \
        [dict create type list content [list \
            [dict create type paragraph content {} meta {}] \
        ] meta {kind ul indentLevel 0}]]

    set errs [docir::validate $ir]
    assert [expr {[llength $errs] > 0}] "Fehler bei paragraph in list.content"
    set found 0
    foreach e $errs {
        if {[string match "*type='paragraph'*" $e]} { set found 1 }
    }
    assert $found "Meldung nennt den falschen Typ explizit"
}

test "docir.validate.legacy_form_still_accepted" {
    # Regression-Schutz: legacy {term desc} ohne type-Feld ist OK
    set ir [list \
        [dict create type list content [list \
            [dict create term {} desc {}] \
        ] meta {kind tp indentLevel 0}]]

    set errs [docir::validate $ir]
    assertEqual 0 [llength $errs] "legacy listItem-Form weiterhin akzeptiert"
}

test "docir.validate.legacy_form_missing_field_clearly_reported" {
    # Wenn legacy-Form unvollständig: muss klare Meldung kommen
    set ir [list \
        [dict create type list content [list \
            [dict create term {}] \
        ] meta {kind tp indentLevel 0}]]

    set errs [docir::validate $ir]
    assert [expr {[llength $errs] > 0}] "Fehler bei unvollständiger legacy-Form"
    # Nicht "Feld 'term' fehlt" — denn term ist da. Sondern desc-Hinweis.
    set found 0
    foreach e $errs {
        if {[string match "*legacy listItem*" $e] && [string match "*desc*" $e]} {
            set found 1
        }
    }
    assert $found "Meldung sagt explizit 'legacy listItem'"
}

# ============================================================
# Bug-Fix-Tests: nroff-Escapes in .OP-Term-Strings auflösen
# ============================================================
#
# Bug-Geschichte: text(n) hatte ".OP \-autoseparators autoSeparators
# AutoSeparators". Der nroffparser speicherte den Term als Rohstring
# "\-autoseparators|autoSeparators|AutoSeparators". docir-roff-source
# wickelte den Rohstring zu einem text-Inline ohne die Escapes
# aufzulösen — Resultat: alle DocIR-Senken (HTML, SVG, MD, PDF)
# zeigten den Backslash. Fix: _unescapeNroff in _mapInlines.

test "roff.unescape.op_hyphen" {
    # Das Standard-Bug-Szenario: \-flag im OP-Term
    set ir [makeIr ".TH t n 1 X\n.OP \\-autoseparators autoSeparators AutoSeparators\nDesc."]
    set termFound ""
    foreach node $ir {
        if {[dict get $node type] ne "list"} continue
        foreach item [dict get $node content] {
            set m [dict get $item meta]
            if {[dict exists $m term]} {
                set t [dict get $m term]
                foreach inline $t {
                    if {[dict exists $inline text]} {
                        append termFound [dict get $inline text]
                    }
                }
            }
        }
    }
    assert [string match "-autoseparators*" $termFound] \
        "OP-Term beginnt mit echtem Minus, nicht mit Backslash-Minus"
    assert [expr {![string match "*\\\\-*" $termFound]}] \
        "Kein Doppelbackslash im Term"
}

test "roff.unescape.helper_basic" {
    # _unescapeNroff direkt testen
    assert [string equal [docir::roff::_unescapeNroff "\\-foo"] "-foo"] "\\- → -"
    assert [string equal [docir::roff::_unescapeNroff "\\.x"] ".x"] "\\. → ."
    assert [string equal [docir::roff::_unescapeNroff "x\\&y"] "xy"] "\\& → entfernt"
    assert [string equal [docir::roff::_unescapeNroff "a\\\\b"] "a\\b"] "\\\\ → \\"
    assert [string equal [docir::roff::_unescapeNroff "plain"] "plain"] "Keine Escapes: unverändert"
}

test "roff.unescape.helper_font_codes_stripped" {
    # \fB \fI \fR \fP werden entfernt — wir können in einem Plain-String
    # keine Bold/Italic-Zustände tracken
    assert [string equal [docir::roff::_unescapeNroff "\\fBbold\\fR"] "bold"]
    assert [string equal [docir::roff::_unescapeNroff "\\fIitalic\\fP"] "italic"]
}

test "roff.unescape.preserves_inline_dicts" {
    # Wenn _mapInlines Inline-Dicts bekommt (NICHT Rohstring), bleibt
    # Inhalt unverändert — der Parser hat dort schon escaped.
    set inlines [list [dict create type text text "-autoseparators"]]
    set result [docir::roff::_mapInlines $inlines]
    assert [string equal [dict get [lindex $result 0] text] "-autoseparators"]
}

# ============================================================
# Spec-Erweiterung 0.2: neue Inline-Typen
# ============================================================

test "spec.inline.strike_valid" {
    set ir [list [dict create type paragraph \
        content [list [dict create type strike text "deleted"]] meta {}]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] == 0}] "strike inline ist gültig"
}

test "spec.inline.image_valid" {
    set ir [list [dict create type paragraph \
        content [list [dict create type image text "alt" url "img.png"]] meta {}]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] == 0}] "image inline mit text+url ist gültig"
}

test "spec.inline.image_missing_url" {
    set ir [list [dict create type paragraph \
        content [list [dict create type image text "alt"]] meta {}]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] == 1}] "image ohne url wird gemeldet"
    assert [string match "*url*" [lindex $errs 0]] "Fehlermeldung erwähnt url"
}

test "spec.inline.linebreak_no_text_required" {
    set ir [list [dict create type paragraph \
        content [list [dict create type linebreak]] meta {}]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] == 0}] "linebreak braucht kein text-Feld"
}

test "spec.inline.span_with_class" {
    set ir [list [dict create type paragraph \
        content [list [dict create type span text "highlighted" class "warning"]] meta {}]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] == 0}] "span mit class ist gültig"
}

test "spec.inline.footnote_ref_valid" {
    set ir [list [dict create type paragraph \
        content [list [dict create type footnote_ref text "1" id "fn1"]] meta {}]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] == 0}] "footnote_ref mit text+id ist gültig"
}

test "spec.inline.footnote_ref_missing_id" {
    set ir [list [dict create type paragraph \
        content [list [dict create type footnote_ref text "1"]] meta {}]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] == 1}] "footnote_ref ohne id wird gemeldet"
}

# ============================================================
# Spec-Erweiterung 0.2: neue Block-Typen
# ============================================================

test "spec.block.image_valid" {
    set ir [list [dict create type image content {} \
        meta [dict create url "img.png" alt "Description"]]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] == 0}] "block image mit url ist gültig"
}

test "spec.block.image_missing_url" {
    set ir [list [dict create type image content {} \
        meta [dict create alt "Description"]]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] == 1}] "block image ohne url wird gemeldet"
}

test "spec.block.footnote_section_valid" {
    set ir [list [dict create type footnote_section \
        content [list \
            [dict create type footnote_def \
                content [list [dict create type text text "First note."]] \
                meta [dict create id "fn1" num "1"]]] \
        meta {}]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] == 0}] "footnote_section mit defs ist gültig"
}

test "spec.block.footnote_section_wrong_child_type" {
    set ir [list [dict create type footnote_section \
        content [list [dict create type paragraph \
            content [list [dict create type text text "wrong"]] meta {}]] \
        meta {}]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] >= 1}] "non-footnote_def child wird gemeldet"
}

test "spec.block.footnote_def_missing_id" {
    set ir [list [dict create type footnote_def \
        content [list [dict create type text text "note"]] \
        meta [dict create num "1"]]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] >= 1}] "footnote_def ohne id wird gemeldet"
}

test "spec.block.div_valid" {
    set ir [list [dict create type div \
        content [list [dict create type paragraph \
            content [list [dict create type text text "in div"]] meta {}]] \
        meta [dict create class "warning" id "warn1"]]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] == 0}] "div mit class+id ist gültig"
}

test "spec.block.div_no_meta" {
    # div ohne meta ist auch OK (class/id sind optional)
    set ir [list [dict create type div content {} meta {}]]
    set errs [docir::validate $ir]
    assert [expr {[llength $errs] == 0}] "div ohne meta ist gültig"
}

# ============================================================
# Dump-Tests für neue Typen
# ============================================================

test "spec.dump.image_block" {
    set ir [list [dict create type image content {} \
        meta [dict create url "img.png" alt "Test"]]]
    set txt [docir::dump $ir]
    assert [expr {[string first "image" $txt] >= 0}]
    assert [expr {[string first "img.png" $txt] >= 0}]
    assert [expr {[string first "Test" $txt] >= 0}]
}

test "spec.dump.footnote_section" {
    set ir [list [dict create type footnote_section \
        content [list \
            [dict create type footnote_def \
                content [list [dict create type text text "Footnote text."]] \
                meta [dict create id "fn1" num "1"]]] \
        meta {}]]
    set txt [docir::dump $ir]
    assert [expr {[string first "footnote_section" $txt] >= 0}]
    assert [expr {[string first "fn1" $txt] >= 0}]
}

test::runAll
