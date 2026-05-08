# DocIR — Changelog

## 2026-05-07 — Spec consolidation, pkgIndex refactor, tile renderer family

### Spec & validation

- **DocIR 0.5: `irSchemaVersion`** as a required field on `doc_meta`
  (integer, currently `1`). The validator still accepts streams without
  a schema version (best-effort) but warns via the test suite.
- **Central schema-skip helper** `docir::checkSchemaVersion` — every sink
  calls it, and a missing `doc_meta` node no longer produces output
  (silently skipped).
- **AST/DocIR spec clarification** (Phase 4/A.2): the AST is parser-
  specific and may lose information on the way to DocIR; DocIR is the
  canonical form. Source modules may discard information from the AST.
- **Table structure unified** (Phase 4/A.3): `table.alignments` is a list
  of `left|center|right` per column. All 6 sinks (html, md, pdf, roff,
  svg, canvas) now honour it consistently.
- **A.1 follow-up bug fixed**: `doc_meta` without `irSchemaVersion` was
  treated by HTML+MD as a body node, producing empty `<div>`/blank lines.
  All sinks now skip `doc_meta` silently.
- **`list.indentLevel`** retrofitted as best-effort in 3 sinks (md, pdf,
  roff). Visual sinks (svg, canvas, tilepdf, tilehtml, tilemd) are
  marked best-effort in the spec.

### Tcl module refactor (major layout change)

- **Sub-directory layout**: `docir-roff-0.1.tm` → `docir/roff-0.1.tm`,
  Tcl module names now consistently `docir::roff` (no longer the
  hyphenated form). Lesson learned: hyphenated module names are
  ambiguous (Tcl version-parser pitfall).
- **Standard Tcl pkgIndex.tcl convention**: one `pkgIndex.tcl` per
  module directory, generated via `tools/generate-pkgindex.tcl`.
  Bootstrap helpers removed, standard `auto_path` mechanism used.
- **Makefile convention** in every repo: `install`, `install-user`,
  `install-bin`, `pkgindex`, `test`, `uninstall`. `make install`
  installs to `/usr/local/lib/tcltk/<repo>/`, no extra setup needed.
- **CamelCase sink/source names** where required: `docir::mdSource`,
  `docir::roffSource`, `docir::rendererTk` (because hyphens in module
  names confuse Tcl's version parser).
- **mdstack big-bang namespace refactor**: `::mdparser` → `::mdstack::parser`,
  `::mdtext` → `::mdstack::text`, etc. 

### Tile renderer family

Adapted from Greg's `cheatsheet-0.1.tm` layout algorithm. Tile =
two-column cheatsheet style with atomic sections and a unified
section-type classification (`code`, `code-intro`, `hint`, `list`,
`table`, `image`).

- **`docir::tilecommon`**: shared helper with `streamToSheets`,
  `packSection`, `tokenize`, `inlinesToText`, `fontFor`. Used by
  tilepdf, tilehtml, and tilemd.
- **`docir::tilepdf`**: PDF, 2 fixed columns, light/dark themes,
  mixed-font inline rendering (bold/italic/code visually distinct),
  images via `pdf4tcl::addImage` proportionally scaled.
- **`docir::tilehtml`**: HTML with CSS Grid + `break-inside: avoid` for
  atomic tiles, 1–4 columns, 5 themes (light/dark/auto/solarized/sepia),
  TOC for multi-sheet output, real `<a href>` links, print CSS.
- **`docir::tilemd`**: linearly structured Markdown (Markdown is linear,
  no two-column layout possible). Section type remains recognisable via
  code fences, blockquotes, MD tables, etc.
- **CLI tools**: `bin/md2tile`, `bin/md2tilehtml`, `bin/md2tilemd`.

### Drift audit

`tools/drift-audit.tcl` built. Detects 49 spec/code drift points across
all sinks. Four real bugs fixed (table.alignments in HTML+MD,
md.doc_header section/version/part).

### Doc sync

All 4 repos (docir, mdstack, mdhelp4, man-viewer) brought up to date:
- `docir::FORMAT` sub-namespaces in all cookbooks/specs/READMEs
- mdstack manuals: H1 titles + backticks + `package require` converted
  to `mdstack::*`
- man-viewer/cli-tools.md: CLI table updated with `docir::*` references
- 9 sinks documented in DocIR spec with comparison table and CLI tools

### Tests

| Repo | Tests |
|---|---|
| docir | 728 ✓ (from ~340) |
| mdstack | 532 ✓ |
| mdhelp4 | 6 suites ✓ |
| man-viewer | 67 ✓ |

### Lessons learned

- **Avoid hyphens in module names** — Tcl version-parser pitfall.
- **CSS Grid removes 350 lines of layout code** (tilehtml vs tilepdf).
- **Big-bang sed with `\b` is not idempotent** — pattern matches between
  `:` (non-word) and a letter; running it again produces
  `mdstack::mdstack::X::`. Use anchored patterns like `[^:]X::` instead
  of `\bX::`.
- **MD cannot do a two-column tile layout** — pure MD is linear. tilemd
  produces clearly-structured linear output instead of a pseudo-columnar
  one.
- **Doc cross-references are easy to miss** — separate inventory beats
  guessing. In this case: filename cross-refs, SVG diagrams, ASCII
  architecture diagrams.
- **Verify "done" with greps before claiming it** — don't rely on memory.

---

## 2026-05-06 — Phase 1+2+3: DocIR repo, full Markdown coverage, mdpdf adapter

Day of the DocIR extraction and sink expansion.

### Phase 1 — DocIR as a standalone repository

DocIR (Document Intermediate Representation) was extracted from
man-viewer. A naming conflict between `docir-md` (man-viewer sink:
DocIR→Markdown) and `docir-md` (mdstack source: Markdown→DocIR) forced
the split. Naming convention: `docir-FORMAT` (sink) vs
`docir-FORMAT-source` (source), both loadable simultaneously. Loader
mechanism with 7 search strategies (`$DOCIR_HOME`, sibling, vendors,
auto_path, /usr/local/...).

### Phase 2 — DocIR spec 0.5: full Markdown coverage

DocIR extended with all Markdown constructs: strike, image, linebreak,
span, footnote, footnote_ref, div. All 6 sinks (html, md, pdf, svg,
canvas, rendererTk) extended consistently. `mdhtml` consolidation: ~600
lines of code duplication eliminated — `mdhtml` has been an adapter to
the DocIR pipeline since then. New `docir-roff` sink (DocIR → nroff for
manpage round-trip). Cross-consistency tests ensure that source X +
sink Y works for every combination.

### Phase 3 — pdf consolidation + mdpdf adapter

`docir-pdf` switched to `pdf4tcllib`: header/footer templates with `%p`
substitution, theme colours (colorLink, colorCode), per-inline rendering
(bold/italic/code/strike distinguishable in one line), image embedding
via `pdf4tcl::addImage` (Tk-free). `mdpdf-0.2.tm` has since been an
adapter (177 lines instead of 1786 lines of legacy). Deliberately NOT
ported: PDF/A, AES-128 encryption, automatic TOC with PDF outlines (the
legacy version is kept as a backup).

### Bug fixes

- `\\-` in `.OP` terms remained in the nroff output (nroffparser issue)
- `docir-pdf` image embedding: root resolution for relative paths
- `docir-pdf` table cells: image embedding inside cells

### Lessons learned

- "Not a problem in practice" is a bet — naming conflicts strike
  exactly when you don't expect them.
- Code duplication is a symptom — DocIR was extracted because the
  parallel implementations in man-viewer + mdstack threatened to diverge.
- `<br>` is not valid in XHTML/foreignObject — must be `<br/>`. A
  doubly-rendered context forces the stricter output.
- First reproduce the bug, then fix, then verify.

---

## 2026-05-06 — DocIR extracted as a standalone repository

Until this point the DocIR modules lived inside the `man-viewer` repo
under `lib/tm/`. Because of growing independence (own spec, own
validator, own tests, use by multiple application repos) and a name
clash with mdstack's `docir-md` source, DocIR was extracted into its
own repo.

