# Convenience wrapper around install.sh. The real logic lives in install.sh;
# this just gives the familiar make entry points.
SHELL := /bin/bash

.PHONY: install uninstall clean help

help:
	@echo "Strix Halo Power — targets:"
	@echo "  make install   build + install everything (driver, services, bridge, applet)"
	@echo "  make uninstall remove everything"
	@echo "  make clean     remove local build artifacts"

install:
	@bash install.sh

uninstall:
	@bash uninstall.sh

clean:
	@rm -f driver/ec_su_axb35.ko driver/*.o driver/*.mod driver/*.mod.c \
	      driver/modules.order driver/Module.symvers driver/*.cmd
	@echo "cleaned local build artifacts (driver/ submodule)"
