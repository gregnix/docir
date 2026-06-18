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
