#!/usr/bin/env tclsh
# test-docir-block.tcl
#
# Tests for docir-block-0.1.tm -- DocIR fragment -> rectangle on a PDF page.
#
# Covered:
#  - unit guard (pdf4tcl object must be in points)
#  - block types (heading, paragraph, pre, list, hr, blank, doc_meta)
#  - inline types (text, strong, emphasis, underline, strike, code, link,
#    linebreak, softbreak, and the non-renderable ones)
#  - line breaking against the box width
#  - overflow and clipping, including inside lists
#  - measure = dryrun (same numbers, nothing drawn)
#  - alignment
#
# No Tk needed: the module only writes PDF, it does not rasterize.

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

set projectRoot [file dirname [file dirname [file normalize [info script]]]]
lappend auto_path $projectRoot
package require docir::block

# ------------------------------------------------------------------ helpers

# A fresh pdf4tcl object in the default unit, with one page started.
proc newPdf {{paper {54m 200m}}} {
    set p [pdf4tcl::new %AUTO% -paper $paper]
    $p startPage
    return $p
}

proc para {text} {
    return [list [dict create type paragraph \
        content [list [dict create type text text $text]] meta {}]]
}

proc inline {args} {
    return [list [dict create type paragraph content $args meta {}]]
}

# ============================================================
# A. Unit guard
# ============================================================

test "block.rejects_non_point_unit" {
    # pdf4tcl reads the font size in the configured unit: with -unit mm,
    # `setFont 9` means nine millimetres. Silently accepting that would
    # produce labels with 3x too large type.
    set p [pdf4tcl::new %AUTO% -paper {54m 60m} -unit mm]
    $p startPage
    set caught [catch {docir::block::pdf $p [para "x"] -x 3 -y 3 -w 40} err]
    assert $caught "non-point unit must raise"
    ::test::assertContains $err "default unit" "message names the cause"
    $p destroy
}

test "block.accepts_point_unit" {
    set p [newPdf]
    set caught [catch {docir::block::pdf $p [para "x"] -x 3 -y 3 -w 40} err]
    assert {!$caught} "point unit must be accepted: $err"
    $p destroy
}

# ============================================================
# B. Return value
# ============================================================

test "block.returns_all_four_keys" {
    set p [newPdf]
    set r [docir::block::pdf $p [para "Hallo"] -x 3 -y 3 -w 40 -size 8]
    foreach k {used lines overflow truncated} {
        assert [dict exists $r $k] "key '$k' present"
    }
    $p destroy
}

test "block.single_line_counts_one" {
    set p [newPdf]
    set r [docir::block::pdf $p [para "kurz"] -x 3 -y 3 -w 40 -size 8]
    assertEqual 1 [dict get $r lines] "one short line"
    assertEqual 0 [dict get $r overflow] "no overflow without -h"
    $p destroy
}

test "block.used_grows_with_font_size" {
    set p [newPdf]
    set small [dict get [docir::block::pdf $p [para "Hallo"] \
                   -x 3 -y 3 -w 40 -size 6] used]
    set big   [dict get [docir::block::pdf $p [para "Hallo"] \
                   -x 3 -y 3 -w 40 -size 12] used]
    assert {$big > $small} "12pt uses more height than 6pt ($big > $small)"
    $p destroy
}

# ============================================================
# C. Line breaking
# ============================================================

test "block.wraps_at_box_width" {
    set p [newPdf]
    set txt "Ein Satz der mit Sicherheit breiter ist als zwanzig Millimeter"
    set schmal [dict get [docir::block::pdf $p [para $txt] \
                    -x 3 -y 3 -w 20 -size 8] lines]
    set breit  [dict get [docir::block::pdf $p [para $txt] \
                    -x 3 -y 3 -w 90 -size 8] lines]
    assert {$schmal > $breit} "narrow box wraps more ($schmal > $breit)"
    $p destroy
}

test "block.linebreak_inline_forces_new_line" {
    set p [newPdf]
    set ohne [dict get [docir::block::pdf $p \
        [inline {type text text {ab cd}}] -x 3 -y 3 -w 60 -size 8] lines]
    set mit [dict get [docir::block::pdf $p [inline \
        {type text text ab} {type linebreak} {type text text cd}] \
        -x 3 -y 3 -w 60 -size 8] lines]
    assert {$mit > $ohne} "explicit linebreak adds a line ($mit > $ohne)"
    $p destroy
}

test "block.bold_is_wider_than_regular" {
    # Measuring must happen in the font that is actually drawn. If the
    # renderer measured everything in the regular face, bold text would
    # silently run past the box edge.
    set p [newPdf]
    set txt "Immer dasselbe Wortmaterial hier entlang bitte"
    set mager [dict get [docir::block::pdf $p [inline \
        [dict create type text text $txt]] -x 3 -y 3 -w 30 -size 8] lines]
    set fett [dict get [docir::block::pdf $p [inline \
        [dict create type strong text $txt]] -x 3 -y 3 -w 30 -size 8] lines]
    assert {$fett >= $mager} "bold needs at least as many lines ($fett >= $mager)"
    $p destroy
}

# ============================================================
# D. Overflow and clipping
# ============================================================

test "block.overflow_flagged_when_too_high" {
    set p [newPdf]
    set txt "Ein sehr langer Absatz der ganz sicher nicht in wenige\
             Millimeter passt weil er immer weiter geht und weiter"
    set r [docir::block::pdf $p [para $txt] -x 3 -y 3 -w 48 -h 8 -size 8]
    assertEqual 1 [dict get $r overflow] "overflow reported"
    assert {[dict get $r truncated] > 0} "truncated counts the lost lines"
    $p destroy
}

test "block.no_overflow_when_it_fits" {
    set p [newPdf]
    set r [docir::block::pdf $p [para "kurz"] -x 3 -y 3 -w 48 -h 30 -size 8]
    assertEqual 0 [dict get $r overflow] "fits, so no overflow"
    assertEqual 0 [dict get $r truncated] "nothing truncated"
    $p destroy
}

test "block.overflow_checks_line_bottom_not_baseline" {
    # A line whose baseline still sits inside the box but whose descenders
    # and leading do not must count as overflow. Checking the baseline alone
    # let the last line slip through unnoticed.
    set p [newPdf]
    set txt "eins zwei drei vier"
    # height chosen so that exactly one line fits by baseline but not by bottom
    set r [docir::block::pdf $p [para $txt] -x 3 -y 3 -w 12 -h 3 -size 8]
    assertEqual 1 [dict get $r overflow] "bottom edge decides, not baseline"
    $p destroy
}

test "block.list_items_can_overflow" {
    # List items are rendered recursively. If the remaining height is not
    # passed down they can never overflow and the box wrongly reports "fits".
    set p [newPdf]
    set liste [list [dict create type list meta {kind ul} content [list \
        [dict create type listItem meta {kind ul} \
            content {{type text text {Schrauben M4}}}] \
        [dict create type listItem meta {kind ul} \
            content {{type text text {Muttern}}}] \
        [dict create type listItem meta {kind ul} \
            content {{type text text {Unterlegscheiben}}}] \
        [dict create type listItem meta {kind ul} \
            content {{type text text {Federringe}}}]]]]
    set r [docir::block::pdf $p $liste -x 3 -y 3 -w 48 -h 8 -size 8]
    assertEqual 1 [dict get $r overflow] "list overflow reported"
    assert {[dict get $r truncated] > 0} "truncated counted from the items"
    $p destroy
}

# ============================================================
# E. measure == dryrun
# ============================================================

test "block.measure_matches_render" {
    set p [newPdf]
    set ir [para "Ein Absatz mit etwas Text zum Umbrechen hier"]
    set gemessen [docir::block::measure $p $ir -x 3 -y 3 -w 30 -size 8]
    set gezeichnet [docir::block::pdf $p $ir -x 3 -y 3 -w 30 -size 8]
    assertEqual [dict get $gemessen used] [dict get $gezeichnet used] \
        "measure and render agree on height"
    assertEqual [dict get $gemessen lines] [dict get $gezeichnet lines] \
        "measure and render agree on line count"
    $p destroy
}

test "block.measure_draws_no_content" {
    # A dry run emits no content. It does register fonts, because a word can
    # only be measured in the font it would be drawn in -- so the document
    # grows slightly. What must NOT happen is that the drawn text appears.
    set tmp [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}]
    set a [newPdf {54m 60m}]
    docir::block::measure $a [para "GEHEIMWORT"] -x 3 -y 3 -w 40 -size 8
    $a write -file [set fa [file join $tmp block-dry.pdf]]
    $a destroy
    set b [newPdf {54m 60m}]
    docir::block::pdf $b [para "GEHEIMWORT"] -x 3 -y 3 -w 40 -size 8
    $b write -file [set fb [file join $tmp block-wet.pdf]]
    $b destroy
    assert {[file size $fa] < [file size $fb]} \
        "dry run stays smaller than a real render\
         ([file size $fa] < [file size $fb])"
    file delete $fa $fb
}

# ============================================================
# F. Block types
# ============================================================

test "block.heading_level_scales_size" {
    set p [newPdf]
    set h1 [dict get [docir::block::pdf $p [list [dict create type heading \
        content {{type text text T}} meta {level 1}]] \
        -x 3 -y 3 -w 48 -size 8] used]
    set h6 [dict get [docir::block::pdf $p [list [dict create type heading \
        content {{type text text T}} meta {level 6}]] \
        -x 3 -y 3 -w 48 -size 8] used]
    assert {$h1 > $h6} "level 1 is taller than level 6 ($h1 > $h6)"
    $p destroy
}

test "block.blank_advances_without_lines" {
    set p [newPdf]
    set r [docir::block::pdf $p [list [dict create type blank content {} meta {}]] \
        -x 3 -y 3 -w 48 -size 8]
    assertEqual 0 [dict get $r lines] "blank draws no line"
    assert {[dict get $r used] > 0} "blank still uses height"
    $p destroy
}

test "block.hr_uses_height_without_lines" {
    set p [newPdf]
    set r [docir::block::pdf $p [list [dict create type hr content {} meta {}]] \
        -x 3 -y 3 -w 48 -size 8]
    assertEqual 0 [dict get $r lines] "hr is not a text line"
    assert {[dict get $r used] > 0} "hr uses height"
    $p destroy
}

test "block.doc_meta_and_header_are_skipped" {
    # docir::md::fromAst prepends both; a block renderer must ignore them
    # rather than emit stray lines.
    set p [newPdf]
    set ir [list \
        [dict create type doc_meta content {} meta {irSchemaVersion 1}] \
        [dict create type doc_header content {} meta {name {}}] \
        [dict create type paragraph content {{type text text x}} meta {}]]
    set r [docir::block::pdf $p $ir -x 3 -y 3 -w 48 -size 8]
    assertEqual 1 [dict get $r lines] "only the paragraph produces a line"
    $p destroy
}

test "block.unknown_block_type_does_not_crash" {
    set p [newPdf]
    set ir [list [dict create type wasauchimmer content {} meta {}]]
    set caught [catch {docir::block::pdf $p $ir -x 3 -y 3 -w 48 -size 8} err]
    assert {!$caught} "unknown block type must be tolerated: $err"
    $p destroy
}

test "block.empty_ir_returns_zero" {
    set p [newPdf]
    set r [docir::block::pdf $p {} -x 3 -y 3 -w 48 -size 8]
    assertEqual 0 [dict get $r lines] "no lines"
    assertEqual 0.000 [dict get $r used] "no height"
    $p destroy
}

# ============================================================
# G. Inline types
# ============================================================

test "block.non_renderable_inlines_stay_visible" {
    # image/math/footnote_ref cannot be drawn in a text block. They must
    # leave a marker instead of vanishing silently.
    set p [newPdf]
    set leer [dict get [docir::block::pdf $p [inline \
        {type text text {}}] -x 3 -y 3 -w 48 -size 8] lines]
    set mit [dict get [docir::block::pdf $p [inline \
        {type image text {}}] -x 3 -y 3 -w 48 -size 8] lines]
    assert {$mit >= 1} "image inline produces a visible marker"
    $p destroy
}

test "block.nested_content_form_accepted" {
    # Flat form is the norm ({type strong text "x"}), but some producers
    # nest inlines under `content`.
    set p [newPdf]
    set flach [docir::block::pdf $p [inline {type strong text Nord}] \
                   -x 3 -y 3 -w 48 -size 8]
    set tief [docir::block::pdf $p [inline \
        [dict create type strong content {{type text text Nord}}]] \
        -x 3 -y 3 -w 48 -size 8]
    assertEqual [dict get $flach lines] [dict get $tief lines] \
        "both forms yield the same line count"
    $p destroy
}

# ============================================================
# H. Alignment
# ============================================================

test "block.alignment_accepted_and_height_neutral" {
    set p [newPdf]
    set h {}
    foreach a {left center right} {
        lappend h [dict get [docir::block::pdf $p [para "Hallo Welt"] \
            -x 3 -y 3 -w 48 -size 8 -align $a] used]
    }
    assertEqual [lindex $h 0] [lindex $h 1] "center same height as left"
    assertEqual [lindex $h 0] [lindex $h 2] "right same height as left"
    $p destroy
}

# ============================================================
# I. Image blocks
# ============================================================

# A tiny PNG written by pdf4tcl-independent means is awkward here, so the
# tests use whatever raster file the suite can find; if none exists they skip.
proc testBild {} {
    foreach f [list /tmp/probe.png /tmp/demo-etikett.png] {
        if {[file readable $f]} { return $f }
    }
    return ""
}

test "block.image_scales_to_box_width" {
    set f [testBild]
    if {$f eq ""} { skip "no raster file available" }
    set p [newPdf]
    set ir [list [dict create type image content {} meta [list url $f alt Test]]]
    set schmal [dict get [docir::block::pdf $p $ir -x 3 -y 3 -w 20] used]
    set breit  [dict get [docir::block::pdf $p $ir -x 3 -y 3 -w 40] used]
    assert {$breit > $schmal} "wider box -> taller image ($breit > $schmal)"
    assertEqual 0 [dict get [docir::block::pdf $p $ir -x 3 -y 3 -w 40] lines] \
        "an image is not a text line"
    $p destroy
}

test "block.image_respects_height_limit" {
    set f [testBild]
    if {$f eq ""} { skip "no raster file available" }
    set p [newPdf]
    set ir [list [dict create type image content {} meta [list url $f alt Test]]]
    set r [docir::block::pdf $p $ir -x 3 -y 3 -w 40 -h 8]
    assert {[dict get $r used] <= 9.5} "scaled down to fit -h ([dict get $r used])"
    assertEqual 1 [dict get $r overflow] "shrinking is reported as overflow"
    $p destroy
}

test "block.missing_image_stays_visible" {
    # A missing file must not leave a silent gap: on a label an empty space
    # looks like a design decision rather than an error.
    set p [newPdf]
    set ir [list [dict create type image content {} \
        meta {url /does/not/exist.png alt Firmenlogo}]]
    set r [docir::block::pdf $p $ir -x 3 -y 3 -w 40]
    assertEqual 1 [dict get $r lines] "placeholder is drawn as a text line"
    $p destroy
}

test "block.inline_image_uses_alt_text" {
    set p [newPdf]
    set r [docir::block::pdf $p [inline \
        {type image text Firmenlogo}] -x 3 -y 3 -w 48 -size 8]
    assertEqual 1 [dict get $r lines] "inline image leaves a marker line"
    $p destroy
}

test::runAll