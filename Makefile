# Simple Makefile
PREFIX ?= /usr/local
BIN := $(PREFIX)/bin/lfm

.PHONY: install uninstall fmt

install:
	install -m 0755 lfm.sh $(BIN)

uninstall:
	rm -f $(BIN)

fmt:
	shellcheck lfm.sh || true
