# docir Makefile -- Install / Test
#
# install     - kopiert lib/tm/* nach $(PREFIX)/lib/tcltk/docir/
#               (Standard-Tcl-Konvention; in tcl::tm::path der via
#               pkgIndex.tcl-Bruecke automatisch sichtbar)
# install-user- kopiert nach $(HOME)/lib/tcltk/docir/, fuer User-Setup
#               ohne sudo
# pkgindex    - generiert pkgIndex.tcl neu (nach Modul-Aenderung)
# test        - laeuft alle Tests
# uninstall   - entfernt $(PREFIX)/lib/tcltk/docir/

PREFIX     ?= /usr/local
INSTALLDIR := $(PREFIX)/lib/tcltk/docir
USERDIR    := $(HOME)/lib/tcltk/docir
BINDIR     := $(PREFIX)/bin

.PHONY: install install-bin install-user uninstall test pkgindex clean help

help:
	@echo "Targets:"
	@echo "  make install        # Module nach $(INSTALLDIR) (sudo evtl. noetig)"
	@echo "  make install-bin    # CLI-Tools (md2tilepdf etc.) nach $(BINDIR)"
	@echo "  make install-user   # Module nach $(USERDIR), ohne sudo"
	@echo "  make uninstall      # entfernt $(INSTALLDIR)"
	@echo "  make pkgindex       # pkgIndex.tcl neu generieren"
	@echo "  make test           # Tests"

install:
	mkdir -p $(INSTALLDIR)
	cp -r lib/tm/. $(INSTALLDIR)/
	@echo "Installiert nach $(INSTALLDIR)"

install-bin:
	mkdir -p $(BINDIR)
	cp bin/md2tilepdf $(BINDIR)/
	cp bin/md2tilehtml $(BINDIR)/
	cp bin/md2tilemd $(BINDIR)/
	chmod +x $(BINDIR)/md2tilepdf $(BINDIR)/md2tilehtml $(BINDIR)/md2tilemd
	@echo "Installiert: $(BINDIR)/md2tilepdf $(BINDIR)/md2tilehtml"

install-user:
	mkdir -p $(USERDIR)
	cp -r lib/tm/. $(USERDIR)/
	@echo "Installiert nach $(USERDIR)"
	@echo "Hinweis: $(HOME)/lib/tcltk/ ist nicht automatisch im auto_path."
	@echo "Setze in ~/.profile o.ae.:"
	@echo "  export TCLLIBPATH=\"\$$HOME/lib/tcltk/docir\""

uninstall:
	rm -rf $(INSTALLDIR)
	@echo "Entfernt: $(INSTALLDIR)"

pkgindex:
	tclsh tools/generate-pkgindex.tcl lib/tm --write

test:
	cd tests && tclsh run-all-tests.tcl

clean:
	@echo "Nichts zu loeschen"
