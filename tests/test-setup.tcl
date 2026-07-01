#!/usr/bin/env tclsh
# Common test setup for docir-Repo.
#
# DocIR ist standalone — keine harte Abhaengigkeit auf Parser.
# Die meisten Tests bauen DocIR direkt aus dict create.
#
# Externe Module (mdparser, nroffparser, pdf4tcl, pdf4tcllib) werden
# erwartet im auto_path / tcl::tm::path. Bei Linux: typisch unter
# /usr/local/lib/tcltk/<repo>/ — siehe README. Tests die diese Module
# brauchen skippen sich selbst wenn sie fehlen (haveParser-Check).

set testDir [file dirname [file normalize [info script]]]
set projectRoot [file dirname $testDir]

# Unified sibling-repo paths (odf, mdstack, man-viewer): one place for all.
source [file join $projectRoot lib repos-path.tcl]
set libDir [file join $projectRoot lib tm]

# pkgIndex.tcl ist in $libDir -- damit Tests, die statt source
# 'package require docir::*' nutzen, die Module auch finden.
if {[lsearch -exact $::auto_path $libDir] < 0} {
    lappend ::auto_path $libDir
}
# Plus: tm::path damit `.tm`-Module via `package require` ladbar sind
# (auto_path allein reicht fuer Tk packages, aber Tcl-Module brauchen
# tm::path).
::tcl::tm::path add $libDir

# DocIR-Module direkt sourcen — Tests laufen aus dem Repo, die Pfade
# sind also bekannt. Tk-abhaengige Module (canvas, rendererTk) und
# Module mit externer Dep (tilepdf braucht pdf4tcl) mit catch — wenn
# die Dep nicht ladbar ist, skipt der entsprechende Test.
source -encoding utf-8 [file join $libDir docir-0.1.1.tm]
# Module ohne externe Deps (Pflicht)
foreach mod {
    util-0.1.tm
    tilecommon-0.1.tm
    roffSource-0.1.tm
    mdSource-0.1.tm
    html-0.1.tm
    svg-0.1.tm
    md-0.1.tm
    roff-0.1.tm
    tilehtml-0.1.tm
    tilemd-0.1.tm
    txt-0.1.tm
} {
    set p [file join $libDir docir $mod]
    if {[file exists $p]} {
        source -encoding utf-8 $p
    }
}
# Module mit externer Dep (pdf4tcl) — catch, damit Tests ohne pdf4tcl
# nicht hart abbrechen sondern sich selbst skippen koennen.
foreach mod {
    pdf-0.3.tm
    tilepdf-0.1.tm
} {
    set p [file join $libDir docir $mod]
    if {[file exists $p]} {
        catch {source -encoding utf-8 $p}
    }
}
foreach mod {
    canvas-0.1.tm
    rendererTk-0.2.tm
} {
    set p [file join $libDir docir $mod]
    if {[file exists $p]} {
        catch {source -encoding utf-8 $p}
    }
}

# Externe Module (mdparser aus mdstack, nroffparser aus man-viewer)
# sind ueber System-Install im auto_path / tm::path erreichbar.
# Tests die diese Module brauchen, machen das selbst per package require
# in einem catch-Block und skippen sich wenn nicht vorhanden.
catch {package require mdstack::parser}
catch {package require nroffparser}
catch {package require mvdebug}

# Skip-stub: if the optional man-viewer parser is not installed, any test that
# calls into nroffparser should *skip*, not die with "invalid command name".
# The stubs never fake a result -- they raise the DOCIR_SKIP signal the test
# framework recognises. A marker variable lets haveParser report it as absent so
# whole-file guards (e.g. test-validator) skip cleanly. When nroffparser IS
# installed none of this is defined.
if {[info commands ::nroffparser::parse] eq ""} {
    namespace eval ::nroffparser {}
    variable ::nroffparser::__stub 1
    foreach __cmd {parse validate validateAST} {
        proc ::nroffparser::$__cmd {args} {
            skip "nroffparser (man-viewer) not installed"
        }
    }
    unset __cmd
}

# Helper fuer Tests die externe Parser brauchen.
proc haveParser {ns} {
    if {[info exists ::${ns}::__stub]} { return 0 }
    return [expr {[namespace exists ::$ns] && [info commands ::${ns}::parse] ne ""}]
}
