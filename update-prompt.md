# Claude Desktop Linux — Version Update Prompts

Reusable prompts for updating the AUR package when a new Claude Desktop version drops.

## How to find the latest version

The build script auto-downloads the latest version. To check manually:

```bash
# JSON with version + hash (preferred)
curl -s https://downloads.claude.ai/releases/win32/x64/.latest
# Or the RELEASES file
curl -s https://downloads.claude.ai/releases/win32/x64/latest/RELEASES
```

---

## Step 0: Clean Slate (Run First)

Before any version update, remove stale artifacts so the build downloads fresh:

> **Prepare for a clean Claude Desktop update.**
>
> 1. Remove old build artifacts and exe:
>    ```bash
>    rm -rf build/ extract/
>    rm -f Claude-Setup-x64.exe
>    ```
> 2. Remove leftover dev binaries from project root:
>    ```bash
>    rm -f chrome-native-host.exe cowork-svc.exe smol-bin.vhdx
>    ```
> 3. Verify clean state:
>    ```bash
>    git status
>    ```
>
> Then proceed to **Prompt 1** — the build script will auto-download the latest exe.

---

## Prompt 1: Build & Fix Patches

Copy-paste this into Claude Code when a new version is available:

> **New Claude Desktop version is available.** Please build and fix patches:
>
> 1. Read the current reference docs (this is your version A baseline):
>    - `CLAUDE_FEATURE_FLAGS.md` — current feature flags, function names, GrowthBook IDs
>    - `CLAUDE_BUILT_IN_MCP.md` — current MCP servers, registration patterns
>    - `CHANGELOG.md` — recent version history (first entry = current version)
>
> 2. Run the build (auto-downloads latest exe):
>    ```bash
>    ./scripts/build-local.sh
>    ```
>
> 3. If patches fail, extract the app for analysis:
>    ```bash
>    mkdir -p /tmp/claude-new
>    7z x -o/tmp/claude-new Claude-Setup-x64.exe -y
>    7z x -o/tmp/claude-new/nupkg /tmp/claude-new/AnthropicClaude-*.nupkg -y
>    asar extract /tmp/claude-new/nupkg/lib/net45/resources/app.asar /tmp/claude-new/app
>    ```
>
> 4. For each failing patch:
>    - Use `rg` to find the new code pattern in the extracted JS
>    - Update the regex in `patches/*.py` — use `\w+` (or `[\w$]+` if the minified name can start with `$`) for variable names
>    - Test the individual patch: `python3 patches/PATCH.py /tmp/test_index.js`
>    - Verify syntax: `node --check /tmp/test_index.js`
>
> 5. Rebuild: `./scripts/build-local.sh`
>
> 6. Verify all patches pass and JS syntax is valid:
>    ```bash
>    # Count patches (should match build output)
>    ls patches/*.py | wc -l
>    ```
>
> 7. Run the Feature Flag Audit (Prompt 3) to check for new/changed flags
>
> 8. Install: `sudo pacman -U build/claude-desktop-bin-*-x86_64.pkg.tar.zst`
>
> 9. Update documentation (compare what you found vs your version A baseline):
>    - `CLAUDE_FEATURE_FLAGS.md` — if flags added/removed/renamed
>    - `CLAUDE_BUILT_IN_MCP.md` — if MCP servers changed (check `registerInternalMcpServer` calls)
>    - `CHANGELOG.md` — add new version entry
>    - `README.md` patch table — if patches added/removed/changed
>
> 10. Commit the changes

---

## Prompt 2: Diff & Discover New Changes

Copy-paste this into Claude Code to analyze what changed between two versions:

> **Compare Claude Desktop JS bundles between old and new version.**
>
> 1. Read the reference docs first (version A baseline):
>    - `CLAUDE_FEATURE_FLAGS.md` — know what flags exist before diffing
>    - `CLAUDE_BUILT_IN_MCP.md` — know what MCP servers exist before diffing
>
> 2. Both JS versions should be extracted:
>    - Old: `/tmp/claude-old/app/.vite/build/index.js`
>    - New: `/tmp/claude-new/app/.vite/build/index.js`
>
>    (If not yet extracted, extract them first using the steps in CLAUDE.md § "Extract and Test Locally".)
>
> Run these comparisons and summarize the findings:
>
> 1. **File-level diff** — new or removed files
>    ```bash
>    diff <(cd /tmp/claude-old/app && find . -type f | sort) \
>         <(cd /tmp/claude-new/app && find . -type f | sort)
>    ```
>
> 2. **Platform checks** — new `process.platform` guards
>    ```bash
>    diff <(rg -o '.{0,40}process\.platform.{0,40}' /tmp/claude-old/app/.vite/build/index.js | sort -u) \
>         <(rg -o '.{0,40}process\.platform.{0,40}' /tmp/claude-new/app/.vite/build/index.js | sort -u)
>    ```
>
> 3. **Feature flags** — new flag IDs
>    ```bash
>    # Find the current flag function name (changes every release)
>    rg -o '\w+\("[0-9]{6,}"\)' /tmp/claude-new/app/.vite/build/index.js | head -1
>    # Then compare flag sets between old and new
>    diff <(rg -o '\w+\("[0-9]{6,}"\)' /tmp/claude-old/app/.vite/build/index.js | sort -u) \
>         <(rg -o '\w+\("[0-9]{6,}"\)' /tmp/claude-new/app/.vite/build/index.js | sort -u)
>    ```
>
> 4. **Unavailable/unsupported gates** — new feature restrictions
>    ```bash
>    diff <(rg -o '.{0,80}status:"unavailable".{0,80}' /tmp/claude-old/app/.vite/build/index.js | sort -u) \
>         <(rg -o '.{0,80}status:"unavailable".{0,80}' /tmp/claude-new/app/.vite/build/index.js | sort -u)
>    ```
>
> 5. **IPC handlers** — new `handle("...")` registrations
> 6. **Native module refs** — new `require("...")` calls
> 7. **Linux/darwin/win32 refs** — new platform-specific code
> 8. **Claude Code / Cowork refs** — changes to these subsystems
>
> For each finding, classify as:
> - **Rename only** — minified variable name changed, no action needed
> - **New feature** — new functionality, may need a Linux patch
> - **Changed behavior** — existing logic changed, existing patches may break
> - **Removed** — feature or code path removed, clean up patches/docs if affected
>
> After analysis, update docs to reflect the new version:
> - `CLAUDE_FEATURE_FLAGS.md` — new/removed flags, renamed functions, updated version history table
> - `CLAUDE_BUILT_IN_MCP.md` — new/removed MCP servers, renamed registration functions
> - `CHANGELOG.md` — add entry summarizing what changed, what was patched, what's new upstream

---

## Prompt 3: Feature Flag Audit

Run this on EVERY version update to catch new/changed feature flags:

> **Audit feature flags for the new Claude Desktop version.**
>
> 1. Read `CLAUDE_FEATURE_FLAGS.md` first — this is your version A baseline. Note the current:
>    - Feature count and names
>    - Static registry function name
>    - Async merger function name
>    - GrowthBook flag IDs
>    - Version history table (last entry = previous version)
>
> 2. Find the static registry function (name changes every release):
>    ```bash
>    # Anchor on a known flag name to find the function
>    rg -o '.{0,30}ccdPlugins.{0,30}' /tmp/claude-new/app/.vite/build/index.js | head -3
>    # Extract the function name pattern
>    rg -o '[\w$]+\(\)\{return\{.*ccdPlugins' /tmp/claude-new/app/.vite/build/index.js | head -1
>    ```
>
> 3. Extract all feature names from the static registry
>
> 4. Compare against your baseline (`CLAUDE_FEATURE_FLAGS.md`) — flag any:
>    - **New features** not in the doc
>    - **Removed features** missing from the new registry
>    - **Renamed functions** (static registry, async merger, gate functions)
>
> 5. Check for gate changes:
>    - Features that moved into/out of platform-gating wrappers
>    - Platform checks added/removed
>    - New async overrides in the feature merger function
>    ```bash
>    # Find the async merger (returns Promise with feature overrides)
>    rg -o '.{0,40}async\(\)=>\(\{.{0,60}' /tmp/claude-new/app/.vite/build/index.js | head -5
>    ```
>
> 6. Check if `enable_local_agent_mode.py` needs new flags in its override list
>
> 7. Verify the feature schema includes all flags we override:
>    ```bash
>    # Find the Zod schema for features
>    rg -o '.{0,20}ccdPlugins.*z\.\w+' /tmp/claude-new/app/.vite/build/index.js | head -3
>    ```
>
> 8. Update `CLAUDE_FEATURE_FLAGS.md`:
>    - Add/remove features from the catalog
>    - Update all function names to match the new version
>    - Update GrowthBook flag IDs (new/removed)
>    - Add row to version history table
>    - Update patches if needed
>
> **Why:** Feature flags control which UI elements appear (Code tab, Cowork tab,
> plugin buttons, etc.). Missing a new flag means features silently disappear.

---

## Cross-Project Dependencies

This project depends on [claude-cowork-service](../claude-cowork-service/). When a new Claude Desktop version drops:
- **Check both projects** — upstream changes may affect the Electron patches (this repo) AND the cowork Go backend
- Cowork protocol changes (new RPC methods, spawn parameters, event types) are tracked in `claude-cowork-service/COWORK_RPC_PROTOCOL.md`
- Run the cowork-service update process too: see `claude-cowork-service/UPDATE-PROMPT-CC-INPUT-MANUAL.md`

---

## Common Variable Renames

Minified names change every release. The pattern is always the same — just the identifier changes. Key categories:

| Category | Examples | Regex tip |
|----------|----------|-----------|
| Electron module | `ce`, `de`, `Pe` | Usually stable as `Pe` |
| Path module | `tt`, `rt` | Use `\w+` |
| Assert module | `oo`, `lo` | Use `\w+` |
| Feature flag fn | `la()`, `Xi()` | Use `\w+\("[0-9]+"\)` |
| Status enum | `Cs`, `$s`, `ps` | Use `[\w$]+` ($ is valid in JS identifiers) |
| CCD gate fn | `Hb`, `Gw` | Use `\w+` — don't hardcode |
| Spawn helper | `xu`, `Cu`, `ti` | Use `\w+` |

---

## Change Detection Summary

| What changes | How to detect | Impact |
|-------------|---------------|--------|
| Minified variable names | Build fails — patch regex doesn't match | Update `\w+` patterns in `patches/*.py` |
| New platform gate (`darwin`/`win32`) | Prompt 2 step 2 — `process.platform` diff | New patch needed to add Linux support |
| New feature flag | Prompt 3 — static registry diff | Add to `enable_local_agent_mode.py` override |
| Feature flag removed | Prompt 3 — flag missing from registry | Remove from override, update docs |
| New IPC handler | Prompt 2 step 5 — `handle("...")` diff | May need Linux implementation |
| Structural JS refactor | Multiple patches fail + new code shape | Rewrite affected patches to match new structure |
| New MCP server | Search for `registerInternalMcpServer` | Update `CLAUDE_BUILT_IN_MCP.md` |
| Cowork protocol change | Diff spawn/event/RPC patterns | Update `claude-cowork-service` too |

---

## Patch Reference

See the **[Patches table in README.md](README.md#patches)** for the full list of all patches including break risk and debug `rg` patterns for finding new code when a patch fails.
