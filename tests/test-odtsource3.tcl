#!/usr/bin/env tclsh
# test-odtsource3.tcl
#
# Testscript fuer docir::odtSource 0.4
#
# Zweck:
#   - ODT-Datei einlesen
#   - docir-IR erzeugen
#   - Blocktypen zaehlen
#   - Tabellen, Bilder, Headings, Paragraphs, Pre-Bloecke pruefen
#   - optionale Detailausgabe
#
# Aufruf:
#   tclsh test-odtsource3.tcl file.odt
#   tclsh test-odtsource3.tcl -v file.odt
#   tclsh test-odtsource3.tcl -dump file.odt
#
# Erwartete Dateien im Modulpfad:
#   odt-0.4.tm
#   odtSource-0.4.tm

proc usage {} {
    puts "usage: tclsh test-odtsource3.tcl ?-v? ?-dump? file.odt"
    exit 1
}

set verbose 0
set dump 0
set file ""

foreach arg $argv {
    switch -- $arg {
        -v {
            set verbose 1
        }
        -dump {
            set dump 1
        }
        default {
            if {$file eq ""} {
                set file $arg
            } else {
                usage
            }
        }
    }
}

if {$file eq ""} {
    usage
}

if {![file exists $file]} {
    puts stderr "ERROR: file not found: $file"
    exit 2
}

set scriptDir [file dirname [file normalize [info script]]]
lappend auto_path $scriptDir
lappend auto_path [pwd]

package require Tcl 8.6
package require docir::odtSource 0.4

proc dictGetDef {d key {default ""}} {
    if {[dict exists $d $key]} {
        return [dict get $d $key]
    }
    return $default
}

proc inlineText {items} {
    set out ""
    foreach item $items {
        if {![dict exists $item type]} {
            continue
        }
        set type [dict get $item type]
        switch -- $type {
            text -
            strong -
            emphasis -
            code -
            span {
                append out [dictGetDef $item text ""]
            }
            linebreak {
                append out " ⏎ "
            }
            link {
                append out [dictGetDef $item text ""]
            }
            default {
                append out "<$type>"
            }
        }
    }
    return $out
}

proc short {s {max 80}} {
    set s [string map [list "\n" " " "\t" " "] $s]
    regsub -all {[ ]+} $s { } s
    if {[string length $s] > $max} {
        return "[string range $s 0 [expr {$max - 4}]]..."
    }
    return $s
}

proc countBlocks {ir} {
    set counts {}
    foreach block $ir {
        set type [dict get $block type]
        dict incr counts $type
    }
    return $counts
}

proc check {condition message} {
    if {!$condition} {
        puts stderr "FAIL: $message"
        return 0
    }
    puts "ok   $message"
    return 1
}

proc hasType {ir type} {
    foreach block $ir {
        if {[dict get $block type] eq $type} {
            return 1
        }
    }
    return 0
}

proc tableInfo {block} {
    set meta [dictGetDef $block meta {}]
    set content [dictGetDef $block content {}]
    set columns [dictGetDef $meta columns "?"]
    set rows [llength $content]
    return [list columns $columns rows $rows]
}

puts "ODT-SOURCE TEST 0.4"
puts "file: $file"
puts ""

set ir [docir::odtSource::fromOdt $file]

puts "BLOCKS: [llength $ir]"
puts ""

set counts [countBlocks $ir]
puts "BLOCK COUNTS"
foreach type [lsort [dict keys $counts]] {
    puts [format "  %-12s %s" $type [dict get $counts $type]]
}
puts ""

set failures 0

if {![check [expr {[llength $ir] > 0}] "IR ist nicht leer"]} { incr failures }
if {![check [hasType $ir heading] "enthaelt heading"]} { incr failures }
if {![check [hasType $ir paragraph] "enthaelt paragraph"]} { incr failures }
if {![check [hasType $ir table] "enthaelt table"]} { incr failures }
if {![check [hasType $ir image] "enthaelt image"]} { incr failures }
if {![check [hasType $ir pre] "enthaelt pre/code"]} { incr failures }

puts ""
puts "HEADINGS"
foreach block $ir {
    if {[dict get $block type] ne "heading"} {
        continue
    }
    set meta [dictGetDef $block meta {}]
    set level [dictGetDef $meta level "?"]
    set id [dictGetDef $meta id ""]
    set text [inlineText [dictGetDef $block content {}]]
    puts [format "  H%-2s %-35s %s" $level $id [short $text 70]]
}

puts ""
puts "TABLES"
set idx 0
foreach block $ir {
    if {[dict get $block type] ne "table"} {
        continue
    }
    incr idx
    set info [tableInfo $block]
    set meta [dictGetDef $block meta {}]
    puts [format "  table %-2d columns=%s rows=%s hasHeader=%s" \
        $idx \
        [dictGetDef $info columns "?"] \
        [dictGetDef $info rows "?"] \
        [dictGetDef $meta hasHeader 0]]
}

puts ""
puts "IMAGES"
set idx 0
foreach block $ir {
    if {[dict get $block type] ne "image"} {
        continue
    }
    incr idx
    set meta [dictGetDef $block meta {}]
    puts [format "  image %-2d url=%s alt=%s" \
        $idx \
        [dictGetDef $meta url ""] \
        [dictGetDef $meta alt ""]]
}

if {$verbose} {
    puts ""
    puts "BLOCK SUMMARY"
    set i 0
    foreach block $ir {
        incr i
        set type [dict get $block type]
        set meta [dictGetDef $block meta {}]
        set content [dictGetDef $block content {}]
        switch -- $type {
            heading -
            paragraph -
            pre {
                set text [inlineText $content]
                puts [format "%3d %-10s meta=%s text=%s" $i $type $meta [short $text 100]]
            }
            table {
                set info [tableInfo $block]
                puts [format "%3d %-10s meta=%s %s" $i $type $meta $info]
            }
            image {
                puts [format "%3d %-10s meta=%s" $i $type $meta]
            }
            default {
                puts [format "%3d %-10s meta=%s" $i $type $meta]
            }
        }
    }
}

if {$dump} {
    puts ""
    puts "FULL IR DUMP"
    foreach block $ir {
        puts $block
        puts ""
    }
}

puts ""
if {$failures == 0} {
    puts "RESULT: OK"
    exit 0
} else {
    puts "RESULT: FAILED ($failures)"
    exit 1
}
