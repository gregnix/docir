# Sinks

A [sink]{.index} produces an output format from the IR. All sinks work
exclusively on the IR and are therefore independent of the original
source.

## PDF

`docir::pdf` renders to PDF via pdf4tcl and pdf4tcllib.

```tcl
docir::pdf::render $ir out.pdf [dict create \
    title "My Document" paper a4 footer "%p"]
```

The sink supports, among other things, a table of contents with page
numbers and a subject index (see the next chapter). It relies on the
Unicode-safe text and font handling of pdf4tcllib.

A code block that no longer fits on the page starts on the next one, in the
fixed-width font. Up to 2026-10-19 it came out proportional there, because
the page break writes the footer in the body font.

The [synopsis]{.index} of a TIP-700 manual page (`::: {.synopsis}` with
the spans `.cmd .sub .lit .arg .ins .optarg .optlit .optdot`) comes out one
line per call form, set as in the Tcl man pages: `.cmd .sub .lit` bold,
`.arg .ins` italic, the optional ones in question marks (`?id?`,
`?-strict?`, `?script script ...?`). This applies to a paragraph made only
of these spans, blanks and soft line breaks that starts with `.cmd` or
`.ins`; other paragraphs stay as they are. Up to 2026-10-23 the synopsis ran
on as one paragraph.

For the PDF [metadata]{.index} there are, besides `title` and `author`,
the options `subject`, `keywords`, `creator` (default `docir::pdf`) and
`lang`, the document language as a BCP 47 tag (`"de"`, `"en-GB"`). It is
written to the catalog and the XMP data, so readers and screen readers use
the right language; this needs pdf4tcl 0.9.4.73 or later. The creation
date is always set: from the option `creationDate` (seconds), else from the environment variable `SOURCE_DATE_EPOCH`, else the current time. With a fixed date two runs on the same input give the same bytes.

## HTML

`docir::html` renders to self-contained HTML with embedded CSS.

```tcl
set html [docir::html::render $ir [dict create \
    title "My Document" includeToc 1]]
```

Headings receive their `id` as an anchor, so the table of contents and
cross-references work as clickable jump targets.

## Further sinks

Besides PDF and HTML there are other [sink]{.index}s in the docir hub,
including a Markdown sink (round-trip), an nroff sink, an SVG and a Canvas
sink, a Tk renderer sink, and the tile sinks for cheat-sheet-style
layouts. Since they all work on the same IR, every source is automatically
available to each of these sinks.
