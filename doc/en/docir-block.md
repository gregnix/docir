# docir::block — DocIR fragments into rectangles

`docir::pdf` flows a whole document across pages. `docir::block` does the
opposite: it places a DocIR fragment into a **fixed rectangle given in
millimetres**. That is what label, form and card layouts need — the geometry
comes from somewhere else (a layout editor, a template), and each rectangle is
filled independently.

```tcl
package require docir::block

set pdf [pdf4tcl::new %AUTO% -paper {54m 56m}]
$pdf startPage

docir::block::pdf $pdf $ir -x 3 -y 39 -w 30 -h 14 -size 8
;# -> used 8.043  lines 2  overflow 0  truncated 0

$pdf write -file label.pdf
$pdf destroy
```

## Commands

### `docir::block::pdf pdfobj ir ?-option value ...?`

Renders `ir` into the rectangle and returns a dict:

| Key | Meaning |
|---|---|
| `used` | height actually consumed, in mm |
| `lines` | number of text lines drawn |
| `overflow` | 1 if the content did not fit into `-h` |
| `truncated` | how many lines were dropped |

`used` is what an editor needs for auto-sizing a block; `overflow` is what it
needs to warn the user before printing.

### `docir::block::measure pdfobj ir ?-option value ...?`

Same call, same return value, but nothing is drawn. Use it to compute a page
length before creating the real document — see *Two passes* below.

## Options

| Option | Default | Meaning |
|---|---|---|
| `-x` `-y` | 0 | top-left corner of the rectangle, mm |
| `-w` | 50 | width, mm — the line break happens against this |
| `-h` | 0 | height, mm. `0` means unbounded: no overflow check |
| `-size` | 9 | base font size in **points** |
| `-font` | Helvetica | base family |
| `-mono` | Courier | family for `code` and `pre` |
| `-leading` | 1.25 | line spacing as a factor of the font size |
| `-align` | left | `left`, `center`, `right` |
| `-paraskip` | 0.35 | gap after a block, as a factor of the font size |
| `-clip` | 1 | drop lines that do not fit instead of drawing past `-h` |
| `-dryrun` | 0 | measure only |
| `-headscale` | see below | font size factor per heading level |
| `-bullet` | `• ` | list marker |
| `-indent` | 4 | list indent, mm |

`-headscale` defaults to `{1 1.6  2 1.4  3 1.25  4 1.1  5 1.0  6 1.0}`.

## Units: mm outside, points inside

Geometry is in millimetres, font sizes are in points.

This is not cosmetic. **pdf4tcl reads the font size in the unit configured on
the object.** With `-unit mm`, `setFont 9` means nine *millimetres* — roughly
26 points. A renderer that mixes millimetre geometry with a millimetre-configured
object produces type three times too large, and nothing reports it.

`docir::block` therefore requires an object in the default unit and refuses
anything else:

```tcl
set p [pdf4tcl::new %AUTO% -paper {54m 60m} -unit mm]
docir::block::pdf $p $ir -x 3 -y 3 -w 40
;# -> error: pdf4tcl object must use the default unit (points), found: mm.
;#    Font sizes would otherwise be read as millimetres.
```

## Supported IR

**Blocks:** `heading` (size by `meta level`), `paragraph`, `pre` (mono, 0.9×),
`list` / `listItem` (bullet + indent), `hr`, `blank`. `doc_meta` and
`doc_header` are skipped — `docir::md::fromAst` prepends both, and a block
renderer must not turn them into stray lines. Unknown block types are ignored
rather than raising.

**Inlines:** `text`, `strong`, `emphasis`, `underline`, `strike`, `code`,
`link` (drawn underlined), `linebreak`, `softbreak`, `span`.

Both inline forms are accepted: the flat one (`{type strong text "bold"}`,
which is what the IR spec uses) and the nested one
(`{type strong content {{type text text bold}}}`).

**Not renderable in a text box:** `image`, `math`, `footnote_ref`. These leave
a visible marker (`[image]`) instead of disappearing. In a label, silently
losing content is worse than an ugly placeholder.

## Two passes: let the content decide the size

Continuous label tape has no fixed length, so the sensible order is: measure
first, then create the page.

```tcl
# 1. measure on a throwaway document
set probe [pdf4tcl::new %AUTO% -paper {54m 300m}]
$probe startPage
set needed [docir::block::measure $probe $ir -x 3 -y 3 -w 48 -size 8]
$probe destroy

# 2. build the real one
set len [expr {int(ceil([dict get $needed used])) + 6}]
set pdf [pdf4tcl::new %AUTO% -paper [list 54m ${len}m]]
$pdf startPage
docir::block::pdf $pdf $ir -x 3 -y 3 -w 48 -size 8
```

With this, changing a font size no longer means adjusting the page length by
hand.

## Notes

**Measuring happens in the font that will be drawn.** Every word is measured
after `setFont` with its own style. Measuring bold text in the regular face
makes lines run past the box edge — the error is small per word and adds up
across a line.

**A dry run is not completely free.** Because measuring needs `setFont`,
pdf4tcl registers those fonts in the document's resource table. A measured
document is a few hundred bytes larger than an untouched one. No content is
emitted.

**Overflow is decided by the bottom of the line, not its baseline.** A line
whose baseline still sits inside the box but whose descenders and leading do
not is counted as overflow. Checking the baseline alone lets the last line
slip through unnoticed.

**List items are rendered recursively** and get the remaining height passed
down, so a list can overflow like any other block.

## Tests

`tests/test-docir-block.tcl`, 36 assertions. No Tk required — the module only
writes PDF, it does not rasterize.

```
tclsh tests/test-docir-block.tcl
```

## Example

`demo/demo-docirblock.tcl` builds a self-describing test label: dimensions,
resolution, printer, timestamp, a printed millimetre scale for checking the
physical size with a ruler, and a frame 1 mm from the edge that reveals
lateral clipping.
