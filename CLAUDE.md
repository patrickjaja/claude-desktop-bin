# CLAUDE.md - Project Guidelines

## Project Overview

This is an AUR package that repackages Claude Desktop (Windows) for Arch Linux. It applies JavaScript patches to make the Electron app work on Linux.

**Target platform:** Linux only. We do NOT need macOS or Windows compatibility — all patches target Linux exclusively (X11, Wayland, XWayland). Supported distros: Arch Linux (AUR primary), plus Fedora/Ubuntu via RPM/DEB packaging.

**Architectures:** x86_64 (primary) and aarch64 (Raspberry Pi 5, NVIDIA Jetson/DGX Spark, etc.). All native binaries (node-pty, kwin-portal-bridge) must be built for both architectures.

**Supported distros & session managers:**

| Distro | Packaging | Min glibc | Arch |
|--------|-----------|-----------|------|
| Arch Linux | AUR (`claude-desktop-bin`) | 2.41 (rolling) | x86_64, aarch64 |
| Ubuntu 22.04+ | `.deb` | 2.35 | amd64, arm64 |
| Debian 11+ | `.deb` | 2.31 | amd64, arm64 |
| Fedora 40+ | `.rpm` | 2.39 | x86_64, aarch64 |
| RHEL 9+ | `.rpm` | 2.34 | x86_64, aarch64 |
| NixOS | Nix flake | 2.40 (current) | x86_64, aarch64 |
| NVIDIA Jetson (JetPack 6) | `.deb` | 2.35 | aarch64 |
| Any (glibc) | `.AppImage` | varies | x86_64, aarch64 |

**glibc floor: 2.31** (Debian 11 Bullseye). All compiled binaries shipped in the package (kwin-portal-bridge, node-pty) must run on glibc >= 2.31. CI enforces this via `cargo-zigbuild --target ...-gnu.2.31` and `objdump` verification. If a new native binary is added, it must follow the same constraint.

| Session type | Compositors / DEs | Input backend | Screenshot tools |
|-------------|-------------------|---------------|-----------------|
| X11 | Any (GNOME, KDE, i3, …) | `xdotool` | `scrot`, `imagemagick`, `gnome-screenshot` |
| Wayland — wlroots | Sway, Hyprland | `ydotool` (+`ydotoold`) | `grim` |
| Wayland — GNOME | GNOME Shell | `ydotool` (+`ydotoold`) | `portal+pipewire` (GNOME 46+), `gnome-screenshot`, `gdbus` (glib2) |
| Wayland — KDE | KDE Plasma | `kwin-portal-bridge` (bundled) | `kwin-portal-bridge` (bundled) |
| XWayland | Any Wayland compositor | `xdotool` (fallback) | depends on compositor |

Patches emit `[claude-cu] diagnostics:` lines to **stderr/stdout** at startup showing detected session, available/missing tools, and screenshot cascade order. Visible when running `claude-desktop` from a terminal. Ask users to share this output when debugging.

**Key constraint:** The upstream binary (`Claude-Setup-x64.exe`) is managed remotely by Anthropic and changes without notice. Every minified variable name, function signature, and feature flag can change between releases. This makes the project inherently fragile — patches and documentation must be re-validated on each upstream update.

## Version-Sensitive Artifacts

These files embed assumptions about upstream internals and **must be challenged on every release**:

| File | What's fragile | Update workflow |
|------|---------------|-----------------|
| `patches/*.nim` | Regex patterns matching minified JS | Build fails → fix patterns → `make` → `node --check` |
| `CLAUDE_FEATURE_FLAGS.md` | Function names, GrowthBook IDs, architecture details | Run Feature Flag Audit (Prompt 3 in update-prompt.md) |
| `README.md` | Patch table (break risk, debug `rg` patterns), feature descriptions. **NOT** install command version numbers — those are updated automatically by CI. | Review after patches are fixed |
| `CLAUDE_BUILT_IN_MCP.md` | Built-in MCP server names, registration patterns | Check `registerInternalMcpServer` calls in new JS |
| `ION.md` | ion-dist SPA bundle stats, patched patterns, config key schema | Run ion-dist checks (Prompt 4 in update-prompt.md) |
| `CHANGELOG.md` | Version-specific notes | Add new entry for each release |

**Rule of thumb:** If a doc references a specific minified name, it will be wrong after the next upstream release. Use `\w+` wildcards in patches; in docs, always note the version the names apply to.

## CI-Managed Files (Do NOT Edit Manually)

- **README.md install command version numbers** (`.deb`, `.rpm`, `.AppImage` filenames) — updated automatically by the `release` job in `.github/workflows/build-and-release.yml` via `sed`. Manual edits will cause merge conflicts with the CI commit.

## Update Workflow

When a new Claude Desktop version drops, follow [update-prompt.md](update-prompt.md) — it has copy-paste prompts for:

1. **Prompt 1:** Build & fix patches (download exe, run build, fix failures)
2. **Prompt 2:** Diff & discover new changes (compare old vs new JS bundles)
3. **Prompt 3:** Feature flag audit (catch new/changed flags)

Quick start:
```bash
# Build (auto-cleans build dir, auto-downloads latest exe, applies patches, packages)
./scripts/build-local.sh
```

### Building on Ubuntu / Debian

```bash
# this is how you build it on ubuntu
SKIP_SMOKE_TEST=1 ./scripts/build-ubuntu-local.sh
```

Flags can be combined (e.g. `--no-smoke-test --install`). Setting
`SKIP_SMOKE_TEST=1` in the environment also skips the smoke test when
invoking `scripts/build-patched-tarball.sh` directly.

See also: [validate_and_fix_claude-setup-x64.md](validate_and_fix_claude-setup-x64.md) for step-by-step patch debugging, and [UPDATE-PROMPT-CC-INPUT-MANUAL.md](UPDATE-PROMPT-CC-INPUT-MANUAL.md) for the one-liner to kick off the process.

## Debugging Patch Failures

**IMPORTANT:** Always work against a **freshly extracted** bundle in `./tmp/` (project-local, gitignored). If the `Claude-Setup-x64.exe` or any extracted `index.js` in `./tmp/` is older than today, re-fetch from upstream and re-extract before doing any patch work (review, debugging, writing). Stale extracts have different minified variable names and will lead to wrong conclusions.

```bash
# Re-download + extract in one step (compares local vs upstream version automatically):
./scripts/build-local.sh

# Or manually: download latest, extract to ./tmp/:
mkdir -p tmp
./scripts/build-patched-tarball.sh Claude-Setup-x64.exe ./tmp
# The unpatched index.js is at: ./tmp/app/app.asar.contents/.vite/build/index.js

# ion-dist (3P config SPA) is in the upstream resources, not inside app.asar:
# After build: build/src/app/locales/ion-dist/
# Or extract manually from the nupkg:
#   ls extract/lib/net45/resources/ion-dist/
```

When patches fail after a new Claude Desktop release, follow this workflow:

### 1. Extract and Test Locally

```bash
# Extract the exe (place Claude-Setup-x64.exe in project root first)
mkdir -p tmp
7z x -o./tmp Claude-Setup-x64.exe -y

# Extract the nupkg (version number will vary)
7z x -o./tmp/nupkg ./tmp/AnthropicClaude-*.nupkg -y

# Extract app.asar
asar extract ./tmp/nupkg/lib/net45/resources/app.asar ./tmp/app.asar.contents
```

### 2. Run Validation Script

```bash
./scripts/validate-patches.sh ./tmp/app.asar.contents
```

Test individual patches directly using compiled Nim binaries:

```bash
# Compile first (or use Docker fallback)
cd patches && make -j$(nproc) && cd ..

# Run a single patch on a copy
cp ./tmp/app.asar.contents/.vite/build/index.js ./tmp/test-index.js
patches/fix_quick_entry_position ./tmp/test-index.js
echo "Exit code: $?"
```

### 3. Find New Patterns

When patterns don't match, the minified variable names likely changed. Search for the actual patterns:

```bash
# Find getPrimaryDisplay patterns (for quick_entry patch)
rg -o '.{0,50}getPrimaryDisplay.{0,50}' ./tmp/app.asar.contents/.vite/build/index.js

# Find resourcesPath patterns (for tray_path patch)
rg -o 'function [a-zA-Z]+\(\)\{return [a-zA-Z]+\.app\.isPackaged\?[a-zA-Z]+\.resourcesPath.{0,50}' ./tmp/app.asar.contents/.vite/build/index.js

# Find specific function patterns
rg -o 'function [a-zA-Z]+\(\)\{const t=[a-zA-Z]+\.screen\.getPrimaryDisplay' ./tmp/app.asar.contents/.vite/build/index.js
```

### 4. Common Variable Name Changes

Minified variable names change between versions. Examples from v1.0.1217 → v1.0.1307:

| Variable | Old | New |
|----------|-----|-----|
| Electron module | `ce` | `de` |
| Process module | `pn` | `gn` |
| Position function | `pTe` | `lPe` |

### 5. Fix Strategy: Use Flexible Patterns

Instead of hardcoding variable names, use `[\w$]+` wildcards with replacement functions:

```nim
# BAD - hardcoded variable names (breaks on updates)
let pattern = re2"function pTe\(\)\{const t=ce\.screen\.getPrimaryDisplay\(\)"

# GOOD - flexible pattern with capture groups
let pattern = re2"(function [\w$]+\(\)\{const t=)([\w$]+)(\.screen\.)getPrimaryDisplay\(\)"

result = content.replace(pattern, proc(m: RegexMatch2, s: string): string =
  let electronVar = s[m.group(1)]
  s[m.group(0)] & electronVar & s[m.group(2)] &
    "getDisplayNearestPoint(" & electronVar & ".screen.getCursorScreenPoint())"
)
```

**Important:** Always use `[\w$]+` (not bare `\w+`) for matching JS identifiers. Minified variable names can contain `$` (e.g., `F$e`, `$S`). Using bare `\w+` will silently fail to match.

### 5b. Patch Strictness Rules

**Every sub-patch MUST succeed or the whole patch script MUST fail (exit 1).** This is critical because:

- A failed sub-patch means the upstream code changed — the pattern no longer matches
- Silent failures hide regressions that only surface as broken features at runtime
- The correct response to a failed match is *investigation*, not silent acceptance

**Required pattern for multi-patch Nim scripts:**

```nim
const EXPECTED_PATCHES = 5  # A, B, C, D, E
var patchesApplied = 0

# ... each successful sub-patch increments patchesApplied ...

if patchesApplied < EXPECTED_PATCHES:
  echo &"  [FAIL] Only {patchesApplied}/{EXPECTED_PATCHES} patches applied"
  quit(1)
```

**Rules:**
1. Count expected patches and require ALL to succeed (or be detected as "already applied")
2. Never use `[WARN]` + continue for a patch that doesn't match — use `[FAIL]` and don't increment the counter
3. "Already patched" detection (idempotency) counts as success — increment the counter
4. When a patch fails after an upstream update, investigate why:
   - **Pattern changed:** The minified variable names shifted — update the regex
   - **Code refactored:** The target code was restructured — rewrite the patch approach
   - **Feature removed:** The code we patched no longer exists — the patch can be removed
   - **Feature upstreamed:** Anthropic added native Linux support — the patch can be removed
5. Never add a new patch with `[WARN]`-on-failure or `patchesApplied == 0` as the only check

### 6. Verify Syntax After Patching

Always check JavaScript syntax after applying patches:

```bash
node --check ./tmp/app.asar.contents/.vite/build/index.js
echo "Syntax check exit: $?"
```

If syntax errors occur, the patch likely replaced only part of a construct (e.g., part of a function), leaving dangling code.

### 7. Build and Test Locally

```bash
./scripts/build-local.sh
```

Or build without installing:

```bash
./scripts/build-local.sh
sudo pacman -U build/claude-desktop-bin-*.pkg.tar.zst
```

### 8. Commit Convention

```bash
git add patches/*.nim js/*.js CHANGELOG.md
git commit -m "$(cat <<'EOF'
Fix patch patterns for Claude Desktop vX.X.XXXX

Update [patch_name].nim to use flexible regex patterns with dynamic
variable capture instead of hardcoded names.

Changes:
- Use \w+ wildcards for minified variable names
- Use replacement functions to capture and reuse actual variable names
- [Any other specific changes]

Tested variable name changes: [list changes like ce→de, pn→gn]
EOF
)"
git push
```

## File Structure

```
patches/     # Nim patch sources (.nim) + Makefile, compiled to native binaries (ls patches/*.nim)
js/          # Shared JS snippets embedded by Nim patches via staticRead
scripts/     # Build, validation, and launcher scripts (ls scripts/)
docs/        # Screenshots (chat, code, cowork, global UI)
```

Each patch has a `# @patch-target:` and `# @patch-type: nim` header. The Makefile compiles them to native binaries. The orchestrator (`scripts/apply_patches.py`) runs the binaries. Use `ls patches/*.nim` as the single source of truth for what exists.

## Profile System (multi-instance)

Multiple Desktop instances can run side by side via named profiles. The launcher (`scripts/claude-desktop-launcher.sh`) resolves `CLAUDE_PROFILE` from `--profile=NAME`, the env var, or its own basename (`claude-desktop-NAME`), then exports it so child processes inherit it.

**Per-profile path table** (default profile = unset = no suffix; named profile suffixes everything with `-<name>`):

| Resource | Mechanism | Where to look in code |
|----------|-----------|----------------------|
| Electron userData | `--user-data-dir` flag in launcher | All `app.getPath("userData")` consumers auto-redirect |
| Claude Code config | `CLAUDE_CONFIG_DIR` env exported by launcher | Honored by `@anthropic-ai/claude-code` CLI |
| Quick Entry socket | `process.env.CLAUDE_PROFILE` read in JS | `patches/fix_quick_entry_cli_toggle.nim` |
| systemd scope | `${profile_suffix}` in launcher | `claude-desktop-launcher.sh` |
| WM_CLASS / Wayland app_id | per-profile Electron binary (hardlink → reflink → copy fallback) | `~/.local/lib/claude-desktop/<APP_ID>-<name>` — must be a real file, not a symlink, because Electron derives its app identity from `/proc/self/exe` (the kernel resolves symlinks before reading) |
| SSO callback routing | marker file written by JS hook on `shell.openExternal`; launcher reads marker to dispatch incoming `claude://` URL | `patches/fix_profile_url_routing.nim` (writer) + `claude-desktop-launcher.sh` URL-handler block (reader / re-exec) |

**Rule when adding a new patch:** if it writes to a fixed user-level path, prefer `app.getPath("userData")` (auto-isolates) over `os.homedir()+"/.config/Claude"` (single-instance leak). If it opens a Unix socket or pipe that is owned by the Electron process itself, append `process.env.CLAUDE_PROFILE` to the path the same way `fix_quick_entry_cli_toggle.nim` does. If the socket is owned by a separate user-level daemon (like cowork-svc), do NOT suffix it — clients across all profiles need to connect to the same listener; profile isolation comes from per-profile state inherited via env. If the patch spawns a long-lived child process that holds state, propagate `process.env.CLAUDE_PROFILE` and `process.env.CLAUDE_CONFIG_DIR` (or accept that `child_process.spawn` inherits `process.env` by default — verify, don't assume).

## Feature Flag System

See [CLAUDE_FEATURE_FLAGS.md](CLAUDE_FEATURE_FLAGS.md) for the full reference: feature flag catalog, 3-layer override architecture (static registry → async merger → IPC), GrowthBook flag IDs, and how `enable_local_agent_mode.nim` bypasses the production gate.

**Note:** Function names in CLAUDE_FEATURE_FLAGS.md are version-specific (they change every release). The version history table at the bottom tracks the renames across versions.

## Log Files

Runtime logs are at `~/.config/Claude/logs/`:

| Log File | Description |
|----------|-------------|
| `main.log` | Main Electron process log (~6MB) |
| `claude.ai-web.log` | BrowserView web content log (~1.6MB) |
| `cowork_vm_node.log` | Cowork VM/session log (~638KB) |
| `mcp.log` | MCP server communication log (~3.5MB) |
| `mcp-server-*.log` | Per-MCP-server logs (e.g., ClickUp) |

```bash
# Tail main process log
tail -f ~/.config/Claude/logs/main.log

# Search for errors across all logs
rg -i 'error|exception|fatal' ~/.config/Claude/logs/

# Check crash reports
ls -la ~/.config/Claude/crash*
```

### Dispatch Debug Workflow

When dispatch responses don't render or features fail, use this sequence:

```bash
# 1. Check bridge event flow (did the message pass through?)
grep -a 'DISPATCH-FWD.*PASSING\|DISPATCH-TRANSFORM\|DISPATCH-WRITE' ~/.config/Claude/logs/main.log | tail -20

# 2. Check for permission denials on MCP tools
grep -a 'Permission.*denied' ~/.config/Claude/logs/main.log | tail -10

# 3. Check the audit log for the dispatch session (shows model's tool calls and results)
AUDIT=$(find ~/.config/Claude/local-agent-mode-sessions -name "audit.jsonl" -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2)
python3 -c "
import json
with open('$AUDIT') as f:
    for i, line in enumerate(f):
        d = json.loads(line)
        t = d.get('type','?')
        if t == 'assistant' and d.get('message'):
            content = d['message'].get('content', [])
            names = [c.get('name','') for c in content if c.get('type') == 'tool_use']
            texts = [c.get('text','')[:80] for c in content if c.get('type') == 'text']
            print(f'[{i}] {t} tools={names} text={texts}')
        elif t == 'user' and ('Error' in str(d) or 'Permission' in str(d)):
            print(f'[{i}] {t} (error): {str(d)[:200]}')
"

# 4. Check cowork-service spawn args (did --tools, --disallowedTools, env pass correctly?)
#    Run cowork-service in debug mode:
kill $(pgrep cowork-svc); rm -f /run/user/1000/cowork-vm-service.sock
nohup /path/to/cowork-svc-linux -debug > /tmp/cowork-debug.log 2>&1 &
#    Then trigger a dispatch session and check:
grep 'DISPATCH-DEBUG\|disallowedTools\|--tools\|CLAUDE_CODE_BRIEF' /tmp/cowork-debug.log

# 5. Check what tools the CLI actually exposed to the model
python3 -c "
import json
with open('$AUDIT') as f:
    for i, line in enumerate(f):
        d = json.loads(line)
        if d.get('tools') and len(d['tools']) > 10:
            names = [t if isinstance(t, str) else t.get('name','?') for t in d['tools']]
            print(f'Tools ({len(names)}): {names}')
            for target in ['SendUserMessage','present_files','send_message']:
                found = [n for n in names if target in n]
                print(f'  {target}: {found or \"MISSING\"}')
            break
"

# 6. Clear stale dispatch session (model remembers past errors)
rm -rf ~/.config/Claude/local-agent-mode-sessions/
```

**Key insight:** The audit.jsonl is the single source of truth for what the model sees and does. The main.log shows how the bridge processes the model's output. Check both when debugging.

## CI Pipeline

GitHub Actions workflow:
1. Downloads latest Claude Desktop exe
2. Runs patch validation in Docker
3. If validation passes, pushes to AUR

When CI fails, download the exe locally and debug using the workflow above.


# Ubuntu VM
vboxmanage startvm "Ubuntu"
# Credentials: osboxes / osboxes.org
# SSH (port 2222) is unreliable — use guest control instead:
# Copy file to VM:  vboxmanage guestcontrol "Ubuntu" copyto --target-directory /home/osboxes/ <file> --username osboxes --password "osboxes.org"
# Run command in VM: vboxmanage guestcontrol "Ubuntu" run --exe /bin/bash --username osboxes --password "osboxes.org" -- bash -c "<cmd>"

# Fedora 43 KDE VM (RPM testing)
vboxmanage startvm "Fedora43-KDE"
# SSH: ssh -p 2223 localhost
# Shared folder: /tmp/fedora-test → auto-mounted in guest
# Install RPM: sudo dnf install /media/sf_shared/claude-desktop-bin-*.x86_64.rpm
