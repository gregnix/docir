# Tile Renderer Examples

This directory shows what the `docir::tilepdf`, `docir::tilehtml`, and
`docir::tilemd` renderers produce. Two parts:

```
demo/tile-examples/
├── sources/                    Three input Markdown files
│   ├── grid-advanced.md
│   ├── widget-packing.md
│   └── place.md
└── output-examples/            Pre-built outputs you can open directly
    ├── grid-light.html         tilehtml, light theme, single sheet
    ├── grid-dark.html          tilehtml, dark theme, single sheet
    ├── combined-3-md.pdf       tilepdf, three sources combined into one PDF
    └── multi.tile.md           tilemd, three sources as linear Markdown
```

## What the tile renderers do

The tile family produces **two-column cheatsheet-style output** (HTML
and PDF) or **linear structured Markdown** (MD), with atomic sections
that don't break across columns. Section types are classified
automatically: `code`, `code-intro`, `hint`, `list`, `table`, `image`.

A **sheet** corresponds to one `# H1` heading in the source. Multiple
sources produce a multi-sheet output.

## Reproducing the examples

After `make install` (or `make install-user` plus `TCLLIBPATH`), the
CLI tools are available as `md2tilepdf`, `md2tilehtml`, `md2tilemd`.

### Single source

```bash
md2tilehtml sources/grid-advanced.md grid-light.html
md2tilehtml sources/grid-advanced.md grid-dark.html  -t dark
md2tilepdf  sources/grid-advanced.md grid-advanced.pdf
md2tilemd   sources/grid-advanced.md grid-advanced.tile.md
```

### Three sources combined

```bash
md2tilepdf sources/grid-advanced.md \
           sources/widget-packing.md \
           sources/place.md \
           -o combined-3-md.pdf

md2tilemd sources/grid-advanced.md \
          sources/widget-packing.md \
          sources/place.md \
          -o multi.tile.md
```

## Available themes (tilehtml)

| Theme       | Flag           | Description                       |
|-------------|----------------|-----------------------------------|
| `light`     | `-t light`     | Default, white background         |
| `dark`      | `-t dark`      | Dark background                   |
| `auto`      | `-t auto`      | Follows system preference         |
| `solarized` | `-t solarized` | Solarized Light                   |
| `sepia`     | `-t sepia`     | Warm beige-yellow                 |

## Column count (tilehtml)

| Flag       | Result                                |
|------------|---------------------------------------|
| `-c 1`     | Single column (mobile-style)          |
| `-c 2`     | Two columns (default)                 |
| `-c 3`     | Three columns (compact print)         |
| `-c 4`     | Four columns                          |

## Multi-sheet TOC

When several sources are combined, a TOC sheet is produced
automatically at the top of the document with anchor links to each
sheet. Disable with `--no-toc`.

```bash
md2tilehtml *.md -o all.html              # with TOC
md2tilehtml *.md -o all.html --no-toc     # no TOC
```

## When to use which renderer

| Renderer    | Best for                                               |
|-------------|--------------------------------------------------------|
| `tilehtml`  | Web cheatsheets, browser display, themes, links        |
| `tilepdf`   | Printable cheatsheets, two fixed columns, light/dark   |
| `tilemd`    | GitHub/Notion/Obsidian display, further editing of MD  |

## Sources

The three source documents in `sources/` come from the Tcl/Tk
documentation effort: layout managers (`grid-advanced.md`,
`widget-packing.md`, `place.md`).
