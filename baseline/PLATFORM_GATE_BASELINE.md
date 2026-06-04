# Platform Gate Baseline

**Last audited:** 2026-06-04 against **v1.10628.2** (re-minify point release on v1.10628.0; counts unchanged)

This is the **re-audit baseline** for the question *"is there anything we could make Linux-compatible that we don't already?"* It records every macOS/Windows-only gate found in the bundle and **why it is or isn't patched**, so future audits skip ground that's already been settled.

Treat it like `ION.md` and `CLAUDE_FEATURE_FLAGS.md`: minified names change every release, so anchor on the **stable feature-name strings** (e.g. `tearOffHalo`, `framebufferPreview`) and the **classification**, not the minified function names.

## How to re-audit (run on a version update)

```bash
NEW=/tmp/claude-new/app/.vite/build/index.js   # extracted main bundle

# 1. Count platform conditionals — large swing vs the baseline below = investigate
echo "darwin: $(rg -o 'platform==="darwin"' "$NEW" | wc -l)"   # baseline v1.10628.0: 65 (v1.9659.4: 64)
echo "win32:  $(rg -o 'platform==="win32"'  "$NEW" | wc -l)"   # baseline v1.10628.0: 113 (v1.9659.4: 112)
echo "linux:  $(rg -o 'platform==="linux"'  "$NEW" | wc -l)"   # baseline v1.10628.0: 5 (unchanged)

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
| `nativeQuickEntry` dictation | `quickEntryDictation` | Apple speech APIs | macOS-only; Linux Quick Entry itself **is** patched (`fix_quick_entry_*`), only the *dictation* sub-feature is native |
| macOS app-menu roles | n/a | `services`, `hideOthers`, `about-panel` are AppKit roles | Genuinely mac-only menu roles — ignore, not user-relevant on Linux |

## STUB — disabled on all platforms (NOT a Linux issue)

Force-enabling these gets you a hardcoded error or an empty/unimplemented feature — they aren't gated *against Linux*, they're just not shipped yet.

| Feature | Stable anchor | Why it's a stub | Evidence |
|---------|--------------|-----------------|----------|
| `framebufferPreview` / Framebuffer MCP server | `framebufferPreview`, `"Framebuffer"`, `framebuffer_screenshot` | Prod-gate + GrowthBook flag, **no platform check at all**. Server handler hardcoded to error. | `function xsr(){return Dm(()=>It("1928275548")?{status:"supported"}...)}` (no darwin/win32); server registered with `isEnabled:r=>!1` and `handleToolCall` returns `"Framebuffer preview unavailable."` |
| `ios_simulator` / `android_emulator` MCP servers | `"ios_simulator"`, `"android_emulator"` | Reserved labels in the server-UUID map with **no server implementation** (precursors for future MCP servers) | Present only as UUID-map labels; no tool list / handler |
| `echo` MCP server | `"echo"` | Label in UUID map, no observable tool/handler — debug/test placeholder | Map entry only |
| `midnightOwl` | `midnightOwl prototype`, `isMidnightOwlEnabled` | Dev-prototype toggle; registration immediately calls `.setEnabled(!1)` | `kh("180602792",e=>{Mr&&Mr.midnightOwl.setEnabled(!1)})` - sublabel literally *"Enables midnightOwl prototype"* |
| dev-gated features (`plushRaccoon`, `quietPenguin`, `bootstrapConfig`, `builtinMcpPresets`, etc.) | see `CLAUDE_FEATURE_FLAGS.md` | Wrapped by the production gate (`Dm()` in v1.10628.0, was `um()`/`Em()`/`lm()`/`PM()`): `{status:"unavailable"}` in **all** packaged builds | `function Dm(e){return aA.app.isPackaged?{status:"unavailable"}:e()}` |

## PORTABLE — actionable opportunities

**Currently: NONE.**

As of v1.10628.2, every darwin/win32-only gate maps to PATCHED, NATIVE, or STUB. There is no feature that is (a) gated to mac/win only, (b) free of a real native dependency, and (c) not already patched. If a future release adds one, it goes here with the exact gate snippet and a proposed patch. (v1.10628.2 counts: darwin 65, win32 113, linux 5 - **exactly identical to v1.10628.0**, zero swing; the re-minify point release added no platform gates. v1.10628.0 was darwin 65 / win32 113 / linux 5, the +1/+1 vs v1.9659.4 being re-minify noise.)

## PATCHED - already Linux-compatible (48 patches)

These map to existing `patches/*.nim`. If a re-audit surfaces a gate touching one of these areas, it's already handled — don't re-flag it. (See the README patch table for the authoritative list.)

- **Compute/agent:** computer use (`fix_computer_use_linux`, `fix_computer_use_tcc`), cowork & local agent mode & VM sessions (`fix_cowork_*`, `fix_vm_session_handlers`, `enable_local_agent_mode`), Claude Code (`fix_claude_code`), dispatch (`fix_dispatch_linux`, `fix_dispatch_outputs_dir`)
- **Servers/integrations:** office add-in / "office" MCP (`fix_office_addin_linux`), browser tools / Claude in Chrome (`fix_browser_tools_linux`), buddy BLE / hardware buddy (`fix_buddy_ble_linux`), imagine/visualize (`fix_imagine_linux`), marketplace (`fix_marketplace_linux`)
- **Config/paths:** enterprise config `/etc/claude-desktop` (`fix_enterprise_config_linux`), ion-dist org-plugins mountPath (`fix_ion_dist_linux`), detected projects (`fix_detected_projects_linux`), sensitive dirs (`fix_sensitive_dirs_linux`), locale paths (`fix_locale_paths`)
- **Window/shell/UI:** tray + DBus + icon (`fix_tray_dbus`, `fix_tray_icon_theme`), quick entry (`fix_quick_entry_*`), native frame / window bounds / dock bounce (`fix_native_frame*`, `fix_window_bounds`, `fix_dock_bounce`), custom themes (`add_feature_custom_themes`), startup settings (`fix_startup_settings`), profile routing/title (`fix_profile_*`)
- **Process/updater:** updater state + disable autoupdate (`fix_updater_state_linux`, `fix_disable_autoupdate`), node host / app quit / utility-process kill / cross-device rename / asar drop+cwd / process argv (`fix_0_node_host`, `fix_app_quit`, `fix_utility_process_kill`, `fix_cross_device_rename`, `fix_asar_*`, `fix_process_argv_renderer`)

## Note: `louderPenguin` (the Code tab)

`louderPenguin` (Code tab) has a **real** `darwin||win32` gate:
```js
function Fsr(){return process.platform!=="darwin"&&process.platform!=="win32"?{status:"unavailable"}:...}
```
This is **not** a native dependency — it's a server-side rollout gate. It is **already handled**: `enable_local_agent_mode.nim` force-enables `louderPenguin` in its 12-flag override list, so Linux gets the Code tab. Don't list it as an opportunity — it's PATCHED.

## Caveats

- **No source maps.** This audit is static analysis of minified production JS. A feature that is *silently degraded* on Linux (rather than explicitly gated) won't appear here — that only surfaces through runtime testing on a real Linux session. If a specific feature feels worse on Linux than it should, trace that code path directly rather than relying on this baseline.
- **Upstream no longer serves prior-version MSIX metadata,** so a true binary gate-diff against the previous version isn't possible. Re-audit by comparing the conditional counts + gate list above against a freshly extracted bundle.
