# DocIR — TODO

Planning / backlog. No commitment — "later."

## Sinks: OpenDocument spreadsheets (ODS) and drawings (ODG)

DocIR currently emits **document-form** output only. Its sinks are `txt`,
`md`, `html`, `nroff`, `pdf`, `svg`, `canvas`, `tile` and **`odt`**
(OpenDocument *Text*). There is **no** ODS (spreadsheet) or ODG (drawing)
sink.

Today, spreadsheet and drawing output is produced **directly** through the
`odf` library (`odf::sheet` → `.ods`, `odf::draw` → `.odg`), bypassing
DocIR — see the export planning in
[`tclutils/docs/todo-output.md`](../tclutils/docs/todo-output.md), which
notes flatly that this "cannot be done by DocIR" and routes it around the
hub.

**TODO — extend DocIR so the "one model → many sinks" promise also covers
spreadsheets and drawings**, so callers no longer have to drop out of the
IR for `.ods` / `.odg`:

- **`docir::odg`** (DocIR / SVG → ODG). The existing `docir::svg` sink is
  the natural bridge: map shapes and paths onto `odf::draw`
  (pages / shapes / paths). Lowest friction — a drawing is already close to
  DocIR's vector model. (Mirrors `tclutils` todo-output P2 #4:
  "Canvas / tkpath / SVG → `.odg`".)
- **`docir::ods`** (DocIR tables → ODS). DocIR already carries `table` /
  `tableRow` / `tableCell` blocks; map them onto `odf::sheet`
  (`addTable` + `addStringRow` / `addRow`, cell formats).
  **Caveat / scope:** a full spreadsheet (formulas, multiple sheets, number
  formats) is more than a document table. Keep this to **tabular export**,
  not a spreadsheet model — anything formula-driven stays with the `odf`
  / `ofcalc` stack.

Both would build on the `odf` library (exactly as `docir::odt` already
does) and stay **optional** (lazy `package require odf`, friendly failure
when the lib is absent), consistent with the rest of the export story.

## Other

- **Ordered lists (`ol`).** `docir::odtSource` maps every ODF list to `ul`;
  ordered-list detection from ODF list styles is not attempted. A real `ol`
  on import (and the matching list-style on export) is the one open semantic
  gap in the ODT round-trip.
