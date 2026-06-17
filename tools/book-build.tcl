#!/usr/bin/env tclsh
# book-build.tcl -- Build a docir/mdstack book to PDF and/or HTML, with
# hierarchical auto-numbering, a table of contents and a subject index.
#
# Usage:
#   book-build.tcl <bookdir> [-pdf out.pdf] [-html out.html]
#                            [-number] [-no-toc] [-no-index]
#                            [-title T] [-author A] [-depth N]
#   book-build.tcl manifest <bookdir>     # write book.tcl from NNN- prefixes
#
# If neither -pdf nor -html is given, both are produced next to <bookdir>
# (<bookname>.pdf / <bookname>.html).
#
# Chapter order
#   - If <bookdir>/book.tcl exists it defines the order: it sets a Tcl
#     variable `chapters` (list of .md files relative to <bookdir>);
#     `title` and `author` are optional. The numeric filename prefix is
#     ignored in this mode.
#   - Otherwise files are taken from <bookdir>/*.md, ordered by a numeric
#     filename prefix (e.g. 010-intro.md). The prefix is only used for
#     ordering and never appears in the output. Files without a numeric
#     prefix follow, sorted alphabetically.
#
# Numbering (-number)
#   Source headings carry no numbers (#, ##, ###). With -number the build
#   assigns 1 / 1.1 / 1.1.1 from nesting + order (down to -depth, default 3).
#   Numbers are added on the IR, so they appear consistently in body, TOC,
#   bookmarks and both output formats. Heading anchors stay title-based, so
#   reordering changes numbers but not cross-reference targets.
#
# Index
#   Index terms are marked in Markdown as bracketed spans: [Term]{.index}
#   The term stays visible in the text and is collected into the index
#   (PDF: pages; HTML: links to the sections, labelled by section title).

package require Tcl 8.6-

# ============================================================
# Module discovery (env overrides + sibling search + system install)
# ============================================================

set scriptDir [file dirname [file normalize [info script]]]

set searchBases {}
if {[info exists env(REPOS_DIR)]} { lappend searchBases $env(REPOS_DIR) }
lappend searchBases \
    $scriptDir \
    [file dirname $scriptDir] \
    [file dirname [file dirname $scriptDir]] \
    [file join $env(HOME) code git github] \
    [file join $env(HOME) lib tcltk] \
    /usr/local/lib/tcltk

proc discover {envVar markerRel} {
    global env searchBases
    if {[info exists env($envVar)] && [file exists [file join $env($envVar) {*}$markerRel]]} {
        return $env($envVar)
    }
    foreach base $searchBases {
        if {![file isdirectory $base]} continue
        if {[file exists [file join $base {*}$markerRel]]} { return $base }
        foreach sub [glob -nocomplain -directory $base -type d *] {
            if {[file exists [file join $sub {*}$markerRel]]} { return $sub }
            foreach sub2 [glob -nocomplain -directory $sub -type d *] {
                if {[file exists [file join $sub2 {*}$markerRel]]} { return $sub2 }
            }
        }
    }
    return ""
}

proc addTm {dir} {
    if {$dir ne "" && [file isdirectory $dir] && $dir ni [tcl::tm::path list]} {
        catch {tcl::tm::path add $dir}
    }
}

set docirRoot   [discover DOCIR_HOME      {lib tm docir-0.1.tm}]
set mdstackRoot [discover MDSTACK_HOME    {lib mdstack-0.1.tm}]
set pdftclRoot  [discover PDF4TCL_HOME    {pdf4tcl.tcl}]
set pdflibRoot  [discover PDF4TCLLIB_HOME {lib pdf4tcllib-0.2.tm}]

if {$docirRoot   ne ""} { addTm [file join $docirRoot lib tm] }
if {$mdstackRoot ne ""} { addTm [file join $mdstackRoot lib] }
if {$pdflibRoot  ne ""} { addTm [file join $pdflibRoot lib] }
if {$pdftclRoot  ne ""} { lappend auto_path $pdftclRoot }

foreach pkg {mdstack::parser docir::mdSource} {
    if {[catch {package require $pkg} err]} {
        puts stderr "FEHLER: kann $pkg nicht laden: $err"
        puts stderr "  Setze DOCIR_HOME / MDSTACK_HOME (und PDF4TCL_HOME / PDF4TCLLIB_HOME)."
        exit 1
    }
}

# ============================================================
# Helpers
# ============================================================

# Hierarchical auto-numbering on the IR: prepend "1.2.3  " to heading text,
# resetting deeper counters when a higher level appears. Down to maxLevel.
proc numberHeadings {ir maxLevel} {
    set counters {0 0 0 0 0 0}
    set out {}
    foreach node $ir {
        if {[dict get $node type] eq "heading"} {
            set m [dict get $node meta]
            set lv [expr {[dict exists $m level] ? [dict get $m level] : 1}]
            if {$lv >= 1 && $lv <= $maxLevel} {
                lset counters [expr {$lv - 1}] [expr {[lindex $counters [expr {$lv - 1}]] + 1}]
                for {set i $lv} {$i < 6} {incr i} { lset counters $i 0 }
                set num [join [lrange $counters 0 [expr {$lv - 1}]] .]
                set content [dict get $node content]
                # Normalize single-inline (flat dict) to a list of inlines.
                if {[lindex $content 0] eq "type"} { set content [list $content] }
                set content [linsert $content 0 [dict create type text text "$num  "]]
                dict set node content $content
            }
        }
        lappend out $node
    }
    return $out
}

# Numeric filename prefix (leading digits), or "" if none.
proc filePrefix {name} {
    if {[regexp {^([0-9]+)} [file tail $name] -> n]} { return $n }
    return ""
}

# Files ordered by numeric prefix; unprefixed files alphabetically after.
proc prefixOrdered {bookdir} {
    set withNum {}
    set noNum {}
    foreach f [glob -nocomplain -directory $bookdir *.md] {
        set p [filePrefix $f]
        if {$p ne ""} {
            lappend withNum [list [scan $p %d] [file tail $f]]
        } else {
            lappend noNum [file tail $f]
        }
    }
    set files {}
    foreach pair [lsort -integer -index 0 $withNum] { lappend files [lindex $pair 1] }
    foreach f [lsort $noNum] { lappend files $f }
    return $files
}

# Read book.tcl in a child interpreter; return {title author chapters}.
proc readManifest {manifestPath} {
    set ip [interp create -safe]
    # Allow only plain variable assignment; book.tcl is data, not code.
    interp eval $ip {set title ""; set author ""; set chapters {}
                     set tocTitle ""; set indexTitle ""}
    set fh [open $manifestPath r]
    fconfigure $fh -encoding utf-8
    set script [read $fh]
    close $fh
    if {[catch {interp eval $ip $script} err]} {
        interp delete $ip
        error "book.tcl: $err"
    }
    set title      [interp eval $ip {set title}]
    set author     [interp eval $ip {set author}]
    set chapters   [interp eval $ip {set chapters}]
    set tocTitle   [interp eval $ip {set tocTitle}]
    set indexTitle [interp eval $ip {set indexTitle}]
    interp delete $ip
    return [list $title $author $chapters $tocTitle $indexTitle]
}

# Resolve order + metadata for a book directory.
# Returns {title author files tocTitle indexTitle} (files relative to bookdir).
proc resolveBook {bookdir} {
    set manifest [file join $bookdir book.tcl]
    if {[file exists $manifest]} {
        lassign [readManifest $manifest] title author chapters tocTitle indexTitle
        return [list $title $author $chapters $tocTitle $indexTitle]
    }
    return [list "" "" [prefixOrdered $bookdir] "" ""]
}

# Generate book.tcl from the prefix order so it can be hand-reordered later.
proc writeManifestFile {bookdir} {
    set files [prefixOrdered $bookdir]
    if {[llength $files] == 0} {
        puts stderr "FEHLER: keine .md-Dateien in $bookdir"
        exit 1
    }
    set out [file join $bookdir book.tcl]
    set fh [open $out w]
    fconfigure $fh -encoding utf-8
    puts $fh "# book.tcl -- chapter order for this book."
    puts $fh "# Generated from filename prefixes; reorder lines freely."
    puts $fh "# Prefixes are ignored once this file exists."
    puts $fh ""
    puts $fh "set title  \"\""
    puts $fh "set author \"\""
    puts $fh ""
    puts $fh "set chapters \{"
    foreach f $files { puts $fh "    $f" }
    puts $fh "\}"
    close $fh
    puts "geschrieben: $out ([llength $files] Kapitel)"
}

# ============================================================
# Argument parsing
# ============================================================

if {[llength $argv] >= 2 && [lindex $argv 0] eq "manifest"} {
    writeManifestFile [lindex $argv 1]
    exit 0
}

if {[llength $argv] < 1} {
    puts stderr "Usage: book-build.tcl <bookdir> \[-pdf out.pdf\] \[-html out.html\]"
    puts stderr "                       \[-number\] \[-no-toc\] \[-no-index\] \[-title T\] \[-author A\] \[-depth N\]"
    puts stderr "                       \[-toc-title T\] \[-index-title T\]"
    puts stderr "       book-build.tcl manifest <bookdir>"
    exit 1
}

set bookdir [lindex $argv 0]
if {![file isdirectory $bookdir]} {
    puts stderr "FEHLER: kein Verzeichnis: $bookdir"
    exit 1
}

set pdfOut    ""
set htmlOut   ""
set doNumber  0
set wantToc   1
set wantIndex 1
set optTitle  ""
set optAuthor ""
set optTocTitle   ""
set optIndexTitle ""
set depth     3

for {set i 1} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    switch -- $a {
        -pdf      { set pdfOut    [lindex $argv [incr i]] }
        -html     { set htmlOut   [lindex $argv [incr i]] }
        -number   { set doNumber  1 }
        -no-toc   { set wantToc   0 }
        -no-index { set wantIndex 0 }
        -title    { set optTitle  [lindex $argv [incr i]] }
        -author   { set optAuthor [lindex $argv [incr i]] }
        -toc-title   { set optTocTitle   [lindex $argv [incr i]] }
        -index-title { set optIndexTitle [lindex $argv [incr i]] }
        -depth    { set depth     [lindex $argv [incr i]] }
        default   { puts stderr "Unbekannte Option: $a"; exit 1 }
    }
}

# Default outputs if neither requested.
if {$pdfOut eq "" && $htmlOut eq ""} {
    set base [file join [file dirname [file normalize $bookdir]] [file tail [file normalize $bookdir]]]
    set pdfOut  "$base.pdf"
    set htmlOut "$base.html"
}

# ============================================================
# Assemble + parse + (number) + render
# ============================================================

lassign [resolveBook $bookdir] mTitle mAuthor files mTocTitle mIndexTitle
if {[llength $files] == 0} {
    puts stderr "FEHLER: keine Kapitel gefunden in $bookdir"
    exit 1
}

set title  [expr {$optTitle  ne "" ? $optTitle  : $mTitle}]
set author [expr {$optAuthor ne "" ? $optAuthor : $mAuthor}]
# Toc/index titles: command-line switch > manifest > German default.
set tocTitle [expr {$optTocTitle ne "" ? $optTocTitle \
    : ($mTocTitle ne "" ? $mTocTitle : "Inhaltsverzeichnis")}]
set indexTitle [expr {$optIndexTitle ne "" ? $optIndexTitle \
    : ($mIndexTitle ne "" ? $mIndexTitle : "Stichwortverzeichnis")}]

puts "Buch: [llength $files] Kapitel aus $bookdir"

set md ""
foreach f $files {
    set path [file join $bookdir $f]
    if {![file exists $path]} {
        puts stderr "WARNUNG: Kapitel fehlt, uebersprungen: $f"
        continue
    }
    set fh [open $path r]
    fconfigure $fh -encoding utf-8
    append md [read $fh] "\n\n"
    close $fh
}

set ast [mdstack::parser::parse $md]
set ir  [docir::md::fromAst $ast]
if {$doNumber} { set ir [numberHeadings $ir $depth] }

if {$pdfOut ne ""} {
    package require docir::pdf
    docir::pdf::render $ir $pdfOut [dict create \
        title         $title \
        author        $author \
        paper         a4 \
        footer        "%p" \
        generateToc   $wantToc \
        tocTitle      $tocTitle \
        tocDepth      $depth \
        generateIndex $wantIndex \
        indexTitle    $indexTitle]
    puts "PDF:  $pdfOut ([file size $pdfOut] Bytes)"
}

if {$htmlOut ne ""} {
    package require docir::html
    set html [docir::html::render $ir [dict create \
        title        $title \
        includeToc   $wantToc \
        includeIndex $wantIndex \
        indexTitle   $indexTitle]]
    set fh [open $htmlOut w]
    fconfigure $fh -encoding utf-8
    puts -nonewline $fh $html
    close $fh
    puts "HTML: $htmlOut ([file size $htmlOut] Bytes)"
}
