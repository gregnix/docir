#!/usr/bin/env tclsh
# tools/drift-audit.tcl
#
# Prueft pro Block-Typ und Spec-Feld, ob jeder Renderer das Feld
# tatsaechlich verwendet. Drift = Spec dokumentiert ein Feld, ein
# Renderer nutzt es aber nicht (auch nicht via Helper).

set scriptDir [file dirname [file normalize [info script]]]
set repoRoot  [file dirname $scriptDir]

set renderers {html svg pdf canvas md roff tilepdf rendererTk}

# Spec: Block-Typ -> Liste Felder
set specFields {
    image          {url alt title}
    list           {kind indentLevel}
    listItem       {kind term}
    doc_header     {name section version part}
    div            {class id}
    table          {columns alignments hasHeader source}
    pre            {kind}
    heading        {level id}
    blank          {lines}
    footnote_def   {id num}
    paragraph      {class}
}

# Liest ein Renderer-Modul komplett.
proc loadRenderer {repoRoot renderer} {
    set path [file join $repoRoot lib tm docir ${renderer}-0.1.tm]
    set fh [open $path r]
    set src [read $fh]
    close $fh
    return $src
}

# Prueft ob ein Feld irgendwo im Renderer als dict-Zugriff genutzt wird.
# Akzeptierte Patterns:
#   dict get $m fieldname
#   dict exists $m fieldname
#   dict get $meta fieldname
#   "fieldname" ist Argument an dict get / dict exists generell
proc rendererUsesField {src field} {
    # Pattern: dict (get|exists) <var> <field>
    set re {dict\s+(?:get|exists)\s+\$\w+\s+}
    append re $field
    append re {\M}
    return [regexp $re $src]
}

# ------------------------------------------------------------
puts "Drift-Audit: Block-Typ x Spec-Feld x Renderer"
puts "============================================="
puts ""

set drifts 0

foreach {block fields} $specFields {
    puts "### $block — Spec-Felder: [join $fields {, }]"
    # Header
    puts -nonewline [format "  %-10s" ""]
    foreach f $fields {
        puts -nonewline [format " %-12s" $f]
    }
    puts ""

    foreach r $renderers {
        set src [loadRenderer $repoRoot $r]
        puts -nonewline [format "  %-10s" $r]
        foreach f $fields {
            if {[rendererUsesField $src $f]} {
                puts -nonewline [format " %-12s" "ok"]
            } else {
                puts -nonewline [format " %-12s" "DRIFT"]
                incr drifts
            }
        }
        puts ""
    }
    puts ""
}

puts "============================================="
puts "Total Drift-Punkte: $drifts"
puts ""
puts "Hinweis: 'DRIFT' bedeutet das Renderer-Modul nutzt das Spec-Feld nicht."
puts "  - In manchen Faellen ist das beabsichtigt (z.B. nroff kennt kein 'title')."
puts "  - In anderen ist es echtes Versehen, das gefixt werden sollte."
