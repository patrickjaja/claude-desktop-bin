# Claude Desktop Feature Flag Architecture

Reference documentation for the feature flag system in Claude Desktop's Electron app. This documents v1.8555.2 internals to aid patch maintenance.

## Overview

27 feature flags are controlled by a 3-layer system:

1. **`Np()` (static)** - Calls individual feature functions, builds base object (26 features)
2. **`SIA` (async merger)** - Spreads `Np()`, adds `louderPenguin` + `coworkKappa` + `coworkArtifacts` + `markTaskComplete` as async overrides (4 total)
3. **IPC handler** - Calls merger, validates against schema, sends to renderer

`wt()` flag reader, `Bm()` listener, `Pr()` multi-key reader. New `Lh()` single-value reader (reads `.value` directly from `CQ` storage). `Pr()` handles structured object flags with key+schema, splitting from the former unified `Pr()` approach used in earlier versions.

Feature name strings (`chillingSlothFeat`, `louderPenguin`, etc.) are runtime IPC identifiers, **not minified** - they are stable pattern anchors.

## All 27 Features

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
| 20 | `markTaskComplete` | static: `Y7i()` (unavailable) + async in SIA | Depends on yukonSilver + GrowthBook `3732274605` | **Task completion** - mark tasks as done |
| 21 | `framebufferPreview` | `b7i()` | **PM() production gate** + GrowthBook `1928275548` | VNC framebuffer preview (dev-gated) |
| 22 | `iosSimulator` | `PM(iSe)` | **PM() production gate** + macOS-only | iOS Simulator integration (dev-gated + macOS-only) |
| 23 | `androidEmulator` | `PM(iSe)` | **PM() production gate** + macOS-only | Android Emulator integration (dev-gated + macOS-only; inner function `iSe` unchanged) |
| 24 | `grandPrix` | `L7i()` | darwin-only, checks connected device pairs + `mxi()` gate | Device pairing (macOS-only) |
| 25 | `tearOffHalo` | `G7i()` | macOS >= 13 only | Tear-off halo overlay behind controlled windows (uses `@ant/claude-swift`) |
| 26 | `grandPrixRequest` | `U7i()` | `Gxi()` - darwin only + service requests | GrandPrix service request availability |
| 27 | `bootstrapConfig` | `PM(()=>gK)` | **PM() production gate** | Bootstrap config access (dev-gated) |
| - | *(async-only: `louderPenguin`, `coworkKappa`, `coworkArtifacts`, `markTaskComplete`)* | See rows 6, 18-20 | async overrides in SIA | See respective rows |

## The PM() Production Gate (was Nb() in v1.8089.1, DT() in v1.7196.0, MW() in v1.6608.0)

```javascript
function PM(e){return gA.app.isPackaged?{status:"unavailable"}:e()}
```

In production builds (`app.isPackaged === true`), PM() returns `{status:"unavailable"}` **without calling** the wrapped function. Only in development builds does it call `e()`.

**Features gated by PM():** `plushRaccoon`, `quietPenguin`, `wakeScheduler`, `framebufferPreview`, `iosSimulator`, `androidEmulator`, `bootstrapConfig`

Note: `louderPenguin` is no longer in Np() at all. It exists only in SIA as `await T7i()`, which has its own platform gate (darwin/win32 only) + server feature flag check via GrowthBook `4116586025`. `operon` has been completely removed in v1.6608.0. `coworkKappa`, `coworkArtifacts`, and `markTaskComplete` are async-only: static returns unavailable, async checks yukonSilver + respective GrowthBook flags. `chillingSlothPool` is GrowthBook-gated directly in the static registry.

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
    markTaskComplete:...,              // always unavailable (async-only)
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

### Layer 2: SIA - Async Merger (was UcA in v1.8089.1, woA in v1.7196.0, DoA in v1.6608.2)

```javascript
const SIA=async()=>{
  const[e,A,t,i]=await Promise.all([
    T7i(),                       // louderPenguin
    ZyA(()=>wt("123929380")),    // coworkKappa
    ZyA(()=>wt("2940196192")),   // coworkArtifacts
    ZyA(()=>wt("3732274605"))    // markTaskComplete
  ]);
  return{...Np(),louderPenguin:e,coworkKappa:A,coworkArtifacts:t,markTaskComplete:i}
};
```

Uses `Promise.all` to parallelize louderPenguin (`T7i()`), coworkKappa (`ZyA()+wt("123929380")`), coworkArtifacts (`ZyA()+wt("2940196192")`), and markTaskComplete (`ZyA()+wt("3732274605")`) async checks. Spreads `Np()` then adds the four as async overrides. `T7i()` checks platform (darwin/win32) then checks server feature flag `4116586025`. The `ZyA()` helper checks yukonSilver first, waits 5 seconds, then checks the respective GrowthBook flag. **`operon` was removed in v1.6608.0** - no longer has a static entry or async override.

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

## GrowthBook Flag Catalog (v1.8555.2)

### Boolean Flags (wt())

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `162211072` | Prompt suggestions enable | No |
| `286376943` | Plugin skills for system prompt — gates `getPluginSkillsForSystemPrompt` (**new in v1.2278.0**) | No |
| `397125142` | Terminal server — gated: `sessionType==="ccd"` AND `r6e` AND this flag. CCD only, NOT cowork. `r6e` patched by `fix_dispatch_linux.nim`; flag itself not patched (enabled server-side) | No |
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
| `2216414644` | Remote session control (Dispatch mobile) | **Yes** — bypassed in `fix_dispatch_linux.nim` |
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
| `3558849738` | Dispatch/Spaces feature (RBe constant) | **Yes** — forced ON in `fix_dispatch_linux.nim` |
| `3572572142` | Sessions-bridge init (Dispatch) | **Yes** — forced ON in `fix_dispatch_linux.nim` |
| `3691521536` | Stealth updater — nudge updates when no active sessions | No |
| `3723845789` | Additional Cowork tools | No |
| `4116586025` | louderPenguin / Code tab master gate | No (overridden at merger level) |
| `4153934152` | CLAUDE_CODE_SKIP_PRECOMPACT_LOAD | No |
| `4160352601` | VM heartbeat monitoring | No |
| `4201169164` | **Remote orchestrator** (codename "manta") — **removed from GrowthBook** in v1.1.9669; `Hhn()` now returns hardcoded `false` (`Qhn=!1`). Code still exists but is disabled. | Indirectly — sessions-bridge gate forced ON in `fix_dispatch_linux.nim` |

#### New Boolean Flags in v1.8089.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `245679952` | `suggestSkillsEnabled` default (when no system prompt override) | No |
| `1129419822` | `ENABLE_TOOL_SEARCH='auto'` env var for LAM sessions | No |
| `1496676413` | SSH remote MCP/plugin passthrough (`adjustSdkOptions`) | No |
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

- `2204227020` now also gates Visualize (Imagine) MCP server for CCD sessions (was cowork-only before)
- New `floatingPenguinEnabled` preference (not yet a feature flag in registry - config-only)
- New `midnightOwl` prototype (dev toggle + GrowthBook flag `180602792`)

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
| `1496676413` | SSH plugin/MCP stripping — gates plugin and MCP forwarding to SSH sessions | No |
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
| `3732274605` | markTaskComplete — task completion feature | **Yes** — forced ON in `enable_local_agent_mode.nim` (3 call sites) |

#### New in v1.3883.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `2049450122` | Session handoff — gates cross-device session activity broadcasting (`com.anthropic.claude.session` NSUserActivity identifier) | No |
| `2192324205` | Dispatch structured content forwarding — gates whether `dispatch_child` and `code` structured content kinds pass the message filter (in the rjt() function patched by `fix_dispatch_linux.nim`) | No |

#### New in v1.3561.0

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `1496676413` | SSH session plugins/MCP forwarding — gates plugin and MCP server forwarding to SSH remote sessions (6 call sites in session start, spawn, and MCP resolution) | No |
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

**Patch 1 - Individual functions:** Remove `process.platform!=="darwin"` gate from the quietPenguin inner function. Note: chillingSlothFeat uses a darwin||win32 variable check (`P3`) - only 1 match now instead of 2, handled gracefully by the `elif len(matches) == 1` branch. Also inject Linux early-return in yukonSilver (`TVA()` in v1.8555.2) to bypass its platform gate (though upstream now has native Linux support too - our patch is defensive).

**Patch 3 - SIA merger override:** Append to the `SIA` return object:
```javascript
,quietPenguin:{status:"supported"},louderPenguin:{status:"supported"},chillingSlothFeat:{status:"supported"},chillingSlothLocal:{status:"supported"},chillingSlothPool:{status:"supported"},yukonSilver:{status:"supported"},yukonSilverGems:{status:"supported"},ccdPlugins:{status:"supported"},computerUse:{status:"supported"},coworkKappa:{status:"supported"},coworkArtifacts:{status:"supported"},markTaskComplete:{status:"supported"}
```

This bypasses the PM() gate by overriding at the merger level (12 total overrides). The spread order ensures our values win:
```
...Np()           -> quietPenguin: {status:"unavailable"}  (from PM)
...our overrides  -> quietPenguin: {status:"supported"}    (wins)
```

Note: `chillingSlothLocal` and `ccdPlugins` overrides are defensive - both are already `{status:"supported"}`, but the overrides protect against future gating. `yukonSilverGemsCache` is NOT overridden but inherits support from the `TVA()` (yukonSilver) function patch in Patch 1b. `coworkKappa` is overridden to `{status:"supported"}` AND its GrowthBook flag `123929380` is forced ON (Patch 3b). `coworkArtifacts` is overridden AND its GrowthBook flag `2940196192` is forced ON (Patch 3c). `chillingSlothPool` is overridden AND its GrowthBook flag `1992087837` is forced ON (Patch 3d). `markTaskComplete` is overridden AND its GrowthBook flag `3732274605` is forced ON (Patch 3e).

### Cowork on Linux (experimental)

As of v1.1.2685, Cowork uses a decoupled architecture with a TypeScript VM client that communicates with an external service over a socket. This makes Linux support feasible:

- **`fix_cowork_linux.nim`** patches the VM client loader to include Linux (not just `win32`)
- The Named Pipe path is replaced with a Unix domain socket on Linux
- **`claude-cowork-service`** (separate Go daemon at `/home/patrickjaja/development/claude-cowork-service`) provides native execution backend — 18 RPC methods, process spawning, path remapping
- `chillingSlothFeat`, `chillingSlothLocal`, `yukonSilver`, `yukonSilverGems`, and `ccdPlugins` are all overridden to `{status:"supported"}` in the SIA merger

Without the daemon running, Cowork will show connection errors naturally in the UI.

### Dispatch on Linux (fix_dispatch_linux.nim)

Dispatch is a remote task orchestration feature that lets you send tasks from your phone to your desktop. It's built on top of the Cowork sessions infrastructure and uses Anthropic's "environments bridge" API.

**Architecture:** Desktop registers with `POST /v1/environments/bridge`, then long-polls `GET /v1/environments/{id}/work/poll` for incoming work from the mobile client. All traffic routes through Anthropic's servers over TLS — no inbound ports needed.

**What we patch:**
1. **Sessions-bridge init gate** (GrowthBook flags `3572572142` + `4201169164`) — The bridge only initializes when the combined gate `h = f || p` is true (`f` from flag `3572572142`, `p` from flag `4201169164`). On Linux neither flag fires. We force `h=!0` (true).
2. **Remote session control** (GrowthBook flag `2216414644`) — Messages with `channel:"mobile"` throw unless this flag is on. We replace `!Hn("2216414644")` with `!1` at both call sites.
3. **Platform label** (`bhe()`) — Returns "Unsupported Platform" for Linux. We add `case"linux":return"Linux"`.
4. **Telemetry gate** — `hi||vs` (darwin||win32) silently drops telemetry on Linux. We extend to include Linux.

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
| v1.10628.2 | `Aw()` | `LCA` | `Dm()` | **Webpack re-minify point release on v1.10628.0** (v1.10628.1 not observed on the public download channel) - same **32 static + `louderPenguin` async-only = 33 total**, identical static feature names (`claudeDesignWindow`/`builtinMcpPresets` both retained, none added/removed), merger return identical (`{...Aw(),louderPenguin:e,coworkKappa:A,coworkArtifacts:t,markTaskComplete:i}` via `Promise.all([Fsr(),pRA(()=>It("123929380")),pRA(()=>It("2940196192")),pRA(()=>It("3732274605"))])`); **unusually light re-minify - most function names held:** registry `Aw()`, async merger `LCA`, dev-gate `Dm()` (`function Dm(e){return aA.app.isPackaged?{status:"unavailable"}:e()}`, electron var `aA`), `louderPenguin` async helper `Fsr()` (still `darwin\|\|win32` gate), cowork helper `pRA()`, GrowthBook bool reader `It()`, computer-use Set `MCA` (`new Set(["darwin","win32"])`, `MCA.has(process.platform)`), win32 var `ro`, darwin\|\|win32 var `O$` all unchanged from v1.10628.0; renamed only: supported constant `XQ`->`Xd` (`{status:"supported"}`), chatTab/chatCodeExecution gate fns `R6e`->`R5e`/`M6e`->`M5e`, cowork 5s-delay helper `u9e`->`u6e`, yukonSilver `WjA`->`W8A`, `zKA`->`z1A`, `$jA`->`$8A`, tray fn `Y6A`->`Y5A` / tray var `VE` unchanged (`fix_tray_dbus.nim`). 68 distinct boolean GrowthBook flag IDs in the raw bundle, all documented key flags present; both new features still in Zod `.partial()` schema; ion-dist `c71860c77-CDhE5jkR.js`->`c71860c77-CV0D52ti.js` (`mountPath` still mac/win-only, 90 MB/691 JS/909 files unchanged); platform gates darwin 65 / win32 113 / linux 5 (zero swing, no new PORTABLE gate); `enable_local_agent_mode.nim` 12-flag override list unchanged; all 48 patches applied without modification |
| v1.10628.0 | `Aw()` | `LCA` | `Dm()` | **Major version bump v1.9659.4 -> v1.10628.0 (~1000 builds).** **2 new static features:** `claudeDesignWindow` (`claudeDesignWindow:XQ`, always supported, no platform gate, no renderer window) and `builtinMcpPresets` (`builtinMcpPresets:Dm(()=>XQ)`, dev-gated on all platforms, gates built-in MCP presets like `m365`/Microsoft 365) -> **32 static + `louderPenguin` async-only = 33 total**; no features removed, both new features in the Zod `.partial()` schema. Function renames (re-minify): registry `Yp()`->`Aw()`, async merger `IlA`->`LCA` (still `{...Aw(),louderPenguin:e,coworkKappa:A,coworkArtifacts:t,markTaskComplete:i}` via `Promise.all([Fsr(),pRA(()=>It("123929380")),pRA(()=>It("2940196192")),pRA(()=>It("3732274605"))])`), dev-gate `um()`->`Dm()` (`function Dm(e){return aA.app.isPackaged?{status:"unavailable"}:e()}`, electron var `aA` unchanged), `louderPenguin` async helper `Frr()`->`Fsr()` (still `darwin\|\|win32` gate), `quietPenguin` inner `Lsr`, cowork async helper `V0A`->`pRA`, GrowthBook bool reader `Bt()`->`It()`, supported constant -> `XQ` (`{status:"supported"}`), computer-use Set `rlA`->`MCA` (`new Set(["darwin","win32"])`, `MCA.has(process.platform)`), platform vars `Or`/`mo`/`P3`->`Yr`(darwin)/`ro`(win32)/`O$`(darwin\|\|win32), tray fn `Y6A` / tray var `VE` (MCP internal-registration `LYA()`-line not re-verified this release; roster unchanged). **GrowthBook delta** (empirical patched-v1.9659.4-install vs fresh-v1.10628.0 binary; no clean prior MSIX available): ~17 flag IDs newly present (traced new: `124685897` template-subst, `1609612026` marketplace install, `2143883161` `/code/` route gate, `2720310975` side-chat tools, `2688060585`+`3269331205` autoMode force-ON defaults; plus re-appearing historical: `1129419822`, `1496676413`, `1824824999`, `2067027393`, `2114777685`, `2192324205`, `2204227020`, `245679952`, `2800354941`, `3444158716`, `4274871493`), 3 removed (`3242661803`, `3638165567`, `3858743149` maxThinkingTokens); 3 force-ON flags our patches rewrite (`1992087837`/`2216414644`/`3732274605`) excluded as patch artifacts. `enable_local_agent_mode.nim` 12-flag override list unchanged; ion-dist `c71860c77-BOyfE2Py.js`->`c71860c77-CDhE5jkR.js` (`mountPath` still mac/win-only); platform gates darwin 64->65 / win32 112->113 / linux 5 (re-minify noise, no new PORTABLE gate); all 48 patches applied without modification (166 `[OK]` sub-patterns, 0 `[FAIL]`) |
| v1.9659.4 | `Yp()` | `IlA` | `um()` | **Webpack re-minify point release on v1.9659.2** (upstream skipped v1.9659.3 on the public download channel) - same 31 features (30 static + `louderPenguin` async-only), same 30 static feature names, `chatTab`/`surfaceTogglesPreview` still the 2 newest, no features added/removed; function renames vs v1.9659.2 (fresh identifiers only): registry `xp()`->`Yp()`, async merger `olA`->`IlA` (still `{...Yp(),louderPenguin:e,coworkKappa:A,coworkArtifacts:t,markTaskComplete:i}` via `Promise.all([Frr(),V0A(()=>Bt("123929380")),V0A(()=>Bt("2940196192")),V0A(()=>Bt("3732274605"))])`), dev-gate wrapper `Em()`->`um()` (`function um(e){return aA.app.isPackaged?{status:"unavailable"}:e()}`, electron var `aA` unchanged), `louderPenguin` async helper `wrr()`->`Frr()` (still `darwin\|\|win32` gate, returns `unavailable` on Linux), cowork async helper `V0A`; GrowthBook bool reader `Bt()` unchanged; computer-use Set `XEA`->`rlA` (`new Set(["darwin","win32"])`, checked via `rlA.has(process.platform)`); 71 GrowthBook flag IDs unchanged; `fix_tray_dbus.nim` this release: tray fn `Jfi`, tray var `RQ`, menu var `mm`; ion-dist byte-identical (`c71860c77-BOyfE2Py.js`, `mountPath` still mac/win-only); platform gates darwin 60->64 / win32 111->112 / linux 5 (re-minify noise, no new PORTABLE gate); `enable_local_agent_mode.nim` 12-flag override list unchanged; all 47 patches applied without modification |
| v1.9659.2 | `xp()` | `olA` | `Em()` | **Webpack re-minify point release on v1.9659.1** - same 31 features (30 static + `louderPenguin` async-only), `chatTab`/`surfaceTogglesPreview` still the 2 newest, no features added/removed; function renames vs v1.9659.1 (fresh identifiers only): registry `Yp()`->`xp()`, async merger `slA`->`olA` (still `{...xp(),louderPenguin:e,coworkKappa:A,coworkArtifacts:t,markTaskComplete:i}` via `Promise.all([wrr(),Bt("123929380"),Bt("2940196192"),Bt("3732274605")])`), dev-gate wrapper `lm()`->`Em()` (`function Em(e){return aA.app.isPackaged?{status:"unavailable"}:e()}`), `louderPenguin` async helper still `wrr()`; GrowthBook bool reader `Bt()` and computer-use Set `XEA` (`new Set(["darwin","win32"])`, checker `AlA()`) unchanged from v1.9659.1; no GrowthBook flag changes; `fix_tray_dbus.nim` this release: tray fn `G9A`, tray var `PE`; ion-dist unchanged (`c71860c77-BOyfE2Py.js`, `mountPath` still mac/win-only); all 47 patches applied without modification |
| v1.9659.1 | `Yp()` | `slA` | `lm()` | **2 new features:** `surfaceTogglesPreview` (`lm()` dev-gated, always `unavailable` in production), `chatTab` (3p-bootstrap-gated via `aze()` = `desktopBootFeatures.chatIn3p.status==="supported"` && `chatTabEnabled===true`, only active in third-party whitelabel builds) → **30 static + `louderPenguin` async-only = 31 total**; **no features removed** (all 28 static from v1.9255.2 retained); function renames (webpack re-minify): registry `Gp()`→`Yp()`, async merger `pEA`→`slA`, bool flag reader `Ct`→`Bt`, async helper `A0A`→`x0A`, dev-gate wrapper `wD()`→`lm()` (NB: the v1.9255.2 row labels this `PM()` in error; `PM()` does not exist in v1.9255.2 either, the dev-gate was already `wD()`), supported constant `_M`→`Ww`; louderPenguin async still `wrr()` (`darwin\|\|win32` gate, returns `unavailable` on Linux); **GrowthBook deltas verified clean** against freshly extracted v1.9255.2 baseline: 71 boolean flag IDs identical, 0 added/removed (async merger still gates `louderPenguin`/`coworkKappa`/`coworkArtifacts`/`markTaskComplete` via `Bt("4116586025")`/`Bt("123929380")`/`Bt("2940196192")`/`Bt("3732274605")`); 1 new numeric remote-config value `1629866860` (claude_code session limit, read via `ad()`, not a boolean toggle, not flag-relevant); `enable_local_agent_mode.nim` 12-flag override list unchanged (the 2 new features are dev-/3p-gated and don't block Linux Cowork/Code/Agent-Mode paths; all overridden flags remain in the Zod `.partial()` schema; validated 25/25 sub-patches, `node --check` OK); all 47 patches compatible without any code change |
| v1.9255.2 | `Gp()` | `pEA` | `PM()` | **2 new features:** `chatIn3p` (PM() dev-gated, third-party chat), `chatCodeExecution` (`qWe(Vi())` 3p config presence check) - 29 total (28 static + louderPenguin async-only); registry rename `Np()`->`Gp()`, async merger rename `SIA`->`pEA` (still spreads `Gp()` + 4 async overrides `louderPenguin`/`coworkKappa`/`coworkArtifacts`/`markTaskComplete` gated by `Ct("4116586025")`/`Ct("123929380")`/`Ct("2940196192")`/`Ct("3732274605")`); tray function (`_5A` in v1.9255.0 / `R6A` in v1.9255.2), tray var (`OE` in v1.9255.0 / `xE` in v1.9255.2) and menu var (`Ak` / `LM`) now merged into single `let X=null,Y=null;` decl with another function between decl and the tray function - `fix_tray_dbus.nim` rebased to extract tray var from `X&&(X.destroy(),X=null)` pattern inside the tray-function body rather than from `let ([\w$]+)=null;function ...`; v1.9255.2 is a webpack re-minify only point release on top of v1.9255.0 (4.2 MB diff, fresh identifiers everywhere) - all 47 patches stayed compatible without any code change between v1.9255.0 and v1.9255.2; ion-dist main `c71860c77-*` chunk renamed `c71860c77-CgRWbV12.js`->`c71860c77-DFJHDHrp.js`, code-split 16->20 sub-chunks (677 total JS files, was 667), `mountPath` still lacks `linux` key so `fix_ion_dist_linux.nim` still required; `enable_local_agent_mode.nim` 12-flag override list (`quietPenguin`, `louderPenguin`, `chillingSlothFeat`, `chillingSlothLocal`, `chillingSlothPool`, `yukonSilver`, `yukonSilverGems`, `ccdPlugins`, `computerUse`, `coworkKappa`, `coworkArtifacts`, `markTaskComplete`) unchanged - 2 new features don't block existing Linux Cowork/Code paths and all overridden flags remain in the Zod `.partial()` schema. GrowthBook flag deltas not re-verified against v1.8555.2 baseline (old MSIX was deleted before diff) - see CHANGELOG for partial findings |
