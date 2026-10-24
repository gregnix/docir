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

## Kolumnentitel

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
