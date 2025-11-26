# CLAUDE.md - Project Guidelines

## Project Overview

This is an AUR package that repackages Claude Desktop (Windows) for Arch Linux. It applies JavaScript patches to make the Electron app work on Linux.

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
git push github master
```

## File Structure

```
patches/
  claude-native.js          # Linux-compatible native module (replaces Windows binary)
  fix_claude_code.py        # Claude Code CLI integration
  fix_locale_paths.py       # Locale file path fixes
  fix_native_frame.py       # Native window frame handling
  fix_quick_entry_position.py  # Multi-monitor Quick Entry positioning
  fix_title_bar.py          # Title bar detection fix
  fix_tray_dbus.py          # Tray menu DBus race condition fix
  fix_tray_path.py          # Tray icon path redirection

scripts/
  build-local.sh            # Local build and install
  extract-version.sh        # Extract version from exe
  generate-pkgbuild.sh      # Generate PKGBUILD from template
  validate-patches.sh       # Validate patches against extracted app
```

## CI Pipeline

GitHub Actions workflow:
1. Downloads latest Claude Desktop exe
2. Runs patch validation in Docker
3. If validation passes, pushes to AUR

When CI fails, download the exe locally and debug using the workflow above.
