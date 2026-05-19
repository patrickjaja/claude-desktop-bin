## New upstream version detected

| | Version |
|---|---|
| **Upstream** | `{{UPSTREAM}}` |
| **Current release** | `{{RELEASED}}` |

---

## Claude Code Update Prompt

Copy-paste this into a Claude Code session to start the update process:

<details><summary>Click to expand prompt</summary>

```
{{CC_PROMPT}}
```

</details>

---

## Linux Compatibility Reference

All upstream changes must be validated against these supported targets:

| Session type | Compositors / DEs | Input backend | Screenshot tools |
|-------------|-------------------|---------------|-----------------|
| X11 | Any (GNOME, KDE, i3, ...) | `xdotool` | `scrot`, `imagemagick`, `gnome-screenshot` |
| Wayland - wlroots | Sway, Hyprland | `ydotool` (+`ydotoold`) | `grim` |
| Wayland - GNOME | GNOME Shell | `ydotool` (+`ydotoold`) | `portal+pipewire`, `gnome-screenshot`, `gdbus` |
| Wayland - KDE | KDE Plasma | `kwin-portal-bridge` (bundled) | `kwin-portal-bridge` (bundled) |
| XWayland | Any Wayland compositor | `xdotool` (fallback) | depends on compositor |

| Distro | Packaging | Min glibc | Arch |
|--------|-----------|-----------|------|
| Arch Linux | AUR | 2.41 | x86_64, aarch64 |
| Ubuntu 22.04+ | `.deb` | 2.35 | amd64, arm64 |
| Debian 11+ | `.deb` | 2.31 | amd64, arm64 |
| Fedora 40+ | `.rpm` | 2.39 | x86_64, aarch64 |
| RHEL 9+ | `.rpm` | 2.34 | x86_64, aarch64 |
| NixOS | Nix flake | 2.40 | x86_64, aarch64 |
| NVIDIA Jetson | `.deb` | 2.35 | aarch64 |

---

## Update Checklist

### Step 0: Clean Slate
- [ ] Remove old build artifacts: `rm -rf build/ extract/ Claude-Setup-x64.exe`
- [ ] Remove leftover dev binaries: `rm -f chrome-native-host.exe cowork-svc.exe smol-bin.vhdx`
- [ ] Verify clean git state: `git status`

### Step 1: Build & Fix Patches
- [ ] Run the build: `./scripts/build-local.sh`
- [ ] If patches fail, extract new app for analysis (see Quick Reference below)
- [ ] Fix each failing patch in `patches/*.nim` - use `[\w$]+` for minified variable names
- [ ] Recompile: `cd patches && make PATCH_NAME && cd ..`
- [ ] Test individual patch: `patches/PATCH_NAME /tmp/test_index.js`
- [ ] Verify JS syntax: `node --check /tmp/test_index.js`
- [ ] Rebuild until all patches pass: `./scripts/build-local.sh`

### Step 2: Linux Compatibility Analysis

Check if new upstream features need Linux support patches:

- [ ] Diff `process.platform` guards between old and new JS - find new darwin/win32-only gates
  ```
  diff <(rg -o '.{0,40}process\.platform.{0,40}' OLD_INDEX | sort -u) \
       <(rg -o '.{0,40}process\.platform.{0,40}' NEW_INDEX | sort -u)
  ```
- [ ] Diff `status:"unavailable"` / `status:"unsupported"` gates - find new restrictions
  ```
  diff <(rg -o '.{0,80}status:"unavailable".{0,80}' OLD_INDEX | sort -u) \
       <(rg -o '.{0,80}status:"unavailable".{0,80}' NEW_INDEX | sort -u)
  ```
- [ ] Search for new mac/win-only code paths missing linux support
  ```
  rg 'process\.platform\s*[!=]==?\s*"(darwin|win32)"' NEW_INDEX | grep -v linux
  ```
- [ ] Check new features against all 5 session types (X11, Wayland-wlroots, Wayland-GNOME, Wayland-KDE, XWayland)
- [ ] Check new native module references - do they need Linux builds for both x86_64 AND aarch64?
  ```
  diff <(rg -o 'require\("[^"]+"\)' OLD_INDEX | sort -u) \
       <(rg -o 'require\("[^"]+"\)' NEW_INDEX | sort -u)
  ```
- [ ] Determine if new patches are needed to add Linux support for newly gated features
- [ ] If new features touch input/screenshot: verify they work with session-specific backends (xdotool vs ydotool vs kwin-portal-bridge)

### Step 3: Diff Old vs New JS Bundles

Remaining non-platform analysis (see [Prompt 2 in update-prompt.md](https://github.com/{{REPO}}/blob/master/update-prompt.md#prompt-2-diff--discover-new-changes)):

- [ ] File-level diff (new/removed files in app.asar)
- [ ] IPC handler diff (`handle("...")` registrations)
- [ ] Claude Code / Cowork subsystem changes
- [ ] Classify findings as: Rename only / New feature / Changed behavior / Removed

### Step 4: Feature Flag Audit

See [Prompt 3 in update-prompt.md](https://github.com/{{REPO}}/blob/master/update-prompt.md#prompt-3-feature-flag-audit):

- [ ] Read `CLAUDE_FEATURE_FLAGS.md` baseline
- [ ] Find new static registry function name (changes every release)
- [ ] Compare flag sets: new flags, removed flags, renamed functions
- [ ] Check if `enable_local_agent_mode.nim` needs new flags in its override list
- [ ] Verify Zod schema includes all overridden flags
- [ ] Update `CLAUDE_FEATURE_FLAGS.md`

### Step 5: ion-dist SPA Audit

See [Prompt 4 in update-prompt.md](https://github.com/{{REPO}}/blob/master/update-prompt.md#prompt-4-ion-dist-3p-config-spa-audit):

- [ ] Check if ion-dist exists in new upstream resources
- [ ] Compare bundle stats against `ION.md` baseline (file count, total size)
- [ ] Check if patched patterns still exist (mountPath, platform ternary)
- [ ] Check for new platform-gated code (mac/win-only without linux)
- [ ] Update `ION.md` and `fix_ion_dist_linux.nim` if anything changed

### Step 6: Cross-Project Dependencies
- [ ] Check if [claude-cowork-service](https://github.com/patrickjaja/claude-cowork-service) needs updating
- [ ] Check cowork protocol for new RPC methods, spawn parameters, or event types
- [ ] See `claude-cowork-service/COWORK_RPC_PROTOCOL.md` for protocol baseline

### Step 7: Update Documentation
- [ ] `CHANGELOG.md` - add new version entry
- [ ] `CLAUDE_FEATURE_FLAGS.md` - if flags added/removed/renamed
- [ ] `CLAUDE_BUILT_IN_MCP.md` - if MCP servers changed
- [ ] `ION.md` - if ion-dist bundle stats or patterns changed
- [ ] `README.md` patch table - if patches added/removed/changed

### Step 8: Commit, Push & Release
- [ ] Commit all changes
- [ ] Push to branch, open PR
- [ ] Trigger build workflow after merge

---

<details><summary>Quick Reference Commands</summary>

### Extract new app for analysis
```bash
mkdir -p /tmp/claude-new
7z x -o/tmp/claude-new Claude-Setup-x64.exe -y
7z x -o/tmp/claude-new/nupkg /tmp/claude-new/AnthropicClaude-*.nupkg -y
asar extract /tmp/claude-new/nupkg/lib/net45/resources/app.asar /tmp/claude-new/app
# New index.js is at: /tmp/claude-new/app/.vite/build/index.js
```

### Platform gate diffs
```bash
# Set these to your actual paths:
OLD_INDEX="/tmp/claude-old/app/.vite/build/index.js"
NEW_INDEX="/tmp/claude-new/app/.vite/build/index.js"

# process.platform guards
diff <(rg -o '.{0,40}process\.platform.{0,40}' "$OLD_INDEX" | sort -u) \
     <(rg -o '.{0,40}process\.platform.{0,40}' "$NEW_INDEX" | sort -u)

# Unavailable/unsupported gates
diff <(rg -o '.{0,80}status:"unavailable".{0,80}' "$OLD_INDEX" | sort -u) \
     <(rg -o '.{0,80}status:"unavailable".{0,80}' "$NEW_INDEX" | sort -u)

# Linux/darwin/win32 references
diff <(rg -o '.{0,40}(darwin|win32|linux).{0,40}' "$OLD_INDEX" | sort -u) \
     <(rg -o '.{0,40}(darwin|win32|linux).{0,40}' "$NEW_INDEX" | sort -u)
```

### Feature flag diff
```bash
diff <(rg -o '\w+\("[0-9]{6,}"\)' "$OLD_INDEX" | sort -u) \
     <(rg -o '\w+\("[0-9]{6,}"\)' "$NEW_INDEX" | sort -u)
```

### Session type detection patterns
```bash
# Check if new code references session detection
rg 'XDG_SESSION_TYPE|WAYLAND_DISPLAY|DISPLAY' "$NEW_INDEX"
```

### Check upstream version
```bash
curl -s https://downloads.claude.ai/releases/win32/x64/.latest | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])"
```

### Trigger build after merge
```bash
gh workflow run build-and-release.yml
```

</details>

---

## Reference Docs

- [update-prompt.md](https://github.com/{{REPO}}/blob/master/update-prompt.md) - Full version update prompts (Prompts 1-4)
- [CLAUDE.md](https://github.com/{{REPO}}/blob/master/CLAUDE.md) - Project guidelines, architecture, and distro/session support tables
- [UPDATE-PROMPT-CC-INPUT-MANUAL.md](https://github.com/{{REPO}}/blob/master/UPDATE-PROMPT-CC-INPUT-MANUAL.md) - Claude Code quick-start prompt

**[Trigger build manually](https://github.com/{{REPO}}/actions/workflows/build-and-release.yml)**

---
*Auto-detected by [version-check workflow](https://github.com/{{REPO}}/actions/workflows/version-check.yml)*
