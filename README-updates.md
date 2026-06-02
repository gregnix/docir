# README-Updates für docir

Einfügbare Blöcke, damit dein vorhandener README-Text erhalten bleibt.
Jeweils den genannten Abschnitt **ersetzen**.

---

## 1. Diagramm ersetzen

Ersetze den ```` ``` ````-Block ganz oben (`[Sources] ... [Sinks]`) durch:

```
[Sources]                    [Hub]              [Sinks]

  nroff    ─→ docir::roffSource ─┐                      ┌─→ docir::rendererTk
  Markdown ─→ docir::mdSource   ─┤                      ├─→ docir::html
  ODT      ─→ docir::odtSource  ─┤                      ├─→ docir::odt
  HTML     ─→ docir::htmlSource ─┼─→ DocIR ─→ ──────────┼─→ docir::md
  .csd     ─→ docir::csdSource  ─┤                      ├─→ docir::pdf
  Tk-Widget→ docir::tkSource    ─┘                      ├─→ docir::svg
                                                        ├─→ docir::canvas
                                                        ├─→ docir::roff
                                                        ├─→ docir::tilepdf
                                                        ├─→ docir::tilehtml
                                                        └─→ docir::tilemd
```

Und den Satz darunter anpassen:

> A new source is automatically served by all sinks. A new sink
> immediately benefits from all sources. ODT and HTML are **bidirectional**
> (source + sink), enabling round-trips such as `ODT → DocIR → ODT` and
> `HTML → DocIR → PDF`.

---

## 2. Sources-Tabelle ersetzen

Ersetze die Tabelle unter `### Sources (FORMAT-AST → DocIR)` durch
(Überschrift leicht angepasst, weil nicht alle Quellen über einen AST gehen):

```
### Sources (… → DocIR)

| Package              | Function                              | Input            |
|----------------------|---------------------------------------|------------------|
| `docir::roffSource`  | `::docir::roff::fromAst ast`          | nroff AST        |
| `docir::mdSource`    | `::docir::md::fromAst ast`            | Markdown AST     |
| `docir::odtSource`   | `::docir::odtSource::fromOdt path`    | ODT file         |
| `docir::htmlSource`  | `::docir::htmlSource::fromHtml html`  | HTML string      |
| `docir::tkSource`    | `::docir::tkSource::fromWidget w ?i1 i2?` | Tk text widget |
| `docir::csdSource`   | `::docir::csd::toSheet csdDict`       | .csd cheatsheet  |

AST-basierte Quellen (`roff`, `md`) exportieren `fromAst`; ODT/HTML/Tk
lesen direkt aus Datei / String / Widget. `tkSource` liefert zusätzlich
`::docir::tkSource::media` (Bild-Bytes des letzten `fromWidget`).
```

---

## 3. Sinks-Tabelle: eine Zeile ergänzen

In **General sinks** nach der `docir::md`-Zeile einfügen:

```
| `docir::odt`         | `::docir::odt::write ir path ?opts?` | ODT (OpenDocument Text), Bilder via `media`-Option |
```

---

## 4. Demo-Tabelle ergänzen

Im Abschnitt mit den Demos (`canvas_demo.tcl` …) ergänzen:

```
| `demo-odt.tcl`    | DocIR → ODT und zurück → HTML/MD/TXT (CLI)                  | `tclsh demo/demo-odt.tcl`     |
| `demo-html.tcl`   | HTML → DocIR → PDF/MD/HTML (CLI)                            | `tclsh demo/demo-html.tcl`    |
| `demo-tk2odt.tcl` | Tk-Widget-Inhalt → ODT via tkSource (GUI)                  | `wish demo/demo-tk2odt.tcl`   |
```

---

## 5. „Related repositories" ergänzen

```
- **odt** — generischer ODT-Leser (Paket `odt`); Basis von `docir::odtSource`
```
