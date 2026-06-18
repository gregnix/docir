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
