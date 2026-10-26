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

# Seit 23.10.2026: 57 (indexEntries, Link in andere PDF-Datei,
# lebender Kolumnentitel, Synopsis zeilenweise, Leerzeichen vor "?").
# Seit 24.10.2026: 60 (Kopf mit Fettteil, Metadaten, fehlendes Bild).
# Seit 19.10.2026: 49 (vier Tests fuer interne Links).
# Soll-Zahl, gemessen am 27.09.2026 mit pdf4tcl UND pdf4tcllib im
# Geschwisterbaum: 45 angemeldete Tests. Ohne pdf4tcllib sind es 3 -- der
# Block ab "if {[catch {package require pdf4tcl}]}" faellt dann weg und
# nimmt 42 Tests mit, ohne dass der Zaehler etwas davon sieht.
# Seit 26.10.2026: 64 (Definitionen mit Bloecken, Kopf am Seitenrand,
# Alias-Anker einer Ueberschrift).
::test::expect 64

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

# Temp-Dir plattform-unabhaengig via docir::util
package require docir::util
set ::TMPBASE [docir::util::tmpdir]

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
        set caught [catch {docir::pdf::render {} [file join $::TMPBASE _nonexistent.pdf]} err]
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
    set out [file join $::TMPBASE "docir-pdf-test-[pid].pdf"]
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
    set out [file join $::TMPBASE "docir-pdf-allblocks-[pid].pdf"]
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
    set out [file join $::TMPBASE "docir-pdf-paginate-[pid].pdf"]
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
    set out [file join $::TMPBASE "docir-pdf-empty-[pid].pdf"]
    catch {file delete $out}
    docir::pdf::render {} $out
    assert [file exists $out] "PDF for empty IR still created"
    catch {file delete $out}
}

test "pdf.render_handles_unknown_block_no_crash" {
    set out [file join $::TMPBASE "docir-pdf-unknown-[pid].pdf"]
    catch {file delete $out}
    set ir [list [dict create type weirdtype content {} meta {}]]
    set caught [catch {docir::pdf::render $ir $out} err]
    assert [expr {!$caught}] "unknown type does not crash: $err"
    catch {file delete $out}
}

test "pdf.render_handles_blank_without_content" {
    set out [file join $::TMPBASE "docir-pdf-blank-[pid].pdf"]
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
    set out [file join $::TMPBASE "docir-pdf-letter-[pid].pdf"]
    catch {file delete $out}
    set ir [list [dict create type heading content {{type text text "X"}} meta {level 1}]]
    docir::pdf::render $ir $out [dict create paper letter]
    assert [file exists $out] "PDF with letter paper created"
    catch {file delete $out}
}

test "pdf.render_options_metadata_title" {
    set out [file join $::TMPBASE "docir-pdf-title-[pid].pdf"]
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
    if {[catch {package require nroffparser}]} { skip "nroffparser (man-viewer) not installed" }
    package require nroffparser
    package require docir::roffSource

    set out [file join $::TMPBASE "docir-pdf-pipeline-[pid].pdf"]
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

# Siehe test-docir-md.tcl: kein fester Ausweichpfad, repos-path.tcl macht das.
if {[catch {package require pdf4tcl}]} {
    puts stderr "skipping spec.pdf.* tests — pdf4tcl not available"
} elseif {[catch {package require pdf4tcllib}]} {
    puts stderr "skipping spec.pdf.* tests — pdf4tcllib not available"
} else {

test "spec.pdf.block.image_fallback" {
    # Image mit nicht-existenter URL → Fallback-Marker (kein Crash)
    set ir [list [dict create type image content {} \
        meta [dict create url "/nonexistent.png" alt "Fallback test"]]]
    set tmpFile [file join $::TMPBASE test-pdf-image.pdf]
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
    set tmpFile [file join $::TMPBASE test-pdf-fn.pdf]
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

test "spec.pdf.block.footnote_emoji_no_crash" {
    # Regression: a footnote definition containing a non-encodable character
    # (emoji / astral codepoint) must be sanitised like every other text path,
    # not passed raw to pdf4tcl (which would abort with
    # "key ... not known in dictionary"). The index path carries the same fix.
    set ir [list \
        [dict create type paragraph \
            content [list [dict create type text text "Body with a note."]] meta {}] \
        [dict create type footnote_section \
            content [list \
                [dict create type footnote_def \
                    content [list [dict create type text \
                        text "Note with \U0001F525 fire and \u2728 sparkles."]] \
                    meta [dict create id "fn1" num "1"]]] \
            meta {}]]
    set tmpFile [file join $::TMPBASE test-pdf-fn-emoji.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile} err]
    if {$rc} {
        puts stderr "PDF render failed: $err"
    }
    assert [expr {$rc == 0}] "footnote with emoji renders without crash"
    assert [file exists $tmpFile] "PDF-Datei wurde erzeugt"
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
    set tmpFile [file join $::TMPBASE test-pdf-div.pdf]
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
    set tmpFile [file join $::TMPBASE test-pdf-hf.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile [dict create \
        header "Test Doc" \
        footer "Page %p"]} err]
    if {$rc} { puts stderr "PDF render failed: $err" }
    assert [expr {$rc == 0}] "PDF mit Header/Footer rendert ohne Crash"
    assert [file exists $tmpFile] "PDF-Datei wurde erzeugt"

    # PDF in Text konvertieren (wenn pdftotext verfügbar)
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join $::TMPBASE test-pdf-hf.txt]
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
    set tmpFile [file join $::TMPBASE test-pdf-multipage.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile [dict create \
        header "Header" \
        footer "Page %p"]} err]
    assert [expr {$rc == 0}] "Multi-page mit Header/Footer rendert"

    # Page-count + Header/Footer-Verifikation
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join $::TMPBASE test-pdf-multipage.txt]
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
    set tmpFile [file join $::TMPBASE test-pdf-theme.pdf]
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
    set tmpFile [file join $::TMPBASE test-pdf-inline.pdf]
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
    set tmpFile [file join $::TMPBASE test-pdf-link.pdf]
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
    set tmpFile [file join $::TMPBASE test-pdf-strike.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile} err]
    if {$rc} { puts stderr "PDF render failed: $err" }
    assert [expr {$rc == 0}] "Strike rendert ohne Crash"
    file delete -force $tmpFile
}

test "spec.pdf.image.embeds_with_root" {
    # Block-Image wird als XObject embedded wenn die Datei vorhanden ist.
    # Pfad-Auflösung gegen opts.root.

    # Test-PNG erzeugen (40x40 rotes Bild) — minimaler PNG via Tcl
    set tmpDir [file join $::TMPBASE test-pdf-img-[pid]]
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
    set tmpFile [file join $::TMPBASE test-pdf-imgmiss.pdf]
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

# ============================================================
# TOC mit Seitenzahlen (generateToc, Zwei-Pass)
# ============================================================
#
# render() rendert bei -generateToc 1 das Dokument iterativ, bis die
# Heading-Seiten stabil sind, und stellt ein Inhaltsverzeichnis mit
# rechtsbuendigen Seitenzahlen voran. Diese Tests pruefen:
#   - generateToc fuegt eine TOC-Seite mit Titel + Eintraegen hinzu,
#   - tocTitle ist anpassbar,
#   - die angezeigte Seitenzahl entspricht der echten Body-Seite,
#   - tocDepth begrenzt die gelisteten Level,
#   - ohne generateToc gibt es kein TOC (unveraenderter Pfad).

test "spec.pdf.toc.disabled_by_default" {
    set ir [list \
        [dict create type heading content {{type text text "OnlyChapter"}} meta {level 1}] \
        [dict create type paragraph content {{type text text "Body."}} meta {}]]
    set out [file join $::TMPBASE "docir-toc-off-[pid].pdf"]
    catch {file delete $out}
    ::docir::pdf::render $ir $out {}
    assert [file exists $out] "PDF without TOC created"
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join $::TMPBASE "docir-toc-off-[pid].txt"]
        exec pdftotext $out $txtFile
        set fh [open $txtFile r]; fconfigure $fh -encoding utf-8
        set txt [read $fh]; close $fh
        file delete -force $txtFile
        assert [expr {[string first "Inhaltsverzeichnis" $txt] < 0}] \
            "no TOC title when generateToc is off"
    }
    catch {file delete $out}
}

test "spec.pdf.toc.page_added_with_title" {
    set ir [list \
        [dict create type heading content {{type text text "IntroChapter"}} meta {level 1}] \
        [dict create type paragraph content {{type text text "Body."}} meta {}]]
    set out [file join $::TMPBASE "docir-toc-on-[pid].pdf"]
    catch {file delete $out}
    ::docir::pdf::render $ir $out [dict create generateToc 1 tocTitle "Inhaltsverzeichnis"]
    assert [file exists $out] "PDF with TOC created"
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join $::TMPBASE "docir-toc-on-[pid].txt"]
        exec pdftotext $out $txtFile
        set fh [open $txtFile r]; fconfigure $fh -encoding utf-8
        set txt [read $fh]; close $fh
        file delete -force $txtFile
        assert [expr {[string first "Inhaltsverzeichnis" $txt] >= 0}] "TOC title present"
        assert [expr {[string first "IntroChapter" $txt] >= 0}] "heading listed in TOC"
    }
    catch {file delete $out}
}

test "spec.pdf.toc.custom_title" {
    set ir [list [dict create type heading content {{type text text "X"}} meta {level 1}]]
    set out [file join $::TMPBASE "docir-toc-ct-[pid].pdf"]
    catch {file delete $out}
    ::docir::pdf::render $ir $out [dict create generateToc 1 tocTitle "Table of Contents"]
    assert [file exists $out] "PDF created"
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join $::TMPBASE "docir-toc-ct-[pid].txt"]
        exec pdftotext $out $txtFile
        set fh [open $txtFile r]; fconfigure $fh -encoding utf-8
        set txt [read $fh]; close $fh
        file delete -force $txtFile
        assert [expr {[string first "Table of Contents" $txt] >= 0}] "tocTitle is customisable"
    }
    catch {file delete $out}
}

test "spec.pdf.toc.page_numbers_match_body" {
    # Core check: the page number shown in the TOC equals the page on which
    # the heading actually appears in the body (two-pass convergence).
    set ir {}
    foreach title {AlphaUniqueChap BetaUniqueChap GammaUniqueChap} {
        lappend ir [dict create type heading \
            content [list [dict create type text text $title]] meta {level 1}]
        for {set i 0} {$i < 45} {incr i} {
            lappend ir [dict create type paragraph \
                content [list [dict create type text text "Filler $i for $title to push pages."]] \
                meta {}]
        }
    }
    set out [file join $::TMPBASE "docir-toc-pn-[pid].pdf"]
    catch {file delete $out}
    ::docir::pdf::render $ir $out [dict create generateToc 1 tocDepth 1]
    assert [file exists $out] "TOC PDF created"

    if {[auto_execok pdftotext] eq ""} { skip "pdftotext not available" }
    set txtFile [file join $::TMPBASE "docir-toc-pn-[pid].txt"]
    exec pdftotext -layout $out $txtFile
    set fh [open $txtFile r]; fconfigure $fh -encoding utf-8
    set txt [read $fh]; close $fh
    file delete -force $txtFile

    # pdftotext separates pages with a form-feed (0x0C).
    set pages [split $txt \x0C]

    # TOC page number for the last chapter (guaranteed > 1). Take the last
    # integer on the TOC line carrying the title (robust against spacing).
    set tocNum ""
    foreach line [split [lindex $pages 0] \n] {
        if {[string first GammaUniqueChap $line] >= 0} {
            set nums [regexp -all -inline {\d+} $line]
            if {[llength $nums] > 0} { set tocNum [lindex $nums end] }
        }
    }
    assert [expr {[string is integer -strict $tocNum]}] "TOC shows a page number ($tocNum)"

    # Actual body page: first page after the TOC whose text carries the title.
    set bodyPage 0
    for {set i 1} {$i < [llength $pages]} {incr i} {
        if {[string first GammaUniqueChap [lindex $pages $i]] >= 0} {
            set bodyPage [expr {$i + 1}]
            break
        }
    }
    assert [expr {$bodyPage > 0}] "chapter found in body (page $bodyPage)"
    assertEqual $bodyPage $tocNum "TOC page number matches the real body page"
    catch {file delete $out}
}

test "spec.pdf.toc.depth_limits_levels" {
    # tocDepth 1 -> only level-1 headings appear in the TOC.
    set ir [list \
        [dict create type heading content {{type text text "TopLevelChap"}} meta {level 1}] \
        [dict create type heading content {{type text text "SubLevelSec"}}  meta {level 2}] \
        [dict create type paragraph content {{type text text "Body."}} meta {}]]
    set out [file join $::TMPBASE "docir-toc-depth-[pid].pdf"]
    catch {file delete $out}
    ::docir::pdf::render $ir $out [dict create generateToc 1 tocDepth 1]
    assert [file exists $out] "PDF created"
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join $::TMPBASE "docir-toc-depth-[pid].txt"]
        exec pdftotext $out $txtFile
        set fh [open $txtFile r]; fconfigure $fh -encoding utf-8
        set txt [read $fh]; close $fh
        file delete -force $txtFile
        set tocPage [lindex [split $txt \x0C] 0]
        assert [expr {[string first "TopLevelChap" $tocPage] >= 0}] "level-1 listed in TOC"
        assert [expr {[string first "SubLevelSec" $tocPage] < 0}] \
            "level-2 omitted from TOC at tocDepth 1"
    }
    catch {file delete $out}
}

# ============================================================
# Sachindex aus [Begriff]{.index}-Markierungen (generateIndex)
# ============================================================
#
# Ein span mit class "index" markiert einen Index-Begriff. Der Begriff
# bleibt im Fliesstext sichtbar und wird mit der Seite, auf der er
# tatsaechlich gerendert wird, in den Sachindex aufgenommen. Mehrere
# Vorkommen eines Begriffs ergeben mehrere Seiten. Diese Tests bauen die
# IR direkt (unabhaengig vom Markdown-Parser).

# Helper: Paragraph mit einem Index-Span bauen.
proc _idxPara {pre term post} {
    return [dict create type paragraph content [list \
        [dict create type text text $pre] \
        [dict create type span text $term class index] \
        [dict create type text text $post]] meta {}]
}

test "spec.pdf.index.collects_marked_terms" {
    set ir [list \
        [dict create type heading content {{type text text "Chap"}} meta {level 1}] \
        [_idxPara "About " "Coroutine" " here."]]
    set out [file join $::TMPBASE "docir-idx-collect-[pid].pdf"]
    catch {file delete $out}
    ::docir::pdf::render $ir $out [dict create generateIndex 1 indexTitle "Stichwortverzeichnis"]
    assert [file exists $out] "index PDF created"
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join $::TMPBASE "docir-idx-collect-[pid].txt"]
        exec pdftotext $out $txtFile
        set fh [open $txtFile r]; fconfigure $fh -encoding utf-8
        set txt [read $fh]; close $fh
        file delete -force $txtFile
        assert [expr {[string first "Stichwortverzeichnis" $txt] >= 0}] "index section present"
        assert [expr {[string first "Coroutine" $txt] >= 0}] "marked term listed in index"
    }
    catch {file delete $out}
}

# A multi-word index term split by the parser at a source-text line break
# arrives as several consecutive index spans (term / "" / term). They must
# coalesce into a single index entry (_coalesceIndexSpans), not be recorded
# as separate terms under different initial letters.
test "spec.pdf.index.multiword_coalesced" {
    set ir [list \
        [dict create type heading content {{type text text "Chap"}} meta {level 1}] \
        [dict create type paragraph content [list \
            [dict create type text text "The "] \
            [dict create type span text "intermediate" class index] \
            [dict create type span text "" class index] \
            [dict create type span text "representation" class index] \
            [dict create type text text " is flat."]] meta {}]]
    set out [file join $::TMPBASE "docir-idx-coalesce-[pid].pdf"]
    catch {file delete $out}
    ::docir::pdf::render $ir $out [dict create generateIndex 1 indexTitle "Stichwortverzeichnis"]
    assert [file exists $out] "index PDF created"
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join $::TMPBASE "docir-idx-coalesce-[pid].txt"]
        exec pdftotext -layout $out $txtFile
        set fh [open $txtFile r]; fconfigure $fh -encoding utf-8
        set txt [read $fh]; close $fh
        file delete -force $txtFile
        # Check only the index section (after its heading), so the body's
        # own "intermediate representation" does not mask a split entry.
        set ipos [string first "Stichwortverzeichnis" $txt]
        assert [expr {$ipos >= 0}] "index section present"
        set idxSection [string range $txt $ipos end]
        assert [expr {[string first "intermediate representation" $idxSection] >= 0}] \
            "multi-word term coalesced into one index entry"
    }
    catch {file delete $out}
}

test "spec.pdf.titlepage.rendered_as_first_page" {
    # titlePage 1 puts title + author on a dedicated first page, separate
    # from the body. Without it, the title is only PDF metadata, not text.
    set ir [list \
        [dict create type heading content {{type text text "Body Chapter"}} meta {level 1}] \
        [dict create type paragraph content {{type text text "Body text."}} meta {}]]
    set out [file join $::TMPBASE "docir-tp-[pid].pdf"]
    catch {file delete $out}
    ::docir::pdf::render $ir $out [dict create \
        title "My Title Page Book" author "An Author" \
        subtitle "A Subtitle" titlePage 1 footer "%p"]
    assert [file exists $out] "title page PDF created"
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join $::TMPBASE "docir-tp-[pid].txt"]
        exec pdftotext -layout $out $txtFile
        set fh [open $txtFile r]; fconfigure $fh -encoding utf-8
        set txt [read $fh]; close $fh
        file delete -force $txtFile
        set page1 [lindex [split $txt \x0C] 0]
        assert [expr {[string first "My Title Page Book" $page1] >= 0}] \
            "title appears on the first page"
        assert [expr {[string first "An Author" $page1] >= 0}] \
            "author appears on the title page"
        assert [expr {[string first "Body Chapter" $page1] < 0}] \
            "body is on a later page, not the title page"
    }
    catch {file delete $out}
}

test "spec.pdf.index.none_without_markers" {
    # Keine .index-Marker und keine indexLevel-Headings -> keine Index-Seite.
    set ir [list \
        [dict create type heading content {{type text text "Chap"}} meta {level 1}] \
        [dict create type paragraph content {{type text text "Plain body."}} meta {}]]
    set out [file join $::TMPBASE "docir-idx-none-[pid].pdf"]
    catch {file delete $out}
    ::docir::pdf::render $ir $out [dict create generateIndex 1 indexTitle "Stichwortverzeichnis"]
    assert [file exists $out] "PDF created"
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join $::TMPBASE "docir-idx-none-[pid].txt"]
        exec pdftotext $out $txtFile
        set fh [open $txtFile r]; fconfigure $fh -encoding utf-8
        set txt [read $fh]; close $fh
        file delete -force $txtFile
        assert [expr {[string first "Stichwortverzeichnis" $txt] < 0}] \
            "no index section when nothing is marked"
    }
    catch {file delete $out}
}

test "spec.pdf.index.page_matches_body" {
    # Begriff-Seite im Index == Seite, auf der der Begriff im Body steht.
    set ir [list [dict create type heading content {{type text text "Start"}} meta {level 1}]]
    for {set i 0} {$i < 55} {incr i} {
        lappend ir [dict create type paragraph \
            content [list [dict create type text text "Filler $i pushing the term down."]] meta {}]
    }
    lappend ir [_idxPara "Topic " "Singletonpattern" " explained."]
    set out [file join $::TMPBASE "docir-idx-page-[pid].pdf"]
    catch {file delete $out}
    ::docir::pdf::render $ir $out [dict create generateIndex 1 indexTitle "Stichwortverzeichnis"]
    assert [file exists $out] "index PDF created"

    if {[auto_execok pdftotext] eq ""} { skip "pdftotext not available" }
    set txtFile [file join $::TMPBASE "docir-idx-page-[pid].txt"]
    exec pdftotext -layout $out $txtFile
    set fh [open $txtFile r]; fconfigure $fh -encoding utf-8
    set txt [read $fh]; close $fh
    file delete -force $txtFile

    set pages [split $txt \x0C]
    # Index-Zahl fuer den Begriff
    set idxNum ""
    foreach line [split $txt \n] {
        if {[string first "Singletonpattern" $line] >= 0} {
            set nums [regexp -all -inline {\d+} $line]
            if {[llength $nums] > 0} { set idxNum [lindex $nums end] }
        }
    }
    assert [expr {[string is integer -strict $idxNum]}] "index shows a page number ($idxNum)"
    # Echte Body-Seite (Vorkommen ausserhalb der Index-Seite)
    set bodyPage 0
    for {set i 0} {$i < [llength $pages]} {incr i} {
        set p [lindex $pages $i]
        if {[string first "Singletonpattern" $p] >= 0 && [string first "Stichwortverzeichnis" $p] < 0} {
            set bodyPage [expr {$i + 1}]
            break
        }
    }
    assert [expr {$bodyPage > 0}] "term found in body (page $bodyPage)"
    assertEqual $bodyPage $idxNum "index page matches the real body page"
    catch {file delete $out}
}

test "spec.pdf.index.multiple_occurrences" {
    # Derselbe Begriff zweimal -> zwei Seiten im selben Eintrag.
    set ir [list [dict create type heading content {{type text text "A"}} meta {level 1}]]
    lappend ir [_idxPara "First " "Repeatedterm" " mention."]
    for {set i 0} {$i < 55} {incr i} {
        lappend ir [dict create type paragraph \
            content [list [dict create type text text "Spacer $i."]] meta {}]
    }
    lappend ir [_idxPara "Second " "Repeatedterm" " mention."]
    set out [file join $::TMPBASE "docir-idx-multi-[pid].pdf"]
    catch {file delete $out}
    ::docir::pdf::render $ir $out [dict create generateIndex 1 indexTitle "Stichwortverzeichnis"]
    assert [file exists $out] "index PDF created"
    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join $::TMPBASE "docir-idx-multi-[pid].txt"]
        exec pdftotext -layout $out $txtFile
        set fh [open $txtFile r]; fconfigure $fh -encoding utf-8
        set txt [read $fh]; close $fh
        file delete -force $txtFile
        set idxLine ""
        foreach line [split $txt \n] {
            if {[string first "Repeatedterm" $line] >= 0} { set idxLine $line }
        }
        set nums [regexp -all -inline {\d+} $idxLine]
        assert [expr {[llength $nums] >= 2}] "two pages listed for repeated term ($nums)"
    }
    catch {file delete $out}
}

# ============================================================
# Inline math ($...$) -- since docir::pdf 0.4
# ============================================================

test "spec.pdf.math.segment_is_atomic" {
    # An inline math node becomes a segment of its own: style "math", the raw
    # LaTeX as text, no $ delimiters -- pdf4tcllib::math draws it.
    set inlines [list \
        [dict create type text text "Formel "] \
        [dict create type math text "E = mc^2" display 0] \
        [dict create type text text " im Satz."]]
    set segs [::docir::pdf::_inlinesToSegments $inlines normal]
    set mathSegs {}
    foreach seg $segs {
        if {[lindex $seg 1] eq "math"} { lappend mathSegs $seg }
    }
    assertEqual 1 [llength $mathSegs] "genau ein math-Segment"
    assertEqual "E = mc^2" [lindex [lindex $mathSegs 0] 0] "raw LaTeX, keine \$-Delimiter"
}

test "spec.pdf.math.display_inline_stays_text" {
    # Display math inside an inline run keeps the old monospace form.
    set inlines [list [dict create type math text "a+b" display 1]]
    set segs [::docir::pdf::_inlinesToSegments $inlines normal]
    assertEqual "code" [lindex [lindex $segs 0] 1] "display math bleibt code-Segment"
}

if {$canRender} {

test "spec.pdf.math.metrics_and_fit" {
    # measureLatex through the docir helper: a formula has a width, and the
    # fit guard rejects a tall one in a fixed line box but allows it where the
    # line can grow.
    set tmpFile [file join $::TMPBASE test-pdf-math-metrics.pdf]
    set pdf [::pdf4tcl::new %AUTO% -paper a4 -file $tmpFile]
    ::docir::pdf::_initState $pdf

    set flat [::docir::pdf::_mathMetrics "E = mc^2" 11]
    assertEqual 3 [llength $flat] "Metrik ist {w h d}"
    assert [expr {[lindex $flat 0] > 0}] "Formel hat Breite"
    assert [::docir::pdf::_mathFitsLine $flat 11 0] "flache Formel passt in die feste Zeile"

    set frac [::docir::pdf::_mathMetrics "\\frac{a}{b}" 11]
    assert [expr {![::docir::pdf::_mathFitsLine $frac 11 0]}] \
        "Bruch passt NICHT in die feste Zeile (Heading)"
    assert [::docir::pdf::_mathFitsLine $frac 11 1] \
        "Bruch passt, wenn die Zeile wachsen darf (Absatz)"

    set bogus [::docir::pdf::_mathMetrics "" 11]
    assert [expr {![::docir::pdf::_mathFitsLine $bogus 11 1]}] "leere Formel faellt zurueck"

    $pdf destroy
    catch {file delete $tmpFile}
}

test "spec.pdf.math.line_box_grows" {
    # A line carrying a fraction gets more room than an ordinary line.
    set tmpFile [file join $::TMPBASE test-pdf-math-box.pdf]
    set pdf [::pdf4tcl::new %AUTO% -paper a4 -file $tmpFile]
    ::docir::pdf::_initState $pdf

    lassign [::docir::pdf::_lineMathBox [list [list "Text" normal "" ""]] 11] a1 b1
    lassign [::docir::pdf::_lineMathBox [list [list "\\frac{a}{b}" math "" ""]] 11] a2 b2
    assert [expr {$a2 >= $a1 && $b2 > $b1}] "Bruch-Zeile ist hoeher als eine Textzeile"

    $pdf destroy
    catch {file delete $tmpFile}
}

test "spec.pdf.math.rendered_not_raw" {
    # End to end: the $ delimiters must not survive into the PDF text.
    set ir [list [dict create type paragraph meta {} content [list \
        [dict create type text text "Die Formel "] \
        [dict create type math text "E = mc^2" display 0] \
        [dict create type text text " steht im Satz."]]]]
    set tmpFile [file join $::TMPBASE test-pdf-math.pdf]
    set rc [catch {::docir::pdf::render $ir $tmpFile} err]
    if {$rc} { puts stderr "PDF render failed: $err" }
    assert [expr {$rc == 0}] "PDF mit Inline-Math rendert ohne Crash"
    assert [file exists $tmpFile] "PDF-Datei wurde erzeugt"

    if {[auto_execok pdftotext] ne ""} {
        set txtFile [file join $::TMPBASE test-pdf-math.txt]
        if {![catch {exec pdftotext $tmpFile $txtFile}]} {
            set fh [open $txtFile r]
            set txt [read $fh]
            close $fh
            assert [expr {[string first "Die Formel" $txt] >= 0}] "Text drumherum steht da"
            assert [expr {[string first "\$" $txt] < 0}] \
                "keine \$-Delimiter mehr im PDF-Text (Formel ist gesetzt)"
            assert [expr {[string first "mc" $txt] >= 0}] "Formelinhalt ist da"
            catch {file delete $txtFile}
        }
    }
    catch {file delete $tmpFile}
}

}  ;# end canRender block for math

# ============================================================
# Code blocks: wrapping (since docir::pdf 0.5)
# ============================================================

if {$canRender} {

test "spec.pdf.code.long_line_wraps" {
    # A long command used to be drawn as-is and ran out of the grey box and off
    # the right edge of the page ("no wrap -- the author formatted it").
    set tmpFile [file join $::TMPBASE test-pdf-codewrap.pdf]
    set pdf [::pdf4tcl::new %AUTO% -paper a4 -file $tmpFile]
    ::docir::pdf::_initState $pdf
    ::docir::pdf::_setFont 11 mono

    set long "TCLKIT=tclkit-Linux64-arm ./Build-Linux.sh arm 64 Setup/Tcl_Basic.bawt update --rootdir /tmp/build"
    set wrapped [::docir::pdf::_wrapCodeLines [list $long] 300]
    assert [expr {[llength $wrapped] > 1}] "lange Zeile wird umgebrochen"
    foreach l $wrapped {
        assert [expr {[$pdf getStringWidth $l] <= 300}] "keine Zeile ist breiter als die Box"
    }
    assert [expr {[string range [lindex $wrapped 1] 0 3] eq "    "}] \
        "Folgezeile hat haengenden Einzug"

    $pdf destroy
    catch {file delete $tmpFile}
}

test "spec.pdf.code.short_line_untouched" {
    set tmpFile [file join $::TMPBASE test-pdf-codewrap2.pdf]
    set pdf [::pdf4tcl::new %AUTO% -paper a4 -file $tmpFile]
    ::docir::pdf::_initState $pdf
    ::docir::pdf::_setFont 11 mono
    set r [::docir::pdf::_wrapCodeLines [list "make install"] 300]
    $pdf destroy
    catch {file delete $tmpFile}
    assertEqual [list "make install"] $r "kurze Zeile bleibt unveraendert"
}

test "spec.pdf.code.unbreakable_token_hard_break" {
    # A single token longer than the box must still be broken -- the
    # alternative is running off the page.
    set tmpFile [file join $::TMPBASE test-pdf-codewrap3.pdf]
    set pdf [::pdf4tcl::new %AUTO% -paper a4 -file $tmpFile]
    ::docir::pdf::_initState $pdf
    ::docir::pdf::_setFont 11 mono
    set token [string repeat "x" 200]
    set wrapped [::docir::pdf::_wrapCodeLines [list $token] 200]
    $pdf destroy
    catch {file delete $tmpFile}
    assert [expr {[llength $wrapped] > 1}] "ein zu langes Token wird hart gebrochen"
}

}  ;# end canRender block for code wrap


# ============================================================
# Interne Links: TOC-Eintraege und "#id"-Verweise (19.10.2026)
# ============================================================
#
# Vorher: TOC ohne Links, "#id" als URI-Link (/S /URI /URI (#id)) -- ein
# Klick fuehrte ins Leere. Jetzt: jede Ueberschrift ein benanntes Ziel
# (h-N und ihre id), Links per pdf4tcl linkAdd.

if {$canRender && [llength [info commands ::pdf4tcl::pdf4tcl]] && \
        "linkAdd" in [info class methods ::pdf4tcl::pdf4tcl -all]} {

proc ::_linkIr {} {
    return [list \
        [dict create type heading content [list [dict create type text text "Erstes Kapitel"]] \
            meta [dict create level 1 id erstes-kapitel]] \
        [dict create type paragraph content [list \
            [dict create type text text "Siehe "] \
            [dict create type link text "zweites" href "#zweites-kapitel"] \
            [dict create type text text " und "] \
            [dict create type link text "Web" href "https://example.com"]] meta {}] \
        [dict create type heading content [list [dict create type text text "Zweites Kapitel"]] \
            meta [dict create level 1 id zweites-kapitel]] \
        [dict create type paragraph content [list [dict create type text text "Text."]] meta {}]]
}

proc ::_pdfRaw {file} {
    set fh [open $file rb]; set d [read $fh]; close $fh; return $d
}

test "pdf.links.toc_entries_link_to_headings" {
    set f [file join $::TMPBASE test-pdf-toclinks.pdf]
    docir::pdf::render [::_linkIr] $f [dict create generateToc 1 compress 0]
    set d [::_pdfRaw $f]
    assert [regexp {/Dest /h-0\M} $d] "TOC-Eintrag 1 verlinkt"
    assert [regexp {/Dest /h-1\M} $d] "TOC-Eintrag 2 verlinkt"
    assert [regexp {/Dests <<} $d] "Katalog hat /Dests"
    catch {file delete $f}
}

test "pdf.links.hash_href_is_internal" {
    set f [file join $::TMPBASE test-pdf-hashlink.pdf]
    docir::pdf::render [::_linkIr] $f [dict create compress 0]
    set d [::_pdfRaw $f]
    assert [regexp {/Dest /zweites-kapitel} $d] "#id wird interner Sprung"
    assert [expr {![regexp {/URI \(#} $d]}] "kein URI-Link auf #id"
    assert [regexp {/URI \(https://example.com\)} $d] "Web-Link bleibt URI"
}

test "pdf.links.off_with_internalLinks_0" {
    set f [file join $::TMPBASE test-pdf-nolinks.pdf]
    docir::pdf::render [::_linkIr] $f [dict create generateToc 1 internalLinks 0 compress 0]
    set d [::_pdfRaw $f]
    assert [expr {![regexp {/Dests} $d]}] "keine Ziele"
    assert [expr {![regexp {/Dest /} $d]}] "keine internen Links"
    catch {file delete $f}
}

test "pdf.links.index_pages_link_to_marker" {
    # Jede Seitenzahl im Stichwortverzeichnis springt an die Fundstelle.
    set ir [list \
        [dict create type heading content [list [dict create type text text "Kapitel"]] \
            meta [dict create level 1 id kapitel]] \
        [dict create type paragraph content [list \
            [dict create type text text "Ein "] \
            [dict create type span class index text "Begriff"] \
            [dict create type text text " im Text."]] meta {}]]
    set f [file join $::TMPBASE test-pdf-indexlinks.pdf]
    docir::pdf::render $ir $f [dict create generateIndex 1]
    set d [::_pdfRaw $f]
    assert [regexp {/Dest /ix-0\M} $d] "Seitenzahl im Index verlinkt"
    assert [regexp {/ix-0 \[\d+ 0 R /XYZ} $d] "Ziel an der Fundstelle definiert"
    catch {file delete $f}
}

}  ;# end linkAdd block

# indexEntries: das Stichwortverzeichnis des letzten Laufs, mit den
# gedruckten Seiten (2026-10-23, fuer bookkit index-gesamt.tcl)
if {$canRender} {
test "pdf.index.entries_after_render" {
    set ir [list \
        [dict create type heading content [list [dict create type text text "Kapitel"]] \
            meta [dict create level 1 id kapitel]] \
        [dict create type paragraph content [list \
            [dict create type span class index text "Zeta"] \
            [dict create type text text " und "] \
            [dict create type span class index text "Alpha"] \
            [dict create type text text " und noch einmal "] \
            [dict create type span class index text "Alpha"]] meta {}]]
    set f [file join $::TMPBASE test-pdf-indexentries.pdf]
    docir::pdf::render $ir $f [dict create generateIndex 1]
    set e [docir::pdf::indexEntries]
    assert [expr {[llength $e] == 2}] "zwei Begriffe: $e"
    assert [expr {[lindex $e 0 0] eq "Alpha" && [lindex $e 1 0] eq "Zeta"}] "sortiert: $e"
    assert [expr {[lindex $e 0 1] eq "1"}] "Alpha einmal, Seite 1: $e"
    catch {file delete $f}
}
}

# Lebender Kolumnentitel (2026-10-23): %c in der Kopfzeile ist die erste
# Ueberschrift der Ebene runningLevel, die auf der Seite beginnt, sonst die
# laufende; runningProc liefert Texte von lang nach kurz, der erste, der
# passt, gilt.
if {$canRender} {
proc ::_runIr {} {
    set ir {}
    foreach kap {A B} n {70 70} {
        lappend ir [dict create type heading content [list [dict create type text text "Kap$kap"]] \
            meta [dict create level 1 id kap$kap]]
        for {set i 0} {$i < $n} {incr i} {
            lappend ir [dict create type paragraph content [list [dict create type text text "Zeile $i von $kap."]] meta {}]
        }
    }
    return $ir
}
proc ::_runText {title level} {
    if {$title eq "KapA"} { return [list [string repeat "SEHRLANG-" 40] RUN-A] }
    if {$title eq "KapB"} { return [list RUN-B] }
    return [list $title]
}
proc ::_pageHeads {f} {
    # erste Zeile jeder Seite (pdftotext); {} ohne pdftotext
    if {[auto_execok pdftotext] eq "" || [catch {exec pdfinfo $f} info]} { return {} }
    regexp {Pages:\s+(\d+)} $info -> n
    set out {}
    for {set p 1} {$p <= $n} {incr p} {
        set t [exec pdftotext -enc UTF-8 -layout -f $p -l $p $f -]
        lappend out [string trim [lindex [split [string trim $t] \n] 0]]
    }
    return $out
}
test "pdf.header.running_title_dictionary_rule" {
    set f [file join $::TMPBASE test-pdf-running.pdf]
    docir::pdf::render [::_runIr] $f [dict create title Handbuch \
        header "%t\t%c" footer "%p" runningProc ::_runText]
    set heads [::_pageHeads $f]
    if {![llength $heads]} {
        puts "  (pdftotext fehlt, nur Lauf geprueft)"
        assert [file exists $f] "PDF erzeugt"
    } else {
        set kinds [lmap h $heads {
            expr {[string match "Handbuch*RUN-A" $h] ? "A" : [string match "Handbuch*RUN-B" $h] ? "B" : "?$h"}
        }]
        assert [expr {"?" ni [lmap k $kinds {string index $k 0}]}] "jede Seite: Titel links, A oder B rechts: $kinds"
        assert [expr {[lindex $kinds 0] eq "A" && [lindex $kinds end] eq "B"}] "erst A, zuletzt B: $kinds"
        set firstB [lsearch $kinds B]
        assert [expr {[lsearch -start $firstB $kinds A] < 0}] "nach dem ersten B kein A mehr: $kinds"
        assert [expr {![string match *SEHRLANG* $heads]}] "zu langer Text nicht genommen"
    }
    catch {file delete $f}
}
test "pdf.header.without_running_unchanged" {
    set f [file join $::TMPBASE test-pdf-noheader.pdf]
    docir::pdf::render [::_runIr] $f [dict create header "Seite %p"]
    set heads [::_pageHeads $f]
    if {[llength $heads]} {
        assert [expr {[lindex $heads 0] eq "Seite 1" && [lindex $heads 1] eq "Seite 2"}] "einfache Kopfzeile wie bisher: [lrange $heads 0 1]"
    } else {
        assert [file exists $f] "PDF erzeugt"
    }
    catch {file delete $f}
}
}

# Link auf eine andere PDF-Datei: GoToR (pdf4tcl fileLinkAdd, 0.9.4.73)
if {$canRender && [llength [info commands ::pdf4tcl::pdf4tcl]] && \
        "fileLinkAdd" in [info class methods ::pdf4tcl::pdf4tcl -all]} {
test "pdf.links.relative_pdf_is_gotor" {
    set ir [list [dict create type paragraph content [list \
        [dict create type link text "S. 12" href "tcllib.pdf#page=12"] \
        [dict create type text text " "] \
        [dict create type link text "Datei" href "other%20file.pdf"] \
        [dict create type text text " "] \
        [dict create type link text "Web" href "https://example.com/a.pdf"]] meta {}]]
    set f [file join $::TMPBASE test-pdf-gotor.pdf]
    docir::pdf::render $ir $f [dict create compress 0]
    set d [::_pdfRaw $f]
    assert [regexp {/S /GoToR /F \(tcllib\.pdf\)\s+/D \[11 /Fit\]} $d] "Datei und Seite 12"
    assert [regexp {/S /GoToR /F \(other file\.pdf\)\s+/D \[0 /Fit\]} $d] "ohne Seite: Seite 1, %20 dekodiert"
    assert [regexp {/URI \(https://example.com/a.pdf\)} $d] "mit Schema bleibt URI"
    catch {file delete $f}
}
} else {
    puts "Note: pdf4tcl without fileLinkAdd -- GoToR test skipped"
}

# Codeblock laenger als eine Seite (2026-10-22, Tablelist-Anleitung S. 50):
# wird auf mehrere Seiten verteilt, keine Zeile geht verloren.
test "pdf.pre.longer_than_page_is_split" {
    set code {}
    for {set i 1} {$i <= 150} {incr i} { lappend code "zeile$i" }
    set ir [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type paragraph content [list [dict create type text text "Vorher."]] meta {}] \
        [dict create type pre content [list [dict create type text text [join $code \n]]] meta {kind code}]]
    set f [file join $::TMPBASE test-pdf-longpre.pdf]
    docir::pdf::render $ir $f [dict create compress 0]
    set d [::_pdfRaw $f]
    set pages [regexp -all {/Type\s*/Page\M} $d]
    assert {$pages >= 3} "150 Zeilen brauchen mindestens 3 Seiten, sind $pages"
    catch {file delete $f}
}

# TIP-700-Synopsis (2026-10-23): eine Zeile je Aufrufform, Klassen
# cmd/sub/lit fett, arg/ins kursiv, optarg/optlit/optdot in ?...?.
proc ::_sp {cls text} { dict create type span class $cls text $text }
proc ::_tx {text} { dict create type text text $text }
proc ::_sb {} { dict create type softbreak }
proc ::_synIr {} {
    list [dict create type paragraph meta {} content [list \
        [::_sp cmd after] [::_tx " "] [::_sp arg ms] [::_tx " "] [::_sp optdot "script script"] [::_sb] \
        [::_sp cmd after] [::_tx " "] [::_sp sub info] [::_tx " "] [::_sp optarg id] [::_sb] \
        [::_sp cmd binary] [::_tx " "] [::_sp sub decode] [::_tx " "] [::_sp optlit -strict] [::_tx " "] [::_sp arg data]]]
}
test "pdf.synopsis.softbreaks_become_linebreaks" {
    set out [docir::pdf::_synopsisLines [dict get [lindex [::_synIr] 0] content]]
    set types [lmap i $out {dict get $i type}]
    assert [expr {"softbreak" ni $types}] "keine softbreaks mehr: $types"
    assert [expr {[llength [lsearch -all $types linebreak]] == 2}] "zwei Zeilenumbrueche: $types"
}
test "pdf.synopsis.other_paragraphs_untouched" {
    foreach c [list \
        [list [::_tx "Ein Satz"] [::_sb] [::_tx "weiter."]] \
        [list [::_sp arg x] [::_sb] [::_sp cmd y]] \
        [list [::_sp cmd after] [::_tx " "] [::_sp arg ms]] \
        [list [::_sp cmd after] [::_tx " wartet"] [::_sb] [::_sp cmd y]] \
        [list [::_sp cmd after] [::_sb] [dict create type strong text x]]] {
        assert [expr {[docir::pdf::_synopsisLines $c] eq $c}] "unveraendert: $c"
    }
}
if {$canRender} {
proc ::_pdfLines {f} {
    if {[auto_execok pdftotext] eq ""} { return {} }
    set t [exec pdftotext -enc UTF-8 -layout $f -]
    return [lmap l [split $t \n] {string trim $l}]
}
test "pdf.synopsis.one_line_per_form" {
    set f [file join $::TMPBASE test-pdf-synopsis.pdf]
    docir::pdf::render [::_synIr] $f {}
    set lines [::_pdfLines $f]
    if {![llength $lines]} {
        assert [file exists $f] "PDF erzeugt"
    } else {
        foreach want {"after ms ?script script ...?" "after info ?id?" "binary decode ?-strict? data"} {
            assert [expr {$want in $lines}] "Zeile '$want' in: $lines"
        }
    }
    catch {file delete $f}
}
test "pdf.text.explicit_space_before_question_mark_kept" {
    # Begriff einer Beschreibungsliste: **after** *ms* ?*script ...*?
    set ir [list [dict create type paragraph meta {} content [list \
        [dict create type strong text after] [::_tx " "] [dict create type emphasis text ms] \
        [::_tx " ?"] [dict create type emphasis text "script ..."] [::_tx "?, und "] \
        [dict create type strong text weiter] [::_tx ", fertig ."]]]]
    set f [file join $::TMPBASE test-pdf-qmark.pdf]
    docir::pdf::render $ir $f {}
    set lines [::_pdfLines $f]
    if {![llength $lines]} {
        assert [file exists $f] "PDF erzeugt"
    } else {
        assert [expr {"after ms ?script ...?, und weiter, fertig." in $lines}] "Abstaende: $lines"
    }
    catch {file delete $f}
}
}

# Review 2026-10-24: Kopfzeile mit fettem Teil, Metadaten, laute Fehler.
if {$canRender} {
proc ::_boldRun {title level} { return [list "pfad / **$title**"] }
test "pdf.header.bold_part_without_asterisks" {
    set f [file join $::TMPBASE test-pdf-hdrbold.pdf]
    docir::pdf::render [::_runIr] $f [dict create title Hb compress 0 \
        header "%t\t%c" footer "%p" runningProc ::_boldRun]
    set heads [::_pageHeads $f]
    if {[llength $heads]} {
        assert [string match "Hb*pfad / KapA" [lindex $heads 0]] "Kopf ohne Sternchen: [lindex $heads 0]"
    }
    assert [expr {[llength [docir::pdf::_hdrSegs "a / **b** c"]] == 3}] "drei Teile"
    assert [expr {[lindex [docir::pdf::_hdrSegs "a / **b**"] 1] eq {b 1}}] "b fett"
    catch {file delete $f}
}
test "pdf.meta.subject_creator_date_lang" {
    set f [file join $::TMPBASE test-pdf-meta.pdf]
    docir::pdf::render [::_runIr] $f [dict create title T subject "Ref pages" \
        lang en-GB compress 0]
    set d [::_pdfRaw $f]
    assert [regexp {/Subject \(Ref pages\)} $d] "Subject"
    assert [regexp {/Creator \(docir::pdf\)} $d] "Creator Vorgabe"
    assert [regexp {/CreationDate \(D:} $d] "Erstelldatum"
    set p [pdf4tcl::new %AUTO%]
    set hasLang [expr {![catch {$p metadata -lang de}]}]
    $p destroy
    if {$hasLang} {
        assert [regexp {/Lang \(en-GB\)} $d] "Sprache im Katalog"
    } else {
        puts "  (pdf4tcl ohne metadata -lang, /Lang nicht geprueft)"
    }
    catch {file delete $f}
}
test "pdf.image.missing_warns" {
    catch {unset ::docir::pdf::_warnedKeys(img:gibtsnicht.png)}
    set ir [list [dict create type image content {} \
        meta [dict create url gibtsnicht.png alt Weg]]]
    set f [file join $::TMPBASE test-pdf-noimg.pdf]
    docir::pdf::render $ir $f {}
    assert [info exists ::docir::pdf::_warnedKeys(img:gibtsnicht.png)] "Warnung fuer fehlendes Bild"
    catch {file delete $f}
}
}
test "pdf.inline.space_before_colon_and_dot_words" {
    # "::http::geturl" und ".top" sind Woerter, kein Satzzeichen: das
    # Leerzeichen davor bleibt. "," und ":" allein haengen am Wort davor.
    if {[auto_execok pdftotext] eq ""} return
    set ir [list [dict create type paragraph meta {} content [list \
        [dict create type text text "Die Prozedur "] \
        [dict create type strong text "::http::geturl"] \
        [dict create type text text " und das Fenster "] \
        [dict create type strong text ".top"] \
        [dict create type text text ", Ende: ja."]]]]
    set f [file join $::TMPBASE test-pdf-colonword.pdf]
    docir::pdf::render $ir $f {}
    set t [exec pdftotext $f -]
    assert [string match "*Prozedur ::http::geturl*" $t] "Leerzeichen vor ::http: $t"
    assert [string match "*Fenster .top, Ende: ja.*" $t] "Leerzeichen vor .top, kein Leerzeichen vor , und :"
    catch {file delete $f}
}

test "pdf.text.number_like_words_unchanged" {
    # Words that look like numbers stay as written: an expr ternary in
    # _wrap turned the TOC entry "5.10" into "5.1" (and "010" into 8/10).
    if {[auto_execok pdftotext] eq ""} return
    set ir [list \
        [dict create type heading meta {level 1} content [list \
            [dict create type text text "5.10  Pages"]]] \
        [dict create type paragraph meta {} content [list \
            [dict create type text text "010 1e3 0x1F 4.80"]]] \
        [dict create type pre meta {kind code} content [list \
            [dict create type text text "010\n1.50"]]]]
    set f [file join $::TMPBASE test-pdf-numwords.pdf]
    docir::pdf::render $ir $f [dict create generateToc 1 title 1.50 \
        footer "%t %p"]
    set t [exec pdftotext $f -]
    assert {[regexp -all {5\.10  ?Pages} $t] >= 2} "TOC and heading keep 5.10: $t"
    assert [string match "*010 1e3 0x1F 4.80*" $t] "paragraph words unchanged"
    assert [regexp {(^|\n)010\n1\.50} $t] "code lines unchanged"
    assert [string match "*1.50 *" $t] "footer title unchanged"
    catch {file delete $f}
}

# Definitions with blocks (listItem.blocks, mdSource 0.2 / TIP 700):
# every block under the term, at the indent of the description; inner
# definition lists step in further. Before 0.6 only the first paragraph
# was printed and further paragraphs were lost.
proc ::_dlBlocksIr {} {
    set inner [dict create type list meta {kind dl indentLevel 0} content [list \
        [dict create type listItem meta [dict create kind dl \
            term [list [dict create type text text "InnerTermQ"]]] \
            content [list [dict create type text text "InnerDefQ text."]]]]]
    set ul [dict create type list meta {kind ul indentLevel 0} content [list \
        [dict create type listItem meta {kind ul term {}} \
            content [list [dict create type text text "BulletOneQ"]]]]]
    set item [dict create type listItem \
        meta [dict create kind dl term [list [dict create type text text "OuterTermQ"]]] \
        content [list [dict create type text text "FLAT CONTENT NOT SHOWN"]] \
        blocks [list \
            [dict create type paragraph meta {} content [list [dict create type text text "FirstParaQ."]]] \
            [dict create type paragraph meta {} content [list [dict create type text text "SecondParaQ."]]] \
            $ul \
            [dict create type pre meta {kind code language ""} content [list [dict create type text text "codeLineQ 1"]]] \
            $inner]]
    return [list [dict create type list meta {kind dl indentLevel 0} content [list $item]] \
        [dict create type paragraph meta {} content [list [dict create type text text "AfterListQ"]]]]
}
proc ::_layoutCol {txt word} {
    foreach line [split $txt \n] {
        set c [string first $word $line]
        if {$c >= 0} { return $c }
    }
    return -1
}

test "pdf.dl.blocks_all_rendered" {
    if {[auto_execok pdftotext] eq ""} { skip "pdftotext not available" }
    set f [file join $::TMPBASE test-pdf-dlblocks.pdf]
    docir::pdf::render [::_dlBlocksIr] $f
    set t [exec pdftotext -layout $f -]
    foreach w {OuterTermQ FirstParaQ SecondParaQ BulletOneQ codeLineQ InnerTermQ InnerDefQ AfterListQ} {
        assert [expr {[string first $w $t] >= 0}] "$w printed"
    }
    assert [expr {[string first "FLAT CONTENT" $t] < 0}] "blocks, not the flat content"
    set order [lmap w {OuterTermQ FirstParaQ SecondParaQ BulletOneQ codeLineQ InnerTermQ InnerDefQ AfterListQ} {string first $w $t}]
    assert [expr {$order eq [lsort -integer $order]}] "in order: $order"
    catch {file delete $f}
}

test "pdf.dl.blocks_indented" {
    if {[auto_execok pdftotext] eq ""} { skip "pdftotext not available" }
    set f [file join $::TMPBASE test-pdf-dlblocks2.pdf]
    docir::pdf::render [::_dlBlocksIr] $f
    set t [exec pdftotext -layout $f -]
    set cT  [::_layoutCol $t OuterTermQ]
    set cP  [::_layoutCol $t SecondParaQ]
    set cIT [::_layoutCol $t InnerTermQ]
    set cID [::_layoutCol $t InnerDefQ]
    set cA  [::_layoutCol $t AfterListQ]
    assert [expr {$cP > $cT}] "paragraph under the term, indented ($cT/$cP)"
    assert [expr {$cIT >= $cP}] "inner term at the description indent ($cP/$cIT)"
    assert [expr {$cID > $cIT}] "inner description further in ($cIT/$cID)"
    assert [expr {$cA == $cT}] "text after the list back at the margin ($cT/$cA)"
    catch {file delete $f}
}

test "pdf.dl.header_footer_stay_at_page_margin" {
    if {[auto_execok pdftotext] eq ""} { skip "pdftotext not available" }
    # a long indented definition breaks the page: the footer of that page
    # must not move by the indent
    set paras {}
    for {set i 0} {$i < 80} {incr i} {
        lappend paras [dict create type list meta {kind ul indentLevel 0} content [list \
            [dict create type listItem meta {kind ul term {}} \
                content [list [dict create type text text "Line $i of a long nested list."]]]]]
    }
    set item [dict create type listItem \
        meta [dict create kind dl term [list [dict create type text text "T"]]] \
        content {} blocks [concat [list [dict create type paragraph meta {} \
            content [list [dict create type text text "P."]]]] $paras]]
    set ir [list [dict create type list meta {kind dl indentLevel 0} content [list $item]]]
    set f [file join $::TMPBASE test-pdf-dlmargin.pdf]
    docir::pdf::render $ir $f [dict create header "HdrLeftQ\tHdrRightQ" footer "FtrQ %p"]
    set t [exec pdftotext -layout $f -]
    set pages [split $t \x0C]
    assert [expr {[llength $pages] >= 2}] "several pages"
    set c1 [::_layoutCol [lindex $pages 0] HdrLeftQ]
    set c2 [::_layoutCol [lindex $pages 1] HdrLeftQ]
    assertEqual $c1 $c2 "header at the same column on page 1 and 2"
    catch {file delete $f}
}

if {[llength [info commands ::pdf4tcl::pdf4tcl]] && \
        "linkAdd" in [info class methods ::pdf4tcl::pdf4tcl -all]} {
test "pdf.links.heading_alias_is_target" {
    # section reference to the second of two equal headings (mdSource 0.2:
    # meta alias)
    set ir [list \
        [dict create type heading content {{type text text Examples}} meta {level 1 id examples}] \
        [dict create type heading content {{type text text Examples}} meta {level 1 id examples alias examples-1}] \
        [dict create type paragraph meta {} content [list \
            [dict create type link text Examples href "#examples-1"]]]]
    set f [file join $::TMPBASE test-pdf-alias.pdf]
    docir::pdf::render $ir $f [dict create compress 0]
    set fh [open $f rb]; set d [read $fh]; close $fh
    assert [regexp {/Dest /examples-1\M} $d] "link to the alias"
    assert [regexp {/examples-1\s*\[} $d] "alias is a named destination"
    catch {file delete $f}
}
}

}  ;# end pdf4tcl-availability block

exit [test::runAll]
