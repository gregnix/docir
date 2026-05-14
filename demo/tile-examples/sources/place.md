# place -- Absolute und relative Positionierung

*Stand: 2026-04-29*

Positioniert Widgets mit absoluten Pixel-Koordinaten oder
relativen Anteilen innerhalb eines Containers. Place ist der
dritte Geometry Manager neben pack und grid.

**Quelle:** https://www.tcl-lang.org/man/tcl8.6/TkCmd/place.html

---

## Übersicht

```tcl
place window option value ?option value ...?
place configure window ?option? ?value option value ...?
place forget window
place info window
place slaves window     ;# Tcl 8.x
place content window    ;# Tcl 9
```

Place arbeitet nach dem Bulletin-Board-Modell: Widgets werden auf
konkreten Koordinaten platziert. Anders als pack und grid schrumpft
place das Parent-Fenster nicht um seinen Inhalt zusammen -- das
Parent behalt seine angegebene Größe unabhängig vom Inhalt.

---

## Wann place verwenden?

| Einsatz | Beispiel |
|:--------|:---------|
| Overlays und schwebende Elemente | Lade-Indikator, Hilfe-Button |
| Linien und Markierungen auf Widgets | Schreibblocklinien auf Text-Widget |
| Eigene Geometriemanager | Geteiltes Fenster, Drag-and-Drop |
| Dynamische Positionierung via Bindings | Tooltip an Mausposition |
| Hintergrund-Widgets | Bild als Hintergrund eines Frames |

Place ist **nicht** für reguläre Formulare oder Dialoge gedacht.
Dort sind pack und grid besser, weil sie auf Schriftgrößen-
und Fenstergroessenaenderungen automatisch reagieren.

---

## Optionen

### Positions-Optionen

| Option | Typ | Default | Beschreibung |
|:-------|:----|:--------|:-------------|
| `-x` | Pixel | 0 | Absolute X-Position |
| `-y` | Pixel | 0 | Absolute Y-Position |
| `-relx` | Float | 0.0 | Relative X-Position (0.0 - 1.0) |
| `-rely` | Float | 0.0 | Relative Y-Position (0.0 - 1.0) |

### Größen-Optionen

| Option | Typ | Default | Beschreibung |
|:-------|:----|:--------|:-------------|
| `-width` | Pixel | -- | Absolute Breite |
| `-height` | Pixel | -- | Absolute Höhe |
| `-relwidth` | Float | -- | Relative Breite (0.0 - 1.0) |
| `-relheight` | Float | -- | Relative Höhe (0.0 - 1.0) |

Ohne `-width`/`-relwidth` verwendet das Widget seine natuerliche
Größe (requested size).

### Steuerungs-Optionen

| Option | Typ | Default | Beschreibung |
|:-------|:----|:--------|:-------------|
| `-anchor` | Position | nw | Bezugspunkt des Widgets |
| `-in` | Widget | Parent | Referenz-Widget für Koordinaten |
| `-bordermode` | Mode | inside | inside oder outside |

---

## Absolute Positionierung

X-Koordinaten wachsen nach rechts, Y-Koordinaten nach unten.
Der Ursprung (0,0) liegt oben links im Parent.

```tcl
# Widget an Position (100, 50)
place .widget -x 100 -y 50

# Mit fester Größe
place .widget -x 100 -y 50 -width 200 -height 100
```

---

## Relative Positionierung

Werte von 0.0 bis 1.0, relativ zur Größe des Parents.
Das Widget skaliert mit wenn der Parent seine Größe aendert.

```tcl
# Zentriert
place .widget -relx 0.5 -rely 0.5 -anchor center

# Rechts unten
place .widget -relx 1.0 -rely 1.0 -anchor se

# Obere Haelfte füllen
place .widget -relx 0.0 -rely 0.0 \
    -relwidth 1.0 -relheight 0.5
```

Mit relativen Koordinaten und Größen verhält sich das
Fenster wie eine Gummifolie -- alles dehnt sich proportional.

---

## Kombination absolut + relativ

Absolute Werte werden zu den relativen **addiert**. Das ist
die eigentliche Staerke von place -- Muster wie "10 Pixel
vom rechten Rand" werden damit möglich:

```tcl
# Rechts unten mit 10px Abstand von beiden Raendern
place .btn -relx 1.0 -rely 1.0 -anchor se -x -10 -y -10

# Volle Breite minus 20px links und rechts
place .bar -x 10 -relwidth 1.0 -width -20

# Untere Haelfte, aber 5px Abstand oben
place .pane -relx 0.0 -rely 0.5 -y 5 \
    -relwidth 1.0 -relheight 0.5 -height -5
```

Die Formeln:

```
endgueltige_x = (relx * parent_width) + x
endgueltige_y = (rely * parent_height) + y
endgueltige_width  = (relwidth * parent_width) + width
endgueltige_height = (relheight * parent_height) + height
```

---

## Anchor

Bestimmt, welcher Punkt des Widgets an den berechneten
Koordinaten liegt. Ohne anchor hängt das Widget von der
berechneten Position nach rechts unten.

```
nw --- n --- ne
|            |
w   center   e
|            |
sw --- s --- se
```

```tcl
place .w -x 100 -y 100 -anchor nw      ;# Oben-links (Standard)
place .w -x 100 -y 100 -anchor center  ;# Mitte auf (100,100)
place .w -x 100 -y 100 -anchor se      ;# Unten-rechts auf (100,100)
```

Häufige Kombination mit relativen Koordinaten:

```tcl
# Zentriert: anchor center + relx/rely 0.5
place .dialog -relx 0.5 -rely 0.5 -anchor center

# Rechts unten: anchor se + relx/rely 1.0
place .status -relx 1.0 -rely 1.0 -anchor se -x -5 -y -5

# Oben mittig: anchor n + relx 0.5
place .title -relx 0.5 -rely 0.0 -anchor n
```

---

## Die -in Option

Normalerweise bezieht sich place auf das Parent-Widget. Mit
`-in` kann ein anderes Widget als Referenz dienen. Damit lassen
sich Widgets **über** anderen Widgets platzieren -- das zentrale
Muster für Overlays.

```tcl
# Frame als Kind des Text-Widgets erstellen
frame .txt._line -height 1 -bg "#c8d8e8"

# Über dem Text-Widget platzieren
place .txt._line -in .txt -x 0 -y 30 \
    -relwidth 1.0 -height 1
raise .txt._line
```

**Regeln für -in:**

- Das platzierte Widget muss ein Nachkomme des `-in`-Widgets
  sein, oder beide müssen Nachkommen desselben Toplevel sein.
- Koordinaten beziehen sich auf das `-in`-Widget, nicht auf
  den eigentlichen Parent.
- Nach `place -in` ist meistens `raise` nötig, damit das
  platzierte Widget über dem Referenz-Widget sichtbar ist.

### Overlay-Linien auf einem Text-Widget

Ein typisches Muster aus dem ruledtext-Projekt -- horizontale
Linien wie auf Schreibblockpapier über einem Text-Widget:

```tcl
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

### Margin-Linie

Eine vertikale rote Linie wie auf College-Block-Papier:

```tcl
frame $txt._margin -width 1 -bg "#e8a0a0"
::place $txt._margin -in $txt -x 55 -y 0 \
    -width 1 -relheight 1.0
raise $txt._margin
```

---

## Bordermode

Steuert ob Koordinaten relativ zum inneren Bereich (innerhalb
des Rahmens) oder zum aeusseren Bereich (einschliesslich Rahmen)
berechnet werden.

```tcl
# Standard: Koordinaten innerhalb des Rahmens
place .w -in .frame -x 0 -y 0 -bordermode inside

# Koordinaten einschliesslich Rahmenbreite
place .w -in .frame -x 0 -y 0 -bordermode outside
```

Bei `-bordermode inside` (Standard) ist (0,0) die obere linke Ecke
des inneren Bereichs. Bei `-bordermode outside` ist (0,0) die obere
linke Ecke einschliesslich Border und Highlight.

---

## Unterbefehle

### place configure

Setzt oder liest Optionen. Ein erneuter `place`-Aufruf aendert
nur die angegebenen Optionen -- alle anderen bleiben erhalten:

```tcl
# Erst vollständig platzieren
place .w -relx 0.5 -rely 0.0 -anchor n -relwidth 1.0

# Später nur die Y-Position ändern (rest bleibt)
place .w -rely 0.3

# Optionen lesen
place configure .w -relx    ;# -> -relx {} {} 0.0 0.5
```

Dieses Verhalten ist nützlich für Animationen und dynamische
Layouts: einmal vollständig konfigurieren, dann nur die
sich aendernden Werte aktualisieren.

### place forget

Entfernt das Widget aus dem place-Manager. Das Widget wird
unsichtbar, existiert aber weiter und kann erneut platziert werden:

```tcl
# Lade-Overlay anzeigen
place .loading -relx 0.5 -rely 0.5 -anchor center

# Lade-Overlay entfernen
place forget .loading
```

Nützlich für Show/Hide-Logik ohne Widget-Zerstoerung.

### place info

Gibt die aktuelle Konfiguration als Key-Value-Liste zurück:

```tcl
place info .widget
# -> -x 0 -relx 0.5 -y 0 -rely 0.5 -width {} -relwidth {}
#    -height {} -relheight {} -anchor center -bordermode inside
```

### place slaves / place content

Listet alle Widgets auf, die mit place in einem Parent
platziert wurden:

```tcl
place slaves .frame     ;# Tcl 8.x
place content .frame    ;# Tcl 9 (neuer Name)
```

---

## Stacking Order: raise und lower

Überlappen sich platzierte Widgets, bestimmt die Stacking Order
welches oben liegt. Später erstellte Widgets liegen standardmäßig
weiter oben.

```tcl
# Widget nach oben bringen
raise .overlay

# Widget nach unten senden
lower .background

# Widget über ein bestimmtes anderes setzen
raise .highlight .content

# Widget unter ein bestimmtes anderes setzen
lower .shadow .content
```

Für place-basierte Overlays ist `raise` nach jedem `place`-Aufruf
empfehlenswert, um sicherzustellen dass die Ebenenreihenfolge stimmt.

---

## Praxisbeispiele

### Schwebender Button

```tcl
text .content -wrap word
pack .content -fill both -expand 1

ttk::button .help -text "?" -width 3 \
    -command showHelp
place .help -relx 1.0 -rely 1.0 -anchor se -x -15 -y -15
```

### Lade-Overlay

```tcl
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

### Hintergrundbild

```tcl
image create photo bgimg -file background.png
label .bg -image bgimg
place .bg -relwidth 1.0 -relheight 1.0

# Inhalt darüber
ttk::frame .content
place .content -relx 0.1 -rely 0.1 \
    -relwidth 0.8 -relheight 0.8
raise .content
```

### Geteiltes Fenster (historisches Muster)

Vor `ttk::panedwindow` wurden geteilte Fenster mit place gebaut.
Das Muster zeigt die Staerke der relativen Positionierung:

```tcl
proc panedwindow_create {win width height} {
    frame $win -width $width -height $height

    # Oberes Teilfenster: hängt von oben herab
    frame $win.pane1
    place $win.pane1 -relx 0.5 -rely 0 -anchor n \
        -relwidth 1.0 -relheight 0.5

    # Unteres Teilfenster: strebt von unten nach oben
    frame $win.pane2
    place $win.pane2 -relx 0.5 -rely 1.0 -anchor s \
        -relwidth 1.0 -relheight 0.5

    # Trennbalken
    frame $win.sash -height 4 -borderwidth 2 -relief sunken
    place $win.sash -relx 0.5 -rely 0.5 \
        -relwidth 1.0 -anchor c

    # Griff zum Ziehen
    frame $win.grip -width 10 -height 10 \
        -borderwidth 2 -relief raised
    place $win.grip -relx 0.95 -rely 0.5 -anchor c

    # Bindings für Drag
    bind $win.grip <B1-Motion> \
        [list panedwindow_drag $win %Y]
    bind $win.grip <ButtonRelease-1> \
        [list panedwindow_drop $win %Y]

    return $win
}

proc panedwindow_divide {win frac} {
    # Nur die sich aendernden Optionen setzen --
    # relx, relwidth, anchor bleiben vom create erhalten
    place $win.sash  -rely $frac
    place $win.grip  -rely $frac
    place $win.pane1 -relheight $frac
    place $win.pane2 -relheight [expr {1.0 - $frac}]
}
```

Beachte: `panedwindow_divide` setzt nur `-rely` und `-relheight`.
Alle anderen Optionen (`-relx`, `-relwidth`, `-anchor`) bleiben
vom ursprünglichen `place`-Aufruf erhalten.

**Heute:** Für geteilte Fenster `ttk::panedwindow` verwenden.
Dieses Muster ist trotzdem lehrreich für eigene Layouts.

### Tooltip an Mausposition

```tcl
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

Place reagiert nicht automatisch auf Größenänderungen des
Inhalts. Für Layouts die sich anpassen sollen, kann ein
`<Configure>`-Binding helfen:

```tcl
bind .parent <Configure> {
    if {%W eq ".parent"} {
        # Positionen neu berechnen
        set w %w
        set h %h
        place .overlay -x [expr {$w - 50}] -y [expr {$h - 30}]
    }
}
```

**Wichtig:** `%W eq ".parent"` filtert Configure-Events von
Kind-Widgets heraus. Ohne diesen Filter wird der Handler bei
jeder Widget-Änderung aufgerufen.

---

## Häufige Fehler

### Propagation nicht beachtet

Place schrumpft das Parent nicht um den Inhalt. Ein leerer Frame
mit place-Kindern bleibt unsichtbar wenn er keine eigene Größe hat:

```tcl
# FALSCH -- Frame bleibt 0x0
frame .f
place .f.btn -x 10 -y 10
pack .f     ;# .f hat keine Größe!

# RICHTIG -- Größe setzen oder pack propagate nutzen
frame .f -width 300 -height 200
place .f.btn -x 10 -y 10
pack .f
```

### Widget-Überlappung nicht erkannt

Place prüft nicht ob sich Widgets überlappen. Bei absoluter
Positionierung mit Schriftgroessenaenderungen können Widgets
übereinander geraten:

```tcl
# Fragil -- überlappt bei groesserer Schrift
place .label1 -x 10 -y 10
place .label2 -x 10 -y 30
```

Besser: Relative Positionierung oder pack/grid verwenden.

### ::place in Namespaces vergessen

In Namespaces kann `place` mit einer eigenen Proc kollidieren:

```tcl
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

Dasselbe gilt für `raise` und `lower` -- immer `::raise`
und `::lower` wenn ein Namespace eigene Procs mit diesen
Namen haben könnte.

### place forget vs destroy

`place forget` entfernt nur die Platzierung, das Widget existiert
weiter. Für endgueltiges Entfernen `destroy` verwenden:

```tcl
# Widget bleibt im Speicher:
place forget .overlay

# Widget komplett entfernen:
destroy .overlay
```

---

## Vergleich: pack -padx vs place für Margins

Für visuelle Raender (z.B. Margin-Linien) in einem Text-Widget
ist place besser als pack-Padding, weil:

| Aspekt | pack -padx | place (Overlay) |
|:-------|:-----------|:----------------|
| Linke Margin | Ja, per `-padx` | Ja, per `-x` |
| Rechte Margin | **Nein** -- text `-padx` akzeptiert nur einen Wert | Ja, per `-x` relativ zu `-relwidth` |
| Asymmetrisch | Nicht möglich bei text `-padx` | Beliebig |
| Visueller Strich | Nein | Ja (1px Frame) |
| Scrollt mit | Ja (Teil des Widgets) | Nein (fixed Overlay) |

**Wichtig:** Das Tk text-Widget akzeptiert bei `-padx` nur **einen**
Wert (symmetrisch). `text .t -padx {67 12}` erzeugt einen
"bad screen distance" Fehler. Siehe auch [text.md](text.md).

---

## Referenz

### Alle Optionen

| Option | Default | Beschreibung |
|:-------|:--------|:-------------|
| `-x` | 0 | Absolute X-Position (Pixel) |
| `-y` | 0 | Absolute Y-Position (Pixel) |
| `-relx` | 0.0 | Relative X-Position (0.0 - 1.0) |
| `-rely` | 0.0 | Relative Y-Position (0.0 - 1.0) |
| `-width` | -- | Absolute Breite (Pixel) |
| `-height` | -- | Absolute Höhe (Pixel) |
| `-relwidth` | -- | Relative Breite (0.0 - 1.0) |
| `-relheight` | -- | Relative Höhe (0.0 - 1.0) |
| `-anchor` | nw | Bezugspunkt: n, s, e, w, center, nw, ne, sw, se |
| `-in` | Parent | Referenz-Widget für Koordinaten |
| `-bordermode` | inside | inside oder outside |

### Alle Unterbefehle

| Befehl | Beschreibung |
|:-------|:-------------|
| `place .w opts` | Widget platzieren oder Optionen ändern |
| `place configure .w` | Optionen lesen |
| `place forget .w` | Platzierung entfernen (Widget bleibt) |
| `place info .w` | Aktuelle Konfiguration als Liste |
| `place slaves .parent` | Platzierte Kinder auflisten (Tcl 8.x) |
| `place content .parent` | Platzierte Kinder auflisten (Tcl 9) |

### Kernregeln

| Regel | Grund |
|:------|:------|
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

- [Geometry Manager](geometry-manager.md) -- pack, grid, place im Überblick
- [Text-Widget](text.md) -- padx-Einschränkung, Overlay-Linien
- [Canvas](canvas.md) -- Stacking Order für Canvas-Items
- [Namespace](namespace.md) -- Namenskollision mit ::place

---

*Letzte Aktualisierung: Maerz 2026*
