# ODT support in DocIR

DocIR reads and writes OpenDocument Text (`.odt`). ODT is **bidirectional**:
a source (`docir::odtSource`, ODT → DocIR) and a sink (`docir::odt`,
DocIR → ODT). A full round-trip `ODT → DocIR → ODT → DocIR` is
byte-identical at the DocIR level for the test corpus, images included.

```
.odt ──→ odf (odf::Package/odf::Text) ──→ docir::odtSource ──→ DocIR ──→ docir::odt ──→ .odt
         (odf repo)                       (this repo)                  (this repo)
```

## Layers

Reading and writing both build on the **`odf`** library (separate repo:
`odf::Package`, `odf::Text`, `odf::Styles`):

- **`odf`** (separate repo) — generic ODF container + content model: opens
  the ZIP, parses `content.xml`/`styles.xml`, resolves styles, and packs a
  conformant ODF 1.3 package. Knows the ODF format, **not** DocIR.
- **`docir::odtSource`** (here) — maps an opened ODT to semantic DocIR using
  `odf::Text` (blocks, runs, style registry) plus plain tdom. Depends on
  `odf::text` + `tdom`; **no** `odtread`.
- **`docir::odt`** (here) — serialises DocIR back to an ODF package via
  `odf` and writes the `.odt`.

## API

```tcl
package require docir::odtSource   ;# import (pulls odf::text + tdom)
package require docir::odt         ;# export (uses odf)

# ODT -> DocIR  (opens the package via odf::Package internally)
set ir [docir::odtSource::fromOdt path.odt]

# DocIR -> ODT  (images embedded via the media option)
docir::odt::write $ir out.odt [list media $urlToBytes]
```

`media` is a dict `url → bytes`. The image `url` in DocIR stays portable
(`Pictures/…`); the caller supplies the bytes. For `ODT → ODT` get them
by reading the source's image parts via `odf::Package` (the `Pictures/*`
parts); for `Tk → ODT` they come from `docir::tkSource::media`.

## Interpretation decisions (import)

Semantic, not visual — in the spirit of "no CSS in DocIR":

- `text:h` outline-level → `heading` level; `text:p` → `paragraph`.
- Monospace-styled paragraph → `pre` (kind `code`).
- Bold → `strong`, italic → `emphasis`, monospace run → inline `code`
  (precedence `code > strong > emphasis`); `text:span` → `span` (class).
- Lists are emitted as `ul` (ODF list level is structural, not semantic);
  on **import** (odtSource) nested lists are flattened to trailing `list`
  blocks with `indentLevel + 1`. The **renderer** also honours the nested
  form produced by `mdSource` — a sub-list carried inside a list item's
  `blocks` is emitted as a real nested `text:list` (`addSublist`). Non-list
  item blocks (indented code, block quotes) render flat (there is no in-item
  ODF paragraph slot in the current `odf::text` API), so they are not lost.
- Tables: if there is no explicit `table:table-header-rows`, the first
  row is marked as header (heuristic).
- Text alignment is dropped (visual, not semantic).

## Nested-list reconstruction (export)

`docir::odt` rebuilds ODF list nesting from the flat `indentLevel`
sequence so that re-import yields the identical flat DocIR. Note this is
round-trip-identical, **not** visually faithful to an arbitrary original:
the **odtSource** flat list model does not store which sub-list belonged to
which parent item, so that association is not recoverable from an
odtSource-imported document. (IR produced by `mdSource` *does* carry that
association in the item's `blocks`; the limitation is specific to the odt
import path.)

## Round-trip

`ODT → DocIR → ODT → DocIR` is byte-identical at the DocIR level for all
test documents, including embedded images. Test:
`tests/odt-roundtrip-test.tcl`.

## Limits

- Visual formatting (fonts, colours, alignment, page geometry) is not
  represented — DocIR is semantic.
- The list parent-item association is lost for **odt-imported** documents
  (odtSource flat list model, see above); IR from `mdSource` keeps it in
  the item's `blocks`.
