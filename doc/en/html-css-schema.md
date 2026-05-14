# HTML CSS Schema for `docir::html`

**As of:** 2026-05-10
**Module:** `docir/lib/tm/docir/html-0.1.tm`

This document describes the HTML structure and CSS classes produced by
`docir::html::render`. It is the **interface between the renderer and
stylesheet authors**: anyone writing custom CSS for docir HTML output
can rely on the classes documented here.

The default stylesheets are embedded in the module code (see
`_defaultCss`). Example themes with alternative layouts ship with the
mdhelp repository under `mdhelp/styles/`.

---

## Document Skeleton

```html
<!DOCTYPE html>
<html lang="...">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="..."/>
  <title>...</title>
  <style>...</style>            <!-- inline, or external link -->
</head>
<body>
  <nav class="toc">             <!-- only when -toc 1 -->
    <ul>
      <li class="toc-level-1"><a href="#anchor">Heading</a></li>
      <li class="toc-level-2"><a href="#anchor">Sub-Heading</a></li>
      ...
    </ul>
  </nav>

  <h1 id="...">...</h1>         <!-- standard Markdown output -->
  <p>...</p>
  <h2 id="...">...</h2>
  ...
</body>
</html>
```

---

## Standard HTML Tags

Produced by ordinary Markdown conversion — no docir-specific classes,
but typically styleable:

| Tag                        | Used for                          |
|----------------------------|-----------------------------------|
| `h1`, `h2`, `h3`, …, `h6`  | Headings                          |
| `p`                        | Paragraph                         |
| `ul`, `ol`, `li`           | Lists                             |
| `dt`, `dd`, `dl`           | Definition lists                  |
| `a`                        | Link                              |
| `code`                     | Inline code                       |
| `pre`                      | Code block                        |
| `pre code`                 | Code inside a code block          |
| `blockquote`               | Quote                             |
| `table`, `tr`, `td`, `th`  | Tables                            |
| `colgroup`, `col`          | Table column definitions          |
| `hr`                       | Horizontal rule                   |
| `img`                      | Images                            |
| `figure`, `figcaption`     | Image with caption                |
| `strong`, `em`, `s`, `u`   | Inline formatting                 |
| `sup`                      | Superscript (also for footnotes)  |
| `br`                       | Line break                        |
| `section`                  | Semantic block                    |

---

## docir-specific Classes

These classes are **only** guaranteed in docir::html output. Other
Markdown-to-HTML converters do not emit them.

### TOC (Table of Contents)

Generated with the `-toc 1` option.

| Selector                           | Purpose                |
|------------------------------------|------------------------|
| `nav.toc`                          | TOC container          |
| `nav.toc ul`                       | List of entries        |
| `nav.toc li.toc-level-1`           | Top-level (`<h1>`)     |
| `nav.toc li.toc-level-2`           | Second level (`<h2>`)  |
| `nav.toc li.toc-level-3`           | Third level (`<h3>`)   |
| ... up to `toc-level-6`            | up to `<h6>`           |
| `nav.toc a[href="#..."]`           | TOC entry link         |

**Example:**

```css
nav.toc { background: #f9f9f9; padding: 1em; border-radius: 4px; }
nav.toc li.toc-level-2 { padding-left: 1em; }
nav.toc li.toc-level-3 { padding-left: 2em; font-size: 0.9em; }
nav.toc a { color: #0055aa; text-decoration: none; }
```

### Manpage Header

When the docir source is a manpage document (e.g. converted from
tcllib doctools or docir-md):

| Selector                       | Purpose                                     |
|--------------------------------|---------------------------------------------|
| `header.manpage-header`        | Manpage header block                        |
| `header.manpage-header h1`     | Inline H1 with no border (manpage style)    |
| `.maninfo`                     | Inline metadata (version, section, etc.)    |
| `.version`                     | Version number                              |
| `.part`                        | Manpage section (e.g. "(n)", "(3tcl)")      |

### Document Header (general)

| Selector                       | Purpose                                     |
|--------------------------------|---------------------------------------------|
| `.docir-doc-header`            | Generic document header                     |
| `.docir-doc-header .name`      | Document name (bold)                        |

### List Variants

docir supports several list types (from tcllib doctools conventions):

| Selector                   | Purpose                                              |
|----------------------------|------------------------------------------------------|
| `.docir-list-tp`           | Term-pair list (dt/dd, bold term + indented body)    |
| `.docir-list-tp dt`        | Term (bold)                                          |
| `.docir-list-tp dd`        | Definition (indented)                                |
| `.docir-list-ip`           | Indented-paragraph list                              |
| `ul.iplist`                | Alternative indented list with disc bullets          |
| `ul.iplist li`             | List entry                                           |

### Indentation Classes

Manually applied indentation (e.g. for nested tcllib doctools):

| Selector      | margin-left |
|---------------|-------------|
| `.indent-1`   | 2em         |
| `.indent-2`   | 4em         |
| `.indent-3`   | 6em         |
| `.indent-4`   | 8em         |

### Table Variants

| Selector                                       | Purpose                          |
|------------------------------------------------|----------------------------------|
| `table.docir-standard-options`                 | Options list, monospaced         |
| `table.docir-standard-options td`              | Option entries                   |
| `table.docir-table`                            | Standard data table              |
| `table.docir-table td`, `table.docir-table th` | Cells with borders               |
| `table.docir-table th`                         | Header cells with background     |

### Footnotes

| Selector                       | Purpose                                     |
|--------------------------------|---------------------------------------------|
| `<sup>` (in body text)         | Footnote anchor                             |
| `<a class="back">↩</a>`        | Back-reference from footnote to anchor      |

### Diagnostic Classes

| Selector                       | When                                        |
|--------------------------------|---------------------------------------------|
| `.docir-unknown`               | Unknown block type — yellow background      |
| `.docir-blank`                 | Blank line (line-height 1.0)                |

---

## Best Practices for Custom Stylesheets

### 1. Rely on class names, not tag order

Bad:
```css
body > p:nth-child(2) { ... }   /* fragile */
```

Good:
```css
.docir-list-tp dd { ... }        /* explicit */
nav.toc li.toc-level-2 { ... }
```

### 2. CSS Grid and docir::html output

If you use `body { display: grid }`: explicitly set `grid-column` for
all direct children, otherwise auto-placement distributes them
alternately across all columns:

```css
body { display: grid; grid-template-columns: 280px 1fr; }
nav.toc { grid-column: 1; grid-row: 1 / -1; }
body > *:not(nav.toc) { grid-column: 2; }   /* IMPORTANT */
```

### 3. Stay backwards-compatible

If your stylesheet should also work with HTML output from other
Markdown converters: only style standard tags, no `.docir-*` classes.
Those are docir-specific.

---

## Example Stylesheets

In the mdhelp repository (or any caller):

- `mdhelp/styles/sticky-top.css` — TOC at the top, scrolls with page
- `mdhelp/styles/sidebar.css` — TOC on the left as sidebar (280px), body on the right
- `mdhelp/styles/collapsible.css` — TOC collapsed, hover to expand

These stylesheets are **mdhelp resources**, not part of docir.
docir itself stays CSS-free except for the internal `_defaultCss`
fallback.

---

## Invocation with custom CSS

```tcl
package require docir::html

# Direct
set html [docir::html::render $ir [list \
    title       "My Doc" \
    cssFile     "/path/to/style.css" \
    includeToc  1]]

# Via mdstack adapter
package require mdstack::html
mdstack::html::export $ast output.html \
    -title "My Doc" \
    -css   "/path/to/style.css" \
    -toc   1
```

`-css` / `cssFile` replaces the `_defaultCss` with the contents of the
file. Without the option: the default CSS embedded in the module is
used.

---

## Schema Version History

- **2026-05-10:** Initial version. Classes extracted from html-0.1.tm.

When changing the `docir::html` renderer (new classes, new tags),
please update this document so that stylesheet authors know what they
can rely on.
