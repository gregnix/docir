#!/usr/bin/env tclsh
# diag-flow-pdf.tcl -- in DEINER Umgebung ausfuehren, Ausgabe schicken.
# Prueft die flow->PDF-Kette Schritt fuer Schritt OHNE catch, damit der
# echte Fehler sichtbar wird (statt still in die Code-Box zu fallen).

proc ok  {m} { puts "  ok   $m" }
proc bad {m} { puts "  FAIL $m" }

puts "Tcl: [info patchlevel]"
puts "tcl::tm::path:"
foreach p [tcl::tm::path list] { puts "    $p" }
puts ""

# 1) Pakete laden
puts "1) package require"
foreach pkg {docir::pdf tclutils::common tclutils::tupngdraw \
             tclutils::tusvg tclutils::tudiagram tclutils::tuflow \
             pdf4tcl pdf4tcllib} {
    if {[catch {package require $pkg} v]} { bad "$pkg : $v" } else { ok "$pkg $v" }
}
puts ""

# 2) Ist der PDF-Renderer wirklich der gepatchte?
puts "2) gepatchte pdf-0.2.tm geladen?"
if {[llength [info procs ::docir::pdf::_renderFlowBlock]]} {
    ok "_renderFlowBlock vorhanden -> Patch aktiv"
} else {
    bad "_renderFlowBlock FEHLT -> es ist die ALTE pdf-0.2.tm (ohne flow-Hook)"
}
catch {puts "  geladen via: [package ifneeded docir::pdf [package provide docir::pdf]]"}
puts ""

# 3) tuflow parsen (ungefangen)
puts "3) tuflow::parse"
set src "flowchart LR\n  A\[Start\] --> B\{Go\}\n  B --> C(End)"
if {[catch {set model [::tclutils::tuflow::parse $src]} e]} {
    bad "tuflow::parse : $e"
} else {
    ok "parse -> [dict size $model] keys"
}
puts ""

# 4) tudiagram -> PNG (ungefangen) -- haeufigster stiller Fehlerpunkt
puts "4) tudiagram::toPng"
if {[info exists model]} {
    if {[catch {set png [::tclutils::tudiagram::toPng $model]} e]} {
        bad "tudiagram::toPng : $e"
    } else {
        ok "toPng -> [string length $png] bytes"
    }
}
puts ""

# 5) pdf4tcl: addImage -type png + putImage (ungefangen)
puts "5) pdf4tcl addImage/putImage"
if {[info exists png]} {
    if {[catch {
        set ch [file tempfile tmp]; fconfigure $ch -translation binary
        puts -nonewline $ch $png; close $ch
        set pdf [::pdf4tcl::new %AUTO% -paper a4]
        $pdf startPage
        set id [$pdf addImage $tmp -type png]
        $pdf putImage $id 50 50 -width 200
        $pdf destroy
        file delete $tmp
    } e]} {
        bad "addImage/putImage : $e"
    } else {
        ok "addImage -type png + putImage funktionieren"
    }
}
puts "\n--> Die erste FAIL-Zeile ist die Ursache."
