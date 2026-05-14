# Widget-Packing: pack vs grid vs place

## Frage

Wann `pack`, wann `grid`, wann `place`?

---

## Kurzantwort

| Layout | Verwende |
|--------|----------|
| Einfach (oben/unten/links/rechts) | `pack` |
| Tabellen/Formulare | `grid` |
| Absolute Position | `place` |

---

## pack

**Konzept:** Widgets werden nacheinander "gepackt".

```tcl
button .btn1 -text "Oben"
button .btn2 -text "Unten"
pack .btn1 -side top
pack .btn2 -side bottom
```

**Optionen:**
```tcl
pack .widget \
    -side top|bottom|left|right \
    -fill x|y|both|none \
    -expand 0|1 \
    -padx 5 -pady 5 \
    -anchor n|s|e|w|center
```

**Typische Verwendung:**
```tcl
# Toolbar oben, Content mitte, Statusbar unten
pack .toolbar -side top -fill x
pack .statusbar -side bottom -fill x
pack .content -side top -fill both -expand 1
```

---

## grid

**Konzept:** Widgets in Zeilen/Spalten.

```tcl
label .lbl1 -text "Name:"
entry .ent1
label .lbl2 -text "Email:"
entry .ent2

grid .lbl1 -row 0 -column 0 -sticky e
grid .ent1 -row 0 -column 1 -sticky ew
grid .lbl2 -row 1 -column 0 -sticky e
grid .ent2 -row 1 -column 1 -sticky ew
```

**Optionen:**
```tcl
grid .widget \
    -row 0 -column 0 \
    -rowspan 1 -columnspan 1 \
    -sticky nsew \
    -padx 5 -pady 5
```

**Spalten/Zeilen konfigurieren:**
```tcl
grid columnconfigure . 1 -weight 1  ;# Spalte 1 expandiert
grid rowconfigure . 0 -weight 0     ;# Zeile 0 fix
```

---

## place

**Konzept:** Absolute oder relative Position.

```tcl
button .btn -text "Klick"
place .btn -x 100 -y 50

# Oder relativ:
place .btn -relx 0.5 -rely 0.5 -anchor center
```

**Optionen:**
```tcl
place .widget \
    -x 100 -y 50 \
    -relx 0.5 -rely 0.5 \
    -width 100 -height 50 \
    -relwidth 0.5 -relheight 0.5 \
    -anchor center
```

**Wann verwenden:**
- Ueberlagernde Widgets
- Exakte Positionierung
- Animationen

---

## Vergleich

| Eigenschaft | pack | grid | place |
|-------------|------|------|-------|
| Lernkurve | Einfach | Mittel | Einfach |
| Flexibilitaet | Mittel | Hoch | Sehr hoch |
| Responsiv | Ja | Ja | Nein |
| Formulare | Nein | Ja | Nein |
| Toolbars | Ja | Moeglich | Nein |

---

## Haeufige Fehler

### Fehler 1: pack und grid mischen

```tcl
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

### Fehler 2: Vergessen zu expandieren

```tcl
# FALSCH:
pack .text
# -> Text-Widget bleibt klein

# RICHTIG:
pack .text -fill both -expand 1
```

### Fehler 3: grid ohne weight

```tcl
# FALSCH:
grid .entry -row 0 -column 1 -sticky ew
# -> Entry expandiert nicht

# RICHTIG:
grid .entry -row 0 -column 1 -sticky ew
grid columnconfigure . 1 -weight 1
```

---

## Best Practice

**Toolbar + Content + Statusbar:**
```tcl
pack .toolbar -side top -fill x
pack .statusbar -side bottom -fill x
pack .content -fill both -expand 1
```

**Formular:**
```tcl
grid .lblName -row 0 -column 0 -sticky e
grid .entName -row 0 -column 1 -sticky ew
grid .lblMail -row 1 -column 0 -sticky e
grid .entMail -row 1 -column 1 -sticky ew
grid columnconfigure . 1 -weight 1
```

**Dialog-Buttons:**
```tcl
frame .buttons
pack .buttons -side bottom -fill x

button .buttons.ok -text "OK"
button .buttons.cancel -text "Cancel"
pack .buttons.cancel .buttons.ok -side right -padx 5
```

---

## Checkliste

- [ ] Einfaches Layout? -> `pack`
- [ ] Tabelle/Formular? -> `grid`
- [ ] Absolute Position noetig? -> `place`
- [ ] pack und grid NICHT mischen in einem Container!
- [ ] `expand 1` fuer dynamische Groesse
- [ ] `weight` bei grid fuer expandierende Spalten

---

## Siehe auch

- [widget-hierarchie.md](widget-hierarchie.md) - Widget-Struktur
- [leere-frames.md](leere-frames.md) - Leere Container
- [widget-creation-helper.md](widget-creation-helper.md) - Helper-Funktionen

---

Quelle: CLAUDE-TCL-TK-WISSEN.md - Widget-Hierarchie
