# The Intermediate Representation

The IR is a flat, fully typed sequence of block nodes. There is no tree:
nesting is expressed through `meta.level` and through ordering, not through
child lists. This makes the IR SAX-like, easy to render, and well
testable.

## Structure of a node

Every [block node]{.index} has three fields:

```tcl
dict create \
    type    <string>   ;# required field
    content <any>      ;# list of inlines, items, or ""
    meta    <dict>     ;# may be empty: {}
```

The approach is defensive: unknown types are ignored rather than rejected,
and sinks tolerate missing or empty fields gracefully.

## Block types

Block types include, among others, [heading]{.index} (with `meta.level`
1..6), `paragraph`, `pre` (code block), `list`, `table`, `doc_header`, and
`blank`. A `doc_header` carries document metadata (for example from a YAML
front matter or an nroff `.TH`).

## Inline types

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

## Validation

`docir::validate $ir` checks an IR and returns an empty list for valid
input, or a list of error strings. Because the IR is sink-near and
source-format-neutral, a validated IR is valid for all sinks alike.
