# Tables: Contents and Index

The table of contents and the subject index are both built from the IR and
are available in both main sinks.

## Table of contents

The [table of contents]{.index} is built from the headings. In PDF,
`generateToc 1` enables a leading contents page with page numbers;
`tocTitle` and `tocDepth` control title and depth. In HTML, `includeToc 1`
does the same with clickable jump targets.

The page numbers in the PDF arise from a two-pass procedure: because the
contents page shifts the following pages, the document is laid out
repeatedly until the page numbers are stable.

## Subject index

A subject [index]{.index} is built from terms marked in the text. The
marker is a bracketed span with the class `index`:

```markdown
A [coroutine]{.index} suspends a script.
```

The term stays visible in the running text and is collected at the same
time. Such a [span]{.index} may appear in any paragraph at any level,
including in sub-chapters, and also in bold or italic
(`**[coroutine]{.index}**`, since 2026-10-21; before, it was then missing
from the index). Inside a code span (`` `[x]{.index}` ``) it is an example
and does not count.

In PDF, `generateIndex 1` enables the index: alphabetical, grouped by
initial letter, each term with all pages where it occurs. The page is
captured while typesetting, so it stays correct across page breaks too. In
HTML, `includeIndex 1` enables the index with links to the occurrences,
labelled with the section title.

After typesetting, `docir::pdf::indexEntries` returns this index as a list
of `{term pages}` with the printed page numbers, so the indexes of several
PDFs can be merged into one combined index (bookkit `index-gesamt.tcl`).
For that the PDF sink turns a relative link to another PDF file,
`other.pdf` or `other.pdf#page=12`, into a jump to that page in that file
(`/GoToR`, pdf4tcl 0.9.4.73 or later; with an older pdf4tcl it stays a URI
link).

## Running header

In a long manual the page number alone does not tell where you are. The
header and footer templates (`header`, `footer`) therefore know `%t` (the
document title) and `%c`, the [running title]{.index}, besides `%p` (the
page): the first heading of level `runningLevel` (default 1) that starts on
the page, else the one still running -- as in a dictionary. TOC and index
pages show their titles. A tab splits a template into a left and a right
part:

```tcl
docir::pdf::render $ir book.pdf [dict create title "Tcl/Tk 9.0" \
    header "%t\t%c" footer "%p"]
```

A header with `%c` is drawn when the page is finished and gets a thin rule
below. With `runningProc` a command of your own returns several texts
instead of the heading, longest first; the first that fits the line is
used. bookkit `manual-build.tcl` passes the path and the neighbouring
chapters this way (`‹ disjointset  |  struct / graph  |  graph1 ›`), and only
the path or the name when space is short.

Text in `**...**` is set bold in header and footer. `manual-build.tcl`
uses it to mark the current page:
`‹ abstract  |  tcl / **after**  |  append ›`.
