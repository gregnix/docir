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
