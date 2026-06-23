# csdSource-0.1.tm -- DocIR source for CSD (Cheatsheet Definition)
# ============================================================
#
# CSDs sind Tcl-deklarative Cheatsheet-Definitions:
#
#   title    "pack -- Cheat Sheet"
#   subtitle "Seiten, Fuellung, expand"
#   sections {
#       {title "Grundbefehl" type table mono 1 content {
#           {{pack}     {pack $w ?-option value ...?}}
#           {{forget}   {pack forget $w}}
#       }}
#       {title "Example" type code content {
#           {pack .b -side left}
#           {pack .e -fill x}
#       }}
#       {title "Hinweise" type hint content {
#           {Order of pack calls determines space allocation.}
#       }}
#       {title "Tips" type list content {
#           {pack info $w shows the current configuration.}
#       }}
#   }
#
# This module is a docir source: CSD dict -> sheets list, in the
# same format that tilecommon::streamToSheets produces and that
# docir::tilepdf::renderSheets/_renderSheet konsumiert.
#
# Damit kann ein cheatsheets-Adapter ohne eigenen Renderer-Code
# auskommen:
#
#   set sheets [docir::csd::toSheets $csdDict]
#   docir::tilepdf::renderSheets $sheets $outFile
#
# Public API:
#   docir::csd::toSheet  csdDict       -> ein Sheet-Dict
#   docir::csd::toSheets csdOrList     -> list of sheet dicts (multi-CSD)

package provide docir::csdSource 0.1

namespace eval docir::csd {
    namespace export toSheet toSheets
}

# Ein CSD-Dict in ein Sheet-Dict (title/subtitle/sections) konvertieren.
# Section types: table/code/hint/list/code-intro/image -- the section
# content is shaped into the format that tilepdf::_renderSection expects.
proc docir::csd::toSheet {csdDict} {
    set title    ""
    set subtitle ""
    if {[dict exists $csdDict title]}    { set title    [dict get $csdDict title] }
    if {[dict exists $csdDict subtitle]} { set subtitle [dict get $csdDict subtitle] }

    set sections {}
    if {![dict exists $csdDict sections]} {
        return [dict create title $title subtitle $subtitle sections $sections]
    }

    foreach csdSec [dict get $csdDict sections] {
        set secTitle [dict get $csdSec title]
        set secType  [dict get $csdSec type]
        set content  [dict get $csdSec content]
        set monoFlag 0
        if {[dict exists $csdSec mono]} { set monoFlag [dict get $csdSec mono] }

        set sheetContent {}
        switch $secType {
            table {
                # CSD table row:  {{label} {value}}  OR {{label} {value} mono}
                # Sheet table-Row: {label value ?mono?}
                foreach row $content {
                    set lbl [lindex $row 0]
                    set val [lindex $row 1]
                    set m   $monoFlag
                    if {[llength $row] >= 3} { set m [lindex $row 2] }
                    lappend sheetContent [list $lbl $val $m]
                }
            }
            code - hint - list {
                # content is already a list of strings, 1:1
                set sheetContent $content
            }
            code-intro {
                # CSD: {... intro {...} content {...}}
                # Sheet erwartet zusaetzlich intro im Section-Dict
                set sec [dict create title $secTitle type code-intro content $content]
                if {[dict exists $csdSec intro]} {
                    dict set sec intro [dict get $csdSec intro]
                }
                lappend sections $sec
                continue
            }
            image {
                # content: list of {url alt title} triples -- 1:1
                set sheetContent $content
            }
            default {
                # Unbekannter Type: als hint behandeln (text-content)
                set secType hint
                set sheetContent $content
            }
        }
        lappend sections [dict create title $secTitle type $secType content $sheetContent]
    }

    return [dict create title $title subtitle $subtitle sections $sections]
}

# Input can be a single CSD dict or a list of CSD dicts (multi-CSD file).
# Heuristic: a single CSD dict has the key 'title' at the top level;
# a list does not.
proc docir::csd::toSheets {csdOrList} {
    set sheets {}

    # Heuristic: is it a dict with a "title" key -> single CSD
    if {[catch {dict exists $csdOrList title} hasTitle] || $hasTitle} {
        lappend sheets [toSheet $csdOrList]
    } else {
        foreach csd $csdOrList {
            lappend sheets [toSheet $csd]
        }
    }
    return $sheets
}
