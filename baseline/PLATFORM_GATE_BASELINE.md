# Platform Gate Baseline

**Last audited:** 2026-06-26 against **v1.15962.0** (bump v1.15200.0 -> v1.15962.0, full re-minify). Counts: **darwin 76 / win32 125 / linux 10 - all unchanged** vs v1.15200.0. Pure re-minify for gate purposes: every darwin/win32 gate-context diff line is a renamed identifier of an existing gate. The only structural movement is the **removal of one macOS-only gate** - `Kh(A){return process.platform!=="darwin"?A:{cmd:H6i(),args:[A.cmd,...A.args]}}`, the `.app/Contents/Helpers/disclaimer` command wrapper (the `"Helpers","disclaimer"` path string drops 1->0). On Linux this was a pass-through no-op, so its removal is NATIVE churn with no Linux impact (accounts for the strict `!=="darwin"` 41->40 and total platform-conds 272->271). `status:"unavailable"` unchanged at 30; the `!=="darwin"&&!=="win32"->unavailable` capability gate unchanged at 2 (one plain, one GrowthBook `4116586025`/Code-tab). All stable feature anchors unchanged (`tearOffHalo` 5, `framebufferPreview` 2, `louderPenguin` 13, `office365-mcp.mjs` 1, `smol-bin` 6, `wakeScheduler` 15, `grandPrix` 18, `getExternalRelayConfig` 4/`ExternalRelay` 9, `yukonSilver` 14). **No new PORTABLE gate, no new Linux-blocking gate, no reclassification.** Prior (v1.15200.0): darwin 73->76 / win32 124->125 / linux 10 (unchanged). The darwin (+3) and win32 (+1) increases were **re-minify reorg churn plus one new darwin-only identifier**: `getExternalRelayConfig`/`ExternalRelay*` (0->9 occurrences) - a partner/enterprise Chrome-extension native-messaging *relay* (allowlist of third-party partner extension IDs, validated against a compiled identity allowlist), darwin-gated and layered on the already-PATCHED `fix_browser_tools_linux` native-host bridge. Classified **NATIVE/partner-gated** (very-low-value PORTABLE, deliberately declined): core "Claude in Chrome" already works on Linux; this gate only governs optional additional-partner-extension relay. `grandPrix` 16->18 is a new darwin-gated `releaseGrandPrixGrants()` calling the existing macOS BLE scope-seed teardown (NATIVE, unchanged classification). All stable feature anchors unchanged (`tearOffHalo` 5, `framebufferPreview` 2, `louderPenguin` 13, `office365-mcp.mjs` 1, `smol-bin` 6, `wakeScheduler` 15); the `!=="darwin"...!=="win32"...status:"unavailable"` capability gate is unchanged at 2. **No new high-value PORTABLE gate, no new Linux-blocking gate.** Prior (v1.14271.0): darwin 77->73 / win32 137->124 / linux 10 (unchanged). The darwin (-4) and win32 (-13) drops are **pure minified-name reorg churn, not feature removals**: the unique-gate-line diff shows every "new" snippet is a rename of an existing NATIVE/PATCHED gate (dock bounce, Mission Control, plist/registry readers, `/usr/bin/open` vs `start`, install-kind label). `status:"unavailable"` count unchanged at 3 - no new capability gate. **No new PORTABLE gate.** Prior: v1.13576.0 darwin 79->77 / win32 141->137 / linux 9->10 - the net drop there was several mac/win-only gates being **upstreamed** (Linux now covered natively, no patch): the dispatch platform-label `switch` became a ternary returning `"Linux"`; the dispatch telemetry `cn=darwin,zo=win32,cAA=cn||zo`+`if(!cAA)return` gate was removed (telemetry now unconditional); the office-addin connected-file-detection `(darwin||win32)&&await FN(e.app,e.document)` lost its platform gate (now flag-only on `louderPenguinEnabled`); the `setTitleBarOverlay` win32 `getAllWindows().forEach` guard was dropped. The enterprise managed-config darwin/win32 ternary collapsed to a single win32 registry reader; the Cowork `process.platform!=="darwin"&&!=="win32"` gate became `C3i()` with a hardcoded `const A="win32"` arch lookup. `fix_office_addin_linux` was **removed** at v1.13576.0 (obsolete - the gate it widened is gone). The net **drop** is several mac/win-only gates being **upstreamed** (Linux now covered natively, no patch): the dispatch platform-label `switch` became a ternary returning `"Linux"`; the dispatch telemetry `cn=darwin,zo=win32,cAA=cn||zo`+`if(!cAA)return` gate was removed (telemetry now unconditional); the office-addin connected-file-detection `(darwin||win32)&&await FN(e.app,e.document)` lost its platform gate (now flag-only on `louderPenguinEnabled`); the `setTitleBarOverlay` win32 `getAllWindows().forEach` guard was dropped. The enterprise managed-config darwin/win32 ternary collapsed to a single win32 registry reader; the Cowork `process.platform!=="darwin"&&!=="win32"` gate became `C3i()` with a hardcoded `const A="win32"` arch lookup. **No new PORTABLE gate.** `fix_office_addin_linux` was **removed** (obsolete - the gate it widened is gone). Prior: v1.12603.1 darwin 79 / win32 141 / linux 9 (unchanged from v1.12603.0).

This is the **re-audit baseline** for the question *"is there anything we could make Linux-compatible that we don't already?"* It records every macOS/Windows-only gate found in the bundle and **why it is or isn't patched**, so future audits skip ground that's already been settled.

Treat it like `ION.md` and `CLAUDE_FEATURE_FLAGS.md`: minified names change every release, so anchor on the **stable feature-name strings** (e.g. `tearOffHalo`, `framebufferPreview`) and the **classification**, not the minified function names.

## How to re-audit (run on a version update)

```bash
NEW=/tmp/claude-new/app/.vite/build/index.js   # extracted main bundle

# 1. Count platform conditionals — large swing vs the baseline below = investigate
echo "darwin: $(rg -o 'platform==="darwin"' "$NEW" | wc -l)"   # baseline v1.15962.0: 76 (v1.15200.0: 76, v1.14271.0: 73, v1.13576.0: 77, v1.12603.1: 79, v1.11847.5: 73, v1.10628.0: 65; unchanged vs v1.15200)
echo "win32:  $(rg -o 'platform==="win32"'  "$NEW" | wc -l)"   # baseline v1.15962.0: 125 (v1.15200.0: 125, v1.14271.0: 124, v1.13576.0: 137, v1.12603.1: 141, v1.11847.5: 122; unchanged)
echo "linux:  $(rg -o 'platform==="linux"'  "$NEW" | wc -l)"   # baseline v1.15962.0: 10 (v1.15200.0: 10, v1.14271.0: 10, v1.13576.0: 10, v1.12603.1: 9, v1.11847.5: 5)

# 2. List darwin/win32-only gates (the audit surface)
rg -o '.{0,60}process\.platform==="darwin".{0,80}' "$NEW" | sort -u
rg -o '.{0,60}process\.platform==="win32".{0,80}'  "$NEW" | sort -u
rg -o '.{0,80}!=="darwin".{0,40}!=="win32".{0,80}' "$NEW" | sort -u   # "not mac and not win -> unavailable"

# 3. Find capability gates that return unavailable
rg -o '.{0,80}status:"unavailable".{0,40}' "$NEW" | sort -u
```

Then for each gate, classify it against the table below. **Only a gate that doesn't map to an existing row is a new finding** — and only `PORTABLE` findings are actionable.

## Classification key

| Class | Meaning | Action |
|-------|---------|--------|
| **PATCHED** | Already made Linux-compatible by one of the 48 patches | None - already done |
| **NATIVE** | Genuine macOS/Windows native-API dependency with no Linux analog | None — not portable |
| **STUB** | Disabled on **all** platforms (hardcoded `!1`, prod-gate, or dev-prototype) — not a Linux exclusion | None — nothing behind it to enable |
| **PORTABLE** | Gated to mac/win only, no real native dependency, works on Linux if widened | **Patch candidate** |

---

## NATIVE — genuinely not portable (do NOT attempt)

These depend on Apple/Windows frameworks with no Linux equivalent. Verified against v1.9659.2.

| Feature | Stable anchor | Native dependency | Evidence |
|---------|--------------|-------------------|----------|
| `tearOffHalo` / Window Halo MCP server | `tearOffHalo`, `"Window Halo"`, `halo_attach`/`halo_detach` | macOS NSView/CALayer compositing via `@ant/claude-swift` (8 refs in bundle) | `await import("@ant/claude-swift")`; server `isEnabled:()=>process.platform==="darwin"&&!1` (disabled even on mac) |
| `wakeScheduler` | `wakeScheduler` | macOS Login Items (ServiceManagement) + IOKit wake-from-sleep | `wakeScheduler:Dm(Jsr)` - prod-gated + macOS-only Login Items. No Linux app-launch-at-wake analog (systemd timers can't hook the same path). |
| `grandPrix` | `"grandPrix"`, `grandPrix:Psr()` | Apple BLE device-pairing state (`IOBluetoothDevice`) | darwin-only, checks paired Apple devices - no "paired Apple device" concept on Linux |
| `grandPrixRequest` | `grandPrixRequest` | macOS XPC/mach service requests | darwin-only service-request routing |
| `getExternalRelayConfig` / `ExternalRelay*` | `getExternalRelayConfig`, `ExternalRelay` | none (config allowlist passthrough), but layered on the macOS extension-relay context | New in v1.15200.0 (`...process.platform==="darwin"&&{getExternalRelayConfig:sie}`, 9 refs). Builds an allowlist of third-party **partner** Chrome-extension IDs and relays native-messaging to them. Very-low-value PORTABLE deliberately declined: core "Claude in Chrome" already works on Linux via `fix_browser_tools_linux`; this only governs an optional additional-partner-extension relay. Revisit only if a partner-extension relay use case surfaces on Linux. |
| `nativeQuickEntry` dictation | `quickEntryDictation` | Apple speech APIs | macOS-only; Linux Quick Entry itself **is** patched (`fix_quick_entry_*`), only the *dictation* sub-feature is native |
| macOS app-menu roles | n/a | `services`, `hideOthers`, `about-panel` are AppKit roles | Genuinely mac-only menu roles — ignore, not user-relevant on Linux |

## STUB — disabled on all platforms (NOT a Linux issue)

Force-enabling these gets you a hardcoded error or an empty/unimplemented feature — they aren't gated *against Linux*, they're just not shipped yet.

| Feature | Stable anchor | Why it's a stub | Evidence |
|---------|--------------|-----------------|----------|
| `framebufferPreview` / Framebuffer MCP server | `framebufferPreview`, `"Framebuffer"`, `framebuffer_screenshot` | Prod-gate + GrowthBook flag, **no platform check at all**. Server handler hardcoded to error. | `function xsr(){return Dm(()=>It("1928275548")?{status:"supported"}...)}` (no darwin/win32); server registered with `isEnabled:r=>!1` and `handleToolCall` returns `"Framebuffer preview unavailable."` |
| `ios_simulator` / `android_emulator` MCP servers | `"ios_simulator"`, `"android_emulator"` | Reserved labels in the server-UUID map with **no server implementation** (precursors for future MCP servers) | Present only as UUID-map labels; no tool list / handler. Since at least v1.11847.5 they also appear as prod-gated capability keys (`iosSimulator:vR(eje)` in v1.12603.0 - `vR` is the `app.isPackaged?{status:"unavailable"}` prod gate) |
| `artifactsPane` | `artifactsPane`, GrowthBook `2115990222` | New capability key in v1.12603.0. GrowthBook-flag-gated only - **no platform check, no prod gate** - so it is available on Linux whenever the flag rolls out. Not a Linux exclusion; nothing to patch. | `function DPt(){return dt("2115990222")?{status:"supported"}:{status:"unavailable"}}` feeding `function sD(){return{artifactsPane:DPt(),...` (v1.12603.0 names; absent from v1.11847.5) |
| `echo` MCP server | `"echo"` | Label in UUID map, no observable tool/handler — debug/test placeholder | Map entry only |
| `midnightOwl` | `midnightOwl prototype`, `isMidnightOwlEnabled` | Dev-prototype toggle; registration immediately calls `.setEnabled(!1)` | `kh("180602792",e=>{Mr&&Mr.midnightOwl.setEnabled(!1)})` - sublabel literally *"Enables midnightOwl prototype"* |
| dev-gated features (`plushRaccoon`, `quietPenguin`, `chatIn3p`, `surfaceTogglesPreview`, etc.) | see `CLAUDE_FEATURE_FLAGS.md` | Wrapped by the production gate (`vR()` in v1.12603.0, was `Dm()`/`OS()`/`um()`/`Em()`/`lm()`/`PM()`): `{status:"unavailable"}` in **all** packaged builds | `function vR(A){return cA.app.isPackaged?{status:"unavailable"}:A()}` (v1.12603.0). Note: `builtinMcpPresets` was prod-gated through v1.11847.5 (`builtinMcpPresets:xur(()=>Bu)`) but is unconditionally `{status:"supported"}` (`builtinMcpPresets:aB`) as of v1.12603.0 - upstreamed to all platforms incl. Linux, nothing to patch |

## PORTABLE — actionable opportunities

**Currently: NONE.**

As of v1.12603.0, every darwin/win32-only gate maps to PATCHED, NATIVE, or STUB. There is no feature that is (a) gated to mac/win only, (b) free of a real native dependency, and (c) not already patched. If a future release adds one, it goes here with the exact gate snippet and a proposed patch.

(v1.12603.0 counts: darwin 79 / win32 141 / linux 9 / `!=="linux"` 6. The +6/+19/+4/+2 swing vs v1.11847.5 looks alarming but is entirely a **second vendored copy of Claude Code CLI/SDK helper code** - the +1.5MB bundle growth. Every new-side diff line is either a minified-name rename of an old gate or an exact duplicate of a vendored helper: NFC-normalize `A.normalize("NFC")` x2 more, os-name/WSL-detect x2, Linux signal-list x2, which/cross-spawn/isexe/supports-color x2, `claude-code-user` 1->2. Verified by stable-string counts: `openssh-ssh-agent`, `filter.lfs.required`, `screenshotFiltering:"native"`, `Native host sync`, `Open Claude`, `Install kind:`, `office365-mcp.mjs`, `smol-bin` vhdx, `louderPenguin` (10 refs) all unchanged old vs new. The capability map gained exactly one key, `artifactsPane` - flag-gated, no platform check, see STUB table. Earlier history: v1.11847.5 was darwin 73 / win32 122 / linux 5; v1.10628.2 was darwin 65 / win32 113 / linux 5, identical to v1.10628.0.)

## PATCHED - already Linux-compatible (48 patches)

These map to existing `patches/*.nim`. If a re-audit surfaces a gate touching one of these areas, it's already handled — don't re-flag it. (See the README patch table for the authoritative list.)

- **Compute/agent:** computer use (`fix_computer_use_linux`, `fix_computer_use_tcc`), cowork & local agent mode & VM sessions (`fix_cowork_*`, `fix_vm_session_handlers`, `enable_local_agent_mode`), Claude Code (`fix_claude_code`), dispatch (`fix_dispatch_linux`, `fix_dispatch_outputs_dir`)
- **Servers/integrations:** office add-in / "office" MCP (no patch as of v1.13576.0 - upstream dropped the connected-file-detection platform gate; now flag-only on `louderPenguinEnabled`, which `enable_local_agent_mode` forces; `fix_office_addin_linux` removed), browser tools / Claude in Chrome (`fix_browser_tools_linux`), buddy BLE / hardware buddy (`fix_buddy_ble_linux`), imagine/visualize (`fix_imagine_linux`), marketplace (`fix_marketplace_linux`)
- **Config/paths:** enterprise config `/etc/claude-desktop` (`fix_enterprise_config_linux`), ion-dist org-plugins mountPath (`fix_ion_dist_linux`), detected projects (`fix_detected_projects_linux`), sensitive dirs (`fix_sensitive_dirs_linux`), locale paths (`fix_locale_paths`)
- **Window/shell/UI:** tray + DBus + icon (`fix_tray_dbus`, `fix_tray_icon_theme`), quick entry (`fix_quick_entry_*`), native frame / window bounds / dock bounce (`fix_native_frame*`, `fix_window_bounds`, `fix_dock_bounce`), custom themes (`add_feature_custom_themes`), startup settings (`fix_startup_settings`), profile routing/title (`fix_profile_*`)
- **Process/updater:** updater state + disable autoupdate (`fix_updater_state_linux`, `fix_disable_autoupdate`), node host / app quit / utility-process kill / cross-device rename / asar drop+cwd / process argv (`fix_0_node_host`, `fix_app_quit`, `fix_utility_process_kill`, `fix_cross_device_rename`, `fix_asar_*`, `fix_process_argv_renderer`)

## Note: `louderPenguin` (the Code tab)

`louderPenguin` (Code tab) has a **real** `darwin||win32` gate (v1.12603.0 shape - now async and additionally GrowthBook-gated by `4116586025`, same semantics since at least v1.11847.5):
```js
async function fqr(){return process.platform!=="darwin"&&process.platform!=="win32"?{status:"unavailable"}:(await kk(),dt("4116586025")?{status:"supported"}:{status:"unavailable"})}
```
This is **not** a native dependency — it's a server-side rollout gate. It is **already handled**: `enable_local_agent_mode.nim` force-enables `louderPenguin` in its 12-flag override list, so Linux gets the Code tab. Don't list it as an opportunity — it's PATCHED.

## Caveats

- **No source maps.** This audit is static analysis of minified production JS. A feature that is *silently degraded* on Linux (rather than explicitly gated) won't appear here — that only surfaces through runtime testing on a real Linux session. If a specific feature feels worse on Linux than it should, trace that code path directly rather than relying on this baseline.
- **Upstream no longer serves prior-version MSIX metadata,** so a true binary gate-diff against the previous version isn't possible. Re-audit by comparing the conditional counts + gate list above against a freshly extracted bundle.
