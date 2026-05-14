#!/usr/bin/env wish
# canvas_demo.tcl — DocIR auf ein Tk-Canvas rendern (Demo)
#
# Standard: echte Tk-Manpage canvas.n aus dem Markdown-Baum (nroff → DocIR → Canvas),
#   Suchreihenfolge: tcltk-manindex/manpages-nroff/ → src/manpages-nroff/ →
#   src/doc/tk/doc/ → src/tk/tk/doc/ → zuletzt demo/canvas.n als Fallback.
#   Voraussetzung: man-viewer als Sibling von docir (../man-viewer/.../nroffparser-0.2.tm).
#
# Aufruf:
#   wish demo/canvas_demo.tcl
#   wish demo/canvas_demo.tcl /abs/pfad/zu/foo.n
#   wish demo/canvas_demo.tcl foo.n          ;# Datei in demo/ suchen
#   wish demo/canvas_demo.tcl --builtin      ;# eingebautes Mini-DocIR statt .n
#
encoding system utf-8

# ---- Repo-Pfade ----
set demoDir   [file dirname [file normalize [info script]]]
set docirRoot [file dirname $demoDir]
set libTm     [file join $docirRoot lib tm]
lappend auto_path $libTm

package require docir
package require docir::canvas

# Quelle der IR (für Fenstertitel / Hinweiszeile)
set ::docir_demo_source {builtin}

# ---- nroffparser (wie demo/quickstart.tcl + fester Pfad man-viewer) ----
proc findNroffparser {docirRoot} {
    set markdownDir [file dirname $docirRoot]
    set explicit [file join $markdownDir man-viewer lib tm nroffparser-0.2.tm]
    if {[file exists $explicit]} { return $explicit }
    foreach base [list $markdownDir [file dirname $markdownDir]] {
        foreach pat {man-viewer man-viewer*} {
            foreach d [glob -nocomplain -directory $base -type d $pat] {
                foreach inner [list $d [file join $d man-viewer]] {
                    set tm [file join $inner lib tm nroffparser-0.2.tm]
                    if {[file exists $tm]} { return $tm }
                }
            }
        }
    }
    return ""
}

proc loadNroffStack {} {
    global docirRoot
    set npath [findNroffparser $docirRoot]
    if {$npath eq ""} {
        return -code error "nroffparser-0.2.tm nicht gefunden (man-viewer als Sibling?)"
    }
    if {[info commands ::debug::scope] eq ""} {
        namespace eval ::debug {
            proc scope {args} {}
            proc log {args} {}
            proc level {args} { return 0 }
            proc getLevel {args} { return 0 }
            proc startTimer {args} {}
            proc stopTimer {args} {}
            proc traceLine {args} {}
        }
    }
    source -encoding utf-8 $npath
    package require docir::roffSource
}

proc docIRFromNroffFile {path} {
    loadNroffStack
    set fh [open $path r]
    fconfigure $fh -encoding utf-8
    set nroff [read $fh]
    close $fh
    set ast [nroffparser::parse $nroff $path]
    docir::roff::fromAst $ast
}

source -encoding utf-8 [file join $demoDir canvas_demo_data.tcl]
proc builtinDemoIR {} {
    ::docir_demo::canvasBuiltinIR
}

proc resolveNroffPath {arg demoDir} {
    if {$arg eq ""} { return "" }
    if {[file exists $arg]} {
        return [file normalize $arg]
    }
    set rel [file join $demoDir $arg]
    if {[file exists $rel]} {
        return [file normalize $rel]
    }
    return ""
}

proc findUpstreamCanvasN {docirRoot demoDir} {
    set md [file dirname $docirRoot]
    foreach p [list \
            [file join $md tcltk-manindex manpages-nroff canvas.n] \
            [file join $md src manpages-nroff canvas.n] \
            [file join $md src doc tk doc canvas.n] \
            [file join $md src tk tk doc canvas.n] \
            [file join $demoDir canvas.n]] {
        if {[file exists $p]} {
            return [file normalize $p]
        }
    }
    return ""
}

proc resolveIR {} {
    global argv docirRoot demoDir
    if {[llength $argv] >= 1} {
        set a0 [lindex $argv 0]
        if {$a0 eq "--builtin" || $a0 eq "-builtin"} {
            set ::docir_demo_source {builtin}
            return [builtinDemoIR]
        }
        set f [resolveNroffPath $a0 $demoDir]
        if {$f eq ""} {
            return -code error "nroff-Datei nicht gefunden: $a0 (auch nicht unter $demoDir)"
        }
        set ::docir_demo_source $f
        return [docIRFromNroffFile $f]
    }
    set def [findUpstreamCanvasN $docirRoot $demoDir]
    if {$def ne ""} {
        set ::docir_demo_source $def
        return [docIRFromNroffFile $def]
    }
    set ::docir_demo_source {builtin}
    return [builtinDemoIR]
}

# ---- UI ----
set ir [resolveIR]
set verr [docir::validate $ir]
if {$verr ne {}} {
    puts stderr "DocIR validate: $verr"
}

if {$::docir_demo_source eq "builtin"} {
    wm title . {DocIR — Canvas-Demo (eingebautes IR)}
} else {
    wm title . "DocIR — Canvas-Demo ([file tail $::docir_demo_source])"
}

frame .bar -bd 0 -pady 4
pack .bar -side top -fill x
label .bar.hint -textvariable ::hint -anchor w
pack .bar.hint -side left -expand 1 -fill x
button .bar.reload -text {Neu zeichnen} -command redraw
pack .bar.reload -side right -padx 4

if {$::docir_demo_source eq "builtin"} {
    if {[llength $argv] >= 1 && ([lindex $argv 0] eq "--builtin" || [lindex $argv 0] eq "-builtin"])} {
        set hint {Quelle: eingebautes IR (--builtin)}
    } else {
        set hint {Quelle: eingebautes IR — keine canvas.n unter ../tcltk-manindex, ../src/ oder demo/ gefunden}
    }
} else {
    set hint "Quelle: $::docir_demo_source  |  builtin: wish [file tail [info script]] --builtin"
}

frame .f
pack .f -side top -expand 1 -fill both
canvas .f.c -width 720 -height 520 -bg white -highlightthickness 1 -highlightbackground gray70
scrollbar .f.sy -orient vertical -command {.f.c yview}
.f.c configure -yscrollcommand {.f.sy set}
grid .f.c .f.sy -sticky nsew
grid rowconfigure .f 0 -weight 1
grid columnconfigure .f 0 -weight 1

proc redraw {} {
    global ir
    docir::canvas::clear .f.c
    update idletasks
    docir::canvas::render .f.c $ir [dict create width 720 margin 18 fontSize 12]
}

bind .f.c <MouseWheel> {
    .f.c yview scroll [expr {-(%D/120)}] units
}
bind .f.c <Button-4> {.f.c yview scroll -1 units}
bind .f.c <Button-5> {.f.c yview scroll 1 units}

redraw

# tclsh beendet das Programm nach dem Skript sonst sofort (Fenster blitzt nur).
# wish bleibt ohnehin im Eventloop — hier nichts tun.
set _exe [file tail [info nameofexecutable]]
if {[string match -nocase *tclsh* $_exe] && ![string match -nocase *wish* $_exe]} {
    tkwait window .
}
