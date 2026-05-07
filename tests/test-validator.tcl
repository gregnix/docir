#!/usr/bin/env tclsh
# test-validator.tcl
#
# Tests für nroffparser::validate und nroffparser::validateAST.
#
# Hintergrund: ein externer Code-Review (2026-05) hat vier Bugs im
# Validator gefunden, die durchrutschten weil keine Tests den
# Validator gegen echten Parser-Output prüften:
#
#   1. blank-Nodes haben kein content-Feld, Validator besteht aber drauf
#   2. .OP-Lists: Parser schreibt meta.kind, Validator prüft meta.listKind
#   3. link-Inlines (vom detectLinks-Schritt) waren nicht in
#      validInlineTypes
#   4. validateAST wurde in der AST-Spec genannt, aber Code hatte
#      nur validate
#
# Diese Test-Suite verhindert Regression auf alle vier Punkte plus
# einen Live-Test gegen Parser-Output realer Konstrukte.

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

# ============================================================
# A. Grundverhalten
# ============================================================

test "validator.empty_ast_errors" {
    set err ""
    catch {nroffparser::validate {}} err
    assert [string match "*empty AST*" $err] "leerer AST → error"
}

test "validator.minimal_paragraph" {
    set ast [list [dict create \
        type    paragraph \
        content [list [dict create type text text "hello"]] \
        meta    {}]]
    assert [nroffparser::validate $ast] "minimale Paragraph valide"
}

test "validator.unknown_type_errors" {
    set ast [list [dict create type bogus content {} meta {}]]
    set err ""
    catch {nroffparser::validate $ast} err
    assert [string match "*invalid type*bogus*" $err] "bogus-type → error"
}

# ============================================================
# B. blank-Nodes ohne content-Feld (Review-Bug #1)
# ============================================================

test "validator.blank_without_content_field_ok" {
    # Parser produziert blank-Nodes ganz ohne content-Feld.
    # Validator soll das akzeptieren.
    set ast [list [dict create \
        type paragraph content [list [dict create type text text x]] meta {}] \
        [dict create type blank meta {lines 1}]]
    assert [nroffparser::validate $ast] "blank ohne content akzeptiert"
}

test "validator.blank_real_parser_output" {
    # Roundtrip: parsen, dann validieren — muss klappen
    set src ".TH t n\n.SH X\nfirst\n\n\nsecond\n"
    set ast [nroffparser::parse $src test.n]
    assert [nroffparser::validate $ast] "Parser-Output mit blank durchläuft"
}

# ============================================================
# C. link-Inline (Review-Bug #3)
# ============================================================

test "validator.link_inline_accepted" {
    # link mit allen Pflichtfeldern (text/name/section)
    set ast [list [dict create \
        type    paragraph \
        content [list [dict create type link text "array(n)" name "array" section "n"]] \
        meta    {}]]
    assert [nroffparser::validate $ast] "link-Inline mit name+section ok"
}

test "validator.link_missing_name_errors" {
    set ast [list [dict create \
        type    paragraph \
        content [list [dict create type link text "x" section "n"]] \
        meta    {}]]
    set err ""
    catch {nroffparser::validate $ast} err
    assert [string match "*link*missing 'name'*" $err] "link ohne name → error"
}

test "validator.link_missing_section_errors" {
    set ast [list [dict create \
        type    paragraph \
        content [list [dict create type link text "x" name "x"]] \
        meta    {}]]
    set err ""
    catch {nroffparser::validate $ast} err
    assert [string match "*link*missing 'section'*" $err] "link ohne section → error"
}

test "validator.link_real_see_also" {
    # Echter SEE-ALSO-Block produziert link-Inlines via detectLinks
    set src ".TH t n\n.SH \"SEE ALSO\"\narray(n), dict(n)\n"
    set ast [nroffparser::parse $src test.n]
    assert [nroffparser::validate $ast] "SEE ALSO mit Links durchläuft"
}

# ============================================================
# D. .OP-List: kind statt listKind (Review-Bug #2)
# ============================================================

test "validator.op_list_uses_kind" {
    # Parser produziert für .OP eine list mit meta {kind op}.
    # term ist pipe-separierter String "cmd|db|class".
    set src ".TH t n\n.SH X\n.OP -fg foreground Foreground\nForeground color.\n"
    set ast [nroffparser::parse $src test.n]
    # Sanity-Check: list-Node existiert und hat kind op
    set listNode {}
    foreach n $ast {
        if {[dict get $n type] eq "list"} { set listNode $n; break }
    }
    assert [expr {[llength $listNode] > 0}] ".OP produziert list-Node"
    set meta [dict get $listNode meta]
    assertEqual op [dict get $meta kind] "meta.kind = op (nicht listKind)"
    # Validator akzeptiert die Struktur
    assert [nroffparser::validate $ast] "Validator akzeptiert .OP-List"
}

# ============================================================
# E. validateAST-Alias (Review-Bug #4)
# ============================================================

test "validator.validateAST_alias_exists" {
    # Spec-konformer Alias: validateAST sollte parallel zu validate
    # existieren und identisch funktionieren.
    set ast [list [dict create \
        type    paragraph \
        content [list [dict create type text text "x"]] \
        meta    {}]]
    assert [nroffparser::validateAST $ast] "validateAST funktioniert"
}

test "validator.validateAST_same_errors" {
    # Beide Aufrufe sollen gleiche Fehler-Meldungen produzieren
    set ast [list [dict create type bogus content {} meta {}]]
    set e1 ""
    set e2 ""
    catch {nroffparser::validate    $ast} e1
    catch {nroffparser::validateAST $ast} e2
    assertEqual $e1 $e2 "validate und validateAST liefern gleiche Errors"
}

# ============================================================
# F. Integration: alle Standard-Konstrukte einmal durch
# ============================================================

test "validator.integration_full_manpage" {
    # Ein kleiner aber repräsentativer Mix von Konstrukten,
    # die alle Inline-Typen berühren plus blank/list.
    set src {.TH test n
.SH NAME
test \- a test command
.SH SYNOPSIS
\fBtest\fR ?\fIarg\fR?
.SH DESCRIPTION
This has \fBbold\fR and \fIitalic\fR text.
.PP
A second paragraph.
.TP
\fB-flag\fR
A flag option.
.SH "SEE ALSO"
array(n), dict(n)
}
    set ast [nroffparser::parse $src test.n]
    assert [nroffparser::validate $ast] "voller Manpage-Mix durchläuft"
}

test::runAll
