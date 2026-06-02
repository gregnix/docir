#!/usr/bin/env tclsh
## docir-od-demo.tcl -- build an .odt with docir, showing ordered lists.
##
## Demonstrates the docir -> ODT pipeline: a DocIR tree (headings, a
## paragraph, a table, and ordered / bullet / nested / mixed lists) is
## rendered to a real OpenDocument Text file via docir::odt. Ordered
## lists come out numbered (1. 2. 3.), not bulleted -- the feature added
## on top of odf 0.20's defineListStyle / listStyleKind.
##
## Run from inside the docir repo:
##     tclsh demo/docir-od-demo.tcl ?out.odt?
## Needs the sibling `odf` repo (>= 0.20) that repos-path.tcl locates.

fconfigure stdout -encoding utf-8
package require Tcl 8.6
source [file join [file dirname [file normalize [info script]]] .. lib repos-path.tcl]
package require docir::odt

# ---- tiny IR helpers (keep the document readable below) ----
proc P  {s}        { return [list [dict create type text text $s]] }
proc LI {s kind}   { return [dict create type listItem content [P $s] meta [dict create kind $kind term {}]] }
proc heading {lvl s} { return [dict create type heading meta [dict create level $lvl] content [P $s]] }
proc para {s}        { return [dict create type paragraph content [P $s]] }
# a flat list block: kind = ol|ul, lvl = indent (higher = nested under previous)
proc listBlock {kind lvl args} {
    set items {}
    foreach s $args { lappend items [LI $s $kind] }
    return [dict create type list meta [dict create kind $kind indentLevel $lvl] content $items]
}

# ---- the document ----
set ir {}
lappend ir [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]]

lappend ir [heading 1 "docir \u2192 ODT demo"]
lappend ir [para "Generated from a DocIR tree. Ordered lists render as numbers, bullet lists as bullets, and nesting / mixing is preserved on round-trip."]

lappend ir [heading 2 "Numbered steps (ordered)"]
lappend ir [listBlock ol 0 "Install Tcl/Tk" "Get the odf and docir libraries" "Build your document"]
# nested ordered sublist hanging off the last step
lappend ir [listBlock ol 1 "Create a DocIR tree" "Render it with docir::odt"]

lappend ir [heading 2 "Notes (bullets)"]
lappend ir [listBlock ul 0 "odf is pass-through: only what you edit is modelled" "docir is the format-neutral IR hub"]

lappend ir [heading 2 "Mixed nesting (bullets under a number)"]
lappend ir [listBlock ol 0 "Outer step one" "Outer step two"]
lappend ir [listBlock ul 1 "a bullet under step two" "another bullet"]

lappend ir [heading 2 "A small table"]
set rows {}
lappend rows [dict create type tableRow meta [dict create kind header] content \
    [list [dict create type tableCell content [P "Library"]] [dict create type tableCell content [P "Produces"]]]]
foreach {a b} {odf::text .odt odf::sheet .ods odf::draw .odg} {
    lappend rows [dict create type tableRow content \
        [list [dict create type tableCell content [P $a]] [dict create type tableCell content [P $b]]]]
}
lappend ir [dict create type table meta [dict create columns 2] content $rows]

# ---- render ----
set out [expr {[llength $argv] >= 1 ? [lindex $argv 0] : "docir-od-demo.odt"}]
docir::odt::write $ir $out
puts "wrote: $out"
puts "open it in LibreOffice Writer to see 1. 2. 3. numbering, bullets, nesting and the table."
