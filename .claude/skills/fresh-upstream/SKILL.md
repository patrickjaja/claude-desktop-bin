---
name: fresh-upstream
description: For claude-desktop-bin - wipe any existing extracted Claude Desktop bundles and extract a fresh, CLEAN, UNPATCHED copy of the latest upstream Claude.msix into ./tmp/ for patch analysis. Downloads the latest msix if missing or stale, then extracts via 7z + asar (NOT the build script, which applies patches).
disable-model-invocation: true
allowed-tools: Bash(rm -rf *), Bash(mkdir -p *), Bash(7z *), Bash(asar *), Bash(wget *), Bash(node --check *), Bash(ls *), Bash(cat *), Bash(stat *)
---

# Fresh upstream extract (clean, unpatched)

Goal: a pristine unpatched bundle in `./tmp/` so patch work compares against the true upstream. Run from `/home/patrickjaja/development/claude-desktop-bin`. `./tmp/` is gitignored.

**Critical:** `scripts/build-patched-tarball.sh` runs `apply_patches.py` - its output is PATCHED. For a clean baseline use the manual `7z`+`asar` flow below.

## Steps

1. **cd to the repo** and read tracked version:
   ```bash
   cd /home/patrickjaja/development/claude-desktop-bin
   cat .upstream-version
   ```

2. **Resolve latest upstream** version + download URL:
   ```bash
   LATEST_JSON=$(wget -q -O - "https://downloads.claude.ai/releases/win32/x64/.latest")
   LATEST_VERSION=$(echo "$LATEST_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['version'])")
   LATEST_HASH=$(echo "$LATEST_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['hash'])")
   echo "upstream latest: $LATEST_VERSION (hash $LATEST_HASH)"
   ```
   Report latest vs `.upstream-version` so the user sees whether this is a new version.

3. **Download msix if missing or stale.** If `./Claude.msix` is absent, re-download. If it exists, verify it's the latest (compare size/age, or just trust if present and the user didn't ask for newest) - re-download when in doubt:
   ```bash
   wget -O ./Claude.msix "https://downloads.claude.ai/releases/win32/x64/${LATEST_VERSION}/Claude-${LATEST_HASH}.msix"
   ```
   (~150MB.) If the download fails, stop and report the URL for manual fetch.

4. **Wipe old extracted bundles** (project-local only - never touch ~/.config/Claude):
   ```bash
   rm -rf ./tmp ./extract ./build/work 2>/dev/null || true
   ```
   Leave `./Claude.msix` in place (just refreshed) and leave `./build/` packages alone unless the user asked for a full clean.

5. **Extract clean, unpatched** to `./tmp/`:
   ```bash
   mkdir -p ./tmp/extract
   7z x -o./tmp/extract ./Claude.msix -y >/dev/null
   asar extract ./tmp/extract/app/resources/app.asar ./tmp/app.asar.contents
   ```
   - Unpatched main bundle: `./tmp/app.asar.contents/.vite/build/index.js`
   - Renderer bundles: `./tmp/app.asar.contents/.vite/renderer/*/assets/*.js`
   - ion-dist (3P-config SPA): `./tmp/extract/app/resources/ion-dist/`
   - i18n: `./tmp/extract/app/resources/*.json`

6. **Sanity check** and report:
   ```bash
   node --check ./tmp/app.asar.contents/.vite/build/index.js && echo "OK: clean unpatched index.js parses"
   ls -la ./tmp/app.asar.contents/.vite/build/
   ```
   Report: upstream version extracted, where the unpatched index.js is, whether it's a new version vs `.upstream-version`. If new, suggest `/update`. If just refreshing for analysis, suggest `/audit`.

## Notes
- This does NOT patch, build, or bump anything - it only stages a clean bundle.
- Distinguish "clean unpatched" (this skill, manual 7z/asar) from "patched build" (`./scripts/build-local.sh`).
- Stale extracts have different minified names → always re-extract before patch debugging if `./tmp` is older than today.
