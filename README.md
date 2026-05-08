# DocIR — Document Intermediate Representation

Hub architecture for document conversion between different source and
target formats via a sequential node-based IR.

```
[Sources]                  [Hub]              [Sinks]

  nroff   ──→ docir::roffSource  ──┐                     ┌──→ docir::rendererTk
                                   │                     │
  Markdown ─→ docir::mdSource    ──┤  ──→ DocIR ──→ ─────┼──→ docir::html
                                                          ├──→ docir::md
                                                          ├──→ docir::pdf
                                                          ├──→ docir::svg
                                                          ├──→ docir::canvas
                                                          ├──→ docir::roff
                                                          ├──→ docir::tilepdf
                                                          ├──→ docir::tilehtml
                                                          └──→ docir::tilemd
```

A new source is automatically served by all 9 sinks. A new sink
immediately benefits from all sources.

## Packages

### Spec / Core

| Package             | Provides                       |
|---------------------|--------------------------------|
| `docir`             | `::docir::validate ir`         |
|                     | DocIR spec, validator          |
| `docir::tilecommon` | `::docir::tile::streamToSheets`, `packSection`, `tokenize`, `inlinesToText` (used by tilepdf, tilehtml, tilemd) |

### Sources (FORMAT-AST → DocIR)

| Package              | Function                       | Input       |
|----------------------|--------------------------------|-------------|
| `docir::roffSource`  | `::docir::roff::fromAst ast`   | nroff AST   |
| `docir::mdSource`    | `::docir::md::fromAst ast`     | Markdown AST|

### Sinks (DocIR → FORMAT output)

**General sinks:**

| Package              | Function                       | Output         |
|----------------------|--------------------------------|----------------|
| `docir::html`        | `::docir::html::render ir ?opts?` | HTML        |
| `docir::md`          | `::docir::md::render ir ?opts?`   | Markdown    |
| `docir::pdf`         | `::docir::pdf::render ir file ?opts?` | PDF (requires pdf4tcl) |
| `docir::roff`        | `::docir::roff::render ir ?opts?` | nroff (man pages) |
| `docir::svg`         | `::docir::svg::render ir ?opts?`  | SVG         |
| `docir::canvas`      | `::docir::canvas::render ir ?opts?` | Tk canvas commands |
| `docir::rendererTk`  | `::docir::renderer::tk::render ir w ?opts?` | Tk text widget |

**Tile sinks** (two-column cheatsheet layouts):

| Package             | Function                                | Output                    |
|---------------------|----------------------------------------|---------------------------|
| `docir::tilepdf`    | `::docir::tilepdf::render ir file ?opts?` | PDF, 2 columns (fixed), light/dark |
| `docir::tilehtml`   | `::docir::tilehtml::render ir file ?opts?` | HTML, CSS Grid 1-4 columns, 5 themes |
| `docir::tilemd`     | `::docir::tilemd::render ir file ?opts?` | Markdown, linear structure |

Tile sink comparison: see [doc/en/docir-spec.md](doc/en/docir-spec.md#tile-sinks-comparison).

### CLI tools (in `bin/`)

| Tool          | Pipeline                                              |
|---------------|-------------------------------------------------------|
| `md2tilepdf`     | mdparser → DocIR → tilepdf → PDF                      |
| `md2tilehtml` | mdparser → DocIR → tilehtml → HTML                    |
| `md2tilemd`   | mdparser → DocIR → tilemd → structured Markdown       |

Installation: `make install-bin` (copies to `$PREFIX/bin/`).

```bash
md2tilepdf cheatsheet.md                           # → cheatsheet.pdf
md2tilehtml *.md -t dark -o all.html            # multi-MD, dark theme
md2tilemd README.md --no-toc -o README.tile.md  # linear, no TOC
```

## Naming conventions

- **Hub module** is `docir` (validator, schema-version, isSchemaOnly)
- **Sinks** are `docir::FORMAT` (FORMAT = output format)
- **Sources** are `docir::FORMATSource` (FORMAT = input format, CamelCase
  because hyphens in module names confuse Tcl's version parser)
- The Tcl namespace is `::docir::FORMAT::*` (source and sink share it)
- Sources export `fromAst`, sinks export `render`
- Both packages (source and sink) for the same FORMAT can be loaded
  simultaneously — they coexist without conflict

## Usage

```tcl
package require docir              ;# spec/validator (hub)
package require docir::roffSource  ;# nroff → DocIR
package require docir::html        ;# DocIR → HTML

set ast  [nroffparser::parse $nroffText]
set ir   [::docir::roff::fromAst $ast]
set html [::docir::html::render $ir [dict create theme manpage lang en]]
```

Before the first `package require`, the module must be on a Tcl tm path
or in `auto_path` — see **Installation** below.

## Installation

DocIR follows the **standard Tcl convention** with `pkgIndex.tcl`: the
module directory contains a pkgIndex.tcl, and Tcl finds the modules
automatically once the parent directory is in `auto_path`.

### System install (all users, sudo)

```bash
sudo make install        # to /usr/local/lib/tcltk/docir/
```

`/usr/local/lib/tcltk/` is on Tcl's standard `auto_path` on Linux/macOS
— no further setup needed. Apps just call `package require docir::roff`
and Tcl finds the module.

### User install (no sudo)

```bash
make install-user        # to ~/lib/tcltk/docir/
export TCLLIBPATH="$HOME/lib/tcltk/docir"   # set in ~/.profile
```

`TCLLIBPATH` is the standard Tcl env variable that extends `auto_path`.

### Manual

```bash
sudo cp -r lib/tm/. /usr/local/lib/tcltk/docir/
```

or wherever you like. The directory just needs to contain `pkgIndex.tcl`
plus all `.tm` files and the `docir/` sub-directory after copying.

### Regenerating pkgIndex.tcl

After module changes or new modules:

```bash
make pkgindex
# or
tclsh tools/generate-pkgindex.tcl lib/tm --write
```

## Tests

```bash
cd tests
tclsh run-all-tests.tcl
```


PDF tests need [pdf4tcl](https://sourceforge.net/projects/pdf4tcl/) and
[pdf4tcllib](https://github.com/gregnix/pdf4tcllib) installed. Tests
skip cleanly when these packages are missing.

## DocIR spec

See `doc/en/docir-spec.md` for the full IR specification.

## Consumer repos

The following repos use DocIR:

- **man-viewer** — nroff manpage browser with DocIR pipeline for export
- **mdstack** — Markdown stack tools (uses `docir::mdSource`)
- **mdhelp** — Markdown help browser (uses `docir::mdSource` + sinks)

## License

(to be defined)

## History

Until May 2026, DocIR was a sub-system inside `man-viewer`. Naming
conflicts with mdstack and growing independence (spec, validator, own
tests) led to it being extracted into its own repo in May 2026. On
2026-05-07 the Tcl module namespace refactor followed, with the
sub-directory layout (`docir-roff` → `docir::roff`).

In the same week the tile renderers were added (tilepdf, tilehtml,
tilemd).
Tile = two-column cheatsheet style, atomic sections, section-type
classification (`code`, `code-intro`, `hint`, `list`, `table`, `image`)
unified across all three tile renderers (via `docir::tilecommon`).


