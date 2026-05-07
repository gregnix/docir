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

# DocIR-Module direkt sourcen — Tests laufen aus dem Repo, die Pfade
# sind also bekannt. Tk-abhaengige Module (canvas, rendererTk) mit
# catch — wenn Tk nicht ladbar ist (kein DISPLAY), skipt der Test.
source -encoding utf-8 [file join $libDir docir-0.1.tm]
foreach mod {
    tilecommon-0.1.tm
    roffSource-0.1.tm
    mdSource-0.1.tm
    html-0.1.tm
    svg-0.1.tm
    pdf-0.1.tm
    md-0.1.tm
    tilepdf-0.1.tm
    tilemd-0.1.tm
} {
    set p [file join $libDir docir $mod]
    if {[file exists $p]} {
        source -encoding utf-8 $p
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
