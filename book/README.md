# Book template

A starting point for a book built with **pdf4tcl + mdstack + docir**.

## Use it

1. Copy this directory to a new location.
2. Edit `book.tcl` — title, author, subtitle/date, and the chapter list.
3. Write one Markdown file per chapter. Use no heading numbers; mark index
   terms as `[term]{.index}`.
4. Build:

       tclsh /path/to/docir/tools/book-build.tcl . -number

This produces a PDF and an HTML file next to the directory, each with a
title page, hierarchically numbered chapters, a table of contents (with
page numbers in PDF), and a subject index.

## Common switches

| Switch | Effect |
|---|---|
| `-number` | hierarchical chapter numbering |
| `-pdf out.pdf` / `-html out.html` | explicit output paths |
| `-no-toc` / `-no-index` | omit the table of contents / index |
| `-title-page` | force a title page (else from `book.tcl`) |
| `-depth N` | numbering / TOC depth (default 3) |

The full convention is documented in `doc/en/book.md`.
