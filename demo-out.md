# docir::odt Demo

Ein Absatz mit **fett**, *kursiv*, `Code` und einem [Link](https://www.tcl.tk/).

## Liste

- Eintrag A
- Eintrag B
- Eintrag C

## Tabelle

| Modul | Rolle | Notiz |
| :--- | :--- | :--- |
| docir::odt | Senke | DocIR nach ODT |
| docir::odtSource | Quelle | ODT nach DocIR |

## Codeblock

```
package require docir::odt
docir::odt::write $ir out.odt
```

## Bild

![](Pictures/demo.png)
