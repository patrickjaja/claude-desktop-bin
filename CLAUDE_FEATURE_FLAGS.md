# Claude Desktop Feature Flag Architecture

Reference documentation for the feature flag system in Claude Desktop's Electron app. This documents v1.1.3770 internals to aid patch maintenance.

## Overview

13 feature flags are controlled by a 3-layer system:

1. **`Oh()` (static)** - Calls individual feature functions, builds base object (11 features)
2. **`mC()` (async merger)** - Spreads `Oh()` (includes `ccdPlugins` via `...Kf()`), adds `chillingSlothEnterprise`, overrides `yukonSilver`/`yukonSilverGems`/`louderPenguin` with async versions
3. **IPC handler** - Calls `mC()`, validates against schema, sends to renderer

Feature name strings (`chillingSlothFeat`, `louderPenguin`, etc.) are runtime IPC identifiers, **not minified** - they are stable pattern anchors.

## All 13 Features

| # | Feature | Function | Gate | Purpose |
|---|---------|----------|------|---------|
| 1 | `nativeQuickEntry` | `uot()` | `platform !== "darwin"` | Native Quick Entry (macOS only) |
| 2 | `quickEntryDictation` | `fot()` | `platform !== "darwin"` | Quick Entry dictation |
| 3 | `customQuickEntryDictationShortcut` | direct value `Gle` | None | Custom dictation shortcut value |
| 4 | `plushRaccoon` | `QL(() => Gle)` | **QL() production gate** | Custom dictation shortcut (dev-gated) |
| 5 | `quietPenguin` | `QL(mot)` | **QL()** + darwin check in `mot()` | Code-related feature (dev-gated) |
| 6 | `louderPenguin` | `QL(yot)` in Oh() / `await hbt()` in mC() | **QL()** in Oh(); **async override** in mC() (no longer purely QL-gated) | **Code tab** |
| 7 | `chillingSlothFeat` | `pot()` | `platform !== "darwin"` | Local Agent Mode |
| 8 | `chillingSlothLocal` | `hot()` | `win32 && arm64` excluded | Local sessions |
| 9 | `yukonSilver` | `Y5()` static / `BEe()` async | `platform !== "darwin"` | Secure VM |
| 10 | `yukonSilverGems` | `_ot()` static / `bot()` async | Depends on `yukonSilver` | VM extensions |
| 11 | `desktopTopBar` | `vot()` | **None** (always supported) | Desktop top bar |
| 12 | `chillingSlothEnterprise` | `dot()` async only | Org config check | Enterprise disable for Claude Code |
| 13 | `ccdPlugins` | `w6` (constant via `Kf()`) | **None** (always supported) | CCD Plugins UI (Add plugins, Browse plugins) |

## The QL() Production Gate

```javascript
function QL(t){return Ae.app.isPackaged?{status:"unavailable"}:t()}
```

In production builds (`app.isPackaged === true`), QL() returns `{status:"unavailable"}` **without calling** the wrapped function. Only in development builds does it call `t()`.

**Features gated by QL():** `plushRaccoon`, `quietPenguin`

Note: `louderPenguin` was QL()-gated in earlier versions but as of v1.1.3770, it has its own async override (`await hbt()`) in mC() via `dbt()`, bypassing the QL() gate. The QL-wrapped value in Oh() is still present but overridden by the async merger.

This is why patching the inner functions (`mot()`) alone is insufficient - QL() never calls them in packaged builds.

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
    louderPenguin:QL(yot),         // QL blocks in production (overridden in mC)
    chillingSlothFeat:pot(),
    chillingSlothLocal:hot(),
    yukonSilver:Y5(),
    yukonSilverGems:_ot(),
    desktopTopBar:vot(),
    ...Kf()                        // spreads {ccdPlugins:w6} (always supported)
  }
}
```

Returns 12 features synchronously (11 named + `ccdPlugins` via `...Kf()` spread). `Kf()` returns `{ccdPlugins:w6}` where `w6` is a constant `{status:"supported"}`. Features wrapped by `QL()` are always `{status:"unavailable"}` in packaged builds.

### Layer 2: mC() - Async Merger

```javascript
const mC=async()=>({
  ...Oh(),
  chillingSlothEnterprise:await dot(),
  yukonSilver:await BEe(),
  yukonSilverGems:await bot(),
  louderPenguin:await hbt()          // v1.1.3770: new async override (bypasses QL)
})
```

Spreads `Oh()` then adds/overrides:
- `ccdPlugins` comes from `...Oh()` → `...Kf()` spread (always supported, no override needed)
- Adds `chillingSlothEnterprise` (org config check)
- Overrides `yukonSilver` with async backend check
- Overrides `yukonSilverGems` with async version
- Overrides `louderPenguin` with `await hbt()` (new in v1.1.3770 — uses `dbt()` directly, no longer QL-gated)

**Because spread applies earlier properties first, later properties win.** This is how our Linux patch works - we append overrides after the last async property so they take precedence over QL-blocked values from `...Oh()`.

### Org-Level Settings

Feature flags can also be affected by organization-level admin settings:

- **"Skills" toggle** in org admin → controls SkillsPlugin availability. When disabled, SkillsPlugin returns 404, causing the renderer to hide plugin UI buttons (Add plugins, Browse plugins). This is independent of `ccdPlugins` — the feature flag can be `{status:"supported"}` but the UI still won't show if the org disables Skills.
- **`chillingSlothEnterprise`** → org-level disable for Claude Code. When the org config disables it, the Code tab disappears regardless of other feature flags.

### Layer 3: IPC Handler

Calls `mC()`, validates the result against a schema, and sends it to the renderer process via IPC. The renderer uses these flags to conditionally render UI elements (e.g., Chat|Code toggle).

## What We Patch on Linux

### enable_local_agent_mode.py

**Patch 1 - Individual functions:** Remove `process.platform!=="darwin"` gate from `mot()` (quietPenguin inner) only. The `pot()` (chillingSlothFeat/Cowork) function is intentionally left gated because it requires ClaudeVM which is not available on Linux.

**Patch 2 - mC() merger override:** Append to the `mC()` return object:
```javascript
,quietPenguin:{status:"supported"},louderPenguin:{status:"supported"},ccdPlugins:{status:"supported"}
```

This bypasses the QL() gate by overriding at the merger level. The spread order ensures our values win:
```
...Oh()           -> quietPenguin: {status:"unavailable"}  (from QL)
...our overrides  -> quietPenguin: {status:"supported"}    (wins)
```

Note: `chillingSlothFeat` **is** now overridden to `{status:"supported"}` along with `chillingSlothLocal`, `yukonSilver`, `yukonSilverGems`, and `ccdPlugins`. The Cowork tab is fully functional when `claude-cowork-service` daemon is running. Without the daemon, the UI shows connection errors naturally.

### Cowork on Linux (experimental)

As of v1.1.2685, Cowork uses a decoupled architecture with a TypeScript VM client (`vZe`) that communicates with an external service over a socket. This makes Linux support feasible:

- **`fix_cowork_linux.py`** patches the VM client loader to include Linux (not just `win32`)
- The Named Pipe path is replaced with a Unix domain socket on Linux
- **`claude-cowork-service`** (separate Go daemon) provides the QEMU/KVM backend via vsock
- `chillingSlothFeat`, `chillingSlothLocal`, `yukonSilver`, `yukonSilverGems`, and `ccdPlugins` are all overridden to `{status:"supported"}` in the mC() merger

Without the daemon running, Cowork will show connection errors naturally in the UI.

### Features we do NOT enable

| Feature | Reason |
|---------|--------|
| `nativeQuickEntry` | Requires macOS Swift code |
| `quickEntryDictation` | Requires macOS Swift code |
| `plushRaccoon` | Dictation shortcut, macOS-only |

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
