# Build every patches-nim/*.nim into a same-named executable.
#
# Usage:
#   make -j$(nproc)      # parallel build (default target = all)
#   make clean           # remove binaries and nim caches
#
# Each binary is rebuilt when its .nim source is newer; make drives the
# dep tracking. The Python orchestrator (scripts/apply_patches.py)
# auto-detects these binaries and prefers them over the Python sources.

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

# JS snippets shared between Python and Nim implementations. Each is a
# checked-in plain .js file under ../js/; Nim embeds them via
# staticRead, so a change to the .js forces a rebuild of the binary.
fix_computer_use_linux: \
  ../js/cu_linux_executor.js \
  ../js/cu_handler_injection.js \
  ../js/cu_mode_preamble.js \
  ../js/executor_linux.js

fix_cowork_linux: ../js/cowork_mode_preamble.js

clean:
	@rm -rf $(BINS) .nimcache
