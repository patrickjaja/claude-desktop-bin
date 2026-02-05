# Claude Desktop Feature Flag Architecture

Reference documentation for the feature flag system in Claude Desktop's Electron app. This documents v1.1.1520 internals to aid patch maintenance.

## Overview

12 feature flags are controlled by a 3-layer system:

1. **`Oh()` (static)** - Calls individual feature functions, builds base object (11 features)
2. **`mC()` (async merger)** - Spreads `Oh()`, adds `chillingSlothEnterprise`, overrides `yukonSilver`/`yukonSilverGems` with async versions
3. **IPC handler** - Calls `mC()`, validates against schema, sends to renderer

Feature name strings (`chillingSlothFeat`, `louderPenguin`, etc.) are runtime IPC identifiers, **not minified** - they are stable pattern anchors.

## All 12 Features

| # | Feature | Function | Gate | Purpose |
|---|---------|----------|------|---------|
| 1 | `nativeQuickEntry` | `uot()` | `platform !== "darwin"` | Native Quick Entry (macOS only) |
| 2 | `quickEntryDictation` | `fot()` | `platform !== "darwin"` | Quick Entry dictation |
| 3 | `customQuickEntryDictationShortcut` | direct value `Gle` | None | Custom dictation shortcut value |
| 4 | `plushRaccoon` | `QL(() => Gle)` | **QL() production gate** | Custom dictation shortcut (dev-gated) |
| 5 | `quietPenguin` | `QL(mot)` | **QL()** + darwin check in `mot()` | Code-related feature (dev-gated) |
| 6 | `louderPenguin` | `QL(yot)` | **QL()** + darwin check in `yot()` | **Code tab** (dev-gated) |
| 7 | `chillingSlothFeat` | `pot()` | `platform !== "darwin"` | Local Agent Mode |
| 8 | `chillingSlothLocal` | `hot()` | `win32 && arm64` excluded | Local sessions |
| 9 | `yukonSilver` | `Y5()` static / `BEe()` async | `platform !== "darwin"` | Secure VM |
| 10 | `yukonSilverGems` | `_ot()` static / `bot()` async | Depends on `yukonSilver` | VM extensions |
| 11 | `desktopTopBar` | `vot()` | **None** (always supported) | Desktop top bar |
| 12 | `chillingSlothEnterprise` | `dot()` async only | Org config check | Enterprise disable for Claude Code |

## The QL() Production Gate

```javascript
function QL(t){return Ae.app.isPackaged?{status:"unavailable"}:t()}
```

In production builds (`app.isPackaged === true`), QL() returns `{status:"unavailable"}` **without calling** the wrapped function. Only in development builds does it call `t()`.

**Features gated by QL():** `plushRaccoon`, `quietPenguin`, `louderPenguin`

This is why patching the inner functions (`mot()`, `yot()`) alone is insufficient - QL() never calls them in packaged builds.

## The Three Layers

### Layer 1: Oh() - Static Registry

```javascript
function Oh(){
  return{
    nativeQuickEntry:uot(),
    quickEntryDictation:fot(),
    customQuickEntryDictationShortcut:Gle,
    plushRaccoon:QL(()=>Gle),
    quietPenguin:QL(mot),          // QL blocks in production
    louderPenguin:QL(yot),         // QL blocks in production
    chillingSlothFeat:pot(),
    chillingSlothLocal:hot(),
    yukonSilver:Y5(),
    yukonSilverGems:_ot(),
    desktopTopBar:vot()
  }
}
```

Returns 11 features synchronously. Features wrapped by `QL()` are always `{status:"unavailable"}` in packaged builds.

### Layer 2: mC() - Async Merger

```javascript
const mC=async()=>({
  ...Oh(),
  chillingSlothEnterprise:await dot(),
  yukonSilver:await BEe(),
  yukonSilverGems:await bot()
})
```

Spreads `Oh()` then adds/overrides:
- Adds `chillingSlothEnterprise` (12th feature, org config)
- Overrides `yukonSilver` with async backend check
- Overrides `yukonSilverGems` with async version

**Because spread applies earlier properties first, later properties win.** This is how our Linux patch works - we append overrides after `yukonSilverGems` so they take precedence over QL-blocked values from `...Oh()`.

### Layer 3: IPC Handler

Calls `mC()`, validates the result against a schema, and sends it to the renderer process via IPC. The renderer uses these flags to conditionally render UI elements (e.g., Chat|Code toggle).

## What We Patch on Linux

### enable_local_agent_mode.py

**Patch 1 - Individual functions:** Remove `process.platform!=="darwin"` gate from `mot()` (quietPenguin inner) only. The `pot()` (chillingSlothFeat/Cowork) function is intentionally left gated because it requires ClaudeVM which is not available on Linux.

**Patch 2 - mC() merger override:** Append to the `mC()` return object:
```javascript
,quietPenguin:{status:"supported"},louderPenguin:{status:"supported"}
```

This bypasses the QL() gate by overriding at the merger level. The spread order ensures our values win:
```
...Oh()           -> quietPenguin: {status:"unavailable"}  (from QL)
...our overrides  -> quietPenguin: {status:"supported"}    (wins)
```

Note: `chillingSlothFeat` is **not** overridden here. It stays gated by its darwin check in `Oh()`, returning `{status:"unavailable"}` on Linux. This prevents the Cowork tab from appearing, since it would hang with infinite loading (the Cowork feature requires ClaudeVM for filesystem/session operations).

### Features we do NOT enable

| Feature | Reason |
|---------|--------|
| `nativeQuickEntry` | Requires macOS Swift code |
| `quickEntryDictation` | Requires macOS Swift code |
| `plushRaccoon` | Dictation shortcut, macOS-only |
| `chillingSlothFeat` | Requires ClaudeVM (Cowork tab would hang with infinite loading) |
| `yukonSilver` / `yukonSilverGems` | Requires `@ant/claude-swift` native module |

## Debugging Feature Flags

### Check if a feature is reaching the renderer

In the renderer DevTools console:
```javascript
// Features are sent via IPC - check what the renderer received
// Look for the feature-flags IPC channel in the Network/IPC tab
```

### Verify mC() patch applied correctly

```bash
# After patching, search for the override string
rg 'quietPenguin:\{status:"supported"\}' /path/to/index.js
```

### Pattern anchor stability

Feature name strings are stable across versions because they're IPC identifiers used by both main and renderer processes. The `yukonSilverGems:await \w+\(\)` pattern uses the feature name as anchor and `\w+` for the minified function name.

### When updating for new versions

1. Check if `mC()` structure changed (new features added, order changed)
2. Check if QL()-wrapped features changed
3. Verify feature name strings haven't been renamed (unlikely - they're IPC contracts)
4. Test with `./scripts/validate-patches.sh`
