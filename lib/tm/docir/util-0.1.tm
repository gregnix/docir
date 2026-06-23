# util-0.1.tm -- general helpers for the DocIR stack
#
# Currently contains: a platform-independent temp directory.
#
# Public API:
#   docir::util::tmpdir
#       Returns a path to a writable temp directory.
#       Search order:
#         1. $TMPDIR     (POSIX: Linux, macOS, BSD)
#         2. $TEMP       (Windows primary)
#         3. $TMP        (Windows fallback)
#         4. /tmp        (Linux/Unix when no env var)
#         5. [pwd]       (last resort)
#
#   docir::util::mktmpdir name
#       Creates a new sub-directory in the temp dir. The name is suffixed with
#       the process id to avoid collisions between parallel runs. Returns the
#       absolute path.
#       Example:
#           set d [docir::util::mktmpdir test-pdf]
#           # -> /tmp/test-pdf-12345    or  C:\Users\...\Local\Temp\test-pdf-12345
#
# Use cases:
#   - tests that need temp files (cross-platform Linux/Windows/macOS)
#   - any code path that needs a writable temp path
#
# Anti-pattern (what not to do):
#   set tmpBase /tmp                          ;# Linux-only
#   set tmpBase $::env(HOME)/tmp              ;# not Windows, restricted on Linux
#   file mkdir "/tmp/mytest"                  ;# not cross-platform
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

