# Build every patches/*.nim into a same-named executable.
#
# Usage:
#   make -j$(nproc)      # parallel build (default target = all)
#   make clean           # remove binaries and nim caches
#
# Each binary is rebuilt when its .nim source is newer; make drives the
# dep tracking. The orchestrator (scripts/apply_patches.py) runs
# the compiled binaries for each patch.

NIM       ?= nim
NIMFLAGS  ?= c -d:release --opt:speed --mm:orc --hints:off

SRCS := $(wildcard *.nim)
BINS := $(SRCS:.nim=)

.PHONY: all clean
.DEFAULT_GOAL := all

all: $(BINS)

%: %.nim
	@echo "  NIM  $@"
	@$(NIM) $(NIMFLAGS) --nimcache:.nimcache/$* -o:$@ $< > /dev/null

# JS snippets shared between patches. Nim embeds them via staticRead,
# so a change to the .js forces a rebuild of the binary.
fix_computer_use_linux: \
  ../js/cu_linux_executor.js \
  ../js/cu_handler_injection.js

clean:
	@rm -rf $(BINS) .nimcache
