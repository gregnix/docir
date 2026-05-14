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
set libDir [file join $projectRoot lib tm]

# pkgIndex.tcl ist in $libDir -- damit Tests, die statt source
# 'package require docir::*' nutzen, die Module auch finden.
if {[lsearch -exact $::auto_path $libDir] < 0} {
    lappend ::auto_path $libDir
}

# DocIR-Module direkt sourcen — Tests laufen aus dem Repo, die Pfade
# sind also bekannt. Tk-abhaengige Module (canvas, rendererTk) und
# Module mit externer Dep (tilepdf braucht pdf4tcl) mit catch — wenn
# die Dep nicht ladbar ist, skipt der entsprechende Test.
source -encoding utf-8 [file join $libDir docir-0.1.tm]
# Module ohne externe Deps (Pflicht)
foreach mod {
    tilecommon-0.1.tm
    roffSource-0.1.tm
    mdSource-0.1.tm
    html-0.1.tm
    svg-0.1.tm
    md-0.1.tm
    roff-0.1.tm
    tilehtml-0.1.tm
    tilemd-0.1.tm
} {
    set p [file join $libDir docir $mod]
    if {[file exists $p]} {
        source -encoding utf-8 $p
    }
}
# Module mit externer Dep (pdf4tcl) — catch, damit Tests ohne pdf4tcl
# nicht hart abbrechen sondern sich selbst skippen koennen.
foreach mod {
    pdf-0.2.tm
    tilepdf-0.1.tm
} {
    set p [file join $libDir docir $mod]
    if {[file exists $p]} {
        catch {source -encoding utf-8 $p}
    }
}
foreach mod {
    canvas-0.1.tm
    rendererTk-0.1.tm
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

# Helper fuer Tests die externe Parser brauchen.
proc haveParser {ns} {
    return [expr {[namespace exists ::$ns] && [info commands ::${ns}::parse] ne ""}]
}
