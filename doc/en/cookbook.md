# DocIR Cookbook (EN)

Practical examples for using DocIR. For the formal specification, see
`docir-spec.md`. 

## Contents

1. [Setup](#setup)
2. [nroff to HTML](#nroff-html)
3. [nroff to Markdown](#nroff-md)
4. [nroff to PDF](#nroff-pdf)
5. [Markdown to HTML](#md-html)
6. [Markdown to nroff (TIP-700 reverse)](#md-roff)
7. [nroff round-trip (sanitizer)](#nroff-roundtrip)
8. [Renderer options](#options)
9. [Round-trip](#roundtrip)
10. [Writing your own renderer](#own-sink)
11. [Writing your own source](#own-source)
12. [Tile rendering: cheatsheet style](#tile-rendering)

---

<a id="setup"></a>
## 1. Setup

```tcl
lappend auto_path /path/to/docir
package require docir              ;# spec/validator
package require docir::roffSource  ;# nroff source
package require docir::html         ;# HTML sink
```

---

<a id="nroff-html"></a>
## 2. nroff to HTML

```tcl
package require nroffparser
package require docir::roffSource
package require docir::html

set ast  [nroffparser::parse $nroffText]
set ir   [::docir::roff::fromAst $ast]
set html [::docir::html::render $ir]
```

With theme:

```tcl
set html [::docir::html::render $ir [dict create \
    theme manpage lang en linkMode online includeToc 1]]
```

---

<a id="nroff-md"></a>
## 3. nroff to Markdown

```tcl
set ir [::docir::roff::fromAst [nroffparser::parse $nroffText]]
set md [::docir::md::render $ir]
```

---

<a id="nroff-pdf"></a>
## 4. nroff to PDF

```tcl
package require docir::pdf      ;# requires pdf4tcl + pdf4tcllib
::docir::pdf::render $ir output.pdf [dict create paper a4]
```

### PDF Options

`docir::pdf` accepts a rich set of options (since Phase 3, 2026-05):

```tcl
::docir::pdf::render $ir output.pdf [dict create \
    paper       a4             \
    margin      56             \
    fontSize    11             \
    title       "My Document"  \
    author      "Greg"         \
    header      "Doc Title - Page %p" \
    footer      "Confidential - %p"   \
    theme       hell           \
    root        /path/to/source     \
    sansFont    /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf \
    sansBoldFont /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf \
    monoFont    /usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf]
```

| Option | Default | Purpose |
|---|---|---|
| `paper` | `a4` | Paper size (a4, letter, ...) |
| `margin` | `56` | Margin in points (~20mm) |
| `fontSize` | `11` | Body font size |
| `title`, `author` | `""` | PDF metadata |
| `header`, `footer` | `""` | Per-page templates with `%p` for page number |
| `theme` | `""` | Theme name (via `mdstack::theme::toPdfOpts`) |
| `colorLink`, `colorCode` | `#0066cc`, `#e8e8e8` | Override theme colors |
| `root` | `""` | Base path for relative image URLs |
| `sansFont`, `sansBoldFont`, `sansItalicFont`, `sansBoldItalicFont`, `monoFont` | (auto) | TTF paths; auto-detected if empty |

### Per-Inline Rendering

Bold, italic, code-spans, links, and strike-through render with
distinct fonts. Hyperlinks become clickable PDF link annotations.

### Images

Block images (`![alt](path.png)` on its own line) are embedded as
PNG/JPEG XObjects via `pdf4tcl::addImage`. Relative paths are
resolved against `root`. HTTP/HTTPS URLs fall back to a text marker.

```tcl
::docir::pdf::render $ir output.pdf [dict create \
    root /path/to/markdown/source]
```

Inline images in the middle of paragraphs are rendered as
`[image: alt]` text markers (this matches mdpdf legacy behavior).

---

<a id="md-html"></a>
## 5. Markdown to HTML

```tcl
package require mdstack::parser            ;# from mdstack
package require docir::mdSource
package require docir::html

set ir   [::docir::md::fromAst [mdstack::parser::parse $mdText]]
set html [::docir::html::render $ir]
```

---

<a id="md-roff"></a>
## 6. Markdown to nroff (TIP-700 reverse)

Use case: write manpages in Markdown, generate nroff for traditional
distribution (`man` command, BSD-style manpages).

```tcl
package require mdstack::parser
package require docir::mdSource
package require docir::roff

set ir    [::docir::md::fromAst [mdstack::parser::parse $mdText]]
set nroff [::docir::roff::render $ir]
```

CLI: `bin/md2roff input.md output.n` (man-viewer repo).

Round-trip information loss is unavoidable: soft hyphens, kerning,
nroff comments, `.so` includes — these don't round-trip.

---

<a id="nroff-roundtrip"></a>
## 7. nroff round-trip (sanitizer)

```tcl
set ir    [::docir::roff::fromAst [nroffparser::parse $nroff]]
set clean [::docir::roff::render $ir]
```

CLI: `bin/n2roff input.n output.n` (man-viewer repo).

Use cases: sanitize hand-written manpages, diff against original to
see what DocIR loses, test the pipeline end-to-end.

---

<a id="options"></a>
## 8. Renderer options

| Option        | Sinks      | Meaning                          |
|---------------|------------|----------------------------------|
| `theme`       | html, pdf  | "default", "manpage", "none"     |
| `lang`        | html       | HTML lang attribute              |
| `includeToc`  | html       | generate table of contents       |
| `linkMode`    | html, md   | "local", "anchor", "online"      |
| `linkResolve` | html, md   | Tcl callback for link resolution |
| `headingShift`| html, md   | "auto" or integer                |
| `listMarker`  | md         | "-", "+", "*"                    |

---

<a id="roundtrip"></a>
## 9. Round-trip

```tcl
# nroff → DocIR → Markdown → DocIR
set ir1 [::docir::roff::fromAst [nroffparser::parse $nroff]]
set md  [::docir::md::render $ir1]
set ir2 [::docir::md::fromAst [mdstack::parser::parse $md]]
# ir1 and ir2 should be semantically equivalent
```

---

<a id="own-sink"></a>
## 10. Writing your own sink

```tcl
package provide docir-FORMAT 0.1
namespace eval ::docir::FORMAT {}

proc ::docir::FORMAT::render {ir {opts {}}} {
    set out ""
    foreach node $ir {
        switch [dict get $node type] {
            heading   { append out [_renderHeading $node] }
            paragraph { append out [_renderParagraph $node] }
            pre       { append out [_renderPre $node] }
            list      { append out [_renderList $node] }
            blank     { append out "\n" }
            hr        { append out "---\n" }
            table     { append out [_renderTable $node] }
            default   { }   ;# unknown types: ignore (DocIR principle)
        }
    }
    return $out
}
```

See `lib/tm/docir/html-0.1.tm` and `lib/tm/docir/md-0.1.tm` for
complete examples covering all block and inline types.

---

<a id="own-source"></a>
## 11. Writing your own source

```tcl
package provide docir-FORMAT-source 0.1
namespace eval ::docir::FORMAT {}

proc ::docir::FORMAT::fromAst {ast} {
    set ir {}
    foreach block [dict get $ast blocks] {
        switch [dict get $block type] {
            heading {
                lappend ir [dict create \
                    type    heading \
                    content [_mapInlines [dict get $block content]] \
                    meta    [dict create level [dict get $block level]]]
            }
            ...
        }
    }
    return $ir
}
```

A DocIR node ALWAYS has three fields: `type`, `content`, `meta`.
Validator: `::docir::validate $ir`.

See `lib/tm/docir/roffSource-0.1.tm` and `docir/mdSource-0.1.tm`.

---

<a id="tile-rendering"></a>
## 12. Tile rendering: cheatsheet style

Three tile sinks produce cheatsheet-style output from DocIR:
`tilepdf` (PDF, 2 columns), `tilehtml` (HTML with CSS Grid),
`tilemd` (linear structured Markdown).

All three use the same section classification (`docir::tilecommon`):

| MD content | Tile section type | Output form |
|------------|-------------------|-------------|
| Code blocks only | `code` | Monospace block |
| Intro paragraph + code | `code-intro` | Helvetica intro + mono code |
| Paragraphs only | `hint` | Highlighted (blockquote/colored) |
| List only | `list` | Bullets |
| Table only | `table` | Label/value 2-column |
| Images only | `image` | Image embed/marker |
| Mixed | `hint` with markers | Plain with » / • prefixes |

### Markdown → Tile-PDF

```bash
md2tilepdf cheatsheet.md                       # → cheatsheet.pdf
md2tilepdf *.md -o all.pdf                     # multi → 1 PDF (multiple sheets)
md2tilepdf cheatsheet.md -t dark -o dark.pdf
```

In Tcl:
```tcl
package require docir::tilepdf
::docir::tilepdf::render $ir output.pdf -theme dark
```

### Markdown → Tile-HTML

Advantages: 1-4 columns via CSS Grid, 5 themes, TOC for multi-sheet,
print-CSS, mobile-responsive.

```bash
md2tilehtml cheatsheet.md                                # → cheatsheet.html
md2tilehtml cheatsheet.md -t solarized -c 3 -o pretty.html
md2tilehtml *.md -o multi.html                           # with auto-TOC
md2tilehtml cheatsheet.md -t auto -o adaptive.html       # follows browser setting
```

In Tcl:
```tcl
package require docir::tilehtml
::docir::tilehtml::render $ir output.html \
    -theme solarized -columns 3 -lang en
```

### Markdown → Tile-Markdown

Linear (no column layout), but section classification stays visible:
code as fenced blocks, hints as blockquotes, lists as bullets.

```bash
md2tilemd cheatsheet.md                  # → cheatsheet.tile.md
md2tilemd *.md -o cheats.md              # with auto-TOC
md2tilemd cheatsheet.md --no-toc --no-hr # minimal
```

### Which tile sink when?

| Use case | Recommendation |
|----------|----------------|
| Print, archive, standalone distribution | `tilepdf` |
| Browser display, searchable, copyable, browser-print-to-PDF | `tilehtml` |
| GitHub display, Notion import, Obsidian, further editing | `tilemd` |
| Multiple parallel columns / responsive layout | `tilehtml` with `-columns N` |
| Dynamic theme switching by browser preference | `tilehtml -t auto` |

---

## Demo

`demo/quickstart.tcl` shows the full pipeline:

```bash
tclsh demo/quickstart.tcl input.n
# Produces input.html, input.svg, input.md
```
