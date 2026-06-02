#!/usr/bin/env tclsh
# test-odt-ol.tcl -- ordered vs unordered list round-trip through ODT.
#
#   DocIR(ol/ul) -> docir::odt -> .odt -> docir::odtSource -> DocIR
# must preserve the list "kind" (ol stays ol, ul stays ul), including a
# nested ordered sublist. Exercises odf 0.20 defineListStyle/listStyleKind.

fconfigure stdout -encoding utf-8
package require Tcl 8.6
source [file join [file dirname [file normalize [info script]]] .. lib repos-path.tcl]
package require docir::odt
package require docir::odtSource

set pass 0; set fail 0
proc ok {b m} { if {[uplevel 1 [list expr $b]]} {incr ::pass; puts "ok   $m"} else {incr ::fail; puts "FAIL $m"} }

proc txt {s} { return [list [dict create type text text $s]] }
proc item {s kind} { return [dict create type listItem content [txt $s] meta [dict create kind $kind term {}]] }

# ---- build an IR: ordered list (with a nested ordered sublist) + bullet list ----
set ir {}
lappend ir [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]]
# ordered list, level 0
lappend ir [dict create type list meta [dict create kind ol indentLevel 0] \
    content [list [item one ol] [item two ol]]]
# its nested ordered sublist (flat model: higher indentLevel = sublist of prev)
lappend ir [dict create type list meta [dict create kind ol indentLevel 1] \
    content [list [item two-a ol] [item two-b ol]]]
# bullet list, level 0
lappend ir [dict create type list meta [dict create kind ul indentLevel 0] \
    content [list [item alpha ul] [item beta ul]]]

set out [file join [file dirname [file normalize [info script]]] out]
file mkdir $out
set odt [file join $out odt-ol.odt]
docir::odt::write $ir $odt

# ---- read back ----
set ir2 [docir::odtSource::fromOdt $odt]

# collect list blocks with their kind/indent
set lists {}
foreach b $ir2 {
    if {[dict get $b type] ne "list"} continue
    set m [dict get $b meta]
    set firstText ""
    set items [dict get $b content]
    if {[llength $items]} {
        set c [dict get [lindex $items 0] content]
        if {[llength $c]} { set firstText [dict get [lindex $c 0] text] }
    }
    lappend lists [list [dict get $m kind] [dict get $m indentLevel] $firstText [llength $items]]
}

# expect three list blocks: ol@0(one), ol@1(two-a), ul@0(alpha)
ok {[llength $lists] == 3}                              "three list blocks read back"
ok {[lindex $lists 0 0] eq "ol"}                        "block0 kind = ol (was ol)"
ok {[lindex $lists 0 1] == 0}                           "block0 indentLevel 0"
ok {[lindex $lists 0 2] eq "one"}                       "block0 first item = one"
ok {[lindex $lists 1 0] eq "ol"}                        "block1 kind = ol (nested sublist)"
ok {[lindex $lists 1 1] == 1}                           "block1 indentLevel 1"
ok {[lindex $lists 1 2] eq "two-a"}                     "block1 first item = two-a"
ok {[lindex $lists 2 0] eq "ul"}                        "block2 kind = ul (was ul)"
ok {[lindex $lists 2 2] eq "alpha"}                     "block2 first item = alpha"

# and: every item meta.kind matches its block (item-level kind preserved)
set itemKindOk 1
foreach b $ir2 {
    if {[dict get $b type] ne "list"} continue
    set bk [dict get [dict get $b meta] kind]
    foreach it [dict get $b content] {
        if {[dict get [dict get $it meta] kind] ne $bk} { set itemKindOk 0 }
    }
}
ok {$itemKindOk} "item-level kind matches block kind"

puts "----"
puts "odt-ol: PASS $pass  FAIL $fail"
exit [expr {$fail > 0 ? 1 : 0}]
