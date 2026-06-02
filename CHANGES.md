# DocIR — Changelog

## 2026-06-02 — Foreign-ODT lists, number formats, cross-format ol

### Changed

- **`lib/tm/docir/odtSource-0.4.tm`** — `_mapList` now inherits the kind
  (and number format) from the enclosing list when a nested `text:list`
  has no `text:style-name`. LibreOffice writes nested lists this way, so an
  ordered LO list no longer degrades to bullets at the inner levels.
- **`lib/tm/docir/odt-0.4.tm`** / **`odtSource-0.4.tm`** — ordered lists now
  carry a number format. The IR list block may set `meta.numFormat`
  (`1` / `a` / `A` / `i` / `I`); the sink defines one ordered list style per
  format (`docir_ol`, `docir_ol_a`, …) and references the right one, and the
  reader recovers it via the new `odf::style listStyleFormat`. Absent
  `numFormat` defaults to decimal, so Markdown/HTML ordered lists are
  unaffected.

### Added

- **`tests/test-odt-ol2.tcl`** — 15 checks: number-format round-trip
  (1/a/A/i/I), nested-list kind inheritance for a style-less sublist, and
  Markdown `1.` and HTML `<ol>` surviving as `ol` through the ODT hop. The
  generated ODTs validate clean against odfvalidator 0.13.0.

Requires `odf` 0.20 with `listStyleFormat` (and the hanging-indent list
styles).

## 2026-06-02 — Better-looking ODT (definition lists + styling)

### Fixed

- **`lib/tm/docir/mdSource-0.1.tm`** — `_mapDeflist` dropped every
  definition body. The parser emits `definitions` as a list of definition
  *groups* (each a flat inline list), but the mapper looked for a `content`
  sub-key on the first element, found none, and produced empty list items —
  rendering as a page full of empty bullets. Now maps the first group's
  inlines, so definition text survives.

### Changed

- **`lib/tm/docir/odt-0.4.tm`** — definition lists (`meta.kind == dl`) now
  render as a bold **term** paragraph followed by an indented definition
  paragraph (new `_fillDeflist`, styles `DefTerm` / `DefBody`), instead of
  bullet items. Heading styles got top/bottom spacing, `keep-with-next` and
  a dark colour; body paragraphs get spacing + line-height (`Body` style);
  code/pre blocks get a light background, indent and padding. The result
  reads like a proper man page rather than cramped flat text.

Known limitation: in the Tcl/Tk man pages, fenced code that is indented
underneath a definition is parsed by mdstack as an *indented* code block, so
the ``` fences appear literally and inline `**bold**` inside it stays raw.
That is mdstack parser semantics (4-space indent = code), not the sink.

## 2026-06-02 — md2odt CLI + safe dict-default lookups

### Added

- **`bin/md2odt`** — Markdown → ODT via the DocIR pipeline
  (`mdstack::parser` → `docir::mdSource` → `docir::odt`). Converts one
  `.md`, or combines several into a single `.odt` (one level-1 section per
  file). Same front end as `md2html`, ODT sink at the back; ordered lists
  come out numbered. Verified end-to-end on the Tcl/Tk 9.0 man-page corpus
  (221 files → one ODT, conformant under odfvalidator 0.13.0).

### Fixed

- **all DocIR sinks/sources** — dict lookups with a default were written as
  `[expr {[dict exists $d $k] ? [dict get $d $k] : DEF}]`. `expr`
  *evaluates* the substituted dict value as an expression, so a text/value
  string that looks like an out-of-range number (e.g. on the math man
  pages `expr.md`, `fpclassify.md`) threw "domain error: argument not in
  valid range". Replaced throughout with a non-evaluating per-namespace
  `_dictDef` helper (mdSource, md, odt, odtSource, html, pdf, svg, canvas,
  roff, roffSource, rendererTk, tilecommon, tilepdf — ~190 sites). Where a
  default was itself an expression (e.g. `$darkMode ? "#9cdcfe" : "#003366"`
  in rendererTk), it is wrapped in `[expr {...}]` so it still evaluates.
  Verified: headless suite 577/0, GUI tests (rendererTk 7/7, canvas) under
  Xvfb, and the full Tcl/Tk 9.0 man-page corpus (221/221 → ODT, conformant).

## 2026-06-02 — Ordered lists in the ODT pipeline

### Changed

- **`lib/tm/docir/odt-0.4.tm`** — the ODT sink now emits ordered lists
  as ordered, not just bullets. `_defineStyles` defines two named list
  styles (`docir_ol` ordered numbers, `docir_ul` bullets); the writer
  references the right one per list block via its `meta.kind` (`ol`/`ul`),
  for both top-level lists and nested sublists. Requires `odf` 0.20
  (`odf::style defineListStyle`).
- **`lib/tm/docir/odtSource-0.4.tm`** — the ODT reader now recovers a
  list's kind instead of assuming `ul`: it resolves the `text:list`'s
  `text:style-name` through `odf::style listStyleKind` and tags the
  block/items `ol` when the style numbers, `ul` otherwise (per level,
  so nested ordered sublists round-trip).

### Added

- **`tests/test-odt-ol.tcl`** — round-trips DocIR(ol/ul, incl. a nested
  ordered sublist) → ODT → DocIR and asserts the kind survives; the
  generated ODT validates clean against odfvalidator 0.13.0 (ODF 1.3).

(Module versions stay `docir::odt` / `docir::odtSource` 0.4 — behaviour
added, no API change: `appendList`/`addSublist` already accepted a style.)

### Fixed

- **`tests/test-framework.tcl`** — `assert {EXPR}` now evaluates its
  condition (`uplevel`/`expr`) instead of being treated as an already-
  resolved boolean. The old bridge passed the raw expression string to
  `::test::assert`'s `if {!$condition}`, which errored with "expected
  boolean value" whenever an `assert {EXPR}` actually ran — only visible
  under a real `$DISPLAY` (headless reported the file as 0/0). Surfaced by
  `test-docir-renderer-frame.tcl`, which is the only suite test using that
  form; it now passes (7/7 under Xvfb). No other behaviour change.

## 2026-05-16 — Plain-text sink, n2md CLI, math + mermaid in renderers

### Added

- **`lib/tm/docir/txt-0.1.tm`** — new plain-text sink (`docir::txt`).
  Seventh sink in the DocIR hub (after tk, html, md, svg, pdf, canvas).
  Renders blocks to clean plain text with word-wrap, ASCII tables,
  indented code blocks, `$$...$$` math blocks, `> ` blockquotes, and
  configurable options (`lineWidth`, `bulletChar`, `codeIndent`,
  `linkStyle`, `showImageUrls`).
- **`bin/n2md`** — new CLI that converts nroff to Markdown via the
  DocIR pipeline (nroffparser → roffSource → md). Locates
  nroffparser via `$NROFFPARSER_PATH`, sibling `../man-viewer/lib/tm`,
  or `~/lib/tcltk/man-viewer/lib/tm`. Exits with code 2 if any
  dependency is missing, with a clear error message.
- **`tests/test-docir-txt.tcl`** — 15 tests covering headings,
  paragraphs, lists, tables, code/math blocks, links, footnotes,
  images, and empty-doc-header skipping.

### Changed

- **`lib/tm/docir/mdSource-0.1.tm`** maps new mdparser AST nodes:
  - `math_block` → DocIR `pre` with `meta {kind math display 1}`
  - `math` inline → DocIR `math` inline with `display` flag
- **`lib/tm/docir/md-0.1.tm`** (sink):
  - `_renderPre` recognizes `kind=math` and renders as `$$...$$`
  - `_renderInline` renders `math` inline as `$...$` or `$$...$$`
- **`lib/tm/docir/html-0.1.tm`** (sink):
  - `_renderPre` recognizes `kind=math` → `<div class="math display">`
  - `_renderPre` recognizes `language=mermaid` → `<pre class="mermaid">`
    (instead of `<pre><code class="language-mermaid">`)
  - `_renderInline` renders `math` inline as
    `<span class="math inline|display">` (Pandoc/KaTeX/MathJax convention)
  - New render options: `enableMermaid` (default 0) and `enableMath`
    (default 0). When set, the renderer injects CDN script tags for
    mermaid.js / KaTeX in the document head. Strictly opt-in — no
    automatic network requests.

### Compatibility

- All existing tests pass (125/126, same pre-existing fail as before).
- No public API changes. New code paths trigger only on new AST node
  types (`math`, `math_block`) or new option keys (`enableMermaid`,
  `enableMath`). Existing consumers see identical output for
  identical input.

---

## 2026-05-14 — Documentation correction in md-0.1.tm

### Documentation

- **`lib/tm/docir/md-0.1.tm`** header comment updated. The previous
  text claimed that `docir::md` (sink) and `docir::mdSource` (source)
  could NOT be loaded simultaneously. In fact both coexist without
  issue since the split into separate packages — they write into the
  same namespace `::docir::md::*` but with disjoint procedures
  (`render` vs. `fromAst`). A Markdown → DocIR → Markdown roundtrip
  is therefore possible.

## 2026-05-14 — Robust font pipeline for older pdf4tcl versions

**Affected consumers:** no public API change. Callers that explicitly
set `Style(fontMode) strict` keep their behavior — only the default
changed from `strict` to `warn`.

### Fixed

- **`lib/tm/docir/tilepdf-0.1.tm`** — older pdf4tcl without
  `::pdf4tcl::createFontSpecCID` caused tests to crash. Resolution:
  - **Capability check before font loading.** `_setupFonts` now
    explicitly checks whether both required procs
    (`loadBaseTrueTypeFont` and `createFontSpecCID`) are available,
    and otherwise falls back cleanly to standard PDF fonts
    (Helvetica / Courier) instead of crashing at call time.
  - **Default `fontMode` changed from `strict` to `warn`.** A
    missing Unicode font pipeline is now a warning rather than an
    error; rendering continues with fallback fonts. Cheatsheet
    consumers preferring strict mode can opt in explicitly via
    `cheatsheet::setStyle fontMode strict`.

### Background

The 2026-05-14 test-runner report showed six failures in
`test-docir-pdf.tcl` and `test-docir-tilepdf.tcl` exclusively due to
`::pdf4tcl::createFontSpecCID`. The procedure is a newer addition in
pdf4tcl; systems with older versions (before CID-font support)
crashed without a capability check.

## 2026-05-13 — Canvas demo

**Affected consumers:** none. Demo and documentation addition only.

### Added

- **`demo/canvas_demo.tcl`** (193 LOC) — runnable demo showing the
  pipeline nroff → `docir::roffSource` → DocIR →
  `docir::canvas::render`. Searches for a real `canvas.n` in several
  standard paths (tcltk-manindex/manpages-nroff, src/manpages-nroff,
  src/doc/tk/doc, src/tk/tk/doc, demo/canvas.n), with a fallback to
  a built-in mini IR via `--builtin`.
- **`demo/canvas_demo_data.tcl`** (43 LOC) — IR data for the
  built-in mode (no Tk dependencies, procedures only).
- **`demo/canvas.n`** — Tk's `canvas(n)` manpage (87 KB) as a
  fallback source when no sibling `man-viewer` with a manpage corpus
  is present.

### Documentation

- **`README.md`** — new "Demos" section between "Regenerating
  pkgIndex.tcl" and "Tests".

## 2026-05-13 — Convergence with cheatsheets (tilepdf extension)

**Affected consumers:** the cheatsheets repo is converted to an
adapter in this session. Other consumers (man-viewer, mdstack,
mdhelp) are unaffected — only Added/Fixed, no API break.

### Added

- **`docir::csdSource 0.1`** (`lib/tm/docir/csdSource-0.1.tm`) —
  new DocIR source for the CSD format (Tcl-declarative cheatsheet
  definitions). Maps a CSD dict to a sheets list consumed by
  `docir::tilepdf::renderSheets`. Public API: `docir::csd::toSheet`,
  `docir::csd::toSheets`.

- **`docir::tilepdf::renderSheets`** — alternative public API
  alongside `render`. Accepts a prepared sheets list instead of a
  DocIR stream. Bypasses the schema check and
  `streamToSheets` classification. Used by the new cheatsheet
  adapter and the `csdSource` path.

- **`docir::tilehtml::renderSheets`** and **`docir::tilemd::renderSheets`** —
  analogous to tilepdf, giving the tile renderer family a consistent
  alternative API. `docir::csdSource` can now feed all three tile
  sinks (PDF / HTML / MD). For `tilehtml`, themes
  (`light` / `dark` / `auto` / `solarized` / `sepia`) and column count
  (1–4) are forwarded as options; for `tilemd`, the TOC option and
  `-hr`.

### Fixed (critical — ported from cheatsheet-0.1.tm)

- **Pagination bug in `docir::tilepdf::_renderSheet`/`_renderSection`:**
  - `_renderSection` took `y col` by value — could not split
    sections that span columns. Now uses `upvar yVar colVar`
    analogous to `cheatsheet-0.1.tm`.
  - Per-item column split in all six section types (table, code,
    code-intro, hint, list, image): pre-measure per row/line/item,
    on overflow `_col` switch and `(cont.)` section.
  - `max_iter=24` spinning loop in `_renderSheet` removed —
    replaced by a `minNeed` heuristic analogous to cheatsheet's
    `render`.
  - Constant `max_iter` removed from the `C` array.

  Before: sections longer than one column produced up to 12 blank
  pages plus truncated content. After: cleanly distributed
  per-item across columns.

### Added (Unicode font pipeline — ported from cheatsheet-0.1.tm)

- **`docir::tilepdf::_setupFonts`** — at PDF start, registers
  Unicode TTF fonts (UniSans / UniSansBold / UniSansOblique /
  UniMono) via `::pdf4tcl::loadBaseTrueTypeFont` +
  `::pdf4tcl::createFontSpecCID`.
- **`docir::tilepdf::_tryLoadFont`** and **`_fontProblem`** —
  robust against missing TTFs (searches through standard paths on
  Linux / macOS / Windows).
- **`Style(fontMode)`** with values `strict` (default, raise on
  font problem), `warn` (stderr warning + fallback to
  Helvetica / Courier), `silent` (silent fallback).
- **`F` array** with slots `prop` / `propBold` / `propOblique` /
  `mono`, replacing hardcoded `Helvetica` / `Helvetica-Bold` /
  `Courier` in `_header`, `_section`, `_row`, `_code`,
  `_listItem`, `_image`, `_fontFor`.

  Before: Unicode characters such as `→`, `←`, `…` did not render
  in the PDF (only ASCII via Helvetica / Courier). After: rendered
  correctly with DejaVu Sans / Mono when available.

### Benefits of this convergence

- Cheatsheets becomes an adapter — 459 fewer LOC to maintain.
- Bug fixes now apply to both paths (Markdown-tile and CSD-tile).
- Tile renderer features (themes, code-intro, image) are immediately
  available to CSDs.
- `tilehtml` and `tilemd` do not benefit from the pagination/font
  fix (HTML/MD have no pagination, and Unicode works in HTML/MD
  anyway) — the fix is `tilepdf`-only.

## 2026-05-13 — Repo hygiene + test setup fixes

**Affected consumers:** no API change; only repo cleanup, test
stability, and minor tooling improvements. Consumers (man-viewer,
mdstack, mdhelp) need no adjustments.

### Removed

- **`lib/tm/docir/pdf-0.1.tm.bak`** — old backup; the new version is
  `pdf-0.2.tm`. `.bak` added to `.gitignore`.
- **`tests/test-toc.pdf`** — test output was accidentally
  version-controlled (gitignore has `*.pdf`).

### Fixed

- **`lib/tm/pkgIndex.tcl`** — the entry for `docir::pdf 0.1` pointed
  at the no-longer-existing `pdf-0.1.tm`. Regenerated via
  `tools/generate-pkgindex.tcl` (now only `docir::pdf 0.2`).
- **`tests/test-setup.tcl`**:
  - `pdf-0.1.tm` (does not exist) replaced by `pdf-0.2.tm`.
  - `pdf-0.2.tm` and `tilepdf-0.1.tm` (both require external
    `pdf4tcl`) now sourced with `catch` — tests skip themselves
    instead of aborting with a stack trace.
  - `roff-0.1.tm` and `tilehtml-0.1.tm` added (were missing).
  - `tcl::tm::path add` so that `package require docir::*` also
    works from tests (needed by some tests).
- **`tests/run-all-tests.tcl`** — crashing test files now let the
  runner continue instead of aborting with "child process exited
  abnormally". Counted as one failure with a "(crashed)" marker.
- **`tests/test-validator.tcl`** — file-level skip when
  `nroffparser` is not installed (all 13 tests require it).

### Changed

- **`bin/md2tilepdf`, `md2tilehtml`, `md2tilemd`** — `-h`/`--help`
  is now evaluated **before** `package require`, so the help works
  even without installed dependencies (previously: stack trace).
  Plus a "Requires: ..." note in the usage line.

### Test status

Without external parsers (nroffparser / mdstack / pdf4tcl):
**473 of 509 tests passing**. With all dependencies installed:
up to 728 tests (per README, not verified in this cleanup session).

Failing test files without deps (all due to external parser calls
within individual tests):
`test-docir.tcl`, `test-docir-html.tcl`, `test-docir-svg.tcl`,
`test-docir-md.tcl`, `test-docir-roff.tcl`.

## 2026-05-07 — Spec consolidation, pkgIndex refactor, tile renderer family

### Spec & validation

- **DocIR 0.5: `irSchemaVersion`** as a required field on `doc_meta`
  (integer, currently `1`). The validator still accepts streams without
  a schema version (best-effort) but warns via the test suite.
- **Central schema-skip helper** `docir::checkSchemaVersion` — every sink
  calls it, and a missing `doc_meta` node no longer produces output
  (silently skipped).
- **AST/DocIR spec clarification**: the AST is parser-specific and may
  lose information on the way to DocIR; DocIR is the canonical form.
  Source modules may discard information from the AST.
- **Table structure unified**: `table.alignments` is a list of
  `left|center|right` per column. All sinks (html, md, pdf, roff,
  svg, canvas) now honour it consistently.
- **Bug fix**: `doc_meta` without `irSchemaVersion` was previously
  treated by HTML and MD sinks as a body node, producing empty
  `<div>`/blank lines. All sinks now skip `doc_meta` silently.
- **`list.indentLevel`** retrofitted as best-effort in the md, pdf,
  and roff sinks. Visual sinks (svg, canvas, tilepdf, tilehtml,
  tilemd) are marked best-effort in the spec.

### Tcl module refactor

- **Sub-directory layout**: `docir-roff-0.1.tm` → `docir/roff-0.1.tm`.
  Tcl module names now consistently `docir::roff` (no longer the
  hyphenated form).
- **Standard Tcl pkgIndex.tcl convention**: one `pkgIndex.tcl` per
  module directory, generated via `tools/generate-pkgindex.tcl`.
  Bootstrap helpers removed; standard `auto_path` mechanism used.
- **Makefile convention** in every repo: `install`, `install-user`,
  `install-bin`, `pkgindex`, `test`, `uninstall`. `make install`
  installs to `/usr/local/lib/tcltk/<repo>/`, no extra setup needed.
- **CamelCase sink/source names** where required: `docir::mdSource`,
  `docir::roffSource`, `docir::rendererTk` (because hyphens in module
  names confuse Tcl's version parser).
- **mdstack namespace refactor**: `::mdparser` → `::mdstack::parser`,
  `::mdtext` → `::mdstack::text`, etc. All 14 mdstack modules
  converted across roughly 432 files.

### Tile renderer family

Adapted from the `cheatsheet-0.1.tm` layout algorithm. Tile = two-column
cheatsheet style with atomic sections and a unified section-type
classification (`code`, `code-intro`, `hint`, `list`, `table`, `image`).

- **`docir::tilecommon`**: shared helper with `streamToSheets`,
  `packSection`, `tokenize`, `inlinesToText`, `fontFor`. Used by
  tilepdf, tilehtml, and tilemd.
- **`docir::tilepdf`**: PDF, two fixed columns, light/dark themes,
  mixed-font inline rendering (bold/italic/code visually distinct),
  images via `pdf4tcl::addImage` proportionally scaled.
- **`docir::tilehtml`**: HTML with CSS Grid plus `break-inside: avoid`
  for atomic tiles, 1–4 columns, five themes
  (light/dark/auto/solarized/sepia), TOC for multi-sheet output, real
  `<a href>` links, print CSS.
- **`docir::tilemd`**: linearly structured Markdown (Markdown is
  linear, no two-column layout possible). Section type remains
  recognisable via code fences, blockquotes, MD tables, etc.
- **CLI tools**: `bin/md2tilepdf`, `bin/md2tilehtml`, `bin/md2tilemd`.

### Drift audit

`tools/drift-audit.tcl` added. Detects spec/code drift across all
sinks. Four bugs fixed (table.alignments in HTML and MD; md.doc_header
section / version / part).

### Doc sync

All four repositories (docir, mdstack, mdhelp4, man-viewer) brought up
to date:
- `docir::FORMAT` sub-namespaces in all cookbooks, specs, and READMEs
- mdstack manuals: H1 titles, backticks, `package require` converted to
  the `mdstack::*` form
- man-viewer/cli-tools.md: CLI table updated with `docir::*` references
- nine sinks documented in the DocIR spec with comparison table and
  CLI tools

### Tests

| Repo | Tests |
|---|---|
| docir | 728 |
| mdstack | 532 |
| mdhelp4 | 6 suites |
| man-viewer | 67 |

### Notes

- Hyphens in module names should be avoided — they confuse Tcl's
  version parser.
- CSS Grid removes around 350 lines of layout code in tilehtml
  compared with tilepdf.
- A sed-based bulk rename with `\b` is not idempotent: the pattern
  matches between `:` (non-word) and a letter, so a second run
  produces `mdstack::mdstack::X::`. Anchored patterns like
  `[^:]X::` are safer.
- Markdown cannot do a two-column tile layout; pure MD is linear.
  `tilemd` produces clearly-structured linear output instead of a
  pseudo-columnar one.
- Cross-references in documentation are easy to miss — a separate
  inventory before claiming completeness is more reliable than
  manual checks.

---

## 2026-05-06 — DocIR extracted as standalone repository, full Markdown coverage, mdpdf adapter

### Repository extraction

DocIR (Document Intermediate Representation) was extracted from the
`man-viewer` repository. Until this point the DocIR modules lived
inside `man-viewer/lib/tm/`. Reasons for the split:

- A naming conflict between `docir-md` (man-viewer sink: DocIR →
  Markdown) and `docir-md` (mdstack source: Markdown → DocIR) forced
  a clear separation.
- Growing independence: own spec, own validator, own tests, use by
  multiple consumer repositories.

The split established the naming convention `docir-FORMAT` (sink) vs
`docir-FORMAT-source` (source), allowing both to be loaded
simultaneously. The original loader mechanism with seven search
strategies was replaced by the standard Tcl `auto_path` mechanism on
2026-05-07.

### Spec 0.5: full Markdown coverage

DocIR extended with all Markdown constructs: strike, image, linebreak,
span, footnote, footnote_ref, div. All six sinks (html, md, pdf, svg,
canvas, rendererTk) extended consistently. `mdhtml` consolidation:
roughly 600 lines of code duplication removed — `mdhtml` is now an
adapter to the DocIR pipeline. New `docir::roff` sink (DocIR → nroff
for manpage round-trip). Cross-consistency tests verify that every
combination of source and sink works.

### PDF consolidation + mdpdf adapter

`docir::pdf` switched to `pdf4tcllib`: header/footer templates with
`%p` substitution, theme colours (colorLink, colorCode), per-inline
rendering (bold/italic/code/strike distinguishable in one line),
image embedding via `pdf4tcl::addImage` (Tk-free). `mdpdf-0.2.tm` is
now an adapter (177 lines instead of 1786 lines of legacy).
Deliberately not ported: PDF/A, AES-128 encryption, automatic TOC
with PDF outlines (the legacy version is kept as a backup).

### Bug fixes

- `\\-` in `.OP` terms remained in nroff output (nroffparser issue)
- `docir::pdf` image embedding: root resolution for relative paths
- `docir::pdf` table cells: image embedding inside cells

### Notes

- A naming-conflict split that "won't happen in practice" tends to
  happen exactly when not expected.
- Code duplication is a symptom — DocIR was extracted because the
  parallel implementations in man-viewer and mdstack threatened to
  diverge.
- `<br>` is not valid in XHTML or `foreignObject`; it must be `<br/>`.
- Reproduce a bug, then fix it, then verify — in that order.
