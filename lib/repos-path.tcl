# repos-path.tcl -- unified module-path bootstrap for the docir ecosystem.
#
# docir's ODT pipeline needs the `odf` packages, its Markdown bridge needs
# `mdstack`, and the man-page source needs `nroffparser` (man-viewer). Those
# live in sibling repositories, not inside docir. Every entry point (bin tools,
# tests, demos) needs them on the path the same way -- this script is that one
# place.
#
# Usage (from a bin tool, test, or demo):
#     source [file join <docir-repo>/lib repos-path.tcl]
# or, relative to a script in tests/ or bin/:
#     source [file join [file dirname [info script]] .. lib repos-path.tcl]
#
# It is idempotent and adds only paths that actually exist (missing repos simply
# stay missing -- "no magic": a package that is not installed will fail to load
# loudly at `package require`, not be silently faked).

namespace eval ::docir::reposPath {
    # repo name -> module subdirectories to register (relative to the repo root).
    # A repo root is registered on auto_path (so its pkgIndex.tcl bridge is used)
    # and each listed subdir is added to tcl::tm::path.
    variable layout {
        docir       {lib/tm}
        odf         {. odf}
        mdstack     {lib lib/tm}
        man-viewer  {lib lib/tm}
        manviewer   {lib lib/tm}
    }

    proc add {} {
        variable layout
        # docir repo root = parent of the lib/ directory holding this script
        set here [file dirname [file normalize [info script]]]
        set docirRoot [file dirname $here]
        set parent [file dirname $docirRoot]

        # candidate roots for each repo: dev-tree sibling, then installed trees
        set homes [list]
        if {[info exists ::env(HOME)]} { lappend homes [file join $::env(HOME) lib tcltk] }
        lappend homes /usr/local/lib/tcltk /usr/lib/tcltk

        foreach {repo subdirs} $layout {
            set roots [list [file join $parent $repo]]
            foreach h $homes { lappend roots [file join $h $repo] }
            # docir itself: also the repo we live in
            if {$repo eq "docir"} { lappend roots $docirRoot }

            foreach root $roots {
                if {![file isdirectory $root]} { continue }
                AddAuto $root
                foreach sub $subdirs {
                    set d [file normalize [file join $root $sub]]
                    if {[file isdirectory $d]} { AddTm $d }
                }
            }
        }
        return
    }

    proc AddTm {dir} {
        set dir [file normalize $dir]
        # tcl::tm::path refuses a path that is nested with an already-registered
        # one ("X is subdirectory of existing module path Y"). Skip such paths --
        # the parent entry already covers them, and odf's submodules are reached
        # through its pkgIndex.tcl on auto_path anyway.
        foreach e [::tcl::tm::path list] {
            set e [file normalize $e]
            if {$dir eq $e || [string match "$e/*" $dir] || [string match "$dir/*" $e]} {
                return
            }
        }
        catch {::tcl::tm::path add $dir}
    }
    proc AddAuto {dir} {
        set dir [file normalize $dir]
        if {$dir ni $::auto_path} { lappend ::auto_path $dir }
    }
}

::docir::reposPath::add
