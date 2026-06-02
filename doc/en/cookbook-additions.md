# Cookbook additions (append to doc/en/cookbook.md)

## ODT → DocIR → other formats

```tcl
package require odt
package require docir::odtSource
package require docir::md

set ir [docir::odtSource::fromOdt input.odt]
set md [docir::md::render $ir]
```

## DocIR → ODT (with images)

```tcl
package require docir::odt
# media: dict url -> bytes (image bytes the caller provides)
docir::odt::write $ir out.odt [list media $media]
```

## ODT → DocIR → ODT (round-trip, images carried over)

```tcl
package require odt
package require docir::odtSource
package require docir::odt

set ir   [docir::odtSource::fromOdt in.odt]
# Bild-Bytes aus der Quelle holen (url -> bytes)
set urls {}
foreach b $ir { if {[dict get $b type] eq "image"} { lappend urls [dict get $b meta url] } }
set media [expr {[llength $urls] ? [odt::_slurp in.odt $urls] : {}}]

docir::odt::write $ir out.odt [list media $media]
```

## HTML → DocIR → PDF (website to PDF)

```tcl
package require docir::htmlSource
package require docir::pdf            ;# requires pdf4tcl

set fh [open page.html]; fconfigure $fh -encoding utf-8
set html [read $fh]; close $fh

set ir [docir::htmlSource::fromHtml $html]
docir::pdf::render $ir page.pdf
```

## Tk text widget → ODT (export what is in the widget)

```tcl
package require docir::tkSource
package require docir::odt

set ir    [docir::tkSource::fromWidget .t]      ;# or .t i1 i2 for a range
set media [docir::tkSource::media]
docir::odt::write $ir out.odt [list media $media]
```

Note: reading a Tk widget is lossy for structured blocks — the renderer
shows tables/lists as text, so they come back as paragraphs; link targets
are lost. For structure-preserving export, feed the DocIR to `docir::odt`
directly rather than via the widget.
