#!/usr/bin/env tclsh
# check-math.tcl -- warum wird md->pdf Math nicht gerendert?
# In DERSELBEN Umgebung wie deine Demo starten (gleiche ~/.tclshrc / tm-Pfade):
#   tclsh check-math.tcl

proc fileOf {pkg ver} {
    set f "?"
    catch {
        regexp {source\s+(?:-encoding\s+\S+\s+)?(\S+\.tm)} \
            [package ifneeded $pkg $ver] -> f
    }
    return $f
}

set v  [package require pdf4tcllib]
set pf [fileOf pdf4tcllib $v]
set hasRL [llength [info commands ::pdf4tcllib::math::renderLatex]]
puts "pdf4tcllib $v"
puts "  file: $pf"
puts "  renderLatex: $hasRL   (1 = neu/ok, 0 = ALTE Version!)"

set dv [package require docir::pdf]
set df [fileOf docir::pdf $dv]
set wired 0
if {$df ne "?" && [file exists $df]} {
    set fh [open $df]; set s [read $fh]; close $fh
    if {[string match *pdf4tcllib::math::measureLatex* $s]} { set wired 1 }
}
puts "docir::pdf $dv"
puts "  file: $df"
puts "  math-wiring: $wired   (1 = neu/ok, 0 = ALTE Version!)"

puts ""
if {$hasRL && $wired} {
    puts "=> Beide Dateien sind neu."
    puts "   Bleibt Math trotzdem Text? Dann ist es INLINE (\$...\$) -- das ist"
    puts "   noch NICHT verdrahtet. Nur DISPLAY (\$\$...\$\$) wird gerendert."
} else {
    puts "=> Mindestens eine Datei ist noch die ALTE."
    puts "   Ersetze sie an GENAU dem oben gezeigten Pfad."
    puts "   (Dual-Clone: du hast evtl. den anderen Klon aktualisiert.)"
}
