Check @update-prompt.md - it describes how to update patches and docs when a new Claude Desktop version drops.

Quick start - run the build to see if patches still apply:

    rm -rf build/ extract/

    # Pick the right build script for your distro:
    # Arch Linux:
    ./scripts/build-local.sh
    # Ubuntu/Debian:
    SKIP_SMOKE_TEST=1 ./scripts/build-ubuntu-local.sh
    # Fedora/RHEL:
    ./scripts/build-fedora-local.sh

If a new version was downloaded and patches fail:
1. Fix failing patches (Prompt 1 in update-prompt.md)
2. Diff old vs new JS bundles for new platform gates (Prompt 2)
3. Audit feature flags for new/changed flags (Prompt 3)
4. Audit ion-dist SPA for new platform gates (Prompt 4 in update-prompt.md)
5. Re-audit platform gates for new Linux-compat opportunities (Prompt 5 in update-prompt.md)
6. Check if claude-cowork-service also needs updating (cross-dependency)
7. Update docs (CHANGELOG.md, CLAUDE_FEATURE_FLAGS.md, CLAUDE_BUILT_IN_MCP.md, ION.md, PLATFORM_GATE_BASELINE.md, README.md patch table)
8. Commit and push
