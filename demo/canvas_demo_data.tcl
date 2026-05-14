# canvas_demo_data.tcl — DocIR-Daten für demo/canvas_demo.tcl (nur Procs, kein Tk)
# Von canvas_demo.tcl per source geladen.

namespace eval ::docir_demo {}

proc ::docir_demo::canvasBuiltinIR {} {
    list \
        [dict create type heading content {{type text text {DocIR → Tk-Canvas}}} meta {level 1}] \
        [dict create type paragraph content [list \
            {type text text {Diese Seite ist reines DocIR (Zwischenrepräsentation), gerendert mit }} \
            {type text text {docir::canvas::render}} \
            {type text text { — ohne HTML- oder PDF-Zwischenschicht.}} \
        ] meta {}] \
        [dict create type hr content {} meta {}] \
        [dict create type heading content {{type text text {Tk canvas}}} meta {level 2}] \
        [dict create type paragraph content {{type text text \
            {Das canvas-Widget zeichnet Linien, Rechtecke, Text, Bilder und weitere Item-Typen. DocIR wird hier in Vektor-Items auf dem Canvas abgebildet — gut für Vorschau und Druck-Pipelines.}}} meta {}] \
        [dict create type pre content {{type text text \
            {.c create line 0 0 100 50 -fill blue\n.c create text 50 80 -text "Hello"}}} meta {kind code}] \
        [dict create type heading content {{type text text {Häufige Item-Typen}}} meta {level 3}] \
        [dict create type list content [list \
            [dict create type listItem content {{type text text {line, rectangle, oval}}} meta [dict create kind ul term ""]] \
            [dict create type listItem content {{type text text {text (mit Umbruch über -width)}}} meta [dict create kind ul term ""]] \
            [dict create type listItem content {{type text text {polygon, image, window}}} meta [dict create kind ul term ""]] \
        ] meta {kind ul}] \
        [dict create type table content [list \
            [dict create type tableRow content [list \
                [dict create type tableCell content {{type text text API}} meta {}] \
                [dict create type tableCell content {{type text text Bedeutung}} meta {}] \
            ] meta {}] \
            [dict create type tableRow content [list \
                [dict create type tableCell content {{type text text {::docir::canvas::render}}} meta {}] \
                [dict create type tableCell content {{type text text {IR → Items}}} meta {}] \
            ] meta {}] \
            [dict create type tableRow content [list \
                [dict create type tableCell content {{type text text {::docir::canvas::clear}}} meta {}] \
                [dict create type tableCell content {{type text text {alles mit Tag docir-canvas}}} meta {}] \
            ] meta {}] \
        ] meta {columns 2 hasHeader 1}] \
        [dict create type blank content {} meta {lines 1}] \
        [dict create type paragraph content {{type text text \
            {Tipp: Mit Mausrad scrollen (sofern gebunden) oder Scrollbar nutzen.}}} meta {}]
}
