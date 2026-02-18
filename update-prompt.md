# Claude Desktop Linux — Version Update Prompts

Reusable prompts for updating the AUR package when a new Claude Desktop version drops.

## How to find the latest version

Check `https://downloads.claude.ai/releases/win32/x64/latest/RELEASES` or look at the Electron app's download URL pattern:
```
https://downloads.claude.ai/releases/win32/x64/<VERSION>/Claude-<HASH>.exe
```

---

## Prompt 1: Build & Fix Patches

Copy-paste this into Claude Code when a new version is available:

> **New Claude Desktop version `<VERSION>` is available.** The download URL is:
> ```
> https://downloads.claude.ai/releases/win32/x64/<VERSION>/Claude-<HASH>.exe
> ```
>
> Please:
> 1. Download the new exe to the project root as `Claude-Setup-x64.exe`
> 2. Run `./scripts/build-local.sh` and capture the output
> 3. For each failing patch:
>    - Extract the new app to `/tmp/claude-new` for analysis
>    - Use `rg` to find the new code pattern in the extracted JS
>    - Update the regex in `patches/*.py` — use `\w+` (or `[\w$]+` if the minified name can start with `$`) for variable names
>    - Test the individual patch: `python3 patches/PATCH.py /tmp/test_index.js`
>    - Verify syntax: `node --check /tmp/test_index.js`
> 4. Rebuild: `./scripts/build-local.sh`
> 5. Verify all 19 patches pass and JS syntax is valid
> 6. Install: `sudo pacman -U build/claude-desktop-bin-*-x86_64.pkg.tar.zst`
> 7. Commit the changes

---

## Prompt 2: Diff & Discover New Changes

Copy-paste this into Claude Code to analyze what changed between two versions:

> **Compare Claude Desktop `<OLD_VERSION>` vs `<NEW_VERSION>` JS bundles.**
>
> Both versions are already extracted:
> - Old: `/tmp/claude-old/app/.vite/build/index.js`
> - New: `/tmp/claude-new/app/.vite/build/index.js`
>
> (If not yet extracted, extract them first using the steps in CLAUDE.md § "Extract and Test Locally".)
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
> 3. **Feature flags** — new flag IDs (function name may change between versions)
>    ```bash
>    # Find the flag function name first (was la(), then Xi(), etc.)
>    rg -o '\w+\("[0-9]{6,}"\)' /tmp/claude-new/app/.vite/build/index.js | head -1
>    # Then compare flag sets
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
> For each area, classify changes as:
> - **Rename only** — minified variable name changed, no action needed
> - **New feature** — new functionality, may need a Linux patch
> - **Structural change** — code logic changed, existing patches may break

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

## Patch Reference

See the **[Patches table in README.md](README.md#patches)** for the full list of all patches including break risk and debug `rg` patterns for finding new code when a patch fails.
