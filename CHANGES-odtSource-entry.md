## 2026-05-23 — ODT source for DocIR (docir::odtSource)

### Added

- **`lib/tm/docir/odtSource-0.3.tm`** — new DocIR source
  (`docir::odtSource`) that reads OpenDocument Text (`.odt`) and emits a
  validated DocIR block stream. Entry point:
  `docir::odtSource::fromOdt $path`. Depends on the external `odt`
  reader package (ZIP + content.xml/styles.xml parsing, style
  resolution, style registry) and `tdom`. With this the DocIR hub gains
  ODT as an input format alongside nroff and Markdown — ODT now renders
  to HTML, PDF, Markdown and plain text through the existing sinks
  without extra work.

  Mapping is **semantic, not visual**: resolved ODF style properties
  decide the DocIR type rather than being copied (DocIR carries no CSS).
  - `text:h` (outline-level N) → `heading` level 1..6, `id` = title slug
  - `text:p` → `paragraph`; monospace style → `pre` (kind code);
    empty → `blank`
  - spans → inlines by resolved property: `font-weight=bold` → `strong`,
    `font-style=italic` → `emphasis`, monospace → `code`, otherwise
    `span` with `class` = style name (precedence code > strong > emphasis)
  - `text:line-break` → `linebreak`, `text:a` → `link` (href),
    `text:s`/`text:tab` → spaces/tab
  - `table:table` → `table`/`tableRow`/`tableCell`; cell content is the
    inline content of the cell paragraphs (multiple paragraphs joined by
    `linebreak`); short rows are padded to the column count
  - `text:list` → `list` (kind `ul`); nested lists are emitted as
    trailing `list` blocks with higher `indentLevel` (flat DocIR model)
  - `draw:frame`/`draw:image` → standalone `image` block
    (`meta.url` = Pictures/…), lifted out of its host paragraph

### Assumptions (deliberate)

- Paragraph alignment (`text-align`) is dropped — DocIR is sink-near and
  has no paragraph alignment (only `class`).
- Lists are mapped as `ul`; ordered-list detection from ODF list styles
  is not attempted.
- Table header: explicit `table:table-header-rows` win; when absent, the
  first row is treated as the header (`hasHeader=1`,
  `tableRow.meta.kind=header`). Correct for virtually all generated ODTs.

### Compatibility

- Pure addition — no changes to existing DocIR modules or public APIs.
- All emitted IR passes `docir::validate`. Verified via a round-trip
  ODT → DocIR → {md, txt, html} over five test documents (headings,
  spans, code, multi-line text, tables, nested lists, images, full
  Unicode); all render clean.

---
