# Claude Desktop Feature Flag Architecture

Reference documentation for the feature flag system in Claude Desktop's Electron app. This documents v1.1.7464 internals to aid patch maintenance.

## Overview

14 feature flags are controlled by a 3-layer system:

1. **`rp()` (static)** - Calls individual feature functions, builds base object (12 features)
2. **`zM` (async merger)** - Spreads `rp()`, adds `louderPenguin` as async override
3. **IPC handler** - Calls `zM`, validates against schema, sends to renderer

Feature name strings (`chillingSlothFeat`, `louderPenguin`, etc.) are runtime IPC identifiers, **not minified** - they are stable pattern anchors.

## All 13 Features

| # | Feature | Function | Gate | Purpose |
|---|---------|----------|------|---------|
| 1 | `nativeQuickEntry` | `A5t()` | `platform !== "darwin"` | Native Quick Entry (macOS only) |
| 2 | `quickEntryDictation` | `C5t()` | `platform !== "darwin"` | Quick Entry dictation |
| 3 | `customQuickEntryDictationShortcut` | direct value `oq` | None | Custom dictation shortcut value |
| 4 | `plushRaccoon` | `$Se(() => oq)` | **$Se() production gate** | Custom dictation shortcut (dev-gated) |
| 5 | `quietPenguin` | `$Se(N5t)` | **$Se()** + darwin check in `N5t()` | Code-related feature (dev-gated) |
| 6 | `louderPenguin` | `await U5t()` in zM only | **async override** in zM; platform gate (darwin/win32) + server flag | **Code tab** |
| 7 | `chillingSlothFeat` | `T5t()` | `platform !== "darwin"` | Local Agent Mode |
| 8 | `chillingSlothEnterprise` | `$5t()` | Org config check | Enterprise disable for Claude Code |
| 9 | `chillingSlothLocal` | `I5t()` | **None** (always supported) | Local sessions |
| 10 | `yukonSilver` | `_Fe()` | Platform/arch gate + org config | Secure VM |
| 11 | `yukonSilverGems` | `j5t()` | Depends on `yukonSilver` | VM extensions |
| 12 | `desktopTopBar` | `L5t()` | **None** (always supported) | Desktop top bar |
| 13 | `ccdPlugins` | `oq` (constant) | **None** (always supported) | CCD Plugins UI (Add plugins, Browse plugins) |
| 14 | `floatingAtoll` | `F5t()` | **Always unavailable** | Floating mini-window (disabled for all platforms) |

## The $Se() Production Gate

```javascript
function $Se(t){return Ee.app.isPackaged?{status:"unavailable"}:t()}
```

In production builds (`app.isPackaged === true`), $Se() returns `{status:"unavailable"}` **without calling** the wrapped function. Only in development builds does it call `t()`.

**Features gated by $Se():** `plushRaccoon`, `quietPenguin`

Note: `louderPenguin` is no longer in rp() at all (was QL()-gated in earlier versions). It exists only in zM as `await U5t()`, which has its own platform gate (darwin/win32 only) + server feature flag check.

This is why patching the inner functions alone is insufficient - $Se() never calls them in packaged builds.

## The Three Layers

### Layer 1: rp() - Static Registry

```javascript
function rp(){
  return{
    nativeQuickEntry:A5t(),
    quickEntryDictation:C5t(),
    customQuickEntryDictationShortcut:oq,
    plushRaccoon:$Se(()=>oq),
    quietPenguin:$Se(N5t),           // $Se blocks in production
    chillingSlothFeat:T5t(),
    chillingSlothEnterprise:$5t(),
    chillingSlothLocal:I5t(),
    yukonSilver:_Fe(),
    yukonSilverGems:j5t(),
    desktopTopBar:L5t(),
    ccdPlugins:oq,                   // constant {status:"supported"}
    floatingAtoll:F5t()              // always {status:"unavailable"}
  }
}
```

Returns 13 features synchronously. `oq` is a constant `{status:"supported"}`. Features wrapped by `$Se()` are always `{status:"unavailable"}` in packaged builds.

### Layer 2: zM - Async Merger

```javascript
const zM=async()=>({
  ...rp(),
  louderPenguin:await U5t()          // only async override remaining
})
```

Spreads `rp()` then adds `louderPenguin` as the sole async override. `U5t()` checks `process.platform!=="darwin"&&process.platform!=="win32"` (returns unavailable on Linux) then checks server feature flag.

**v1.1.3770 → v1.1.3918 changes:**
- `chillingSlothEnterprise` moved from async-only (mC) to static (Fd)
- `yukonSilver`/`yukonSilverGems` async overrides removed (static values in Fd sufficient)
- `louderPenguin` removed from Fd entirely (only exists in mP)
- `ccdPlugins` inlined as `nU` (was `...Kf()` spread)

**v1.1.4173 → v1.1.4328 changes:**
- No structural changes; all 13 features identical
- `formatMessage` calls now include `id` field (i18n improvement)
- Function renames only: Fd→nh, mP→rO, o_e→Ebe

**v1.1.6041 → v1.1.7053 changes:**
- **New feature: `floatingAtoll`** added to static registry (always `{status:"unavailable"}` — disabled for all platforms)
- Function renames: nh→Kh, rO→$M, Ebe→Qwe, J5→K9
- Gate function renames: CMt→BBt, $Mt→UBt, MMt→KBt, TMt→qBt, kMt→jBt, IMt→zBt, NDe→BFe, BMt→e3t, LMt→JBt, FMt→QBt
- No structural changes to the 3-layer architecture

**Because spread applies earlier properties first, later properties win.** This is how our Linux patch works - we append overrides after the last async property so they take precedence over $Se()-blocked values from `...rp()`.

**v1.1.7053 → v1.1.7464 changes:**
- No structural changes to feature flag architecture — same 14 features, same 3-layer system
- Function renames: Kh→rp, $M→zM, Qwe→$Se, K9→oq
- Gate function renames: BBt→A5t, UBt→C5t, KBt→N5t, qBt→T5t, jBt→$5t, zBt→I5t, BFe→_Fe, e3t→j5t, JBt→L5t, QBt→U5t, YBt→F5t
- New Dispatch infrastructure: sessions-bridge, environments API, remote session control (separate from feature flags — gated by GrowthBook flags `3572572142` and `2216414644`)
- New upstream features: SSH remote CCD, Scheduled Tasks, Teleport to Cloud, Git/PR integration, DXT extensions

### Org-Level Settings

Feature flags can also be affected by organization-level admin settings:

- **"Skills" toggle** in org admin → controls SkillsPlugin availability. When disabled, SkillsPlugin returns 404, causing the renderer to hide plugin UI buttons (Add plugins, Browse plugins). This is independent of `ccdPlugins` — the feature flag can be `{status:"supported"}` but the UI still won't show if the org disables Skills.
- **`chillingSlothEnterprise`** → org-level disable for Claude Code. When the org config disables it, the Code tab disappears regardless of other feature flags.

### Layer 3: IPC Handler

Calls `zM`, validates the result against a Zod schema, and sends it to the renderer process via IPC. The renderer uses these flags to conditionally render UI elements (e.g., Chat|Code toggle).

## What We Patch on Linux

### enable_local_agent_mode.py

**Patch 1 - Individual functions:** Remove `process.platform!=="darwin"` gate from `N5t()` (quietPenguin inner) and `T5t()` (chillingSlothFeat). Also inject Linux early-return in `_Fe()` (yukonSilver) to bypass its platform gate.

**Patch 3 - zM merger override:** Append to the `zM` return object:
```javascript
,quietPenguin:{status:"supported"},louderPenguin:{status:"supported"},chillingSlothFeat:{status:"supported"},chillingSlothLocal:{status:"supported"},yukonSilver:{status:"supported"},yukonSilverGems:{status:"supported"},ccdPlugins:{status:"supported"}
```

This bypasses the $Se() gate by overriding at the merger level. The spread order ensures our values win:
```
...rp()           -> quietPenguin: {status:"unavailable"}  (from $Se)
...our overrides  -> quietPenguin: {status:"supported"}    (wins)
```

Note: `chillingSlothLocal` and `ccdPlugins` overrides are defensive — both are already `{status:"supported"}` in v1.1.7464, but the overrides protect against future gating.

### Cowork on Linux (experimental)

As of v1.1.2685, Cowork uses a decoupled architecture with a TypeScript VM client (`vZe`) that communicates with an external service over a socket. This makes Linux support feasible:

- **`fix_cowork_linux.py`** patches the VM client loader to include Linux (not just `win32`)
- The Named Pipe path is replaced with a Unix domain socket on Linux
- **`claude-cowork-service`** (separate Go daemon) provides the QEMU/KVM backend via vsock
- `chillingSlothFeat`, `chillingSlothLocal`, `yukonSilver`, `yukonSilverGems`, and `ccdPlugins` are all overridden to `{status:"supported"}` in the rO merger

Without the daemon running, Cowork will show connection errors naturally in the UI.

### Dispatch on Linux (fix_dispatch_linux.py)

Dispatch is a remote task orchestration feature that lets you send tasks from your phone to your desktop. It's built on top of the Cowork sessions infrastructure and uses Anthropic's "environments bridge" API.

**Architecture:** Desktop registers with `POST /v1/environments/bridge`, then long-polls `GET /v1/environments/{id}/work/poll` for incoming work from the mobile client. All traffic routes through Anthropic's servers over TLS — no inbound ports needed.

**What we patch:**
1. **Sessions-bridge init gate** (GrowthBook flag `3572572142`) — The bridge only initializes when this server-side flag fires with `on=true`. On Linux it never fires. We force the gate variable to `!0` (true).
2. **Remote session control** (GrowthBook flag `2216414644`) — Messages with `channel:"mobile"` throw unless this flag is on. We replace `!Jr("2216414644")` with `!1` at both call sites.
3. **Platform label** (`HI()`) — Returns "Unsupported Platform" for Linux. We add `case"linux":return"Linux"`.
4. **Telemetry gate** (`Xqe`) — `Hr||Pn` (darwin||win32) silently drops telemetry on Linux. We extend to include Linux.

**No patching needed for:**
- Keep-awake (`powerSaveBlocker`) — works on Linux via Electron API
- Bridge state persistence — uses `userData` path, works on Linux
- CCR transport — pure HTTP/SSE, platform-agnostic
- OAuth configs — same endpoints for all platforms

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

1. Check if `rO` structure changed (new features added, order changed)
2. Check if Ebe()-wrapped features changed
3. Verify feature name strings haven't been renamed (unlikely - they're IPC contracts)
4. Test with `./scripts/validate-patches.sh`

## Version History

| Version | Static Registry | Async Merger | Gate Function | Notable Changes |
|---------|----------------|--------------|---------------|-----------------|
| v1.1.3770 | `Oh()` | `mC()` | `QL()` | louderPenguin async override added, ccdPlugins via Kf() spread |
| v1.1.3918 | `Fd()` | `mP` | `o_e()` | chillingSlothEnterprise moved to static, mP simplified to louderPenguin only, ccdPlugins inlined, chillingSlothLocal unconditional |
| v1.1.4328 | `nh()` | `rO` | `Ebe()` | No structural changes; formatMessage calls now include `id` field; function renames only |
| v1.1.7053 | `Kh()` | `$M` | `Qwe()` | New `floatingAtoll` feature (always unavailable); function renames only; 14 features total |
| v1.1.7464 | `rp()` | `zM` | `$Se()` | No structural changes; Dispatch infrastructure added (separate GrowthBook gates); function renames only |
