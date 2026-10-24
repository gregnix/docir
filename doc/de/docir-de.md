# 1  Einleitung

DocIR ist eine Hub-Architektur fuer die Dokument-Konvertierung. Eine
[Quelle]{.index} liest ein Eingabeformat in eine gemeinsame Zwischen-
darstellung, die [DocIR]{.index} (Document Intermediate Representation).
Beliebige [Senken]{.index} erzeugen daraus die Ausgabeformate. Quellen und
Senken kennen einander nicht; sie sprechen ausschliesslich ueber die IR.

## 1.1  Das Nabe-Speiche-Prinzip

Eine neue Quelle wird sofort von allen Senken bedient, und eine neue Senke
profitiert sofort von allen Quellen. So bleibt die Zahl der noetigen
Konverter linear statt quadratisch: nicht jede Quelle muss jede Senke
kennen, sondern nur die IR.

## 1.2  Der uebliche Weg

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

## 1.3  Zu diesem Handbuch

Dieses Handbuch ist selbst ein Beispiel fuer die Buch-Konvention: Markdown-
Kapitel ohne feste Nummern, Index-Begriffe als `[Begriff]{.index}`, eine
Reihenfolge in `book.tcl` und ein Build nach PDF und HTML mit
`book-build.tcl` (aus dem **bookkit**-Toolkit).

# 2  Die Zwischendarstellung

Die IR ist eine flache, vollstaendig typisierte Folge von Block-Knoten. Es
gibt keinen Baum: Verschachtelung wird ueber `meta.level` und die
Reihenfolge ausgedrueckt, nicht ueber Kind-Listen. Das macht die IR
SAX-artig, leicht zu rendern und gut testbar.

## 2.1  Aufbau eines Knotens

Jeder [Block-Knoten]{.index} hat drei Felder:

```tcl
dict create \
    type    <string>   ;# Pflichtfeld
    content <any>      ;# Liste von Inlines, Items oder ""
    meta    <dict>     ;# darf leer sein: {}
```

Das Prinzip ist defensiv: Unbekannte Typen werden ignoriert statt
abgelehnt, und Senken behandeln fehlende oder leere Felder vertraeglich.

## 2.2  Block-Typen

Zu den Block-Typen zaehlen unter anderem [heading]{.index} (mit
`meta.level` 1..6), `paragraph`, `pre` (Codeblock), `list`, `table`,
`doc_header` sowie `blank`. Ein `doc_header` traegt Dokument-Metadaten
(etwa aus einer YAML-Frontmatter oder einem nroff-`.TH`).

## 2.3  Inline-Typen

Innerhalb von `content` stehen Inline-Knoten: `text`, `strong`,
`emphasis`, `underline`, `strike`, `code`, `link`, `image`, `linebreak`,
`softbreak`, `footnote_ref`, `math` und der [span]{.index}. Der span
traegt eine `class` und eine optionale `id` und ist die Grundlage fuer
Index-Markierungen (siehe das Kapitel zu Verzeichnissen).

Span und `link` haben seit 2026-10-21 das optionale Feld `style`: eine
Liste aus `strong`, `emphasis` und `strike`, das Innerste zuerst. Es steht
da, wenn der Span oder Link in der Quelle in einer Hervorhebung stand:
`**[adduser]{.index}**` wird zu
`{type span text adduser class index style strong}`. HTML setzt
`<strong>`/`<em>`/`<s>` darum, PDF schreibt fett oder kursiv, Markdown
schreibt die Zeichen zurueck; die uebrigen Senken zeigen den Text.

## 2.4  Validierung

`docir::validate $ir` prueft eine IR und liefert eine leere Liste bei
gueltiger Eingabe oder eine Liste von Fehlermeldungen. Da die IR
sink-nah und quellformat-neutral ist, gilt eine validierte IR fuer alle
Senken gleichermassen.

# 3  Quellen

Eine [Quelle]{.index} uebersetzt einen quellformat-spezifischen AST in die
IR. Der Leitsatz lautet: der AST ist quellnah, die IR ist senkennah. Die
Mapping-Funktion einer Quelle darf dabei anreichern, vereinheitlichen und
weglassen, was die Senken nicht brauchen.

## 3.1  Markdown

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

Hervorhebungen (`**`, `*`, `~~`) werden flach: Jedes Stueck Text darin
wird ein eigener `strong`-, `emphasis`- oder `strike`-Inline. Ein Span
oder Link darin behaelt seinen Knoten und bekommt die Hervorhebung in
`style`. Bis 2026-10-20 wurde auch er flach; ein Stichwort in Fett fehlte
dann im Index, ein fetter Link verlor sein Ziel.

## 3.2  nroff

`docir::roffSource` stellt `docir::roff::fromAst` bereit und uebersetzt
den AST des nroff-Parsers. Hier zeigt sich die Vereinheitlichung
besonders deutlich: nroff `.SH` wird zu `heading level=1`, `.SS` zu
`heading level=2`, und das nroff-`.TH` wird zum `doc_header`.

## 3.3  Der Begriff "heading"

Eine bekannte Stolperstelle: In einem quellnahen AST kann `heading` etwas
anderes bedeuten als in der IR. Im nroff-AST ist `heading` der
Manpage-Kopf (`.TH`), in der IR ist `heading` die generische Ueberschrift.
Die Quellen loesen das beim Mapping auf; in der IR gilt durchgaengig die
sink-nahe Bedeutung.

# 4  Senken

Eine [Senke]{.index} erzeugt aus der IR ein Ausgabeformat. Alle Senken
arbeiten ausschliesslich auf der IR und sind damit von der ursprünglichen
Quelle unabhaengig.

## 4.1  PDF

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
Das Erstelldatum wird immer gesetzt: aus der Option `creationDate` (Sekunden), sonst aus der Umgebungsvariablen `SOURCE_DATE_EPOCH`, sonst die aktuelle Zeit. Mit festem Datum ergeben zwei Läufe mit derselben Eingabe dieselben Bytes.

## 4.2  HTML

`docir::html` rendert nach eigenstaendigem HTML mit eingebettetem CSS.

```tcl
set html [docir::html::render $ir [dict create \
    title "Mein Dokument" includeToc 1]]
```

Ueberschriften erhalten ihre `id` als Anker, sodass das Inhaltsverzeichnis
und Querverweise als klickbare Sprungziele funktionieren.

## 4.3  Bloecke: Fragmente in feste Rechtecke

Die bisher genannten Senken setzen ein **fliessendes** Dokument: Ueberschrift,
Absatz, Liste untereinander, ueber Seiten hinweg. Fuer Etiketten, Formulare
und Karten braucht man das Gegenteil -- ein Fragment bekommt ein festes
Rechteck zugewiesen, angegeben in Millimetern.

Das leistet `docir::block`:

```tcl
package require docir::block

set pdf [pdf4tcl::new %AUTO% -paper {54m 56m}]
$pdf startPage
docir::block::pdf $pdf $ir -x 3 -y 39 -w 30 -h 14 -size 8
;# -> used 8.043  lines 2  overflow 0  truncated 0
```

Der Rueckgabewert traegt die beiden Angaben, die ein [Layout]{.index}-Editor
braucht: `used` ist die tatsaechlich verbrauchte Hoehe in Millimetern, mit der
sich ein Block automatisch bemessen laesst, und `overflow` meldet, dass der
Inhalt nicht in das Rechteck passt -- lieber vor dem Druck als danach.

`docir::block::measure` nimmt dieselben Argumente, zeichnet aber nichts. Damit
laesst sich die Seitenlaenge vor dem Anlegen des Dokuments bestimmen, was bei
Endlosmaterial der uebliche Weg ist: erst messen, dann die Seite in der
passenden Laenge erzeugen.

**Millimeter aussen, Punkt innen.** Die Geometrie wird in Millimetern
angegeben, Schriftgroessen in Punkt. Das ist keine Kosmetik: pdf4tcl liest die
Schriftgroesse in der Einheit, die am Objekt eingestellt ist. Bei `-unit mm`
bedeutet `setFont 9` neun *Millimeter*, also rund 26 Punkt. `docir::block`
verlangt deshalb ein Objekt in der Standardeinheit und weist andere ab, statt
still dreifach zu grossen Satz zu erzeugen.

Neben Text setzt die Senke auch **Bilder**: ein `image`-Block bettet PNG und
JPEG ueber pdf4tcl ein, maszstabsgerecht auf die Rechteckbreite. SVG bleibt
bewusst aussen vor -- das Rastern braucht Tk, und die Senke soll Tk-frei
bleiben, damit ihre Tests ohne Bildschirm laufen. Wer SVG braucht, rastert es
vorher und uebergibt die PNG-Datei.

## 4.4  Weitere Senken

Neben PDF und HTML gibt es weitere [Senke]{.index}n im docir-Hub, darunter
eine Markdown-Senke (Round-Trip), eine nroff-Senke, eine SVG- und eine
Canvas-Senke, eine Tk-Renderer-Senke sowie die Tile-Senken fuer
Spickzettel-artige Layouts. Da alle auf derselben IR arbeiten, steht jede
Quelle automatisch jeder dieser Senken zur Verfuegung.

# 5  Verzeichnisse: Inhalt und Index

Inhalts- und Stichwortverzeichnis entstehen aus der IR und stehen in
beiden Hauptsenken zur Verfuegung.

## 5.1  Inhaltsverzeichnis

Das [Inhaltsverzeichnis]{.index} wird aus den Ueberschriften gebildet. In
PDF aktiviert `generateToc 1` eine vorangestellte Verzeichnisseite mit
Seitenzahlen; `tocTitle` und `tocDepth` steuern Titel und Tiefe. In HTML
leistet `includeToc 1` dasselbe mit klickbaren Sprungzielen.

Die Seitenzahlen im PDF entstehen in einem Zwei-Pass-Verfahren: Da das
Verzeichnis die folgenden Seiten verschiebt, wird das Dokument so lange
wiederholt gesetzt, bis die Seitenzahlen stabil sind.

## 5.2  Stichwortverzeichnis

Ein [Sachindex]{.index} entsteht aus im Text markierten Begriffen. Die
Markierung ist ein eingeklammerter Span mit der Klasse `index`:

```markdown
Eine [Koroutine]{.index} unterbricht ein Skript.
```

Der Begriff bleibt im Fliesstext sichtbar und wird zugleich gesammelt. Ein
solcher [Span]{.index} darf in jedem Absatz auf jeder Ebene stehen, auch
in Unterkapiteln, und auch in Fett oder Kursiv (`**[Koroutine]{.index}**`,
seit 2026-10-21; vorher fehlte er dann im Index). In einem Code-Span
(`` `[x]{.index}` ``) ist er ein Beispiel und zaehlt nicht.

In PDF aktiviert `generateIndex 1` den Index: alphabetisch, nach
Anfangsbuchstaben gruppiert, je Begriff mit allen Seiten seines
Vorkommens. Die Seite wird beim Setzen erfasst, also auch ueber
Seitenumbrueche hinweg korrekt. In HTML aktiviert `includeIndex 1` den
Index mit Links zu den Vorkommen, beschriftet mit dem Abschnittstitel.

Nach dem Setzen liefert `docir::pdf::indexEntries` dieses Verzeichnis als
Liste von `{begriff seiten}`, mit den gedruckten Seitenzahlen. So lassen
sich die Verzeichnisse mehrerer PDFs zu einem Gesamtindex zusammenfassen
(bookkit `index-gesamt.tcl`). Dafuer setzt die PDF-Senke einen relativen
Link auf eine andere PDF-Datei, `andere.pdf` oder `andere.pdf#page=12`,
als Sprung in diese Datei auf die Seite (`/GoToR`, ab pdf4tcl 0.9.4.73;
mit aelterem pdf4tcl bleibt es ein URI-Link).

## 5.3  Kolumnentitel

In einem langen Handbuch zeigt die Seitenzahl allein nicht, wo man ist.
Die Vorlagen fuer Kopf- und Fusszeile (`header`, `footer`) kennen deshalb
neben `%p` (Seite) auch `%t` (Titel des Dokuments) und `%c`, den
[Kolumnentitel]{.index}: die erste Ueberschrift der Ebene `runningLevel`
(Vorgabe 1), die auf der Seite beginnt, sonst die noch laufende -- wie im
Woerterbuch. Inhalts- und Stichwortverzeichnis zeigen ihren Titel. Ein
Tabulator teilt die Vorlage in einen linken und einen rechten Teil:

```tcl
docir::pdf::render $ir buch.pdf [dict create title "Tcl/Tk 9.0" \
    header "%t\t%c" footer "%p"]
```

Eine Kopfzeile mit `%c` entsteht erst, wenn die Seite fertig ist, und
bekommt eine feine Linie darunter. Mit `runningProc` liefert ein eigener
Befehl statt der Ueberschrift mehrere Texte, vom laengsten zum kuerzesten;
genommen wird der erste, der in die Zeile passt. bookkit `manual-build.tcl`
gibt so den Pfad und die Nachbarkapitel an
(`‹ disjointset  |  struct / graph  |  graph1 ›`), bei Platzmangel nur den
Pfad oder den Namen.

Text in `**...**` steht in Kopf- und Fusszeile fett. So hebt
`manual-build.tcl` die aktuelle Seite hervor:
`‹ abstract  |  tcl / **after**  |  append ›`.

# 6  Buecher bauen

Ein Buch ist ein Verzeichnis aus Markdown-Kapiteln, das `book-build.tcl`
(aus dem **bookkit**-Toolkit) in einem Durchgang nach PDF und HTML setzt.

## 6.1  Aufbau

Ein Verzeichnis, eine Datei je Kapitel. Ueberschriften tragen in der
Quelle **keine** Nummern; Kapitel- und Abschnittsnummern entstehen beim
Bauen.

```
mybook/
    book.tcl
    010-einleitung.md
    020-konzepte.md
```

## 6.2  Reihenfolge

Es gibt zwei Wege, das Manifest hat Vorrang. Existiert ein [book.tcl]{.index},
legt es die Reihenfolge ueber eine Liste `chapters` fest (optional auch
`title` und `author`); der Dateinamen-Praefix wird dann ignoriert. Fehlt
das Manifest, bestimmt der numerische [Praefix]{.index} im Dateinamen die
Reihenfolge. Ein Generatorlauf schreibt aus den Praefixen ein Manifest,
das sich anschliessend frei umsortieren laesst:

```
tclsh bookkit/tools/book-build.tcl manifest mybook/
```

## 6.3  Nummerierung und stabile Verweise

Die Option `-number` vergibt hierarchische Nummern (`1`, `1.1`, `1.1.1`)
aus Verschachtelung und Reihenfolge. Da die [Nummerierung]{.index} auf der
IR geschieht, erscheint sie konsistent in Text, Inhaltsverzeichnis,
Lesezeichen und in beiden Ausgabeformaten.

Anker werden aus dem Titel gebildet, nicht aus der Nummer. Umsortieren
aendert daher die Nummern, aber nicht die Anker — Querverweise auf
`#titel-anker` bleiben gueltig.

## 6.4  Bauen

```
tclsh bookkit/tools/book-build.tcl mybook/ -number
tclsh bookkit/tools/book-build.tcl mybook/ -pdf out.pdf -html out.html -number
```

Ohne `-pdf`/`-html` werden beide Formate neben dem Buch-Verzeichnis
erzeugt. Die Schalter `-no-toc` und `-no-index` lassen die Verzeichnisse
weg, `-depth N` steuert die Tiefe von Nummerierung und Inhaltsverzeichnis.

# 7  Eigene Quelle und Senke

Der Hub lebt davon, dass [Quelle]{.index}n und [Senke]{.index}n unabhaengig
voneinander entstehen. Beide werden ueber die IR angebunden und brauchen
einander nicht zu kennen.

## 7.1  Eine Quelle schreiben

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

## 7.2  Eine Senke schreiben

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

## 7.3  Das Hub-Versprechen

Sobald die neue Quelle gueltige IR liefert, bedienen sie alle vorhandenen
Senken — PDF, HTML und die uebrigen. Sobald die neue Senke die IR
verarbeitet, profitiert sie von allen Quellen. Genau dieser Schnitt an der
[Zwischendarstellung]{.index} haelt die Zahl der Konverter klein.
