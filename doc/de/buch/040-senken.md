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
