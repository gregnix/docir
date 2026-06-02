#!/usr/bin/env wish
## docir-view.tcl  --  DocIR-Viewer (ODT / Markdown / HTML -> Vorschau + HTML)
##
## Vorschau: docir::rendererTk (nativ, -tablemode frame). Kein mdstack noetig.
## HTML: docir::html -> Temp-Datei, per Toolbar-Button "Im Browser oeffnen".
## Kein Original-ODF-Layout.
##
## Pfade: source repos-path.tcl (Repo) oder installiertes TCLLIBPATH.
## Fehler: keine stillen catch — stderr + Meldung mit errorInfo.
##
## Nutzung:
##   wish docir-view.tcl ?datei?
##   wish docir-view.tcl --selftest
##   ODTVIEW_SELFTEST=1 wish docir-view.tcl test.odt
##
## Legacy: odt-view.tcl sourced dieses Skript.

package require Tk

namespace eval ::docirView {}

source -encoding utf-8 [file normalize [file join [file dirname [file normalize [info script]]] ../ lib repos-path.tcl]]

proc ::docirView::die {msg} {
    puts stderr "docir-view FATAL: $msg"
    tk_messageBox -icon error -title "DocIR-View" -message $msg
    exit 2
}

## Pflicht-Paket: Fehler mit errorInfo, nicht verschlucken
proc ::docirView::requirePkg {pkg} {
    if {[catch {package require {*}$pkg} err]} {
        ::docirView::die "$pkg nicht ladbar:\n$err\n\n$::errorInfo"
    }
}

## Optional: nur stderr-Hinweis (welches Paket / warum), kein stiller 0
proc ::docirView::optionalPkg {pkg} {
    if {[catch {package require {*}$pkg} err]} {
        puts stderr "docir-view: optional $pkg fehlt: $err"
        return 0
    }
    return 1
}

proc ::docirView::reportError {title err} {
    puts stderr "$title: $err"
    if {[info exists ::errorInfo] && $::errorInfo ne ""} {
        puts stderr $::errorInfo
    }
    set detail $err
    if {[info exists ::errorInfo] && $::errorInfo ne ""} {
        append detail "\n\n[string range $::errorInfo 0 1200]"
    }
    tk_messageBox -icon error -title $title -message $detail
}

proc ::docirView::warn {msg} {
    puts stderr "docir-view WARN: $msg"
    catch { .bar.hint configure -text $msg -foreground #a04000 }
}

::docirView::requirePkg docir
::docirView::requirePkg docir::html
::docirView::requirePkg docir::rendererTk

set ::docirView::haveOdt  [::docirView::optionalPkg docir::odtSource]
set ::docirView::haveHtml [::docirView::optionalPkg docir::htmlSource]
set ::docirView::haveMd   [expr {
    [::docirView::optionalPkg mdstack::parser]
    && [::docirView::optionalPkg docir::mdSource]
}]
set ::docirView::haveOdf  [::docirView::optionalPkg odf]

puts stderr "docir-view Module: ODT=$::docirView::haveOdt MD=$::docirView::haveMd HTML-in=$::docirView::haveHtml odf=$::docirView::haveOdf"

set ::docirView::viewerPath   .nb.preview.t
set ::docirView::currentPath  ""
set ::docirView::currentFmt   ""
set ::docirView::currentIr    {}
set ::docirView::htmlTemp     ""
set ::docirView::lastHtml     ""
set ::docirView::lastHtmlOk   0
set ::docirView::imageRoot    ""
set ::docirView::mediaSeq     0
set ::docirView::tocHeadings  {}
set ::docirView::tmproot [file join \
    [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] docirview-[pid]]
file mkdir $::docirView::tmproot

set ::docirView::selftest [expr {
    "--selftest" in $argv
    || [info exists ::env(DOCIRVIEW_SELFTEST)]
    || [info exists ::env(ODTVIEW_SELFTEST)]
}]
set argv [lsearch -all -inline -not -exact $argv --selftest]

# --- Quellen --------------------------------------------------------------

proc ::docirView::extFmt {path} {
    switch -- [string tolower [file extension $path]] {
        .odt  { return odt }
        .md   -
        .markdown { return md }
        .html -
        .htm  { return html }
        default { return "" }
    }
}

proc ::docirView::readUtf8 {path} {
    set fh [open $path r]
    fconfigure $fh -encoding utf-8
    set data [read $fh]
    close $fh
    return $data
}

proc ::docirView::extractParts {path members destDir} {
    if {!$::docirView::haveOdf} { return }
    set pkg [odf::Package new $path]
    try {
        foreach m $members {
            if {![$pkg has $m]} continue
            set dst [file join $destDir $m]
            file mkdir [file dirname $dst]
            set fh [open $dst wb]
            puts -nonewline $fh [$pkg part $m]
            close $fh
        }
    } finally {
        $pkg destroy
    }
}

proc ::docirView::collectImageUrls {nodes} {
    set urls {}
    foreach node $nodes {
        if {![dict exists $node type]} { continue }
        set type [dict get $node type]
        switch -- $type {
            image {
                if {[dict exists $node meta]} {
                    set m [dict get $node meta]
                    if {[dict exists $m url]} { lappend urls [dict get $m url] }
                } elseif {[dict exists $node url]} {
                    lappend urls [dict get $node url]
                }
            }
            table {
                foreach row [dict get $node content] {
                    foreach cell [dict get $row content] {
                        foreach u [::docirView::collectImageUrls [dict get $cell content]] {
                            lappend urls $u
                        }
                    }
                }
            }
            list {
                foreach item [dict get $node content] {
                    if {[dict exists $item type] && [dict get $item type] eq "listItem"} {
                        foreach u [::docirView::collectImageUrls [dict get $item content]] {
                            lappend urls $u
                        }
                    }
                }
            }
            div {
                foreach u [::docirView::collectImageUrls [dict get $node content]] {
                    lappend urls $u
                }
            }
            default {
                if {[dict exists $node content] && [llength [dict get $node content]]} {
                    set first [lindex [dict get $node content] 0]
                    if {[string is list $first] || [catch {dict get $first type}]} {
                        foreach u [::docirView::collectImageUrls [dict get $node content]] {
                            lappend urls $u
                        }
                    }
                }
            }
        }
    }
    return [lsort -unique $urls]
}

proc ::docirView::remapImageUrl {url} {
    if {$::docirView::imageRoot eq "" || ![file isdirectory $::docirView::imageRoot]} {
        return $url
    }
    set local [file join $::docirView::imageRoot $url]
    if {[file exists $local]} { return $local }
    return $url
}

proc ::docirView::prepareImages {path ir} {
    set urls [::docirView::collectImageUrls $ir]
    set ::docirView::imageRoot ""
    if {[llength $urls] == 0} { return $ir }
    set dir [file join $::docirView::tmproot media[incr ::docirView::mediaSeq]]
    file mkdir $dir
    set ::docirView::imageRoot $dir
    if {$path ne "" && $::docirView::haveOdf} {
        if {[catch {::docirView::extractParts $path $urls $dir} err]} {
            ::docirView::warn "Bilder aus ODT nicht extrahiert: $err"
        }
    } elseif {[llength $urls] > 0 && !$::docirView::haveOdf} {
        ::docirView::warn "odf fehlt — eingebettete Bilder werden nicht angezeigt"
    }
    return $ir
}

# --- Bild-urls fuer rendererTk auf lokale Pfade umbiegen --------------------
# rendererTk laedt Bilder per "image create photo -file $url"; daher die urls
# in einer IR-Kopie auf die entpackten Temp-Pfade biegen. Traversal wie
# collectImageUrls (image / table / list / div / generisch).

proc ::docirView::remapNodeUrl {node} {
    if {[dict exists $node meta] && [dict exists [dict get $node meta] url]} {
        set m [dict get $node meta]
        dict set m url [::docirView::remapImageUrl [dict get $m url]]
        dict set node meta $m
    } elseif {[dict exists $node url]} {
        dict set node url [::docirView::remapImageUrl [dict get $node url]]
    }
    return $node
}

proc ::docirView::remapImagesDeep {nodes} {
    set out {}
    foreach node $nodes {
        if {![dict exists $node type]} { lappend out $node; continue }
        switch -- [dict get $node type] {
            image {
                lappend out [::docirView::remapNodeUrl $node]
            }
            table {
                set rows {}
                foreach row [dict get $node content] {
                    set cells {}
                    foreach cell [dict get $row content] {
                        dict set cell content [::docirView::remapImagesDeep [dict get $cell content]]
                        lappend cells $cell
                    }
                    dict set row content $cells
                    lappend rows $row
                }
                dict set node content $rows
                lappend out $node
            }
            list {
                set items {}
                foreach item [dict get $node content] {
                    if {[dict exists $item content]} {
                        dict set item content [::docirView::remapImagesDeep [dict get $item content]]
                    }
                    lappend items $item
                }
                dict set node content $items
                lappend out $node
            }
            div {
                dict set node content [::docirView::remapImagesDeep [dict get $node content]]
                lappend out $node
            }
            default {
                if {[dict exists $node content] && [llength [dict get $node content]]} {
                    set first [lindex [dict get $node content] 0]
                    if {![catch {dict get $first type}]} {
                        dict set node content [::docirView::remapImagesDeep [dict get $node content]]
                    }
                }
                lappend out $node
            }
        }
    }
    return $out
}

# --- TOC-Anker aus dem nativen Renderer sammeln -----------------------------
# rendererTk ruft headingCallback: name level mark. mark ist eine echte Text-
# Mark, zu der jumpToc springen kann.
proc ::docirView::onHeading {text level mark} {
    lappend ::docirView::tocHeadings [list $mark $text $level]
}

# --- Anzeige --------------------------------------------------------------

proc ::docirView::clearToc {} {
    foreach i [.toc.tv children {}] { .toc.tv delete $i }
}

proc ::docirView::rebuildToc {} {
    ::docirView::clearToc
    foreach ent $::docirView::tocHeadings {
        lassign $ent anchor title level
        if {$anchor eq ""} { continue }
        .toc.tv insert {} end -text [string repeat "  " [expr {$level - 1}]]$title \
            -values [list $anchor $level]
    }
}

proc ::docirView::jumpToc {} {
    set sel [.toc.tv selection]
    if {$sel eq ""} { return }
    set anchor [lindex [.toc.tv item $sel -values] 0]
    if {$anchor eq ""} { return }
    set w $::docirView::viewerPath
    if {[lsearch -exact [$w mark names] $anchor] >= 0} {
        $w see $anchor
        $w yview $anchor
    }
}

proc ::docirView::renderPreview {ir} {
    if {$::docirView::currentFmt eq "odt" && $::docirView::currentPath ne ""} {
        ::docirView::prepareImages $::docirView::currentPath $ir
    } elseif {$::docirView::currentPath ne ""} {
        set ::docirView::imageRoot [file dirname $::docirView::currentPath]
    } else {
        set ::docirView::imageRoot $::docirView::tmproot
    }
    # rendererTk loads images by file path -> remap urls in an IR copy
    set viewIr [::docirView::remapImagesDeep $ir]
    # headings are collected via the renderer's headingCallback (onHeading)
    set ::docirView::tocHeadings {}
    docir::renderer::tk::render $::docirView::viewerPath $viewIr \
        [dict create fontSize 11 fontFamily TkDefaultFont monoFamily TkFixedFont \
            tablemode frame]
    ::docirView::rebuildToc
}

proc ::docirView::renderHtmlPane {ir} {
    set title [expr {
        $::docirView::currentPath ne "" ? [file tail $::docirView::currentPath] : "DocIR"
    }]
    set html ""
    set htmlErr 0
    if {[catch {
        docir::html::render $ir [dict create \
            title $title standalone 1 includeToc 1 lang de]
    } html err]} {
        set htmlErr 1
        puts stderr "docir-view: docir::html::render fehlgeschlagen: $err"
        if {[info exists ::errorInfo]} { puts stderr $::errorInfo }
        set html [format {<!DOCTYPE html><html lang="de"><head><meta charset="utf-8">
<title>HTML-Export fehlgeschlagen</title></head><body>
<h1>HTML-Export fehlgeschlagen</h1>
<pre>%s</pre>
<h2>errorInfo</h2>
<pre>%s</pre>
</body></html>} \
            [::docirView::xmlEscape $err] [::docirView::xmlEscape $::errorInfo]]
        ::docirView::warn "HTML-Export fehlgeschlagen (oeffnet als Fehlerseite im Browser; Details auf stderr)"
    }
    set ::docirView::lastHtml $html
    set ::docirView::lastHtmlOk [expr {!$htmlErr}]
    if {$::docirView::htmlTemp ne "" && [file exists $::docirView::htmlTemp]} {
        file delete -force $::docirView::htmlTemp
    }
    # Always write the temp file -- on error it holds the error page, so the
    # "Im Browser oeffnen" button still shows what went wrong.
    set ::docirView::htmlTemp [file join $::docirView::tmproot preview.html]
    set fh [open $::docirView::htmlTemp w]
    fconfigure $fh -encoding utf-8
    puts -nonewline $fh $html
    close $fh
}

proc ::docirView::xmlEscape {s} {
    return [string map {& &amp; < &lt; > &gt; \" &quot; ' &#39;} $s]
}

proc ::docirView::loadIr {path fmt} {
    switch -- $fmt {
        odt {
            if {!$::docirView::haveOdt} { error "docir::odtSource fehlt" }
            return [docir::odtSource::fromOdt $path]
        }
        md {
            if {!$::docirView::haveMd} { error "mdstack/docir::md fehlt" }
            return [docir::md::fromAst [mdstack::parser::parse [::docirView::readUtf8 $path]]]
        }
        html {
            if {!$::docirView::haveHtml} { error "docir::htmlSource fehlt" }
            return [docir::htmlSource::fromHtml [::docirView::readUtf8 $path]]
        }
        default { error "Unbekanntes Format: $fmt" }
    }
}

proc ::docirView::showIr {ir path fmt} {
    set ::docirView::currentIr $ir
    set ::docirView::currentPath $path
    set ::docirView::currentFmt $fmt
    ::docirView::renderPreview $ir
    ::docirView::renderHtmlPane $ir
    set label [expr {$path ne "" ? [file tail $path] : "(Beispiel)"}]
    .bar.file configure -text "$label  \u2014  [string toupper $fmt] \u2192 DocIR ([llength $ir] Bloecke)"
    .bar.hint configure -text "Vorschau: native Tk-Frame-Tabellen"
    wm title . "DocIR-View \u2014 $label"
    .bar.lo configure -state [expr {$fmt eq "odt" ? "normal" : "disabled"}]
}

proc ::docirView::openFile {path} {
    set fmt [::docirView::extFmt $path]
    if {$fmt eq ""} {
        tk_messageBox -icon warning -title "Format" \
            -message "Nicht unterstuetzt: [file extension $path]"
        return
    }
    if {[catch {::docirView::loadIr $path $fmt} ir err]} {
        ::docirView::reportError "Lesen fehlgeschlagen" $err
        return
    }
    ::docirView::showIr $ir $path $fmt
}

proc ::docirView::openDialog {} {
    set types [list {"Alle unterstuetzten" {.odt .md .markdown .html .htm}}]
    if {$::docirView::haveOdt}  { lappend types {"ODT" {.odt}} }
    if {$::docirView::haveMd}   { lappend types {"Markdown" {.md .markdown}} }
    if {$::docirView::haveHtml} { lappend types {"HTML" {.html .htm}} }
    lappend types {"Alle Dateien" *}
    set f [tk_getOpenFile -title "Dokument oeffnen" -filetypes $types]
    if {$f ne ""} { ::docirView::openFile $f }
}

proc ::docirView::openHtmlInBrowser {} {
    if {$::docirView::htmlTemp eq "" || ![file exists $::docirView::htmlTemp]} {
        tk_messageBox -icon info -message "Zuerst eine Datei oeffnen."
        return
    }
    set path [file normalize $::docirView::htmlTemp]
    if {[catch {
        switch -- $::tcl_platform(platform) {
            windows { exec {*}[auto_execok start] "" $path & }
            macosx  { exec open $path & }
            default { exec {*}[auto_execok xdg-open] $path & }
        }
    } err]} {
        tk_messageBox -icon warning -message "Browser:\n$err\n\n$path"
    }
}

proc ::docirView::openInLibreOffice {} {
    if {$::docirView::currentFmt ne "odt" || $::docirView::currentPath eq ""} { return }
    set path [file normalize $::docirView::currentPath]
    if {[catch {
        switch -- $::tcl_platform(platform) {
            windows { exec {*}[auto_execok start] "" $path & }
            macosx  { exec open $path & }
            default { exec {*}[auto_execok xdg-open] $path & }
        }
    } err]} {
        ::docirView::reportError "LibreOffice oeffnen" $err
    }
}

proc ::docirView::sampleIr {} {
    return [list \
        [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]] \
        [dict create type heading content {{type text text "DocIR-View"}} meta {level 1 id intro}] \
        [dict create type paragraph content {
            {type text text "Tabellen wie in mdhelp (frame-Modus)."}
        } meta {}] \
        [dict create type table content {
            {type tableRow content {
                {type tableCell content {{type text text Modul}} meta {}}
                {type tableCell content {{type text text Rolle}} meta {}}
            } meta {kind header}}
            {type tableRow content {
                {type tableCell content {{type text text docir::odtSource}} meta {}}
                {type tableCell content {{type text text ODT einlesen}} meta {}}
            } meta {}}
        } meta {columns 2 alignments {left left} hasHeader 1}] \
    ]
}

proc ::docirView::cleanup {} {
    if {[file exists $::docirView::tmproot]} {
        if {[catch {file delete -force $::docirView::tmproot} err]} {
            puts stderr "docir-view WARN: temp nicht geloescht ($::docirView::tmproot): $err"
        }
    }
}

# --- UI -------------------------------------------------------------------

wm title . "DocIR-View"
wm geometry . 1000x720

ttk::frame .bar
ttk::button .bar.open -text "Oeffnen\u2026" -command ::docirView::openDialog
ttk::button .bar.browser -text "Im Browser oeffnen" -command ::docirView::openHtmlInBrowser
ttk::button .bar.lo   -text "LibreOffice\u2026" -command ::docirView::openInLibreOffice -state disabled
ttk::label  .bar.file -text "(keine Datei)"
ttk::label  .bar.hint -text "native Tk-Frame-Tabellen" -foreground gray40
pack .bar.open .bar.browser .bar.lo -side left -padx 4 -pady 4
pack .bar.file -side left -padx 8
pack .bar.hint -side right -padx 8
pack .bar -side top -fill x

ttk::panedwindow .pw -orient horizontal
pack .pw -side top -fill both -expand 1

ttk::frame .toc -width 220
ttk::label .toc.cap -text "Inhalt" -font TkCaptionFont
ttk::treeview .toc.tv -columns {anchor lvl} -show {tree} -height 12 -selectmode browse
.toc.tv heading #0 -text "Ueberschrift"
bind .toc.tv <<TreeviewSelect>> ::docirView::jumpToc
ttk::scrollbar .toc.sb -orient vertical -command {.toc.tv yview}
.toc.tv configure -yscrollcommand {.toc.sb set}
pack .toc.cap -side top -anchor w -padx 4 -pady 2
pack .toc.sb -side right -fill y
pack .toc.tv -side left -fill both -expand 1
.pw add .toc -weight 0

ttk::notebook .nb
.pw add .nb -weight 1

ttk::frame .nb.preview
text $::docirView::viewerPath -wrap word -relief flat -padx 12 -pady 8 \
    -yscrollcommand {.nb.preview.sb set}
ttk::scrollbar .nb.preview.sb -orient vertical -command "$::docirView::viewerPath yview"
pack .nb.preview.sb -side right -fill y
pack $::docirView::viewerPath -side left -fill both -expand 1
.nb add .nb.preview -text "Vorschau"

# native renderer: headings -> TOC (anchors are real text marks)
docir::renderer::tk::setHeadingCallback ::docirView::onHeading

bind . <Control-o> ::docirView::openDialog
bind . <Control-q> { ::docirView::cleanup; exit }
wm protocol . WM_DELETE_WINDOW { ::docirView::cleanup; exit }

if {[llength $argv] > 0 && [file readable [lindex $argv 0]]} {
    ::docirView::openFile [file normalize [lindex $argv 0]]
} else {
    ::docirView::showIr [::docirView::sampleIr] "" sample
}

if {$::docirView::selftest} {
    update idletasks
    set t $::docirView::viewerPath
    set txt [$t get 1.0 end]
    set html [string range $::docirView::lastHtml 0 79]
    set tocN [llength [.toc.tv children {}]]
    set hasFrame 0
    foreach w [winfo children $t] {
        if {[winfo class $w] eq "Frame"} { set hasFrame 1; break }
    }
    set htmlOk [expr {$::docirView::lastHtmlOk && [string match *<!DOCTYPE* $html]}]
    set ok [expr {[string length $txt] > 20 && $tocN >= 1 && $hasFrame}]
    if {!$htmlOk} {
        puts stderr "docir-view SELFTEST: HTML-Export fehlgeschlagen (Vorschau ok) — siehe stderr / \"Im Browser oeffnen\""
    }
    if {[info exists ::env(ODTVIEW_SELFTEST)]} {
        puts "SELFTEST: [$t index end] Zeilen, [string length $txt] Zeichen, frame=$hasFrame"
        puts "ERSTE ZEILEN:"
        foreach l [lrange [split $txt \n] 0 6] { puts "  | $l" }
    } else {
        puts "SELFTEST: zeichen=[string length $txt] toc=$tocN frame=$hasFrame fmt=$::docirView::currentFmt"
        puts [expr {$ok ? "PASS" : "FAIL"}]
    }
    ::docirView::cleanup
    exit [expr {$ok ? 0 : 1}]
}
