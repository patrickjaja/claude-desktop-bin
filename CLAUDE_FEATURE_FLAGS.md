# Claude Desktop Feature Flag Architecture

Reference documentation for the feature flag system in Claude Desktop's Electron app. This documents v1.1.8359 internals to aid patch maintenance.

## Overview

16 feature flags are controlled by a 3-layer system:

1. **`lA()` (static)** - Calls individual feature functions, builds base object (14 features)
2. **`jY` (async merger)** - Spreads `lA()`, adds `louderPenguin` + `operon` as async overrides
3. **IPC handler** - Calls `jY`, validates against schema, sends to renderer

Feature name strings (`chillingSlothFeat`, `louderPenguin`, etc.) are runtime IPC identifiers, **not minified** - they are stable pattern anchors.

## All 16 Features

| # | Feature | Function | Gate | Purpose |
|---|---------|----------|------|---------|
| 1 | `nativeQuickEntry` | `zjr()` | `platform !== "darwin"` | Native Quick Entry (macOS only) |
| 2 | `quickEntryDictation` | `Gjr()` | `platform !== "darwin"` | Quick Entry dictation |
| 3 | `customQuickEntryDictationShortcut` | direct value `xq` | None | Custom dictation shortcut value |
| 4 | `plushRaccoon` | `VKe(() => xq)` | **VKe() production gate** | Custom dictation shortcut (dev-gated) |
| 5 | `quietPenguin` | `VKe(tqr)` | **VKe()** + darwin check in `tqr()` | Code-related feature (dev-gated) |
| 6 | `louderPenguin` | `await aqr()` in jY only | **async override** in jY; platform gate (darwin/win32) + GrowthBook `4116586025` | **Code tab** |
| 7 | `chillingSlothFeat` | `Kjr()` | `platform !== "darwin"` | Local Agent Mode / Cowork |
| 8 | `chillingSlothEnterprise` | `Wjr()` | Org config check | Enterprise disable for Claude Code |
| 9 | `chillingSlothLocal` | `Yjr()` | **None** (always supported) | Local sessions |
| 10 | `yukonSilver` | `U2e()` | Platform/arch gate via `uUt()` + org config | Secure VM |
| 11 | `yukonSilverGems` | `QKe()` | Depends on `yukonSilver` (`U2e()`) | VM extensions |
| 12 | `yukonSilverGemsCache` | `QKe()` | Depends on `yukonSilver` (`U2e()`) | VM extensions cache |
| 13 | `desktopTopBar` | `nqr()` | **None** (always supported) | Desktop top bar |
| 14 | `ccdPlugins` | `xq` (constant) | **None** (always supported) | CCD Plugins UI (Add plugins, Browse plugins) |
| 15 | `floatingAtoll` | `iqr()` | **Always unavailable** | Floating mini-window (macOS window button offset, disabled for all) |
| 16 | **`operon`** | `await I$t()` in jY only | **async override** in jY; blocks win32, checks `U2e()` (yukonSilver) + GrowthBook `1306813456`. Static: `oqr()` returns unavailable (**new in v1.1.8359**) | Nest — 120+ IPC endpoints, 18 sub-interfaces |

## The VKe() Production Gate

```javascript
function VKe(t){return Ee.app.isPackaged?{status:"unavailable"}:t()}
```

In production builds (`app.isPackaged === true`), VKe() returns `{status:"unavailable"}` **without calling** the wrapped function. Only in development builds does it call `t()`.

**Features gated by VKe():** `plushRaccoon`, `quietPenguin`

Note: `louderPenguin` is no longer in lA() at all (was QL()-gated in earlier versions). It exists only in jY as `await aqr()`, which has its own platform gate (darwin/win32 only) + server feature flag check. Similarly, `operon` exists only in jY as `await I$t()`.

This is why patching the inner functions alone is insufficient - VKe() never calls them in packaged builds.

## The Three Layers

### Layer 1: lA() - Static Registry

```javascript
function lA(){
  return{
    nativeQuickEntry:zjr(),
    quickEntryDictation:Gjr(),
    customQuickEntryDictationShortcut:xq,
    plushRaccoon:VKe(()=>xq),
    quietPenguin:VKe(tqr),             // VKe blocks in production
    chillingSlothFeat:Kjr(),
    chillingSlothEnterprise:Wjr(),
    chillingSlothLocal:Yjr(),
    yukonSilver:U2e(),
    yukonSilverGems:QKe(),
    yukonSilverGemsCache:QKe(),
    desktopTopBar:nqr(),
    ccdPlugins:xq,                     // constant {status:"supported"}
    floatingAtoll:iqr()                // always {status:"unavailable"}
  }
}
```

Returns 14 features synchronously. `xq` is a constant `{status:"supported"}`. Features wrapped by `VKe()` are always `{status:"unavailable"}` in packaged builds.

### Layer 2: jY - Async Merger

```javascript
const jY=async()=>({
  ...lA(),
  louderPenguin:await aqr(),           // async override (platform + GrowthBook 4116586025)
  operon:await I$t()                   // NEW in v1.1.8359 — checks yukonSilver + GrowthBook 1306813456
})
```

Spreads `lA()` then adds `louderPenguin` and `operon` as async overrides. `aqr()` checks `process.platform!=="darwin"&&process.platform!=="win32"` (returns unavailable on Linux) then checks server feature flag `4116586025`. `I$t()` blocks win32, checks `U2e()` (yukonSilver), then checks GrowthBook flag `1306813456`.

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

**v1.1.7053 → v1.1.7464 changes:**
- No structural changes to feature flag architecture — same 14 features, same 3-layer system
- Function renames: Kh→rp, $M→zM, Qwe→$Se, K9→oq
- Gate function renames: BBt→A5t, UBt→C5t, KBt→N5t, qBt→T5t, jBt→$5t, zBt→I5t, BFe→_Fe, e3t→j5t, JBt→L5t, QBt→U5t, YBt→F5t
- New Dispatch infrastructure: sessions-bridge, environments API, remote session control (separate from feature flags — gated by GrowthBook flags `3572572142` and `2216414644`)
- New upstream features: SSH remote CCD, Scheduled Tasks, Teleport to Cloud, Git/PR integration, DXT extensions

**v1.1.7464 → v1.1.7714 changes:**
- **New feature: `yukonSilverGemsCache`** added to static registry (mirrors `yukonSilverGems`, depends on `_Be()`)
- Function renames: rp→fp, zM→cN, $Se→r1e, oq→xq
- Gate function renames: A5t→sUt, C5t→aUt, N5t→pUt, T5t→cUt, $5t→oUt, I5t→lUt, _Fe→_Be, j5t→n1e, L5t→gUt, U5t→_Ut, F5t→yUt
- GrowthBook flag function renamed: Jr→Vr (same semantics, `\w+` patterns handle this)
- Logger variable renamed: T→C (fixed in `fix_dispatch_linux.py`)
- New `uUt()` platform gate function called by `_Be()` (yukonSilver)
- `computer-use-server.js` removed from app root (**breaking** for computer-use on Linux)
- `claude-native-binding.node` now bundled inside app.asar (handled by existing shim)
- Two Linux guards removed upstream: `isStartupOnLoginEnabled()` and auto-updater (both gracefully degrade)
- New Quick Entry position-save/restore system (`T7t()`) — patched to always use cursor display

**Because spread applies earlier properties first, later properties win.** This is how our Linux patch works - we append overrides after the last async property so they take precedence over VKe()-blocked values from `...lA()`.

### Org-Level Settings

Feature flags can also be affected by organization-level admin settings:

- **"Skills" toggle** in org admin → controls SkillsPlugin availability. When disabled, SkillsPlugin returns 404, causing the renderer to hide plugin UI buttons (Add plugins, Browse plugins). This is independent of `ccdPlugins` — the feature flag can be `{status:"supported"}` but the UI still won't show if the org disables Skills.
- **`chillingSlothEnterprise`** → org-level disable for Claude Code. When the org config disables it, the Code tab disappears regardless of other feature flags.

### Layer 3: IPC Handler

Calls `jY`, validates the result against a Zod schema, and sends it to the renderer process via IPC. The renderer uses these flags to conditionally render UI elements (e.g., Chat|Code toggle).

## GrowthBook Flag Catalog (v1.1.8359)

### Boolean Flags (Qn())

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `159894531` | ENABLE_TOOL_SEARCH ("auto"/"false") | No |
| `162211072` | Prompt suggestions enable | No |
| `397125142` | Terminal server (ccd + darwin only) | No |
| `714014285` | CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING | No |
| `763725229` | Developer menu label/visibility | No |
| `720735283` | Marketplace migration | No |
| `748063099` | VM client retry on pipe close | No |
| `770567414` | VM service routing (direct vs persistent pipe) | No |
| `1306813456` | Operon/Nest gate | No |
| `1412563253` | askUserQuestion preview format ("html") | No |
| `1640386726` | Query close on idle teardown | No |
| `1942781881` | Prompt suggestions in sessions | No |
| `2051942385` | CIC can-use-tool | No |
| `2067027393` | canLaunchCodeSession | No |
| `2216414644` | Remote session control (Dispatch mobile) | **Yes** — bypassed in `fix_dispatch_linux.py` |
| `2246535838` | Local MCP server prefix (`local:`) | No |
| `2339084909` | VM monitoring fallback (non-heartbeat) | No |
| `2340532315` | Plugin sync on session start | No |
| `2349950458` | Scheduled task notifications | No |
| `2614807392` | Session feature A | No |
| `2678455445` | MCP SDK server mode | No |
| `2860753854` | System prompt override (via value) | No |
| `2976814254` | Launch server (isAvailable check) | No |
| `3196624152` | Phoenix Rising updater | No |
| `3246569822` | canSaveSkill (save reusable skills) | No |
| `3298006781` | MSIX updater gate | No |
| `3366735351` | Auto-update on ready state | No |
| `3444158716` | Cowork resources MCP ("visualize" — show_widget tool) | No |
| `3558849738` | Dispatch/Spaces feature (RBe constant) | **Yes** — forced ON in `fix_dispatch_linux.py` |
| `3572572142` | Sessions-bridge init (Dispatch) | **Yes** — forced ON in `fix_dispatch_linux.py` |
| `3723845789` | Additional Cowork tools | No |
| `3885610113` | Model name [1m] suffix for sonnet-4-6/opus-4-6 | No |
| `4116586025` | louderPenguin / Code tab master gate | No (overridden at merger level) |
| `4153934152` | CLAUDE_CODE_SKIP_PRECOMPACT_LOAD | No |
| `4160352601` | VM heartbeat monitoring | No |

### Object/Value Flags (xy() / $o())

| Flag ID | Type | Purpose |
|---------|------|---------|
| `476513332` | xy() | Update check interval ticks config |
| `554317356` | xy() | Timer interval config |
| `1677081600` | xy() | Custom prompt/instruction text |
| `1748356779` | xy() | System prompt / user prompt template config |
| `1978029737` | $o() | OAuth config (disableOauthRefresh, skillsSyncIntervalMs) |
| `2860753854` | xy() | System prompt override text |
| `3300773012` | $o() | Scheduled tasks config (skillDescription, skillPrompt) |
| `3586389629` | xy() | Connection timeout config |
| `3758515526` | $o() | Default marketplace repo config (repo, repoCCD) |

### Listener Flags (Bx())

| Flag ID | Purpose |
|---------|---------|
| `180602792` | Cookie change / midnight owl |
| `1978029737` | Skills plugin sync |
| `3572572142` | Sessions-bridge on/off toggle |

## What We Patch on Linux

### enable_local_agent_mode.py

**Patch 1 - Individual functions:** Remove `process.platform!=="darwin"` gate from `tqr()` (quietPenguin inner) and `Kjr()` (chillingSlothFeat). Also inject Linux early-return in `U2e()` (yukonSilver) via `uUt()` to bypass its platform gate.

**Patch 3 - jY merger override:** Append to the `jY` return object:
```javascript
,quietPenguin:{status:"supported"},louderPenguin:{status:"supported"},chillingSlothFeat:{status:"supported"},chillingSlothLocal:{status:"supported"},yukonSilver:{status:"supported"},yukonSilverGems:{status:"supported"},ccdPlugins:{status:"supported"}
```

This bypasses the VKe() gate by overriding at the merger level. The spread order ensures our values win:
```
...lA()           -> quietPenguin: {status:"unavailable"}  (from VKe)
...our overrides  -> quietPenguin: {status:"supported"}    (wins)
```

Note: `chillingSlothLocal` and `ccdPlugins` overrides are defensive — both are already `{status:"supported"}`, but the overrides protect against future gating. `yukonSilverGemsCache` is NOT overridden but inherits support from the `U2e()` (yukonSilver) function patch in Patch 1b.

### Cowork on Linux (experimental)

As of v1.1.2685, Cowork uses a decoupled architecture with a TypeScript VM client that communicates with an external service over a socket. This makes Linux support feasible:

- **`fix_cowork_linux.py`** patches the VM client loader to include Linux (not just `win32`)
- The Named Pipe path is replaced with a Unix domain socket on Linux
- **`claude-cowork-service`** (separate Go daemon at `/home/patrickjaja/development/claude-cowork-service`) provides native execution backend — 18 RPC methods, process spawning, path remapping
- `chillingSlothFeat`, `chillingSlothLocal`, `yukonSilver`, `yukonSilverGems`, and `ccdPlugins` are all overridden to `{status:"supported"}` in the cN merger

Without the daemon running, Cowork will show connection errors naturally in the UI.

### Dispatch on Linux (fix_dispatch_linux.py)

Dispatch is a remote task orchestration feature that lets you send tasks from your phone to your desktop. It's built on top of the Cowork sessions infrastructure and uses Anthropic's "environments bridge" API.

**Architecture:** Desktop registers with `POST /v1/environments/bridge`, then long-polls `GET /v1/environments/{id}/work/poll` for incoming work from the mobile client. All traffic routes through Anthropic's servers over TLS — no inbound ports needed.

**What we patch:**
1. **Sessions-bridge init gate** (GrowthBook flag `3572572142`) — The bridge only initializes when this server-side flag fires with `on=true`. On Linux it never fires. We force the gate variable to `!0` (true).
2. **Remote session control** (GrowthBook flag `2216414644`) — Messages with `channel:"mobile"` throw unless this flag is on. We replace `!Qn("2216414644")` with `!1` at both call sites.
3. **Platform label** (`HI()`) — Returns "Unsupported Platform" for Linux. We add `case"linux":return"Linux"`.
4. **Telemetry gate** — `Hr||Pn` (darwin||win32) silently drops telemetry on Linux. We extend to include Linux.

**Note on `operon` (Nest):** Do NOT force-enable — requires VM infrastructure (120+ IPC endpoints across 18 sub-interfaces). Currently `{status:"unavailable"}` on Linux (GrowthBook flag `1306813456` not enabled server-side).

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
| `floatingAtoll` | macOS window button positioning, disabled for all platforms |
| `operon` | Requires VM infrastructure (Nest); flag not enabled server-side |

### Known Issues (v1.1.8359)

| Issue | Status | Detail |
|-------|--------|--------|
| `computer-use-server.js` removed | **Broken** | File removed from app root; our patch applies but `existsSync` fails at runtime. Computer-use MCP server won't register. Needs bundling or embedding. |

## Debugging Feature Flags

### Check if a feature is reaching the renderer

In the renderer DevTools console:
```javascript
// Features are sent via IPC - check what the renderer received
// Look for the feature-flags IPC channel in the Network/IPC tab
```

### Verify jY patch applied correctly

```bash
# After patching, search for the override string
rg 'quietPenguin:\{status:"supported"\}' /path/to/index.js
```

### Pattern anchor stability

Feature name strings are stable across versions because they're IPC identifiers used by both main and renderer processes. The `yukonSilverGems:await \w+\(\)` pattern uses the feature name as anchor and `\w+` for the minified function name.

### When updating for new versions

1. Check if `jY` structure changed (new features added, order changed)
2. Check if VKe()-wrapped features changed
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
| v1.1.7714 | `fp()` | `cN` | `r1e()` | New `yukonSilverGemsCache` (15 features); `Jr()`→`Vr()` flag function; logger `T`→`C`; `computer-use-server.js` removed; Quick Entry position-save added; two Linux guards removed upstream |
| v1.1.8359 | `lA()` | `jY` | `VKe()` | New `operon` (Nest) feature (16 features, 2 async overrides); `Vr()`→`Qn()` flag reader; new GrowthBook flags: `1306813456` (operon), `2051942385` (CIC can-use-tool), `720735283` (marketplace migration), `748063099` (VM pipe retry); removed flags: `1143815894`, `2339607491`; Operon adds 120+ IPC endpoints across 18 sub-interfaces but currently unavailable on Linux |
