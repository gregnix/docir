#!/usr/bin/env tclsh
# test-odt-ol2.tcl -- advanced ordered-list round-trips through ODT:
#   A) number format (1/a/A/i/I) survives DocIR -> ODT -> DocIR
#   B) a nested list WITHOUT its own text:style-name inherits the parent's
#      kind (LibreOffice writes nested lists this way)
#   C) Markdown ordered list -> ODT -> DocIR stays ol
#   D) HTML <ol> -> ODT -> DocIR stays ol

fconfigure stdout -encoding utf-8
package require Tcl 8.6
source [file join [file dirname [file normalize [info script]]] .. lib repos-path.tcl]
package require docir::odt
package require docir::odtSource
package require odf::text
package require odf::style

set pass 0; set fail 0
proc ok {b m} { if {[uplevel 1 [list expr $b]]} {incr ::pass; puts "ok   $m"} else {incr ::fail; puts "FAIL $m"} }

set out [file join [file dirname [file normalize [info script]]] out]; file mkdir $out

proc txt {s} { return [list [dict create type text text $s]] }
proc olItem {s} { return [dict create type listItem content [txt $s] meta [dict create kind ol term {}]] }

# collect list blocks (kind, indentLevel, numFormat, firstItemText) from an IR
proc lists {ir} {
    set res {}
    foreach b $ir {
        if {[dict get $b type] ne "list"} continue
        set m [dict get $b meta]
        set first ""; set items [dict get $b content]
        if {[llength $items]} {
            set c [dict get [lindex $items 0] content]
            if {[llength $c]} { set first [dict get [lindex $c 0] text] }
        }
        lappend res [list \
            [dict get $m kind] \
            [dict get $m indentLevel] \
            [expr {[dict exists $m numFormat] ? [dict get $m numFormat] : ""}] \
            $first]
    }
    return $res
}

# ---- A) number formats round-trip ----
set ir {}
lappend ir [dict create type doc_meta content {} meta [dict create irSchemaVersion 1]]
foreach fmt {1 a A i I} {
    lappend ir [dict create type list \
        meta [dict create kind ol indentLevel 0 numFormat $fmt] \
        content [list [olItem "fmt-$fmt-one"] [olItem "fmt-$fmt-two"]]]
}
set odtA [file join $out ol2-formats.odt]
docir::odt::write $ir $odtA
set back [lists [docir::odtSource::fromOdt $odtA]]
foreach fmt {1 a A i I} {
    set found ""
    foreach l $back { if {[lindex $l 3] eq "fmt-$fmt-one"} { set found $l } }
    ok {[lindex $found 0] eq "ol"}   "A: list fmt=$fmt is ol"
    ok {[lindex $found 2] eq $fmt}   "A: numFormat $fmt preserved"
}

# ---- B) nested list without style-name inherits ol ----
set pkg [odf::newTextDoc]
set sty [odf::Styles new $pkg]
$sty defineListStyle docir_ol -kind ordered
set t [odf::Text new $pkg]
set lo [$t appendList docir_ol]
set i1 [$t addListItem $lo "outer"]
set sub [$t addSublist $i1 ""]      ;# NO style on the nested list (LO-style)
$t addListItem $sub "inner"
$t flush; $sty flush
set odtB [file join $out ol2-nested.odt]
$pkg save $odtB
$t destroy; $sty destroy; $pkg destroy
set bl [lists [docir::odtSource::fromOdt $odtB]]
set outerB ""; set innerB ""
foreach l $bl {
    if {[lindex $l 3] eq "outer"} { set outerB $l }
    if {[lindex $l 3] eq "inner"} { set innerB $l }
}
ok {[lindex $outerB 0] eq "ol"}                 "B: outer list is ol"
ok {[lindex $innerB 0] eq "ol"}                 "B: nested list (no style-name) inherits ol"
ok {[lindex $innerB 1] == 1}                    "B: nested list indentLevel 1"

# ---- C) Markdown ordered list -> ODT -> DocIR ----
package require mdstack::parser
package require docir::mdSource
set irC [docir::md::fromAst [mdstack::parser::parse "1. one\n2. two\n"]]
set odtC [file join $out ol2-md.odt]
docir::odt::write $irC $odtC
set cl [lists [docir::odtSource::fromOdt $odtC]]
set olC ""; foreach l $cl { if {[lindex $l 0] eq "ol"} { set olC $l } }
ok {$olC ne "" && [lindex $olC 0] eq "ol"}      "C: md ordered list survives as ol through ODT"

# ---- D) HTML <ol> -> ODT -> DocIR ----
package require docir::htmlSource
set irD [docir::htmlSource::fromHtml "<ol><li>x</li><li>y</li></ol>"]
set odtD [file join $out ol2-html.odt]
docir::odt::write $irD $odtD
set dl [lists [docir::odtSource::fromOdt $odtD]]
set olD ""; foreach l $dl { if {[lindex $l 0] eq "ol"} { set olD $l } }
ok {$olD ne "" && [lindex $olD 0] eq "ol"}      "D: html <ol> survives as ol through ODT"

puts "----"
puts "odt-ol2: PASS $pass  FAIL $fail"
exit [expr {$fail > 0 ? 1 : 0}]
