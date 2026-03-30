# Claude Desktop Feature Flag Architecture

Reference documentation for the feature flag system in Claude Desktop's Electron app. This documents v1.1.9669 internals to aid patch maintenance.

## Overview

18 feature flags are controlled by a 3-layer system:

1. **`_b()` (static)** - Calls individual feature functions, builds base object (16 features)
2. **`Cie` (async merger)** - Spreads `_b()`, adds `louderPenguin` + `operon` as async overrides
3. **IPC handler** - Calls `Cie`, validates against schema, sends to renderer

Feature name strings (`chillingSlothFeat`, `louderPenguin`, etc.) are runtime IPC identifiers, **not minified** - they are stable pattern anchors.

## All 18 Features

| # | Feature | Function | Gate | Purpose |
|---|---------|----------|------|---------|
| 1 | `nativeQuickEntry` | `xun()` | `platform !== "darwin"` | Native Quick Entry (macOS only) |
| 2 | `quickEntryDictation` | `Iun()` | `platform !== "darwin"` | Quick Entry dictation |
| 3 | `customQuickEntryDictationShortcut` | direct value `pve` | None | Custom dictation shortcut value |
| 4 | `plushRaccoon` | `fve(() => pve)` | **fve() production gate** | Custom dictation shortcut (dev-gated) |
| 5 | `quietPenguin` | `fve(Oun)` | **fve()** + inner `Oun()` returns supported | Code-related feature (dev-gated) |
| 6 | `louderPenguin` | `await Uun()` in Cie only | **async override** in Cie; platform gate (darwin/win32) + GrowthBook `4116586025` | **Code tab** |
| 7 | `chillingSlothFeat` | `Tun()` | `platform !== "darwin"` (darwin gate re-introduced in v1.1.9669) | Local Agent Mode / Cowork |
| 8 | `chillingSlottEnterprise` | `kun()` | Org config check | Enterprise disable for Claude Code |
| 9 | `chillingSlothLocal` | `Run()` | **None** (always supported) | Local sessions |
| 10 | `yukonSilver` | `vBe()` | Platform/arch gate via `$un()` + org config (has native Linux support!) | Secure VM |
| 11 | `yukonSilverGems` | `tlt()` | Depends on `yukonSilver` (`vBe()`) | VM extensions |
| 12 | `yukonSilverGemsCache` | `tlt()` | Depends on `yukonSilver` (`vBe()`) | VM extensions cache |
| 13 | `wakeScheduler` | `fve(qun)` | **fve() gate** + `platform !== "darwin"` + macOS >= 13.0 | macOS Login Items / wake scheduling |
| 14 | `desktopTopBar` | `Mun()` | **None** (always supported) | Desktop top bar |
| 15 | `ccdPlugins` | `pve` (constant) | **None** (always supported) | CCD Plugins UI (Add plugins, Browse plugins) |
| 16 | `floatingAtoll` | `Fun()` | **Always unavailable** | Floating mini-window (macOS window button offset, disabled for all) |
| 17 | `operon` | static: `Qun()` (unavailable) + async: `await pHt()` in Cie | blocks win32, checks `vBe()` (yukonSilver) + GrowthBook `1306813456` | Nest — 120+ IPC endpoints, 28 sub-interfaces |
| 18 | **`computerUse`** (NEW) | `jun()` | `platform !== "darwin"` → returns "unsupported" | Computer use feature flag (macOS only in upstream; **patched for Linux**) |

## The fve() Production Gate

```javascript
function fve(t){return Re.app.isPackaged?{status:"unavailable"}:t()}
```

In production builds (`app.isPackaged === true`), fve() returns `{status:"unavailable"}` **without calling** the wrapped function. Only in development builds does it call `t()`.

**Features gated by fve():** `plushRaccoon`, `quietPenguin`, `wakeScheduler`

Note: `louderPenguin` is no longer in _b() at all (was QL()-gated in earlier versions). It exists only in Cie as `await Uun()`, which has its own platform gate (darwin/win32 only) + server feature flag check. `operon` now has both a static entry (`Qun()` returning unavailable) and an async override in Cie as `await pHt()`.

This is why patching the inner functions alone is insufficient - fve() never calls them in packaged builds.

## The Three Layers

### Layer 1: _b() - Static Registry

```javascript
function _b(){
  return{
    nativeQuickEntry:xun(),
    quickEntryDictation:Iun(),
    customQuickEntryDictationShortcut:pve,
    plushRaccoon:fve(()=>pve),
    quietPenguin:fve(Oun),
    chillingSlothFeat:Tun(),           // darwin gate re-introduced
    chillingSlottEnterprise:kun(),
    chillingSlothLocal:Run(),
    yukonSilver:vBe(),
    yukonSilverGems:tlt(),
    yukonSilverGemsCache:tlt(),
    wakeScheduler:fve(qun),
    operon:Qun(),                      // always unavailable
    desktopTopBar:Mun(),
    ccdPlugins:pve,                    // constant {status:"supported"}
    floatingAtoll:Fun(),               // always {status:"unavailable"}
    computerUse:jun()                  // NEW in v1.1.9669 (darwin-only)
  }
}
```

Returns 16 features synchronously (up from 15). `pve` is a constant `{status:"supported"}`. Features wrapped by `fve()` are always `{status:"unavailable"}` in packaged builds.

### Layer 2: Cie - Async Merger

```javascript
const Cie=async()=>{
  const[t,e]=await Promise.all([Uun(),pHt()]);
  return{..._b(),louderPenguin:t,operon:e}
};
```

Now uses `Promise.all` to parallelize louderPenguin (`Uun()`) and operon (`pHt()`) async checks. Spreads `_b()` then adds `louderPenguin` and `operon` as async overrides. `Uun()` checks `process.platform!=="darwin"&&process.platform!=="win32"` (returns unavailable on Linux) then checks server feature flag `4116586025`. `pHt()` blocks win32, checks `vBe()` (yukonSilver), then checks GrowthBook flag `1306813456`.

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

**Because spread applies earlier properties first, later properties win.** This is how our Linux patch works - we append overrides after the last async property so they take precedence over fve()-blocked values from `..._b()`.

### Org-Level Settings

Feature flags can also be affected by organization-level admin settings:

- **"Skills" toggle** in org admin → controls SkillsPlugin availability. When disabled, SkillsPlugin returns 404, causing the renderer to hide plugin UI buttons (Add plugins, Browse plugins). This is independent of `ccdPlugins` — the feature flag can be `{status:"supported"}` but the UI still won't show if the org disables Skills.
- **`chillingSlothEnterprise`** → org-level disable for Claude Code. When the org config disables it, the Code tab disappears regardless of other feature flags.

### Layer 3: IPC Handler

Calls `Cie`, validates the result against a Zod schema, and sends it to the renderer process via IPC. The renderer uses these flags to conditionally render UI elements (e.g., Chat|Code toggle).

## GrowthBook Flag Catalog (v1.1.9669)

### Boolean Flags (Vn())

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
| `3246569822` | canSaveSkill (save reusable skills) | No |
| `3298006781` | MSIX updater gate | No |
| `3366735351` | Auto-update on ready state | No |
| `3444158716` | Cowork resources MCP ("visualize" — show_widget tool) | No |
| `3558849738` | Dispatch/Spaces feature (RBe constant) | **Yes** — forced ON in `fix_dispatch_linux.py` |
| `3572572142` | Sessions-bridge init (Dispatch) | **Yes** — forced ON in `fix_dispatch_linux.py` |
| `3691521536` | Stealth updater — nudge updates when no active sessions | No |
| `3723845789` | Additional Cowork tools | No |
| `3885610113` | Model name [1m] suffix for sonnet-4-6/opus-4-6 | No |
| `4116586025` | louderPenguin / Code tab master gate | No (overridden at merger level) |
| `4153934152` | CLAUDE_CODE_SKIP_PRECOMPACT_LOAD | No |
| `4160352601` | VM heartbeat monitoring | No |
| `4201169164` | **Remote orchestrator** (codename "manta") — **removed from GrowthBook** in v1.1.9669; `Hhn()` now returns hardcoded `false` (`Qhn=!1`). Code still exists but is disabled. | Indirectly — sessions-bridge gate forced ON in `fix_dispatch_linux.py` |

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

### Object/Value Flags (j1() / Js())

| Flag ID | Type | Purpose |
|---------|------|---------|
| `476513332` | j1() | Update check interval ticks config |
| `554317356` | j1() | Timer interval config |
| `927037640` | Js() | Subagent model config (`model`, default: `"claude-sonnet-4-6"`) (**new in v1.1.9134**) |
| `1677081600` | j1() | Custom prompt/instruction text |
| `1748356779` | j1() | System prompt / user prompt template config |
| `1978029737` | Js() | OAuth config (disableOauthRefresh, skillsSyncIntervalMs) |
| `2860753854` | j1() | System prompt override text |
| `2893011886` | Js() | Wake scheduler config (enabled, scheduledTasksWakeEnabled, minLeadTimeMs, chainIntervalMs, batteryIntervalMs, acIntervalMs) (**new in v1.1.9134**) |
| `3190506572` | Js() | Chrome permission control (skip_all_permission_checks, disable_javascript_tool) |
| `3300773012` | Js() | Scheduled tasks config (skillDescription, skillPrompt) |
| `3586389629` | j1() | Connection timeout config |
| `3758515526` | Js() | Default marketplace repo config (repo, repoCCD) |

### Listener Flags (wR())

| Flag ID | Purpose |
|---------|---------|
| `180602792` | Cookie change / midnight owl |
| `1978029737` | Skills plugin sync |
| `3572572142` | Sessions-bridge on/off toggle |
| `2940196192` | Artifacts changed listener — triggers re-emit on flag toggle (**new in v1.1.9134**) |

## What We Patch on Linux

### enable_local_agent_mode.py

**Patch 1 - Individual functions:** Remove `process.platform!=="darwin"` gate from `Oun()` (quietPenguin inner). Note: `Tun()` (chillingSlothFeat) had the darwin gate re-introduced in v1.1.9669 (it was removed upstream in v1.1.9134 but came back) — our Patch 1 still handles it. Also inject Linux early-return in `vBe()` (yukonSilver) via `$un()` to bypass its platform gate (though upstream now has native Linux support in `$un()` too — our patch is defensive).

**Patch 3 - Cie merger override:** Append to the `Cie` return object:
```javascript
,quietPenguin:{status:"supported"},louderPenguin:{status:"supported"},chillingSlothFeat:{status:"supported"},chillingSlothLocal:{status:"supported"},yukonSilver:{status:"supported"},yukonSilverGems:{status:"supported"},ccdPlugins:{status:"supported"},computerUse:{status:"supported"}
```

This bypasses the fve() gate by overriding at the merger level (8 total overrides). The spread order ensures our values win:
```
..._b()           -> quietPenguin: {status:"unavailable"}  (from fve)
...our overrides  -> quietPenguin: {status:"supported"}    (wins)
```

Note: `chillingSlothLocal` and `ccdPlugins` overrides are defensive — both are already `{status:"supported"}`, but the overrides protect against future gating. `yukonSilverGemsCache` is NOT overridden but inherits support from the `vBe()` (yukonSilver) function patch in Patch 1b.

### Cowork on Linux (experimental)

As of v1.1.2685, Cowork uses a decoupled architecture with a TypeScript VM client that communicates with an external service over a socket. This makes Linux support feasible:

- **`fix_cowork_linux.py`** patches the VM client loader to include Linux (not just `win32`)
- The Named Pipe path is replaced with a Unix domain socket on Linux
- **`claude-cowork-service`** (separate Go daemon at `/home/patrickjaja/development/claude-cowork-service`) provides native execution backend — 18 RPC methods, process spawning, path remapping
- `chillingSlothFeat`, `chillingSlothLocal`, `yukonSilver`, `yukonSilverGems`, and `ccdPlugins` are all overridden to `{status:"supported"}` in the Cie merger

Without the daemon running, Cowork will show connection errors naturally in the UI.

### Dispatch on Linux (fix_dispatch_linux.py)

Dispatch is a remote task orchestration feature that lets you send tasks from your phone to your desktop. It's built on top of the Cowork sessions infrastructure and uses Anthropic's "environments bridge" API.

**Architecture:** Desktop registers with `POST /v1/environments/bridge`, then long-polls `GET /v1/environments/{id}/work/poll` for incoming work from the mobile client. All traffic routes through Anthropic's servers over TLS — no inbound ports needed.

**What we patch:**
1. **Sessions-bridge init gate** (GrowthBook flags `3572572142` + `4201169164`) — The bridge only initializes when the combined gate `h = f || p` is true (`f` from flag `3572572142`, `p` from flag `4201169164`). On Linux neither flag fires. We force `h=!0` (true).
2. **Remote session control** (GrowthBook flag `2216414644`) — Messages with `channel:"mobile"` throw unless this flag is on. We replace `!Hn("2216414644")` with `!1` at both call sites.
3. **Platform label** (`bhe()`) — Returns "Unsupported Platform" for Linux. We add `case"linux":return"Linux"`.
4. **Telemetry gate** — `di||ns` (darwin||win32) silently drops telemetry on Linux. We extend to include Linux.

**Note on `operon` (Nest):** Do NOT force-enable — requires VM infrastructure (120+ IPC endpoints across 18 sub-interfaces). Currently `{status:"unavailable"}` on Linux (GrowthBook flag `1306813456` not enabled server-side).

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

### Features we do NOT enable

| Feature | Reason |
|---------|--------|
| `nativeQuickEntry` | Requires macOS Swift code |
| `quickEntryDictation` | Requires macOS Swift code |
| `plushRaccoon` | Dictation shortcut, macOS-only |
| `wakeScheduler` | Requires macOS Login Items API + macOS >= 13.0 |
| `floatingAtoll` | macOS window button positioning, disabled for all platforms |
| `operon` | Requires VM infrastructure (Nest); flag not enabled server-side |

### Known Issues (v1.1.9669)

No known issues. Computer-use is fully integrated into `index.js` since v1.1.8359 and working on Linux.

## Debugging Feature Flags

### Check if a feature is reaching the renderer

In the renderer DevTools console:
```javascript
// Features are sent via IPC - check what the renderer received
// Look for the feature-flags IPC channel in the Network/IPC tab
```

### Verify Cie patch applied correctly

```bash
# After patching, search for the override string
rg 'quietPenguin:\{status:"supported"\}' /path/to/index.js
```

### Pattern anchor stability

Feature name strings are stable across versions because they're IPC identifiers used by both main and renderer processes. The `yukonSilverGems:await \w+\(\)` pattern uses the feature name as anchor and `\w+` for the minified function name.

### When updating for new versions

1. Check if `Cie` structure changed (new features added, order changed)
2. Check if fve()-wrapped features changed
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
