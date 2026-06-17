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
