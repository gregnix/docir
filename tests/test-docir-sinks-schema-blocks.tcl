#!/usr/bin/env tclsh
# test-docir-sinks-schema-blocks.tcl
#
# Reviewer-Empfehlung 2026-05-07 (Phase 4 / nach A.3):
#
#   "Für jeden neuen Top-Level-Blocktyp einen kleinen Test
#    'IR mit genau diesem Block → Senke X darf nicht unknown
#    loggen / muss skippen' — oder zentral in der Senke ein
#    doc_meta-Skip statt sieben Copy-Paste-Stellen."
#
# Beides wurde umgesetzt:
#   - zentrale Liste docir::SCHEMA_ONLY_BLOCKS in docir-0.1.tm
#   - Helper docir::isSchemaOnly
#   - alle sieben Senken nutzen den Helper im default-Case
#
# Dieser Test stellt sicher, dass **jeder** Block-Typ aus
# SCHEMA_ONLY_BLOCKS in jeder String-Senke silent geskippt wird:
#
#   - kein "unknown"-Marker im Output
#   - kein Tcl-Error beim Render
#
# Wenn ein neuer Schema-only-Block-Typ eingeführt wird (= Eintrag
# in SCHEMA_ONLY_BLOCKS), läuft dieser Test ihn automatisch mit.
# ============================================================

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

# String-Senken explizit sourcen — test-setup lädt sie nicht alle
# automatisch. (Pattern wie in test-docir-roff/html/md/svg.tcl.)
foreach sinkMod {
    roff-0.1.tm
    html-0.1.tm
    md-0.1.tm
    svg-0.1.tm
} {
    source -encoding utf-8 [file join $testDir .. lib tm docir $sinkMod]
}


# Helper: konstruiere ein minimales IR mit einem Schema-only-Block am
# Anfang plus einem leeren Paragraph. Der Paragraph sorgt dafür, dass
# der Render-Pfad nicht beim ersten Block stoppt.
proc makeIrWith {schemaType} {
    return [list \
        [dict create type $schemaType content {} meta {irSchemaVersion 1}] \
        [dict create type paragraph content {{type text text Hello}} meta {}]]
}

# Helper: sucht nach typischen "unknown"-Markern, die Senken bei
# tatsächlich unbekannten Block-Typen ausgeben würden.
proc containsUnknownMarker {output} {
    foreach pat {{unknown block} {unknown type} {type=*unknown} {block-unknown}} {
        if {[string match -nocase "*$pat*" $output]} { return 1 }
    }
    return 0
}

# Test-Helper: läuft pro (sink, schemaBlock) und prüft kein Error +
# kein unknown-Marker im Output.
proc testSinkSchemaSkip {sink schemaBlock} {
    set ir       [makeIrWith $schemaBlock]
    set procName "::docir::${sink}::render"
    set out ""
    set ok [expr {[catch {set out [$procName $ir]} err] == 0}]
    assert $ok "Senke $sink wirft keinen Error für $schemaBlock-Block: $err"
    set hasMarker [containsUnknownMarker $out]
    assert [expr {!$hasMarker}] \
        "Senke $sink hat KEIN 'unknown'-Marker im Output für Schema-Block $schemaBlock (= war A.1-Folgebug)"
}

# ============================================================
# Test 1: docir::SCHEMA_ONLY_BLOCKS-Liste sanity
# ============================================================

test "schema-blocks.list_nonempty" {
    assert [expr {[llength $::docir::SCHEMA_ONLY_BLOCKS] >= 1}] \
        "SCHEMA_ONLY_BLOCKS hat mindestens einen Eintrag"
}

test "schema-blocks.list_contains_doc_meta" {
    assert [expr {"doc_meta" in $::docir::SCHEMA_ONLY_BLOCKS}] \
        "doc_meta ist als Schema-only markiert"
}

# ============================================================
# Test 2: docir::isSchemaOnly liefert korrekte Werte
# ============================================================

test "schema-blocks.isSchemaOnly_true_for_doc_meta" {
    assertEqual 1 [::docir::isSchemaOnly doc_meta] \
        "doc_meta ist schema-only"
}

test "schema-blocks.isSchemaOnly_false_for_paragraph" {
    assertEqual 0 [::docir::isSchemaOnly paragraph] \
        "paragraph ist NICHT schema-only"
}

test "schema-blocks.isSchemaOnly_false_for_unknown" {
    assertEqual 0 [::docir::isSchemaOnly nonsense_type] \
        "Unbekannter Typ ist nicht automatisch schema-only"
}

# ============================================================
# Test 3: Pro Schema-only-Block-Typ × pro String-Senke prüfen,
# dass kein "unknown"-Output erscheint und kein Tcl-Error fliegt.
#
# Sinks die direkt einen String liefern (renderToString-Pattern):
#   - docir-roff, docir-html, docir-md, docir-svg
# NICHT abgedeckt (Side-Effects auf Datei/Widget/Canvas — eigene
# Test-Pfade, getrennt von dieser Schicht):
#   - docir-pdf (pdf4tcl-Datei-Output)
#   - docir-canvas (Canvas-Widget)
#   - docir-renderer-tk (Text-Widget)
# ============================================================

set stringSinks {roff html md svg}

foreach schemaBlock $::docir::SCHEMA_ONLY_BLOCKS {
    foreach sink $stringSinks {
        set testName "schema-blocks.${sink}.no_unknown_for.${schemaBlock}"
        # Test-Body via format binden, damit sink+schemaBlock zur
        # Test-Definitions-Zeit in den Body eingesetzt werden (statt
        # zur Test-Lauf-Zeit, wo die foreach-Variablen schon weg wären).
        test $testName [format {testSinkSchemaSkip %s %s} $sink $schemaBlock]
    }
}

# ============================================================
# Run
# ============================================================

test::runAll
