# Buecher bauen

Ein Buch ist ein Verzeichnis aus Markdown-Kapiteln, das `book-build.tcl`
in einem Durchgang nach PDF und HTML setzt.

## Aufbau

Ein Verzeichnis, eine Datei je Kapitel. Ueberschriften tragen in der
Quelle **keine** Nummern; Kapitel- und Abschnittsnummern entstehen beim
Bauen.

```
mybook/
    book.tcl
    010-einleitung.md
    020-konzepte.md
```

## Reihenfolge

Es gibt zwei Wege, das Manifest hat Vorrang. Existiert ein [book.tcl]{.index},
legt es die Reihenfolge ueber eine Liste `chapters` fest (optional auch
`title` und `author`); der Dateinamen-Praefix wird dann ignoriert. Fehlt
das Manifest, bestimmt der numerische [Praefix]{.index} im Dateinamen die
Reihenfolge. Ein Generatorlauf schreibt aus den Praefixen ein Manifest,
das sich anschliessend frei umsortieren laesst:

```
tclsh book-build.tcl manifest mybook/
```

## Nummerierung und stabile Verweise

Die Option `-number` vergibt hierarchische Nummern (`1`, `1.1`, `1.1.1`)
aus Verschachtelung und Reihenfolge. Da die [Nummerierung]{.index} auf der
IR geschieht, erscheint sie konsistent in Text, Inhaltsverzeichnis,
Lesezeichen und in beiden Ausgabeformaten.

Anker werden aus dem Titel gebildet, nicht aus der Nummer. Umsortieren
aendert daher die Nummern, aber nicht die Anker — Querverweise auf
`#titel-anker` bleiben gueltig.

## Bauen

```
tclsh book-build.tcl mybook/ -number
tclsh book-build.tcl mybook/ -pdf out.pdf -html out.html -number
```

Ohne `-pdf`/`-html` werden beide Formate neben dem Buch-Verzeichnis
erzeugt. Die Schalter `-no-toc` und `-no-index` lassen die Verzeichnisse
weg, `-depth N` steuert die Tiefe von Nummerierung und Inhaltsverzeichnis.
