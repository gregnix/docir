#!/usr/bin/env tclsh
# manual-build.tcl -- merge a tree of nroff-derived manpage Markdown files
# into ONE Markdown manual (and optionally PDF/HTML).
#
# Unlike book-build.tcl (for hand-written, number-free chapters), this is for
# converted manpages that carry their own NAME/DESCRIPTION sections and YAML
# front matter. Each manpage becomes a chapter titled by its command name
# (the file name); the manpage's own sections are shifted one level down, so
# the result is a clean hierarchy: "# after" / "## NAME" / "## DESCRIPTION".
#
# Usage:
#   tclsh manual-build.tcl <dir> [-md out.md] [-pdf out.pdf] [-html out.html]
#                                [-title T]
#
# <dir> is scanned recursively for *.md (e.g. .../de-markdown/8.6 covers both
# tcl/ and tk/). Files are ordered by path, so tcl/ sorts before tk/.

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

set docirRoot   [discover DOCIR_HOME      {lib tm docir-0.1.1.tm}]
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
package require docir::md

# ============================================================
# Manual assembly
# ============================================================

# Collect *.md recursively, ordered by path (so tcl/ sorts before tk/).
proc collectManpages {dir} {
    set files [lsort [glob -nocomplain -directory $dir *.md]]
    foreach sub [lsort [glob -nocomplain -type d -directory $dir *]] {
        foreach f [collectManpages $sub] { lappend files $f }
    }
    return $files
}

# One manpage -> a chapter: "# <command>" then the manpage body with its own
# headings shifted down one level (NAME/DESCRIPTION become ##, sub-sections
# ###). The command name is taken from the file name.
#
# The body is taken VERBATIM from the source Markdown (no docir round-trip):
# the round-trip would degrade Pandoc definition lists (": text") into
# 4-space-indented code blocks, which then overflow the page as non-wrapping
# monospace. We only (a) strip the YAML front matter (but keep its Copyright
# lines), and (b) raise ATX heading levels by one, skipping fenced code blocks
# so that "# comment" lines inside examples are left untouched. The copyright
# of each manpage is preserved as a small note at the end of its chapter.
proc manualChapter {file} {
    set name [file rootname [file tail $file]]
    set fh [open $file r]
    fconfigure $fh -encoding utf-8
    set md [read $fh]
    close $fh

    set lines [split $md \n]
    set i 0
    set copyrights {}
    # Strip leading YAML front matter (--- ... ---), but capture Copyright:.
    if {[llength $lines] > 0 && [lindex $lines 0] eq "---"} {
        set inCopyright 0
        for {set i 1} {$i < [llength $lines]} {incr i} {
            set fm [lindex $lines $i]
            if {$fm eq "---"} { incr i; break }
            if {[regexp {^Copyright:} $fm]} { set inCopyright 1; continue }
            if {$inCopyright} {
                if {[regexp {^ +- +(.+)$} $fm -> cline]} {
                    lappend copyrights [string trim $cline]
                    continue
                } else {
                    set inCopyright 0
                }
            }
        }
    }

    set out "# $name\n\n"
    set inFence 0
    set fenceMark ""
    for {} {$i < [llength $lines]} {incr i} {
        set line [lindex $lines $i]
        # Track fenced code blocks (``` or ~~~); leave their content verbatim.
        if {[regexp {^[ \t]*(```+|~~~+)} $line -> mark]} {
            if {!$inFence} {
                set inFence 1; set fenceMark [string index $mark 0]
            } elseif {[string index $mark 0] eq $fenceMark} {
                set inFence 0
            }
            append out $line "\n"
            continue
        }
        if {!$inFence && [regexp {^(#{1,6}) (.*)$} $line -> hashes rest]} {
            if {[string length $hashes] < 6} { set hashes "#$hashes" }
            append out $hashes " " $rest "\n"
        } else {
            append out $line "\n"
        }
    }
    set out [string trimright $out]
    # Preserve the manpage's copyright as a small italic note.
    if {[llength $copyrights] > 0} {
        set notes {}
        foreach c $copyrights { lappend notes "*$c*" }
        append out "\n\n" [join $notes "\\\n"]
    }
    return "$out\n\n"
}

# ============================================================
# CLI
# ============================================================

if {[llength $argv] < 1} {
    puts stderr "Usage: manual-build.tcl <dir> \[-md out.md\] \[-pdf out.pdf\] \[-html out.html\]"
    puts stderr "                         \[-title T\] [-license file ...]"
    exit 1
}

set dir [lindex $argv 0]
if {![file isdirectory $dir]} {
    puts stderr "FEHLER: kein Verzeichnis: $dir"
    exit 1
}

set mdOut    ""
set pdfOut   ""
set htmlOut  ""
set title    ""
set licFiles {}
for {set i 1} {$i < [llength $argv]} {incr i} {
    set a [lindex $argv $i]
    switch -- $a {
        -md      { set mdOut   [lindex $argv [incr i]] }
        -pdf     { set pdfOut  [lindex $argv [incr i]] }
        -html    { set htmlOut [lindex $argv [incr i]] }
        -title   { set title   [lindex $argv [incr i]] }
        -license { lappend licFiles [lindex $argv [incr i]] }
        default  { puts stderr "Unbekannte Option: $a"; exit 1 }
    }
}
if {$mdOut eq "" && $pdfOut eq "" && $htmlOut eq ""} {
    set base [file normalize $dir]
    set mdOut "[file tail $base]-all.md"
}

set files [collectManpages $dir]
if {[llength $files] == 0} {
    puts stderr "FEHLER: keine .md gefunden unter $dir"
    exit 1
}
puts "Manual: [llength $files] Manpages aus $dir"

# Assemble merged Markdown.
set manual ""
foreach f $files { append manual [manualChapter $f] }
set manual [string trimright $manual]\n

# Optional license appendix. One or more -license files are appended as a
# final "# License" chapter so they travel with the merged manual. With a
# single file the text follows the heading directly; with several files each
# gets a "## <name>" sub-section (name = file stem, e.g. tcl, tk) so they are
# told apart.
if {[llength $licFiles] > 0} {
    foreach lf $licFiles {
        if {![file exists $lf]} {
            puts stderr "FEHLER: Lizenzdatei nicht gefunden: $lf"
            exit 1
        }
    }
    append manual "\n# License\n\n"
    set multi [expr {[llength $licFiles] > 1}]
    foreach lf $licFiles {
        set fh [open $lf r]
        fconfigure $fh -encoding utf-8
        set lic [read $fh]
        close $fh
        if {$multi} {
            append manual "## [file rootname [file tail $lf]]\n\n"
        }
        append manual "```\n[string trim $lic]\n```\n\n"
    }
    set manual [string trimright $manual]\n
}

# Direct Markdown output: write the assembled manual as-is.
if {$mdOut ne ""} {
    set fh [open $mdOut w]
    fconfigure $fh -encoding utf-8
    puts -nonewline $fh $manual
    close $fh
    puts "MD:   $mdOut ([file size $mdOut] Bytes)"
}

# For PDF/HTML, re-parse the merged Markdown so command chapters become real
# headings, optionally number them, then render through the docir sinks.
if {$pdfOut ne "" || $htmlOut ne ""} {
    set ir [docir::md::fromAst [mdstack::parser::parse $manual]]
    if {$pdfOut ne ""} {
        package require docir::pdf
        docir::pdf::render $ir $pdfOut [dict create \
            title $title paper a4 footer "%p" \
            generateToc 1 tocTitle "Contents" tocDepth 1 \
            generateIndex 0]
        puts "PDF:  $pdfOut ([file size $pdfOut] Bytes)"
    }
    if {$htmlOut ne ""} {
        package require docir::html
        set html [docir::html::render $ir [dict create \
            title $title includeToc 1 includeIndex 0]]
        set fh [open $htmlOut w]
        fconfigure $fh -encoding utf-8
        puts -nonewline $fh $html
        close $fh
        puts "HTML: $htmlOut ([file size $htmlOut] Bytes)"
    }
}
