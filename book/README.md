# Book tooling — moved to the bookkit repository

The book **tooling** that used to live here is now the standalone **bookkit**
repository — its own repo, kept next to docir. bookkit is the canonical,
maintained version: the same `docir + mdstack + pdf4tcl` book format, plus
multilingual tools, a migration guide and web output.

| Was here | Now (in the bookkit repo) |
|---|---|
| `book-build.tcl` | `bookkit/tools/book-build.tcl` |
| `book-template/` | `bookkit/template/` |
| `manual-build.tcl` | `bookkit/tools/manual-build.tcl` |
| format / conventions | `bookkit/SPEC.md` |
| tool reference | `bookkit/doc/TOOLS.md` |

## docir's own manual

The chapters under `doc/en/book/` (and `doc/de/buch/`) are docir's own
documentation, written in the book format. They stay here as **content** and are
built with bookkit. With docir and bookkit checked out side by side, from the
workspace root:

    tclsh bookkit/tools/book-build.tcl docir/doc/en/book/ -number

## Building a manpage manual

    tclsh bookkit/tools/manual-build.tcl <dir> -pdf out.pdf -html out.html

bookkit needs `docir`, `mdstack` and `pdf4tcl` reachable (sibling repos or the
`*_HOME` environment variables). This is a build-time dependency for the
documentation only; docir itself has no runtime dependency on bookkit.
