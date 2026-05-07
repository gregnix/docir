# DocIR 0.5 – Intermediate Representation Spec

Date: 2026-05-07
Version: 0.5
Status: Stable

---

## Purpose

DocIR is a **flat, type-bound block sequence** as a common intermediate
format for:

- `nroffparser` → `docir/roffSource-0.1.tm` (DocIR-Quelle)
- `mdparser` → `docir/mdSource-0.1.tm` (DocIR-Quelle)
- future HTML importers

Renderers (Tk, HTML, PDF) work exclusively on DocIR. Parsers do not need
to be restructured — mapping functions translate between parser-specific
ASTs and DocIR.

---

## Position in the Stack — AST vs. DocIR

DocIR sits between source-format-specific ASTs and renderer-side
sinks. The central convention is:

> **AST is close to source.**
> **DocIR is close to sinks.**

Concrete consequences:

| Aspect | AST (e.g. `nroffparser`) | DocIR |
|---|---|---|
| Vocabulary | Mirrors the source (`section` = `.SH`, `subsection` = `.SS`, `heading` = `.TH`) | Sink-near, source-format-neutral (`heading` with `level 1..6`, `doc_header`) |
| Inline set | Small and source-near (in the nroff AST: `text`/`strong`/`emphasis`) | Richer and sink-near (12 types incl. `underline`/`strike`/`code`/`link`/`image`/`linebreak`/`span`/`footnote_ref`) |
| Variability | Differs per source format | One spec for all sources |
| Responsibility | Preserves what the source says | Provides what sinks need |

Mapping functions (`docir::roffSource`, `docir::mdSource`) translate
in either direction. They may **enrich** (e.g. nroff `\fB…\fR` to
DocIR `strong`), **unify** (different source constructs mapped to one
DocIR type), and **drop** what sinks do not care about.

### Naming pitfall: `heading` means different things in each spec

This is the most common stumbling block and is documented explicitly
here rather than renamed — a code-wide rename would carry more risk
than benefit.

| Term         | AST meaning                                          | DocIR meaning                                       |
|--------------|------------------------------------------------------|-----------------------------------------------------|
| `heading`    | nroff `.TH` — the manpage header (1× per doc, `meta.level=0`) | Generic heading `.SH`/`.SS`/`# Markdown` (any number, `meta.level=1..6`) |
| `section`    | nroff `.SH` — a section heading                      | does not exist — mapped to `heading level=1`        |
| `subsection` | nroff `.SS` — a sub-section                          | does not exist — mapped to `heading level=2`        |
| `doc_header` | does not exist                                       | Generic doc header — target of AST `heading` (nroff `.TH`) and mdparser YAML frontmatter |

The full AST → DocIR mapping is given further down in the section
*"Mapping from nroff AST"*. The canonical AST spec lives alongside in
[`ast-spec.md`](ast-spec.md).

---

## Design Principles

- **Flat**: no children tree, linear sequence of block nodes
- **Fully typed**: each node has `type`, `content`, `meta`
- **SAX-like**: stable, easy to render, well testable
- **Extensible**: unknown types are ignored, not rejected
- **Defensive**: validators and renderers handle missing or empty
  fields gracefully where it makes sense (see `blank` below)

---

## Block Node Structure

```tcl
dict create \
    type    <string>   ;# Required field
    content <any>      ;# Required field (list of inlines OR items OR "")
    meta    <dict>     ;# Required field (can be empty: {})
```

**Validator:** `docir::validate $ir` returns an empty list on valid
input, or a list of error strings.

---

## Block Types

The current set of block types accepted by `docir::validate`:

| Type         | content              | meta fields                         |
|--------------|----------------------|-------------------------------------|
| `doc_meta`   | `{}`                 | `irSchemaVersion` (int ≥ 1, required)|
| `doc_header` | `{}`                 | `name`, `section`, `version`, `part`|
| `heading`    | Inline list          | `level` (1..6), `id` (optional)     |
| `paragraph`  | Inline list          | `{}` or `class`                     |
| `pre`        | Inline list          | `kind` (code/example/...)           |
| `list`       | listItem list        | `kind` (tp/ip/op/ap/ul/ol/dl), `indentLevel` (best-effort: structural sinks (md, pdf, roff, html, rendererTk) honor; visual sinks (svg, canvas, tilepdf) may ignore depending on layout) |
| `listItem`   | Inline list (desc)   | `kind`, `term` (inline list)        |
| `blank`      | `{}`                 | `lines` (int, default 1)            |
| `hr`         | `{}`                 | `{}`                                |
| `table`      | tableRow list        | `columns` (int), `alignments` (list), `hasHeader` (bool), `source` (optional tag) |
| `tableRow`   | tableCell list       | `kind` (header|body, optional)      |
| `tableCell`  | Inline list          | `{}`                                |
| `image`      | `{}`                 | `url`, `alt`, `title` (optional)    |
| `footnote_section` | footnote-def list | `{}`                              |
| `footnote_def` | Inline list        | `id`, `num` (display marker)        |
| `div`        | Block list           | `class`, `id` (TIP-700)             |

### Notes on the new block types

**`image`** — standalone image in its own paragraph slot. Equivalent to
HTML `<figure><img src=... alt=...></figure>`. `meta.url` is required;
`meta.alt` defaults to empty; `meta.title` is optional. Sinks that
cannot render images emit `[image: alt]` or skip the block.

**`footnote_section`** — collected footnote definitions, typically at
the end of the document. `content` is a list of `footnote_def` blocks.
HTML emits `<section class="footnotes">` with a list. Plain-text sinks
emit a `[notes]` divider followed by each definition on its own line.

**`footnote_def`** — single footnote definition with `meta.id` (matches
the `id` of `footnote_ref` inlines) and `meta.num` (display marker).
Content is the footnote body as inline list.

**`div`** — TIP-700 block-level container. `meta.class` and `meta.id`
are HTML/CSS attributes preserved by HTML/Markdown sinks. Other sinks
treat it as a transparent container (render content without wrapper).

### Markdown-specific Extensions (via docir::md)

| Type         | content              | meta fields                        |
|--------------|----------------------|------------------------------------|
| `paragraph`  | Inline list          | `class blockquote` (optional)      |
| `list`       | listItem list        | `kind` (ul/ol/dl/tp/ip/op/ap)      |
| `listItem`   | Inline list (desc)   | `kind`, `term` (inline list)       |

---

## listItem Node (within list.content)

Each item in `list.content` is itself a complete DocIR node:

```tcl
dict create \
    type    listItem         ;# Required
    content <Inline-List>    ;# desc — main text
    meta    {                ;# Required
        kind  tp|ip|op|ap|ul|ol|dl  ;# List type (inherited from parent)
        term  <Inline-List>          ;# Term/Label (for tp/ip/op/dl)
    }
```

**Rationale:** Treating `listItem` as a real DocIR node (with the same
type/content/meta shape as any other block) means the validator, the
dump tools and the diff tools work without any special-case code.

---

## Table Nodes (since 0.4)

Tables are represented as a three-level structure:

```tcl
{type table content {
    {type tableRow content {
        {type tableCell content <inline-list> meta {}}
        {type tableCell content <inline-list> meta {}}
        ...
    } meta {}}
    ...
} meta {columns N alignments {ALIGN ...} hasHeader BOOL source TAG}}
```

**Constraints (enforced by validator):**

- `table.meta.columns` is required and must be an integer >= 1
- `table.content` must be a list of `tableRow` nodes only
- `tableRow.content` must be a list of `tableCell` nodes only
- `tableCell.content` is an inline list (see Inline Types below)
- Empty cells are represented as `tableCell` nodes with empty `content`

**`alignments` (since 0.5):** list of per-column alignments, one
element per column from the set `{left center right}`. Derived by
mdparser sources from the `:` markers in the GFM separator row
(`:---` = left, `:---:` = center, `---:` = right). Renderers may
honour or ignore the alignment — in monospaced Tk text it is
typically applied; nroff sources without alignment information set
every column to `left`.

**`tableRow.meta.kind` (since 0.5):** optional, value `header` or
`body`. Ensures that the header row is identifiable without relying
on it being the first list element.

**`source` tag**: optional marker for the upstream construct that
produced the table. Currently `standardOptions` is set by the
nroff-to-DocIR mapper for tables derived from `.SO`/`.SE` blocks
(see "Mapping from nroff AST" below).

**Renderer expectation:** in a Tk text widget there are no real tables.
The renderer computes column widths over all cells and uses monospaced
spacing to align columns visually. Inline formatting inside cells
(e.g. `strong` for option names) is preserved.

---

## Schema Versioning — `doc_meta` (since 0.5)

Every DocIR stream produced by a source begins with a `doc_meta` block
that carries the IR schema version:

```tcl
{type doc_meta content {} meta {irSchemaVersion 1}}
```

**Purpose:** Renderers and other consumers can detect whether an IR
stream conforms to a schema version they are able to process. Before
0.5 only the packages had a version (`package provide docir 0.5`); the
IR itself did not.

**Validator rules:**

- `doc_meta.content` must be `{}`
- `doc_meta.meta.irSchemaVersion` is required and must be an integer ≥ 1
- `doc_meta` may appear **only once** in the stream

**Lenient mode (current):** IRs without a `doc_meta` block remain
valid. The validator does not raise an error, and `docir::schemaVersion`
returns `0` ("unversioned") in that case. This keeps older
hand-constructed IRs (e.g. from tests written before 0.5) working
without modification.

A future step (A.1.1) may switch to strict mode — `doc_meta` would
then be a required first block.

**Helper procs (in `docir-0.1.tm`):**

| Proc | Purpose |
|---|---|
| `docir::schemaVersion $ir` | Returns the integer (1, …) if a `doc_meta` block is present; otherwise `0`. |
| `docir::checkSchemaVersion $ir ?supported? ?strict?` | Checks the IR against a list of allowed versions. Default `supported`: `$::docir::SUPPORTED_SCHEMA_VERSIONS`. With `strict 1` even version 0 (= no `doc_meta`) is rejected. Returns `{}` on success. |
| `$::docir::SUPPORTED_SCHEMA_VERSIONS` | List of versions known to the hub. Currently `{1}`. |

**Renderer use:**

```tcl
set err [docir::checkSchemaVersion $ir]
if {$err ne ""} {
    error "renderer cannot handle this IR: $err"
}
```

Renderers may demand a narrower set of versions than the hub supports:

```tcl
docir::checkSchemaVersion $ir {1}      ;# v1 only
docir::checkSchemaVersion $ir {1} 1    ;# v1 strict (no v0)
```

**Sources:** `docir/roffSource-0.1.tm` and `docir/mdSource-0.1.tm`
emit `doc_meta` as the very first block — even when no `doc_header`
follows (e.g. an nroff AST without `.TH`).

---

## blank Nodes — content is optional

`blank` nodes are exempt from the "content is required" rule. The nroff
parser produces blank nodes without a `content` field at all:

```tcl
{type blank meta {lines 1}}                  ;# canonical form
{type blank content "" meta {lines 1}}       ;# also accepted
```

Both forms are valid. Consumers that read `content` from arbitrary
nodes should use the defensive pattern:

```tcl
set content [expr {[dict exists $node content] ? [dict get $node content] : {}}]
```

The validator skips content checks for `blank` nodes regardless of
whether the field exists.

---

## Inline Types

Inlines are dicts `{type <t> text <s>}` plus optional fields:

| Type           | Required fields            | Optional fields     |
|----------------|---------------------------|----------------------|
| `text`         | `text`                    | –                    |
| `strong`       | `text`                    | –                    |
| `emphasis`     | `text`                    | –                    |
| `underline`    | `text`                    | –                    |
| `strike`       | `text`                    | –                    |
| `code`         | `text`                    | –                    |
| `link`         | `text`, `name`, `section` | `href`               |
| `image`        | `text` (= alt), `url`     | `title`              |
| `linebreak`    | (none)                    | –                    |
| `span`         | `text`                    | `class`, `id`        |
| `footnote_ref` | `text` (= display num)    | `id` (target)        |

### Notes on the new types

**`strike`** — Markdown `~~text~~`. Renders as `<s>` in HTML, `~~..~~` in
Markdown, `[OVERSTRIKE]` text via `\s-1[\s+1` hack in nroff (or
plain text on text-only sinks), `text-decoration: line-through` in SVG,
overstrike Tk tag in renderer-tk/canvas.

**`image`** — inline image like `![alt](url "title")`. The `text` field
is the alt-text. Sinks that cannot render images (nroff, text) emit
`[image: alt]` as plain text.

**`linebreak`** — hard line break. The inline carries no text; it forces
a line break inside a paragraph. HTML `<br/>`, Markdown two trailing
spaces + newline, nroff `.br`, SVG/PDF newline within text run.

**`span`** — TIP-700 inline container. The `text` is the displayed
content; `class` and `id` are HTML/CSS attributes preserved by
HTML/Markdown/SVG sinks. nroff/text sinks just emit the text.

**`footnote_ref`** — reference to a footnote definition. `text` holds
the displayed marker (typically a number like "1"); `id` points to a
matching `footnote_section` entry. HTML emits `<sup><a href="#fn-1">1</a></sup>`.
Sinks without link-targets emit `[1]`.

`link` inlines are produced when the source AST already had link
inlines (the nroff parser's `detectLinks` step in SEE ALSO sections,
or markdown's link references). The DocIR mapper preserves them
unchanged.

---

## Mapping from nroff AST (docir/roff-0.1.tm)

| nroff Type    | DocIR Type    | Note                                 |
|---------------|---------------|--------------------------------------|
| `heading`     | `doc_header`  | Only the first heading node          |
| `section`     | `heading`     | meta `level=1`, `id` from title      |
| `subsection`  | `heading`     | meta `level=2`                       |
| `paragraph`   | `paragraph`   | unchanged                            |
| `pre`         | `pre`         | unchanged — UNLESS preceding section was "STANDARD OPTIONS", then attempted as `table` (see below) |
| `list`        | `list`        | content = listItem nodes             |
| list-item     | `listItem`    | content=desc, meta.term=term         |
| `blank`       | `blank`       | unchanged (content may be absent)    |

### Standard Options Tables (`.SO` / `.SE`)

When a section titled `STANDARD OPTIONS` (case-insensitive) is
followed by a `pre` block whose text is structured as tab-separated
columns and newline-separated rows, the mapper transforms that
`pre` block into a `table` node.

Heuristic (in `_tryStandardOptionsTable`):

1. Concatenate the `pre` block's inline texts to a single string
2. Split on `\n` to get rows; trim and discard empty lines
3. Determine the maximum column count across all rows
4. If max >= 2, build the table; rows with fewer columns are padded
   with empty `tableCell` nodes
5. Otherwise return empty (the `pre` block stays as `pre`)

Cell content for Tk-style standard options is wrapped in a
`strong` inline (option identifiers like `-background`) — this
matches the `\fB...\fR` formatting in the nroff source.

The `source` tag in the resulting `table.meta` is set to
`standardOptions`.

This mapping is **specific to DocIR**. It does not affect:

- The AST returned by `nroffparser::parse` (still has the `pre` block)
- Other (non-DocIR) consumers of the AST

DocIR-aware consumers (such as `man-viewer.tcl` via the Tk renderer)
benefit from properly formatted tables.

---

## Mapping from mdparser AST (docir/md-0.1.tm)

| mdparser Type | DocIR Type    | Note                                 |
|---------------|---------------|--------------------------------------|
| `document`    | `doc_header`  | meta from YAML frontmatter           |
| `heading`     | `heading`     | meta level=1..6, id=anchor           |
| `paragraph`   | `paragraph`   | unchanged                            |
| `code_block`  | `pre`         | meta kind=code, language             |
| `list`        | `list`        | content = listItem nodes             |
| `list_item`   | `listItem`    | content=desc, meta.term={}           |
| `blockquote`  | `paragraph`   | meta class=blockquote                |
| `deflist`     | `list`        | kind=dl, listItem with term          |
| `table`       | `table`       | structurally identical (since 0.4)   |
| `hr`          | `hr`          | unchanged                            |
| `div`         | –             | inner blocks recursively mapped      |

---

## Example: nroff → DocIR

**Source:**

```nroff
.TH canvas n 8.3 Tk
.SH NAME
canvas \- create and manipulate 'canvas' widgets
.SH "STANDARD OPTIONS"
.SO
\-background\t\-cursor
\-foreground\t\-relief
.SE
```

**DocIR:**

```tcl
{type doc_meta content {} meta {irSchemaVersion 1}}
{type doc_header content {} meta {name canvas section n version 8.3 part Tk}}
{type heading content {{type text text NAME}} meta {level 1 id name}}
{type paragraph content {{type text text {canvas - create and manipulate 'canvas' widgets}}} meta {}}
{type heading content {{type text text {STANDARD OPTIONS}}} meta {level 1 id standard-options}}
{type table content {
    {type tableRow content {
        {type tableCell content {{type strong text -background}} meta {}}
        {type tableCell content {{type strong text -cursor}} meta {}}
    } meta {}}
    {type tableRow content {
        {type tableCell content {{type strong text -foreground}} meta {}}
        {type tableCell content {{type strong text -relief}} meta {}}
    } meta {}}
} meta {columns 2 hasHeader 0 source standardOptions}}
```

---

## Renderer Support (docir/rendererTk-0.1.tm)

| DocIR Type   | Rendering                                              |
|--------------|--------------------------------------------------------|
| `doc_header` | Title line with name, section, version                 |
| `heading`    | level 1–6: font size +4/+2/+1 pt                       |
| `paragraph`  | Normal text; `class=blockquote` adds `│` bar           |
| `pre`        | Monospace block, tab expansion                         |
| `list`       | kind tp/ap: Term+Desc; ip: hanging indent              |
|              | kind ul/ol: `•` bullet; kind dl: term bold             |
| `listItem`   | Rendered within `list`                                 |
| `blank`      | Blank line(s) per `meta.lines`                         |
| `hr`         | `────────────` separator line                          |
| `table`      | Monospace columns, widths computed across all cells;   |
|              | inline formatting inside cells preserved               |

## Available Sinks

DocIR currently has the following sinks (`docir::*` modules). Each
sink takes a DocIR stream and produces an output format:

| Sink               | Module                 | Output                                          |
|--------------------|------------------------|-------------------------------------------------|
| `docir::html`      | html-0.1.tm            | HTML5 with semantic classes                     |
| `docir::md`        | md-0.1.tm              | Markdown (CommonMark + GFM)                     |
| `docir::pdf`       | pdf-0.1.tm             | PDF via pdf4tcl, standard layout                |
| `docir::roff`      | roff-0.1.tm            | nroff/groff (man pages)                         |
| `docir::svg`       | svg-0.1.tm             | SVG graphics                                    |
| `docir::canvas`    | canvas-0.1.tm          | Tk canvas items (for GUI display)               |
| `docir::tilepdf`   | tilepdf-0.1.tm         | 2-column tile PDF (cheatsheet style)            |
| `docir::tilehtml`  | tilehtml-0.1.tm        | 2-column tile HTML with CSS Grid                |
| `docir::tilemd`    | tilemd-0.1.tm          | Tile-structured Markdown (linear)               |
| `docir::rendererTk`| rendererTk-0.1.tm      | Tk text widget (interactive viewer)             |

Plus shared helper:

| Helper             | Module                 | Function                                        |
|--------------------|------------------------|-------------------------------------------------|
| `docir::tilecommon`| tilecommon-0.1.tm      | DocIR → sheets/sections logic (used by tilepdf, tilehtml, tilemd) |

### Tile sinks comparison

The three `tile*` sinks share the same section classification
(via `tilecommon::packSection`):

| | tilepdf | tilehtml | tilemd |
|---|---|---|---|
| **Output** | PDF | HTML | Markdown |
| **Layout** | 2 columns (fixed) | CSS Grid (1-4 columns) | linear |
| **Themes** | light/dark | light/dark/auto/solarized/sepia | (none) |
| **Images** | local (URL→fallback) | local + URL | as `![alt](url)` |
| **Inline bold/italic/code** | mixed-font | real tags | pseudo-MD |
| **Links** | as pseudo-MD | real `<a href>` | as `[text](url)` |
| **TOC** | no | auto on multi-sheet | auto on multi-sheet |
| **Use case** | print/archive | browser/print-to-PDF | GitHub/Notion/Obsidian |

### CLI tools (in `bin/`)

| Tool | Sink | Pipeline |
|------|------|----------|
| `md2tilepdf` | tilepdf | mdparser → DocIR → tilepdf → PDF |
| `md2tilehtml` | tilehtml | mdparser → DocIR → tilehtml → HTML |
| `md2tilemd` | tilemd | mdparser → DocIR → tilemd → Markdown |

Install: `make install-bin` (copies to `$PREFIX/bin/`).

**Classification for best-effort fields:**

- **Structural sinks** (md, pdf, roff, html, rendererTk) honor optional
  fields like `list.indentLevel` with measurable output difference.
- **Visual sinks** (svg, canvas, tilepdf, tilehtml, tilemd) may ignore some
  fields when their layout doesn't accommodate arbitrary depths/options.

Both classes satisfy the DocIR spec — the spec marks
"best-effort" fields as such.

---

## Versioning

| Version | Date       | Change                                                  |
|---------|------------|---------------------------------------------------------|
| 0.1     | 2026-03-05 | Initial spec, roff mapping                              |
| 0.2     | 2026-03-06 | `listItem` as complete node (type/content/meta)         |
| 0.3     | 2026-03-06 | docir/md-0.1.tm (mdparser mapper); Renderer: blockquote, ul/ol, dl |
| 0.4     | 2026-05-05 | `table`/`tableRow`/`tableCell` block types; `.SO`/`.SE` mapping; documented `blank` content optionality; `link` inline canonicalised |
| 0.5     | 2026-05-07 | `doc_meta` block type with `irSchemaVersion` field; helper procs `docir::schemaVersion` / `docir::checkSchemaVersion`; sources emit `doc_meta` as first block; validator lenient towards IRs without `doc_meta` (transition phase) |
