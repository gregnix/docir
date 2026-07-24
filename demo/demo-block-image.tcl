#!/usr/bin/env tclsh
# demo-block-image.tcl -- image and diagram blocks with docir::block
#
# Shows the two non-text block kinds side by side with text:
#
#   text      Markdown -> mdstack::parser -> docir::md::fromAst
#   image     PNG or JPEG, embedded by pdf4tcl
#   SVG       rasterized by Tk 9 first (docir::block stays Tk-free)
#   diagram   docir::diagram::renderPng -> PNG bytes
#
# Self-contained on purpose: the PNG and the SVG are generated here, so the
# demo needs no assets. A demo that depends on someone's logo file is a demo
# that does not run.
#
## Run from inside the docir repo:
##     tclsh demo/demo-block-image.tcl
## Extra packages that are not part of the docir tree:
##     export LD_LIBRARY_PATH=/path/to/tclpdfium/vendor/pdfium-linux-x64/lib
##     export TCLLIBPATH="/path/to/tclpdfium /path/to/pdf4tcl/pkg"
## Tk is loaded (SVG rasterizing and the PDF preview both need a photo),
## so a display must be reachable. The trailing `exit` is required.
##
## The SVG block needs an svg photo format: built into Tk 8.7 and later, or
## the tksvg extension under 8.6. Without either, that one block is skipped
## and the demo still runs.

package require Tk
wm withdraw .
fconfigure stdout -encoding utf-8
package require Tcl 8.6-
source [file join [file dirname [file normalize [info script]]] .. lib repos-path.tcl]
package require docir::block
package require docir::diagram
package require docir::mdSource
package require mdstack::parser
package require pdfiumtcl

set TMP [expr {[info exists env(TMPDIR)] ? $env(TMPDIR) : "/tmp"}]
set BAND 54
set WPX  590          ;# printable width of a 54 mm tape at 300 dpi

# ---------------------------------------------------------------- assets
# A tiny PNG drawn programmatically: a filled square with a lighter notch,
# just enough to be recognizable on the label.
proc makePng {path {size 64}} {
    set img [image create photo -width $size -height $size]
    $img put black -to 0 0 $size $size
    set inset [expr {$size/4}]
    $img put white -to $inset $inset [expr {$size-$inset}] [expr {$size-$inset}]
    $img put black -to [expr {$size/2}] [expr {$size/2}] \
                       [expr {$size-$inset}] [expr {$size-$inset}]
    $img write $path -format png
    image delete $img
    return $path
}

# SVG is text, so it can be written directly. Tk 9 rasterizes it natively;
# pdf4tcl cannot, which is why the conversion happens here and not in the
# module.
proc makeSvg {path} {
    set fh [open $path w]
    fconfigure $fh -encoding utf-8
    puts $fh {<svg xmlns="http://www.w3.org/2000/svg" width="120" height="60">}
    puts $fh {  <rect x="1" y="1" width="118" height="58" fill="none"}
    puts $fh {        stroke="black" stroke-width="2"/>}
    puts $fh {  <circle cx="30" cy="30" r="18" fill="black"/>}
    puts $fh {  <path d="M60 45 L75 15 L90 45 Z" fill="black"/>}
    puts $fh {</svg>}
    close $fh
    return $path
}

# Two ways to get an SVG photo:
#   Tk 8.7+   built in
#   Tk 8.6    the tksvg extension, which registers the same photo format
# Tk 8.6 without tksvg reports `image file format "svg" is not supported`,
# which names the symptom and not the cause.
#
# Ask for the capability, not the version: tksvg makes 8.6 as capable as 9.0
# here, and a pure version check would refuse a perfectly usable setup.
proc svgSupported {} {
    if {![catch {package require Tk 8.7-}]} { return 1 }
    if {![catch {package require tksvg}]}   { return 1 }
    return 0
}

proc svgToPng {svg png} {
    if {![svgSupported]} {
        return -code error "Tk [package provide Tk] has no svg photo format.\
            Either use Tk 8.7 or later (built in), or install the tksvg\
            extension for 8.6, or convert the file yourself and pass the PNG."
    }
    set img [image create photo]
    if {[catch {$img read $svg -format svg} err]} {
        image delete $img
        return -code error "cannot rasterize $svg: $err"
    }
    # Write beside the target and rename: a reader never sees a half file.
    $img write $png.new -format png
    image delete $img
    file rename -force $png.new $png
    return $png
}

proc diagramToPng {source lang png} {
    # renderPng returns PNG *bytes*, not a file.
    set bytes [docir::diagram::renderPng $source $lang]
    set fh [open $png.new wb]
    puts -nonewline $fh $bytes
    close $fh
    file rename -force $png.new $png
    return $png
}

# ------------------------------------------------------------------ build
set pngFile [makePng      [file join $TMP demo-mark.png]]
set svgFile [makeSvg      [file join $TMP demo-mark.svg]]
# Do not abort on a missing feature: the other four blocks are unaffected,
# and a demo that dies at step three shows nothing.
if {[catch {set svgPng [svgToPng $svgFile [file join $TMP demo-mark-svg.png]]} err]} {
    puts "SVG block skipped: $err"
    puts ""
    set svgPng ""
}

set diagSrc "Wareneingang -> Pruefung\nPruefung -> Lager\nLager -> Versand"
if {[catch {set diagPng [diagramToPng $diagSrc flow \
                            [file join $TMP demo-flow.png]]} err]} {
    puts "diagram rendering failed: $err"
    puts "(the rest of the demo still runs)"
    set diagPng ""
}

# Helper: an image block is content-free, everything lives in meta.
proc imageBlock {url alt} {
    return [list [dict create type image content {} meta [list url $url alt $alt]]]
}
proc textBlock {md} {
    return [docir::md::fromAst [mdstack::parser::parse $md]]
}

# Geometry in mm, exactly what a layout editor would hand over.
set layout {
    title {x 3  y 3   w 48 h 8}
    mark  {x 3  y 13  w 14 h 14}
    logo  {x 20 y 13  w 31 h 14}
    flow  {x 3  y 30  w 48 h 30}
    note  {x 3  y 62  w 48 h 10}
}

set pdf [pdf4tcl::new %AUTO% -paper [list ${BAND}m 76m]]
$pdf startPage

puts [format "%-7s %-18s %8s %6s %s" block rect used lines note]
foreach {id r} $layout {
    switch -- $id {
        title { set ir [textBlock "# Warenfluss"] ; set opt {-size 11} }
        mark  { set ir [imageBlock $pngFile "PNG"] ; set opt {} }
        logo  {
            if {$svgPng eq ""} {
                set ir [textBlock "*(SVG needs Tk 8.7+ or tksvg)*"]
                set opt {-size 7}
            } else {
                set ir [imageBlock $svgPng "SVG"] ; set opt {-align right}
            }
        }
        flow  {
            if {$diagPng eq ""} {
                set ir [textBlock "*(diagram unavailable)*"] ; set opt {-size 7}
            } else {
                set ir [imageBlock $diagPng "flow"] ; set opt {}
            }
        }
        note  { set ir [textBlock "PNG, SVG und **flow** in einem Etikett"]
                set opt {-size 7} }
    }
    set res [docir::block::pdf $pdf $ir \
        -x [dict get $r x] -y [dict get $r y] \
        -w [dict get $r w] -h [dict get $r h] {*}$opt]
    puts [format "%-7s %-18s %8s %6s %s" $id \
        "[dict get $r x],[dict get $r y] [dict get $r w]x[dict get $r h]" \
        [dict get $res used] [dict get $res lines] \
        [expr {[dict get $res overflow] ? "scaled/clipped" : ""}]]
}

set out [file join $TMP demo-block-image.pdf]
$pdf write -file $out
$pdf destroy

# --------------------------------------------------------------- rasterize
set doc [pdfium::open $out]
lassign [pdfium::pagesize $doc 0] pw ph
pdfium::render $doc 0 -width $WPX -imagename ::page
set png [file join $TMP demo-block-image.png]
::page write $png -format png
pdfium::close $doc

puts ""
puts [format "page : %.1f x %.1f mm" $pw $ph]
puts [format "png  : %d x %d px" [image width ::page] [image height ::page]]
puts "pdf  : $out"
puts "png  : $png"
exit 0
