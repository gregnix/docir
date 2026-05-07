#!/usr/bin/env tclsh
# test-docir-tilepdf.tcl -- Smoke-Tests fuer docir::tilepdf
#
# Tests sind smoke-orientiert: erzeugt PDF, prueft dass File existiert
# und nicht-leer ist. Fuer Layout-Pixel-Genauigkeit waeren
# screenshot-tests noetig — gehoert nicht in unit-tests.

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

# pdf4tcl muss verfuegbar sein
if {[catch {package require pdf4tcl}]} {
    puts "Skipping tilepdf tests: pdf4tcl not available"
    test::runAll
    return
}
package require docir::tilepdf

# Helper: minimales DocIR mit doc_meta + ein paar Sektionen
proc minimalIr {} {
    return [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text value "Test Sheet" meta {}]] \
            meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text value "Section A" meta {}]] \
            meta [dict create level 2]] \
        [dict create type pre content [list \
            [dict create type text value "set x 1" meta {}]] meta {}] \
        [dict create type heading content [list \
            [dict create type text value "Section B" meta {}]] \
            meta [dict create level 2]] \
        [dict create type list content [list \
            [dict create type listItem content [list \
                [dict create type text value "first" meta {}]] meta {}] \
            [dict create type listItem content [list \
                [dict create type text value "second" meta {}]] meta {}] \
        ] meta {kind ul}]]
}

# Multi-Sheet IR (zwei H1)
proc multiSheetIr {} {
    return [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text value "Sheet One" meta {}]] \
            meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text value "A" meta {}]] \
            meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text value "Hello" meta {}]] meta {}] \
        [dict create type heading content [list \
            [dict create type text value "Sheet Two" meta {}]] \
            meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text value "B" meta {}]] \
            meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text value "World" meta {}]] meta {}]]
}

set tmpDir [file join [pwd] tmp-tilepdf-tests]
file mkdir $tmpDir

# ============================================================
# A. _streamToSheets — Sheet-Aufteilung
# ============================================================

test "tilepdf.stream.single_sheet_with_h1_title" {
    set sheets [::docir::tilepdf::_streamToSheets [minimalIr] "" ""]
    assertEqual 1 [llength $sheets]
    set sheet [lindex $sheets 0]
    assertEqual "Test Sheet" [dict get $sheet title]
    assert [expr {[llength [dict get $sheet sections]] >= 2}] \
        "mindestens 2 Sections (A, B)"
}

test "tilepdf.stream.multi_h1_creates_multi_sheets" {
    set sheets [::docir::tilepdf::_streamToSheets [multiSheetIr] "" ""]
    assertEqual 2 [llength $sheets]
    assertEqual "Sheet One" [dict get [lindex $sheets 0] title]
    assertEqual "Sheet Two" [dict get [lindex $sheets 1] title]
}

test "tilepdf.stream.title_override_wins" {
    set sheets [::docir::tilepdf::_streamToSheets [minimalIr] "Override Title" ""]
    assertEqual "Override Title" [dict get [lindex $sheets 0] title]
}

test "tilepdf.stream.empty_doc_header_does_not_clear_h1_title" {
    # Bug-Regression: zweite doc_header mit name="" überschreibt Sheet-1-Titel nicht
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type doc_header content {} meta [dict create name ""]] \
        [dict create type heading content [list \
            [dict create type text value "Real Title" meta {}]] \
            meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text value "S" meta {}]] \
            meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text value "x" meta {}]] meta {}] \
        [dict create type doc_header content {} meta [dict create name ""]] \
        [dict create type heading content [list \
            [dict create type text value "Other Sheet" meta {}]] \
            meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text value "T" meta {}]] \
            meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text value "y" meta {}]] meta {}]]
    set sheets [::docir::tilepdf::_streamToSheets $ir "" ""]
    assertEqual "Real Title" [dict get [lindex $sheets 0] title]
    assertEqual "Other Sheet" [dict get [lindex $sheets 1] title]
}

# ============================================================
# B. _packSection — Block-Typ-Klassifikation
# ============================================================

test "tilepdf.pack.pre_only_becomes_code" {
    set content [list \
        [dict create type pre content [list \
            [dict create type text value "code line" meta {}]] meta {}]]
    set section [::docir::tilepdf::_packSection "X" $content]
    assertEqual "code" [dict get $section type]
}

test "tilepdf.pack.list_only_becomes_list" {
    set content [list \
        [dict create type list content [list \
            [dict create type listItem content [list \
                [dict create type text value "i1" meta {}]] meta {}]] meta {}]]
    set section [::docir::tilepdf::_packSection "X" $content]
    assertEqual "list" [dict get $section type]
}

test "tilepdf.pack.paragraph_only_becomes_hint" {
    set content [list \
        [dict create type paragraph content [list \
            [dict create type text value "p1" meta {}]] meta {}]]
    set section [::docir::tilepdf::_packSection "X" $content]
    assertEqual "hint" [dict get $section type]
}

test "tilepdf.pack.table_only_becomes_table" {
    set content [list \
        [dict create type table content [list \
            [dict create type tableRow content [list \
                [dict create type tableCell content [list \
                    [dict create type text value "L" meta {}]] meta {}] \
                [dict create type tableCell content [list \
                    [dict create type text value "V" meta {}]] meta {}]] meta {}]] \
            meta [dict create columns 2]]]
    set section [::docir::tilepdf::_packSection "X" $content]
    assertEqual "table" [dict get $section type]
    set rows [dict get $section content]
    assertEqual 1 [llength $rows]
}

test "tilepdf.pack.intro_para_plus_pre_becomes_code_intro" {
    # Heuristik: 1 Intro-Paragraph + Code -> code-intro Section
    # mit Intro-Lines (Helvetica) + Code-Lines (Courier)
    set content [list \
        [dict create type paragraph content [list \
            [dict create type text value "Intro" meta {}]] meta {}] \
        [dict create type pre content [list \
            [dict create type text value "code" meta {}]] meta {}]]
    set section [::docir::tilepdf::_packSection "X" $content]
    assertEqual "code-intro" [dict get $section type]
    assertEqual {Intro} [dict get $section intro]
    assertEqual {code} [dict get $section content]
}

test "tilepdf.pack.code_only_no_intro_remains_code" {
    # Keine Paragraphen -> reine code-Section, nicht code-intro
    set content [list \
        [dict create type pre content [list \
            [dict create type text value "code" meta {}]] meta {}]]
    set section [::docir::tilepdf::_packSection "X" $content]
    assertEqual "code" [dict get $section type]
}

test "tilepdf.pack.really_mixed_becomes_hint" {
    # paragraph + list + pre = wirklich gemischt -> hint
    set content [list \
        [dict create type paragraph content [list \
            [dict create type text value "p" meta {}]] meta {}] \
        [dict create type list content [list \
            [dict create type listItem content [list \
                [dict create type text value "i" meta {}]] meta {}]] \
            meta {kind ul}] \
        [dict create type pre content [list \
            [dict create type text value "code" meta {}]] meta {}]]
    set section [::docir::tilepdf::_packSection "X" $content]
    assertEqual "hint" [dict get $section type]
}

# ============================================================
# C. render — End-to-End PDF erzeugen
# ============================================================

test "tilepdf.render.creates_pdf_file" {
    set out [file join $tmpDir test1.pdf]
    file delete -force $out
    ::docir::tilepdf::render [minimalIr] $out
    assert [file exists $out] "PDF-Datei wurde nicht erzeugt"
    set sz [file size $out]
    assert [expr {$sz > 1000}] "PDF zu klein ($sz bytes), wahrscheinlich leer"
}

test "tilepdf.render.multi_sheet_pdf_has_multiple_pages" {
    set out [file join $tmpDir multi.pdf]
    file delete -force $out
    ::docir::tilepdf::render [multiSheetIr] $out
    assert [file exists $out]
    # PDF hat 2 Sheets -> mindestens 2 Pages
    set fh [open $out r]
    fconfigure $fh -translation binary
    set bytes [read $fh]
    close $fh
    set pageCount [regexp -all {/Type\s*/Page\M} $bytes]
    assert [expr {$pageCount >= 2}] \
        "Multi-Sheet PDF muss mehrere Pages haben, hat $pageCount"
}

test "tilepdf.render.invalid_schema_version_rejected" {
    set badIr [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 99]] \
        [dict create type paragraph content [list \
            [dict create type text value "x" meta {}]] meta {}]]
    set caught 0
    if {[catch {::docir::tilepdf::render $badIr [file join $tmpDir bad.pdf]} err]} {
        set caught 1
        assert [string match "*99*" $err] \
            "Fehler sollte Versions-Nummer nennen, war: $err"
    }
    assert $caught "render mit ungueltiger Schema-Version sollte fail"
}

# ============================================================
# D. Theme-Support
# ============================================================

test "tilepdf.theme.set_light_populates_white_bg" {
    ::docir::tilepdf::_setTheme light
    assertEqual 1.0 $::docir::tilepdf::COL(bg_r)
    assertEqual 1.0 $::docir::tilepdf::COL(bg_g)
    assertEqual 1.0 $::docir::tilepdf::COL(bg_b)
    assertEqual 0.0 $::docir::tilepdf::COL(fg_r)
}

test "tilepdf.theme.set_dark_populates_dark_bg" {
    ::docir::tilepdf::_setTheme dark
    assert [expr {$::docir::tilepdf::COL(bg_r) < 0.2}] \
        "dark theme bg_r sollte < 0.2 sein"
    assert [expr {$::docir::tilepdf::COL(fg_r) > 0.8}] \
        "dark theme fg_r sollte > 0.8 sein"
}

test "tilepdf.theme.unknown_theme_errors" {
    set caught 0
    if {[catch {::docir::tilepdf::_setTheme purple} err]} {
        set caught 1
        assert [string match "*unknown theme*" $err] \
            "Fehler sollte 'unknown theme' enthalten, war: $err"
    }
    assert $caught "_setTheme mit unknown theme sollte fail"
    # Reset auf light fuer andere Tests
    ::docir::tilepdf::_setTheme light
}

test "tilepdf.render.dark_theme_creates_pdf" {
    set out [file join $tmpDir dark.pdf]
    file delete -force $out
    ::docir::tilepdf::render [minimalIr] $out -theme dark
    assert [file exists $out] "dark-theme PDF wurde nicht erzeugt"
    assert [expr {[file size $out] > 1000}] "dark PDF zu klein"
}

test "tilepdf.render.unknown_theme_option_rejected" {
    set caught 0
    if {[catch {::docir::tilepdf::render [minimalIr] \
        [file join $tmpDir bad-theme.pdf] -theme purple} err]} {
        set caught 1
    }
    assert $caught "render mit unknown theme sollte fail"
}

# ============================================================
# E. Tokenizer (_tokenize) — Inline-Markup Erkennung
# ============================================================

test "tilepdf.tokenize.plain_text" {
    set tokens [::docir::tilepdf::_tokenize "hello world"]
    assertEqual 1 [llength $tokens]
    assertEqual {plain {hello world}} [lindex $tokens 0]
}

test "tilepdf.tokenize.bold" {
    set tokens [::docir::tilepdf::_tokenize "**bold**"]
    assertEqual 1 [llength $tokens]
    assertEqual {bold bold} [lindex $tokens 0]
}

test "tilepdf.tokenize.italic" {
    set tokens [::docir::tilepdf::_tokenize "*ital*"]
    assertEqual 1 [llength $tokens]
    assertEqual {italic ital} [lindex $tokens 0]
}

test "tilepdf.tokenize.code" {
    set tokens [::docir::tilepdf::_tokenize "`code`"]
    assertEqual 1 [llength $tokens]
    assertEqual {code code} [lindex $tokens 0]
}

test "tilepdf.tokenize.mixed" {
    set tokens [::docir::tilepdf::_tokenize "use **bold** and `code` here"]
    assertEqual 5 [llength $tokens]
    assertEqual {plain {use }}    [lindex $tokens 0]
    assertEqual {bold bold}       [lindex $tokens 1]
    assertEqual {plain { and }}   [lindex $tokens 2]
    assertEqual {code code}       [lindex $tokens 3]
    assertEqual {plain { here}}   [lindex $tokens 4]
}

test "tilepdf.fontFor.maps_types_to_pdf_fonts" {
    assertEqual Helvetica         [::docir::tilepdf::_fontFor plain]
    assertEqual Helvetica-Bold    [::docir::tilepdf::_fontFor bold]
    assertEqual Helvetica-Oblique [::docir::tilepdf::_fontFor italic]
    assertEqual Courier           [::docir::tilepdf::_fontFor code]
}

test::runAll

# Cleanup nach allen Tests
file delete -force $tmpDir
