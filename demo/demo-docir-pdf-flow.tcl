#!/usr/bin/env tclsh
# demo-docir-pdf-flow.tcl
#
# Demonstrates docir -> PDF rendering of flow-diagram code blocks.
#
# A ```flow (or ```tuflow) fenced block is parsed by tclutils::tuflow into a
# tudiagram model, rasterised to PNG by tudiagram::toPng (pure Tcl, no browser
# and no external SVG rasteriser) and embedded into the PDF as an image. A
# ```mermaid block is rendered the same way (best-effort tuflow subset), while
# an ordinary code block (e.g. ```tcl) stays a normal monospace code box.
#
# Everything is lazy + defensive: if tclutils::tuflow is not installed, or a
# block does not parse, docir-pdf silently falls back to the code box, so the
# PDF export can never break on a diagram block.
#
# Prerequisites (installed in tcl::tm::path / auto_path):
#   docir 0.1.1, docir::pdf 0.2, pdf4tcl, pdf4tcllib,
#   tclutils::tuflow, tclutils::tudiagram, tclutils::tupngdraw, tclutils::common

package require docir::pdf

# ----------------------------------------------------------------------------
# Tiny IR builders so the document below reads top-to-bottom.
# ----------------------------------------------------------------------------
proc head {lv txt} {
    return [dict create type heading \
        content [list [dict create type text text $txt]] meta [list level $lv]]
}
proc para {txt} {
    return [dict create type paragraph \
        content [list [dict create type text text $txt]] meta {}]
}
proc block {lang src} {
    return [dict create type pre \
        content [list [dict create type text text $src]] \
        meta [list kind code language $lang]]
}

# ----------------------------------------------------------------------------
# Flow sources (compact arrow notation; node shapes: [box] (round) ([stadium])
# ((circle)) {diamond}; edges --> --- -.-> ==> with |label| or -- label -->).
# Diagram labels are kept ASCII because the diagram font is a fixed bitmap face.
# ----------------------------------------------------------------------------
set pipeline {flowchart LR
    S[Source] --> L[Lint]
    L --> C[Compile]
    C --> T[Test]
    T --> P([Package])}

set decision {flowchart LR
    A[Commit] --> B{Tests ok?}
    B -->|yes| C[Merge]
    B -->|no| D[Fix]
    D --> A
    C --> E((Release))}

set forkmerge {flowchart TB
    Start --> A[Fetch]
    Start --> B[Parse]
    Start --> C[Validate]
    A --> J[Join]
    B --> J
    C --> J
    J --> End([Done])}

set skipedge {flowchart LR
    Lex[Lexer] --> Parse[Parser]
    Parse --> Sem[Semantic]
    Sem --> Gen[Codegen]
    Parse --> Gen}

set mermaidsrc {flowchart LR
    Idea --> Draft
    Draft --> Review
    Review -->|approve| Publish
    Review -->|reject| Draft}

set tclsrc {proc greet {name} {
    puts "Hallo, $name!"
}
greet Welt}

# ----------------------------------------------------------------------------
# Assemble the document IR.
# ----------------------------------------------------------------------------
set ir [list \
    [head 1 "docir -> PDF: flow & mermaid"] \
    [para "Jeder ```flow-Block wird von tuflow geparst, von tudiagram zu PNG\
           gerendert (pure Tcl) und als Bild ins PDF eingebettet. Ein normaler\
           Code-Block bleibt eine Monospace-Box."] \
\
    [head 2 "1. Lineare Pipeline (LR)"] \
    [para "Eine einfache Kette von Boxen; der letzte Knoten ist ein Stadium."] \
    [block flow $pipeline] \
\
    [head 2 "2. Entscheidungs-Flow mit Kantenlabels"] \
    [para "Diamant-Knoten, beschriftete Kanten (yes/no) und ein Zyklus\
           (Fix -> Commit)."] \
    [block flow $decision] \
\
    [head 2 "3. Fork / Merge (TB)"] \
    [para "Parallele Pfade, die wieder zusammenlaufen -- 2D-Layout von oben\
           nach unten."] \
    [block flow $forkmerge] \
\
    [head 2 "4. Skip-Edge-Routing (LR)"] \
    [para "Die Kante Parser -> Codegen ueberspringt einen Rang und wird per\
           Dummy-Knoten um die Kette herum geroutet, statt hinter den Boxen\
           durchzulaufen."] \
    [block flow $skipedge] \
\
    [head 2 "5. mermaid-Tag im PDF"] \
    [para "Ein ```mermaid-Block wird im PDF best-effort ueber tuflow\
           gerendert (im HTML-Sink bliebe er dagegen browserseitiges\
           mermaid.js)."] \
    [block mermaid $mermaidsrc] \
\
    [head 2 "6. Normaler Code-Block (Kontrast)"] \
    [para "Ein ```tcl-Block ist kein Diagramm und bleibt eine Code-Box:"] \
    [block tcl $tclsrc] \
]

# ----------------------------------------------------------------------------
# Render.
# ----------------------------------------------------------------------------
set out [file join [file dirname [file normalize [info script]]] \
             demo-docir-pdf-flow.pdf]
docir::pdf::render $ir $out [dict create \
    title    "docir -> PDF: flow & mermaid" \
    author   "tuflow / tudiagram demo" \
    date     "2026-06-20"]

puts "geschrieben: $out ([file size $out] bytes)"
