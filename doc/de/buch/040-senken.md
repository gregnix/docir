# Senken

Eine [Senke]{.index} erzeugt aus der IR ein Ausgabeformat. Alle Senken
arbeiten ausschliesslich auf der IR und sind damit von der ursprünglichen
Quelle unabhaengig.

## PDF

`docir::pdf` rendert ueber pdf4tcl und pdf4tcllib nach PDF.

```tcl
docir::pdf::render $ir out.pdf [dict create \
    title "Mein Dokument" paper a4 footer "%p"]
```

Die Senke unterstuetzt unter anderem ein Inhaltsverzeichnis mit
Seitenzahlen und einen Sachindex (siehe das naechste Kapitel). Sie nutzt
die Unicode-sichere Text- und Schrift-Behandlung von pdf4tcllib.

Ein Codeblock, der nicht mehr auf die Seite passt, beginnt auf der
naechsten, in fester Schrift. Bis 2026-10-19 kam er dort proportional
heraus, weil der Seitenumbruch die Fusszeile in der Grundschrift schreibt.

Die [Synopsis]{.index} einer Handbuchseite nach TIP 700
(`::: {.synopsis}` mit den Spans `.cmd .sub .lit .arg .ins .optarg .optlit
.optdot`) steht im PDF eine Zeile je Aufrufform, gesetzt wie in den
Tcl-Manpages: `.cmd .sub .lit` fett, `.arg .ins` kursiv, die optionalen in
Fragezeichen (`?id?`, `?-strict?`, `?script script ...?`). Das gilt fuer
einen Absatz, der nur aus diesen Spans, Leerzeichen und weichen
Zeilenumbruechen besteht und mit `.cmd` oder `.ins` beginnt; andere Absaetze
bleiben, wie sie sind. Bis 2026-10-23 lief die Synopsis als ein Absatz
durch.

Fuer die [Metadaten]{.index} des PDF gibt es neben `title` und `author`
die Optionen `subject`, `keywords`, `creator` (Vorgabe `docir::pdf`) und
`lang`, die Sprache des Dokuments als BCP-47-Kennung (`"de"`,
`"en-GB"`). Sie steht im Katalog und in den XMP-Daten, sodass Leseprogramme
und Vorleser die richtige Sprache nehmen; das braucht pdf4tcl ab 0.9.4.73.
Das Erstelldatum wird immer gesetzt.

## HTML

`docir::html` rendert nach eigenstaendigem HTML mit eingebettetem CSS.

```tcl
set html [docir::html::render $ir [dict create \
    title "Mein Dokument" includeToc 1]]
```

Ueberschriften erhalten ihre `id` als Anker, sodass das Inhaltsverzeichnis
und Querverweise als klickbare Sprungziele funktionieren.

## Weitere Senken

Neben PDF und HTML gibt es weitere [Senke]{.index}n im docir-Hub, darunter
eine Markdown-Senke (Round-Trip), eine nroff-Senke, eine SVG- und eine
Canvas-Senke, eine Tk-Renderer-Senke sowie die Tile-Senken fuer
Spickzettel-artige Layouts. Da alle auf derselben IR arbeiten, steht jede
Quelle automatisch jeder dieser Senken zur Verfuegung.
