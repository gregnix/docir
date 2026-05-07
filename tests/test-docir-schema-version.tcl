#!/usr/bin/env tclsh
# test-docir-schema-version.tcl
#
# Tests fuer ::docir::schemaVersion und ::docir::checkSchemaVersion.
#
# checkSchemaVersion implementiert die Hub-API fuer Konsumenten
# (Quellen, Senken, externe Validatoren), um IR-Streams gegen die
# erlaubten Schema-Versionen zu pruefen — mit zwei Modi:
#
#   lenient (strict=0, default):
#       - IR ohne doc_meta-Block ("Version 0") wird toleriert.
#       - IR mit doc_meta-Block muss eine erlaubte Version enthalten.
#
#   strict (strict=1):
#       - IR ohne doc_meta-Block wird abgelehnt.
#       - IR mit doc_meta-Block muss eine erlaubte Version enthalten.

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

# ============================================================
# Hilfen — IR-Konstruktoren
# ============================================================

# Minimales IR mit doc_meta-Block.
proc irWithMeta {version} {
    return [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion $version]] \
        [dict create type paragraph content [list \
            [dict create type text value "x" meta {}]] meta {}]]
}

# IR ohne doc_meta-Block.
proc irWithoutMeta {} {
    return [list \
        [dict create type paragraph content [list \
            [dict create type text value "x" meta {}]] meta {}]]
}

# IR mit doc_meta aber ohne irSchemaVersion-Feld in meta.
# (Validator faengt das vorher ab — checkSchemaVersion sollte aber
#  defensiv mit fehlendem Feld umgehen.)
proc irWithMetaNoVersion {} {
    return [list \
        [dict create type doc_meta content {} meta [dict create author "X"]] \
        [dict create type paragraph content [list \
            [dict create type text value "x" meta {}]] meta {}]]
}

# ============================================================
# A. schemaVersion -- niedrige Helper-API
# ============================================================

test "schemaVersion.no_doc_meta_returns_0" {
    set v [::docir::schemaVersion [irWithoutMeta]]
    assert [string equal $v 0] "schemaVersion soll 0 zurueckgeben fuer IR ohne doc_meta, war: $v"
}

test "schemaVersion.with_doc_meta_returns_version" {
    set v [::docir::schemaVersion [irWithMeta 1]]
    assert [string equal $v 1] "schemaVersion soll 1 zurueckgeben fuer IR mit doc_meta v1, war: $v"
}

test "schemaVersion.empty_ir_returns_0" {
    set v [::docir::schemaVersion {}]
    assert [string equal $v 0] "schemaVersion auf leerem IR soll 0 zurueckgeben, war: $v"
}

test "schemaVersion.doc_meta_without_version_returns_0" {
    set v [::docir::schemaVersion [irWithMetaNoVersion]]
    assert [string equal $v 0] "schemaVersion soll 0 zurueckgeben wenn doc_meta ohne irSchemaVersion, war: $v"
}

# ============================================================
# B. checkSchemaVersion -- lenient mode (default, strict=0)
# ============================================================

test "checkSchemaVersion.lenient.no_doc_meta_ok" {
    set err [::docir::checkSchemaVersion [irWithoutMeta]]
    assert [string equal $err ""] "lenient: IR ohne doc_meta soll OK sein, war: '$err'"
}

test "checkSchemaVersion.lenient.supported_version_ok" {
    set err [::docir::checkSchemaVersion [irWithMeta 1]]
    assert [string equal $err ""] "lenient: v1 ist unterstuetzt, war: '$err'"
}

test "checkSchemaVersion.lenient.unsupported_version_error" {
    set err [::docir::checkSchemaVersion [irWithMeta 99]]
    assert [string match "*99*" $err] "lenient: v99 nicht unterstuetzt, sollte Fehler ergeben, war: '$err'"
}

test "checkSchemaVersion.lenient.custom_supported_list" {
    # Wenn der Aufrufer eine engere Liste angibt, gilt die.
    # Schreiben wir IR mit Version 2, supported nur {1,3}.
    set err [::docir::checkSchemaVersion [irWithMeta 2] {1 3}]
    assert [string match "*2*" $err] "lenient: v2 nicht in {1,3}, sollte Fehler ergeben, war: '$err'"
}

test "checkSchemaVersion.lenient.custom_supported_list_match" {
    set err [::docir::checkSchemaVersion [irWithMeta 1] {1 3}]
    assert [string equal $err ""] "lenient: v1 ist in {1,3}, war: '$err'"
}

# ============================================================
# C. checkSchemaVersion -- strict mode (strict=1)
# ============================================================

test "checkSchemaVersion.strict.no_doc_meta_error" {
    set err [::docir::checkSchemaVersion [irWithoutMeta] {} 1]
    assert [string match "*strict*" $err] "strict: IR ohne doc_meta sollte Fehler ergeben, war: '$err'"
}

test "checkSchemaVersion.strict.supported_version_ok" {
    set err [::docir::checkSchemaVersion [irWithMeta 1] {} 1]
    assert [string equal $err ""] "strict: v1 ist unterstuetzt, war: '$err'"
}

test "checkSchemaVersion.strict.unsupported_version_error" {
    set err [::docir::checkSchemaVersion [irWithMeta 99] {} 1]
    assert [string match "*99*" $err] "strict: v99 nicht unterstuetzt, war: '$err'"
}

test "checkSchemaVersion.strict.custom_supported_list" {
    set err [::docir::checkSchemaVersion [irWithMeta 2] {1 3} 1]
    assert [string match "*2*" $err] "strict: v2 nicht in {1,3}, war: '$err'"
}

test "checkSchemaVersion.strict.empty_ir_rejected" {
    set err [::docir::checkSchemaVersion {} {} 1]
    assert [string match "*strict*" $err] "strict: leeres IR sollte Fehler ergeben, war: '$err'"
}

# ============================================================
# D. SUPPORTED_SCHEMA_VERSIONS -- Hub-Liste
# ============================================================

test "SUPPORTED_SCHEMA_VERSIONS.contains_1" {
    set ::docir::dummy ""
    set supported $::docir::SUPPORTED_SCHEMA_VERSIONS
    assert [expr {1 in $supported}] "Version 1 muss in SUPPORTED_SCHEMA_VERSIONS sein, ist: $supported"
}

# ============================================================
# E. Versionierung-Edge-Cases
# ============================================================

test "checkSchemaVersion.lenient.multiple_versions_ok" {
    # Wenn supported {1 2 3}, ist jedes davon OK.
    foreach v {1 2 3} {
        set err [::docir::checkSchemaVersion [irWithMeta $v] {1 2 3}]
        assert [string equal $err ""] "lenient: v$v in {1,2,3} sollte OK sein, war: '$err'"
    }
}

test "checkSchemaVersion.strict.error_message_contains_supported" {
    # Fehlermeldung sollte die erlaubten Versionen nennen.
    set err [::docir::checkSchemaVersion [irWithMeta 99] {1 2}]
    assert [string match "*1 2*" $err] "Fehler sollte erlaubte Versionen nennen, war: '$err'"
}

# ============================================================
# Test-Run Summary
# ============================================================
test::runAll
