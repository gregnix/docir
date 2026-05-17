# util-0.1.tm -- Allgemeine Helper fuer den DocIR-Stack
#
# Aktuell enthaelt: plattformunabhaengiges Temp-Verzeichnis.
#
# Public API:
#   docir::util::tmpdir
#       Liefert einen Pfad auf ein schreibbares Temp-Verzeichnis.
#       Such-Reihenfolge:
#         1. $TMPDIR     (POSIX: Linux, macOS, BSD)
#         2. $TEMP       (Windows primary)
#         3. $TMP        (Windows fallback)
#         4. /tmp        (Linux/Unix wenn keine env-Var)
#         5. [pwd]       (Last resort)
#
#   docir::util::mktmpdir name
#       Erstellt ein neues Sub-Verzeichnis im Temp-Dir. Name wird mit
#       Process-ID suffixiert, um Kollisionen bei parallelen Lauefen
#       zu vermeiden. Returnt absoluten Pfad.
#       Beispiel:
#           set d [docir::util::mktmpdir test-pdf]
#           # -> /tmp/test-pdf-12345    bzw. C:\Users\...\Local\Temp\test-pdf-12345
#
# Use cases:
#   - Tests die Temp-Files brauchen (Cross-Platform Linux/Windows/macOS)
#   - Beliebige Code-Pfade die einen schreibbaren Temp-Pfad brauchen
#
# Anti-Pattern (was nicht zu tun ist):
#   set tmpBase /tmp                          ;# Linux-only
#   set tmpBase $::env(HOME)/tmp              ;# Win nicht, restricted Linux
#   file mkdir "/tmp/mytest"                  ;# kein cross-platform
#

package provide docir::util 0.1
package require Tcl 8.6-

namespace eval ::docir::util {
    namespace export tmpdir mktmpdir
}

proc ::docir::util::tmpdir {} {
    foreach var {TMPDIR TEMP TMP} {
        if {[info exists ::env($var)] && $::env($var) ne ""} {
            set dir $::env($var)
            if {[file isdirectory $dir] && [file writable $dir]} {
                return $dir
            }
        }
    }
    if {[file isdirectory /tmp] && [file writable /tmp]} { return /tmp }
    return [pwd]
}

proc ::docir::util::mktmpdir {name} {
    set dir [file join [tmpdir] "${name}-[pid]"]
    file mkdir $dir
    return $dir
}
