Check @update-prompt.md — it describes how to update patches and docs when a new Claude Desktop version drops.

Quick start — run the build to see if patches still apply:
```bash
rm -rf build/ extract/ Claude-Setup-x64.exe
./scripts/build-local.sh
```

If a new version was downloaded and patches fail:
1. Fix failing patches (Prompt 1 in update-prompt.md)
2. Diff old vs new JS bundles for new platform gates (Prompt 2)
3. Audit feature flags for new/changed flags (Prompt 3)
4. Check if claude-cowork-service also needs updating (cross-dependency)
5. Update docs (CHANGELOG.md, CLAUDE_FEATURE_FLAGS.md, CLAUDE_BUILT_IN_MCP.md, README.md patch table)
6. Commit and push
