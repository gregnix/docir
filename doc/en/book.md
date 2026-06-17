# Writing Books with docir + mdstack (EN)

A convention for multi-chapter books written in Markdown and built to PDF
**and** HTML from one source, with hierarchical numbering, a table of
contents and a subject index. The build tool is `book-build.tcl`. For the
PDF/HTML option details see `pdf-toc.md` and the renderer sections of
`cookbook.md`.

---

## Directory layout

One directory per book, one Markdown file per chapter:

```
mybook/
    book.tcl            (optional manifest; see below)
    010-introduction.md
    020-concepts.md
    030-reference.md
```

Headings carry **no numbers** in the source (`#`, `##`, `###`). Chapter and
section numbers are assigned at build time, so reordering never means
renumbering by hand.

---

## Chapter order

Two ways, manifest takes precedence:

1. **Manifest `book.tcl`** — a small data file listing the order:

   ```tcl
   set title  "My Book"
   set author "Jane Doe"
   set chapters {
       010-introduction.md
       030-reference.md
       020-concepts.md
   }
   ```

   With a manifest the filename prefix is ignored; reorder by moving lines.
   `title`/`author` are optional. The file is read in a safe interpreter
   (data only, no side effects).

2. **Filename prefix** — without a manifest, files are ordered by a leading
   numeric prefix (`010-…md`). The prefix is only for ordering and never
   appears in the output. Files without a prefix follow, alphabetically.

Generate a manifest from the current prefix order (then reorder freely):

```
tclsh book-build.tcl manifest mybook/
```

---

## Numbering (and stable cross-references)

`-number` assigns `1`, `1.1`, `1.1.1` from nesting and order, down to
`-depth` (default 3). Numbers are added on the intermediate representation,
so they show up identically in the body, the TOC, the PDF bookmarks and in
both output formats.

Anchors are derived from the heading **title** (a slug), not from the
number. Reordering changes the numbers but not the anchors, so internal
links written as `[see](#section-title-slug)` stay valid. In HTML they are
clickable; in PDF they jump internally.

---

## Subject index

Mark an index term anywhere in the running text — in any paragraph, at any
heading level — as a bracketed span with class `index`:

```markdown
A [coroutine]{.index} suspends a script; see also [namespace]{.index}.
```

The term stays visible in the text and is collected into the index:

- **PDF**: alphabetical, grouped by initial letter, each term with all the
  pages it occurs on (`coroutine  3, 7`). Pages are captured at render time,
  so they are correct even across page breaks within a paragraph.
- **HTML**: alphabetical, each term linking to its occurrences, labelled by
  the (numbered) section title; multiple hits in one section collapse to one
  link.

---

## Building

```
# Both formats, numbered, next to the book directory:
tclsh book-build.tcl mybook/ -number

# Explicit outputs:
tclsh book-build.tcl mybook/ -pdf out/book.pdf -html out/book.html -number

# Switches:
#   -number        hierarchical auto-numbering on
#   -no-toc        omit the table of contents
#   -no-index      omit the subject index
#   -title T       override title (else from manifest)
#   -author A      override author
#   -depth N       numbering/TOC depth (default 3)
```

If neither `-pdf` nor `-html` is given, both are produced next to the book
directory.

### Module discovery

`book-build.tcl` finds docir, mdstack, pdf4tcl and pdf4tcllib via the
environment variables `DOCIR_HOME`, `MDSTACK_HOME`, `PDF4TCL_HOME`,
`PDF4TCLLIB_HOME`, then by scanning sibling repositories, then from whatever
is already on `tcl::tm::path` / `auto_path` (a normal system install needs
no variables).

---

## What is built in vs. specific to a book

- **Generic (in docir):** the numbered TOC and the subject index live in
  `docir::pdf` and `docir::html` (`generateToc`/`tocTitle`/`tocDepth`,
  `generateIndex`/`includeIndex`/`indexTitle`). Any document can use them.
- **Per book:** only the directory of chapters and the optional `book.tcl`.
  `book-build.tcl` is the same for every book.
