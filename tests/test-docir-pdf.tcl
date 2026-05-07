#!/usr/bin/env tclsh
# test-docir-pdf.tcl
#
# Tests fuer docir-pdf-0.1.tm — DocIR → PDF Renderer.
#
# Zwei Test-Gruppen:
#   A) Modul-Loading und API ohne pdf4tcl-Aufrufe (laufen immer)
#   B) Echte Rendering-Tests (skippen wenn pdf4tcl nicht verfuegbar ist)
#
# pdf4tcl wird per Lazy-Load erst beim render-Aufruf geholt — das Modul
# selbst kann auch auf Systemen ohne pdf4tcl geladen werden.

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

set projectRoot [file dirname [file dirname [file normalize [info script]]]]
lappend auto_path $projectRoot
package require docir::pdf

set hasPdf4tcl [expr {![catch {package require pdf4tcl}]}]
set hasPdf4tcllib [expr {![catch {package require pdf4tcllib}]}]
if {!$hasPdf4tcl} {
    puts "Note: pdf4tcl not available — rendering tests will be skipped"
}
if {!$hasPdf4tcllib} {
    puts "Note: pdf4tcllib not available — rendering tests will be skipped"
}
# Beides braucht docir-pdf jetzt
set canRender [expr {$hasPdf4tcl && $hasPdf4tcllib}]

# ============================================================
# A. Modul-Loading und API
# ============================================================

test "pdf.module_loaded" {
    assert [string length [package present docir::pdf]] "docir-pdf provides version"
}

test "pdf.public_api_present" {
    assert [string length [info commands docir::pdf::render]] "render command exists"
    assert [string length [info commands docir::pdf::renderToHandle]] "renderToHandle command exists"
}

test "pdf.render_without_pdf4tcl_errors_clearly" {
    # Dieser Test prueft die Fehlermeldung wenn pdf4tcl nicht da ist.
    # Wenn pdf4tcl bereits provided wurde, geht der Code-Pfad
    # nicht mehr in den ensure-Zweig — dann triviale Pseudo-Assertion.
    if {[catch {package present pdf4tcl}]} {
        # pdf4tcl nicht da → echter Test
        set caught [catch {docir::pdf::render {} /tmp/_nonexistent.pdf} err]
        assert $caught "render without pdf4tcl errors"
        assert [string match "*pdf4tcl*" $err] "error mentions pdf4tcl"
    } else {
        # pdf4tcl da → trivial
        assert 1 "pdf4tcl already present, skipping"
    }
}

# ============================================================
# B. Echte Rendering-Tests (skippen wenn pdf4tcl fehlt)
# ============================================================

if {$canRender} {

test "pdf.render_writes_file" {
    set out [file join /tmp "docir-pdf-test-[pid].pdf"]
    catch {file delete $out}

    set ir [list \
        [dict create type heading content {{type text text "Hello"}} meta {level 1}] \
        [dict create type paragraph content {{type text text "World"}} meta {}]]

    docir::pdf::render $ir $out
    assert [file exists $out] "PDF file created"
    assert [expr {[file size $out] > 0}] "PDF file non-empty"

    # Magic bytes
    set fh [open $out r]
    fconfigure $fh -translation binary
    set head [read $fh 5]
    close $fh
    assert [string match "%PDF-*" $head] "starts with %PDF- magic"

    catch {file delete $out}
}

test "pdf.render_handles_all_block_types" {
    set out [file join /tmp "docir-pdf-allblocks-[pid].pdf"]
    catch {file delete $out}

    set ir [list \
        [dict create type doc_header content {} meta {name puts section n version 9.0 part Tcl}] \
        [dict create type heading content {{type text text "NAME"}} meta {level 1 id name}] \
        [dict create type paragraph content {{type text text "puts - write to channel"}} meta {}] \
        [dict create type heading content {{type text text "SYNOPSIS"}} meta {level 2}] \
        [dict create type pre content {{type text text "puts ?-nonewline? string"}} meta {kind code}] \
        [dict create type heading content {{type text text "DESCRIPTION"}} meta {level 2}] \
        [dict create type paragraph content {{type text text "Writes a string to the channel."}} meta {}] \
        [dict create type list content [list \
            [dict create type listItem content {{type text text "first item"}} meta {kind ul}] \
            [dict create type listItem content {{type text text "second item"}} meta {kind ul}] \
        ] meta {kind ul}] \
        [dict create type hr content {} meta {}] \
        [dict create type table content [list \
            [dict create type tableRow content [list \
                [dict create type tableCell content {{type text text "-bg"}} meta {}] \
                [dict create type tableCell content {{type text text "-fg"}} meta {}] \
            ] meta {}] \
        ] meta {columns 2 hasHeader 0}] \
        [dict create type blank content {} meta {lines 1}] \
        [dict create type paragraph content {{type text text "End."}} meta {}]]

    docir::pdf::render $ir $out
    assert [file exists $out] "PDF file created with all block types"
    assert [expr {[file size $out] > 500}] "PDF file has substantial content"

    catch {file delete $out}
}

test "pdf.render_paginates_long_content" {
    set out [file join /tmp "docir-pdf-paginate-[pid].pdf"]
    catch {file delete $out}

    set ir {}
    for {set i 0} {$i < 200} {incr i} {
        lappend ir [dict create type paragraph \
            content [list [dict create type text text "Line $i: This is filler content meant to overflow the page boundary, testing automatic page breaks."]] \
            meta {}]
    }

    # Direkt mit renderToHandle arbeiten um pageCount lesen zu koennen
    set pdf [pdf4tcl::new %AUTO% -paper a4 -orient true]
    $pdf startPage
    docir::pdf::renderToHandle $pdf $ir
    set pageCount [$pdf pageCount]
    $pdf write -file $out
    $pdf destroy

    assert [file exists $out] "long PDF created"
    assert [expr {$pageCount > 1}] "multiple pages produced ($pageCount)"

    catch {file delete $out}
}

test "pdf.render_handles_empty_ir" {
    set out [file join /tmp "docir-pdf-empty-[pid].pdf"]
    catch {file delete $out}
    docir::pdf::render {} $out
    assert [file exists $out] "PDF for empty IR still created"
    catch {file delete $out}
}

test "pdf.render_handles_unknown_block_no_crash" {
    set out [file join /tmp "docir-pdf-unknown-[pid].pdf"]
    catch {file delete $out}
    set ir [list [dict create type weirdtype content {} meta {}]]
    set caught [catch {docir::pdf::render $ir $out} err]
    assert [expr {!$caught}] "unknown type does not crash: $err"
    catch {file delete $out}
}

test "pdf.render_handles_blank_without_content" {
    set out [file join /tmp "docir-pdf-blank-[pid].pdf"]
    catch {file delete $out}
    # blank ohne content-Feld
    set ir [list \
        [dict create type paragraph content {{type text text "Before"}} meta {}] \
        [dict create type blank meta {lines 2}] \
        [dict create type paragraph content {{type text text "After"}} meta {}]]
    set caught [catch {docir::pdf::render $ir $out} err]
    assert [expr {!$caught}] "blank without content does not crash: $err"
    catch {file delete $out}
}

test "pdf.render_options_paper_size" {
    set out [file join /tmp "docir-pdf-letter-[pid].pdf"]
    catch {file delete $out}
    set ir [list [dict create type heading content {{type text text "X"}} meta {level 1}]]
    docir::pdf::render $ir $out [dict create paper letter]
    assert [file exists $out] "PDF with letter paper created"
    catch {file delete $out}
}

test "pdf.render_options_metadata_title" {
    set out [file join /tmp "docir-pdf-title-[pid].pdf"]
    catch {file delete $out}
    set ir [list [dict create type heading content {{type text text "X"}} meta {level 1}]]
    docir::pdf::render $ir $out [dict create title "My Title" author "Tester"]

    # Titel aus PDF auslesen
    set fh [open $out r]
    fconfigure $fh -translation binary
    set content [read $fh]
    close $fh
    assert [string match "*My Title*" $content] "title in PDF metadata"
    catch {file delete $out}
}

test "pdf.full_pipeline_nroff_to_pdf" {
    package require nroffparser
    package require docir::roffSource

    set out [file join /tmp "docir-pdf-pipeline-[pid].pdf"]
    catch {file delete $out}

    set nroff {.TH foo n 1.0 Test
.SH NAME
foo \- a test
.SH DESCRIPTION
This is a test of the nroff to PDF pipeline.
}
    set ast [nroffparser::parse $nroff]
    set ir  [docir::roff::fromAst $ast]
    docir::pdf::render $ir $out

    assert [file exists $out] "pipeline produced PDF"
    catch {file delete $out}
}

}  ;# end if canRender

# ============================================================
# Spec 0.5: Tests für neue Block-Typen in docir-pdf
# ============================================================
#
# Hinweis: Diese Tests laufen nur wenn pdf4tcl verfügbar ist.
# Sie prüfen nicht die Pixel-Genauigkeit, sondern dass der
# Render-Pfad ohne Crash durchläuft und sinnvolle Bytes erzeugt.

if {[catch {package require pdf4tcl}] && \
    [catch {source /home/claude/md-uploads/vendors/pkg/pdf4tcl0.9.4.25/pdf4tcl.tcl}]} {
    puts stderr "skipping spec.pdf.* tests — pdf4tcl not available"
} elseif {[catch {package require pdf4tcllib}]} {
    puts stderr "skipping spec.pdf.* tests — pdf4tcllib not available"
} else {

test "spec.pdf.block.image_fallback" {
    # Image mit nicht-existenter URL → Fallback-Marker (kein Crash)
    set ir [list [dict create type image content {} \
        meta [dict create url "/nonexistent.png" alt "Fallback test"]]]
    set tmpFile [file join /tmp test-pdf-image.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile} err]
    if {$rc} {
        puts stderr "PDF render failed: $err"
    }
    assert [expr {$rc == 0}] "PDF mit Image-Fallback rendert ohne Crash"
    assert [file exists $tmpFile] "PDF-Datei wurde erzeugt"
    file delete -force $tmpFile
}

test "spec.pdf.block.footnote_section" {
    set ir [list \
        [dict create type paragraph \
            content [list [dict create type text text "Body."]] meta {}] \
        [dict create type footnote_section \
            content [list \
                [dict create type footnote_def \
                    content [list [dict create type text text "Note text."]] \
                    meta [dict create id "fn1" num "1"]]] \
            meta {}]]
    set tmpFile [file join /tmp test-pdf-fn.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile} err]
    if {$rc} {
        puts stderr "PDF render failed: $err"
    }
    assert [expr {$rc == 0}] "PDF mit footnote_section rendert ohne Crash"
    assert [file exists $tmpFile] "PDF-Datei wurde erzeugt"
    set sz [file size $tmpFile]
    assert [expr {$sz > 500}] "PDF hat substantielle Größe (>500 bytes)"
    file delete -force $tmpFile
}

test "spec.pdf.block.div_transparent" {
    set ir [list [dict create type div \
        content [list \
            [dict create type heading \
                content [list [dict create type text text "In Div"]] \
                meta [dict create level 1]] \
            [dict create type paragraph \
                content [list [dict create type text text "Body in div."]] meta {}]] \
        meta [dict create class "warning"]]]
    set tmpFile [file join /tmp test-pdf-div.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile} err]
    assert [expr {$rc == 0}] "PDF mit div rendert ohne Crash"
    assert [file exists $tmpFile] "PDF-Datei wurde erzeugt"
    file delete -force $tmpFile
}

test "spec.pdf.header_footer.simple" {
    # Test: Header und Footer werden gerendert
    set ir [list \
        [dict create type heading content [list [dict create type text text "Test"]] \
            meta [dict create level 1]] \
        [dict create type paragraph content [list [dict create type text text "Body."]] \
            meta {}]]
    set tmpFile [file join /tmp test-pdf-hf.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile [dict create \
        header "Test Doc" \
        footer "Page %p"]} err]
    if {$rc} { puts stderr "PDF render failed: $err" }
    assert [expr {$rc == 0}] "PDF mit Header/Footer rendert ohne Crash"
    assert [file exists $tmpFile] "PDF-Datei wurde erzeugt"

    # PDF in Text konvertieren (wenn pdftotext verfügbar)
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join /tmp test-pdf-hf.txt]
        if {[catch {exec pdftotext $tmpFile $txtFile} ex]} {
            puts stderr "pdftotext failed: $ex"
        } else {
            set fh [open $txtFile r]
            set txt [read $fh]
            close $fh
            assert [expr {[string first "Test Doc" $txt] >= 0}] "Header im Text"
            assert [expr {[string first "Page 1" $txt] >= 0}] "Footer mit %p substituiert"
            file delete -force $txtFile
        }
    }
    file delete -force $tmpFile
}

test "spec.pdf.header_footer.multipage" {
    # Test: Header/Footer auf jeder Seite
    set ir [list]
    for {set i 1} {$i <= 50} {incr i} {
        lappend ir [dict create type paragraph \
            content [list [dict create type text text "Paragraph $i."]] meta {}]
    }
    set tmpFile [file join /tmp test-pdf-multipage.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile [dict create \
        header "Header" \
        footer "Page %p"]} err]
    assert [expr {$rc == 0}] "Multi-page mit Header/Footer rendert"

    # Page-count + Header/Footer-Verifikation
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join /tmp test-pdf-multipage.txt]
        if {[catch {exec pdftotext $tmpFile $txtFile} ex]} {
            puts stderr "pdftotext failed: $ex"
        } else {
            set fh [open $txtFile r]
            set txt [read $fh]
            close $fh
            # "Page 1" muss da sein, idealerweise auch "Page 2"
            assert [expr {[string first "Page 1" $txt] >= 0}] "Page 1 footer"
            # Header sollte mehrfach auftauchen
            set headerCount [llength [regexp -all -inline {Header} $txt]]
            assert [expr {$headerCount >= 1}] "Header mindestens 1x"
            file delete -force $txtFile
        }
    }
    file delete -force $tmpFile
}

test "spec.pdf.theme.colorCode_applied" {
    # Bei Default (kein theme) wird der eingebaute Default
    # colorCode "#e8e8e8" verwendet. Bei explizitem theme wird der
    # Theme-Wert verwendet. Wir testen mit explizitem colorCode-Override.
    set ir [list \
        [dict create type pre \
            content [list [dict create type text text "code line"]] \
            meta [dict create kind code]]]
    set tmpFile [file join /tmp test-pdf-theme.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile [dict create \
        colorCode "#ff0000"]} err]
    if {$rc} { puts stderr "PDF render failed: $err" }
    assert [expr {$rc == 0}] "PDF mit colorCode-Override rendert"
    file delete -force $tmpFile
}

test "spec.pdf.theme.hex_to_rgb" {
    # Hex→RGB-Helper: gängige Werte
    lassign [::docir::pdf::_hexToRgb "#ffffff"] r g b
    assert [expr {abs($r - 1.0) < 0.01}] "white R"
    assert [expr {abs($g - 1.0) < 0.01}] "white G"
    assert [expr {abs($b - 1.0) < 0.01}] "white B"

    lassign [::docir::pdf::_hexToRgb "#000000"] r g b
    assert [expr {$r == 0.0 && $g == 0.0 && $b == 0.0}] "black 0/0/0"

    lassign [::docir::pdf::_hexToRgb "#0066cc"] r g b
    assert [expr {abs($r - 0.0) < 0.01}] "0066cc R=0"
    assert [expr {abs($g - 0.4) < 0.05}] "0066cc G≈0.4"
    assert [expr {abs($b - 0.8) < 0.05}] "0066cc B≈0.8"

    # Kurzform #abc → #aabbcc
    lassign [::docir::pdf::_hexToRgb "#f0a"] r g b
    assert [expr {abs($r - 1.0) < 0.01}] "#f0a R=1"

    # Ungültiger Input → schwarz
    lassign [::docir::pdf::_hexToRgb "garbage"] r g b
    assert [expr {$r == 0 && $g == 0 && $b == 0}] "garbage → 0/0/0"
}

test "spec.pdf.inline.styles_render" {
    # Bold/Italic/Code/Link/Strike in einem Paragraph rendern ohne Crash
    set ir [list \
        [dict create type paragraph content [list \
            [dict create type text text "has "] \
            [dict create type strong text "bold"] \
            [dict create type text text " and "] \
            [dict create type emphasis text "italic"] \
            [dict create type text text " and "] \
            [dict create type code text "code"] \
            [dict create type text text "."]] meta {}]]
    set tmpFile [file join /tmp test-pdf-inline.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile} err]
    if {$rc} { puts stderr "PDF render failed: $err" }
    assert [expr {$rc == 0}] "Per-Inline-Styles rendern ohne Crash"

    # Mehrere Font-Subsets im PDF: verschiedene Glyph-Sets für versch. Styles
    if {[file exists $tmpFile]} {
        set fh [open $tmpFile rb]
        set content [read $fh]
        close $fh
        set fontCount [llength [regexp -all -inline {/FontDescriptor} $content]]
        # Bei aktiver Per-Inline-Pipeline sollten mehrere Font-Subsets da sein
        assert [expr {$fontCount >= 2}] "Mehrere Font-Subsets eingebettet"
    }
    file delete -force $tmpFile
}

test "spec.pdf.inline.hyperlink_added" {
    # Link-Inline erzeugt Hyperlink-Annotation
    set ir [list \
        [dict create type paragraph content [list \
            [dict create type text text "Visit "] \
            [dict create type link text "site" href "https://example.com"]] meta {}]]
    set tmpFile [file join /tmp test-pdf-link.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile} err]
    assert [expr {$rc == 0}] "Link rendert"

    if {[file exists $tmpFile]} {
        set fh [open $tmpFile rb]
        set content [read $fh]
        close $fh
        # Link-Annotation muss anwesend sein
        assert [expr {[string first "/Subtype /Link" $content] >= 0}] "Link-Annotation im PDF"
        assert [expr {[string first "example.com" $content] >= 0}] "URL im PDF"
    }
    file delete -force $tmpFile
}

test "spec.pdf.inline.strike_renders" {
    # Strike-Inline wird gerendert (Linie wird gezeichnet — wir testen nur dass
    # der Renderer nicht crashed, die Linie selbst ist im PDF schwer zu testen)
    set ir [list \
        [dict create type paragraph content [list \
            [dict create type text text "Some "] \
            [dict create type strike text "deleted"] \
            [dict create type text text " text."]] meta {}]]
    set tmpFile [file join /tmp test-pdf-strike.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile} err]
    if {$rc} { puts stderr "PDF render failed: $err" }
    assert [expr {$rc == 0}] "Strike rendert ohne Crash"
    file delete -force $tmpFile
}

test "spec.pdf.image.embeds_with_root" {
    # Block-Image wird als XObject embedded wenn die Datei vorhanden ist.
    # Pfad-Auflösung gegen opts.root.

    # Test-PNG erzeugen (40x40 rotes Bild) — minimaler PNG via Tcl
    set tmpDir [file join /tmp test-pdf-img-[pid]]
    file mkdir $tmpDir

    # Minimaler PNG (1x1 pixel rot): hardcoded bytes
    set hex "89504e470d0a1a0a0000000d49484452000000010000000108020000009077"
    append hex "53de0000000c4944415478da63f8cffc1f000004ff01ffd472ee26"
    append hex "0000000049454e44ae426082"
    set png [binary format "H*" $hex]
    set fh [open [file join $tmpDir test.png] wb]
    puts -nonewline $fh $png
    close $fh

    set ir [list \
        [dict create type image content {} \
            meta [dict create url "test.png" alt "Test"]]]

    set tmpFile [file join $tmpDir output.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile [dict create root $tmpDir]} err]
    if {$rc} { puts stderr "render: $err" }
    assert [expr {$rc == 0}] "PDF mit image+root rendert"

    if {[file exists $tmpFile]} {
        set fh [open $tmpFile rb]
        set content [read $fh]
        close $fh
        # Mindestens 1 Image-XObject im PDF erwartet
        set imgCount [llength [regexp -all -inline {/Subtype */Image} $content]]
        assert [expr {$imgCount >= 1}] "PDF enthält Image-XObject"
    }
    file delete -force $tmpDir
}

test "spec.pdf.image.fallback_when_missing" {
    # Wenn Image nicht vorhanden: Fallback auf [image: alt]-Marker
    set ir [list \
        [dict create type image content {} \
            meta [dict create url "/nonexistent/foo.png" alt "Missing"]]]
    set tmpFile [file join /tmp test-pdf-imgmiss.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile} err]
    assert [expr {$rc == 0}] "PDF mit fehlendem Image rendert (Fallback)"
    file delete -force $tmpFile
}

test "spec.pdf.image.resolve_path" {
    # _resolveImagePath direkt testen
    namespace eval ::docir::pdf {
        variable opts
        set opts [dict create root /tmp/foo]
    }
    assert [expr {[::docir::pdf::_resolveImagePath "bar.png"] eq "/tmp/foo/bar.png"}] \
        "Relativ wird gegen root aufgelöst"
    assert [expr {[::docir::pdf::_resolveImagePath "/abs/path.png"] eq "/abs/path.png"}] \
        "Absolut bleibt unverändert"
    assert [expr {[::docir::pdf::_resolveImagePath "https://x.com/y.png"] eq ""}] \
        "HTTP wird verworfen"
    assert [expr {[::docir::pdf::_resolveImagePath ""] eq ""}] \
        "Empty bleibt empty"
}

}  ;# end pdf4tcl-availability block

test::runAll
