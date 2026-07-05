LUA ?= lua
# `love` is often a shell alias (not on PATH for make); fall back to the app bundle.
LOVE ?= $(shell command -v love 2>/dev/null || echo /Applications/love.app/Contents/MacOS/love)
TESTS := $(wildcard tests/*_test.lua)

.PHONY: all check test smoke run

all: check test smoke

check:
	luacheck .

# Unit tests print nothing on success, FAIL lines + non-zero exit on failure.
test:
	@for t in $(TESTS); do echo "== $$t"; $(LUA) $$t || exit 1; done; echo "TESTS OK"

smoke:
	$(LOVE) . --smoke

run:
	$(LOVE) .
