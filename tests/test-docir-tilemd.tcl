#!/usr/bin/env tclsh
# test-docir-tilemd.tcl -- Smoke-Tests fuer docir::tilemd

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]
package require docir::tilemd

# Helper: minimales DocIR
proc minimalIr {} {
    return [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "Test Sheet" meta {}]] \
            meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "Code Sec" meta {}]] \
            meta [dict create level 2]] \
        [dict create type pre content [list \
            [dict create type text text "set x 1" meta {}]] meta {}] \
        [dict create type heading content [list \
            [dict create type text text "List Sec" meta {}]] \
            meta [dict create level 2]] \
        [dict create type list content [list \
            [dict create type listItem content [list \
                [dict create type text text "first" meta {}]] meta {}] \
            [dict create type listItem content [list \
                [dict create type text text "second" meta {}]] meta {}] \
        ] meta {kind ul}]]
}

set tmpDir [file join [pwd] tmp-tilemd-tests]
file mkdir $tmpDir

# ============================================================
# A. Render & Struktur
# ============================================================

test "tilemd.render.creates_md_file" {
    set out [file join $tmpDir test1.md]
    file delete -force $out
    ::docir::tilemd::render [minimalIr] $out
    assert [file exists $out] "MD-Datei wurde nicht erzeugt"
    set sz [file size $out]
    assert [expr {$sz > 50}] "MD zu klein ($sz bytes)"
}

test "tilemd.render.starts_with_h1_sheet_title" {
    set out [file join $tmpDir h1.md]
    ::docir::tilemd::render [minimalIr] $out
    set fh [open $out r]
    set md [read $fh]
    close $fh
    assert [string match "# Test Sheet*" $md] "MD sollte mit '# Test Sheet' beginnen"
}

test "tilemd.render.section_titles_as_h2" {
    set out [file join $tmpDir h2.md]
    ::docir::tilemd::render [minimalIr] $out
    set fh [open $out r]
    set md [read $fh]
    close $fh
    assert [string match "*## Code Sec*" $md] "Section sollte ## H2"
    assert [string match "*## List Sec*" $md] "List Section sollte ## H2"
}

# ============================================================
# B. Section-Type Rendering
# ============================================================

test "tilemd.code.fenced_block" {
    set out [file join $tmpDir code.md]
    ::docir::tilemd::render [minimalIr] $out
    set fh [open $out r]
    set md [read $fh]
    close $fh
    assert [string match "*\n```\nset x 1\n```\n*" $md] \
        "code-Section sollte fenced ```...``` sein"
}

test "tilemd.list.uses_dash_bullet" {
    set out [file join $tmpDir list.md]
    ::docir::tilemd::render [minimalIr] $out
    set fh [open $out r]
    set md [read $fh]
    close $fh
    assert [string match "*\n- first\n- second\n*" $md] \
        "list-Section sollte - Bullets"
}

test "tilemd.hint.uses_blockquote" {
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "T" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "Hint" meta {}]] meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text text "this is a hint" meta {}]] meta {}]]
    set out [file join $tmpDir hint.md]
    ::docir::tilemd::render $ir $out
    set fh [open $out r]
    set md [read $fh]
    close $fh
    assert [string match "*> this is a hint*" $md] \
        "hint-Section sollte > blockquote"
}

test "tilemd.code-intro.intro_then_fenced_code" {
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "T" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "CodeIntro" meta {}]] meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text text "explanation" meta {}]] meta {}] \
        [dict create type pre content [list \
            [dict create type text text "code line" meta {}]] meta {}]]
    set out [file join $tmpDir codeintro.md]
    ::docir::tilemd::render $ir $out
    set fh [open $out r]
    set md [read $fh]
    close $fh
    assert [string match "*explanation\n\n```\ncode line\n```*" $md] \
        "code-intro sollte 'intro\\n\\n```\\ncode\\n```' Form haben"
}

test "tilemd.image.uses_image_syntax" {
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "T" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "Pic" meta {}]] meta [dict create level 2]] \
        [dict create type image content {} meta [dict create url /img.png alt "Alt" title "Tip"]]]
    set out [file join $tmpDir image.md]
    ::docir::tilemd::render $ir $out
    set fh [open $out r]
    set md [read $fh]
    close $fh
    assert [regexp {!\[Alt\]\(/img\.png "Tip"\)} $md] \
        {image mit title sollte ![alt](url "title") sein}
}

test "tilemd.table.uses_md_table" {
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "T" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "Tab" meta {}]] meta [dict create level 2]] \
        [dict create type table content [list \
            [dict create type tableRow content [list \
                [dict create type tableCell content [list \
                    [dict create type text text "L1" meta {}]] meta {}] \
                [dict create type tableCell content [list \
                    [dict create type text text "V1" meta {}]] meta {}]] meta {}]] \
            meta [dict create columns 2]]]
    set out [file join $tmpDir tab.md]
    ::docir::tilemd::render $ir $out
    set fh [open $out r]
    set md [read $fh]
    close $fh
    assert [string match "*| L1 | V1 |*" $md] "table sollte | L1 | V1 | als Zeile"
}

# B2. Escaping (2026-10-22, Bash-Spickzettel: ${#var}, [[ ]], a|b)
proc csdSheetMd {sec} {
    set sheet [dict create title T subtitle "" sections [list $sec]]
    set out [file join $::tmpDir esc.md]
    ::docir::tilemd::renderSheets [list $sheet] $out
    set fh [open $out r]; fconfigure $fh -encoding utf-8
    set md [read $fh]; close $fh
    return $md
}
test "tilemd.escape.table_literal" {
    set md [csdSheetMd {title S type table content {{{a|b)} {${#var} [[ x ]] *.txt _y <z>}}}}]
    assert [expr {[string first {| a\|b) | \${#var} \[\[ x \]\] \*.txt \_y \<z> |} $md] >= 0}] \
        "Tabelle: | \$ \[ \* \_ \< escapen: $md"
}
test "tilemd.escape.table_mono_code_span" {
    set md [csdSheetMd {title S type table content {{L {echo `x` | wc} 1}}}]
    assert [expr {[string first {| L | ``echo `x` \| wc`` |} $md] >= 0}] "mono: Code-Span, Fence laenger als Inhalt: $md"
}
test "tilemd.escape.list_keeps_markup" {
    set md [csdSheetMd {title S type list content {{**fett** und `code` und [Doku](https://x.org) $HOME}}}]
    assert [expr {[string first {- **fett** und `code` und [Doku](https://x.org) \$HOME} $md] >= 0}] "Liste: Markup bleibt, \$ escapt: $md"
}
test "tilemd.escape.code_fence_longer" {
    set md [csdSheetMd {title S type code content {{```} {x}}}]
    assert [string match "*````\n```\nx\n````*" $md] "Fence laenger als ``` im Code: $md"
}

# ============================================================
# C. TOC + Multi-Sheet
# ============================================================

test "tilemd.toc.single_sheet_no_toc" {
    set out [file join $tmpDir no-toc.md]
    ::docir::tilemd::render [minimalIr] $out
    set fh [open $out r]
    set md [read $fh]
    close $fh
    assert [expr {![string match "*## Inhalt*" $md]}] \
        "single-Sheet sollte KEIN TOC haben"
}

test "tilemd.toc.multi_sheet_has_toc" {
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "Sheet One" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "S" meta {}]] meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text text "x" meta {}]] meta {}] \
        [dict create type heading content [list \
            [dict create type text text "Sheet Two" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "T" meta {}]] meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text text "y" meta {}]] meta {}]]
    set out [file join $tmpDir multi.md]
    ::docir::tilemd::render $ir $out
    set fh [open $out r]
    set md [read $fh]
    close $fh
    assert [string match "*## Inhalt*" $md] "Multi-Sheet sollte TOC haben"
    # `[` ist Glob-Special — wir suchen mit regexp statt string match
    assert [regexp {\[Sheet One\]\(#sheet-one\)} $md] "TOC-Link auf Sheet 1"
    assert [regexp {\[Sheet Two\]\(#sheet-two\)} $md] "TOC-Link auf Sheet 2"
    assert [string match "*<!-- pagebreak -->*" $md] \
        "Multi-Sheet sollte pagebreak-Trenner haben"
}

test "tilemd.toc.no_toc_option_disables" {
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content [list \
            [dict create type text text "Sheet One" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "S" meta {}]] meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text text "x" meta {}]] meta {}] \
        [dict create type heading content [list \
            [dict create type text text "Sheet Two" meta {}]] meta [dict create level 1]] \
        [dict create type heading content [list \
            [dict create type text text "T" meta {}]] meta [dict create level 2]] \
        [dict create type paragraph content [list \
            [dict create type text text "y" meta {}]] meta {}]]
    set out [file join $tmpDir no-toc-opt.md]
    ::docir::tilemd::render $ir $out -toc false
    set fh [open $out r]
    set md [read $fh]
    close $fh
    assert [expr {![string match "*## Inhalt*" $md]}] \
        "-toc false sollte TOC unterdruecken"
}

# ============================================================
# D. -hr Option
# ============================================================

test "tilemd.hr.default_true_separates_sections" {
    set out [file join $tmpDir hr.md]
    ::docir::tilemd::render [minimalIr] $out
    set fh [open $out r]
    set md [read $fh]
    close $fh
    set hrCount [regexp -all {\n---\n} $md]
    assert [expr {$hrCount >= 2}] "Mindestens 2 hr (zwischen 2 Sections)"
}

test "tilemd.hr.false_no_separator" {
    set out [file join $tmpDir no-hr.md]
    ::docir::tilemd::render [minimalIr] $out -hr false
    set fh [open $out r]
    set md [read $fh]
    close $fh
    set hrCount [regexp -all {\n---\n} $md]
    assertEqual 0 $hrCount
}

# Aufraeumen vor exit -- danach lief es nie (Ordner blieb liegen, Review
# 2026-10-24).
set rc [test::runAll]
file delete -force $tmpDir
exit $rc
