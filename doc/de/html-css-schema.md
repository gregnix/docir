# HTML-CSS-Schema fuer `docir::html`

**Stand:** 2026-05-10
**Modul:** `docir/lib/tm/docir/html-0.1.tm`

Diese Datei dokumentiert die HTML-Struktur und CSS-Klassen die
`docir::html::render` erzeugt. Sie ist die **Schnittstelle zwischen
Renderer und Stylesheet-Autoren**: Wer eigene CSS fuer docir-HTML
schreibt, kann sich auf die hier gelisteten Klassen verlassen.

Die docir-eigenen Default-Stylesheets liegen im Modul-Code (siehe
`_defaultCss`). Beispiel-Themes mit alternativen Layouts liegen im
mdhelp-Repo unter `mdhelp/styles/`.

---

## Dokumenten-Geruest

```html
<!DOCTYPE html>
<html lang="...">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="..."/>
  <title>...</title>
  <style>...</style>            <!-- inline, oder externer Link -->
</head>
<body>
  <nav class="toc">             <!-- nur wenn -toc 1 -->
    <ul>
      <li class="toc-level-1"><a href="#anker">Heading</a></li>
      <li class="toc-level-2"><a href="#anker">Sub-Heading</a></li>
      ...
    </ul>
  </nav>

  <h1 id="...">...</h1>         <!-- Standard-Markdown-Output -->
  <p>...</p>
  <h2 id="...">...</h2>
  ...
</body>
</html>
```

---

## Standard-HTML-Tags

Aus normaler Markdown-Konvertierung — keine docir-spezifischen
Klassen, aber ueblicherweise mitstylebar:

| Tag                        | Wofuer                          |
|----------------------------|---------------------------------|
| `h1`, `h2`, `h3`, …, `h6`  | Headings                        |
| `p`                        | Absatz                          |
| `ul`, `ol`, `li`           | Listen                          |
| `dt`, `dd`, `dl`           | Definitionslisten               |
| `a`                        | Link                            |
| `code`                     | Inline-Code                     |
| `pre`                      | Code-Block                      |
| `pre code`                 | Code im Code-Block (kombiniert) |
| `blockquote`               | Zitat                           |
| `table`, `tr`, `td`, `th`  | Tabellen                        |
| `colgroup`, `col`          | Tabellen-Spaltendefinition      |
| `hr`                       | Horizontale Trennlinie          |
| `img`                      | Bilder                          |
| `figure`, `figcaption`     | Bild mit Beschriftung           |
| `strong`, `em`, `s`, `u`   | Inline-Formatierung             |
| `sup`                      | Hochgestellt (auch Footnotes)   |
| `br`                       | Zeilenumbruch                   |
| `section`                  | Semantischer Block              |

---

## docir-spezifische Klassen

Diese Klassen sind **nur** bei docir::html-Output garantiert. Andere
Markdown-zu-HTML-Konverter erzeugen sie nicht.

### TOC (Table of Contents)

Erzeugt mit `-toc 1`-Option.

| Selektor                           | Was               |
|------------------------------------|-------------------|
| `nav.toc`                          | TOC-Container     |
| `nav.toc ul`                       | Liste der Eintraege |
| `nav.toc li.toc-level-1`           | Top-Level (`<h1>`) |
| `nav.toc li.toc-level-2`           | 2. Ebene (`<h2>`)  |
| `nav.toc li.toc-level-3`           | 3. Ebene (`<h3>`)  |
| ... bis `toc-level-6`              | bis `<h6>`         |
| `nav.toc a[href="#..."]`           | TOC-Eintrag-Link   |

**Beispiel:**

```css
nav.toc { background: #f9f9f9; padding: 1em; border-radius: 4px; }
nav.toc li.toc-level-2 { padding-left: 1em; }
nav.toc li.toc-level-3 { padding-left: 2em; font-size: 0.9em; }
nav.toc a { color: #0055aa; text-decoration: none; }
```

### Manpage-Header

Wenn die docir-Quelle ein manpage-Doc ist (z.B. konvertiert aus tcllib
oder docir-md):

| Selektor                       | Was                                         |
|--------------------------------|---------------------------------------------|
| `header.manpage-header`        | Manpage-Header-Block                        |
| `header.manpage-header h1`     | Inline-H1 ohne Border (manpage-Style)       |
| `.maninfo`                     | Inline-Info (Version, Section, etc.)        |
| `.version`                     | Versionsnummer                              |
| `.part`                        | Manpage-Section (z.B. "(n)", "(3tcl)")      |

### Document Header (allgemein)

| Selektor                       | Was                                         |
|--------------------------------|---------------------------------------------|
| `.docir-doc-header`            | Allgemeiner Doku-Header                     |
| `.docir-doc-header .name`      | Doku-Name (fett)                            |

### Listen-Varianten

docir kennt mehrere Listentypen (von tcllib-Doctools-Konventionen):

| Selektor                   | Was                                              |
|----------------------------|--------------------------------------------------|
| `.docir-list-tp`           | Term-Pair-Liste (dt/dd, fett-Term + indent-Beschreibung) |
| `.docir-list-tp dt`        | Term (fett)                                      |
| `.docir-list-tp dd`        | Definition (eingerueckt)                         |
| `.docir-list-ip`           | Indented-Paragraph-Liste                         |
| `ul.iplist`                | Alternative Indented-List mit Disc-Bullets       |
| `ul.iplist li`             | Listeneintrag                                    |

### Einrueckungs-Klassen

Manuell gesetzte Einrueckungen (z.B. fuer verschachtelte tcllib-Doctools):

| Selektor      | Margin-Left |
|---------------|-------------|
| `.indent-1`   | 2em         |
| `.indent-2`   | 4em         |
| `.indent-3`   | 6em         |
| `.indent-4`   | 8em         |

### Tabellen-Varianten

| Selektor                                       | Was                            |
|------------------------------------------------|--------------------------------|
| `table.docir-standard-options`                 | Optionsliste, monospaced       |
| `table.docir-standard-options td`              | Optionseintraege               |
| `table.docir-table`                            | Standard-Datentabelle          |
| `table.docir-table td`, `table.docir-table th` | Zellen mit Border              |
| `table.docir-table th`                         | Header-Zellen mit Hintergrund  |

### Footnotes

| Selektor                       | Was                                         |
|--------------------------------|---------------------------------------------|
| `<sup>` (im Text)              | Footnote-Anker                              |
| `<a class="back">↩</a>`        | Rueckverweis von Footnote zum Anker         |

### Diagnose-Klassen

| Selektor                       | Wann                                        |
|--------------------------------|---------------------------------------------|
| `.docir-unknown`               | Unbekannter Block-Typ — gelb hinterlegt     |
| `.docir-blank`                 | Leerzeile (line-height 1.0)                 |

---

## Best Practices fuer eigene Stylesheets

### 1. Auf Klassen-Namen verlassen, nicht auf Tag-Reihenfolge

Schlecht:
```css
body > p:nth-child(2) { ... }   /* fragil */
```

Gut:
```css
.docir-list-tp dd { ... }        /* explizit */
nav.toc li.toc-level-2 { ... }
```

### 2. CSS-Grid und docir::html-Output

Wenn du `body { display: grid }` nutzt: explizit `grid-column` setzen
fuer alle direkten Kinder, sonst verteilt das Auto-Placement
abwechselnd auf alle Spalten:

```css
body { display: grid; grid-template-columns: 280px 1fr; }
nav.toc { grid-column: 1; grid-row: 1 / -1; }
body > *:not(nav.toc) { grid-column: 2; }   /* WICHTIG */
```

### 3. Backwards-Compatible bleiben

Wenn dein Stylesheet auch fuer Markdown-zu-HTML-Output anderer Konverter
funktionieren soll: nur Standard-Tags stylen, keine `.docir-*`-Klassen.
Diese sind docir-spezifisch.

---

## Beispiel-Stylesheets

Im mdhelp-Repo (oder beliebigem Aufrufer):

- `mdhelp/styles/sticky-top.css` — TOC oben, scrollt mit
- `mdhelp/styles/sidebar.css` — TOC links als Sidebar (280px), Body rechts
- `mdhelp/styles/collapsible.css` — TOC zugeklappt, Hover oeffnet

Diese Stylesheets sind **mdhelp-Ressourcen**, nicht Teil von docir.
docir bleibt CSS-frei (ausser dem internen `_defaultCss` als Fallback).

---

## Aufruf mit eigenem CSS

```tcl
package require docir::html

# Direkt
set html [docir::html::render $ir [list \
    title    "Mein Doc" \
    cssFile  "/pfad/zu/style.css" \
    includeToc 1]]

# Ueber mdstack-Adapter
package require mdstack::html
mdstack::html::export $ast output.html \
    -title "Mein Doc" \
    -css   "/pfad/zu/style.css" \
    -toc   1
```

`-css`/`cssFile` ersetzt den `_defaultCss` durch den Inhalt der Datei.
Wenn keine Option uebergeben: Default-CSS (im Modul) wird verwendet.

---

## Versions-Historie dieses Schemas

- **2026-05-10:** Erstfassung. Klassen aus html-0.1.tm extrahiert.

Bei aenderung am `docir::html`-Renderer: bitte hier nachziehen, damit
Stylesheet-Autoren wissen worauf sie sich verlassen koennen.
