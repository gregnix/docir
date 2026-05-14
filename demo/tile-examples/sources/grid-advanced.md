# Grid Layout - Fortgeschritten

**Frage:** Wie nutze ich sticky, columnspan, weight richtig?

**Kurz:** `sticky` dehnt Widgets, `weight` verteilt Platz, `columnspan` überspannt Zellen.

---

## sticky - Widget-Ausdehnung

```tcl
# Richtungen: n, s, e, w (oder Kombinationen)
grid .btn -sticky ""      ;# Zentriert (default)
grid .btn -sticky w       ;# Links
grid .btn -sticky e       ;# Rechts
grid .btn -sticky ew      ;# Horizontal gestreckt
grid .btn -sticky ns      ;# Vertikal gestreckt
grid .btn -sticky nsew    ;# Komplett gestreckt
```

**Merkhilfe:** Himmelsrichtungen - North, South, East, West

---

## weight - Platzverteilung

```tcl
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

```tcl
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

```tcl
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

```tcl
# Spalte mindestens 100 Pixel:
grid columnconfigure . 0 -minsize 100

# Zeile mindestens 50 Pixel:
grid rowconfigure . 0 -minsize 50
```

---

## uniform - Gleiche Größe

```tcl
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

```tcl
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

```tcl
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

### Fehler 1: weight vergessen

```tcl
# FALSCH - Entry wächst nicht:
grid .label -row 0 -column 0
grid .entry -row 0 -column 1 -sticky ew
# Entry bleibt klein!

# RICHTIG - weight setzen:
grid columnconfigure . 1 -weight 1
```

### Fehler 2: sticky vergessen

```tcl
# FALSCH - Widget zentriert in Zelle:
grid .entry -row 0 -column 0
grid columnconfigure . 0 -weight 1
# Entry wächst nicht mit!

# RICHTIG - sticky ew:
grid .entry -row 0 -column 0 -sticky ew
```

### Fehler 3: Falsches Parent

```tcl
# FALSCH:
grid columnconfigure .frame.entry 0 -weight 1

# RICHTIG:
grid columnconfigure .frame 0 -weight 1
```

---

## Checkliste

- [ ] `weight` auf Spalten/Zeilen die wachsen sollen?
- [ ] `sticky` auf Widgets die sich dehnen sollen?
- [ ] `columnconfigure` auf Parent (Frame), nicht Widget?
- [ ] Bei `columnspan`: sticky ew für volle Breite?

---

## Siehe auch

- [widget-packing.md](widget-packing.md) - pack vs grid vs place
- [leere-frames.md](leere-frames.md) - Frames richtig nutzen

---

**Quelle:** Tk Grid-Layout Patterns
