# DocIR — Changelog

## 2026-05-13 — Canvas-Demo

**Affected consumers:** keine. Reine Demo-/Doku-Addition.

### Added

- **`demo/canvas_demo.tcl`** (193 LOC) -- runable Demo das die Pipeline
  nroff -> `docir::roffSource` -> DocIR -> `docir::canvas::render`
  zeigt. Sucht eine echte canvas.n in mehreren Standard-Pfaden
  (tcltk-manindex/manpages-nroff, src/manpages-nroff, src/doc/tk/doc,
  src/tk/tk/doc, demo/canvas.n), Fallback auf eingebautes Mini-IR via
  `--builtin`.
- **`demo/canvas_demo_data.tcl`** (43 LOC) -- IR-Daten fuer den
  Builtin-Modus (kein Tk-Bezug, nur Procs).
- **`demo/canvas.n`** -- Tk's canvas(n) Manpage (87 KB) als
  Fallback-Quelle wenn kein sibling `man-viewer` mit Manpage-Korpus
  vorhanden ist.

### Documentation

- **`README.md`** -- neue "Demos"-Sektion zwischen "Regenerating
  pkgIndex.tcl" und "Tests".

## 2026-05-13 — Konvergenz mit cheatsheets (tilepdf-Erweiterung)

**Affected consumers:** cheatsheets-Repo wird in dieser Session zum
Adapter umgebaut. Andere Konsumenten (man-viewer, mdstack, mdhelp4)
unbeeinflusst -- nur Added/Fixed, keine API-Breakage.

### Added

- **`docir::csdSource 0.1`** (`lib/tm/docir/csdSource-0.1.tm`) --
  neue DocIR-Source fuer CSD-Format (Tcl-deklarative Cheatsheet-Defs).
  Mappt CSD-Dict auf Sheets-Liste die `docir::tilepdf::renderSheets`
  konsumiert. Public API: `docir::csd::toSheet`,
  `docir::csd::toSheets`.

- **`docir::tilepdf::renderSheets`** -- alternative Public API neben
  `render`. Nimmt eine fertige Sheets-Liste statt eines DocIR-Streams.
  Bypass des Schema-Checks und der streamToSheets-Klassifizierung.
  Wird vom neuen cheatsheet-Adapter und vom csdSource-Pfad genutzt.

- **`docir::tilehtml::renderSheets`** und **`docir::tilemd::renderSheets`** --
  analog zu tilepdf, gibt der Tile-Renderer-Family eine konsistente
  alternative API. Damit kann `docir::csdSource` ueber alle drei
  Tile-Sinks (PDF/HTML/MD) genutzt werden. Bei `tilehtml` werden
  Themes (`light/dark/auto/solarized/sepia`) und Spaltenzahl (1-4) als
  Optionen weitergereicht; bei `tilemd` die TOC-Option und `-hr`.

### Fixed (kritisch -- aus cheatsheet-0.1.tm portiert)

- **Pagination-Bug in `docir::tilepdf::_renderSheet`/`_renderSection`:**
  - `_renderSection` nahm `y col` als call-by-value -- konnte keine
    Sections splitten die ueber Spalten gehen. Jetzt mit
    `upvar yVar colVar` analog cheatsheet-0.1.tm.
  - Per-item Spalten-Split in allen 6 Section-Typen (table, code,
    code-intro, hint, list, image): Pre-measure pro Row/Line/Item,
    bei Ueberlauf `_col`-Wechsel und `(cont.)`-Section.
  - `max_iter=24`-Spinning-Loop in `_renderSheet` entfernt -- ersetzt
    durch eine `minNeed`-Heuristik analog cheatsheet's `render`.
  - Konstante `max_iter` aus `C`-Array entfernt.

  Vorher: Sections die laenger als eine Spalte waren produzierten
  bis zu 12 leere Seiten + abgeschnittenen Content.
  Jetzt: sauber per-item ueber Spalten verteilt.

### Added (Unicode-Font-Pipeline -- aus cheatsheet-0.1.tm portiert)

- **`docir::tilepdf::_setupFonts`** -- registriert beim PDF-Start
  Unicode-TTF-Fonts (UniSans/UniSansBold/UniSansOblique/UniMono) via
  `::pdf4tcl::loadBaseTrueTypeFont` + `::pdf4tcl::createFontSpecCID`.
- **`docir::tilepdf::_tryLoadFont`** + **`_fontProblem`** -- robust
  gegen fehlende TTFs (sucht durch Standard-Pfade unter Linux/macOS/
  Windows).
- **`Style(fontMode)`** mit den Werten `strict` (default, Exception
  bei Font-Problem), `warn` (stderr-Warnung + Fallback auf
  Helvetica/Courier), `silent` (still Fallback).
- **`F`-Array** mit Slots `prop`/`propBold`/`propOblique`/`mono`,
  ersetzt vorher hardcoded `Helvetica`/`Helvetica-Bold`/`Courier` in
  `_header`, `_section`, `_row`, `_code`, `_listItem`, `_image`,
  `_fontFor`.

  Vorher: Unicode-Zeichen wie `→`, `←`, `…` wurden in PDF nicht
  gerendert (nur ASCII via Helvetica/Courier).
  Jetzt: korrekt mit DejaVu-Sans/Mono falls verfuegbar.

### Vorteile dieser Konvergenz

- cheatsheets als Adapter -- 459 LOC weniger zu pflegen.
- Bugfixes wirken jetzt fuer beide Pfade (Markdown-Tile UND CSD-Tile).
- Tile-Renderer-Features (Themes, code-intro, image) sind sofort fuer
  CSDs verfuegbar.
- Tilehtml/tilemd profitieren nicht von Pagination/Font-Fix (HTML/MD
  kennen keine Pagination und Unicode geht in HTML/MD sowieso) -- der
  Fix ist tilepdf-only.

## 2026-05-13 — Repo-Hygiene + Test-Setup Fixes

**Affected consumers:** keine API-Aenderung; nur Repo-Aufraeumen, Test-
Stabilitaet und kleinere Tooling-Verbesserungen. Konsumenten
(man-viewer, mdstack, mdhelp) brauchen nichts anzupassen.

### Removed

- **`lib/tm/docir/pdf-0.1.tm.bak`** -- alter Backup, neue Version ist
  `pdf-0.2.tm`. `.bak` zusaetzlich in `.gitignore`.
- **`tests/test-toc.pdf`** -- Test-Output war versehentlich versioniert
  (gitignore hat `*.pdf`).

### Fixed

- **`lib/tm/pkgIndex.tcl`** -- der Eintrag fuer `docir::pdf 0.1` zeigte
  auf die nicht mehr existierende `pdf-0.1.tm`. Via
  `tools/generate-pkgindex.tcl` neu generiert (jetzt nur noch
  `docir::pdf 0.2`).
- **`tests/test-setup.tcl`**:
  - `pdf-0.1.tm` (existiert nicht) durch `pdf-0.2.tm` ersetzt.
  - `pdf-0.2.tm` und `tilepdf-0.1.tm` (beide brauchen externes `pdf4tcl`)
    jetzt mit `catch` gesourced -- Tests skippen sich selbst statt mit
    Stack-Trace abzubrechen.
  - `roff-0.1.tm` und `tilehtml-0.1.tm` ergaenzt (fehlten).
  - `tcl::tm::path add` damit auch `package require docir::*` aus den
    Tests funktioniert (war noetig fuer einige Tests).
- **`tests/run-all-tests.tcl`** -- Crashende Test-Files lassen den Runner
  jetzt weiterlaufen statt mit "child process exited abnormally"
  abzubrechen. Wird als 1 Fail mit "(crashed)"-Marker gezaehlt.
- **`tests/test-validator.tcl`** -- File-level Skip wenn `nroffparser`
  nicht installiert ist (alle 13 Tests brauchen es).

### Changed

- **`bin/md2tilepdf`, `md2tilehtml`, `md2tilemd`** -- `-h`/`--help`
  wird jetzt VOR `package require` ausgewertet. Damit funktioniert die
  Hilfe auch ohne installierte Deps (vorher: Stack-Trace).
  Plus Hinweis `Benoetigt: ...` in der Usage.

### Test status

Ohne externe Parser (nroffparser/mdstack/pdf4tcl): **473 von 509 Tests
passing**. Mit allen Deps installiert: bis zu 728 Tests (Stand README,
nicht verifiziert in dieser Cleanup-Session).

Failende Test-Files ohne Deps (alle wegen externem Parser-Aufruf in
einzelnen Tests innerhalb der Datei):
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
