tcl::tm::path add ./
package require docir::odtSource

set file [lindex $argv 0]
if {$file eq ""} {
    puts "usage: tclsh test-odt-source.tcl file.odt"
    exit 1
}

set ir [docir::odtSource::fromOdt $file]

puts "BLOCKS: [llength $ir]"
puts ""

foreach block $ir {
    puts [dict get $block type]
    puts "  meta: [dict get $block meta]"
    puts "  content: [dict get $block content]"
    puts ""
}