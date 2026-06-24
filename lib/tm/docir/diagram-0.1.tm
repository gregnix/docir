# diagram-0.1.tm -- central diagram-language seam for docir sinks.
#
# Single source of truth for (a) which fenced-code languages are diagrams and
# (b) the render dispatch to the tuflow facade. Every sink calls this instead of
# carrying its own copy of the language gate and the parse/render chain, so a
# new diagram family (e.g. pie) is added in ONE place, not in four sinks.
#
# Language policy:
#   native  {flow tuflow pie}  -- rendered through the tuflow facade (inline SVG
#                                 in HTML, embedded PNG in the raster sinks).
#   browser {mermaid}          -- HTML keeps these as <pre class="mermaid"> for
#                                 client-side mermaid.js; the raster sinks
#                                 (pdf/odt/tk) have no browser and render them
#                                 through the facade as well (best effort: the
#                                 facade understands the graph-like mermaid
#                                 types and throws UNSUPPORTED for the rest).
#
# Native-preferred mermaid subtypes: some inner diagram types render more
# reliably through the facade than through the browser's mermaid.js (e.g.
# `architecture-beta`, where mermaid.js 11.x is stricter than tuflow and may
# throw "Syntax error" on input the facade accepts). For a ```mermaid``` block
# whose first keyword is in `nativeMermaid`, an HTML sink can render natively
# (inline SVG, consistent with the PDF output) and fall back to <pre class=
# "mermaid"> only if the facade render fails. See `preferNative`.
#
# The render entry points are thin wrappers over the tuflow facade; the facade
# detects the diagram kind from the source, so the language argument is only
# carried for the caller's diagnostics. This module has NO catch: render errors
# ({TCLUTILS TUFLOW|TUDIAGRAM|TUPIE ...}, {TCL PACKAGE ...}) propagate to the
# calling sink, which wraps them in try/on error and hands the errorCode to
# docir::diag.
#
# Namespace: ::docir::diagram   Package: docir::diagram 0.1

package require Tcl 8.6-

namespace eval ::docir {}
namespace eval ::docir::diagram {
    variable native  {flow tuflow pie}
    variable browser {mermaid}
    # mermaid inner diagram types an HTML sink should render natively (facade)
    # instead of deferring to mermaid.js. Matched against the first keyword of
    # the source. These are types where mermaid.js 11.x is fragile or absent
    # while the facade renders them reliably: architecture-beta (lenient ids/
    # labels), mindmap (special chars / indentation), and the tclutils 2D
    # renderers kanban / packet-beta / treemap-beta / radar-beta (own engines,
    # not 1:1 with mermaid.js). Mature graph types (flowchart, sequence, state,
    # pie, er, class, gantt, ...) stay on mermaid.js where it renders them well.
    # Add a type here to move it from the browser to the native path; set the
    # list empty to defer every mermaid block, or see preferNative for an
    # all-native policy. Keep lowercase.
    variable nativeMermaid {
        architecture-beta architecture mindmap
        kanban packet-beta packet treemap-beta treemap radar-beta radar
    }
    namespace export \
        isDiagram isNative isBrowserPreferred preferNative languages \
        renderSvg renderPng
}

proc ::docir::diagram::_norm {lang} {
    return [string tolower [string trim $lang]]
}

# All recognised diagram languages (native plus browser).
proc ::docir::diagram::languages {} {
    variable native
    variable browser
    return [concat $native $browser]
}

# True if a sink that can rasterise should treat this fenced block as a diagram.
# Covers native and browser languages, because the raster sinks render both.
proc ::docir::diagram::isDiagram {lang} {
    return [expr {[_norm $lang] in [languages]}]
}

# True for languages rendered directly through the facade (inline SVG in HTML).
proc ::docir::diagram::isNative {lang} {
    variable native
    return [expr {[_norm $lang] in $native}]
}

# True for languages a browser sink prefers to defer to the client (mermaid.js).
proc ::docir::diagram::isBrowserPreferred {lang} {
    variable browser
    return [expr {[_norm $lang] in $browser}]
}

# First diagram keyword: first token of the first non-empty, non-comment line.
proc ::docir::diagram::_firstKeyword {source} {
    foreach line [split $source \n] {
        set t [string trim $line]
        if {$t eq "" || [string match {%%*} $t]} continue
        return [string tolower [lindex [split $t] 0]]
    }
    return ""
}

# True if an HTML sink should render this block natively (facade -> inline SVG)
# rather than defer to the browser. That is the case for a native language, or
# for a browser language whose inner diagram type is native-preferred (e.g. a
# ```mermaid``` block that begins with `architecture-beta` or `mindmap`). The
# sink should still fall back to its browser path if the facade render fails.
#
# For an all-native policy ("never depend on mermaid.js; render every diagram via
# tuflow, fall back to the browser only when the facade can't"), replace the
# `nativeMermaid` membership test below with `return [isBrowserPreferred $lang]`.
proc ::docir::diagram::preferNative {lang source} {
    if {[isNative $lang]} { return 1 }
    if {[isBrowserPreferred $lang]} {
        variable nativeMermaid
        return [expr {[_firstKeyword $source] in $nativeMermaid}]
    }
    return 0
}

# Keep only the options the tuflow facade understands.
proc ::docir::diagram::_facadeArgs {arglist} {
    set out {}
    foreach {k v} $arglist {
        if {$k in {-fontfile -scale -width -height -legend}} { lappend out $k $v }
    }
    return $out
}

# Render the diagram source to an SVG string. Options: -fontfile (ignored by the
# SVG backend), plus the pie-specific sizing options. lang is informational.
proc ::docir::diagram::renderSvg {source lang args} {
    package require tclutils::tuflow 0.2
    return [::tclutils::tuflow::toSvg $source {*}[_facadeArgs $args]]
}

# Render the diagram source to PNG bytes. Options: -fontfile <ttf>, -scale <int>,
# plus the pie-specific sizing options. lang is informational.
proc ::docir::diagram::renderPng {source lang args} {
    package require tclutils::tuflow 0.2
    return [::tclutils::tuflow::toPng $source {*}[_facadeArgs $args]]
}

package provide docir::diagram 0.1
