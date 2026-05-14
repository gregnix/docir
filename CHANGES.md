# DocIR — Changelog

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
