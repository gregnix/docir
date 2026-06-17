# DocIR PDF: Table of Contents (EN)

How to generate a printed table of contents (TOC) with page numbers in
the DocIR PDF sink (`docir::pdf`). For general renderer options see
`cookbook.md`, section *Renderer options*; for the formal IR spec see
`docir-spec.md`.

---

## Options

The TOC is controlled through three render options passed to
`docir::pdf::render` (or `mdstack::pdf` once it forwards them):

| Option        | Type   | Default              | Meaning                                             |
|---------------|--------|----------------------|-----------------------------------------------------|
| `generateToc` | bool   | `0`                  | Emit a table of contents before the body.           |
| `tocTitle`    | string | `Inhaltsverzeichnis` | Heading printed on the TOC page.                    |
| `tocDepth`    | int    | `2`                  | Highest heading level listed (1 = chapters only).   |

When `generateToc` is `0` (the default), rendering is unchanged: a single
pass, no TOC page.

---

## Behaviour

With `generateToc 1` the renderer produces a TOC page (or pages) ahead of
the body. Entries are indented by heading level and the page number is
printed right-aligned on the entry's first line. Headings deeper than
`tocDepth` are skipped.

### Page numbers (two-pass)

A heading's page number is only known after the document has been laid
out, and the TOC itself shifts every page that follows it. `render`
therefore renders the whole document repeatedly, feeding the heading
pages observed in one iteration back into the next, until the page list
is stable; that stable result is written to disk. Because the page number
sits on the heading's own line (right-aligned), adding the numbers does
not change the TOC page count, so this normally converges after the
second iteration. A safety cap of six iterations applies; if the layout
has not stabilised by then, the last result is written and a warning is
printed to `stderr`.

The page numbers shown in the TOC are the final page numbers of the
produced PDF (the TOC pages are already included in the count), so they
match the document's PDF bookmarks and the body pages exactly.

---

## Example

```tcl
package require mdstack::parser
package require docir::mdSource
package require docir::pdf

set ast [mdstack::parser::parse $markdown]
set ir  [docir::md::fromAst $ast]

docir::pdf::render $ir output.pdf [dict create \
    title       "My Document" \
    generateToc 1 \
    tocTitle    "Inhaltsverzeichnis" \
    tocDepth    2]
```

A runnable version is in `demo/demo-md-pdf-toc.tcl`.

---

## Limitation: `renderToHandle`

`renderToHandle` renders into a PDF handle owned by the caller, so the
renderer cannot discard and rebuild it for the iterative two-pass. Over
that path the TOC is still produced (via `generateToc`) but **without**
page numbers. Page-numbered TOCs require the file-writing `render` entry
point.

---

## Tests

Covered by `tests/test-docir-pdf.tcl` under the `spec.pdf.toc.*` names:
TOC presence and title, custom title, `tocDepth` limiting, the default-off
path, and a correctness check that the page number shown in the TOC equals
the body page on which the heading appears.
