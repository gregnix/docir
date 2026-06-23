# docir::diag - central diagnostics policy for docir renderers
#
# A renderer that hits a *non-fatal* problem (e.g. a diagram block whose
# language is flow/tuflow/mermaid but does not render) reports it here instead
# of swallowing it in a silent `catch` or inventing a per-sink mechanism.
#
# One place decides the policy:
#   mode = warn    -> write to `chan` and keep going (code-box fallback)   [default]
#   mode = strict  -> re-throw, aborting the render (for tests / CI)
#   mode = silent  -> say nothing, just record
# Every report is recorded in an entries log regardless of mode, so a caller
# can ask afterwards "what failed?" (docir::diag::log).
#
# Usage in a renderer:
#   try {
#       package require tclutils::tuflow
#       ... render + embed ...
#   } on error {m o} {
#       docir::diag::report [dict get $o -errorcode] "flow/$lang: $m"
#   }

package require Tcl 8.6 9

namespace eval docir::diag {
    namespace export report reset log configure
    variable mode    warn    ;# warn | strict | silent
    variable chan    stderr  ;# output channel for warn mode ("" also silences)
    variable entries {}      ;# collected list of {code msg}
}

# Configure policy: -mode warn|strict|silent, -channel <chan>|""
proc docir::diag::configure {args} {
    variable mode
    variable chan
    foreach {k v} $args {
        switch -- $k {
            -mode {
                if {$v ni {warn strict silent}} {
                    throw {DOCIR DIAG MODE} "invalid -mode \"$v\" (warn|strict|silent)"
                }
                set mode $v
            }
            -channel { set chan $v }
            default  { throw {DOCIR DIAG OPT} "unknown option \"$k\"" }
        }
    }
    return
}

proc docir::diag::reset {} { variable entries; set entries {} }
proc docir::diag::log   {} { variable entries; return $entries }

# Report a non-fatal problem. `code` is an errorCode list (e.g. the upstream
# {TCLUTILS TUFLOW ...}); `msg` a human message. Always recorded; then acted on
# per `mode`.
proc docir::diag::report {code msg} {
    variable mode
    variable chan
    variable entries
    if {$code eq "" || $code eq "NONE"} { set code {DOCIR DIAG ERROR} }
    lappend entries [list $code $msg]
    switch -- $mode {
        strict { throw $code $msg }
        warn   { if {$chan ne ""} { catch {puts $chan "docir \[[join $code /]\]: $msg"} } }
        silent {}
    }
    return
}

package provide docir::diag 0.1
