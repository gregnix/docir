# book.tcl -- manifest for your book.
# Edit the metadata, list chapters in reading order, then build:
#   tclsh ../../book/book-build.tcl . -number
#
# Reorder chapters by moving lines; filename prefixes are ignored once this
# file exists.

set title     "My Book Title"
set author    "Your Name"
set subtitle  "An optional subtitle"      ;# shown on the title page
set date      "2026"                      ;# shown on the title page
set titlePage 1                           ;# 1 = render a dedicated title page

set tocTitle   "Contents"
set indexTitle "Index"

set chapters {
    010-introduction.md
    020-first-topic.md
}
