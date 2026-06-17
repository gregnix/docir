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
