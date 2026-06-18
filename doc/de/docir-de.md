# Einleitung

DocIR ist eine Hub-Architektur fuer die Dokument-Konvertierung. Eine
[Quelle]{.index} liest ein Eingabeformat in eine gemeinsame Zwischen-
darstellung, die [DocIR]{.index} (Document Intermediate Representation).
Beliebige [Senken]{.index} erzeugen daraus die Ausgabeformate. Quellen und
Senken kennen einander nicht; sie sprechen ausschliesslich ueber die IR.

## Das Nabe-Speiche-Prinzip

Eine neue Quelle wird sofort von allen Senken bedient, und eine neue Senke
profitiert sofort von allen Quellen. So bleibt die Zahl der noetigen
Konverter linear statt quadratisch: nicht jede Quelle muss jede Senke
kennen, sondern nur die IR.

## Der uebliche Weg

Fuer Markdown fuehrt der Weg ueber den [mdstack]{.index}-Parser zum AST,
von dort ueber `docir::md::fromAst` in die IR, und schliesslich ueber eine
Senke wie `docir::pdf` oder `docir::html` ins Ausgabeformat.

```tcl
package require mdstack::parser
package require docir::mdSource
package require docir::pdf

set ast [mdstack::parser::parse $markdown]
set ir  [docir::md::fromAst $ast]
docir::pdf::render $ir out.pdf {}
```

## Zu diesem Handbuch

Dieses Handbuch ist selbst ein Beispiel fuer die Buch-Konvention: Markdown-
Kapitel ohne feste Nummern, Index-Begriffe als `[Begriff]{.index}`, eine
Reihenfolge in `book.tcl` und ein Build nach PDF und HTML mit
`book-build.tcl`.

# Die Zwischendarstellung

Die IR ist eine flache, vollstaendig typisierte Folge von Block-Knoten. Es
gibt keinen Baum: Verschachtelung wird ueber `meta.level` und die
Reihenfolge ausgedrueckt, nicht ueber Kind-Listen. Das macht die IR
SAX-artig, leicht zu rendern und gut testbar.

## Aufbau eines Knotens

Jeder [Block-Knoten]{.index} hat drei Felder:

```tcl
dict create \
    type    <string>   ;# Pflichtfeld
    content <any>      ;# Liste von Inlines, Items oder ""
    meta    <dict>     ;# darf leer sein: {}
```

Das Prinzip ist defensiv: Unbekannte Typen werden ignoriert statt
abgelehnt, und Senken behandeln fehlende oder leere Felder vertraeglich.

## Block-Typen

Zu den Block-Typen zaehlen unter anderem [heading]{.index} (mit
`meta.level` 1..6), `paragraph`, `pre` (Codeblock), `list`, `table`,
`doc_header` sowie `blank`. Ein `doc_header` traegt Dokument-Metadaten
(etwa aus einer YAML-Frontmatter oder einem nroff-`.TH`).

## Inline-Typen

Innerhalb von `content` stehen Inline-Knoten: `text`, `strong`,
`emphasis`, `underline`, `strike`, `code`, `link`, `image`, `linebreak`,
`softbreak`, `footnote_ref`, `math` und der [span]{.index}. Der span
traegt eine `class` und eine optionale `id` und ist die Grundlage fuer
Index-Markierungen (siehe das Kapitel zu Verzeichnissen).

## Validierung

`docir::validate $ir` prueft eine IR und liefert eine leere Liste bei
gueltiger Eingabe oder eine Liste von Fehlermeldungen. Da die IR
sink-nah und quellformat-neutral ist, gilt eine validierte IR fuer alle
Senken gleichermassen.

# Quellen

Eine [Quelle]{.index} uebersetzt einen quellformat-spezifischen AST in die
IR. Der Leitsatz lautet: der AST ist quellnah, die IR ist senkennah. Die
Mapping-Funktion einer Quelle darf dabei anreichern, vereinheitlichen und
weglassen, was die Senken nicht brauchen.

## Markdown

`docir::mdSource` stellt `docir::md::fromAst` bereit. Eingabe ist der AST
des [mdstack]{.index}-Parsers, Ausgabe ist die IR.

```tcl
set ast [mdstack::parser::parse $markdown]
set ir  [docir::md::fromAst $ast]
```

Markdown-Ueberschriften werden zu `heading` mit `meta.level` aus der
Anzahl der `#`. Jede Ueberschrift erhaelt ueber `meta.id` einen Anker
(einen Slug aus dem Titel), der spaeter fuer Querverweise und
Verzeichnisse dient.

## nroff

`docir::roffSource` stellt `docir::roff::fromAst` bereit und uebersetzt
den AST des nroff-Parsers. Hier zeigt sich die Vereinheitlichung
besonders deutlich: nroff `.SH` wird zu `heading level=1`, `.SS` zu
`heading level=2`, und das nroff-`.TH` wird zum `doc_header`.

## Der Begriff "heading"

Eine bekannte Stolperstelle: In einem quellnahen AST kann `heading` etwas
anderes bedeuten als in der IR. Im nroff-AST ist `heading` der
Manpage-Kopf (`.TH`), in der IR ist `heading` die generische Ueberschrift.
Die Quellen loesen das beim Mapping auf; in der IR gilt durchgaengig die
sink-nahe Bedeutung.

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

# Verzeichnisse: Inhalt und Index

Inhalts- und Stichwortverzeichnis entstehen aus der IR und stehen in
beiden Hauptsenken zur Verfuegung.

## Inhaltsverzeichnis

Das [Inhaltsverzeichnis]{.index} wird aus den Ueberschriften gebildet. In
PDF aktiviert `generateToc 1` eine vorangestellte Verzeichnisseite mit
Seitenzahlen; `tocTitle` und `tocDepth` steuern Titel und Tiefe. In HTML
leistet `includeToc 1` dasselbe mit klickbaren Sprungzielen.

Die Seitenzahlen im PDF entstehen in einem Zwei-Pass-Verfahren: Da das
Verzeichnis die folgenden Seiten verschiebt, wird das Dokument so lange
wiederholt gesetzt, bis die Seitenzahlen stabil sind.

## Stichwortverzeichnis

Ein [Sachindex]{.index} entsteht aus im Text markierten Begriffen. Die
Markierung ist ein eingeklammerter Span mit der Klasse `index`:

```markdown
Eine [Koroutine]{.index} unterbricht ein Skript.
```

Der Begriff bleibt im Fliesstext sichtbar und wird zugleich gesammelt. Ein
solcher [Span]{.index} darf in jedem Absatz auf jeder Ebene stehen, auch
in Unterkapiteln.

In PDF aktiviert `generateIndex 1` den Index: alphabetisch, nach
Anfangsbuchstaben gruppiert, je Begriff mit allen Seiten seines
Vorkommens. Die Seite wird beim Setzen erfasst, also auch ueber
Seitenumbrueche hinweg korrekt. In HTML aktiviert `includeIndex 1` den
Index mit Links zu den Vorkommen, beschriftet mit dem Abschnittstitel.

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

# Eigene Quelle und Senke

Der Hub lebt davon, dass [Quelle]{.index}n und [Senke]{.index}n unabhaengig
voneinander entstehen. Beide werden ueber die IR angebunden und brauchen
einander nicht zu kennen.

## Eine Quelle schreiben

Eine Quelle uebersetzt einen quellformat-spezifischen AST in die IR. Sie
besteht im Kern aus einer Funktion, die je AST-Knoten den passenden
IR-Block erzeugt:

```tcl
namespace eval myformat {}

proc myformat::fromAst {ast} {
    set ir {}
    foreach node $ast {
        switch [dict get $node type] {
            title   { lappend ir [dict create type heading \
                          content [list [dict create type text \
                              text [dict get $node text]]] \
                          meta [dict create level 1]] }
            para    { lappend ir [dict create type paragraph \
                          content [list [dict create type text \
                              text [dict get $node text]]] meta {}] }
        }
    }
    return $ir
}
```

Anschliessend laesst sich das Ergebnis mit `docir::validate` pruefen und
an jede Senke uebergeben.

## Eine Senke schreiben

Eine Senke iteriert ueber die flache IR und erzeugt das Ausgabeformat.
Weil die IR flach ist, genuegt eine Schleife mit einem `switch` ueber
`type` — keine Baum-Rekursion noetig:

```tcl
namespace eval myrender {}

proc myrender::render {ir} {
    set out ""
    foreach node $ir {
        switch [dict get $node type] {
            heading   { append out ">> " [text [dict get $node content]] "\n" }
            paragraph { append out [text [dict get $node content]] "\n\n" }
            default   { }   ;# unbekannte Typen ignorieren, nicht abbrechen
        }
    }
    return $out
}
```

Der `default`-Zweig ignoriert unbekannte Typen, statt abzubrechen — das
ist die defensive Grundhaltung der IR.

## Das Hub-Versprechen

Sobald die neue Quelle gueltige IR liefert, bedienen sie alle vorhandenen
Senken — PDF, HTML und die uebrigen. Sobald die neue Senke die IR
verarbeitet, profitiert sie von allen Quellen. Genau dieser Schnitt an der
[Zwischendarstellung]{.index} haelt die Zahl der Konverter klein.
