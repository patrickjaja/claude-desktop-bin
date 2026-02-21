# Claude Desktop Feature Flag Architecture

Reference documentation for the feature flag system in Claude Desktop's Electron app. This documents v1.1.3918 internals to aid patch maintenance.

## Overview

13 feature flags are controlled by a 3-layer system:

1. **`Fd()` (static)** - Calls individual feature functions, builds base object (12 features)
2. **`mP` (async merger)** - Spreads `Fd()`, adds `louderPenguin` as async override
3. **IPC handler** - Calls `mP`, validates against schema, sends to renderer

Feature name strings (`chillingSlothFeat`, `louderPenguin`, etc.) are runtime IPC identifiers, **not minified** - they are stable pattern anchors.

## All 13 Features

| # | Feature | Function | Gate | Purpose |
|---|---------|----------|------|---------|
| 1 | `nativeQuickEntry` | `vPt()` | `platform !== "darwin"` | Native Quick Entry (macOS only) |
| 2 | `quickEntryDictation` | `_Pt()` | `platform !== "darwin"` | Quick Entry dictation |
| 3 | `customQuickEntryDictationShortcut` | direct value `nU` | None | Custom dictation shortcut value |
| 4 | `plushRaccoon` | `o_e(() => nU)` | **o_e() production gate** | Custom dictation shortcut (dev-gated) |
| 5 | `quietPenguin` | `o_e(xPt)` | **o_e()** + darwin check in `xPt()` | Code-related feature (dev-gated) |
| 6 | `louderPenguin` | `await $Pt()` in mP() only | **async override** in mP(); platform gate (darwin/win32) + server flag | **Code tab** |
| 7 | `chillingSlothFeat` | `wPt()` | `platform !== "darwin"` | Local Agent Mode |
| 8 | `chillingSlothEnterprise` | `bPt()` | Org config check | Enterprise disable for Claude Code |
| 9 | `chillingSlothLocal` | `SPt()` | **None** (always supported) | Local sessions |
| 10 | `yukonSilver` | `YNe()` | Platform/arch gate + org config | Secure VM |
| 11 | `yukonSilverGems` | `kPt()` | Depends on `yukonSilver` | VM extensions |
| 12 | `desktopTopBar` | `CPt()` | **None** (always supported) | Desktop top bar |
| 13 | `ccdPlugins` | `nU` (constant) | **None** (always supported) | CCD Plugins UI (Add plugins, Browse plugins) |

## The o_e() Production Gate

```javascript
function o_e(t){return Ae.app.isPackaged?{status:"unavailable"}:t()}
```

In production builds (`app.isPackaged === true`), o_e() returns `{status:"unavailable"}` **without calling** the wrapped function. Only in development builds does it call `t()`.

**Features gated by o_e():** `plushRaccoon`, `quietPenguin`

Note: `louderPenguin` is no longer in Fd() at all (was QL()-gated in earlier versions). It exists only in mP as `await $Pt()`, which has its own platform gate (darwin/win32 only) + server feature flag check.

This is why patching the inner functions (`xPt()`) alone is insufficient - o_e() never calls them in packaged builds.

## The Three Layers

### Layer 1: Fd() - Static Registry

```javascript
function Fd(){
  return{
    nativeQuickEntry:vPt(),
    quickEntryDictation:_Pt(),
    customQuickEntryDictationShortcut:nU,
    plushRaccoon:o_e(()=>nU),
    quietPenguin:o_e(xPt),          // o_e blocks in production
    chillingSlothFeat:wPt(),
    chillingSlothEnterprise:bPt(),   // moved here from async layer in v1.1.3918
    chillingSlothLocal:SPt(),
    yukonSilver:YNe(),
    yukonSilverGems:kPt(),
    desktopTopBar:CPt(),
    ccdPlugins:nU                    // inlined (was ...Kf() spread in v1.1.3770)
  }
}
```

Returns 12 features synchronously. `nU` is a constant `{status:"supported"}`. Features wrapped by `o_e()` are always `{status:"unavailable"}` in packaged builds.

### Layer 2: mP - Async Merger

```javascript
const mP=async()=>({
  ...Fd(),
  louderPenguin:await $Pt()          // only async override remaining
})
```

Spreads `Fd()` then adds `louderPenguin` as the sole async override. `$Pt()` checks `process.platform!=="darwin"&&process.platform!=="win32"` (returns unavailable on Linux) then checks server feature flag `ms("4116586025")`.

**v1.1.3770 → v1.1.3918 changes:**
- `chillingSlothEnterprise` moved from async-only (mC) to static (Fd)
- `yukonSilver`/`yukonSilverGems` async overrides removed (static values in Fd sufficient)
- `louderPenguin` removed from Fd entirely (only exists in mP)
- `ccdPlugins` inlined as `nU` (was `...Kf()` spread)

**Because spread applies earlier properties first, later properties win.** This is how our Linux patch works - we append overrides after the last async property so they take precedence over o_e()-blocked values from `...Fd()`.

### Org-Level Settings

Feature flags can also be affected by organization-level admin settings:

- **"Skills" toggle** in org admin → controls SkillsPlugin availability. When disabled, SkillsPlugin returns 404, causing the renderer to hide plugin UI buttons (Add plugins, Browse plugins). This is independent of `ccdPlugins` — the feature flag can be `{status:"supported"}` but the UI still won't show if the org disables Skills.
- **`chillingSlothEnterprise`** → org-level disable for Claude Code. When the org config disables it, the Code tab disappears regardless of other feature flags.

### Layer 3: IPC Handler

Calls `mP`, validates the result against a Zod schema (`XHe`), and sends it to the renderer process via IPC. The renderer uses these flags to conditionally render UI elements (e.g., Chat|Code toggle).

## What We Patch on Linux

### enable_local_agent_mode.py

**Patch 1 - Individual functions:** Remove `process.platform!=="darwin"` gate from `xPt()` (quietPenguin inner) and `wPt()` (chillingSlothFeat). Also inject Linux early-return in `YNe()` (yukonSilver) to bypass its platform gate.

**Patch 3 - mP merger override:** Append to the `mP` return object:
```javascript
,quietPenguin:{status:"supported"},louderPenguin:{status:"supported"},chillingSlothFeat:{status:"supported"},chillingSlothLocal:{status:"supported"},yukonSilver:{status:"supported"},yukonSilverGems:{status:"supported"},ccdPlugins:{status:"supported"}
```

This bypasses the o_e() gate by overriding at the merger level. The spread order ensures our values win:
```
...Fd()           -> quietPenguin: {status:"unavailable"}  (from o_e)
...our overrides  -> quietPenguin: {status:"supported"}    (wins)
```

Note: `chillingSlothLocal` and `ccdPlugins` overrides are defensive — both are already `{status:"supported"}` in v1.1.3918, but the overrides protect against future gating.

### Cowork on Linux (experimental)

As of v1.1.2685, Cowork uses a decoupled architecture with a TypeScript VM client (`vZe`) that communicates with an external service over a socket. This makes Linux support feasible:

- **`fix_cowork_linux.py`** patches the VM client loader to include Linux (not just `win32`)
- The Named Pipe path is replaced with a Unix domain socket on Linux
- **`claude-cowork-service`** (separate Go daemon) provides the QEMU/KVM backend via vsock
- `chillingSlothFeat`, `chillingSlothLocal`, `yukonSilver`, `yukonSilverGems`, and `ccdPlugins` are all overridden to `{status:"supported"}` in the mP merger

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

### Verify mP patch applied correctly

```bash
# After patching, search for the override string
rg 'quietPenguin:\{status:"supported"\}' /path/to/index.js
```

### Pattern anchor stability

Feature name strings are stable across versions because they're IPC identifiers used by both main and renderer processes. The `yukonSilverGems:await \w+\(\)` pattern uses the feature name as anchor and `\w+` for the minified function name.

### When updating for new versions

1. Check if `mP` structure changed (new features added, order changed)
2. Check if o_e()-wrapped features changed
3. Verify feature name strings haven't been renamed (unlikely - they're IPC contracts)
4. Test with `./scripts/validate-patches.sh`

## Version History

| Version | Static Registry | Async Merger | Gate Function | Notable Changes |
|---------|----------------|--------------|---------------|-----------------|
| v1.1.3770 | `Oh()` | `mC()` | `QL()` | louderPenguin async override added, ccdPlugins via Kf() spread |
| v1.1.3918 | `Fd()` | `mP` | `o_e()` | chillingSlothEnterprise moved to static, mP simplified to louderPenguin only, ccdPlugins inlined, chillingSlothLocal unconditional |
