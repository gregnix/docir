## Inhalt

- [Grid Layout - Fortgeschritten](#grid-layout-fortgeschritten)
- [Widget-Packing: pack vs grid vs place](#widget-packing-pack-vs-grid-vs-place)
- [place -- Absolute und relative Positionierung](#place-absolute-und-relative-positionierung)

---

# Grid Layout - Fortgeschritten

## Übersicht

> **Frage:** Wie nutze ich sticky, columnspan, weight richtig?
> **Kurz:** `sticky` dehnt Widgets, `weight` verteilt Platz, `columnspan` überspannt Zellen.

---

## sticky - Widget-Ausdehnung

**Merkhilfe:** Himmelsrichtungen - North, South, East, West

```
# Richtungen: n, s, e, w (oder Kombinationen)
grid .btn -sticky ""      ;# Zentriert (default)
grid .btn -sticky w       ;# Links
grid .btn -sticky e       ;# Rechts
grid .btn -sticky ew      ;# Horizontal gestreckt
grid .btn -sticky ns      ;# Vertikal gestreckt
grid .btn -sticky nsew    ;# Komplett gestreckt
```

---

## weight - Platzverteilung

```
# Spalten-Gewichtung:
grid columnconfigure . 0 -weight 0   ;# Feste Breite
grid columnconfigure . 1 -weight 1   ;# Bekommt Extra-Platz

# Zeilen-Gewichtung:
grid rowconfigure . 0 -weight 0      ;# Feste Höhe
grid rowconfigure . 1 -weight 1      ;# Bekommt Extra-Platz

# Mehrere Spalten gleich:
grid columnconfigure . {0 1 2} -weight 1
```

---

## Typisches Formular-Layout

```
# Labels links (fest), Entries rechts (flexibel)
ttk::label .lname -text "Name:"
ttk::entry .ename
ttk::label .lemail -text "Email:"
ttk::entry .eemail
ttk::button .ok -text "OK"

grid .lname  -row 0 -column 0 -sticky e -padx 5 -pady 2
grid .ename  -row 0 -column 1 -sticky ew -padx 5 -pady 2
grid .lemail -row 1 -column 0 -sticky e -padx 5 -pady 2
grid .eemail -row 1 -column 1 -sticky ew -padx 5 -pady 2
grid .ok     -row 2 -column 1 -sticky e -padx 5 -pady 10

# Nur Spalte 1 wächst:
grid columnconfigure . 1 -weight 1
```

---

## columnspan / rowspan

```
# Button über 2 Spalten:
grid .btn -row 0 -column 0 -columnspan 2

# Widget über 3 Zeilen:
grid .sidebar -row 0 -column 0 -rowspan 3 -sticky ns

# Beispiel: Header über gesamte Breite
ttk::label .header -text "Titel"
ttk::label .left -text "Links"
ttk::label .right -text "Rechts"

grid .header -row 0 -column 0 -columnspan 2 -sticky ew
grid .left   -row 1 -column 0
grid .right  -row 1 -column 1
```

---

## minsize - Minimalgröße

```
# Spalte mindestens 100 Pixel:
grid columnconfigure . 0 -minsize 100

# Zeile mindestens 50 Pixel:
grid rowconfigure . 0 -minsize 50
```

---

## uniform - Gleiche Größe

```
# Alle Buttons gleich breit:
grid columnconfigure . {0 1 2} -uniform buttons

# Anwendung:
grid .btn1 -row 0 -column 0
grid .btn2 -row 0 -column 1
grid .btn3 -row 0 -column 2
grid columnconfigure . {0 1 2} -uniform grp -weight 1
```

---

## Grid in Frame

```
# WICHTIG: columnconfigure auf PARENT, nicht Widget!
ttk::frame .f
ttk::entry .f.e
ttk::button .f.b -text "OK"

grid .f.e -row 0 -column 0 -sticky ew
grid .f.b -row 0 -column 1

# Auf Frame konfigurieren:
grid columnconfigure .f 0 -weight 1  ;# Nicht "."!

pack .f -fill x
```

---

## Debugging

```
# Grid-Info eines Widgets:
puts [grid info .mywidget]

# Alle Widgets in Grid:
puts [grid slaves .]

# Spalten-Config:
puts [grid columnconfigure . 0]

# Grid sichtbar machen (Debugging):
. configure -background red
# Jetzt sieht man wo Lücken sind
```

---

## Häufige Fehler


---

## Fehler 1: weight vergessen

```
# FALSCH - Entry wächst nicht:
grid .label -row 0 -column 0
grid .entry -row 0 -column 1 -sticky ew
# Entry bleibt klein!

# RICHTIG - weight setzen:
grid columnconfigure . 1 -weight 1
```

---

## Fehler 2: sticky vergessen

```
# FALSCH - Widget zentriert in Zelle:
grid .entry -row 0 -column 0
grid columnconfigure . 0 -weight 1
# Entry wächst nicht mit!

# RICHTIG - sticky ew:
grid .entry -row 0 -column 0 -sticky ew
```

---

## Fehler 3: Falsches Parent

```
# FALSCH:
grid columnconfigure .frame.entry 0 -weight 1

# RICHTIG:
grid columnconfigure .frame 0 -weight 1
```

---

## Checkliste

- `weight` auf Spalten/Zeilen die wachsen sollen?
- `sticky` auf Widgets die sich dehnen sollen?
- `columnconfigure` auf Parent (Frame), nicht Widget?
- Bei `columnspan`: sticky ew für volle Breite?

---

## Siehe auch

> • widget-packing.md - pack vs grid vs place
> • leere-frames.md - Frames richtig nutzen
> **Quelle:** Tk Grid-Layout Patterns

---


<!-- pagebreak -->

# Widget-Packing: pack vs grid vs place

## Frage

> Wann `pack`, wann `grid`, wann `place`?

---

## Kurzantwort

| | |
|---|---|
| Layout | Verwende |
| Einfach (oben/unten/links/rechts) | `pack` |
| Tabellen/Formulare | `grid` |
| Absolute Position | `place` |

---

## pack

> **Konzept:** Widgets werden nacheinander "gepackt".
> » button .btn1 -text "Oben"
> » button .btn2 -text "Unten"
> » pack .btn1 -side top
> » pack .btn2 -side bottom
> **Optionen:**
> » pack .widget \
> »     -side top|bottom|left|right \
> »     -fill x|y|both|none \
> »     -expand 0|1 \
> »     -padx 5 -pady 5 \
> »     -anchor n|s|e|w|center
> **Typische Verwendung:**
> » # Toolbar oben, Content mitte, Statusbar unten
> » pack .toolbar -side top -fill x
> » pack .statusbar -side bottom -fill x
> » pack .content -side top -fill both -expand 1

---

## grid

> **Konzept:** Widgets in Zeilen/Spalten.
> » label .lbl1 -text "Name:"
> » entry .ent1
> » label .lbl2 -text "Email:"
> » entry .ent2
> » grid .lbl1 -row 0 -column 0 -sticky e
> » grid .ent1 -row 0 -column 1 -sticky ew
> » grid .lbl2 -row 1 -column 0 -sticky e
> » grid .ent2 -row 1 -column 1 -sticky ew
> **Optionen:**
> » grid .widget \
> »     -row 0 -column 0 \
> »     -rowspan 1 -columnspan 1 \
> »     -sticky nsew \
> »     -padx 5 -pady 5
> **Spalten/Zeilen konfigurieren:**
> » grid columnconfigure . 1 -weight 1  ;# Spalte 1 expandiert
> » grid rowconfigure . 0 -weight 0     ;# Zeile 0 fix

---

## place

> **Konzept:** Absolute oder relative Position.
> » button .btn -text "Klick"
> » place .btn -x 100 -y 50
> » # Oder relativ:
> » place .btn -relx 0.5 -rely 0.5 -anchor center
> **Optionen:**
> » place .widget \
> »     -x 100 -y 50 \
> »     -relx 0.5 -rely 0.5 \
> »     -width 100 -height 50 \
> »     -relwidth 0.5 -relheight 0.5 \
> »     -anchor center
> **Wann verwenden:**
> • Ueberlagernde Widgets
> • Exakte Positionierung
> • Animationen

---

## Vergleich

| | |
|---|---|
| Eigenschaft | pack |
| Lernkurve | Einfach |
| Flexibilitaet | Mittel |
| Responsiv | Ja |
| Formulare | Nein |
| Toolbars | Ja |

---

## Haeufige Fehler


---

## Fehler 1: pack und grid mischen

```
# FALSCH - im selben Container!
pack .btn1
grid .btn2
# -> Endlosschleife oder unvorhersehbares Verhalten!

# RICHTIG - verschiedene Container:
frame .top
frame .bottom
pack .top .bottom

pack .btn1 -in .top
grid .btn2 -in .bottom
```

---

## Fehler 2: Vergessen zu expandieren

```
# FALSCH:
pack .text
# -> Text-Widget bleibt klein

# RICHTIG:
pack .text -fill both -expand 1
```

---

## Fehler 3: grid ohne weight

```
# FALSCH:
grid .entry -row 0 -column 1 -sticky ew
# -> Entry expandiert nicht

# RICHTIG:
grid .entry -row 0 -column 1 -sticky ew
grid columnconfigure . 1 -weight 1
```

---

## Best Practice

> **Toolbar + Content + Statusbar:**
> » pack .toolbar -side top -fill x
> » pack .statusbar -side bottom -fill x
> » pack .content -fill both -expand 1
> **Formular:**
> » grid .lblName -row 0 -column 0 -sticky e
> » grid .entName -row 0 -column 1 -sticky ew
> » grid .lblMail -row 1 -column 0 -sticky e
> » grid .entMail -row 1 -column 1 -sticky ew
> » grid columnconfigure . 1 -weight 1
> **Dialog-Buttons:**
> » frame .buttons
> » pack .buttons -side bottom -fill x
> » button .buttons.ok -text "OK"
> » button .buttons.cancel -text "Cancel"
> » pack .buttons.cancel .buttons.ok -side right -padx 5

---

## Checkliste

- Einfaches Layout? -> `pack`
- Tabelle/Formular? -> `grid`
- Absolute Position noetig? -> `place`
- pack und grid NICHT mischen in einem Container!
- `expand 1` fuer dynamische Groesse
- `weight` bei grid fuer expandierende Spalten

---

## Siehe auch

> • widget-hierarchie.md - Widget-Struktur
> • leere-frames.md - Leere Container
> • widget-creation-helper.md - Helper-Funktionen
> Quelle: CLAUDE-TCL-TK-WISSEN.md - Widget-Hierarchie

---


<!-- pagebreak -->

# place -- Absolute und relative Positionierung

## Übersicht

> *Stand: 2026-04-29*
> Positioniert Widgets mit absoluten Pixel-Koordinaten oder relativen Anteilen innerhalb eines Containers. Place ist der dritte Geometry Manager neben pack und grid.
> **Quelle:** https://www.tcl-lang.org/man/tcl8.6/TkCmd/place.html

---

## Übersicht

Place arbeitet nach dem Bulletin-Board-Modell: Widgets werden auf konkreten Koordinaten platziert. Anders als pack und grid schrumpft place das Parent-Fenster nicht um seinen Inhalt zusammen -- das Parent behalt seine angegebene Größe unabhängig vom Inhalt.

```
place window option value ?option value ...?
place configure window ?option? ?value option value ...?
place forget window
place info window
place slaves window     ;# Tcl 8.x
place content window    ;# Tcl 9
```

---

## Wann place verwenden?

> Place ist **nicht** für reguläre Formulare oder Dialoge gedacht. Dort sind pack und grid besser, weil sie auf Schriftgrößen- und Fenstergroessenaenderungen automatisch reagieren.

---

## Optionen


---

## Positions-Optionen

| | |
|---|---|
| Option | Typ |
| `-x` | Pixel |
| `-y` | Pixel |
| `-relx` | Float |
| `-rely` | Float |

---

## Größen-Optionen

> Ohne `-width`/`-relwidth` verwendet das Widget seine natuerliche Größe (requested size).

---

## Steuerungs-Optionen

| | |
|---|---|
| Option | Typ |
| `-anchor` | Position |
| `-in` | Widget |
| `-bordermode` | Mode |

---

## Absolute Positionierung

X-Koordinaten wachsen nach rechts, Y-Koordinaten nach unten. Der Ursprung (0,0) liegt oben links im Parent.

```
# Widget an Position (100, 50)
place .widget -x 100 -y 50

# Mit fester Größe
place .widget -x 100 -y 50 -width 200 -height 100
```

---

## Relative Positionierung

Werte von 0.0 bis 1.0, relativ zur Größe des Parents. Das Widget skaliert mit wenn der Parent seine Größe aendert.
Mit relativen Koordinaten und Größen verhält sich das Fenster wie eine Gummifolie -- alles dehnt sich proportional.

```
# Zentriert
place .widget -relx 0.5 -rely 0.5 -anchor center

# Rechts unten
place .widget -relx 1.0 -rely 1.0 -anchor se

# Obere Haelfte füllen
place .widget -relx 0.0 -rely 0.0 \
    -relwidth 1.0 -relheight 0.5
```

---

## Kombination absolut + relativ

Absolute Werte werden zu den relativen **addiert**. Das ist die eigentliche Staerke von place -- Muster wie "10 Pixel vom rechten Rand" werden damit möglich:
Die Formeln:

```
# Rechts unten mit 10px Abstand von beiden Raendern
place .btn -relx 1.0 -rely 1.0 -anchor se -x -10 -y -10

# Volle Breite minus 20px links und rechts
place .bar -x 10 -relwidth 1.0 -width -20

# Untere Haelfte, aber 5px Abstand oben
place .pane -relx 0.0 -rely 0.5 -y 5 \
    -relwidth 1.0 -relheight 0.5 -height -5
endgueltige_x = (relx * parent_width) + x
endgueltige_y = (rely * parent_height) + y
endgueltige_width  = (relwidth * parent_width) + width
endgueltige_height = (relheight * parent_height) + height
```

---

## Anchor

Bestimmt, welcher Punkt des Widgets an den berechneten Koordinaten liegt. Ohne anchor hängt das Widget von der berechneten Position nach rechts unten.
Häufige Kombination mit relativen Koordinaten:

```
nw --- n --- ne
|            |
w   center   e
|            |
sw --- s --- se
place .w -x 100 -y 100 -anchor nw      ;# Oben-links (Standard)
place .w -x 100 -y 100 -anchor center  ;# Mitte auf (100,100)
place .w -x 100 -y 100 -anchor se      ;# Unten-rechts auf (100,100)
# Zentriert: anchor center + relx/rely 0.5
place .dialog -relx 0.5 -rely 0.5 -anchor center

# Rechts unten: anchor se + relx/rely 1.0
place .status -relx 1.0 -rely 1.0 -anchor se -x -5 -y -5

# Oben mittig: anchor n + relx 0.5
place .title -relx 0.5 -rely 0.0 -anchor n
```

---

## Die -in Option

> Normalerweise bezieht sich place auf das Parent-Widget. Mit `-in` kann ein anderes Widget als Referenz dienen. Damit lassen sich Widgets **über** anderen Widgets platzieren -- das zentrale Muster für Overlays.
> » # Frame als Kind des Text-Widgets erstellen
> » frame .txt._line -height 1 -bg "#c8d8e8"
> » # Über dem Text-Widget platzieren
> » place .txt._line -in .txt -x 0 -y 30 \
> »     -relwidth 1.0 -height 1
> » raise .txt._line
> **Regeln für -in:**
> • Das platzierte Widget muss ein Nachkomme des `-in`-Widgets sein, oder beide müssen Nachkommen desselben Toplevel sein.
> • Koordinaten beziehen sich auf das `-in`-Widget, nicht auf den eigentlichen Parent.
> • Nach `place -in` ist meistens `raise` nötig, damit das platzierte Widget über dem Referenz-Widget sichtbar ist.

---

## Overlay-Linien auf einem Text-Widget

Ein typisches Muster aus dem ruledtext-Projekt -- horizontale Linien wie auf Schreibblockpapier über einem Text-Widget:

```
set txt .editor.txt
set font [$txt cget -font]
set ls [font metrics $font -linespace]

# Pool von 1px-Frames erstellen
for {set i 0} {$i < 40} {incr i} {
    frame $txt._line$i -height 1 -bg "#c8d8e8"
}

# Linien zwischen den Textzeilen positionieren
# Faktor 1.5 setzt die Linie zwischen Zeile n und n+1
for {set i 0} {$i < 40} {incr i} {
    set ypos [expr {int($ls * ($i + 1.5))}]
    ::place $txt._line$i -in $txt -x 0 -y $ypos \
        -relwidth 1.0 -height 1
    raise $txt._line$i
}
```

---

## Margin-Linie

Eine vertikale rote Linie wie auf College-Block-Papier:

```
frame $txt._margin -width 1 -bg "#e8a0a0"
::place $txt._margin -in $txt -x 55 -y 0 \
    -width 1 -relheight 1.0
raise $txt._margin
```

---

## Bordermode

Steuert ob Koordinaten relativ zum inneren Bereich (innerhalb des Rahmens) oder zum aeusseren Bereich (einschliesslich Rahmen) berechnet werden.
Bei `-bordermode inside` (Standard) ist (0,0) die obere linke Ecke des inneren Bereichs. Bei `-bordermode outside` ist (0,0) die obere linke Ecke einschliesslich Border und Highlight.

```
# Standard: Koordinaten innerhalb des Rahmens
place .w -in .frame -x 0 -y 0 -bordermode inside

# Koordinaten einschliesslich Rahmenbreite
place .w -in .frame -x 0 -y 0 -bordermode outside
```

---

## Unterbefehle


---

## place configure

Setzt oder liest Optionen. Ein erneuter `place`-Aufruf aendert nur die angegebenen Optionen -- alle anderen bleiben erhalten:
Dieses Verhalten ist nützlich für Animationen und dynamische Layouts: einmal vollständig konfigurieren, dann nur die sich aendernden Werte aktualisieren.

```
# Erst vollständig platzieren
place .w -relx 0.5 -rely 0.0 -anchor n -relwidth 1.0

# Später nur die Y-Position ändern (rest bleibt)
place .w -rely 0.3

# Optionen lesen
place configure .w -relx    ;# -> -relx {} {} 0.0 0.5
```

---

## place forget

Entfernt das Widget aus dem place-Manager. Das Widget wird unsichtbar, existiert aber weiter und kann erneut platziert werden:
Nützlich für Show/Hide-Logik ohne Widget-Zerstoerung.

```
# Lade-Overlay anzeigen
place .loading -relx 0.5 -rely 0.5 -anchor center

# Lade-Overlay entfernen
place forget .loading
```

---

## place info

Gibt die aktuelle Konfiguration als Key-Value-Liste zurück:

```
place info .widget
# -> -x 0 -relx 0.5 -y 0 -rely 0.5 -width {} -relwidth {}
#    -height {} -relheight {} -anchor center -bordermode inside
```

---

## place slaves / place content

Listet alle Widgets auf, die mit place in einem Parent platziert wurden:

```
place slaves .frame     ;# Tcl 8.x
place content .frame    ;# Tcl 9 (neuer Name)
```

---

## Stacking Order: raise und lower

Überlappen sich platzierte Widgets, bestimmt die Stacking Order welches oben liegt. Später erstellte Widgets liegen standardmäßig weiter oben.
Für place-basierte Overlays ist `raise` nach jedem `place`-Aufruf empfehlenswert, um sicherzustellen dass die Ebenenreihenfolge stimmt.

```
# Widget nach oben bringen
raise .overlay

# Widget nach unten senden
lower .background

# Widget über ein bestimmtes anderes setzen
raise .highlight .content

# Widget unter ein bestimmtes anderes setzen
lower .shadow .content
```

---

## Praxisbeispiele


---

## Schwebender Button

```
text .content -wrap word
pack .content -fill both -expand 1

ttk::button .help -text "?" -width 3 \
    -command showHelp
place .help -relx 1.0 -rely 1.0 -anchor se -x -15 -y -15
```

---

## Lade-Overlay

```
proc showLoading {parent} {
    ttk::label $parent._loading -text "Laden..." \
        -font {TkDefaultFont 16} -background white
    place $parent._loading -relx 0.5 -rely 0.5 -anchor center
    raise $parent._loading
}

proc hideLoading {parent} {
    place forget $parent._loading
}
```

---

## Hintergrundbild

```
image create photo bgimg -file background.png
label .bg -image bgimg
place .bg -relwidth 1.0 -relheight 1.0

# Inhalt darüber
ttk::frame .content
place .content -relx 0.1 -rely 0.1 \
    -relwidth 0.8 -relheight 0.8
raise .content
```

---

## Geteiltes Fenster (historisches Muster)

> Vor `ttk::panedwindow` wurden geteilte Fenster mit place gebaut. Das Muster zeigt die Staerke der relativen Positionierung:
> » proc panedwindow_create {win width height} {
> »     frame $win -width $width -height $height
> »     # Oberes Teilfenster: hängt von oben herab
> »     frame $win.pane1
> »     place $win.pane1 -relx 0.5 -rely 0 -anchor n \
> »         -relwidth 1.0 -relheight 0.5
> »     # Unteres Teilfenster: strebt von unten nach oben
> »     frame $win.pane2
> »     place $win.pane2 -relx 0.5 -rely 1.0 -anchor s \
> »         -relwidth 1.0 -relheight 0.5
> »     # Trennbalken
> »     frame $win.sash -height 4 -borderwidth 2 -relief sunken
> »     place $win.sash -relx 0.5 -rely 0.5 \
> »         -relwidth 1.0 -anchor c
> »     # Griff zum Ziehen
> »     frame $win.grip -width 10 -height 10 \
> »         -borderwidth 2 -relief raised
> »     place $win.grip -relx 0.95 -rely 0.5 -anchor c
> »     # Bindings für Drag
> »     bind $win.grip <B1-Motion> \
> »         [list panedwindow_drag $win %Y]
> »     bind $win.grip <ButtonRelease-1> \
> »         [list panedwindow_drop $win %Y]
> »     return $win
> » }
> » proc panedwindow_divide {win frac} {
> »     # Nur die sich aendernden Optionen setzen --
> »     # relx, relwidth, anchor bleiben vom create erhalten
> »     place $win.sash  -rely $frac
> »     place $win.grip  -rely $frac
> »     place $win.pane1 -relheight $frac
> »     place $win.pane2 -relheight [expr {1.0 - $frac}]
> » }
> Beachte: `panedwindow_divide` setzt nur `-rely` und `-relheight`. Alle anderen Optionen (`-relx`, `-relwidth`, `-anchor`) bleiben vom ursprünglichen `place`-Aufruf erhalten.
> **Heute:** Für geteilte Fenster `ttk::panedwindow` verwenden. Dieses Muster ist trotzdem lehrreich für eigene Layouts.

---

## Tooltip an Mausposition

```
toplevel .tip -bg black -bd 1
wm overrideredirect .tip 1
wm withdraw .tip

label .tip.l -bg lightyellow -padx 4 -pady 2
pack .tip.l

proc showTip {w text x y} {
    .tip.l configure -text $text
    wm geometry .tip "+[expr {$x + 15}]+[expr {$y + 10}]"
    wm deiconify .tip
    raise .tip
}

proc hideTip {} {
    wm withdraw .tip
}

bind .btn <Enter> {showTip %W "Hilfetext" %X %Y}
bind .btn <Leave> hideTip
```

---

## Dynamische Updates mit Configure-Event

Place reagiert nicht automatisch auf Größenänderungen des Inhalts. Für Layouts die sich anpassen sollen, kann ein `<Configure>`-Binding helfen:
**Wichtig:** `%W eq ".parent"` filtert Configure-Events von Kind-Widgets heraus. Ohne diesen Filter wird der Handler bei jeder Widget-Änderung aufgerufen.

```
bind .parent <Configure> {
    if {%W eq ".parent"} {
        # Positionen neu berechnen
        set w %w
        set h %h
        place .overlay -x [expr {$w - 50}] -y [expr {$h - 30}]
    }
}
```

---

## Häufige Fehler


---

## Propagation nicht beachtet

Place schrumpft das Parent nicht um den Inhalt. Ein leerer Frame mit place-Kindern bleibt unsichtbar wenn er keine eigene Größe hat:

```
# FALSCH -- Frame bleibt 0x0
frame .f
place .f.btn -x 10 -y 10
pack .f     ;# .f hat keine Größe!

# RICHTIG -- Größe setzen oder pack propagate nutzen
frame .f -width 300 -height 200
place .f.btn -x 10 -y 10
pack .f
```

---

## Widget-Überlappung nicht erkannt

Place prüft nicht ob sich Widgets überlappen. Bei absoluter Positionierung mit Schriftgroessenaenderungen können Widgets übereinander geraten:
Besser: Relative Positionierung oder pack/grid verwenden.

```
# Fragil -- überlappt bei groesserer Schrift
place .label1 -x 10 -y 10
place .label2 -x 10 -y 30
```

---

## ::place in Namespaces vergessen

In Namespaces kann `place` mit einer eigenen Proc kollidieren:
Dasselbe gilt für `raise` und `lower` -- immer `::raise` und `::lower` wenn ein Namespace eigene Procs mit diesen Namen haben könnte.

```
namespace eval mywidget {
    proc place {w x y} { ... }   ;# eigene Proc
    proc draw {} {
        place .line -x 10 -y 20  ;# ruft mywidget::place!
    }
}

# RICHTIG -- Tk-Befehl global qualifizieren:
namespace eval mywidget {
    proc draw {} {
        ::place .line -x 10 -y 20
        ::raise .line
    }
}
```

---

## place forget vs destroy

`place forget` entfernt nur die Platzierung, das Widget existiert weiter. Für endgueltiges Entfernen `destroy` verwenden:

```
# Widget bleibt im Speicher:
place forget .overlay

# Widget komplett entfernen:
destroy .overlay
```

---

## Vergleich: pack -padx vs place für Margins

> Für visuelle Raender (z.B. Margin-Linien) in einem Text-Widget ist place besser als pack-Padding, weil:
> **Wichtig:** Das Tk text-Widget akzeptiert bei `-padx` nur **einen** Wert (symmetrisch). `text .t -padx {67 12}` erzeugt einen "bad screen distance" Fehler. Siehe auch text.md.

---

## Referenz


---

## Alle Optionen

| | |
|---|---|
| Option | Default |
| `-x` | 0 |
| `-y` | 0 |
| `-relx` | 0.0 |
| `-rely` | 0.0 |
| `-width` | -- |
| `-height` | -- |
| `-relwidth` | -- |
| `-relheight` | -- |
| `-anchor` | nw |
| `-in` | Parent |
| `-bordermode` | inside |

---

## Alle Unterbefehle

| | |
|---|---|
| Befehl | Beschreibung |
| `place .w opts` | Widget platzieren oder Optionen ändern |
| `place configure .w` | Optionen lesen |
| `place forget .w` | Platzierung entfernen (Widget bleibt) |
| `place info .w` | Aktuelle Konfiguration als Liste |
| `place slaves .parent` | Platzierte Kinder auflisten (Tcl 8.x) |
| `place content .parent` | Platzierte Kinder auflisten (Tcl 9) |

---

## Kernregeln

| | |
|---|---|
| Regel | Grund |
| Place nicht für Formulare verwenden | pack/grid reagieren auf Schriftaenderungen |
| `raise` nach `place -in` | Overlay muss über dem Referenz-Widget liegen |
| `::place` in Namespaces | Vermeidet Kollision mit eigenen Procs |
| `-relx`/`-rely` für skalierbare Layouts | Passt sich an Fenstergroesse an |
| `-x`/`-y` negativ mit `-relx 1.0` | Abstand vom rechten/unteren Rand |
| `place forget` für Show/Hide | Widget bleibt im Speicher, kann erneut platziert werden |
| Configure-Event filtern mit `%W eq` | Sonst feuert Handler für jedes Kind-Widget |
| Parent braucht eigene Größe | place propagiert nicht wie pack/grid |

---

## Siehe auch

> • Geometry Manager -- pack, grid, place im Überblick
> • Text-Widget -- padx-Einschränkung, Overlay-Linien
> • Canvas -- Stacking Order für Canvas-Items
> • Namespace -- Namenskollision mit ::place
> *Letzte Aktualisierung: Maerz 2026*

---

