#!/usr/bin/env tclsh
# test-validator-inline-breaks.tcl -- softbreak/linebreak im DocIR-Validator
#
# Hintergrund: Das 2026-06-14-Release ergaenzte den strukturierten
# `softbreak`-Inline in allen Renderern und in der Spec (docir-spec.md
# Z. 306/325), vergass aber die `inlineTypes`-Whitelist im Validator
# (docir-0.1.tm). Dadurch meldete gueltige IR mit einem softbreak-Knoten
# "Unbekannter Inline-Typ 'softbreak'" -- und nach dem Whitelisten zunaechst
# "Feld 'text' fehlt", weil softbreak in den default-Required-Field-Zweig fiel.
#
# Diese Suite verhindert Regression auf beide Punkte und prueft, dass bewusst
# ungueltige Inline-Typen weiterhin abgelehnt werden. Sie braucht keinen
# externen Parser -- die IR wird von Hand gebaut.

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

package require docir

# Helper: minimale Paragraph-IR mit gegebener Inline-Liste
proc paraIr {inlines} {
    return [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type paragraph content $inlines meta {}]]
}

# ============================================================
# softbreak ist ein gueltiger Inline-Typ (Spec-konform)
# ============================================================

test "validator.softbreak.is_valid" {
    set ir [paraIr [list \
        [dict create type text text "a"] \
        [dict create type softbreak] \
        [dict create type text text "b"]]]
    assertEqual 0 [llength [docir::validate $ir]] \
        "softbreak sollte ein gueltiger Inline-Typ sein"
}

# softbreak hat kein text-Feld -- darf wie linebreak KEINE
# "Feld 'text' fehlt"-Meldung ausloesen.
test "validator.softbreak.needs_no_text_field" {
    set ir [paraIr [list [dict create type softbreak]]]
    assertEqual 0 [llength [docir::validate $ir]] \
        "softbreak darf kein text-Feld verlangen"
}

# ============================================================
# linebreak bleibt gueltig (keine Regression)
# ============================================================

test "validator.linebreak.is_valid" {
    set ir [paraIr [list \
        [dict create type text text "a"] \
        [dict create type linebreak] \
        [dict create type text text "b"]]]
    assertEqual 0 [llength [docir::validate $ir]] \
        "linebreak sollte gueltig bleiben"
}

# ============================================================
# Unbekannte Inline-Typen werden weiterhin gemeldet
# (Validierung nicht aufgeweicht)
# ============================================================

test "validator.unknown_inline.is_rejected" {
    set ir [paraIr [list \
        [dict create type text text "a"] \
        [dict create type bogus]]]
    assert {[llength [docir::validate $ir]] > 0} \
        "unbekannter Inline-Typ muss weiterhin gemeldet werden"
}

# Auch ein softbreak GEMISCHT mit gueltigem Inhalt darf nichts kaputt machen
test "validator.softbreak.mixed_paragraph_ok" {
    set ir [paraIr [list \
        [dict create type text text "Zeile eins"] \
        [dict create type softbreak] \
        [dict create type strong text "fett"] \
        [dict create type softbreak] \
        [dict create type text text "Zeile drei"]]]
    assertEqual 0 [llength [docir::validate $ir]] \
        "softbreak zwischen text/strong sollte sauber validieren"
}

test::runAll
