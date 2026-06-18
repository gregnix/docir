# First Topic

A second chapter. Code blocks render verbatim in both PDF and HTML:

```tcl
puts "Hello from your book"
```

Lists, tables, emphasis and links all work as in normal Markdown. Refer to
another chapter by its title anchor, for example the
[Introduction](#introduction).

## Building this book

From inside this directory:

    tclsh ../../tools/book-build.tcl . -number

You get a PDF and an HTML file next to the directory, each with a title
page, numbered chapters, a [table of contents]{.index} and a subject
[index]{.index}.
