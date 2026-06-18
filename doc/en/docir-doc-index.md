# DocIR Documentation

DocIR is a hub for document conversion: sources read an input format into a
common intermediate representation, and sinks produce the output formats
from it. This is the entry point to the English documentation.

## Guides

| Topic | Page |
|---|---|
| Write multi-chapter books (PDF + HTML from one source) | [Writing Books](../../book/book.md) |
| Recipes for common conversion tasks | [Cookbook](cookbook.md) |
| Table of contents and subject index in PDF | [PDF: TOC & Index](pdf-toc.md) |

## Reference

| Topic | Page |
|---|---|
| The intermediate representation (block/inline types, validation) | [DocIR Spec](docir-spec.md) |
| nroff parser AST | [AST Spec](ast-spec.md) |
| HTML sink CSS classes | [HTML CSS Schema](html-css-schema.md) |
| HTML source (`docir::htmlSource`) | [HTML Source](html-source.md) |
| ODT support | [ODT](odt.md) |

## Quick orientation

The usual Markdown path:

```tcl
package require mdstack::parser
package require docir::mdSource
package require docir::pdf

set ast [mdstack::parser::parse $markdown]
set ir  [docir::md::fromAst $ast]
docir::pdf::render $ir out.pdf {}
```

For whole books, use `book-build.tcl` (see [Writing Books](../../book/book.md)); it
assigns chapter numbers, a table of contents and a subject index, and
builds PDF and HTML in one run.

A complete worked example is the **DocIR Handbook**: the English edition
lives next to this file in `book/`, the German edition in `../de/buch/`.
Each is a small book that uses the whole convention and documents docir at
the same time. The reusable starting point for your own books is the
template in the repository's `book/book/` directory.
