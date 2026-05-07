# pkgIndex.tcl -- Wurzel-Bruecke
#
# Erlaubt das ganze Repo als Modul-Verzeichnis im auto_path zu nutzen:
# wenn ~/lib/tcltk/ in auto_path ist und das Repo unter
# ~/lib/tcltk/docir-X.Y.Z/ liegt, findet Tcl die Module via dieser
# Bruecke.
#
# Ohne die Bruecke wuerde Tcl nur die Wurzel scannen — aber pkgIndex.tcl
# liegt in lib/tm/. Die folgende Brücke leitet weiter.
set dir [file join $dir lib tm]
source [file join $dir pkgIndex.tcl]
