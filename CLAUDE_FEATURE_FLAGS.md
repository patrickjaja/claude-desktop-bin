# Claude Desktop Feature Flag Architecture

Reference documentation for the feature flag system in Claude Desktop's Electron app. This documents v1.5354.0 internals to aid patch maintenance.

## Overview

24 feature flags are controlled by a 3-layer system:

1. **`v_()` (static)** - Calls individual feature functions, builds base object (23 features)
2. **`ZDA` (async merger)** - Spreads `v_()`, adds `louderPenguin` + `operon` + `coworkKappa` + `coworkArtifacts` + `markTaskComplete` as async overrides
3. **IPC handler** - Calls merger, validates against schema, sends to renderer

Feature name strings (`chillingSlothFeat`, `louderPenguin`, etc.) are runtime IPC identifiers, **not minified** - they are stable pattern anchors.

## All 24 Features

| # | Feature | Function | Gate | Purpose |
|---|---------|----------|------|---------|
| 1 | `nativeQuickEntry` | `L_r()` | `platform !== "darwin"` + macOS >= 13 | Native Quick Entry (macOS only) |
| 2 | `quickEntryDictation` | `G_r()` | `platform !== "darwin"` + macOS >= 14.0 + mic | Quick Entry dictation |
| 3 | `customQuickEntryDictationShortcut` | direct value `saA` | None | Custom dictation shortcut value |
| 4 | `plushRaccoon` | `MW(() => saA)` | **MW() production gate** | Custom dictation shortcut (dev-gated) |
| 5 | `quietPenguin` | `MW(J_r)` | **MW()** + inner `J_r()` returns supported on darwin | Code-related feature (dev-gated) |
| 6 | `louderPenguin` | `await j_r()` in ZDA only | **async override** in ZDA; platform gate (darwin/win32) + GrowthBook `4116586025` | **Code tab** |
| 7 | `chillingSlothFeat` | `F_r()` | darwin\|\|win32 variable check | Local Agent Mode / Cowork |
| 8 | `chillingSlothEnterprise` | `U_r()` | Org config check | Enterprise disable for Claude Code |
| 9 | `chillingSlothLocal` | `x_r()` | **None** (always supported) | Local sessions |
| 10 | `chillingSlothPool` | GrowthBook `1992087837` | GrowthBook flag gate | **Concurrent session pooling** (**new in v1.4758.0**) |
| 11 | `yukonSilver` | `zDA()` | Platform/arch gate + org config (has native Linux support!) | Secure VM |
| 12 | `yukonSilverGems` | `JHe()` | Depends on `yukonSilver` (`zDA()`) | VM extensions |
| 13 | `yukonSilverGemsCache` | `JHe()` | Depends on `yukonSilver` (`zDA()`) | VM extensions cache |
| 14 | `wakeScheduler` | `MW(W_r)` | **MW() gate** + `platform !== "darwin"` + macOS >= 13.0 | macOS Login Items / wake scheduling |
| 15 | `operon` | `z_r()` | always unavailable in static; async check in ZDA | Nest — 120+ IPC endpoints, 33 sub-interfaces |
| 16 | `desktopTopBar` | `q_r()` | **None** (always supported) | Desktop top bar |
| 17 | `ccdPlugins` | `saA` (constant) | **None** (always supported) | CCD Plugins UI (Add plugins, Browse plugins) |
| 18 | `floatingAtoll` | `V_r()` | **None** (always supported, unconditional) | Floating mini-window |
| 19 | `computerUse` | `$_r()` | Set-based check on `process.platform` | Computer use feature flag (**patched for Linux** via Set modification) |
| 20 | `coworkKappa` | static: `Z_r()` (unavailable) + async in ZDA | Depends on yukonSilver + GrowthBook `123929380` | Memory consolidation — `consolidate-memory` skill |
| 21 | `coworkArtifacts` | static: `X_r()` (unavailable) + async in ZDA | Depends on yukonSilver + GrowthBook `2940196192` | **Cowork artifacts** — artifact rendering in cowork sessions |
| 22 | `markTaskComplete` | static: `ARr()` (unavailable) + async in ZDA | Depends on yukonSilver + GrowthBook `3732274605` | **Task completion** — mark tasks as done |
| 23 | `framebufferPreview` | `ivr()` | **MW() production gate** + GrowthBook `1928275548` | VNC framebuffer preview (**new in v1.5354.0**, dev-gated) |
| 24 | `iosSimulator` | `MW(rvr)` | **MW() production gate** + macOS-only | iOS Simulator integration (**new in v1.5354.0**, dev-gated + macOS-only) |

## The MW() Production Gate

```javascript
function MW(e){return hA.app.isPackaged?{status:"unavailable"}:e()}
```

In production builds (`app.isPackaged === true`), MW() returns `{status:"unavailable"}` **without calling** the wrapped function. Only in development builds does it call `e()`.

**Features gated by MW():** `plushRaccoon`, `quietPenguin`, `wakeScheduler`, `framebufferPreview`, `iosSimulator`

Note: `louderPenguin` is no longer in d_() at all. It exists only in $yA as `await j_r()`, which has its own platform gate (darwin/win32 only) + server feature flag check. `operon` has both a static entry (unconditionally unavailable) and an async override in $yA. `coworkKappa`, `coworkArtifacts`, and `markTaskComplete` are similarly async-only: static returns unavailable, async checks yukonSilver + respective GrowthBook flags. `chillingSlothPool` is GrowthBook-gated directly in the static registry.

This is why patching the inner functions alone is insufficient - MW() never calls them in packaged builds.

## The Three Layers

### Layer 1: v_() - Static Registry

```javascript
function v_(){
  return{
    nativeQuickEntry:...,
    quickEntryDictation:...,
    customQuickEntryDictationShortcut:...,
    plushRaccoon:MW(()=>...),
    quietPenguin:MW(...),
    chillingSlothFeat:...,             // darwin||win32 variable check
    chillingSlothEnterprise:...,
    chillingSlothLocal:...,
    chillingSlothPool:...,             // GrowthBook 1992087837 gate
    yukonSilver:...,
    yukonSilverGems:...,
    yukonSilverGemsCache:...,
    wakeScheduler:MW(...),
    operon:...,                        // always unavailable
    desktopTopBar:...,
    ccdPlugins:...,                    // constant {status:"supported"}
    floatingAtoll:...,                 // always supported (unconditional)
    computerUse:...,                   // Set-based gate, "linux" added by patch
    coworkKappa:...,                   // always unavailable (async-only)
    coworkArtifacts:...,               // always unavailable (async-only)
    markTaskComplete:...,              // always unavailable (async-only)
    framebufferPreview:MW(...),        // dev-gated (new in v1.5354.0)
    iosSimulator:MW(...)               // dev-gated + macOS-only (new in v1.5354.0)
  }
}
```

Returns 23 features synchronously. Features wrapped by `MW()` are always `{status:"unavailable"}` in packaged builds.

### Layer 2: ZDA - Async Merger

```javascript
const ZDA=async()=>{
  const[e,A,t,i,r]=await Promise.all([j_r(),mFt(),DFA(()=>Pt("123929380")),DFA(()=>Pt("2940196192")),DFA(()=>Pt("3732274605"))]);
  return{...v_(),louderPenguin:e,operon:A,coworkKappa:t,coworkArtifacts:i,markTaskComplete:r}
};
```

Uses `Promise.all` to parallelize louderPenguin (`j_r()`), operon (`mFt()`), coworkKappa (`DFA()+Pt("123929380")`), coworkArtifacts (`DFA()+Pt("2940196192")`), and markTaskComplete (`DFA()+Pt("3732274605")`) async checks. Spreads `v_()` then adds the five as async overrides. `j_r()` checks platform (darwin/win32) then checks server feature flag `4116586025`. The operon async check introduces a 5-second delay, then blocks win32, checks yukonSilver, and checks GrowthBook flag `1306813456`. The `DFA()` helper checks yukonSilver first, waits 5 seconds, then checks the respective GrowthBook flag.

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

**Because spread applies earlier properties first, later properties win.** This is how our Linux patch works - we append overrides after the last async property so they take precedence over gate-blocked values from `...Hb()`.

### Org-Level Settings

Feature flags can also be affected by organization-level admin settings:

- **"Skills" toggle** in org admin → controls SkillsPlugin availability. When disabled, SkillsPlugin returns 404, causing the renderer to hide plugin UI buttons (Add plugins, Browse plugins). This is independent of `ccdPlugins` — the feature flag can be `{status:"supported"}` but the UI still won't show if the org disables Skills.
- **`chillingSlothEnterprise`** → org-level disable for Claude Code. When the org config disables it, the Code tab disappears regardless of other feature flags.

### Layer 3: IPC Handler

Calls the merger, validates the result against a Zod schema, and sends it to the renderer process via IPC. The renderer uses these flags to conditionally render UI elements (e.g., Chat|Code toggle).

## GrowthBook Flag Catalog (v1.5354.0)

### Boolean Flags (Pt())

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
| `1306813456` | Operon/Nest gate | No |
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
| `2860753854` | System prompt override (via value) | No |
| `2976814254` | Launch server (isAvailable check) | No |
| `3246569822` | canSaveSkill (save reusable skills) | No |
| `3298006781` | MSIX updater gate | No |
| `3366735351` | Auto-update on ready state | No |
| `2940196192` | coworkArtifacts — persistent HTML artifact storage in cowork sessions | **Yes** — forced ON in `enable_local_agent_mode.nim` (4 call sites) |
| `3444158716` | Cowork resources MCP ("visualize" — show_widget tool) | No |
| `1143815894` | hostLoopMode — non-VM cowork (bare SDK loop, no cowork service spawn) | **No** — must NOT be forced ON; doing so bypasses the cowork service, breaking skills/plugins |
| `3558849738` | Dispatch/Spaces feature (RBe constant) | **Yes** — forced ON in `fix_dispatch_linux.nim` |
| `3572572142` | Sessions-bridge init (Dispatch) | **Yes** — forced ON in `fix_dispatch_linux.nim` |
| `3691521536` | Stealth updater — nudge updates when no active sessions | No |
| `3723845789` | Additional Cowork tools | No |
| `3885610113` | Model name [1m] suffix for sonnet-4-6/opus-4-6 | No |
| `4116586025` | louderPenguin / Code tab master gate | No (overridden at merger level) |
| `4153934152` | CLAUDE_CODE_SKIP_PRECOMPACT_LOAD | No |
| `4160352601` | VM heartbeat monitoring | No |
| `4201169164` | **Remote orchestrator** (codename "manta") — **removed from GrowthBook** in v1.1.9669; `Hhn()` now returns hardcoded `false` (`Qhn=!1`). Code still exists but is disabled. | Indirectly — sessions-bridge gate forced ON in `fix_dispatch_linux.nim` |

#### New in v1.1.9134

| Flag ID | Purpose | Patched? |
|---------|---------|----------|
| `66187241` | `CLAUDE_CODE_EMIT_TOOL_USE_SUMMARIES` for LAM/Cowork sessions | No |
| `1585356617` | Epitaxy routing — SSH session routing, spawned session tools, system prompt append. When on, sessions route to `/epitaxy?openSession=` instead of `/claude-code-desktop/` | No |
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
| `1004628546` | `Bn()` | Configurable consolidate-memory skill description/prompt | No |
| `3229517805` | `Bn()` | `runScheduledTaskEnabled` (default `true`) — scheduled task execution gate | No |

#### New Listener Flags in v1.5354.0

| Flag ID | Purpose |
|---------|---------|
| `2345515473` | Sessions-bridge account-change reevaluation |

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

### Object/Value Flags (Es())

`di()` reads single-value flags; `Es()` reads multi-key object/value flags.

| Flag ID | Type | Purpose |
|---------|------|---------|
| `254738541` | fs() | Prompt text (**new in v1.1348.0**) |
| `365342473` | wA() | shouldScrubTelemetry (default: `true`) (**new in v1.1348.0**) |
| `476513332` | wA() | Update check interval ticks config |
| `554317356` | wA() | Timer interval config |
| `1677081600` | wA() | Custom prompt/instruction text |
| `1748356779` | wA() | System prompt / user prompt template config |
| `1893165035` | wA() | SDK error auto-recovery config (`{enabled, categories}`) — categories include `sdk_binary_missing`, `sandbox_deps_missing`, `filesystem_error` (**new in v1.2278.0**) |
| `1978029737` | fs() | Session config (skillsSyncIntervalMs, artifactMcpConcurrencyLimit, artifactSampleConcurrencyLimit, idleGraceMs, disableSessionsDiskCleanup, sessionsBridgePollIntervalMs, coworkMessageTimeoutMs, coworkWebFetchViaApi, coworkNativeFilePreview) |
| `2860753854` | wA() | System prompt override text |
| `2893011886` | fs() | Wake scheduler config (enabled, scheduledTasksWakeEnabled, minLeadTimeMs, chainIntervalMs, batteryIntervalMs, acIntervalMs) |
| `3300773012` | fs() | Scheduled tasks config (skillDescription, skillPrompt, scheduledTaskPostWakeDelayMs, dispatchJitterMaxMinutes) |
| `3586389629` | wA() | Connection timeout config |
| `3758515526` | fs() | Default marketplace repo config (repo, repoCCD) |
| `3858743149` | fs() | maxThinkingTokens config (default 4000, min 1024) (**new in v1.2773.0**) |
| `4066504968` | fs() | Setup-cowork skill config (skillDescription, skillPrompt) (**new in v1.1348.0**) |

### Listener Flags (FG())

| Flag ID | Purpose |
|---------|---------|
| `180602792` | Cookie change / midnight owl |
| `1978029737` | Skills plugin sync / poll sleep kick |
| `3572572142` | Sessions-bridge on/off toggle |
| `2940196192` | Artifacts changed listener — triggers re-emit on flag toggle |
| `gHt` (`3558849738`) | Dispatch/Spaces feature — used via variable reference |

## What We Patch on Linux

### enable_local_agent_mode.nim

**Patch 1 - Individual functions:** Remove `process.platform!=="darwin"` gate from the quietPenguin inner function. Note: chillingSlothFeat uses a darwin||win32 variable check — only 1 match now instead of 2, handled gracefully by the `elif len(matches) == 1` branch. Also inject Linux early-return in yukonSilver (`jyA()` in v1.4758.0) to bypass its platform gate (though upstream now has native Linux support too — our patch is defensive).

**Patch 3 - $yA merger override:** Append to the `$yA` return object:
```javascript
,quietPenguin:{status:"supported"},louderPenguin:{status:"supported"},chillingSlothFeat:{status:"supported"},chillingSlothLocal:{status:"supported"},chillingSlothPool:{status:"supported"},yukonSilver:{status:"supported"},yukonSilverGems:{status:"supported"},ccdPlugins:{status:"supported"},computerUse:{status:"supported"},coworkKappa:{status:"supported"},coworkArtifacts:{status:"supported"},markTaskComplete:{status:"supported"}
```

This bypasses the yFA() gate by overriding at the merger level (12 total overrides). The spread order ensures our values win:
```
...d_()           -> quietPenguin: {status:"unavailable"}  (from yFA)
...our overrides  -> quietPenguin: {status:"supported"}    (wins)
```

Note: `chillingSlothLocal` and `ccdPlugins` overrides are defensive — both are already `{status:"supported"}`, but the overrides protect against future gating. `yukonSilverGemsCache` is NOT overridden but inherits support from the `jyA()` (yukonSilver) function patch in Patch 1b. `coworkKappa` is overridden to `{status:"supported"}` AND its GrowthBook flag `123929380` is forced ON (Patch 3b). `coworkArtifacts` is overridden AND its GrowthBook flag `2940196192` is forced ON (Patch 3c). `chillingSlothPool` is overridden AND its GrowthBook flag `1992087837` is forced ON (Patch 3d). `markTaskComplete` is overridden AND its GrowthBook flag `3732274605` is forced ON (Patch 3e).

### Cowork on Linux (experimental)

As of v1.1.2685, Cowork uses a decoupled architecture with a TypeScript VM client that communicates with an external service over a socket. This makes Linux support feasible:

- **`fix_cowork_linux.nim`** patches the VM client loader to include Linux (not just `win32`)
- The Named Pipe path is replaced with a Unix domain socket on Linux
- **`claude-cowork-service`** (separate Go daemon at `/home/patrickjaja/development/claude-cowork-service`) provides native execution backend — 18 RPC methods, process spawning, path remapping
- `chillingSlothFeat`, `chillingSlothLocal`, `yukonSilver`, `yukonSilverGems`, and `ccdPlugins` are all overridden to `{status:"supported"}` in the gwA merger

Without the daemon running, Cowork will show connection errors naturally in the UI.

### Dispatch on Linux (fix_dispatch_linux.nim)

Dispatch is a remote task orchestration feature that lets you send tasks from your phone to your desktop. It's built on top of the Cowork sessions infrastructure and uses Anthropic's "environments bridge" API.

**Architecture:** Desktop registers with `POST /v1/environments/bridge`, then long-polls `GET /v1/environments/{id}/work/poll` for incoming work from the mobile client. All traffic routes through Anthropic's servers over TLS — no inbound ports needed.

**What we patch:**
1. **Sessions-bridge init gate** (GrowthBook flags `3572572142` + `4201169164`) — The bridge only initializes when the combined gate `h = f || p` is true (`f` from flag `3572572142`, `p` from flag `4201169164`). On Linux neither flag fires. We force `h=!0` (true).
2. **Remote session control** (GrowthBook flag `2216414644`) — Messages with `channel:"mobile"` throw unless this flag is on. We replace `!Hn("2216414644")` with `!1` at both call sites.
3. **Platform label** (`bhe()`) — Returns "Unsupported Platform" for Linux. We add `case"linux":return"Linux"`.
4. **Telemetry gate** — `hi||vs` (darwin||win32) silently drops telemetry on Linux. We extend to include Linux.

**Note on `operon` (Nest):** Do NOT force-enable — requires VM infrastructure (120+ IPC endpoints across 31 sub-interfaces). Currently `{status:"unavailable"}` on Linux (GrowthBook flag `1306813456` not enabled server-side). See [Operon Tool Inventory](#operon-tool-inventory-v11062) below for the full model-facing toolset.

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
| `floatingAtoll` | Now always supported upstream — not patched (no longer needs it) |
| `operon` | Requires VM infrastructure (Nest); flag not enabled server-side |
| ~~`coworkArtifacts`~~ | **Enabled on Linux** — flag `2940196192` forced ON + merger override in `enable_local_agent_mode.nim` (**new in v1.3883.0**) |
| ~~`coworkKappa`~~ | **Enabled on Linux** — flag `123929380` forced ON + merger override in `enable_local_agent_mode.nim` |

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

1. Check if `Mle` structure changed (new features added, order changed)
2. Check if G1e()-wrapped features changed
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
