---
name: update
description: For claude-desktop-bin - handle a new upstream Claude Desktop version end-to-end: build, fix failing patches, diff old vs new JS for new platform gates, audit feature flags + ion-dist + platform gates, update baseline docs + CHANGELOG, bump .upstream-version, then commit. Mirrors issue #145 / UPDATE-PROMPT-CC-INPUT-MANUAL.md.
disable-model-invocation: true
---

# Update to a new upstream Claude Desktop version

**When to run this:** normally you don't. CI auto-releases new upstream versions (version-check.yml dispatches build-and-release.yml; green run = released + `.upstream-version` bumped + tracking issue closed). Run this skill when the **auto-release failed** (a comment on the "new version detected" issue links the failed run) or when you want a deep audit of a bump. On a patch failure, decide FIRST: did the re-minify just move the anchor (fix the regex), or did upstream natively implement what we patch (**remove the patch** — the expected direction, since Anthropic maintains 1p Linux support; do NOT convert to a regression guard)?

Run from `/home/patrickjaja/development/claude-desktop-bin`. The official Linux `.deb` is remotely managed and re-minifies every release; patches use `[\w$]+` wildcards on stable string anchors. Step 1 runs `/fresh-upstream` for a clean extract; Step 9 ends with `/deploy` to release. `$ARGUMENTS` may name a target version.

Use sequential thinking and delegate independent analysis (diff, flag audit, ion-dist, platform gates) to parallel sub-agents where useful; you coordinate and edit.

## Step 0 - clean slate
```bash
cd /home/patrickjaja/development/claude-desktop-bin
git status                  # must be clean before starting
rm -rf build/ extract/      # old artifacts
```
Note current `.upstream-version`. If you're here because the auto-release failed, read the failed run's log first — it names exactly which patch (and which sub-patch counter) failed.

## Step 1 - build & fix patches
Run the build for this OS (Arch here). It auto-downloads the latest official `.deb`, applies patches, packages:
```bash
./scripts/build-local.sh
# Ubuntu/Debian: SKIP_SMOKE_TEST=1 ./scripts/build-ubuntu-local.sh
# Fedora/RHEL:   ./scripts/build-fedora-local.sh
```
If patches fail (upstream renamed identifiers / refactored / removed a feature):
1. Get a clean unpatched extract (run `/fresh-upstream`, or it's already in `./tmp/app.asar.contents/.vite/build/`). The main bundle is code-split since v1.19367.0: `index.js` is a loader stub, the code lives in `index.chunk-<hash>.js` siblings (hashes change every release) + `index.pre.js`; `rg` across `index*.js`, not just `index.js`.
2. For each failing patch, find the new pattern with `rg`, then fix `patches/<name>.nim` using `[\w$]+` + capture/replace. **Edit the `.js` in `js/`** for Computer Use / cowork-font (they're `staticRead` into the patch).
3. Recompile + test one patch against the stub+chunks concatenation (what the orchestrator stages):
   ```bash
   cd patches && make <patch_name> && cd ..
   B=./tmp/app.asar.contents/.vite/build
   { cat $B/index.js; for c in $B/index.chunk-*.js; do printf '\n/*__CDB_SPLIT__%s__*/\n' "$(basename $c)"; cat "$c"; done; } > /tmp/test-index.js
   patches/<patch_name> /tmp/test-index.js; echo "exit=$?"
   node --check /tmp/test-index.js
   ```
4. Re-run the build until all patches pass. **Every sub-patch must succeed or `quit(1)`** - never `[WARN]`+continue. If a feature was upstreamed, **remove the patch** (`git rm`) - once nothing of ours is injected, a patch that only asserts upstream's own behavior is not maintaining our modification. See CLAUDE.md Rule 4/6. Pure assert-only regression-guard patches were retired 2026-07-15.

## Step 2 - Linux-compat analysis (new gates?)
Diff old vs new for newly darwin/win32-gated features that need Linux support (set `OLD`/`NEW` to the two index.js paths):
```bash
diff <(rg -o '.{0,40}process\.platform.{0,40}' "$OLD"|sort -u) <(rg -o '.{0,40}process\.platform.{0,40}' "$NEW"|sort -u)
diff <(rg -o '.{0,80}status:"unavailable".{0,80}' "$OLD"|sort -u) <(rg -o '.{0,80}status:"unavailable".{0,80}' "$NEW"|sort -u)
rg 'process\.platform\s*[!=]==?\s*"(darwin|win32)"' "$NEW" | grep -v linux
diff <(rg -o 'require\("[^"]+"\)' "$OLD"|sort -u) <(rg -o 'require\("[^"]+"\)' "$NEW"|sort -u)   # new native modules → need x86_64+aarch64
```
Validate any new input/screenshot feature across all 5 session types (X11, wlroots, GNOME, KDE, XWayland).

## Step 3 - diff old vs new JS
File-level diff (new/removed files in app.asar), IPC handler diff (`handle("...")`), Claude Code / Cowork subsystem changes. Classify each finding: rename-only / new feature / changed behavior / removed. (Prompt 2 in `update-prompt.md`.)

## Step 4 - feature-flag audit
Read `baseline/CLAUDE_FEATURE_FLAGS.md`. Find the new static-registry function name (changes every release). Diff flag sets:
```bash
diff <(rg -o '\w+\("[0-9]{6,}"\)' "$OLD"|sort -u) <(rg -o '\w+\("[0-9]{6,}"\)' "$NEW"|sort -u)
```
Check `enable_local_agent_mode.nim`'s override list still covers the cowork/code flags and its Zod schema includes them. Update the doc + version-history table.

Also refresh the flag catalog in `js/growthbook_overrides.js` (TEMPLATE): it lists every store-consulted flag of the audited version, commented out. Extract IDs with `rg -o '[\w$]+(?:\.[\w$]+)*\("([0-9]{6,10})"[,)]' -r '$1' <new-bundle-concat> | sort -u`, drop the IDs force-rewritten by patches (`rg -oI '"[0-9]{6,10}"' patches/*.nim`, minus IDs only mentioned in comments), and update descriptions + the version stamp in the header. Then regenerate the browsable copy and rebuild the binary:
```bash
node scripts/check-jsonc-template-sync.sh --write   # updates docs/claude-desktop-bin.jsonc
touch patches/add_growthbook_overrides.nim && (cd patches && make)  # Makefile doesn't track staticRead deps
```
CI runs `scripts/check-jsonc-template-sync.sh` (no `--write`) and fails if the docs catalog drifts from the shipped template.

## Step 5 - ion-dist SPA audit
Read `baseline/ION.md`. Confirm ion-dist exists in new resources; compare bundle stats + content-hash of the config chunk; confirm `fix_ion_dist_linux.nim` patterns (mountPath linux key, platform ternary) still match (it finds the target by content signature, not filename). Update `ION.md`/the patch if changed. (Prompt 4.)

## Step 6 - platform-gate re-audit
Read `baseline/PLATFORM_GATE_BASELINE.md`. Re-count darwin/win32/linux gates; reclassify any new ones PATCHED/NATIVE/STUB/PORTABLE. Any PORTABLE = a new Linux-support opportunity. Update the doc. (Prompt 5.)

## Step 7 - Cowork backend
Cowork now runs on the `.deb`'s bundled native VM backend (cowork-linux-helper + virtiofsd + smol-bin + QEMU/OVMF; requires `/dev/kvm`). The old `claude-cowork-service` Go daemon is deprecated and out of scope - no cross-dependency to check.

## Step 8 - docs
Update only what changed:
- `CHANGELOG.md` - add the new entry (one `##` section per day, newest at top; informative not a debug log).
- `baseline/CLAUDE_FEATURE_FLAGS.md`, `CLAUDE_BUILT_IN_MCP.md`, `ION.md`, `PLATFORM_GATE_BASELINE.md` - if their tracked internals moved.
- `README.md` patch table - if patches added/removed/changed. **Do NOT touch README install-command version numbers** (CI updates those via `sed`; manual edits cause merge conflicts).

## Step 9 - bump .upstream-version (required) + commit
```bash
echo "<NEW_VERSION>" > .upstream-version    # closes the "new version detected" issue, greens the README badge
```
Then commit + push to `master` directly (per global CLAUDE.md), only when the user says to. After merge, release with `/deploy` (or `/deploy force` for patch-only changes where upstream version didn't move).

## Guardrails
- Always re-extract fresh if `./tmp` is stale (different minified names → wrong conclusions).
- `node --check` after every patch edit.
- A green build with all patches applied + docs synced + `.upstream-version` bumped is "done". Don't claim done with failing patches.
