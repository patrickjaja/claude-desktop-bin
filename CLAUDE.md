# CLAUDE.md - Project Guidelines

## Project Overview

This is an AUR package that repackages Claude Desktop (Windows) for Arch Linux. It applies JavaScript patches to make the Electron app work on Linux.

**Key constraint:** The upstream binary (`Claude-Setup-x64.exe`) is managed remotely by Anthropic and changes without notice. Every minified variable name, function signature, and feature flag can change between releases. This makes the project inherently fragile — patches and documentation must be re-validated on each upstream update.

## Version-Sensitive Artifacts

These files embed assumptions about upstream internals and **must be challenged on every release**:

| File | What's fragile | Update workflow |
|------|---------------|-----------------|
| `patches/*.py` | Regex patterns matching minified JS | Build fails → fix patterns → `node --check` |
| `CLAUDE_FEATURE_FLAGS.md` | Function names, GrowthBook IDs, architecture details | Run Feature Flag Audit (Prompt 3 in update-prompt.md) |
| `README.md` | Patch table (break risk, debug `rg` patterns), feature descriptions | Review after patches are fixed |
| `CLAUDE_BUILT_IN_MCP.md` | Built-in MCP server names, registration patterns | Check `registerInternalMcpServer` calls in new JS |
| `CHANGELOG.md` | Version-specific notes | Add new entry for each release |

**Rule of thumb:** If a doc references a specific minified name, it will be wrong after the next upstream release. Use `\w+` wildcards in patches; in docs, always note the version the names apply to.

## Update Workflow

When a new Claude Desktop version drops, follow [update-prompt.md](update-prompt.md) — it has copy-paste prompts for:

1. **Prompt 1:** Build & fix patches (download exe, run build, fix failures)
2. **Prompt 2:** Diff & discover new changes (compare old vs new JS bundles)
3. **Prompt 3:** Feature flag audit (catch new/changed flags)

Quick start:
```bash
# Build (auto-cleans build dir, auto-downloads latest exe, applies patches, packages)
./scripts/build-local.sh --install
```

See also: [validate_and_fix_claude-setup-x64.md](validate_and_fix_claude-setup-x64.md) for step-by-step patch debugging, and [UPDATE-PROMT-CC-INPUT-MANUAL.md](UPDATE-PROMT-CC-INPUT-MANUAL.md) for the one-liner to kick off the process.

## Debugging Patch Failures

When patches fail after a new Claude Desktop release, follow this workflow:

### 1. Extract and Test Locally

```bash
# Extract the exe (place Claude-Setup-x64.exe in project root first)
mkdir -p /tmp/claude-patch-test
7z x -o/tmp/claude-patch-test Claude-Setup-x64.exe -y

# Extract the nupkg (version number will vary)
7z x -o/tmp/claude-patch-test/nupkg /tmp/claude-patch-test/AnthropicClaude-*.nupkg -y

# Extract app.asar
asar extract /tmp/claude-patch-test/nupkg/lib/net45/resources/app.asar /tmp/claude-patch-test/app.asar.contents
```

### 2. Run Validation Script

```bash
./scripts/validate-patches.sh /tmp/claude-patch-test/app.asar.contents
```

**Note:** The validation script has a bug - it checks `sed`'s exit code instead of `python3`'s due to piping. Test patches directly:

```bash
python3 patches/fix_quick_entry_position.py /tmp/claude-patch-test/app.asar.contents/.vite/build/index.js
echo "Exit code: $?"
```

### 3. Find New Patterns

When patterns don't match, the minified variable names likely changed. Search for the actual patterns:

```bash
# Find getPrimaryDisplay patterns (for quick_entry patch)
rg -o '.{0,50}getPrimaryDisplay.{0,50}' /tmp/claude-patch-test/app.asar.contents/.vite/build/index.js

# Find resourcesPath patterns (for tray_path patch)
rg -o 'function [a-zA-Z]+\(\)\{return [a-zA-Z]+\.app\.isPackaged\?[a-zA-Z]+\.resourcesPath.{0,50}' /tmp/claude-patch-test/app.asar.contents/.vite/build/index.js

# Find specific function patterns
rg -o 'function [a-zA-Z]+\(\)\{const t=[a-zA-Z]+\.screen\.getPrimaryDisplay' /tmp/claude-patch-test/app.asar.contents/.vite/build/index.js
```

### 4. Common Variable Name Changes

Minified variable names change between versions. Examples from v1.0.1217 → v1.0.1307:

| Variable | Old | New |
|----------|-----|-----|
| Electron module | `ce` | `de` |
| Process module | `pn` | `gn` |
| Position function | `pTe` | `lPe` |

### 5. Fix Strategy: Use Flexible Patterns

Instead of hardcoding variable names, use `\w+` wildcards with replacement functions:

```python
# BAD - hardcoded variable names (breaks on updates)
pattern = rb'function pTe\(\)\{const t=ce\.screen\.getPrimaryDisplay\(\)'

# GOOD - flexible pattern with capture groups
pattern = rb'(function \w+\(\)\{const t=)(\w+)(\.screen\.)getPrimaryDisplay\(\)'

def replacement_func(m):
    electron_var = m.group(2).decode('utf-8')
    return (m.group(1) + m.group(2) + m.group(3) +
            f'getDisplayNearestPoint({electron_var}.screen.getCursorScreenPoint())'.encode('utf-8'))

content, count = re.subn(pattern, replacement_func, content)
```

### 6. Verify Syntax After Patching

Always check JavaScript syntax after applying patches:

```bash
node --check /tmp/claude-patch-test/app.asar.contents/.vite/build/index.js
echo "Syntax check exit: $?"
```

If syntax errors occur, the patch likely replaced only part of a construct (e.g., part of a function), leaving dangling code.

### 7. Build and Test Locally

```bash
./scripts/build-local.sh --install
```

Or build without installing:

```bash
./scripts/build-local.sh
sudo pacman -U build/claude-desktop-bin-*.pkg.tar.zst
```

### 8. Commit Convention

```bash
git add patches/*.py CHANGELOG.md
git commit -m "$(cat <<'EOF'
Fix patch patterns for Claude Desktop vX.X.XXXX

Update [patch_name].py to use flexible regex patterns with dynamic
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
patches/     # Python/JS patches applied to the extracted app (ls patches/)
scripts/     # Build, validation, and launcher scripts (ls scripts/)
docs/        # Screenshots (chat, code, cowork, global UI)
```

Each patch has a header comment describing its target and purpose. The [Patches table in README.md](README.md#patches) lists break risk and debug `rg` patterns — but use `ls patches/` as the single source of truth for what exists.

## Feature Flag System

See [CLAUDE_FEATURE_FLAGS.md](CLAUDE_FEATURE_FLAGS.md) for the full reference: feature flag catalog, 3-layer override architecture (static registry → async merger → IPC), GrowthBook flag IDs, and how `enable_local_agent_mode.py` bypasses the production gate.

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

## CI Pipeline

GitHub Actions workflow:
1. Downloads latest Claude Desktop exe
2. Runs patch validation in Docker
3. If validation passes, pushes to AUR

When CI fails, download the exe locally and debug using the workflow above.


# Ubuntu VM
vboxmanage startvm "Ubuntu"
