# 1  Introduction

DocIR is a hub architecture for document conversion. A [source]{.index}
reads an input format into a common intermediate representation, the
[DocIR]{.index} (Document Intermediate Representation). Arbitrary
[sink]{.index}s produce the output formats from it. Sources and sinks do
not know each other; they communicate only through the IR.

## 1.1  The hub-and-spoke principle

A new source is immediately served by all sinks, and a new sink
immediately benefits from all sources. This keeps the number of converters
linear instead of quadratic: no source needs to know any sink — only the
IR.

## 1.2  The usual path

For Markdown the path runs through the [mdstack]{.index} parser to the
AST, from there through `docir::md::fromAst` into the IR, and finally
through a sink such as `docir::pdf` or `docir::html` into the output
format.

```tcl
package require mdstack::parser
package require docir::mdSource
package require docir::pdf

set ast [mdstack::parser::parse $markdown]
set ir  [docir::md::fromAst $ast]
docir::pdf::render $ir out.pdf {}
```

## 1.3  About this handbook

This handbook is itself an example of the book convention: Markdown
chapters without fixed numbers, index terms written as `[term]{.index}`,
an order defined in `book.tcl`, and a build to PDF and HTML via
`book-build.tcl` (from the **bookkit** toolkit).

# 2  The Intermediate Representation

The IR is a flat, fully typed sequence of block nodes. There is no tree:
nesting is expressed through `meta.level` and through ordering, not through
child lists. This makes the IR SAX-like, easy to render, and well
testable.

## 2.1  Structure of a node

Every [block node]{.index} has three fields:

```tcl
dict create \
    type    <string>   ;# required field
    content <any>      ;# list of inlines, items, or ""
    meta    <dict>     ;# may be empty: {}
```

The approach is defensive: unknown types are ignored rather than rejected,
and sinks tolerate missing or empty fields gracefully.

## 2.2  Block types

Block types include, among others, [heading]{.index} (with `meta.level`
1..6), `paragraph`, `pre` (code block), `list`, `table`, `doc_header`, and
`blank`. A `doc_header` carries document metadata (for example from a YAML
front matter or an nroff `.TH`).

## 2.3  Inline types

Inside `content` there are inline nodes: `text`, `strong`, `emphasis`,
`underline`, `strike`, `code`, `link`, `image`, `linebreak`, `softbreak`,
`footnote_ref`, `math`, and the [span]{.index}. The span carries a `class`
and an optional `id` and is the basis for index markers (see the chapter
on tables of contents and indexes).

Since 2026-10-21 span and `link` have the optional field `style`: a list of
`strong`, `emphasis` and `strike`, innermost first. It is set when the span
or link sat inside emphasis in the source: `**[adduser]{.index}**` becomes
`{type span text adduser class index style strong}`. HTML wraps it in
`<strong>`/`<em>`/`<s>`, PDF draws it bold or italic, Markdown writes the
markers back; the other sinks show the text.

## 2.4  Validation

`docir::validate $ir` checks an IR and returns an empty list for valid
input, or a list of error strings. Because the IR is sink-near and
source-format-neutral, a validated IR is valid for all sinks alike.

# 3  Sources

A [source]{.index} translates a source-format-specific AST into the IR.
The guiding principle is: the AST is close to the source, the IR is close
to the sinks. A source's mapping function may enrich, unify, and drop
whatever the sinks do not need.

## 3.1  Markdown

`docir::mdSource` provides `docir::md::fromAst`. The input is the AST of
the [mdstack]{.index} parser, the output is the IR.

```tcl
set ast [mdstack::parser::parse $markdown]
set ir  [docir::md::fromAst $ast]
```

Markdown headings become `heading` with `meta.level` taken from the number
of `#`. Each heading receives an anchor via `meta.id` (a slug derived from
the title) that is later used for cross-references and tables.

Emphasis (`**`, `*`, `~~`) is flattened: each piece of text inside becomes
its own `strong`, `emphasis` or `strike` inline. A span or link inside keeps
its node and carries the emphasis in `style`. Up to 2026-10-20 it was
flattened too; a term in bold was then missing from the index, a link in
bold lost its target.

## 3.2  nroff

`docir::roffSource` provides `docir::roff::fromAst` and translates the AST
of the nroff parser. Here unification is especially visible: nroff `.SH`
becomes `heading level=1`, `.SS` becomes `heading level=2`, and the nroff
`.TH` becomes the `doc_header`.

## 3.3  The term "heading"

A well-known stumbling block: in a source-near AST, `heading` can mean
something different from the IR. In the nroff AST, `heading` is the manpage
header (`.TH`); in the IR, `heading` is the generic heading. Sources
resolve this during mapping; in the IR the sink-near meaning holds
throughout.

# 4  Sinks

A [sink]{.index} produces an output format from the IR. All sinks work
exclusively on the IR and are therefore independent of the original
source.

## 4.1  PDF

`docir::pdf` renders to PDF via pdf4tcl and pdf4tcllib.

```tcl
docir::pdf::render $ir out.pdf [dict create \
    title "My Document" paper a4 footer "%p"]
```

The sink supports, among other things, a table of contents with page
numbers and a subject index (see the next chapter). It relies on the
Unicode-safe text and font handling of pdf4tcllib.

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
date is always set.

A code block that no longer fits on the page starts on the next one, in the
fixed-width font. Up to 2026-10-19 it came out proportional there, because
the page break writes the footer in the body font.

## 4.2  HTML

`docir::html` renders to self-contained HTML with embedded CSS.

```tcl
set html [docir::html::render $ir [dict create \
    title "My Document" includeToc 1]]
```

Headings receive their `id` as an anchor, so the table of contents and
cross-references work as clickable jump targets.

## 4.3  Further sinks

Besides PDF and HTML there are other [sink]{.index}s in the docir hub,
including a Markdown sink (round-trip), an nroff sink, an SVG and a Canvas
sink, a Tk renderer sink, and the tile sinks for cheat-sheet-style
layouts. Since they all work on the same IR, every source is automatically
available to each of these sinks.

# 5  Tables: Contents and Index

The table of contents and the subject index are both built from the IR and
are available in both main sinks.

## 5.1  Table of contents

The [table of contents]{.index} is built from the headings. In PDF,
`generateToc 1` enables a leading contents page with page numbers;
`tocTitle` and `tocDepth` control title and depth. In HTML, `includeToc 1`
does the same with clickable jump targets.

The page numbers in the PDF arise from a two-pass procedure: because the
contents page shifts the following pages, the document is laid out
repeatedly until the page numbers are stable.

## 5.2  Subject index

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

## 5.3  Running header

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

# 6  Building Books

A book is a directory of Markdown chapters that `book-build.tcl` (from the
**bookkit** toolkit) typesets in a single run to PDF and HTML.

## 6.1  Layout

One directory, one file per chapter. Headings carry **no** numbers in the
source; chapter and section numbers are produced during the build.

```
mybook/
    book.tcl
    010-introduction.md
    020-concepts.md
```

## 6.2  Order

There are two ways; the manifest takes precedence. If a [book.tcl]{.index}
exists, it defines the order via a `chapters` list (optionally also
`title` and `author`); the filename prefix is then ignored. Without the
manifest, the numeric [prefix]{.index} in the filename determines the
order. A generator run writes a manifest from the prefixes, which can then
be reordered freely:

```
tclsh bookkit/tools/book-build.tcl manifest mybook/
```

## 6.3  Numbering and stable references

The `-number` option assigns hierarchical numbers (`1`, `1.1`, `1.1.1`)
from nesting and order. Because the [numbering]{.index} happens on the IR,
it appears consistently in the text, the table of contents, the bookmarks,
and in both output formats.

Anchors are built from the title, not from the number. Reordering
therefore changes the numbers but not the anchors — cross-references to
`#title-anchor` remain valid.

## 6.4  Building

```
tclsh bookkit/tools/book-build.tcl mybook/ -number
tclsh bookkit/tools/book-build.tcl mybook/ -pdf out.pdf -html out.html -number
```

Without `-pdf`/`-html`, both formats are produced next to the book
directory. The switches `-no-toc` and `-no-index` omit the tables,
`-depth N` controls the depth of numbering and table of contents.

# 7  Your Own Source and Sink

The hub thrives on [source]{.index}s and [sink]{.index}s arising
independently of one another. Both are connected through the IR and need
not know each other.

## 7.1  Writing a source

A source translates a source-format-specific AST into the IR. At its core
it is a function that produces the matching IR block for each AST node:

```tcl
namespace eval myformat {}

proc myformat::fromAst {ast} {
    set ir {}
    foreach node $ast {
        switch [dict get $node type] {
            title   { lappend ir [dict create type heading \
                          content [list [dict create type text \
                              text [dict get $node text]]] \
                          meta [dict create level 1]] }
            para    { lappend ir [dict create type paragraph \
                          content [list [dict create type text \
                              text [dict get $node text]]] meta {}] }
        }
    }
    return $ir
}
```

The result can then be checked with `docir::validate` and handed to any
sink.

## 7.2  Writing a sink

A sink iterates over the flat IR and produces the output format. Because
the IR is flat, a loop with a `switch` over `type` suffices — no tree
recursion needed:

```tcl
namespace eval myrender {}

proc myrender::render {ir} {
    set out ""
    foreach node $ir {
        switch [dict get $node type] {
            heading   { append out ">> " [text [dict get $node content]] "\n" }
            paragraph { append out [text [dict get $node content]] "\n\n" }
            default   { }   ;# ignore unknown types, do not abort
        }
    }
    return $out
}
```

The `default` branch ignores unknown types instead of aborting — this is
the defensive baseline of the IR.

## 7.3  The hub promise

As soon as the new source yields valid IR, all existing sinks serve it —
PDF, HTML, and the rest. As soon as the new sink processes the IR, it
benefits from all sources. It is exactly this cut at the [intermediate representation]{.index} that keeps the number of converters small.
