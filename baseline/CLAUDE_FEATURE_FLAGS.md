# Claude Desktop Feature Flag Architecture

Reference documentation for the feature flag system in Claude Desktop's Electron app, to aid patch maintenance. The architecture/prose below was first written against v1.8555.2; minified names drift every release, so the **version history table at the bottom is the authoritative record of renames** (current through v1.19367.0). Always cross-check a specific name there before trusting it.

**Code-split caveat (v1.19367.0+):** the main bundle is split into `index.js` (stub) + content-hashed `index.chunk-*.js` files + `index.pre.js`. Minified names are now **per-chunk**: the same function can appear under different local names in different chunks (e.g. the boolean flag reader is `rt()` in the big chunk but `isFeatureEnabled()` in 4 smaller chunks). When grepping, search across ALL `index*.js` files (or the orchestrator's concatenation), and do not assume one canonical name per function.

## Overview

Feature flags are controlled by a 3-layer system (current minified names — see version-history table for the rename trail):

1. **`yh()` (static)** - Calls individual feature functions, builds base object (was `sM()` in v1.18286.x). Since v1.19367.0 the result is post-processed by `tAn()`, which stamps `maturity:"beta"` onto supported features listed in `mvn=["chatTab","surfaceTogglesPreview","chatCodeExecution"]` (cosmetic, no gating).
2. **`_Be` (async merger)** - Spreads `yh()` and applies the async overrides: returns `{...yh(),...s}` where `s={louderPenguin,coworkKappa,coworkArtifacts,epitaxyMcpApps,coworkWatchRecord}` (5 overrides). `markTaskComplete` is **no longer an async override** — it was removed in v1.17282.0 (merger was `Yue` in v1.18286.x).
3. **IPC handler** - Calls merger, validates against schema, sends to renderer

`rt(...)` flag reader in the big chunk (unchanged from v1.18286.x, but aliased `isFeatureEnabled(...)` in other chunks — per-chunk naming, see caveat above). `Bm()` listener, `Pr()` multi-key reader, `Lh()` single-value reader names are v1.18286-era; re-verify per chunk.

Feature name strings (`chillingSlothFeat`, `louderPenguin`, etc.) are runtime IPC identifiers, **not minified** - they are stable pattern anchors.

## All Features (30 listed; `markTaskComplete` removed in v1.17282.0)

| # | Feature | Function | Gate | Purpose |
|---|---------|----------|------|---------|
| 1 | `nativeQuickEntry` | `f7i()` | `platform !== "darwin"` + macOS >= 13 | Native Quick Entry (macOS only) |
| 2 | `quickEntryDictation` | `p7i()` | `platform !== "darwin"` + macOS >= 14.0 + mic | Quick Entry dictation |
| 3 | `customQuickEntryDictationShortcut` | direct value `gK` | None | Custom dictation shortcut value |
| 4 | `plushRaccoon` | `PM(() => gK)` | **PM() production gate** | Custom dictation shortcut (dev-gated) |
| 5 | `quietPenguin` | `PM(M7i)` | **PM()** + inner `M7i()` returns supported on darwin | Code-related feature (dev-gated) |
| 6 | `louderPenguin` | `await T7i()` in SIA only | **async override** in SIA; platform gate (darwin/win32) + GrowthBook `4116586025` | **Code tab** |
| 7 | `chillingSlothFeat` | `m7i()` | darwin\|\|win32 variable check (`P3`) | Local Agent Mode / Cowork |
| 8 | `chillingSlothEnterprise` | `w7i()` | Org config check | Enterprise disable for Claude Code |
| 9 | `chillingSlothLocal` | `D7i()` | **None** (always supported) | Local sessions |
| 10 | `chillingSlothPool` | GrowthBook `1992087837` | GrowthBook flag gate | **Concurrent session pooling** (**new in v1.4758.0**) |
| 11 | `yukonSilver` | `TVA()` | Platform/arch gate + org config (has native Linux support!) | Secure VM |
| 12 | `yukonSilverGems` | `rSe()` | Depends on `yukonSilver` (`TVA()`) | VM extensions |
| 13 | `yukonSilverGemsCache` | `rSe()` | Depends on `yukonSilver` (`TVA()`) | VM extensions cache |
| 14 | `wakeScheduler` | `PM(F7i)` | **PM() gate** + `platform !== "darwin"` + macOS >= 13.0 | macOS Login Items / wake scheduling |
| 15 | `desktopTopBar` | `k7i()` | **None** (always supported) | Desktop top bar |
| 16 | `ccdPlugins` | `gK` (constant) | **None** (always supported) | CCD Plugins UI (Add plugins, Browse plugins) |
| 17 | `computerUse` | `v7i()` | Set-based check on `process.platform` | Computer use feature flag (**patched for Linux** via Set modification) |
| 18 | `coworkKappa` | static: `O7i()` (unavailable) + async in SIA | Depends on yukonSilver + GrowthBook `123929380` | Memory consolidation - `consolidate-memory` skill |
| 19 | `coworkArtifacts` | static: `x7i()` (unavailable) + async in SIA | Depends on yukonSilver + GrowthBook `2940196192` | **Cowork artifacts** - artifact rendering in cowork sessions |
| 20 | `markTaskComplete` | ~~static + async in merger~~ | ~~yukonSilver + GrowthBook `3732274605`~~ | **REMOVED in v1.17282.0** — gone from the static registry, the async merger, the Zod schema, and the force-ON defaults map. Was: task-completion ("mark tasks as done"), GrowthBook `3732274605`. Row kept for history. |
| 21 | `framebufferPreview` | `b7i()` | **PM() production gate** + GrowthBook `1928275548` | VNC framebuffer preview (dev-gated) |
| 22 | `iosSimulator` | `PM(iSe)` | **PM() production gate** + macOS-only | iOS Simulator integration (dev-gated + macOS-only) |
| 23 | `androidEmulator` | `PM(iSe)` | **PM() production gate** + macOS-only | Android Emulator integration (dev-gated + macOS-only; inner function `iSe` unchanged) |
| 24 | `grandPrix` | `L7i()` | darwin-only, checks connected device pairs + `mxi()` gate | Device pairing (macOS-only) |
| 25 | `tearOffHalo` | `G7i()` | macOS >= 13 only | Tear-off halo overlay behind controlled windows (uses `@ant/claude-swift`) |
| 26 | `grandPrixRequest` | `U7i()` | `Gxi()` - darwin only + service requests | GrandPrix service request availability |
| 27 | `bootstrapConfig` | `PM(()=>gK)` | **PM() production gate** | Bootstrap config access (dev-gated) |
| 28 | `chillingSlothSshShell` | `V3e()` → `{status:"supported"}` | **None** (no platform gate) | **SSH shell for Code/Cowork** (new in v1.17282.0; same `V3e()` getter as `chillingSlothFeat`, always supported) |
| 29 | `coworkWatchRecord` | `yHt()` | **darwin-only** (`process.platform!=="darwin"` → `{status:"unsupported", reason:"Watch-record is not available on this platform"}`) | Screen / watch-record (macOS only → **unsupported on Linux**). Async override in `Yue` (new in v1.17282.0) |
| 30 | `spaceMemoryBridge` | `rt("1197768857")?Ed:{status:"unavailable"}` | GrowthBook `1197768857` (no platform check) | **Space memory bridge** — read/index space memory (new in v1.17282.0) |
| - | *(async overrides in `Yue`: `louderPenguin`, `coworkKappa`, `coworkArtifacts`, `epitaxyMcpApps`, `coworkWatchRecord`)* | See rows 6, 18-19, `epitaxyMcpApps`, 29 | async overrides in merger | `markTaskComplete` removed in v1.17282.0 — no longer an async override |

## The Production Gate `LM()` (was `gM()` in v1.15962.x, `HR()` in v1.15200.0, historically `PM()`/`Nb()`/`DT()`/`MW()`)

```javascript
function LM(A){return sA.app.isPackaged?{status:"unavailable"}:A()}
```

In production builds (`app.isPackaged === true`), PM() returns `{status:"unavailable"}` **without calling** the wrapped function. Only in development builds does it call `e()`.

**Features gated by PM():** `plushRaccoon`, `quietPenguin`, `wakeScheduler`, `framebufferPreview`, `iosSimulator`, `androidEmulator`, `bootstrapConfig`

Note: `louderPenguin` is no longer in the static registry at all. It exists only in the async merger, which has its own platform gate (darwin/win32 only) + server feature flag check via GrowthBook `4116586025`. `operon` has been completely removed in v1.6608.0. `coworkKappa`, `coworkArtifacts`, and `coworkWatchRecord` are async-only: static returns unavailable, async checks GrowthBook flags (`coworkWatchRecord` is darwin-only via `yHt()`). **`markTaskComplete` was removed entirely in v1.17282.0** — it is no longer a static entry or an async override. `chillingSlothPool` is GrowthBook-gated directly in the static registry.

This is why patching the inner functions alone is insufficient - PM() never calls them in packaged builds.

## The Three Layers

### Layer 1: Np() - Static Registry

```javascript
function Np(){
  return{
    nativeQuickEntry:...,
    quickEntryDictation:...,
    customQuickEntryDictationShortcut:...,
    plushRaccoon:PM(()=>...),
    quietPenguin:PM(...),
    chillingSlothFeat:...,             // darwin||win32 variable check (P3)
    chillingSlothEnterprise:...,
    chillingSlothLocal:...,
    chillingSlothPool:...,             // GrowthBook 1992087837 gate
    yukonSilver:...,
    yukonSilverGems:...,
    yukonSilverGemsCache:...,
    wakeScheduler:PM(...),
    desktopTopBar:...,
    ccdPlugins:...,                    // constant {status:"supported"}
    computerUse:...,                   // Set-based gate, "linux" added by patch
    coworkKappa:...,                   // always unavailable (async-only)
    coworkArtifacts:...,               // always unavailable (async-only)
    // markTaskComplete: REMOVED in v1.17282.0 (was always-unavailable async-only)
    coworkWatchRecord:...,             // always unavailable static; darwin-only async override (yHt())
    chillingSlothSshShell:...,         // V3e() -> {status:"supported"}, no gate
    spaceMemoryBridge:...,             // GrowthBook 1197768857 gate
    framebufferPreview:PM(...),        // dev-gated + GrowthBook 1928275548
    iosSimulator:PM(...),              // dev-gated + macOS-only
    androidEmulator:PM(...),           // dev-gated + macOS-only
    grandPrix:...,                     // macOS-only, checks device pairs via L7i()
    tearOffHalo:...,                   // macOS >= 13 only
    grandPrixRequest:...,              // darwin only + service requests
    bootstrapConfig:PM(()=>...),       // dev-gated
  }
}
```

Returns 26 features synchronously. Features wrapped by `PM()` are always `{status:"unavailable"}` in packaged builds.

### Layer 2: Yue - Async Merger (was HSA in v1.15962.x, UcA in v1.8089.1, woA in v1.7196.0)

```javascript
const Yue=async()=>{
  const[A,e,t,r,i]=await Promise.all([
    wen(),                       // louderPenguin
    p6e(()=>et("123929380")),    // coworkKappa
    p6e(()=>et("2940196192")),   // coworkArtifacts
    Pue(()=>et("3516166472")),   // epitaxyMcpApps
    Den()                        // coworkWatchRecord (darwin-only via yHt())
  ]);
  // a 6th Promise.all slot (pt().overlayApplied()) is consumed separately, not in n
  const n={louderPenguin:A,coworkKappa:e,coworkArtifacts:t,epitaxyMcpApps:r,coworkWatchRecord:i};
  return{...sM(),...n}
};
```

Uses `Promise.all` to parallelize the async overrides, then spreads `sM()` and applies `n` (5 overrides). louderPenguin (`wen()`) checks platform (darwin/win32) then server feature flag `4116586025`. The `p6e()` helper checks yukonSilver first, waits 5 seconds, then checks the respective GrowthBook flag. `coworkWatchRecord` (`Den()` → `yHt()`) is darwin-only — unsupported on Linux. **`markTaskComplete` was removed in v1.17282.0** — its former `p6e(()=>et("3732274605"))` slot and `markTaskComplete:i` override are both gone. **`operon` was removed in v1.6608.0.**

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

**Because spread applies earlier properties first, later properties win.** This is how our Linux patch works - we append overrides after the last async property so they take precedence over gate-blocked values from `...Np()`.

### Org-Level Settings

Feature flags can also be affected by organization-level admin settings:

- **"Skills" toggle** in org admin → controls SkillsPlugin availability. When disabled, SkillsPlugin returns 404, causing the renderer to hide plugin UI buttons (Add plugins, Browse plugins). This is independent of `ccdPlugins` — the feature flag can be `{status:"supported"}` but the UI still won't show if the org disables Skills.
- **`chillingSlothEnterprise`** → org-level disable for Claude Code. When the org config disables it, the Code tab disappears regardless of other feature flags.

### Layer 3: IPC Handler

Calls the merger, validates the result against a Zod schema, and sends it to the renderer process via IPC. The renderer uses these flags to conditionally render UI elements (e.g., Chat|Code toggle).

## GrowthBook Flag Catalog (baseline v1.8555.2; see version-history table for current names)

#### New Flags in v1.19367.0

| Flag ID | Type | Purpose | Patched? |
|---------|------|---------|----------|
| `1544796833` | value (`Vr(id,key,default,zodInt)`) | Session-concurrency limits config via `M6(key,default)`: `maxConcurrentPerSession` (8), `maxConcurrentTotal` (16), `maxQueuedPerSession` (256), `maxQueuedTotal` (1024), `maxQueuedCharsTotal` (256MB) | No |
| `2016258596` | boolean (constant `otr`) | Device-tool artifact storage/read gate — when OFF, artifact reads emit `artifact_read_gate_off` telemetry and return a gate-off message; also augments the `1947305033` create/update_artifact tool description | No |
| `416245092` | boolean, default ON (`ga(id,!0)`) | GPU crash-streak marker — gates writing a `gpu-crash-streak-marker` state file after repeated GPU process crashes | No |

(`"123456789"` also appears new in the raw numeric diff but is a TUI keypress helper string — number-row key matching — not a flag.)

**Removed in v1.19367.0:** none (broad numeric-string diff OLD vs NEW shows 0 removals).

**New static feature in v1.19367.0:** `coworkScheduledTaskProjects:ul` (always supported, no platform gate, present in the Zod schema; no override needed).

#### New Flags in v1.17282.0

| Flag ID | Role | Patched? |
|---------|------|----------|
| `1197768857` | `spaceMemoryBridge` feature gate — registry entry `rt("1197768857")?Ed:{status:"unavailable"}`, also gates the space-memory MCP tools (`readSpaceMemoryIndex`) | No |
| `1295378343` | `gapSurviveEnabled` — value flag, default OFF (`FE("1295378343",!1)`); spread onto a spawned live-process options object | No |
| `130970054` | `rt("130970054")` read into a prompt/feature enable check (`Ve({enabled:...})`) | No |
| `1569828280` | Binary-asset-fetch gate — `if(!et("1569828280")){...gate_off...skipping binary asset fetch}` | No |
| `2431502897` | Model-policy map entry — `"2431502897":lW("inherit")` in the model/permission policy resolver map | No |
| `3778159589` | Device-stale-relogin — `rt("3778159589")?e():A()` selecting the relogin path (`markDeviceStaleRelogin`) | No |
| `629684104` | Assistant-error-recovery — gates synthesizing a recovery result (`assistantUuid`/`resultUuid`) on an assistant error | No |

#### Removed in v1.17282.0

| Flag ID | Was | Notes |
|---------|-----|-------|
| `1802019210` | Cowork plugin upload migration gate | Gone from the bundle (no `rt()`/`wt()` calls) |
| `1985784543` | `isEnabled` gate spread onto a config object (added v1.13576.0) | Gone from the bundle |
| `3110209724` | (prior gate) | Gone from the bundle |
| `3732274605` | `markTaskComplete` feature gate | Gone — feature removed from registry, merger, Zod schema, and force-ON defaults map |
| `4018578026` | (prior gate) | Gone from the bundle |

### Boolean Flags (wt())

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `162211072` | Prompt suggestions enable | No |
| `286376943` | Plugin skills for system prompt — gates `getPluginSkillsForSystemPrompt` (**new in v1.2278.0**) | No |
| `397125142` | Terminal server — gated: `sessionType==="ccd"&&!isSSH` AND this flag. CCD only, NOT cowork. Upstream **dropped** the old `pj`/`r6e` platform gate, so no patch needed (was `fix_dispatch_linux.nim`, now removed); flag enabled server-side | No |
| `714014285` | CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING | No |
| `763725229` | Developer menu label/visibility | No |
| `720735283` | Marketplace migration | No |
| `748063099` | VM client retry on pipe close | No |
| `770567414` | VM service routing (direct vs persistent pipe) | No |
| `1412563253` | askUserQuestion preview format ("html") | No |
| `1434290056` | Dispatch code tasks permission mode — bypass-permissions for dispatch sessions (**new in v1.2278.0**) | No |
| `1942781881` | Prompt suggestions in sessions | No |
| `2051942385` | CIC can-use-tool | No |
| `2067027393` | canLaunchCodeSession | No |
| `2216414644` | Remote session control (Dispatch mobile) | No — was bypassed in `fix_dispatch_linux.nim`; **patch removed** (Dispatch is upstream-native on Linux as of v1.17377, live-tested) |
| `2246535838` | Local MCP server prefix (`local:`) | No |
| `2339084909` | VM monitoring fallback (non-heartbeat) | No |
| `2340532315` | Plugin sync on session start | No |
| `2345107588` | GrowthBook cache persistence — persist/seed GrowthBook cache from/into sessions (**new in v1.2278.0**) | No |
| `2349950458` | Scheduled task notifications | No |
| `2392971184` | Replay user messages — adds `--replay-user-messages` to CLI args for session resume; also enables `/remote-control`/`/rc` command in dispatch (**new in v1.2278.0**) | No |
| `2614807392` | Session feature A | No |
| `2725876754` | Org CLI exec policies — gates reading `orgCliExecPolicies` for plugin tool permission checks (**new in v1.2278.0**) | No |
| `2976814254` | Launch server (isAvailable check) | No |
| `3246569822` | canSaveSkill (save reusable skills) | No |
| `3366735351` | Auto-update on ready state | No |
| `2940196192` | coworkArtifacts — persistent HTML artifact storage in cowork sessions | **Yes** — forced ON in `enable_local_agent_mode.nim` (4 call sites) |
| `3444158716` | Cowork resources MCP ("visualize" — show_widget tool) | No |
| `1143815894` | hostLoopMode — non-VM cowork (bare SDK loop, no cowork service spawn) | **No** — must NOT be forced ON; doing so bypasses the cowork service, breaking skills/plugins |
| `3558849738` | Dispatch/Spaces feature (RBe constant) | No — was forced ON in `fix_dispatch_linux.nim`; **patch removed** (defaults ON upstream on Linux) |
| `3572572142` | Sessions-bridge init (Dispatch) | No — was forced ON in `fix_dispatch_linux.nim`; **patch removed** (inits natively on Linux) |
| `3691521536` | Stealth updater — nudge updates when no active sessions | No |
| `3723845789` | Additional Cowork tools | No |
| `4116586025` | louderPenguin / Code tab master gate | No (overridden at merger level) |
| `4153934152` | CLAUDE_CODE_SKIP_PRECOMPACT_LOAD | No |
| `4160352601` | VM heartbeat monitoring | No |
| `4201169164` | **Remote orchestrator** (codename "manta") — **removed from GrowthBook** in v1.1.9669; `Hhn()` now returns hardcoded `false` (`Qhn=!1`). Code still exists but is disabled. | No — `fix_dispatch_linux.nim` removed (Dispatch upstream-native) |

#### New Boolean Flags in v1.8089.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `245679952` | `suggestSkillsEnabled` default (when no system prompt override) | No |
| `1129419822` | `ENABLE_TOOL_SEARCH='auto'` env var for LAM sessions | No |
| `1496676413` | SSH remote MCP/plugin passthrough (`adjustSdkOptions`) **(removed upstream v1.18286.0 - gate went unconditional)** | No - Patch 3n deleted |
| `2049450122` | Session handoff detection (`cse_`/`session_` prefix check) | No |
| `2192324205` | Tool use result formatting/filtering | No |
| `2800354941` | Deterministic sorting of plugins/tools/logs | No |

#### Flags Now in Force-ON Defaults Map (uNi) in v1.8555.2

| Flag ID | Purpose | Notes |
|---------|---------|-------|
| `3246569822` | `canSaveSkill` (save reusable skills) | Was already documented but now in force-ON defaults map |

#### New Non-Boolean Flag in v1.8089.0

| Flag ID | Type | Purpose | Patched? |
|---------|------|---------|----------|
| `4274871493` | value | Plugin enabled state fetching (`fetchEnabledState`) | No |

#### New Listener Flag in v1.8089.0

| Flag ID | Purpose |
|---------|---------|
| `180602792` | midnightOwl prototype (quick access overlay feature) |

#### Removed in v1.8089.0

| Flag ID | Was | Notes |
|---------|-----|-------|
| `982691970` | Cowork plugin host ops gate | Completely removed from `wt()` calls |
| `1802019210` | Cowork plugin upload migration | Completely removed from `wt()` calls |
| `2216480658` | VM outputs directory mounting | Completely removed from `wt()` calls |
| `2860753854` | System prompt override | Completely removed from `wt()` calls |
| `3298006781` | MSIX updater gate | Completely removed from `wt()` calls |
| `3858743149` | `maxThinkingTokens` config | Completely removed from `wt()` calls |
| `3885610113` | Model name [1m] suffix | Completely removed from `wt()` calls |
| `4019128077` | Cowork CU `alwaysLoad` | Completely removed from `wt()` calls |

#### Access Pattern Changes in v1.8089.0

| Flag ID | Change | Notes |
|---------|--------|-------|
| `2307090146` | Plugin OAuth storage gate | Still in force-ON defaults map (`uNi`) but no longer in `wt()` direct calls |
| `2345515473` | Sessions-bridge account-change | Still in `Bm()` listener calls |
| `3558849738` | Dispatch/Spaces | Stored as `mpt` constant, read via `wt(mpt)` (still exists) |
| `3572572142` | Sessions-bridge init | Still in `Bm()` listener calls |

#### Notable Feature Changes in v1.8089.0

- `2204227020` also gated Visualize (Imagine) MCP server for CCD sessions (was cowork-only before). **Renamed to `3516166472` in v1.13576** - the old ID no longer appears in the bundle; `fix_imagine_linux.nim` Patch C tracks the new ID.
- New `floatingPenguinEnabled` preference (not yet a feature flag in registry - config-only)
- New `midnightOwl` prototype (dev toggle + GrowthBook flag `180602792`)

#### New Boolean Flags in v1.13576.0

(Delta measured vs the v1.12603.0 baseline bundle; `1703762832` was already added in v1.12603.1, so net-new in v1.13576.0 is `1985784543` + `3646818354`.)

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `1985784543` | An `isEnabled` gate spread onto a config object: `e?{...e,isEnabled:()=>Ct("1985784543")}:null`. No platform gate. | No |
| `3646818354` | `shouldKillOnIdlePause()` returns `!Ct("3646818354")` - when ON, the session is NOT killed on idle pause. No platform gate. | No |

#### New Boolean Flags in v1.12603.1

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `1703762832` | `onModelRefusalFallback` retry - when ON, a refusal response with `direction:"retry"` in `AgentModeSessionManager` triggers a fallback handler (sets `session.overrideLabel` + initiates retry). No platform gate, purely server-side rollout. | No |

#### New Boolean Flags in v1.12603.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `2115990222` | `artifactsPane` feature gate - NEW static registry feature `artifactsPane:DPt()` where `function DPt(){return dt("2115990222")?{status:"supported"}:{status:"unavailable"}}`. No platform gate, purely GrowthBook-rolled-out. First key in the registry object. | No |
| `2745857735` | LAM remote folder-access requests - when ON, dispatch/LAM sessions get an extra tool ("Ask the user to grant this session access to a folder on this device that is not currently connected"), telemetry event `lam_remote_request_folder_access`; when OFF the handler returns "Folder access requests are not enabled on this device." Also changes trusted-folder enumeration: `dt("2745857735")?[]:Object.values(i).flat()` (flag ON narrows the default trusted-folder set to per-session entries) | No |
| `884132720` | OAuth scope passthrough - forwards the OAuth token scope into the CLI session env build: `oauthScope:dt("884132720")?t.scope:void 0` inside `ZWr({oauthToken,...})` | No |

#### New Value Flag in v1.12603.0

| Flag ID | Type | Purpose | Patched? |
|---------|------|---------|----------|
| `3932491586` | `LC()` value, default `!1` | VM optional mounts - marks user-selected folder mounts as `optional:LC("3932491586",!1)===!0` in the cowork VM mount table; present as force-OFF (`qdr`) in the `Vdr` defaults map. `LC(A,e)` is a NEW reader: `function LC(A,e){const t=gf[A];return LAA(A,t),t===void 0?e:t.value}` | No |

**Removed in v1.12603.0:** none (0 flag IDs removed; broad numeric-string diff OLD vs NEW confirmed only the 4 additions above).

#### New Boolean Flags in v1.11847.5

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `3516166472` | `epitaxyMcpApps` async gate - MCP apps inside epitaxy (SSH remote) sessions; merger helper `zQt()` = `await e4A(5e3)` (5s delay) + `await ctt()` prereq + this flag | No |
| `1997559319` | `onUserDialog` broker - enables `supportedDialogKinds:["refusal_fallback_prompt"]` permission-dialog path | No |
| `2724639973` | Session governor `evictionEnabled` - memory-pressure-based session eviction | No |
| `3807767338` | `seedPolicyLimitsIntoSession` / `refreshPolicyLimitsPersist` - org policy-limit persistence | No |

**New static features in v1.11847.5** (see version history row): `coworkRemoteSessionSpaces` (always supported), `coworkBranchSession` (always supported), `epitaxyMcpApps` (static unavailable + async override via `3516166472`). None platform-gated; `enable_local_agent_mode.nim` override list unchanged. (Precise add/remove flag delta is not fully reliable - the only local prior bundle is patched - so this table lists the 4 flags verified genuinely new this release rather than a raw set diff.)

#### New Boolean Flags in v1.8555.2

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `434204418` | MCP non-blocking connection | No |

#### New Listener Flags in v1.8555.2

| Flag ID | Purpose |
|---------|---------|
| `4150329283` | Cloud sync drive |
| `2358734848` | Hardware buddy |

#### Flags Now in Force-ON Defaults Map (uNi) in v1.8555.2

| Flag ID | Purpose | Notes |
|---------|---------|-------|
| `2940196192` | coworkArtifacts | Added to force-ON defaults map |

#### Removed in v1.8555.2

| Flag ID | Was | Notes |
|---------|-----|-------|
| `658929541` | Lock mid-session model changes (LAM setModel buffer) | Completely removed from `wt()` calls |
| `2815031518` | CCD lock mid-session model change (LocalSessionManager) | Completely removed from `wt()` calls |

#### Removed Value Flags in v1.8555.2

| Flag ID | Was | Notes |
|---------|-----|-------|
| `2921038508` | Cowork memory guide prompt text | Completely removed |

#### New in v1.1.9134

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `66187241` | `CLAUDE_CODE_EMIT_TOOL_USE_SUMMARIES` for LAM/Cowork sessions | No |
| `1585356617` | Epitaxy routing - SSH session routing, spawned session tools, system prompt append. When on, sessions route to `/epitaxy?openSession=` instead of `/claude-code-desktop/` | No |
| `2199295617` | AutoArchiveEngine — auto-archives sessions when PRs close | No |
| `3792010343` | `CLAUDE_CODE_EMIT_TOOL_USE_SUMMARIES` for CCD (non-LAM) sessions | No |

#### Removed in v1.1.9134

| Flag ID | Was | Notes |
|---------|-----|-------|
| `3196624152` | Phoenix Rising updater | Completely removed |

#### New in v1.1062.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `2114777685` | Cowork onboarding / CU-only mode (`show_onboarding_role_picker` tool) | No |
| `3371831021` | `cuOnlyMode` — computer-use-only session variant | No |

#### New in v1.2773.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `2140326016` | Author-supplied bin stubs error enforcement | No |
| `2216480658` | VM outputs directory mounting | No |
| `3858743149` | `maxThinkingTokens` config (configurable thinking budget, default 4000, min 1024) | No |

#### Removed in v1.2773.0

| Flag ID | Was | Notes |
|---------|-----|-------|
| `1585356617` | Epitaxy routing — SSH session routing | Completely removed |
| `2199295617` | AutoArchiveEngine — auto-archives sessions when PRs close | Completely removed |
| `4201169164` | Remote orchestrator ("manta") — was already hardcoded off | Completely removed |

#### New in v1.5354.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `451382573` | `DISABLE_BRIEF_MODE_STOP_HOOK` env var for cowork/LAM sessions | No |
| `839037100` | Cowork OAuth configs — gates OAuth config loading | No |
| `939257113` | Dispatch child session detection — `isRemoteDispatchChild` qualifier | No |
| `975112542` | Cowork memory remote sync — `canSyncCoworkMemoryRemotely()` | No |
| `1696890383` | `CLAUDE_COWORK_MEMORY_GUIDE` env — passes memory guide to cowork sessions (also in force-ON defaults) | No |
| `1824824999` | Consolidate-memory skill v2 — configurable descriptions via `1004628546` | No |
| `1928275548` | framebufferPreview feature — dev-gated (inside `MW()`) | No (dev-only) |
| `2216901299` | Org policy backend check — remote management policy enforcement | No |
| `2393677837` | PreToolUse hook for worktree-aware tool input validation | No |
| `2979038612` | Session notifications — `queueSessionNotification` for model switch, folder access | No |
| `3023518717` | Updater rollback detection — extends auto-update triggers | No |
| `4019128077` | Cowork browser/CU `alwaysLoad` — forces all CU MCP tools to always load | No |
| `4141490266` | Framebuffer system prompt injection — adds instructions when Framebuffer server active | No |

#### New Value/Object Flags in v1.5354.0

| Flag ID | Type | Purpose | Patched? |
|---------|------|---------|----------|
| `1004628546` | `lp()` | Configurable consolidate-memory skill description/prompt | No |
| `3229517805` | `lp()` | `runScheduledTaskEnabled` (default `true`) — scheduled task execution gate | No |

#### New Listener Flags in v1.5354.0

| Flag ID | Purpose |
|---------|---------|
| `2345515473` | Sessions-bridge account-change reevaluation |

#### New in v1.6259.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `982691970` | Cowork plugin host ops gate (dynamic import) | No |
| `1802019210` | Cowork plugin upload migration gate (dynamic import) | No |
| `2307090146` | Plugin OAuth storage gate (also added to force-ON defaults map) | No |

#### New Value/Object Flags in v1.6259.0

| Flag ID | Type | Purpose | Patched? |
|---------|------|---------|----------|
| `873030668` | `lp()` | GrandPrix partner config (salt + partner entries) | No |
| `1126577245` | `lp()` | Cowork memory remote sync config | No |
| `2921038508` | `lp()` | Cowork memory guide prompt text | No |

#### Removed in v1.6259.0

| Flag ID | Was | Notes |
|---------|-----|-------|
| `839037100` | Cowork OAuth configs gate | Completely removed |

#### Removed in v1.6608.0

| Flag ID | Was | Notes |
|---------|-----|-------|
| `1306813456` | Operon/Nest gate | Completely removed (operon feature removed) |
| `1496450144` | `CLAUDE_CODE_ENABLE_TASKS` env var | Completely removed |
| `2216480658` | VM outputs directory mounting | Completely removed |
| `2433104842` | Operon/CU-related | Completely removed |
| `2486083521` | Operon/CU-related | Completely removed |
| `4019128077` | Cowork browser/CU `alwaysLoad` | Completely removed |

#### New Server-Side GrowthBook Flags in v1.6608.2

21 new server-side GrowthBook flag IDs observed. These are **not** feature flags in the static registry (`Np()` in v1.8555.2, was `eD()` in v1.8089.0, `pw()` in v1.6608.2); they are server-side toggles read via `wt()` (was `St()` in v1.8089.0, `pt()` in v1.6608.2) at runtime. All function names unchanged from v1.6608.1.

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `66187241` | `CLAUDE_CODE_EMIT_TOOL_USE_SUMMARIES` for local-agent sessions | No |
| `451382573` | `DISABLE_BRIEF_MODE_STOP_HOOK` for dispatch sessions | No |
| `658929541` | Lock mid-session model changes when message buffer non-empty | No |
| `939257113` | Dispatch subscription check (`isRemoteDispatchChild` qualifier) | No |
| `975112542` | Cowork memory remote sync (`canSyncCoworkMemoryRemotely()`) | No |
| `1496676413` | SSH plugin/MCP stripping — gates plugin and MCP forwarding to SSH sessions **(removed upstream v1.18286.0 - gate went unconditional)** | No - Patch 3n deleted |
| `1696890383` | Cowork memory guidelines injection (`CLAUDE_COWORK_MEMORY_GUIDE` env) | No |
| `1824824999` | Memory-consolidation skill config (configurable descriptions) | No |
| `2049450122` | Session handoff — cross-device session activity broadcasting | No |
| `2114777685` | Cowork-only MCP tool (`show_onboarding_role_picker`) | No |
| `2140326016` | Hard-fail on author-supplied bin/ stubs | No |
| `2192324205` | Tool use result filtering (dispatch structured content forwarding) | No |
| `2216901299` | Org policy backend check — remote management policy enforcement | No |
| `2393677837` | PreToolUse hook for worktree-aware permission blocking | No |
| `2800354941` | Sort plugin skills alphabetically — deterministic ordering | No |
| `2815031518` | CCD lock mid-session model change (LocalSessionManager equivalent) | No |
| `2979038612` | Notify user on missing session folders (`queueSessionNotification`) | No |
| `3023518717` | Auto-update nudge — extends auto-update triggers (rollback detection) | No |
| `3371831021` | Cowork CU-only mode (`COWORK_CU_ONLY`) | No |
| `3792010343` | `CLAUDE_CODE_EMIT_TOOL_USE_SUMMARIES` for CCD (non-LAM) sessions | No |
| `4141490266` | Extended tool actions (framebuffer system prompt injection) | No |

**Note:** Many of these flag IDs already appeared in earlier version sections (e.g., `66187241` and `3792010343` in v1.1.9134, `451382573` in v1.5354.0). They are listed here because they were newly observed in server-side GrowthBook payloads for v1.6608.2, confirming they remain active.

#### MCP Registration Renames in v1.6608.2

| Old | New | Context |
|-----|-----|---------|
| `lrA()` | `BrA()` | MCP server registration function |
| `MG` | `I_` | MCP-related variable |
| `VqA` | `xSA` | MCP-related variable |
| `Y7()` | `pq()` | MCP-related function |

**Note:** `lrA()`→`BrA()` was already noted in the v1.6608.1 version history entry. The remaining three renames (`MG`→`I_`, `VqA`→`xSA`, `Y7()`→`pq()`) are new in v1.6608.2.

#### Removed in v1.5354.0

| Flag ID | Was | Notes |
|---------|-----|-------|
| `365342473` | `shouldScrubTelemetry` (value flag) | Completely removed from codebase |

#### New in v1.4758.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `1992087837` | chillingSlothPool — concurrent session pooling | **Yes** — forced ON in `enable_local_agent_mode.nim` (2 call sites) |
| `3732274605` | markTaskComplete — task completion feature | ~~**Yes** — forced ON in `enable_local_agent_mode.nim`~~ **REMOVED in v1.17282.0** (flag gone from bundle; the patch's markTaskComplete force-ON entry is now a vestigial no-op, but the patch was intentionally left unchanged) |

#### New in v1.3883.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `2049450122` | Session handoff — gates cross-device session activity broadcasting (`com.anthropic.claude.session` NSUserActivity identifier) | No |
| `2192324205` | Dispatch structured content forwarding — gates whether `dispatch_child` and `code` structured content kinds pass the message filter (in the rjt() function patched by `fix_dispatch_linux.nim`) | No |

#### New in v1.3561.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `1496676413` | SSH session plugins/MCP forwarding — gates plugin and MCP server forwarding to SSH remote sessions (6 call sites in session start, spawn, and MCP resolution) **(removed upstream v1.18286.0 - gate went unconditional)** | No - Patch 3n deleted |
| `2023768496` | Trusted device token — gates `coworkTrustedDeviceToken` read/write for cowork sessions | No |

**Also:** `123929380` (coworkKappa) added to force-ON defaults map — Anthropic enabling consolidate-memory by default before server config loads.

#### New in v1.3036.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `658929541` | LocalAgentModeSessionManager `setModel` buffer check — allows model-switch when `messageBuffer.length>0` (ccd_lock mitigation) | No |
| `1496450144` | `CLAUDE_CODE_ENABLE_TASKS` env var — enables the new Tasks CLI feature (gated alongside `CLAUDE_CODE_SKIP_PRECOMPACT_LOAD`) | No |
| `2800354941` | Alphabetical sort for plugin/skill lists and system-prompt skills — deterministic ordering | No |
| `2815031518` | LocalSessionManager `setModel` buffer check — CCD-session equivalent of `658929541` (ccd_lock mitigation) | No |

#### Removed in v1.3036.0

| Flag ID | Was | Notes |
|---------|-----|-------|
| `159894531` | ENABLE_TOOL_SEARCH env-var override (was forced ON by our patch) | **Completely removed — the Desktop-side `ENABLE_TOOL_SEARCH="false"` override is gone. User's `~/.claude/settings.json` now passes through unmolested. Our Patch 3c was removed.** |
| `919950191` | ENABLE_TOOL_SEARCH for LAM sessions (was new in v1.2773.0) | Completely removed |
| `2678455445` | MCP SDK server mode | Completely removed |

#### New in v1.2581.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `123929380` | coworkKappa / `consolidate-memory` skill — reflective pass over memory files (merge, prune, fix). Also gates session context building for typeless sessions. | **Yes** — forced ON in `enable_local_agent_mode.nim` (3 call sites) |

#### Removed in v1.2581.0

| Flag ID | Was | Notes |
|---------|-----|-------|
| `4040257062` | Memory path routing — nested memory dir for non-session contexts | Completely removed from codebase |

#### New in v1.1348.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `4040257062` | Memory path routing — nested memory dir for non-session contexts | No (**removed in v1.2581.0**) |

#### Removed in v1.1348.0

| Flag ID | Was | Notes |
|---------|-----|-------|
| `927037640` | Subagent model config (Js() value flag) | Completely removed from codebase |
| `3190506572` | Chrome permission control (skip_all_permission_checks, disable_javascript_tool) | Completely removed from codebase |

#### Removed in v1.1062.0

These dispatch-era flags were removed from GrowthBook boolean calls (code may still reference them but they no longer fire):

| Flag ID | Was | Notes |
|---------|-----|-------|
| `3558849738` | Dispatch/Spaces feature | Still used as constant `PLe` + `hI()` wrapper + listener, but not in direct boolean calls |
| `3572572142` | Sessions-bridge init (Dispatch) | Still has active listener `LI("3572572142", ...)` |
| `4201169164` | Remote orchestrator ("manta") | Fully removed |
| `1585356617` | Epitaxy routing | Removed |
| `2199295617` | AutoArchiveEngine | Removed |
| `2860753854` | System prompt override (boolean call) | Removed from boolean calls (still exists as value flag) |

### Object/Value Flags (Pr())

`Lh()` reads single-value flags (reads `.value` directly from `CQ` storage); `Pr()` reads structured object flags with key+schema.

| Flag ID | Type | Purpose |
|---------|------|---------|
| `254738541` | fs() | Prompt text (**new in v1.1348.0**) |
| `365342473` | wA() | shouldScrubTelemetry (default: `true`) (**new in v1.1348.0**) |
| `476513332` | wA() | Update check interval ticks config |
| `554317356` | wA() | Timer interval config |
| `1677081600` | wA() | Custom prompt/instruction text |
| `1748356779` | wA() | System prompt / user prompt template config |
| `1893165035` | wA() | SDK error auto-recovery config (`{enabled, categories}`) — categories include `sdk_binary_missing`, `sandbox_deps_missing`, `filesystem_error` (**new in v1.2278.0**) |
| `1978029737` | fs() | Session config (skillsSyncIntervalMs, artifactMcpConcurrencyLimit, artifactSampleConcurrencyLimit, idleGraceMs, disableSessionsDiskCleanup, sessionsBridgePollIntervalMs, coworkMessageTimeoutMs, coworkWebFetchViaApi, coworkNativeFilePreview, coworkWebFetchPrompt, memoryIndexSnapshotIdleMs, peakHoursStartPst, peakHoursEndPst) |
| `2860753854` | wA() | System prompt override text |
| `2893011886` | fs() | Wake scheduler config (enabled, scheduledTasksWakeEnabled, minLeadTimeMs, chainIntervalMs, batteryIntervalMs, acIntervalMs) |
| `3300773012` | fs() | Scheduled tasks config (skillDescription, skillPrompt, scheduledTaskPostWakeDelayMs, dispatchJitterMaxMinutes) |
| `3586389629` | wA() | Connection timeout config |
| `3758515526` | fs() | Default marketplace repo config (repo, repoCCD) |
| `3858743149` | fs() | maxThinkingTokens config (default 4000, min 1024) (**new in v1.2773.0**) |
| `4066504968` | fs() | Setup-cowork skill config (skillDescription, skillPrompt) (**new in v1.1348.0**) |

### Listener Flags (Bm())

| Flag ID | Purpose |
|---------|---------|
| `180602792` | midnightOwl prototype (quick access overlay feature) (**new in v1.8089.0**) |
| `1978029737` | Skills plugin sync / poll sleep kick |
| `2345515473` | Sessions-bridge account-change reevaluation |
| `2940196192` | Artifacts changed listener - triggers re-emit on flag toggle |
| `3572572142` | Sessions-bridge on/off toggle |
| `mpt` (`3558849738`) | Dispatch/Spaces feature - used via variable reference |

## What We Patch on Linux

### enable_local_agent_mode.nim

**Patch 1 - Individual functions:** Remove the `process.platform!=="darwin"` (or compound darwin/win32) gate from the remaining platform-gated feature function(s) (only quietPenguin as of v1.17377; the count varies per release and the patch accepts >=1 match). **Patch 1b (yukonSilver) is a pure regression guard** - upstream's official Linux `.deb` has native Cowork support (linux->"unix" VM-bundle key + `eo.files[e_A("linux")][arch]` gated on the real `are()` KVM probe), so nothing is injected; the guard fails the build loud if that native path ever disappears.

**Patch 3 - merger override (7 keys as of 2026-07-01):** Append to the async merger's return object:
```javascript
,quietPenguin:{status:"supported"},louderPenguin:{status:"supported"},chillingSlothFeat:{status:"supported"},chillingSlothLocal:{status:"supported"},chillingSlothPool:{status:"supported"},ccdPlugins:{status:"supported"},computerUse:{status:"supported"}
```

The spread order ensures our values win over the static registry. **Deliberately NOT overridden:** `yukonSilver` / `yukonSilverGems` / `coworkKappa` / `coworkArtifacts` status objects - those must reflect upstream's native VM-capability probe (`are()`: /dev/kvm, OVMF, qemu, virtiofsd); force-marking them would mask a real unavailable state and turn the honest "install QEMU" message into a generic VM-spawn failure. The GrowthBook flag force-flips are separate and kept: `coworkKappa` `123929380` (3b), `coworkArtifacts` `2940196192` (3c), `chillingSlothPool` `1992087837` (3d), plus the 3f-3p set. `markTaskComplete` (former Patch 3e, flag `3732274605`) was removed upstream in v1.17282.0 and the sub-patch was deleted.

**Platform spoofs removed (2026-07-02, issue #173):** former sub-patches 5 (HTTP header `anthropic-client-os-platform: darwin`), 5b (Macintosh User-Agent), 6 (`getSystemInfo` IPC -> `win32`) and 8 (`navigator.platform="Win32"` + Windows userAgentFallback) are GONE. They were MSIX-era workarounds; against the official Linux `.deb` they made the remote claude.ai renderer see Windows and block Cowork ("Cowork is not currently supported on Windows"). The app now reports `linux` everywhere, guarded by a positive assertion that the header builder sends the raw `.platform` read. **The GrowthBook force-flips stay regardless:** a live post-fix session's `/api/desktop/features` payload (disk cache `~/.config/Claude/fcache`) serves all 200 features as `null` with zero rules ("0 changed" vs the spoofed-era cache), so honest platform reporting unlocks nothing server-side - without the flips, every gated lookup returns null and the features switch off.

### Cowork on Linux (experimental)

As of the official Linux `.deb`, Cowork runs on Anthropic's **native Linux VM backend** bundled in the package (cowork-linux-helper + virtiofsd + smol-bin + QEMU/OVMF; requires `/dev/kvm`). The MSIX-era wiring is gone:

- **`fix_cowork_linux.nim` and the rest of the cowork-wiring cluster were removed** in the `.deb` pivot - the official build ships the VM client loader with native Linux support
- **`claude-cowork-service`** (the separate Go daemon) is **deprecated** and no longer used; Cowork now works through the official native backend
- The only remaining Cowork patch is **`fix_cowork_firmware_paths_linux.nim`** (adds non-Debian OVMF firmware paths *and* non-Debian `virtiofsd` paths to the VM capability probe)
- `yukonSilver` / `yukonSilverGems` are **NOT overridden** - their status comes from upstream's native VM-capability probe, so a KVM-less or QEMU-less host honestly reports Cowork unavailable (with the actionable reason) instead of failing at VM spawn
- **The bundled `resources/virtiofsd` fallback is Ubuntu-22.04-only** (verified v1.17377.2: `Uoi()`'s upstream `os-release id==="ubuntu" && versionId.startsWith("22.")` gate) - on every other distro, incl. Arch/Fedora/NixOS, `virtiofsdPath` resolves to `null` unless a *system* `virtiofsd` exists at one of the probed absolute paths. `claude-desktop --diagnose`'s Cowork replica previously checked the bundled path unconditionally (missing that gate), so it could report a false "SHOULD pass" that disagreed with the real in-app probe on non-Ubuntu-22.04 hosts ([#177](https://github.com/patrickjaja/claude-desktop-bin/issues/177), fixed alongside the new NixOS `/run/current-system/sw/bin/virtiofsd` candidate).

### Dispatch on Linux (upstream-native — patch removed)

Dispatch is a remote task orchestration feature that lets you send tasks from your phone to your desktop. It's built on top of the Cowork sessions infrastructure and uses Anthropic's "environments bridge" API.

**Architecture:** Desktop registers with `POST /v1/environments/bridge`, then long-polls `GET /v1/environments/{id}/work/poll` for incoming work from the mobile client. All traffic routes through Anthropic's servers over TLS — no inbound ports needed.

**Status (v1.17377):** `fix_dispatch_linux.nim` has been **removed**. Dispatch works on Linux with no patch — live-tested by sending a task from phone to desktop and receiving the rendered response. Over several releases upstream shipped every piece the patch used to force. For the historical record, the patch used to change:
1. **Sessions-bridge init gate** (flags `3572572142` + `4201169164`) — forced the combined init gate ON; now inits on Linux natively.
2. **Remote session control** (flag `2216414644`) — bypassed the `channel:"mobile"` throw; now permitted on Linux.
3. **Platform label** — added `case"linux":return"Linux"`; upstream now returns "Linux" via a ternary.
4. **Telemetry gate** — extended the darwin||win32 gate to Linux; upstream dropped the platform gate entirely.

If a future release breaks phone→desktop Dispatch on Linux, re-check these four before re-introducing a patch.

**Note on `operon` (Nest):** Completely removed in v1.6608.0. Previously required VM infrastructure (120+ IPC endpoints across 31 sub-interfaces). See [Operon Tool Inventory](#operon-tool-inventory-v11062) below for the historical model-facing toolset.

**No patching needed for:**
- Keep-awake (`powerSaveBlocker`) — works on Linux via Electron API
- Bridge state persistence — uses `userData` path, works on Linux
- CCR transport — pure HTTP/SSE, platform-agnostic
- OAuth configs — same endpoints for all platforms

### Remote Orchestrator ("Manta Desktop") — new in v1.1.8629

The **Remote Orchestrator** (codename "manta", flag `4201169164` / `yukon_silver_manta_desktop`) is an alternative to local Cowork. Instead of running a local `cowork-svc` process, it connects to Anthropic's cloud infrastructure via WebSocket (`wss://bridge.claudeusercontent.com`) to run Cowork/Dispatch sessions remotely.

**Flow:**
1. Calls `findOrchestrationRemoteEnvironment()` → looks for an `anthropic_cloud` environment via `/v1/environments`
2. Creates a CCR (Claude Code Remote) session on Anthropic's servers
3. Connects via WebSocket bridge (`/v2/ccr-sessions/devices/{org}_{account}/mcp`)
4. Skips local env registration & work polling — the cloud handles it

**Three ways to enable:**
1. GrowthBook flag `4201169164` — server-side, not enabled for Linux users
2. Env var `CLAUDE_COWORK_FORCE_REMOTE_ORCHESTRATOR=1` — force override
3. Developer setting `isMantaDesktopEnabled` (requires restart)

**Sessions-bridge gate interaction:** The sessions-bridge init gate variable `h` is now `h = f || p` where `f` = flag `3572572142` (dispatch) and `p` = flag `4201169164` (remote orchestrator). Our Patch A forces `h=!0`, which opens the gate for both features. However, the remote orchestrator has its own separate `isRemoteOrchestratorEnabled()` check — our patch doesn't force that.

**Linux status:** Not tested. The remote orchestrator bypasses the need for local `cowork-svc` entirely, which could simplify the Linux Cowork stack. However, it requires Anthropic's backend to return an `anthropic_cloud` environment, which may be limited to Pro accounts or not yet rolled out. Setting `CLAUDE_COWORK_FORCE_REMOTE_ORCHESTRATOR=1` would attempt the connection but likely fail with "No anthropic_cloud environment found" until Anthropic enables it server-side.

**Related env vars:**
- `CLAUDE_COWORK_FORCE_REMOTE_ORCHESTRATOR` — force enable remote mode
- `CLAUDE_REMOTE_TOOLS_BRIDGE_URL` — override WebSocket bridge URL (default: `wss://bridge.claudeusercontent.com`)

### Operon Tool Inventory (v1.1617.0)

When Operon is active (flag `1306813456`), the model gets access to a rich toolset organized in 4 categories. These are **NOT MCP tools** — they are dispatched through Operon's internal `_executeBrainTool()` / `_executeComputeTool()` routing, not the MCP protocol.

#### Brain Tools (`d3e` routing table, built via `Z0()`)

**Tool Router** (routed via `_handleX` methods):

| Tool | Handler | Status |
|------|---------|--------|
| `ask_user` | `_handleAskUser` | Active |
| `search_agents` | `_handleSearchAgents` | Active |
| `search_skills` | `_handleSearchSkills` | Active |
| `create_skill` | `_handleCreateSkill` | Active |
| `generate_plan` | `_handleGeneratePlan` | Active |
| `update_step_status` | `_handleUpdateStepStatus` | Active |
| `render_dashboard` | `_handleRenderDashboard` | **DISABLED** — `"disabled pending sandbox hardening (T12421, mitigation 25263)"` |
| `patch_dashboard` | `_handlePatchDashboard` | **DISABLED** — same sandbox hardening gate |
| `read_dashboard` | `_handleReadDashboard` | Active |
| `request_network_access` | `_handleRequestNetworkAccess` | Active |
| `request_host_access` | `_handleRequestHostAccess` | Active |

**Delegator** (multi-agent orchestration, also in `RNn` table):

| Tool | Handler | Description |
|------|---------|-------------|
| `delegate_to` | `_handleDelegation` | Delegate task to another agent |
| `delegate_subtask` | `_handleSubtaskDelegation` | Spawn a subtask to an agent |
| `stop_child` | `_handleStopChild` | Stop a child agent |
| `wait_for_notification` | `_handleWaitForNotification` | Wait for async notification from child |

All brain tools are collected in the `L$n` array as Anthropic-format tool schemas (with `input_schema`).

#### Compute Tools (`u3e` array, with `parameters` + `handler`)

| Tool | Variable | Description |
|------|----------|-------------|
| `bash` | `LPn` | Shell command execution |
| `python` | `FPn` | Python code execution (via `I5e()`) |
| `r` | `UPn` | R code execution |
| `save_artifacts` | `t6n` | Save output artifacts |
| `manage_environments` | `d6n` | Manage compute environments |
| `manage_packages` | `f6n` | Manage installed packages |
| `fetch_article_fulltext` | `N6n` | Fetch full text of a web article |

Special handling set `SNn`: `python`, `r`, `manage_environments`, `manage_packages`.

#### Dynamic Tool

| Tool | Description |
|------|-------------|
| `skill` | Dynamically built via `Z0()`, pushed into `_computeTools`. Handled in both `_executeLocalTool` and `_executeComputeTool` |

#### Internal LLM Tools (not model-facing — forced `tool_choice` in internal calls)

| Tool | Variable | Purpose |
|------|----------|---------|
| `report_input_files` | `hNn` | Identify all input files read during code generation |
| `select_relevant_inputs` | `mNn` | Select which inputs contributed to outputs |
| `summarize_conversation` | `zer`/`vvn()` | Context compaction / conversation summarization |
| `create_work_item` | `Izn` | Create structured work items from context |

These are never exposed to the user-facing model. They are used by Operon internally with forced `tool_choice:{type:"tool",name:"..."}`.

#### Anthropic API Built-in Tool

| Tool | Type ID | Gating |
|------|---------|--------|
| `web_search` | `web_search_20250305` | `enable_web_search` flag |

Not an MCP or Operon tool — passed directly in the API request as `{type:"web_search_20250305",name:"web_search"}`. Referenced in the `Nzn` exclusion set: `new Set([...u3e.map(t=>t.name),"skill","request_network_access","request_host_access","tool_search_tool_regex","code_execution","web_search","web_fetch"])`.

#### Cowork Command (not a standard tool)

| Name | Description | Scope |
|------|-------------|-------|
| `context` | Show what's using your context window | `cowork` |

Defined in `ODt` array alongside `AskUserQuestion` and `ExitPlanMode`. UI command, not a tool-use tool.

### Operon Sub-Interfaces (v1.1617.0)

33 sub-interfaces (unchanged from v1.1348.0):

`OperonAgentConfig`, `OperonAgents`, `OperonAnalytics`, `OperonAnnotations`, `OperonApiKeys`, `OperonArtifactDownloads`, `OperonArtifacts`, `OperonAssembly`, `OperonAttachments`, `OperonBootstrap`, `OperonCloud`, `OperonConversations`, `OperonDesktop` (**new**), `OperonEvents`, `OperonExportBundle`, `OperonFolders`, `OperonFrames`, `OperonHostAccess`, `OperonHostAccessProvider`, `OperonImageProvider`, `OperonMcp`, `OperonMcpToolAccessProvider` (**new**), `OperonNotes`, `OperonPreferences`, `OperonProjects`, `OperonQuitHandler`, `OperonReplay`, `OperonSDK`, `OperonSecrets`, `OperonServices`, `OperonSessionManager`, `OperonSkills`, `OperonSkillsSync`, `OperonSystem`

### Features we do NOT enable

| Feature | Reason |
|---------|--------|
| `nativeQuickEntry` | Requires macOS Swift code |
| `quickEntryDictation` | Requires macOS Swift code |
| `plushRaccoon` | Dictation shortcut, macOS-only |
| `wakeScheduler` | Requires macOS Login Items API + macOS >= 13.0 |
| `framebufferPreview` | Dev-only (PM() gate) |
| `iosSimulator` | Dev-only + macOS-only |
| `androidEmulator` | Dev-only + macOS-only |
| `grandPrix` | macOS-only, requires connected device pairs |
| `tearOffHalo` | macOS >= 13 only, uses `@ant/claude-swift` |
| `grandPrixRequest` | macOS-only, requires GrandPrix service |
| `bootstrapConfig` | Dev-only (PM() gate) |
| ~~`coworkArtifacts`~~ | **Enabled on Linux** - flag `2940196192` forced ON + merger override in `enable_local_agent_mode.nim` (**new in v1.3883.0**) |
| ~~`coworkKappa`~~ | **Enabled on Linux** - flag `123929380` forced ON + merger override in `enable_local_agent_mode.nim` |

### Known Issues (v1.3883.0)

No known issues. Computer-use is fully integrated into `index.js` since v1.1.8359 and working on Linux.

## Debugging Feature Flags

### Check if a feature is reaching the renderer

In the renderer DevTools console:
```javascript
// Features are sent via IPC - check what the renderer received
// Look for the feature-flags IPC channel in the Network/IPC tab
```

### Verify tse patch applied correctly

```bash
# After patching, search for the override string
rg 'quietPenguin:\{status:"supported"\}' /path/to/index.js
```

### Pattern anchor stability

Feature name strings are stable across versions because they're IPC identifiers used by both main and renderer processes. The `yukonSilverGems:await \w+\(\)` pattern uses the feature name as anchor and `\w+` for the minified function name.

### When updating for new versions

1. Check if `SIA` structure changed (new features added, order changed)
2. Check if PM()-wrapped features changed
3. Verify feature name strings haven't been renamed (unlikely - they're IPC contracts)
4. Test with `./scripts/validate-patches.sh`

## Version History

| Version | Static Registry | Async Merger | Gate Function | Notable Changes |
| v1.19367.0 | `yh()` | `_Be` | `NA()` | **Bump v1.18286.2 -> v1.19367.0: bundle CODE-SPLIT** (index.js -> 773-byte stub + ~45 content-hashed `index.chunk-*.js`; `index.pre.js` grew to 4.5MB and is the package.json `main`). **Minified names are now PER-CHUNK** - the flag reader is `rt()` in the big chunk (`index.chunk-CNXUb5h4.js`-era hash) but `isFeatureEnabled()` in 4 smaller chunks; never assume one canonical name. Function renames (big-chunk namespace): registry `sM()`->`yh()`, async merger `Yue`->`_Be`, dev-gate `LM()`->`NA()` (electron var `sA`->`G`), supported-constant `Ed`->`ul`; helpers `p6e`->`Mot` (yukonSilver-then-flag), `Pue`->`wBe` (epitaxyMcpApps), `wen`->`zvn` (louderPenguin), `Den`->`Vvn` (coworkWatchRecord); gate fns quietPenguin inner `Hvn` (still darwin\|\|win32), computerUse `Wvn()`/checker `I1()`/Set `Zoe` (still `new Set(["darwin","win32"])`), yukonSilver `gBe()`, Gems/GemsCache `Pot()`, chillingSlothFeat+SshShell shared `Rot()`, watchRecord `uQt()` (darwin-only), coworkKappa `Xvn()`, coworkArtifacts `eAn()`, force-ON defaults map `rDr`. **NEW: registry post-processor `tAn()`** stamps `maturity:"beta"` on supported `mvn=["chatTab","surfaceTogglesPreview","chatCodeExecution"]` (cosmetic). **+1 static feature `coworkScheduledTaskProjects`** (always supported `ul`, in Zod schema) -> 42 schema keys; none removed. Merger shape unchanged (5 overrides + 6th `ct().overlayApplied()` slot). **GrowthBook delta: +3 / -0** (`1544796833` session-concurrency value config, `2016258596` device-tool artifact read gate, `416245092` GPU crash-streak marker default-ON); louderPenguin still `4116586025`. All 13 active forced flag IDs have IDENTICAL old-vs-new counts; `1496676413` still absent (reappearance guard holds); imagine IDs `3444158716`/`3516166472`, chicago `2486083521`, spaceMemoryBridge `1197768857` all present at same counts. `manta=off` literal + `dramatic_shrimp` my-access capability unchanged (issue-186 state holds). No new force-ON entries needed. |
| v1.18286.0 | `sM()` | `Yue` | `LM()` | **Bump v1.17377.2 -> v1.18286.0 (full re-minify; v1.17377.x had kept the v1.17282 names).** Function renames: registry `xR()`->`sM()`, async merger `X0A`->`Yue`, flag reader `et()`->`rt()`; helpers `W3e`->`p6e` (yukonSilver-then-flag), `kge`->`Pue` (epitaxyMcpApps), `cZi`->`wen` (louderPenguin), `lZi`->`Den` (coworkWatchRecord). Merger shape unchanged (`n={louderPenguin:A,coworkKappa:e,coworkArtifacts:t,epitaxyMcpApps:r,coworkWatchRecord:i};return{...sM(),...n}`). **GrowthBook delta: +8 / -4.** Added: `17519066` (external-browser URL block), `1972091654` (askClaude device RPC), `2229805612` (remote_control_at_startup default), `2309422447` (mergeMessageBufferIfActive), `2795002549` (Projects OAuth scopes), `3602524236` (isOpenInDefaultAppEnabled file preview), `4034153053` (isEpitaxyPreviewEnabled, gated on native support probe), `4293378213` (device-app tools, inert: `&&!1`). None gates a cowork/code/Linux surface - no forcing needed. Removed: `1496676413` (SSH remote MCP/plugin passthrough -> **unconditional**, no replacement: `createSpawnFunction` lost the flag arg, `resolveSshControllerForMcp` unconditional -> **enable_local_agent_mode Patch 3n deleted**, EXPECTED_PATCHES 20->19 + reappearance guard), `1609612026` (marketplace download/backfill -> unconditional), `1997559319` (onUserDialog refusal fallback -> unconditional), `3792010343` (CCD tool-use summaries dropped; env reads only `66187241`). All 13 remaining forced flag IDs present with healthy counts; Patch 1b yukonSilver guard, 7-key merger override, preferences defaults, and header-unspoofed guard all verified. **CU gate family refactor** (fix_computer_use_linux Patches 6/11/12 re-anchored): old isEnabled/rj pair merged into `wS()` (pref-respecting) / `bue()` (flag `2486083521`-gated, pref-ignoring; flag pre-existing) / `dq()` (stub-mode nudge); `handleToolCall` body extracted into `vgn()` with teach-mode telemetry; wrapper gained an AbortController `setTimeout`. Platform set still `new Set(["darwin","win32"])`. |
| v1.17282.0 | `xR()` | `X0A` | `LM()` | **Bump v1.15962.x -> v1.17282.0 (full re-minify + feature churn).** Function renames: registry `QR()`->`xR()`, async merger fn `HSA`->`X0A`, flag reader `it()`->`et()`; dev-gate `gM()`->`LM()` (`function LM(A){return sA.app.isPackaged?{status:"unavailable"}:A()}`, electron var `aA`->`sA`); supported-constant `AB`->`Ed`. Gate-fn renames: yukonSilver `Uae()`->`Nge()`, yukonSilverGems `T3e()`->`j3e()`, coworkKappa `O6r()`->`BZi()`, coworkArtifacts `x6r()`->`QZi()`, artifactsPane `Fae()`->`vge()`, chillingSlothFeat `y6r()`->`V3e()`. **Registry: +`chillingSlothSshShell` (`V3e()` -> `{status:"supported"}`, no gate; same getter as `chillingSlothFeat`, which lost its darwin/win32 gate), +`coworkWatchRecord` (`yHt()`, darwin-only -> unsupported on Linux; async override in `X0A`), +`spaceMemoryBridge` (`et("1197768857")?Ed:{status:"unavailable"}`, GrowthBook-gated, no platform check); -`markTaskComplete` (REMOVED — gone from registry, merger, Zod schema, and force-ON defaults map).** Async merger now `n={louderPenguin:A,coworkKappa:e,coworkArtifacts:t,epitaxyMcpApps:r,coworkWatchRecord:i};return{...xR(),...n}` (5 overrides; `markTaskComplete:i` slot dropped, `coworkWatchRecord` added; a 6th `Promise.all` slot `pt().overlayApplied()` is consumed separately). **GrowthBook delta:** 7 added (`1197768857` spaceMemoryBridge; `1295378343` `gapSurviveEnabled` value flag, default OFF; `130970054`; `1569828280` binary-asset-fetch gate; `2431502897` model-policy map entry; `3778159589` device-stale-relogin; `629684104` assistant-error-recovery), 5 removed (`1802019210` cowork plugin upload migration; `1985784543`; `3110209724`; `3732274605` markTaskComplete; `4018578026`). **No new force-ON entries needed** — none of the new features is mandatory for Linux, and `coworkWatchRecord` is macOS-only (must NOT be force-enabled on Linux). `enable_local_agent_mode.nim` left unchanged; its `markTaskComplete` override/force-ON (Patch 3e) is now a vestigial no-op targeting the removed feature/flag. |
| v1.15962.0 | `QR()` | `HSA` | `gM()` | **Bump v1.15200.0 -> v1.15962.0 (full re-minify).** Routine re-minify; **no new/removed static features**, merger shape unchanged (`n={louderPenguin:A,coworkKappa:e,coworkArtifacts:t,markTaskComplete:i,epitaxyMcpApps:r};return{...QR(),...n}`, 6-slot `Promise.all` with the 6th `yt().overlayApplied()` as before). Function renames: registry `z_()`->`QR()`, async merger `yDA`->`HSA`, dev-gate `HR()`->`gM()` (`function gM(A){return aA.app.isPackaged?{status:"unavailable"}:A()}`, electron var `aA` unchanged), flag reader `nt()`->`it()` (storage `Zf`->`Ih`). **Cowork (`yukonSilver`) support fn renamed `$oe()`->`Uae()`** (delegate chain + leading `var r,n;` hoist retained - `enable_local_agent_mode.nim` Patch 1b's `nhPatternZce` still matches; Patch 1's sole gate fn is now `M6r()`). **GrowthBook delta:** 4 added (`144158705` LAM remote folder-access consent network call; `3377630395` overlay/window mount toggle; `3531779070` agent-mode `thinking-display:"summarized"` CLI arg; `3555657854` org-scoped plugin-bridge MCP config loading), 1 removed (`2232207471` CLI governor session cap). None of the new flags is darwin/win32-gated or gates a cowork/code/dispatch/skill surface -> no forcing needed, override list unchanged. All 15 forced flag IDs + all 12 merger override feature names still present; `enable_local_agent_mode.nim` all anchors match (24/24 + mainmodule). **3 patches fixed for re-minify drift** (`fix_quick_entry_cli_toggle` focus-branch call gained an arg; `fix_window_bounds` new post-`MAIN_WINDOW` setup call; `fix_cowork_linux` Patch G smol-bin gate wrapped in a GrowthBook-await comma-expr) -> 49 index.js patches, all apply. `.electron-version` stays 42.0.0. |
| v1.15200.0 | `z_()` | `yDA` | `HR()` | **Bump v1.14271.0 -> v1.15200.0 (full re-minify).** Routine re-minify; **no new/removed static features**, merger shape unchanged (`n={louderPenguin:A,coworkKappa:e,coworkArtifacts:t,markTaskComplete:i,epitaxyMcpApps:r};return{...z_(),...n}`). Function renames: registry `D_()`->`z_()`, async merger `PwA`->`yDA` (`const yDA=async()=>{const[A,e,t,i,r]=await Promise.all(...)}`), dev-gate `pR()`->`HR()` (`function HR(A){return aA.app.isPackaged?{status:"unavailable"}:A()}`, electron var `sA`->`aA`), flag reader now `nt()`. **Cowork (`yukonSilver`) support fn renamed `hre()`->`$oe()`** and gained a leading `var r,n;` hoist before the `const A=...` delegate chain - `enable_local_agent_mode.nim` Patch 1b's `nhPatternZce` updated to allow the optional `var <ids>;` (Linux early-return injected before the hoist; vars unused on Linux path, harmless); all 25 sub-patches apply. **GrowthBook delta:** 3 added (`2051751800` Chrome permission-mode `skip_all_permission_checks` resolver gate; `2726556121` SSH file-transfer fast-path *disable* gate - guarded `!nt(...)`; `3982397363` stale-model-clear robustness toggle), 0 removed. None gates a cowork/code/dispatch/skill surface -> no forcing needed, override list unchanged. All 15 forced flag IDs + all 12 merger override feature names still present. **1 patch fixed for re-minify drift** (`enable_local_agent_mode` yukonSilver `var` hoist) + `fix_enterprise_config_linux` ("Enterprise config loaded" log renamed to "Managed config loaded", nested redact arg `yXA(zJ(l))`) -> 52 patches, all apply. Plus a build-script fix: node-pty 1.2.0-beta.13 dropped the `build/Release/` dir for a `prebuilds/` layout, so `build-patched-tarball.sh` now `mkdir -p`s the dest. |
| v1.14271.0 | `D_()` | `PwA` | `pR()` | **Bump v1.13576.4 -> v1.14271.0 (~700 builds, full re-minify).** Routine re-minify; **no new/removed static features**, merger shape unchanged (`n={louderPenguin:A,coworkKappa:e,coworkArtifacts:t,markTaskComplete:i,epitaxyMcpApps:r};return{...D_(),...n}`). Function renames: registry `nR()`->`D_()` (was `sR()` at v1.13576.0; the `.4` build had already re-minified to `nR()`), dev-gate `eM()`->`pR()` (electron var `lA`->`sA`), flag reader `dt()`->`ot()` (storage `Qh`->`Uf`). **GrowthBook delta:** 2 added (`1947305033` gates `create_artifact`/`update_artifact` tools - "...not enabled on this device" + `gate_off` telemetry; `2438134137` Figma/design OAuth `user:design:read user:design:write` scope expansion), 0 removed. Neither new flag is darwin/win32-gated -> no Linux impact, no forcing needed. `enable_local_agent_mode.nim` override list + all 25 sub-patches match unchanged; the patch overrides at the merger level (no embedded Zod schema to revalidate). All 12 merger override feature names still present. **2 patches fixed for re-minify drift** (`fix_cowork_linux` C2 deref-var backreference `r`->`i`; `fix_browser_tools_linux` 3 sub-patches rewritten for a real native-host install refactor) -> 51 patches, all apply. |
| v1.13576.0 | `sR()` | `c0A` | `rM()` | **Major bump v1.12603.1 -> v1.13576.0 (~970 builds, full re-minify).** **2 new static features:** `iosSimulatorH264:rM(GYA)` and `quickEntryGlobalShortcut:g3i()` -> **39 static + `louderPenguin` async-only + 4 other async (`coworkKappa`/`coworkArtifacts`/`markTaskComplete`/`epitaxyMcpApps`) = 44 total**; no features removed. Async merger shape unchanged (`{...sR(),louderPenguin:A,coworkKappa:e,coworkArtifacts:t,markTaskComplete:r,epitaxyMcpApps:i}`). Function renames: registry `aD()`->`sR()`, merger `fSA`->`c0A`, dev-gate `vR()`->`rM()` (`function rM(A){return lA.app.isPackaged?{status:"unavailable"}:A()}`, electron var `cA`->`lA`), flag reader `dt()`->`Ct()`. **Cowork (`yukonSilver`) gate refactored:** registry entry now `yukonSilver:Zce()` where `Zce()` delegates to `Q3i()`/`C3i()` and `C3i()` HARDCODES `const A="win32"` for the VM-bundle arch lookup (`fo.files["win32"][arch]`) - the old `const X=process.platform;if(X!=="darwin"&&X!=="win32")...unsupported_platform` form is GONE. `enable_local_agent_mode.nim` Patch 1b rebased to inject the Linux early-return into `Zce()`'s delegate-chain; all 25 sub-patches apply. **GrowthBook delta vs v1.12603.0 baseline:** 3 added (`1703762832` onModelRefusalFallback retry [already in v1.12603.1], `1985784543` an `isEnabled` gate, `3646818354` `shouldKillOnIdlePause`), 0 removed. `enable_local_agent_mode.nim` 12-flag override list unchanged (none of the new flags is darwin/win32-gated). 7 patches fixed + 1 removed (`fix_office_addin_linux` - its connected-file-detection platform gate was dropped upstream) -> 50->49 patches; all apply. |
|---------|----------------|--------------|---------------|-----------------|
| v1.1.3770 | `Oh()` | `mC()` | `QL()` | louderPenguin async override added, ccdPlugins via Kf() spread |
| v1.1.3918 | `Fd()` | `mP` | `o_e()` | chillingSlothEnterprise moved to static, mP simplified to louderPenguin only, ccdPlugins inlined, chillingSlothLocal unconditional |
| v1.1.4328 | `nh()` | `rO` | `Ebe()` | No structural changes; formatMessage calls now include `id` field; function renames only |
| v1.1.7053 | `Kh()` | `$M` | `Qwe()` | New `floatingAtoll` feature (always unavailable); function renames only; 14 features total |
| v1.1.7464 | `rp()` | `zM` | `$Se()` | No structural changes; Dispatch infrastructure added (separate GrowthBook gates); function renames only |
| v1.1.7714 | `fp()` | `cN` | `r1e()` | New `yukonSilverGemsCache` (15 features); `Jr()`→`Vr()` flag function; logger `T`→`C`; `computer-use-server.js` removed; Quick Entry position-save added; two Linux guards removed upstream |
| v1.1.8359 | `lA()` | `jY` | `Kge()` | New `operon` (Nest) feature (16 features, 2 async overrides); `Vr()`→`Qn()` flag reader; new GrowthBook flags: `1306813456` (operon), `2051942385` (CIC can-use-tool), `720735283` (marketplace migration), `748063099` (VM pipe retry); removed flags: `1143815894`, `2339607491`; Operon adds 120+ IPC endpoints across 18 sub-interfaces but currently unavailable on Linux |
| v1.1.8629 | `dA()` | `JX` | `Oet()` | New GrowthBook flag `4201169164` (remote orchestrator / "manta"); `Qn()`→`Hn()` flag reader; `Bx()`→`Hk()` listener; sessions-bridge gate changed from single var to triple (`let f,p,h; h=f\|\|p`); 16 new i18n locale files; no structural changes to feature flag architecture |
| v1.1.9134 | `rw()` | `yre` | `Kge()` | New `wakeScheduler` feature (17 total); `operon` now in static registry too (`Ztn()` returns unavailable); `chillingSlothFeat` darwin gate removed upstream; `jtn()` has native Linux support; `Hn()`→`kn()` flag reader; `Hk()`→`bC()` listener; `xy()`/`$o()`→`_b()`/`js()` value flags; 4 new GrowthBook flags; 1 removed (`3196624152` Phoenix Rising); `$s` variable with `$` in mainView.js preload |
| v1.1.9669 | `_b()` | `Cie` | `fve()` | **New `computerUse` feature** (18 features, 2 async overrides); `chillingSlothFeat` darwin gate re-introduced; `Vn()` flag reader; `wR()` listener; `j1()`/`Js()` value flags; new flags: `3691521536` (stealth updater), `3190506572` (Chrome perms); remote orchestrator (`4201169164`) removed from GrowthBook (hardcoded off); Promise.all pattern in async merger |
| v1.2.234 | `Uw()` | `Lse` | `I_e()` | Same 18 features; `fn()` flag reader; computer-use platform gate now Set-based (`ese = new Set(["darwin","win32"])`); `operon` static entry unconditionally unavailable (`$gn()`), async override adds 5s delay; `floatingAtoll` state sync via new GrowthBook flag `1985802636`; read_terminal server now natively supports Linux; 38+ GrowthBook flags |
| v1.569.0 | `$w()` | `tse` | `V0e()` | Same 18 features; `Sn()` flag reader; `chillingSlothEnterprise` spelling fixed (was `chillingSlottEnterprise` in earlier builds); async merger `$w()` uses `$` in name (required `[\w$]+` regex fix in patch); 3 new GrowthBook flags (`286376943`, `1434290056`, `2392971184`); `1143815894` re-added; several dispatch-era flags removed from boolean calls |
| v1.1062.0 | `Ow()` | `xse` | `m0e()` | Same 18 features (17 static + louderPenguin async); `rn()` flag reader; function renames only; 2 new GrowthBook flags (`2114777685` cowork CU-only mode, `3371831021` cuOnlyMode); 6 dispatch-era flags removed (`3558849738`, `3572572142`, `4201169164`, `1585356617`, `2199295617`, `2860753854`); HTTP header pattern changed (`,` separator instead of `;` — fixed in patch) |
| v1.1348.0 | `gb()` | `eoe` | `Kwe()` | Same 18 features; `tn()` flag reader; `LI()` listener; `js()`/`$b()` value flags; `floatingAtoll` now preference-gated (`$wn()` reads `floatingAtollActive`); 1 new boolean flag (`4040257062` memory routing); 3 new value flags (`254738541` prompt, `4066504968` setup-cowork, `365342473` telemetry scrub); 2 removed (`927037640` subagent model, `3190506572` Chrome perms); Operon 31→33 sub-interfaces (`OperonDesktop`, `OperonMcpToolAccessProvider`); all 34 patches applied without modification |
| v1.1617.0 | `wb()` | `Soe` | `bbe()` | Same 18 features; `rn()` flag reader; `ZI()` listener; `Gs()`/`Db()` value flags; no new/removed GrowthBook flags; platform gate `z5e`→`g5e`; new `radar` MCP server (disabled); 3 force-ON flags (`2976814254`, `3246569822`, `1143815894` in `m6r` map); new renderer windows (`buddy_window/`, `find_in_page/`); new deps (`node-pty`, `ws`); all 35 patches applied without modification |
| v1.2278.0 | `eA()` | `yue` | `CEe()` | Same 18 features; `Zr()` flag reader; `VI()` listener; `xs()`/`_A()` value flags; `chillingSlothFeat` gate changed `g5e`→`IOe` (darwin\|\|win32, was darwin-only); platform booleans `hi`/`vs`/`IOe`; 5 new boolean flags (`286376943`, `1434290056`, `2345107588`, `2392971184`, `2725876754`); 1 new value flag (`1893165035` SDK error auto-recovery); new `index.pre.js` bootstrap file with enterprise config; enterprise config switched from switch/case to ternary; 3 patches updated (`fix_cowork_first_bash.py`, `fix_cowork_linux.py`, `fix_enterprise_config_linux.py`) |
| v1.2581.0 | `iA()` | `jue` | `XEe()` | **New `coworkKappa` feature** (19 features, 3 async overrides); `Yr()` flag reader; platform vars `_s`/`c3e`; async merger now 3-way `Promise.all` (louderPenguin + operon + coworkKappa); 1 new flag (`123929380` coworkKappa/consolidate-memory); 1 removed flag (`4040257062` memory path routing); `fix_tray_dbus.py` updated (`[\w$]+` for tray variable with `$`) |
| v1.2773.0 | `Hb()` | `Mle` | `G1e()` | Same 19 features; `Wr()` flag reader; `QR()` listener; `us()`/`cA()` value flags; platform vars `pi`/`vs`/`r6e`; `chillingSlothFeat` gate changed from `process.platform!=="darwin"` to `r6e` (darwin\|\|win32); `floatingAtoll` now always supported (`Rkn()` unconditional, was preference-gated); 4 new flags (`919950191` LAM tool search, `2140326016` author stubs error, `2216480658` VM outputs, `3858743149` maxThinkingTokens); 3 removed flags (`1585356617` epitaxy, `2199295617` AutoArchive, `4201169164` remote orchestrator); MCP registration `One()`→`ooe()`; computer-use Set `ese`→`ele`; all patches compatible |
| v1.3036.0 | `nA()` | `ode` | `ESe()` | Same 19 features; `Wr()` flag reader unchanged; `Xk()` listener (was `QR()`); `fs()`/`wA()` value flags (was `us()`/`cA()`); platform vars `hi` (darwin, unchanged)/`xce` (win32, was `vs`)/`UMe` (darwin\|\|win32, was `r6e`); 4 new flags (`658929541` LAM setModel buffer, `1496450144` CLAUDE_CODE_ENABLE_TASKS, `2800354941` plugin/skill sort, `2815031518` LocalSessionMgr setModel buffer); 3 removed flags (`159894531` ENABLE_TOOL_SEARCH, `919950191` LAM tool search, `2678455445` MCP SDK server mode); MCP registration `ooe()`→`kce()`; **Patch 3c removed from `enable_local_agent_mode.py`** — upstream dropped the Desktop-side ENABLE_TOOL_SEARCH="false" override, user settings.json now passes through; all other patches compatible |
| v1.3109.0 | `J0()` | `ewA` | `aFA()` | Same 19 features; **webpack re-minify only — no GrowthBook flag additions/removals, no new MCP servers, no new IPC handlers, no new `process.platform` gates vs v1.3036.0**; `Wr()`→`Ti()` flag reader; `Xk()`→`wG()` listener; `fs()`/`wA()`→`Es()`/`di()` value flags; platform vars `hi`→`en` (darwin), `xce`→`ws` (win32), `UMe`→`WhA` (darwin\|\|win32); MCP registration `kce()`→`DfA()`; dispatch IPC bridge re-minified (`rjt` item `s→n`, auto-wake session `n→i`, notification `s→n`, child session `e→A`, index `r→t`, logger `B/P→M`) — `fix_dispatch_linux.py` sub-patches F and J updated with `[\w$]+` captures; all 41 patches compatible without regex changes elsewhere |
| v1.3561.0 | `A_()` | `gwA` | `GGA()` | Same 19 features; `Ti()`→`fi()` flag reader; `wG()`→`bG()` listener; `Es()`/`di()`→`zn()`/`f_()` value flags; platform vars `en` unchanged (darwin), `ws`→`ys` (win32), `WhA`→`bfA` (darwin\|\|win32); MCP registration `DfA()`→`gpA()`; computer-use Set `ele`→`rwA`, checker `Jne()`→`nBA()`; 2 new GrowthBook flags (`1496676413` SSH plugins, `2023768496` trusted device); `123929380` added to force-ON defaults; locale i18n moved to `ion-dist/i18n/` with `.overrides.json`; all 42 patches compatible without regex changes |
| v1.3883.0 | `s_()` | `FwA` | `lUA()` | **New `coworkArtifacts` feature** (20 features, 4 async overrides); `Ii()` flag reader; `FG()` listener; `y_()`/`zn()` value flags; async merger now 4-way `Promise.all` (louderPenguin + operon + coworkKappa + coworkArtifacts); 2 new GrowthBook flags (`2049450122` session handoff, `2192324205` dispatch structured content forwarding); locale i18n JSONs removed from app.asar (moved to resources/ alongside asar); upstream `rjt()` message filter expanded (adds dispatch tool name variables `SU`/`T4` behind a gate parameter — `fix_dispatch_linux.nim` Patch F updated to match new pattern); new `@ant/claude-swift` module (macOS-only, no Linux impact); `@ant/claude-native-binding.node` bundled in asar; MCP registration `gpA()`→`FpA()`; 1 patch updated (`fix_dispatch_linux.nim`); 41 patches compatible without changes |
| v1.4758.0 | `d_()` | `$yA` | `yFA()` | **2 new features:** `chillingSlothPool` (GrowthBook `1992087837`), `markTaskComplete` (GrowthBook `3732274605`) → 22 features, 5 async overrides; `louderPenguin` moved from static to async-only; `zt()` flag reader; `backgroundThrottling:!1` removed from webPreferences (upstream default now used); `process.resourcesPath` removed from `index.pre.js`; `checkTrust`/`saveTrust` gained `DQ()` path expansion; CU teach overlay gate moved before TCC stub (ternary); ion-dist platform enum `W`→`G`; yukonSilver `formatMessage` now called via `Qe().formatMessage` (function call before property access); 6 patches updated, all 42 compatible |
| v1.5354.0 | `v_()` | `ZDA` | `MW()` | **2 new dev-gated features:** `framebufferPreview` (VNC preview, GrowthBook `1928275548`), `iosSimulator` (macOS-only) → 24 features, 5 async overrides unchanged; `Pt()` flag reader; `fM()` listener; `Bn()` value flag reader; platform vars `Zr` (darwin), `ys` (win32), `BwA` (darwin\|\|win32); MCP registration `gpA()`→`qwA()`; 13 new boolean GrowthBook flags; 2 new value flags (`1004628546`, `3229517805`); 1 removed flag (`365342473` telemetry scrub); `1696890383` added to force-ON defaults; sessions-bridge gate variable position changed (not last in `let` decl); dispatch `openPath` gained `Tc()` wrapper; ion-dist SPA code-split (842→1612 files, 85→105 MB); 3 patches fixed (`fix_window_bounds`, `fix_dispatch_linux`, `fix_dispatch_outputs_dir`); all 44 compatible |
| v1.6259.0 | `Y_()` | `xDA` | `UO()` | **2 new macOS-only features:** `androidEmulator` (dev-gated + macOS), `grandPrix` (device pairing, macOS + GrowthBook `873030668`) → 26 features, 5 async overrides unchanged; `Jt()` flag reader; `kM()` listener; `lp()` single-value flag reader; `dn()` multi-key flag reader; platform vars `Xi` (darwin), `Ds` (win32), `ryA` (darwin\|\|win32); 3 new boolean flags (`982691970`, `1802019210`, `2307090146`); 3 new value flags (`873030668`, `1126577245`, `2921038508`); 1 removed (`839037100`); `2307090146` added to force-ON defaults; Vertex auth replaced by generic `interactiveAuth`; 18 new IPC endpoints; `desktopTopBar` now always supported; all 43 patches compatible |
| v1.6259.1 | `v_()` | `ZDA` | `MW()` | **3 features removed:** `floatingAtoll` (always supported, now gone), `androidEmulator` (dev-gated macOS), `grandPrix` (macOS-only device pairing) → 23 features, 5 async overrides unchanged; `Pt()` flag reader; `fM()` listener; `ew()` single-value flag reader; `Bn()` multi-key flag reader; platform vars `Zr` (darwin), `ys` (win32), `BwA` (darwin\|\|win32); MCP registration still `qwA()`; computer-use Set `rwA`→`qDA`; force-ON defaults map: `2307090146` removed (5→5 entries, replaced by existing); async merger helpers `DFA`→`D1A`, `j_r`→`evr`, `mFt`→`jxt`; new MCP server `"skills"` (list_skills, search_skills); new Chrome tools (browser_batch, list_connected_browsers, select_browser); update_plan removed from Chrome; new tools: mark_chapter (ccd_session), retire_card (radar), propose_skills (cowork); all 43 patches compatible |
| v1.6608.0 | `pw()` | `woA` | `pt()` | +framebufferPreview, +iosSimulator, +androidEmulator, +grandPrix, -operon; 6 flags removed → 23 static + 4 async = 27 total features; `pt()` flag reader (was `Pt()`); async merger reduced from 5→4 overrides (operon removed); 6 GrowthBook flags removed: `1306813456`, `1496450144`, `2216480658`, `2433104842`, `2486083521`, `4019128077` (all operon/CU-related); louderPenguin async check `evr()`→`Nvi()`; all 43 patches compatible |
| v1.6608.1 | `pw()` | `DoA` | `pt()` | **Webpack re-minify only** — no new/removed features or GrowthBook flags; `MW()`→`DT()` (production gate), `woA`→`DoA` (merger), `fM()`→`Cm()` (listener), `ew()`→`wr()` (single-value reader), `Bn()`→`OQ()` (multi-key reader), `Nvi()`→`vbi()` (louderPenguin async), `D1A()`→`dhA()` (cowork helper), `lrA()`→`BrA()` (MCP registration); 4 new session config keys under `1978029737`: `coworkWebFetchPrompt`, `memoryIndexSnapshotIdleMs`, `peakHoursStartPst`, `peakHoursEndPst`; all 43 patches compatible |
| v1.6608.2 | `pw()` | `DoA` | `pt()` | **No feature flag changes** — same 27 features, same function names (`pw`, `DoA`, `mT`, `ft`, `Cm`, `wr`, `OQ`); 21 new server-side GrowthBook flags observed (see "New Server-Side GrowthBook Flags in v1.6608.2"); MCP registration renames: `lrA()`→`BrA()` (already in v1.6608.1), `MG`→`I_`, `VqA`→`xSA`, `Y7()`→`pq()`; all 43 patches compatible |
| v1.7196.0 | `pw()` | `woA` | `pt()` | **No new/removed features** - same 27 features (23 static + 4 async overrides); `wr()` single-value reader removed (`pr()` now handles value reads); async merger reverted `DoA`->`woA`, MCP registration reverted `BrA()`->`lrA()`, display labels `xSA`->`FSA`; computer-use Set `QoA`->`BoA`; platform vars unchanged (`or`/`fn`/`OiA`); `pw()`, `pt()`, `Cm()`, `OQ()`, `DT()`, `Gu` all unchanged; no new GrowthBook flags; imagine `isEnabled` may gain `ccd` session type (flag `2204227020`) in future builds; `pt()` may gain pre-return telemetry call in future builds; 3 patches refreshed by @boommasterxd with forward-looking fallbacks; all 45 patches compatible |
| v1.8089.0 | `eD()` | `UcA` | `St()` | **No new/removed features** - same 25 features (23 static + 4 async overrides, 2 features removed vs v1.7196.0 total count adjustment); major renames: `pw()`->`eD()`, `woA`->`UcA`, `DT()`->`Nb()`, `pt()`->`St()`, `Cm()`->`AS()`; platform vars `or`->`Lr` (darwin), `fn`->`Io` (win32), `OiA`->`pj` (darwin\|\|win32); supported constant `saA`->`C5`; computer-use Set `QoA`->`NcA`; GrowthBook storage `Gu`->`nQ`; 6 new boolean GrowthBook flags (`245679952`, `1129419822`, `1496676413`, `2049450122`, `2192324205`, `2800354941`); 1 new non-boolean flag (`4274871493`); 1 new listener flag (`180602792` midnightOwl); 8 removed flags (`982691970`, `1802019210`, `2216480658`, `2860753854`, `3298006781`, `3858743149`, `3885610113`, `4019128077`); `2204227020` now gates Visualize for CCD sessions; new `floatingPenguinEnabled` pref; `3246569822` added to force-ON defaults (`k_i`); all 45 patches compatible |
| v1.8555.2 | `Np()` | `SIA` | `PM()` | **3 new features:** `tearOffHalo` (macOS >= 13 halo overlay), `grandPrixRequest` (darwin service requests), `bootstrapConfig` (dev-gated) - 27 total (26 static + louderPenguin async-only); major renames: `eD()`->`Np()`, `UcA`->`SIA`, `Nb()`->`PM()`, `St()`->`wt()`, `AS()`->`Bm()`, `OQ()`->`Pr()`; new `Lh()` single-value reader (reads `.value` from `CQ` storage); platform vars `Lr`->`Or` (darwin), `Io`->`mo` (win32), `pj`->`P3` (darwin\|\|win32); supported constant `C5`->`gK`; computer-use Set `NcA`->`hIA`, checker `fIA()`; GrowthBook storage `nQ`->`CQ`; force-ON defaults `k_i`->`uNi`; dispatch constant `_ht`->`mpt`; async merger helper `syA`->`ZyA`; 1 new boolean flag (`434204418` MCP non-blocking connection); 2 new listener flags (`4150329283` cloud sync drive, `2358734848` hardware buddy); 2 removed boolean flags (`658929541`, `2815031518` setModel buffer checks); 1 removed value flag (`2921038508` cowork memory guide prompt); `2940196192` added to force-ON defaults map |
| v1.12603.1 | `aD()` | `fSA` | `vR()` | **Point release on v1.12603.0** - minimal change (+446 bytes, full re-minify of the same code). **No new/removed features** - same **37 static + `louderPenguin` async-only = 38 total**. **Function renames:** static registry `sD()`->`aD()` (all other names unchanged: merger `fSA`, dev-gate `vR()`, flag reader `dt()`, supported constant `aB`, cowork helper `eYA()`, 5s-delay helper `SPt()`). **GrowthBook delta:** 1 added (`1703762832` - gates `onModelRefusalFallback` retry behavior in `AgentModeSessionManager`: when ON, a refusal response with direction `"retry"` triggers a fallback; no platform gate, purely server-side rollout), 0 removed. `enable_local_agent_mode.nim` 12-flag override list unchanged (new flag `1703762832` is a pure server-rollout behavioral flag with no platform gate - Linux is unaffected; no new darwin/win32-gated features); all 50 patches applied without modification. |
| v1.12603.0 | `sD()` | `fSA` | `vR()` | **Version bump v1.11847.5 -> v1.12603.0 (~760 builds, full re-minify).** **1 new static feature:** `artifactsPane:DPt()` (gated solely by NEW GrowthBook flag `2115990222`, no platform gate) -> **37 static + `louderPenguin` async-only = 38 total**; no features removed. **`artifactsPane` is now the FIRST key in the registry** - rg anchors using `return\{nativeQuickEntry` no longer match the registry opening; anchor on `return\{artifactsPane` or `ccdPlugins` instead. `builtinMcpPresets` changed from dev-gated `xur(()=>Bu)` to bare `aB` (always supported in the registry; production gating moved to the usage site: `NODE_ENV!=="production"\|\|desktopBootFeatures.builtinMcpPresets.status==="supported"`), so the bundle is back to a single `app.isPackaged` dev-gate function. Async merger shape unchanged: 5-way `Promise.all` -> `{...sD(),louderPenguin:A,coworkKappa:e,coworkArtifacts:t,markTaskComplete:i,epitaxyMcpApps:r}` via `Promise.all([fqr(),eYA(()=>dt("123929380")),eYA(()=>dt("2940196192")),eYA(()=>dt("3732274605")),SPt(()=>dt("3516166472"))])`. Function renames: registry `Rw()`->`sD()`, merger `PBA`->`fSA`, dev-gate `OS()`->`vR()` (`function vR(A){return cA.app.isPackaged?{status:"unavailable"}:A()}`, electron var `oA`->`cA`), flag reader `lt()`->`dt()`, GrowthBook storage `zd`->`gf`, telemetry helper `Hz`->`LAA`, listener `Vh()`->`Em()`, object reader `Vr()`->`Qn()`, NEW value-with-default reader `LC(id,default)`, supported constant `Bu`->`aB`, louderPenguin helper `Xur()`->`fqr()` (still darwin\|\|win32 gate + `await kk(),dt("4116586025")`), cowork helper `JNA()`->`eYA()`, 5s-delay helper `zQt()`->`SPt()`, yukonSilver `DZA()`->`Lae()`, quietPenguin inner `Wur()`->`Bqr()` (still the only darwin\|\|win32 fn matching Patch 1), chillingSlothFeat `Jur()`/`Qz`->`lqr()`/`cAA` (`cAA=cn\|\|zo`), force-ON defaults map `yKi`->`Vdr`, Zod feature schema `Kji` (status union `ko`, includes `artifactsPane` + all 12 patch-overridden features). **GrowthBook delta:** 4 added (`2115990222` artifactsPane gate, `2745857735` LAM folder-access requests, `884132720` oauthScope passthrough, `3932491586` VM optional mounts - read via new `LC()` reader, force-OFF in `Vdr`), 0 removed. `enable_local_agent_mode.nim` 12-flag override list unchanged (none of the 4 new flags is darwin/win32-gated, so none needs forcing for Linux; `artifactsPane` follows the `epitaxyMcpApps` precedent of leaving pure server-rollout features alone); all 50 patches applied without modification. |
| v1.11847.5 | `Rw()` | `PBA` | `OS()` | **Version bump v1.11187.4 -> v1.11847.5 (~660 builds, full re-minify).** **3 new static features:** `coworkRemoteSessionSpaces:Bu` and `coworkBranchSession:Bu` (both always supported, no platform gate, no override needed) and `epitaxyMcpApps` (static `{status:"unavailable"}` + NEW async override) -> **36 static + `louderPenguin` async-only = 37 total**; no features removed. **Async merger now 5-way** `Promise.all`: `{...Rw(),louderPenguin:A,coworkKappa:e,coworkArtifacts:t,markTaskComplete:i,epitaxyMcpApps:r}` via `Promise.all([Xur(),JNA(()=>lt("123929380")),JNA(()=>lt("2940196192")),JNA(()=>lt("3732274605")),zQt(()=>lt("3516166472"))])`. Function renames: registry `Dw()`->`Rw()`, async merger `SBA`->`PBA`, dev-gate `MS()`->`OS()` (`function OS(A){return oA.app.isPackaged?{status:"unavailable"}:A()}`, electron var `sA`->`oA`; 2nd dev-gate `xEr()`->`xur()` for `builtinMcpPresets`), `louderPenguin` async helper `XEr()`->`Xur()` (still `darwin\|\|win32` gate + `await pR(),lt("4116586025")`), cowork helper `mNA()`->`JNA()` (5s delay now in inner `zQt()`), supported constant `_d`->`Bu`; GrowthBook bool reader `lt()` unchanged; `quietPenguin` inner `Wur()` is the only darwin\|\|win32 feature fn (1 match for Patch 1); `chillingSlothFeat:Jur()` uses `Qz` variable gate. **GrowthBook delta:** 73 distinct boolean flag IDs (was 68); 8 added (`3516166472` epitaxyMcpApps/MCP-apps + `/epitaxy` side-chat, `1109029378` macOS tray usage menu, `1936081873` system-prompt build-skip, `1997559319` refusal_fallback_prompt dialog kind, `2232207471` CLI governor session cap, `2724639973` CLI governor eviction, `3633961296` plugin enabled-state backfill, `3807767338` policy-limits session seeding), 1 removed (`3638165567`). `enable_local_agent_mode.nim` 12-flag override list unchanged (all 25 sub-patches match; `epitaxyMcpApps` intentionally NOT forced on - experimental, not needed for Linux Cowork/Code/Agent-Mode). 1 patch fixed this release (`fix_claude_code` getStatus - upstream added `||await this.getHostPreseedInPlacePath()` to the first if-condition), all 48 applied. |
| v1.11187.4 | `Dw()` | `SBA` | `MS()` | **Version bump v1.10628.2 -> v1.11187.4 (~560 builds, full re-minify).** **1 new static feature** `coworkArtifactPopout:_d` (always supported, no platform gate, no override needed) -> **33 static + `louderPenguin` async-only = 34 total**; no features removed. Merger return identical shape: `{...Dw(),louderPenguin:A,coworkKappa:e,coworkArtifacts:t,markTaskComplete:i}` via `Promise.all([XEr(),mNA(()=>lt("123929380")),mNA(()=>lt("2940196192")),mNA(()=>lt("3732274605"))])`. Function renames: registry `Aw()`->`Dw()`, async merger `LCA`->`SBA`, dev-gate `Dm()`->`MS()` (`function MS(A){return sA.app.isPackaged?{status:"unavailable"}:A()}`, electron var `aA`->`sA`; 2nd dev-gate `xEr()` used only by `builtinMcpPresets`), `louderPenguin` async helper `Fsr()`->`XEr()` (still `darwin\|\|win32` gate, now also `await IR(),lt("4116586025")`), cowork helper `pRA()`->`mNA()`, GrowthBook bool reader `It()`->`lt()`, supported constant `Xd`->`_d`. `bootstrapConfig` changed from `MS()`-gated to bare `_d` (always supported); `desktopTopBar:ZEr()` unconditional `{status:"supported"}`. **GrowthBook delta** (vs v1.9659.4, the only local prior bundle - spans the full jump): 5 added (`124685897` template-subst, `1323782925` APe qualifier, `1609612026` marketplace install, `2720310975` side-chat tools, `790863764` device_bash), 1 removed (`3638165567`). `enable_local_agent_mode.nim` 12-flag override list unchanged (all 25 sub-patches match; both new chat features still in the Zod `.partial()` schema); 2 patches fixed this release for refactored code (`fix_utility_process_kill`, `fix_asar_folder_drop` Patch B), all 48 applied. |
| v1.10628.2 | `Aw()` | `LCA` | `Dm()` | **Webpack re-minify point release on v1.10628.0** (v1.10628.1 not observed on the public download channel) - same **32 static + `louderPenguin` async-only = 33 total**, identical static feature names (`claudeDesignWindow`/`builtinMcpPresets` both retained, none added/removed), merger return identical (`{...Aw(),louderPenguin:e,coworkKappa:A,coworkArtifacts:t,markTaskComplete:i}` via `Promise.all([Fsr(),pRA(()=>It("123929380")),pRA(()=>It("2940196192")),pRA(()=>It("3732274605"))])`); **unusually light re-minify - most function names held:** registry `Aw()`, async merger `LCA`, dev-gate `Dm()` (`function Dm(e){return aA.app.isPackaged?{status:"unavailable"}:e()}`, electron var `aA`), `louderPenguin` async helper `Fsr()` (still `darwin\|\|win32` gate), cowork helper `pRA()`, GrowthBook bool reader `It()`, computer-use Set `MCA` (`new Set(["darwin","win32"])`, `MCA.has(process.platform)`), win32 var `ro`, darwin\|\|win32 var `O$` all unchanged from v1.10628.0; renamed only: supported constant `XQ`->`Xd` (`{status:"supported"}`), chatTab/chatCodeExecution gate fns `R6e`->`R5e`/`M6e`->`M5e`, cowork 5s-delay helper `u9e`->`u6e`, yukonSilver `WjA`->`W8A`, `zKA`->`z1A`, `$jA`->`$8A`, tray fn `Y6A`->`Y5A` / tray var `VE` unchanged (`fix_tray_dbus.nim`). 68 distinct boolean GrowthBook flag IDs in the raw bundle, all documented key flags present; both new features still in Zod `.partial()` schema; ion-dist `c71860c77-CDhE5jkR.js`->`c71860c77-CV0D52ti.js` (`mountPath` still mac/win-only, 90 MB/691 JS/909 files unchanged); platform gates darwin 65 / win32 113 / linux 5 (zero swing, no new PORTABLE gate); `enable_local_agent_mode.nim` 12-flag override list unchanged; all 48 patches applied without modification |
| v1.10628.0 | `Aw()` | `LCA` | `Dm()` | **Major version bump v1.9659.4 -> v1.10628.0 (~1000 builds).** **2 new static features:** `claudeDesignWindow` (`claudeDesignWindow:XQ`, always supported, no platform gate, no renderer window) and `builtinMcpPresets` (`builtinMcpPresets:Dm(()=>XQ)`, dev-gated on all platforms, gates built-in MCP presets like `m365`/Microsoft 365) -> **32 static + `louderPenguin` async-only = 33 total**; no features removed, both new features in the Zod `.partial()` schema. Function renames (re-minify): registry `Yp()`->`Aw()`, async merger `IlA`->`LCA` (still `{...Aw(),louderPenguin:e,coworkKappa:A,coworkArtifacts:t,markTaskComplete:i}` via `Promise.all([Fsr(),pRA(()=>It("123929380")),pRA(()=>It("2940196192")),pRA(()=>It("3732274605"))])`), dev-gate `um()`->`Dm()` (`function Dm(e){return aA.app.isPackaged?{status:"unavailable"}:e()}`, electron var `aA` unchanged), `louderPenguin` async helper `Frr()`->`Fsr()` (still `darwin\|\|win32` gate), `quietPenguin` inner `Lsr`, cowork async helper `V0A`->`pRA`, GrowthBook bool reader `Bt()`->`It()`, supported constant -> `XQ` (`{status:"supported"}`), computer-use Set `rlA`->`MCA` (`new Set(["darwin","win32"])`, `MCA.has(process.platform)`), platform vars `Or`/`mo`/`P3`->`Yr`(darwin)/`ro`(win32)/`O$`(darwin\|\|win32), tray fn `Y6A` / tray var `VE` (MCP internal-registration `LYA()`-line not re-verified this release; roster unchanged). **GrowthBook delta** (empirical patched-v1.9659.4-install vs fresh-v1.10628.0 binary; no clean prior MSIX available): ~17 flag IDs newly present (traced new: `124685897` template-subst, `1609612026` marketplace install, `2143883161` `/code/` route gate, `2720310975` side-chat tools, `2688060585`+`3269331205` autoMode force-ON defaults; plus re-appearing historical: `1129419822`, `1496676413`, `1824824999`, `2067027393`, `2114777685`, `2192324205`, `2204227020`, `245679952`, `2800354941`, `3444158716`, `4274871493`), 3 removed (`3242661803`, `3638165567`, `3858743149` maxThinkingTokens); 3 force-ON flags our patches rewrite (`1992087837`/`2216414644`/`3732274605`) excluded as patch artifacts. `enable_local_agent_mode.nim` 12-flag override list unchanged; ion-dist `c71860c77-BOyfE2Py.js`->`c71860c77-CDhE5jkR.js` (`mountPath` still mac/win-only); platform gates darwin 64->65 / win32 112->113 / linux 5 (re-minify noise, no new PORTABLE gate); all 48 patches applied without modification (166 `[OK]` sub-patterns, 0 `[FAIL]`) |
| v1.9659.4 | `Yp()` | `IlA` | `um()` | **Webpack re-minify point release on v1.9659.2** (upstream skipped v1.9659.3 on the public download channel) - same 31 features (30 static + `louderPenguin` async-only), same 30 static feature names, `chatTab`/`surfaceTogglesPreview` still the 2 newest, no features added/removed; function renames vs v1.9659.2 (fresh identifiers only): registry `xp()`->`Yp()`, async merger `olA`->`IlA` (still `{...Yp(),louderPenguin:e,coworkKappa:A,coworkArtifacts:t,markTaskComplete:i}` via `Promise.all([Frr(),V0A(()=>Bt("123929380")),V0A(()=>Bt("2940196192")),V0A(()=>Bt("3732274605"))])`), dev-gate wrapper `Em()`->`um()` (`function um(e){return aA.app.isPackaged?{status:"unavailable"}:e()}`, electron var `aA` unchanged), `louderPenguin` async helper `wrr()`->`Frr()` (still `darwin\|\|win32` gate, returns `unavailable` on Linux), cowork async helper `V0A`; GrowthBook bool reader `Bt()` unchanged; computer-use Set `XEA`->`rlA` (`new Set(["darwin","win32"])`, checked via `rlA.has(process.platform)`); 71 GrowthBook flag IDs unchanged; `fix_tray_dbus.nim` this release: tray fn `Jfi`, tray var `RQ`, menu var `mm`; ion-dist byte-identical (`c71860c77-BOyfE2Py.js`, `mountPath` still mac/win-only); platform gates darwin 60->64 / win32 111->112 / linux 5 (re-minify noise, no new PORTABLE gate); `enable_local_agent_mode.nim` 12-flag override list unchanged; all 47 patches applied without modification |
| v1.9659.2 | `xp()` | `olA` | `Em()` | **Webpack re-minify point release on v1.9659.1** - same 31 features (30 static + `louderPenguin` async-only), `chatTab`/`surfaceTogglesPreview` still the 2 newest, no features added/removed; function renames vs v1.9659.1 (fresh identifiers only): registry `Yp()`->`xp()`, async merger `slA`->`olA` (still `{...xp(),louderPenguin:e,coworkKappa:A,coworkArtifacts:t,markTaskComplete:i}` via `Promise.all([wrr(),Bt("123929380"),Bt("2940196192"),Bt("3732274605")])`), dev-gate wrapper `lm()`->`Em()` (`function Em(e){return aA.app.isPackaged?{status:"unavailable"}:e()}`), `louderPenguin` async helper still `wrr()`; GrowthBook bool reader `Bt()` and computer-use Set `XEA` (`new Set(["darwin","win32"])`, checker `AlA()`) unchanged from v1.9659.1; no GrowthBook flag changes; `fix_tray_dbus.nim` this release: tray fn `G9A`, tray var `PE`; ion-dist unchanged (`c71860c77-BOyfE2Py.js`, `mountPath` still mac/win-only); all 47 patches applied without modification |
| v1.9659.1 | `Yp()` | `slA` | `lm()` | **2 new features:** `surfaceTogglesPreview` (`lm()` dev-gated, always `unavailable` in production), `chatTab` (3p-bootstrap-gated via `aze()` = `desktopBootFeatures.chatIn3p.status==="supported"` && `chatTabEnabled===true`, only active in third-party whitelabel builds) → **30 static + `louderPenguin` async-only = 31 total**; **no features removed** (all 28 static from v1.9255.2 retained); function renames (webpack re-minify): registry `Gp()`→`Yp()`, async merger `pEA`→`slA`, bool flag reader `Ct`→`Bt`, async helper `A0A`→`x0A`, dev-gate wrapper `wD()`→`lm()` (NB: the v1.9255.2 row labels this `PM()` in error; `PM()` does not exist in v1.9255.2 either, the dev-gate was already `wD()`), supported constant `_M`→`Ww`; louderPenguin async still `wrr()` (`darwin\|\|win32` gate, returns `unavailable` on Linux); **GrowthBook deltas verified clean** against freshly extracted v1.9255.2 baseline: 71 boolean flag IDs identical, 0 added/removed (async merger still gates `louderPenguin`/`coworkKappa`/`coworkArtifacts`/`markTaskComplete` via `Bt("4116586025")`/`Bt("123929380")`/`Bt("2940196192")`/`Bt("3732274605")`); 1 new numeric remote-config value `1629866860` (claude_code session limit, read via `ad()`, not a boolean toggle, not flag-relevant); `enable_local_agent_mode.nim` 12-flag override list unchanged (the 2 new features are dev-/3p-gated and don't block Linux Cowork/Code/Agent-Mode paths; all overridden flags remain in the Zod `.partial()` schema; validated 25/25 sub-patches, `node --check` OK); all 47 patches compatible without any code change |
| v1.9255.2 | `Gp()` | `pEA` | `PM()` | **2 new features:** `chatIn3p` (PM() dev-gated, third-party chat), `chatCodeExecution` (`qWe(Vi())` 3p config presence check) - 29 total (28 static + louderPenguin async-only); registry rename `Np()`->`Gp()`, async merger rename `SIA`->`pEA` (still spreads `Gp()` + 4 async overrides `louderPenguin`/`coworkKappa`/`coworkArtifacts`/`markTaskComplete` gated by `Ct("4116586025")`/`Ct("123929380")`/`Ct("2940196192")`/`Ct("3732274605")`); tray function (`_5A` in v1.9255.0 / `R6A` in v1.9255.2), tray var (`OE` in v1.9255.0 / `xE` in v1.9255.2) and menu var (`Ak` / `LM`) now merged into single `let X=null,Y=null;` decl with another function between decl and the tray function - `fix_tray_dbus.nim` rebased to extract tray var from `X&&(X.destroy(),X=null)` pattern inside the tray-function body rather than from `let ([\w$]+)=null;function ...`; v1.9255.2 is a webpack re-minify only point release on top of v1.9255.0 (4.2 MB diff, fresh identifiers everywhere) - all 47 patches stayed compatible without any code change between v1.9255.0 and v1.9255.2; ion-dist main `c71860c77-*` chunk renamed `c71860c77-CgRWbV12.js`->`c71860c77-DFJHDHrp.js`, code-split 16->20 sub-chunks (677 total JS files, was 667), `mountPath` still lacks `linux` key so `fix_ion_dist_linux.nim` still required; `enable_local_agent_mode.nim` 12-flag override list (`quietPenguin`, `louderPenguin`, `chillingSlothFeat`, `chillingSlothLocal`, `chillingSlothPool`, `yukonSilver`, `yukonSilverGems`, `ccdPlugins`, `computerUse`, `coworkKappa`, `coworkArtifacts`, `markTaskComplete`) unchanged - 2 new features don't block existing Linux Cowork/Code paths and all overridden flags remain in the Zod `.partial()` schema. GrowthBook flag deltas not re-verified against v1.8555.2 baseline (old MSIX was deleted before diff) - see CHANGELOG for partial findings |
