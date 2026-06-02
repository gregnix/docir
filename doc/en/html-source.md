# HTML source (`docir::htmlSource`)

`docir::htmlSource` reads HTML into DocIR — the inverse of the `docir::html`
sink. Together they make HTML **bidirectional**, enabling round-trips and
chains like `HTML → DocIR → PDF`.

```
HTML ──→ docir::htmlSource ──→ DocIR ──→ docir::pdf  → PDF
                                       → docir::md   → Markdown
                                       → docir::html → HTML (normalised)
```

## API

```tcl
package require docir::htmlSource
set ir [docir::htmlSource::fromHtml $html]
```

Parses with tdom (`dom parse -html -keepEmpties`) and maps the document
semantics. Works on a body fragment or a full document (head/CSS/TOC are
ignored).

## Mapping

| HTML                                   | DocIR                          |
|----------------------------------------|--------------------------------|
| `h1`…`h6` (`id` optional)              | `heading` (level, id)          |
| `p`                                    | `paragraph`                    |
| `pre` / `pre>code` (`language-X`)      | `pre` (kind code, lang)        |
| `ul`/`ol`/`dl`                         | `list` (kind, indentLevel)     |
| `li` / `dt`+`dd`                       | `listItem` (term for dl)       |
| `table`, `tr`, `th`/`td`, `colgroup`   | `table`/`tableRow`/`tableCell` |
| `hr`                                   | `hr`                           |
| `img`                                  | `image`                        |
| `strong`/`b`, `em`/`i`, `u`, `s`/`del` | strong / emphasis / underline / strike |
| `code`, `a`, `span`, `sup.footnote-ref`, `br` | code / link / span / footnote_ref / linebreak |
| `span.math`                            | `math` inline                  |

List kind comes from the `docir-list-XXX` class (else the tag); the
nesting depth from the `indent-N` class (else recursion depth). Table
header from `<th>`; alignments from `<colgroup>`. These mirror the
`docir::html` sink, so its output round-trips exactly.

Transparent containers (`div`, `section`, `article`, `figure`) are
recursed into; non-document elements (`script`, `style`, `nav`, `header`,
`footer`, `aside`, `head`) are skipped. Whitespace runs in the inline flow
are collapsed to a single space (HTML rule); `pre` text is kept verbatim.

## Round-trip

`DocIR → docir::html → DocIR'` reproduces the same document — verified by
comparing the re-rendered HTML and Markdown. Test:
`tests/html-roundtrip-test.tcl` (covers headings, all inlines incl. inline
spaces, ul/ol, nested lists via `indent-N`, tables with alignments and
header, pre, image, hr, and body extraction from a full document).

## Scope / limits

- **Document HTML** (articles, doc pages, the sink's own output) maps
  cleanly.
- **Layout-heavy pages** (nested divs, columns, widgets) are reduced to
  their document content; everything non-document is dropped. This is not
  a pixel-faithful page rebuild — it is the text content as a document, in
  DocIR's "semantic, no layout" spirit.
- Link targets are read from `href`; `name`/`section` (roff-style links)
  are not produced.
- KaTeX/MathJax `span.math` is mapped to a `math` inline (the `$…$`
  delimiters are stripped).
