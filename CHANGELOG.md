# Changelog

All notable changes to claude-desktop-bin AUR package will be documented in this file.

## 2026-04-26 — Multi-profile follow-ups

Review feedback fixes applied on top of the multi-profile feature:

- **Fix: cowork is broken for named profiles.** The previous round suffixed the cowork socket path with `-NAME` on the client (Electron) side, but `cowork-svc-linux` is a separate user-level daemon that listens on the unsuffixed `cowork-vm-service.sock` only. Named profiles silently failed to reach the daemon. Reverted in `patches/fix_cowork_linux.nim` — all profiles share the daemon. Per-profile state still flows correctly: the spawned `claude` CLI inherits `CLAUDE_CONFIG_DIR=~/.claude-NAME` and uses a per-profile `--plugin-dir` derived from `app.getPath("userData")`, so cowork's stateless spawning produces correctly-scoped sessions per profile.
- **Fix: per-profile binary stale after package upgrades.** Hardlinks/reflinks/copies snapshot the system Electron at `--create-profile` time. Package upgrades (and NixOS rebuilds where store paths move) leave the per-profile copy on the old version, producing a version mismatch with the upgraded `app.asar`. The launcher now auto-detects staleness on every named-profile launch (canonical newer than per-profile, or per-profile non-executable, or any sibling symlink dangling) and re-materialises the binary plus refreshes the symlink mirror. Also factored the materialise/mirror logic into reusable helpers (`_materialise_profile_binary`, `_mirror_profile_siblings`, `_canonical_electron_bin`, `_refresh_profile_binary_if_stale`).
- **Fix: PipeWire portal restore token leaked across profiles.** `js/cu_linux_executor.js` hardcoded `~/.config/Claude/pipewire-restore-token` in both the Node side and the embedded Python script — bypassing `app.getPath("userData")`. Switched to userData (per-profile) on the Node side, and pass the path into the Python via the `CLAUDE_PORTAL_TOKEN_PATH` env var.
- **Fix: silent UX degradation when `--profile=NAME` is used without `--create-profile`.** The launcher now prints a one-line stderr hint pointing at `--create-profile` when the per-profile binary doesn't exist. Suppress with `CLAUDE_PROFILE_QUIET=1`.
- **Fix: competing `claude://` URL handlers.** `--create-profile` no longer copies `MimeType=` from the system `.desktop` into the per-profile entry. Only the system entry claims the scheme; routing to the right profile happens via the auth-marker mechanism.

---

## 2026-04-25 — Multi-profile support

- **Feature: named profiles for multi-account use.** Run several Claude Desktop windows side by side, each logged in to a different account, with fully isolated state for both Desktop and the Claude Code CLI it spawns.
  - New launcher subcommands: `--create-profile=NAME`, `--delete-profile=NAME`, `--list-profiles`
  - New flags / env: `--profile=NAME`, `CLAUDE_PROFILE=NAME`. Also auto-resolved from the launcher's basename (e.g. `claude-desktop-work`)
  - Per-profile isolation:
    - Electron userData via `--user-data-dir` (login, logs, settings, spaces, custom themes — anything reached through `app.getPath("userData")`)
    - Claude Code config via `CLAUDE_CONFIG_DIR` (`~/.claude-NAME`)
    - Cowork VM-service socket (`patches/fix_cowork_linux.nim`) — suffixed with profile name
    - Quick Entry toggle socket (`patches/fix_quick_entry_cli_toggle.nim`) — suffixed with profile name
    - systemd user scope name — suffixed with profile name
    - WM_CLASS / Wayland app_id — `--create-profile` materialises a per-profile Electron binary at `~/.local/lib/claude-desktop/<APP_ID>-NAME` (hardlink → reflink → copy fallback, ~200 MB on cross-fs ext4, near-zero-cost on btrfs/xfs reflinks). A real distinct file is required because the kernel resolves symlinks for `/proc/self/exe`, which Electron uses to derive its app identity. Generated `.desktop` files use an absolute `Exec=` path so they don't depend on `~/.local/bin` being in `$PATH`
    - SSO callback routing — new patch `fix_profile_url_routing.nim` hooks `shell.openExternal` to write a marker at `$XDG_RUNTIME_DIR/claude-desktop-pending-auth-NAME` whenever a profile opens an auth-ish URL. The launcher reads markers (5-min TTL, most-recent wins) when handling incoming `claude://` URLs and re-execs as the right profile so login completes in the originating window. See README ("SSO and URL routing") for semantics and known limits.
    - XDG autostart (`patches/fix_startup_settings.nim`) — "Start at login" toggles a per-profile autostart file `~/.config/autostart/com.anthropic.claude-desktop[-NAME].desktop` with `Exec=/usr/bin/claude-desktop [--profile=NAME] --startup`, so each profile's autostart state is tracked independently and the right profile auto-starts at login.
    - Quick Entry main-window app_id reset (`patches/fix_quick_entry_app_id.nim`) — the post-Quick-Entry `CHROME_DESKTOP` / `app.setDesktopName()` reset is computed at runtime from `CLAUDE_PROFILE`, so settings dialogs and other windows opened after Quick Entry get the correct per-profile app_id rather than the unsuffixed default.
  - The default profile (no `--profile` flag, no `CLAUDE_PROFILE` env) is byte-identical to the previous single-instance behavior — no migration needed for existing users.
  - Plugins, MCP servers, and login state are intentionally not shared between profiles.

---

## 2026-04-25 (v1.4758.0) — Upstream update, 6 patches fixed, 2 new feature flags, GNOME session restore fix

- **Fix:** "Start in system tray" now works with GNOME session restore ([#67](https://github.com/patrickjaja/claude-desktop-bin/pull/67)). GNOME's `gnome-session-service` re-launches saved apps after reboot without the `--startup` flag, so Claude's main window would always appear even when "Start in system tray" was enabled. New heuristic: checks the mtime of the Wayland compositor socket (or D-Bus bus socket on X11) — if Claude starts within 60s of that timestamp, it assumes session-restore and suppresses the main window. — contributed by [@boommasterxd](https://github.com/boommasterxd)
- **Version bump:** v1.3883.0 → v1.4758.0
- **6 patches updated:**
  - `enable_local_agent_mode.nim` — yukonSilver `formatMessage` now called via `Qe().formatMessage` (function invocation before property access); made `()` optional in regex with `(?:\(\))?` to match both old and new intl forms. Added 2 new GrowthBook force-ON patches (3d: `chillingSlothPool` flag `1992087837`, 3e: `markTaskComplete` flag `3732274605`). Merger overrides expanded from 10 to 12. — regex improvement contributed by [@boommasterxd](https://github.com/boommasterxd)
  - `fix_asar_workspace_cwd.nim` — `checkTrust`/`saveTrust` methods gained intermediate `DQ()` path expansion call. Simplified regex to match method signature only (not body), making it robust against future body changes.
  - `fix_computer_use_linux.nim` — CU teach overlay gate moved from after TCC stub to before it (ternary wrapping). Added before-stub ternary check alongside existing after-stub check.
  - `fix_dock_bounce.nim` — Removed `backgroundThrottling` sub-patch (EXPECTED_PATCHES 4→3). Upstream dropped `backgroundThrottling:!1` from webPreferences; Electron now uses its default (`true`), which is what our patch was achieving.
  - `fix_ion_dist_linux.nim` — Platform enum variable renamed `W`→`G` in ion-dist SPA. Changed from hardcoded literal matching to regex capture for dynamic enum variable detection.
  - `fix_locale_paths_pre.nim` — **Removed.** Redundant with `fix_locale_paths.nim` which already handles `index.pre.js` (lines 68-81). Upstream also removed `process.resourcesPath` from `index.pre.js` in this release.
- **2 new feature flags** (22 total, was 20): `chillingSlothPool` (concurrent session pooling, GrowthBook `1992087837`), `markTaskComplete` (task completion, GrowthBook `3732274605`)
- **1 feature moved:** `louderPenguin` moved from static registry to async-only (now solely in $yA merger)
- **0** new MCP servers (17 remain), **0** new `process.platform` gates requiring patches

---

## 2026-04-23 (v1.3883.0) — Bundle all upstream resources, 3P Inference, theme fixes, CI fix, XDG autostart

- **Fix:** "Start at login" toggle now works on Linux ([#60](https://github.com/patrickjaja/claude-desktop-bin/issues/60), [#61](https://github.com/patrickjaja/claude-desktop-bin/pull/61)). The previous patch disabled startup settings entirely on Linux (always returned `false`, write was a no-op). Replaced with proper XDG autostart management: creates/removes `~/.config/autostart/com.anthropic.claude-desktop.desktop` with `Exec=claude-desktop --startup` so the app starts hidden in tray. The toggle now correctly reflects actual autostart state. — contributed by [@boommasterxd](https://github.com/boommasterxd)

- **Fix:** Third-Party Inference configuration now works on Linux ([#57](https://github.com/patrickjaja/claude-desktop-bin/issues/57)). The `ion-dist/` web frontend (85MB, 842 files) was missing from the package — the `app://` protocol handler had nothing to serve. Main process code is already Linux-compatible; the SPA needed minor patching (see below).
- **New patch: `fix_ion_dist_linux.nim`** — patches the ion-dist 3P configuration SPA for Linux:
  - Adds Linux org-plugins mount path (`/etc/claude-desktop/org-plugins`) — upstream only has macOS and Windows paths, so on Linux it showed the macOS path
  - Fixes mount-path display component to use the Linux path when `platform === "linux"` instead of falling back to macOS
  - Dynamically finds the target JS file (content-hashed filename changes every upstream release)
- **Updated: `fix_vm_session_handlers.nim`** — extended IPC error suppression to also cover `LocalSessions` and `QuickEntry` handlers (in addition to existing `ClaudeVM` and `LocalAgentModeSessions`)
- **Build: future-proof resource copying** — replaced individual `cp` commands for locales, tray icons, claude-ssh, and cowork-plugin-shim with a bulk copy of all upstream resources to `locales/`. Windows-only files (`.exe`, `.dll`, `.vhdx`, `.ico`) are excluded. New resources Anthropic adds in future releases will be automatically included.
- **Build: ion-dist post-copy patching** — new build step applies `fix_ion_dist_linux` to ion-dist after resource copy, with graceful skip if ion-dist or the patch binary is unavailable
- **Newly bundled resources:** `ion-dist/` (web frontend), `fonts/`, `drizzle/` (DB migrations), `seed/`, `claude-screen*.png`
- **Fix:** Custom theme `chatFont` override now applies to user-sent messages (not just Claude responses). Added `[data-user-message-bubble]` selectors to both the main theme injection and the cowork font fix.
- **Fix:** `generate-pkgbuild.sh` caches the Electron version in `build/.electron-version` to avoid GitHub API rate limits on repeated builds. Delete the cache file to force a re-fetch.
- **Fix:** CI `deploy-rpm-repo` job failed because `.deb`/`.rpm` packages (~129MB each) exceed GitHub's 100MB git file size limit. Switched from `git push --force` to artifact-based Pages deployment (`actions/upload-pages-artifact` + `actions/deploy-pages`), which supports up to 10GB. No URL or user-facing changes — APT/RPM repos work exactly as before.
- **Docs:** Removed `--install` from CLAUDE.md build examples.

---

## 2026-04-22 (v1.3883.0) — Upstream update, 1 patch fixed, Live Artifacts

- **Version bump:** v1.3561.0 → v1.3883.0
- **1 patch updated:** `fix_dispatch_linux.nim` — Patch F (rjt() text forward) updated to match new upstream pattern. Upstream expanded the message filter with dispatch tool name variables (`SU`/`T4`) behind a gate parameter; our patch now preserves the upstream additions while adding `mcp__dispatch__send_message` and `mcp__cowork__present_files`. Also fixed Patch E idempotency (Jr() already-applied detection used hardcoded param name `t` instead of regex).
- **New feature flag:** `coworkArtifacts` (20 total features, was 19) — persistent HTML artifact storage in cowork sessions (`create_artifact`, `update_artifact`, `list_artifacts` tools). Force-enabled on Linux: merger override + GrowthBook `2940196192` forced ON (4 call sites) in `enable_local_agent_mode.nim`.
- **Live Artifacts working on Linux** — requires [claude-cowork-service](https://github.com/patrickjaja/claude-cowork-service) fix: reverse mount path remapping was applied unconditionally, producing `/sessions/` paths that don't exist on native Linux
- **2** new GrowthBook flags: `2049450122` (session handoff), `2192324205` (dispatch structured content forwarding); **0** removed
- **0** new MCP servers (17 remain), **0** new `process.platform` gates
- Locale i18n JSON files removed from `app.asar` (moved to `resources/` alongside asar — build script already handles this)
- New `@ant/claude-swift` module (macOS-only, no Linux impact)
- `@ant/claude-native-binding.node` now bundled inside asar (handled by existing native shim)

### Upstream diff summary (v1.3561.0 → v1.3883.0)

Variable renames only (all handled by `\w+`/`[\w$]+` wildcards):
- Static registry: `A_()` → `s_()`
- Async merger: `gwA` → `FwA`
- Production gate: `GGA()` → `lUA()`
- Flag reader: `fi()` → `Ii()`
- Listener: `bG()` → `FG()`
- Value flags: `zn()`/`f_()` → `y_()`/`zn()`
- MCP registration: `gpA()` → `FpA()`

---

## 2026-04-20 (v1.3561.0) — Upstream update, all patches applied (no fixes needed)

- **Version bump:** v1.3109.0 → v1.3561.0
- **All 42 patches applied without modification** — webpack re-minify only, no structural changes
- **2** new GrowthBook boolean flags: `1496676413` (SSH plugins/MCP forwarding), `2023768496` (trusted device token); **0** removed
- `123929380` (coworkKappa) promoted to force-ON defaults map — Anthropic enabling consolidate-memory by default
- **0** new MCP servers, **0** new tools (same 17 servers)
- **0** new `process.platform` gates — no new Linux restrictions
- Locale i18n files moved into `ion-dist/i18n/` with `.overrides.json` sidecar files (same language set)

### Upstream diff summary (v1.3109.0 → v1.3561.0)

Variable renames only (all handled by `\w+`/`[\w$]+` wildcards):
- Static registry: `J0()` → `A_()`
- Async merger: `ewA` → `gwA`
- Production gate: `aFA()` → `GGA()`
- Flag reader: `Ti()` → `fi()`
- Listener: `wG()` → `bG()`
- Value flags: `Es()`/`di()` → `zn()`/`f_()`
- MCP registration: `DfA()` → `gpA()`
- Platform vars: `ws` → `ys` (win32), `WhA` → `bfA` (darwin||win32), `en` unchanged (darwin)
- Computer-use Set: `ele` → `rwA`, checker `Jne()` → `nBA()`

---

## 2026-04-20 — Fix Cowork font preference + theme font override ([#52](https://github.com/patrickjaja/claude-desktop-bin/issues/52))

### Fixed
- **Cowork tab font**: The Cowork tab rendered with default Serif font instead of the user's chosen font preference. The claude.ai SPA lazy-initializes font preferences when the Chat view mounts — if Cowork is visited first, the font was wrong. Fixed by injecting CSS on `dom-ready` that reads the font preference from localStorage and applies it immediately. (`fix_cowork_font.nim`)

### Added
- **Theme `chatFont` override**: Custom themes can now override the chat font via a `"chatFont"` key in `~/.config/Claude/claude-desktop-bin.json`. Works per-theme or as a global setting. Only system-installed fonts are supported (`fc-list` to browse).

---

## 2026-04-19 — Quick Entry: socket trigger + Wayland retry gate + timeout reductions (#47, based on PR #50 by @boommasterxd)

### Added
- **`claude-desktop --toggle`**: Fast Quick Entry toggle via Unix domain socket.
  Toggles in ~5-25 ms instead of ~300 ms (no Electron process spawn). Starts the
  app automatically if not running.
  **GNOME users:** run `claude-desktop --install-gnome-hotkey` once to update the
  stored shortcut command.

### Performance
- **`fix_quick_entry_cli_toggle`** (sub-patch D): Unix domain socket server
  injected on startup. Any connection directly calls the Quick Entry toggle
  handler, bypassing the Electron process-spawn + `second-instance` IPC path.
- **`fix_quick_entry_cli_toggle`**: Debounce window reduced from 900 ms to
  100 ms. The GNOME double-fire regression (issue #38) is eliminated by the
  socket path bypassing `second-instance` entirely.
- **`fix_quick_entry_position`**: Position+focus retries (50/150/300 ms) gated
  to X11 only. On Wayland the compositor never repositions windows after
  `show()`, so the retries caused jitter with no benefit.
- **`fix_quick_entry_ready_wayland`**: `ready-to-show` timeout reduced from
  200 ms to 100 ms (Chromium first-paint on Wayland: typically 30-50 ms).
- **`fix_quick_entry_cli_toggle`**: First-instance trigger delay reduced from
  500 ms to 250 ms.
- **`fix_quick_entry_position`**: `execFileSync` timeouts for `xdotool` and
  `hyprctl` reduced from 200 ms to 100 ms.

---

## 2026-04-19 — Add missing patches to README table

### Fixed
- **README patch table** was missing 4 patches: `fix_locale_paths_pre.nim`, `fix_quick_entry_app_id.nim` ([#39](https://github.com/patrickjaja/claude-desktop-bin/issues/39), [PR #46](https://github.com/patrickjaja/claude-desktop-bin/pull/46)), `fix_quick_entry_cli_toggle.nim`, `fix_quick_entry_wayland_blur_guard.nim`. Updated patch count from 38+ to 42+.

---

## 2026-04-18 — Quick Entry gets its own Wayland app_id ([PR #46](https://github.com/patrickjaja/claude-desktop-bin/pull/46) by [@boommasterxd](https://github.com/boommasterxd))

### Fixed
- **Quick Entry window inherits main window's Wayland `app_id`**, causing shell extensions like GNOME Blur My Shell to apply blur/animations to it. New patch `fix_quick_entry_app_id.nim` sets a distinct `app_id` so compositors can treat Quick Entry differently. Fixes [#39](https://github.com/patrickjaja/claude-desktop-bin/issues/39).

---

## 2026-04-18 — Include patch release in version badges

### Fixed
- **Badge version mismatch**: APT, RPM, AppImage, Nix, and version-check badges showed only the base version (e.g. `v1.3109.0`) while AUR showed the full version with patch release (`v1.3109.0-5`). All badges now include `${PKGREL}` to match.

---

## 2026-04-18 — Bundle Electron instead of depending on system package

### Changed
- **AUR PKGBUILD bundles Electron** from GitHub releases instead of depending on the system `electron` package (flagged out-of-date on Arch, installs to version-specific paths that broke the build). Matches how deb/rpm/AppImage packages already work.
- **Runtime deps** changed from `electron` to `alsa-lib`, `gtk3`, `nss` (the shared libraries bundled Electron links against).
- **Electron version fallback removed** across all packaging scripts (deb, AppImage, AUR). Build now fails with a clear error if the GitHub API is unreachable, instead of silently bundling a stale version.
- **Launcher** updated to search `resources/app.asar` path (new bundled Electron layout).

---

## 2026-04-18 — Fix .gitignore excluding Nim patch sources from CI

### Fixed
- **CI build broken**: `patches/.gitignore` patterns (`fix_*`, `add_*`, `enable_*`) excluded `.nim` source files from git. All 41 Nim patches were never committed, causing CI to apply zero patches and crash on `en-US.json` ENOENT. Added `!*.nim` negation to track sources while still ignoring compiled binaries.
- **Nim compile fails on read-only mount**: CI bind-mounts `/input` as read-only, so Nim can't write `.nimcache` or compiled binaries. Build script now copies patches to a writable temp dir when the source dir is read-only.

---

## 2026-04-18 — Fix PKGBUILD cross-device link failure + add makepkg CI test

### Fixed
- **Build fails on cross-device setups** (CachyOS, separate /home partition, btrfs subvolumes): `ln` (hard link) in PKGBUILD can't cross filesystem boundaries. Replaced with `cp` for consistent behavior across all systems.

### Added
- **CI: `test-pkgbuild` job** — runs `makepkg` on a tmpfs (cross-device) inside an Arch container, then runs `namcap` to catch dependency issues before release.

---

## 2026-04-18 — Migrate patch system from Python to Nim

### Changed
- **All 41 patches rewritten in Nim** for ~10x faster build times. Python interpreter startup overhead eliminated.
- Patches compile to native binaries via `patches/Makefile` (`make -j$(nproc)`).
- New orchestrator `scripts/apply_patches.py` runs compiled Nim binaries, stages files on tmpfs.
- `scripts/compile-nim-patches.sh` handles Nim compilation with Docker fallback.
- Large inline JS snippets extracted to `js/` directory (shared between patches via `staticRead`).
- CI updated: Nim + nimble installed in build container, ruff lint replaced with Nim compile check.

### Removed
- All `patches/*.py` files (replaced by `patches/*.nim`)
- `pyproject.toml` (was only for ruff linting of Python patches)

---

## 2026-04-18 — Fix computer-use broken by upstream parameter reorder

### Fixed
- **All computer-use tools returning `Unknown tool: [object Object]`**: Upstream reordered the `handleToolCall(toolName, input, sessionCtx)` parameters. Our `LINUX_HANDLER_INJECTION_JS` template used hardcoded `e`/`t`/`r` matching the old order where `t` was the tool name. After the upstream swap, `t` became the session context object, causing every tool dispatch to hit the `default` branch and stringify the object.
- **Fix**: Replaced hardcoded single-letter param references with placeholders (`__TOOL_NAME__`, `__INPUT__`, `__SESSION__`) that are dynamically substituted with the captured minified parameter names from the regex match at patch time. This makes the injection resilient to future parameter renamings or reorderings.
- **`ese` Set false-positive "already applied"**: Upstream added `"linux"` to an *unrelated* Set (not the computer-use gate `BmA`). Initial fix detected it as "already applied" and skipped the real `BmA` Set, leaving `SdA()` returning `false` on Linux — computer-use MCP server never registered (0 tools). Fixed: always apply to all `["darwin","win32"]` Sets first, only fall back to "already applied" if zero unpatched Sets remain.

---

## 2026-04-17 — Fix computer-use zoom on HiDPI / multi-monitor (issue #32)

### Fixed
- **Zoom returns incorrect region on HiDPI / multi-monitor setups**: `_captureRegion` now accepts and applies a `scaleFactor` parameter, converting Electron's logical pixel coordinates to physical pixels before passing to screenshot tools (grim, spectacle+convert, scrot, etc.). Previously coordinates were passed unscaled, causing wrong crop regions when `scaleFactor > 1`.
- **Zoom ignored active display**: The zoom handler passed hardcoded `displayId=0` instead of the user's pinned display (`switch_display`). Now passes `__cuPinnedDisplay` when set, otherwise auto-detects the monitor from the zoom coordinates.

### Added
- **`_findMonByPoint(px, py)`** helper: determines which monitor contains a given coordinate point, used by both zoom and `_captureRegion` for automatic scaleFactor detection.
- **Display diagnostics at startup**: `[claude-cu] diagnostics: displays=[...]` now logs all detected monitors with dimensions, origins, and scale factors — visible when running `claude-desktop` from a terminal.
- **Zoom debug logging**: `[claude-cu] zoom: rect=... sf=...` logs coordinates, scaleFactor, and target monitor for each zoom call.

---

## 2026-04-17 — Cowork crash fix (`t.platform` → `e.platform`) + patch strictness hardening

### Fixed
- **`patches/fix_computer_use_linux.py`** sub-patches 13b/13c/13d injected `(t.platform==="linux"?...)` inside function `qir(e,A,t)`. In that scope `t` is the installed-apps array (no `.platform`) and `e` is the CU config. On win32 the ternary short-circuited; on darwin/linux every cowork session init crashed with `Cannot read properties of undefined (reading 'platform')`, blocking the CLI spawn entirely. Fixed by using the correct parameter `e`. Comment at line 1015–1019 now documents the scope to prevent regression.

### Changed — patch strictness (prevention for the class of bug above)
Four patches previously allowed `[WARN]` + continue / no counter, so silent anchor drift after an upstream release could hide as "everything's fine" while a feature was broken. All four now enforce `EXPECTED_PATCHES` / `patches_applied` with loud `[FAIL]` on any sub-patch miss (see CLAUDE.md §5b):

- `patches/enable_local_agent_mode.py` — `EXPECTED_PATCHES=11`; yukonSilver NH, coworkKappa flag, navigator spoof, single-file test mode all converted WARN→FAIL; idempotency counting added across 6 sub-patches.
- `patches/fix_cowork_spaces.py` — `EXPECTED_PATCHES=3`; silent `"__spaceMgr__"` fallback (the exact silent-bug class) **removed** — missing singleton regex now fails with an investigation hint.
- `patches/fix_asar_folder_drop.py` — `EXPECTED_PATCHES=2`; second-instance argv parser miss no longer marked "non-critical".
- `patches/fix_dock_bounce.py` — `EXPECTED_PATCHES=4`; `requestUserAttention` required (Option A — drift should surface); `app.focus({steal})` split into real-idempotent vs miss.

### Other
- `scripts/claude-desktop-launcher.sh` — cowork socket age-based cleanup disabled (kept as commented-out block). The 24 h `find -mmin +1440` heuristic was deleting live sockets of healthy long-running daemons; pending replacement with a proper connect-probe health check.

---

## 2026-04-17 — Quick Entry hotkey: GNOME bypass via `gsettings` + CLI trigger (issue #38)

The portal-based path from commit 814e8fb is correct for KDE/Hyprland but unreliable on GNOME — the xdg-desktop-portal GlobalShortcuts approval notification is easy to miss, and Electron's `globalShortcut.register()` returns `true` either way, so the hotkey silently doesn't fire. Empirical check: on this project's Ubuntu GNOME Shell 48 VM, `gsettings get org.gnome.settings-daemon.global-shortcuts applications` was `@as []` — no app had completed the approval flow — despite the portal being available and all identity signals correctly aligned.

### Added
- **New patch `patches/fix_quick_entry_cli_toggle.py`** (3 sub-patches, strict `EXPECTED_PATCHES=3`):
  - **A**: capture the Quick Entry show handler into `globalThis.__ceQuickEntryShow`. Anchored on the stable `.QUICK_ENTRY` enum property name inside `XYe(Iw.QUICK_ENTRY, () => {...})`. All minified identifiers captured with `[\w$]+`.
  - **B**: prepend an argv pre-check to `app.on("second-instance", ...)`. If argv contains `--toggle-quick-entry`, invoke the captured handler and return early — don't fall through to upstream main-window show. Anchored on the literal `"second-instance"` (Electron API surface, stable).
  - **C**: first-instance path — schedule a 500 ms `setTimeout` that fires the handler if `process.argv.includes("--toggle-quick-entry")`. Covers the cold-start case where no `second-instance` event fires. Emitted as part of sub-patch A's replacement so A and C either both apply or both don't.
- **New patch `patches/fix_quick_entry_wayland_blur_guard.py`** — replaces the upstream `Po.on("blur", () => EHA(null))` with a focus-tracked variant. On GNOME Wayland, Mutter's focus-stealing prevention declines to transfer focus to Po on show but Chromium still emits phantom `blur` events because the logical focus state changed. The guard registers `focus`/`blur`/`show`/`hide` listeners and only dismisses on blur **if Po was ever focused since the last show**. If focus never fired (phantom blur), the dismiss is skipped — Po stays open until the user presses Escape or submits. X11 / KDE / Hyprland paths are unchanged (Po focuses normally there, so blur-click-outside-dismiss keeps working).
- **Debounce guard in `patches/fix_quick_entry_cli_toggle.py` handler** — on GNOME the `claude-desktop --toggle-quick-entry` CLI gets delivered as TWO `second-instance` events ~500 ms apart for a single Ctrl+Alt+Space press (empirical: launcher fires once, Electron's `second-instance` event fires twice). Upstream `U$t()` implements toggle semantics (`IHA && Po.isVisible() ? EHA(null) : show`), so the second fire saw Po visible and dismissed it via `kjA()` → `Po.blur()` + `Po.hide()` — the "flashes open, closes" symptom. The handler now debounces with a 900 ms window (`if Date.now() - globalThis.__ceQEInvokedAt < 900 return;`); a deliberate second press >900 ms later still toggles normally.
- **Three launcher subcommands** (`scripts/claude-desktop-launcher.sh`):
  - `--install-gnome-hotkey [ACCEL]` — binds ACCEL (default `<Primary><Alt>space`) to `claude-desktop --toggle-quick-entry` via `gsettings`, under slot `/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/claude-desktop-quick-entry/`. Preserves any other custom keybindings (Python helper for safe array manipulation). Idempotent — re-run with a different accelerator to change it.
  - `--uninstall-gnome-hotkey` — removes the slot from the array and resets the per-slot schema.
  - `--diagnose` — one-shot snapshot: session env vars, Electron path + version (reads the bundled `version` file rather than invoking the binary, which would spawn Claude), systemd-run / gsettings / gdbus availability, `.desktop` file presence at the APP_ID path, portal GlobalShortcuts version, `org.gnome.settings-daemon.global-shortcuts applications` contents (empty means no app has completed approval), whether the project hotkey slot is installed with its name/command/binding, recent launcher log tail.

### Behavior
- Portal path (`--enable-features=GlobalShortcutsPortal`) is **unchanged** and remains the default on native Wayland. Sites where it works — KDE via `kglobalaccel` persistent grants, Hyprland via `xdg-desktop-portal-hyprland` — are unaffected.
- GNOME users get a single-command alternative that bypasses the portal entirely. Paths are independent (no auto-fallback, no double-firing).
- `--toggle-quick-entry` is **not** intercepted by the launcher — it passes through to Electron so the patch sees it in `process.argv` / second-instance argv.

### Deliberately out of scope
- No auto-install of the GNOME hotkey on first launch. Silent gsettings writes conflict with users' existing custom keybindings and are hard to audit afterward — opt-in only.
- No portal-Activated verification or self-healing. Two code paths racing is the class of bug we're avoiding.
- No new IPC channel. `app.on('second-instance')` already gives argv in the main process; bouncing through `ipcMain.handle` adds no capability.
- No changes to the XWayland escape hatch (`CLAUDE_USE_XWAYLAND=1`). GNOME 49 has tightened XWayland key-grab policy anyway, so `--install-gnome-hotkey` is the recommended GNOME path.

### References
- [aaddrick/claude-desktop-debian#404](https://github.com/aaddrick/claude-desktop-debian/issues/404) — same symptom reproduced independently on Fedora 43 GNOME 49.
- `wayland.md` has a new Quick Entry section with full troubleshooting and `--diagnose` reference.

---

## 2026-04-17 (v1.3109.0) — Dispatch rename fix + strict-mode patch hardening

### Upstream diff summary (v1.3036.0 → v1.3109.0)
Re-audited 2026-04-17 by diffing both extracted bundles side-by-side. This version bump is **webpack re-minification only** — no structural or feature-flag changes upstream:

- **0** new files in `app.asar` (only renderer asset-hash bumps)
- **0** new `ipcMain.handle(...)` registrations
- **0** new `process.platform` gates (diff lines are all renames)
- **0** new `status:"unavailable"` feature gates
- **0** new GrowthBook flags, **0** removed (same flag set as v1.3036.0)
- **0** new or removed MCP servers (same 17: 3 renderer-facing + 14 backend)
- **Same 19 features** in the static registry + async merger

No new Linux compatibility patches needed; `[\w$]+` regex wildcards absorbed every minifier rename automatically — except the dispatch IPC bridge, fixed below.

Function renames (full list in CLAUDE_FEATURE_FLAGS.md and CLAUDE_BUILT_IN_MCP.md version-history tables): static registry `nA()`→`J0()`; async merger `ode`→`ewA`; gate wrapper `ESe()`→`aFA()`; flag reader `Wr()`→`Ti()`; value flag readers `fs()`→`Es()` and `wA()`→`di()`; listener `Xk()`→`wG()`; platform vars `hi`→`en` (darwin), `xce`→`ws` (win32), `UMe`→`WhA` (darwin\|\|win32); MCP registration `kce()`→`DfA()`.

### Fixed
- **`fix_dispatch_linux.py` sub-patches F (rjt text forward) & J (auto-wake cold parent)** stopped matching on v1.3109.0 because webpack re-minified the dispatch IPC bridge. Variable rename cascade: rjt item `s→n`; auto-wake session `n→i`, notification `s→n`, child session `e→A`, index `r→t`, logger `B/P→M`. Both patterns now use `[\w$]+` captures with backreferences so future minification shifts self-heal.

### Changed — strict-mode patch hardening
Per project rule "a failed sub-patch means upstream changed — investigate, don't silently skip", converted `[WARN]` (silent continue) to `[FAIL] + return False` in every case where a required pattern was not found and no already-patched marker exists:
- `fix_dispatch_linux.py` — C (platform label), D (telemetry gate), F (rjt), J (auto-wake)
- `fix_updater_state_linux.py` — idle-state version/versionNumber
- `fix_native_frame.py` — titleBarStyle, autoHideMenuBar, window icon
- `fix_dock_bounce.py` — backgroundThrottling
- `fix_window_bounds.py` — Quick Entry blur-before-hide
- `fix_cross_device_rename.py` — now idempotent via EXDEV-catch marker detection
- `fix_0_node_host.py` — shellPathWorker

Idempotency tails ("No changes made") and counter-enforced patches left unchanged — those paths are already safe.

---

## 2026-04-16 — Quick Entry fixes: portal identity + transparency (issues #38, #39)

### Fixed
- **Quick Entry hotkey only works when Claude has focus** (issues #38, upstream aaddrick #404): root cause is app identity. `xdg-desktop-portal` identifies unsandboxed apps by their systemd-scope / cgroup name and matches them against the installed `.desktop` file. We previously shipped as `"Claude"` (`app.setName` default, plus `claude-desktop.desktop`), which is not a valid reverse-URL and can't be resolved by the portal → GlobalShortcuts registrations succeed but Activated events never route back to the app. Fix aligns every identity signal on `com.anthropic.claude-desktop`. Credit to the KDE-side reporter who diagnosed the same class of problem for persistent grants in KDE Settings.
- **Quick Entry window shows opaque square behind the rounded card** (issue #39): Chromium transparency silently fails on some Wayland compositors when `--enable-transparent-visuals` isn't set. Adding the flag forces ARGB visuals; the 606×470 Quick Entry window now renders its outer area transparently as intended.

### Changed — launcher (`scripts/claude-desktop-launcher.sh`)
- New constant `APP_ID='com.anthropic.claude-desktop'` — the canonical reverse-URL id used across packaging and runtime.
- **Launch via `systemd-run --user --scope --unit=app-${APP_ID}-$$.scope`** — gives the Electron process a named systemd user scope so the portal resolves cgroup → scope name → matching `.desktop` file. Falls back to direct `exec` if `systemd-run` is unavailable.
- **New Chromium flag `--class=${APP_ID}`** — Wayland `app_id` / X11 `WM_CLASS` now match the `.desktop` filename and `StartupWMClass`.
- **New Chromium flag `--enable-transparent-visuals`** — fixes the #39 "opaque rectangle" symptom on most Wayland configs. Harmless on X11.
- **Electron <40 warning** — prints a clear message on startup (`log` + stderr) pointing users at [electron/electron#49806](https://github.com/electron/electron/issues/49806) and asking them to update. No silent XWayland fallback — the bug is upstream, users should update Electron. `CLAUDE_USE_XWAYLAND=1` remains as a manual escape hatch for users who can't.
- `app.setName("Claude")` is **not** changed — userData (`~/.config/Claude`) stays put.

### Changed — packaging
- `.desktop` filename is now `com.anthropic.claude-desktop.desktop` across every format (RPM, DEB, AUR, AppImage, Nix). `StartupWMClass` updated to match. `Name=` / `Icon=` unchanged.
- Existing pinned shortcuts referencing `claude-desktop.desktop` will need to be re-pinned once (minor one-time inconvenience; the new desktop entry is picked up by `update-desktop-database` automatically).

### Known limitation
- **Nix flake**: the Nix package uses `makeWrapper` rather than our shared launcher script, so the `systemd-run` scope wrap does not apply to Nix builds. `--class` and `--enable-transparent-visuals` are wired in. Portal identity on Nix would require a small wrapper-of-wrapper; deferred.

### Patches — unchanged
- `fix_quick_entry_position.py`, `fix_quick_entry_ready_wayland.py`, `fix_window_bounds.py`, `fix_native_frame.py` — all still correct and still needed; the current symptoms were outside the asar surface they touch.

### References
- electron/electron#49806 — `globalShortcut` fails on Wayland with `GlobalShortcutsPortal` feature enabled.
- electron/electron#49842 — Fix merged 2026-02-19, backported to 40-x-y and 41-x-y. Not backported to 39.

---

## 2026-04-16 (v1.3036.0) — Upstream update, 1 patch removed (obsolete)

### Upstream
- **Version bump:** v1.2773.0 → v1.3036.0
- Same 19 features — no additions or removals
- Function renames: `Hb()`→`nA()` (static registry), `Mle`→`ode` (async merger), `G1e()`→`ESe()` (gate function), `QR()`→`Xk()` (listener), `us()`→`fs()` / `cA()`→`wA()` (value flags), `ooe()`→`kce()` (MCP registration)
- Platform variables renamed: `vs`→`xce` (win32), `r6e`→`UMe` (darwin||win32). `hi` (darwin) unchanged.
- **`Wr()` boolean flag reader name unchanged** — first release in a while without a flag-reader rename
- 4 new GrowthBook flags: `658929541` (LAM setModel buffer check / ccd_lock mitigation), `1496450144` (CLAUDE_CODE_ENABLE_TASKS env var), `2800354941` (plugin/skill alphabetical sort), `2815031518` (LocalSessionManager setModel buffer check / ccd_lock mitigation)
- 3 removed GrowthBook flags: `159894531` (ENABLE_TOOL_SEARCH env-var override — upstream dropped the Desktop-side `"false"` override entirely, user settings.json now passes through), `919950191` (LAM-specific tool search), `2678455445` (MCP SDK server mode)
- Same 17 MCP servers

### Patches
- **Removed: `enable_local_agent_mode.py` Patch 3c** — flag `159894531` no longer exists. Upstream removed the ENABLE_TOOL_SEARCH="false" Desktop override that the patch was working around. `ENABLE_TOOL_SEARCH` now passes through from the user's environment / `~/.claude/settings.json` without Desktop interference. The patch replaced the only failing sub-patch — everything else applied cleanly.
- All other 39 patches (38 Python + 1 JS) applied without modification — `[\w$]+` regex patterns handled all renames automatically

### Documentation
- **CLAUDE_FEATURE_FLAGS.md** — updated all function names (static registry, async merger, gate function, listener, value-flag readers, MCP registration) and platform-variable names, added new flags section, removed flags section, version history entry
- **CLAUDE_BUILT_IN_MCP.md** — version number updated, registration function rename noted, version history entry
- **CHANGELOG.md** — this entry

---

## 2026-04-16 (v1.2773.0) — Upstream update, all patches applied (no fixes needed)

### Upstream
- **Version bump:** v1.2581.0 → v1.2773.0
- Same 19 features, no additions or removals
- `chillingSlothFeat` gate changed: `process.platform!=="darwin"` → `r6e` (darwin||win32 combined variable). Our patches handle this gracefully (Patch 1 finds 1 match instead of 2, elif branch; Patch 3 merger override still forces supported)
- `floatingAtoll` now always `{status:"supported"}` unconditionally (was preference-gated via `floatingAtollActive` + GrowthBook `1985802636` listener). Listener for `1985802636` removed
- Function renames: `iA()`→`Hb()` (static registry), `jue`→`Mle` (async merger), `XEe()`→`G1e()` (gate function), `Yr()`→`Wr()` (flag reader), `VI()`→`QR()` (listener), `xs()`→`us()` / `_A()`→`cA()` (value flags)
- Platform variables renamed: `_s`→`vs` (win32), `c3e`→`r6e` (darwin||win32), new named `pi` (darwin)
- MCP registration function renamed: `One()`→`ooe()`
- Computer-use Set variable renamed: `ese`→`ele`, checker `Lte()`→`Jne()`
- 4 new GrowthBook flags: `919950191` (LAM tool search), `2140326016` (author stubs error), `2216480658` (VM outputs), `3858743149` (maxThinkingTokens config, default 4000)
- 3 removed GrowthBook flags: `1585356617` (epitaxy routing), `2199295617` (AutoArchiveEngine), `4201169164` (remote orchestrator — was already hardcoded off)
- Same 17 MCP servers (Chrome, mcp-registry, office-addin, radar, computer-use, terminal, visualize, scheduled-tasks, cowork-onboarding, dev-debug, plugins, Claude Preview, dispatch, cowork, session_info, workspace, ccd_session)

### Patches
- **Enhanced: `enable_local_agent_mode.py`** — added Patch 3c: force GrowthBook flag `159894531` to true (2 call sites). Without this, Desktop sets `ENABLE_TOOL_SEARCH="false"` as env var when spawning the CLI, silently overriding the user's `~/.claude/settings.json`. With the patch, CCD sessions get `"auto"` and LAM sessions get the correct gate value — matching macOS/Windows behavior.
- All other 39 patches applied without modification (38 Python + 1 JS) — `[\w$]+` regex patterns handled all renames automatically

---

## 2026-04-15 — Fix integrated terminal (node-pty) loading on all distros

### Bug Fix
- **Integrated terminal broken** — `node-pty`'s native `pty.node` was packed inside `app.asar` where Electron can't `dlopen()` native modules. Fixed `build-patched-tarball.sh` to use `asar pack --unpack "{**/*.node,**/spawn-helper}"` so Electron's loader redirects `require()` to `app.asar.unpacked/`.
- **Missing `spawn-helper`** — `@electron/rebuild` only builds `.node` modules, not executables. Added `gcc` build of `spawn-helper` from node-pty source (pure C, no Node deps). Required by `pty.fork()` to spawn PTY shell processes.
- **All distros covered** — the tarball produced by `build-patched-tarball.sh` is consumed by all packaging scripts (Arch PKGBUILD, Debian, RPM, AppImage, Nix) via `cp -r app/*`, so the fix propagates automatically.
- **ARM64 + glibc-compat** — updated `scripts/rebuild-pty-for-arch.sh` and the CI inline glibc-compat Docker rebuild step to also build and install `spawn-helper` alongside `pty.node`.

---

## 2026-04-14 (v1.2581.0) — Upstream update, all patches applied (1 fixed)

### Upstream
- **Version bump:** v1.2278.0 → v1.2581.0
- **New feature: `coworkKappa`** — 19th feature flag added. Static entry `sPn()` always unavailable; async override `aPn()` depends on `yukonSilver` + GrowthBook flag `123929380`. Gates a `consolidate-memory` skill ("Reflective pass over memory files — merge duplicates, fix stale facts, prune the index") and auto-memory directory for typeless sessions. **Enabled on Linux** — forced flag `123929380` to true (3 call sites) and added merger override. Purely local file I/O, no VM needed.
- Async merger `jue` now uses 3-way `Promise.all([tPn(), Xsr(), aPn()])` (was 2-way) adding `coworkKappa` alongside `louderPenguin` and `operon`
- Function renames: `eA()`→`iA()` (static registry), `yue`→`jue` (async merger), `CEe()`→`XEe()` (gate function), `Zr()`→`Yr()` (flag reader)
- Platform variables renamed: `vs`→`_s` (win32), `IOe`→`c3e` (darwin||win32)
- 1 new GrowthBook boolean flag: `123929380` (coworkKappa / consolidate-memory skill)
- 1 removed GrowthBook flag: `4040257062` (memory path routing — was new in v1.1348.0)
- Same 6 MCP servers (Chrome, mcp-registry, office-addin, radar, visualize, computer-use)

### Patches
- **Fixed: `fix_tray_dbus.py`** — tray variable pattern was too strict: used `\w+` which can't match `$` in JS identifiers (tray variable is now `$m`), and required `});` immediately before `let XX=null;` but the event listener registration now sits in between. Changed to `[\w$]+` and removed the `\}\);` prefix from the pattern.
- **Enhanced: `enable_local_agent_mode.py`** — added `coworkKappa` as 9th feature override in merger + bypassed GrowthBook flag `123929380` (3 call sites). Enables `/consolidate-memory` skill and auto-memory directory for sessions on Linux.
- All other 34 patches applied without modification — `[\w$]+` regex patterns handled the renames automatically

### ARM64 / Raspberry Pi 5
- **ARM64 integrated terminal** — node-pty is now cross-compiled for arm64 via Docker + QEMU in CI, replacing the old "strip x86_64 pty.node" workaround. All ARM64 packages (deb, rpm, AppImage) now include a working integrated terminal.
- **New: `scripts/rebuild-pty-for-arch.sh`** — reusable script for cross-compiling node-pty to any target architecture. Verifies the produced binary matches the target arch.
- **Nix aarch64-linux** — `packaging/nix/package.nix` now lists `aarch64-linux` in `meta.platforms`
- **Raspberry Pi 5** — added to supported devices in README alongside DGX Spark and Jetson
- **`enable_local_agent_mode.py`** — added `coworkKappa:{status:"supported"}` to feature merger overrides and force-enabled GrowthBook flag `123929380` (consolidate-memory skill, auto-memory for typeless sessions)

### Documentation
- **CLAUDE_FEATURE_FLAGS.md** — added `coworkKappa` (19th feature), updated all function names, added flag `123929380`, removed flag `4040257062`, version history entry
- **CLAUDE_BUILT_IN_MCP.md** — version number updated
- **CHANGELOG.md** — this entry

---

## 2026-04-14 (v1.2278.0) — Upstream update, all patches applied (3 fixed)

### Upstream
- **Version bump:** v1.1617.0 → v1.2278.0
- **No structural changes** to feature flag architecture — same 18 features, same 3-layer system
- Function renames only: `wb()`→`eA()` (static registry), `Soe`→`yue` (async merger), `bbe()`→`CEe()` (gate function), `rn()`→`Zr()` (flag reader), `Db()`→`_A()` / `Gs()`→`xs()` (value flags)
- **`chillingSlothFeat` gate changed** from darwin-only (`g5e`) to darwin||win32 (`IOe`) — Linux still excluded, handled by merger override
- Platform booleans now named `hi` (darwin), `vs` (win32), `IOe` (combined)
- 5 new GrowthBook boolean flags: `286376943` (plugin skills), `1434290056` (dispatch permissions), `2345107588` (GrowthBook cache), `2392971184` (replay messages), `2725876754` (org CLI exec policies)
- 1 new value flag: `1893165035` (SDK error auto-recovery config)
- New `index.pre.js` bootstrap file with enterprise config loading
- Enterprise config switched from switch/case to ternary structure
- Same 6 MCP servers (Chrome, mcp-registry, office-addin, radar, visualize, computer-use)

### Patches
- **Fixed: `fix_cowork_first_bash.py`** — upstream renamed event socket functions (`ZVt`→`$er`, `Sq`→`oH`, `Ts`→`Ps`) and variable (`mA`→`nE`). Converted from exact byte match to regex pattern with dynamic variable detection. Now finds the events socket variable by anchoring on `subscribeEvents` context.
- **Fixed: `fix_cowork_linux.py` Patch F** — `$w` function renamed to `ub`. Changed hardcoded `\$w\(` in regex to `([\w$]+)\(` to match any function name dynamically.
- **Fixed: `fix_enterprise_config_linux.py`** — enterprise config structure changed from switch/case (`case"win32":VAR=FUNC();break;default:VAR={};break`) to ternary chain (`process.platform==="darwin"?FUNC_D():process.platform==="win32"?FUNC_W():{}`). Updated regex pattern to match the new ternary form. Now also patches `index.pre.js` (new bootstrap file) for early-boot enterprise config.
- All other 35 patches applied without modification — `[\w$]+` regex patterns handled the renames automatically

### Documentation
- **CLAUDE_FEATURE_FLAGS.md** — updated all function names, added 5 new boolean flags + 1 value flag, version history entry, `chillingSlothFeat` gate change noted
- **CLAUDE_BUILT_IN_MCP.md** — version number updated
- **CHANGELOG.md** — this entry

---

## 2026-04-11 (v1.1617.0) — Fix Cowork skills/plugins broken by hostLoopMode

### Patches
- **Critical fix: `fix_dispatch_linux.py`** — removed erroneous override of GrowthBook flag `1143815894` (hostLoopMode). Forcing this flag `true` made Desktop bypass the cowork service spawn entirely, falling back to a bare HostLoop SDK that lacks `mcp__workspace__bash` and plugin skill mapping. Result: all Cowork skills (`/pdf`, `/docx`, `/pptx`, etc.) returned "Unknown skill" and sessions completed in ~12ms with zero API calls. Fix: only override flag `3558849738` (dispatch agent name), leave `1143815894` to its default so the cowork service handles session spawning.
- **New sub-patch: `fix_cowork_linux.py` Patch F** — allows `present_files` MCP tool to accept native host paths. Previously, `present_files` only accepted `/sessions/` VM paths; on native Linux without root (no `/sessions/` symlink), all files failed the accessibility check. The patch falls back to checking the host outputs directory.

### Build
- **Copy missing `cowork-plugin-shim.sh`** — the plugin permission bridge file was present in the upstream exe but not copied during build. Without it, Desktop logs a `[warn] ENOENT` on every session start. The shim enables the confirmation UI for plugin operations (e.g., "allow send email?") but is not required for skills to load — the actual skills breakage was caused by the hostLoopMode flag above.

---

## 2026-04-10 (v1.1617.0) — Fix RPM glibc compatibility

### Build
- **Fix RPM install failure on Fedora 40** — the node-pty rebuild (added in `6509b00`) compiled `pty.node` inside the `archlinux:base-devel` CI container, which links against glibc 2.42 (Arch rolling release). rpmbuild auto-detected this as a package dependency, making the RPM uninstallable on Fedora 40 (glibc 2.39). Fix: added a post-processing CI step that rebuilds `pty.node` inside a `node:20-bullseye` container (Debian 11, glibc 2.31), then repackages the tarball. This makes the RPM compatible with Fedora 38+, Ubuntu 20.04+, Debian 11+, and RHEL 9+.

---

## 2026-04-10 (v1.1617.0) — New patch: fix dispatch outputs dir

### Patches
- **New patch: `fix_dispatch_outputs_dir.py`** — fixes "Show folder" opening an empty outputs directory for dispatch sessions. On Linux with the native Go backend, the dispatch parent and child sessions have separate directories. When the parent's outputs dir is empty, the patch scans sibling session directories for one that has files and opens that instead. Uses `[\w$]+` regex wildcards and `require("fs")`/`require("path")` for version resilience.

---

## 2026-04-10 (v1.1617.0) — Upstream update, 38 patches (3 new)

### Upstream
- **Version bump:** v1.1348.0 → v1.1617.0
- **No structural changes** to feature flag architecture — same 18 features, same 3-layer system
- Function renames only: `gb()`→`wb()` (static registry), `eoe`→`Soe` (async merger), `Kwe()`→`bbe()` (gate function), `tn()`→`rn()` (flag reader), `LI()`→`ZI()` (listener), `js()`→`Gs()` / `$b()`→`Db()` (value flags)
- Platform gate variable renamed: `z5e`→`g5e` (same `darwin||win32` pattern)
- computerUse Set variable renamed: kept as `Hae` with `Lte()` checker
- No new GrowthBook flag IDs added or removed
- **New MCP server: `radar`** — records actionable items (`record_card` tool), currently **disabled** (`isEnabled:()=>!1`)
- **New renderer windows:** `buddy_window/`, `find_in_page/`
- **New infrastructure:** `transcript-search-worker/`, `sqlite-worker/`
- **New dependencies:** `node-pty` (1.1.0-beta34), `ws` (^8.18.0), `@ant/imagine-server`
- Operon: same 33 sub-interfaces, no changes
- 3 force-ON GrowthBook flags upstream: `2976814254`, `3246569822`, `1143815894` (hardcoded in `m6r` map) — note: our patch no longer overrides `1143815894` (see 2026-04-11 fix)

### Patches
- All 35 existing patches applied without modification — minified variable names changed but `[\w$]+` regex patterns handled the renames automatically
- **New patch: `fix_imagine_linux.py`** — enables Imagine/Visualize MCP server on Linux by forcing GrowthBook flag `3444158716`. Provides `show_widget` (inline SVG/HTML rendering) and `read_me` (CSS/theme guidance) tools in Cowork sessions. No platform gate exists upstream — only the server-side flag was blocking it.
- **New patch: `fix_cowork_sandbox_refs.py`** — replaces upstream system prompts and tool descriptions that tell the model it runs in "a lightweight Linux VM (Ubuntu 22)" / "isolated sandbox". On Linux with the native Go backend there is no VM — the model now correctly understands it runs directly on the host. Patches: bash tool description (Edn function), cowork identity prompt, computer use explanation, and 3× "isolated Linux environment" references.
- **New patch: `fix_cowork_first_bash.py`** — fixes first bash command in Cowork sessions returning empty output. Root cause: events socket (`yUt`) opens async but `qTe()` sends spawn immediately via the RPC socket — on Linux the command completes before events are subscribed. Fix: poll-wait for `mA` (events socket connection) before spawning. Not visible on macOS/Windows where the VM boot delay masks the race.

### Documentation
- **CLAUDE_FEATURE_FLAGS.md** — updated function names, version history table
- **CLAUDE_BUILT_IN_MCP.md** — new `radar` server (full tool schema), expanded `visualize` server docs, platform gate variable renames, node-pty status, version notes
- **README.md** — added `fix_imagine_linux.py` to patch table
- **CHANGELOG.md** — this entry

### Build
- **node-pty rebuilt for Linux** in `build-patched-tarball.sh` — installs source from npm, rebuilds against Electron 40.8.5 headers via `@electron/rebuild`, replaces Windows PE32+ binaries with Linux ELF. Enables the integrated terminal and `read_terminal` MCP tool. Build dependency: `npx` (already required for asar).

### Known Limitations
- **Radar**: Server disabled at MCP level (`isEnabled:()=>!1`), session creation in renderer code. Not activatable yet.

## 2026-04-08 (v1.1348.0) — Upstream update, all 34 patches apply cleanly

### Upstream
- **Version bump:** v1.1062.0 → v1.1348.0
- **No structural changes** to feature flag architecture — same 18 features, same 3-layer system
- Function renames only: `Ow()`→`gb()` (static registry), `xse`→`eoe` (async merger), `m0e()`→`Kwe()` (gate function), `rn()`→`tn()` (flag reader), `wR()`→`LI()` (listener), `Js()`→`js()` / `j1()`→`$b()` (value flags)
- New GrowthBook boolean flag: `4040257062` (memory path routing for non-session contexts)
- New GrowthBook value flags: `254738541` (prompt), `4066504968` (setup-cowork skill config), `365342473` (shouldScrubTelemetry)
- New value flag keys: `1978029737` gained `artifactMcpConcurrencyLimit`, `idleGraceMs`, `disableSessionsDiskCleanup`, `sessionsBridgePollIntervalMs`, `coworkMessageTimeoutMs`; `3300773012` gained `scheduledTaskPostWakeDelayMs`, `dispatchJitterMaxMinutes`
- Removed GrowthBook flags: `927037640` (subagent model config), `3190506572` (Chrome permission control)
- Operon sub-interfaces: 31 → 33 (new: `OperonDesktop`, `OperonMcpToolAccessProvider`)
- 3 new cowork tools: `create_artifact`, `update_artifact` (flag `2940196192`), `save_skill` (conditional)
- New `Buddy` BLE device pairing IPC (macOS hardware accessory)
- Terminal server upstream regression: `z5e` (darwin||win32) replaced `LRe` (which included Linux) — already handled by `fix_dispatch_linux.py` `z5e` patch
- `chillingSlothFeat` gate changed from `process.platform!=="darwin"` to `z5e` variable — also handled by `z5e` patch + merger override
- Electron 40.8.5

### Patches
- All 34 existing patches applied without modification — minified variable names changed but `[\w$]+` regex patterns handled the renames automatically
- Terminal server Linux support maintained via existing `fix_dispatch_linux.py` `z5e` patch (no new patch needed)
- **New patch: `fix_buddy_ble_linux.py`** — enables Hardware Buddy (Nibblet M5StickC Plus BLE device) on Linux by forcing GrowthBook flag `2358734848`. BLE communication uses Web Bluetooth via BlueZ — no native code needed. Requires `bluez` package.

### Documentation
- **CLAUDE_FEATURE_FLAGS.md** — updated function names, GrowthBook flag catalog, version history table
- **CLAUDE_BUILT_IN_MCP.md** — new cowork tools, terminal regression note, Operon sub-interfaces
- **CHANGELOG.md** — this entry

## 2026-04-07 — Fix CU system prompt: model no longer misidentifies Linux as macOS

### Fixed
- **fix_computer_use_linux.py** sub-patch 14a: "Separate filesystems" system prompt paragraph replaced with "Same filesystem" on Linux — the CLI and desktop share the same machine, there is no sandbox
- **fix_computer_use_linux.py** sub-patch 14b: macOS app names "Maps, Notes, Finder, Photos, System Settings" replaced with distro-generic terms "the file manager, image viewer, terminal emulator, system settings" (works across Arch, Ubuntu, Fedora, NixOS)
- **fix_computer_use_linux.py** sub-patch 14c: File manager name "Finder" → "Files" on Linux in host filesystem guidance

### Root cause
The CU system prompt builder only distinguished Windows vs non-Windows, giving Linux sessions macOS-specific text ("Separate filesystems", "Finder", sandbox references). The model used these cues plus visual similarity to misidentify Linux desktops as macOS. The `.host-home` path examples (`/Users/alice/...`) were already skipped on Linux due to `hostLoopMode=true`.

## 2026-04-07 — Strict patch validation, `[\w$]+` regex hardening, built-in MCP/flag audit

### Fixed
- **fix_dispatch_linux.py** Patch D: telemetry gate variable `F$e` not matched by `\w+` (contains `$`)
- **fix_startup_settings.py** Patch 2: logger variable changed `re` → `R` upstream; now uses flexible `[\w$]+` pattern
- **fix_computer_use_linux.py** Patch 7: teach overlay gate function `nee()` not in hardcoded allowlist; now uses generic `[\w$]+()&&(` pattern

### Changed
- **16 patch files**: All `\w+` regex patterns matching JS identifiers replaced with `[\w$]+` to handle minified names containing `$`
- **8 patch files**: Lenient success criteria (`patches_applied == 0`) replaced with strict `EXPECTED_PATCHES` check — all sub-patches must succeed or the build fails
- **fix_app_quit.py**: Changed silent `sys.exit(0)` on failure to `sys.exit(1)`

### Docs
- **CLAUDE.md**: Added Section 5b "Patch Strictness Rules" — all sub-patches must match, `[\w$]+` required for JS identifiers
- **CLAUDE_BUILT_IN_MCP.md**: Added `update_plan` Chrome tool, `read_me` widget tool, `cowork-artifact` dynamic servers, `web_search` API built-in, fixed `scheduled-tasks` server name, Operon expanded to 31 sub-interfaces, v1.1062.0 version notes
- **CLAUDE_FEATURE_FLAGS.md**: Added Operon tool inventory (14 brain + 7 compute + 1 dynamic + 4 internal LLM tools), 3 new Operon interfaces, new/removed GrowthBook flags for v1.1062.0

## 2026-04-07 — Portal+PipeWire screenshots for GNOME Wayland 46+ (#28)

### Added
- **fix_computer_use_linux.py**: XDG ScreenCast portal screenshot method with PipeWire restore tokens for GNOME Wayland 46+. First screenshot shows a one-time permission dialog, all subsequent screenshots are silent. Token-aware cascade: if restore token exists, portal goes first (fast, silent); if not, `gnome-screenshot` is tried first (no dialog on older GNOME), with portal as fallback after `gdbus`. Fixes repeated permission dialogs on GNOME 46+ where `gnome-screenshot` and `gdbus ScreenshotArea` are both broken.
- **PKGBUILD.template**: New optdepends `python-gobject` and `gst-plugin-pipewire` for portal screenshots.

### Technical details
- Python script embedded inline (spawned via `python3 -` stdin pipe), no extra files needed
- GStreamer pipeline: single frame capture (`num-buffers=1`) — ~300ms per screenshot with restore token
- Restore token persisted at `~/.config/Claude/pipewire-restore-token`
- Graceful degradation: missing `python3-gi` returns exit code 2, cascade falls through to next method

## 2026-04-07 (v1.1062.0) — Upstream update, fix 3 patches for minified name changes

### Fixed
- **enable_local_agent_mode.py**: HTTP header platform spoof pattern — upstream changed separator from `;` to `,` after `getSystemVersion()` (more declarations on same line). Updated regex to accept `[;,]`.
- **fix_asar_folder_drop.py**: File-drop convergence function renamed (`noe` → `Coe`). Replaced hardcoded `noe` with `\w+` wildcard so the pattern survives future renames.
- **fix_quick_entry_ready_wayland.py**: Ready-to-show variable names changed (`NEe` → `YEe`, `nK` → `AK`). Replaced hardcoded literal match with regex-based extraction of variable names.

### Changed
- Upstream version: v1.569.0 → v1.1062.0
- Feature flag function renames: `$w()` → `Ow()`, `tse` → `xse`, `V0e()` → `m0e()`, `Sn()` → `rn()`
- 2 new GrowthBook flags: `2114777685` (cowork session CU gate), `3371831021` (cuOnlyMode)
- 6 dispatch-era GrowthBook flags removed upstream

### Docs
- **CLAUDE_FEATURE_FLAGS.md**: Updated all function names, GrowthBook catalog, version history table for v1.1062.0
- **CLAUDE_BUILT_IN_MCP.md**: Added new `cowork-onboarding` MCP server (#8) with `show_onboarding_role_picker` tool (gated by GrowthBook `2114777685`); renumbered servers 9→16; version header updated

## 2026-04-06 (v1.569.0) — Linux-aware CU tool descriptions, gnome-screenshot priority

### Added
- **fix_computer_use_linux.py** sub-patch 13 (13a–13g): Fix computer-use tool descriptions for Linux. The upstream `V7r()` builder produces descriptions that tell the model "This computer is running macOS", reference Finder/bundle identifiers, and warn about allowlist gates that are bypassed on Linux. Seven sub-patches wrap key description strings in `process.platform` checks: (a) `Lf` allowlist gate suffix → empty on Linux, (b) `request_access` says "Linux" with correct file-manager info, (c–d) app identifiers use WM_CLASS not macOS bundle IDs, (e) `open_application` drops allowlist requirement, (f–g) `screenshot` removes allowlist references. Non-fatal — descriptions don't affect tool functionality.

### Changed
- **fix_computer_use_linux.py**: Reordered GNOME Wayland screenshot cascade — `gnome-screenshot` now takes priority over `gdbus` (GNOME Shell D-Bus). `gnome-screenshot` is more widely available (works on Ubuntu GNOME where the D-Bus interface may be absent), so it should be tried first with `gdbus` as fallback.

### Docs
- **CLAUDE_BUILT_IN_MCP.md**: Rewrote Computer Use tools table with verbatim upstream descriptions (v1.569.0) and platform-dependent notes showing what Linux patches change.
- **CLAUDE.md**: Updated Wayland GNOME screenshot tool order, sub-patch count (12→13), added sub-patch 13 row.

## 2026-04-06 (v1.569.0) — Add gnome-screenshot fallback for Wayland GNOME, Ubuntu build script

### Fixed
- **fix_computer_use_linux.py**: `gnome-screenshot` was never tried on Wayland GNOME sessions — it was only in the X11 code path. If `gdbus` (GNOME Shell D-Bus) failed, screenshots fell through directly to the Electron `desktopCapturer` fallback. Added `gnome-screenshot` as a Wayland GNOME fallback (full capture + ImageMagick crop, with uncropped fallback). Updated diagnostics to include it in relevant-tools and cascade-order output.

### Added
- **scripts/build-ubuntu-local.sh**: Local build script for Ubuntu/Debian — downloads the latest exe, applies patches, and builds an installable `.deb`.

### Changed
- **scripts/build-patched-tarball.sh**: Added `SKIP_SMOKE_TEST=1` env var to allow skipping the Electron smoke test on systems without `electron`/`xvfb-run`.

## 2026-04-06 (v1.569.0) — Add runtime diagnostics logging for all patches

### Added
- **fix_computer_use_linux.py**: Startup diagnostics IIFE logs session type, DE, available/missing tools, input backend, and screenshot cascade order to stdout/stderr (visible when running `claude-desktop` from a terminal). First-use logging for each input operation (mouse, click, key, type, scroll, drag) shows which backend handled it.
- **fix_browser_tools_linux.py**: Logs native host presence and detected browser profiles at startup.
- **fix_claude_code.py**: Logs which path the CLI binary was found at, or warns with install instructions if missing.
- **fix_quick_entry_position.py**: One-time log for cursor positioning method (xdotool, hyprctl, or Electron fallback).
- **CLAUDE.md**: Added supported distros and session managers reference table.

### Notes
- All diagnostics use structured `[tag] category: detail` format. Visible when running `claude-desktop` from a terminal. Not written to `main.log` (that file uses Electron's structured logger).

## 2026-04-05 (v1.569.0) — Fix Quick Entry focus on X11/XWayland

### Fixed
- **fix_quick_entry_position.py**: Quick Entry window opened but didn't receive keyboard focus on X11 — typing, Escape, and click-outside-to-dismiss all failed until manually clicking inside. Root cause: X11 WMs ignore Electron's `_NET_ACTIVE_WINDOW` focus request due to focus-stealing prevention. Fix uses `xdotool windowactivate` on X11/XWayland (detected via `XDG_SESSION_TYPE` and `--ozone-platform=x11` argv) with graceful fallback to Electron APIs. Wayland path uses pure Electron `focus()` + `focusOnWebView()` via `xdg_activation_v1`. Retries at 50/150/300ms for async WM processing.

## 2026-04-05 (v1.569.0) — Fix Quick Entry global shortcut on Wayland

### Fixed
- **fix_quick_entry_ready_wayland.py** (new): Quick Entry overlay never appeared on native Wayland even though the global shortcut fired correctly. Root cause: Electron's `ready-to-show` event never fires for transparent frameless BrowserWindows on Wayland, and Claude's code awaits it indefinitely. Fix adds a 200ms `Promise.race` timeout so the window proceeds to show.

### Added
- **scripts/build-fedora-local.sh**: Local build script for Fedora — downloads the latest exe, applies patches, and builds an installable RPM.
- **wayland.md**: Troubleshooting guide for stale kglobalaccel entries that can block global shortcut registration on KDE Wayland.

### Notes
- Electron's native `GlobalShortcutsPortal` (`--enable-features=GlobalShortcutsPortal`) works correctly on KDE Wayland — no external D-Bus helper needed. On first launch KDE shows an approval dialog; the permission persists in `kglobalshortcutsrc` across restarts.

## 2026-04-04 (v1.569.0) — Fix app.asar Cowork file-drop on every launch (#24)

### Fixed
- **fix_asar_folder_drop.py**: Rewrote patch to filter `.asar` paths at the `noe()` function — the single convergence point for all file-drop dispatches to Cowork. The previous patch only guarded the `isDirectory` helper, but app.asar fell through to the `existsSync` check and got dispatched as a file instead of a folder. Also guards the second-instance argv parser (`KXn`) as defense-in-depth. Credit: @dvolonnino for identifying the fix.

## 2026-04-03 (v1.569.0) — Fix app menu launch, upstream version bump

### Fixed
- **Desktop files**: Remove `Path=%h` from all .desktop files (#26). `%h` is a field code only valid in the `Exec` key — in `Path` it's treated as a literal string, causing desktop environments (Cinnamon, others) to fail silently when launching from the app menu. The `fix_asar_workspace_cwd.py` patch already handles cwd sanitization in JS, so the .desktop `Path` was unnecessary.

## 2026-04-03 (v1.569.0) — Upstream version bump, patch regex fix

### Fixed
- **enable_local_agent_mode.py**: Async feature merger regex failed because the static registry function was renamed to `$w()` — the `$` character isn't matched by `\w`. Changed regex from `\w+` to `[\w$]+` to handle `$`-prefixed minified names.

### Added
- **fix_dispatch_linux.py**: Force-enable GrowthBook flag `3558849738` (dispatch agent name) on Linux. ~~Also forced `1143815894` (hostLoopMode) — later reverted in 2026-04-11 as it bypassed the cowork service spawn, breaking all skills/plugins.~~

### Changed
- **Version bump to v1.569.0** — upstream switched from 4-part versioning (v1.2.234) to 3-part (v1.569.0). All 31 patches apply cleanly. Same 18 feature flags, no structural changes.
- Function renames: `Uw()`→`$w()` (static registry), `Lse`→`tse` (async merger), `I_e()`→`V0e()` (production gate), `fn()`→`Sn()` (flag reader).
- 3 new GrowthBook flags: `286376943`, `1434290056`, `2392971184`. Flag `1143815894` re-added.

### Docs
- **CLAUDE_FEATURE_FLAGS.md**: Updated all function names, version history table, GrowthBook catalog for v1.569.0.
- **CLAUDE_BUILT_IN_MCP.md**: Updated version header.

## 2026-04-03 (v1.2.234) — Fix workspace trust dialog showing "app.asar" (#24)

### Fixed
- **fix_asar_workspace_cwd.py** (new): On first launch, the workspace trust dialog could show "Allow Claude to change files in 'app.asar'?" because the web app resolved `app.getAppPath()` as the default workspace. The new patch injects a `__cdb_sanitizeCwd()` helper that redirects any workspace path containing `app.asar` to `os.homedir()` on Linux. Patches 5 IPC bridge functions: `checkTrust`, `saveTrust`, `start`, and both `startCodeSession` handlers.
- **.desktop files**: Added `Path=%h` across all packaging formats (Arch, RPM, DEB, AppImage) so the working directory defaults to `$HOME` when launching from the app menu, preventing the desktop environment from inheriting an arbitrary cwd.

## 2026-04-02 (v1.2.234) — Session-aware Computer Use tool selection

### Fixed
- **fix_computer_use_linux.py**: Tool selection now uses session type and compositor detection instead of binary existence. Prevents wrong tools on wrong sessions (e.g., grim on KDE Wayland, scrot on Wayland, gnome-screenshot on Wayland GNOME 42+).
- **fix_computer_use_linux.py**: `_isWayland()` now trusts `XDG_SESSION_TYPE` over `WAYLAND_DISPLAY` — fixes false positive when XWayland sets `WAYLAND_DISPLAY` on X11 sessions.
- **fix_computer_use_linux.py**: grim restricted to wlroots compositors (`SWAYSOCK`/`HYPRLAND_INSTANCE_SIGNATURE`), scrot/import/gnome-screenshot restricted to X11.
- **fix_computer_use_linux.py**: Fixed `type()` redundant `_checkYdotool()` that could fall back to xdotool on Wayland if daemon crashed mid-operation.

## 2026-04-02 (v1.2.234) — Nix build fix, docs & packaging improvements

### Fixed
- **flake.nix**: Pass `claude-code = null` to avoid pulling yanked npm tarballs from nixpkgs (e.g. `@anthropic-ai/claude-code@2.1.88` → 404). Users can still override.

### Changed
- **README.md**: Split KDE Plasma / GNOME install commands into separate lines, added socat as optional dependency, improved session-type guidance.
- **packaging/nix/package.nix**: Added `glib` optional dependency for GNOME `gsettings` (flat mouse acceleration).
- **patches/fix_computer_use_linux.py**: Updated doc comment (switch_display uses Electron screen API, not xrandr).

## 2026-04-02 (v1.2.234) — Computer Use multi-monitor & teach overlay fixes

### Fixed
- **fix_computer_use_linux.py**: Multi-monitor coordinate translation — clicks used display-relative coordinates directly with xdotool (absolute). Added `__txC()`/`__untxC()` to translate using the active display's origin offset.
- **fix_computer_use_linux.py**: Teach overlay spawned on wrong monitor — patched `xlr()` to always resolve to primary display on Linux.
- **fix_computer_use_linux.py**: Teach overlay buttons (Next/Exit) unclickable (Electron bug #16777) — override `setIgnoreMouseEvents` to no-op so overlay stays interactive.
- **fix_computer_use_linux.py**: Teach tooltip stuck in upper-left — `getDisplaySize()` missing `originX`/`originY`, `_findMon()` didn't match Electron native display IDs.

### Changed
- **fix_computer_use_linux.py**: Default screenshot display → primary (was displayId=0). Now 12 sub-patches (was 8).

### Docs
- **README.md**: Documented multi-monitor limitation (primary monitor only) and teach overlay behavior.
- **CLAUDE_BUILT_IN_MCP.md**: Updated sub-patch table (8→12), expanded feature flag docs.

## 2026-04-01 (v1.2.234) — Computer Use Wayland fix

### Fixed
- **fix_computer_use_linux.py**: Computer Use now works on all Wayland compositors (tested KDE Plasma + GNOME on Ubuntu). Three bugs fixed:
  1. **Window click-through** — Added `setIgnoreMouseEvents` wrapper so clicks pass through Claude's window to the target app.
  2. **Cursor positioning** — Split ydotool `--absolute` into origin-reset + delay + relative move (single-command was too fast for libinput).
  3. **Keyboard input** — `_mapKeyWayland()` returns raw Linux numeric keycodes. ydotool v1.0.4 `key` only accepts numeric codes, not names.

### Added
- **scripts/setup-ydotool.sh**: One-command setup for Ubuntu/Debian Wayland users. Builds ydotool v1.0.4 from source, configures uinput permissions, starts daemon. Also sets flat mouse acceleration on GNOME.
  Usage: `curl -fsSL https://raw.githubusercontent.com/patrickjaja/claude-desktop-bin/master/scripts/setup-ydotool.sh | sudo bash`

### Docs
- **README.md**: All Wayland compositors need ydotool for input (not just wlroots). Added ydotool setup section with `curl | sudo bash` for Ubuntu/Debian, one-liners for Arch/Fedora, and GNOME flat acceleration note.

### Changed
- **Version bump to v1.2.234** — Major upstream release. Feature flag registry unchanged (same 18 features), but internal function names renamed across the board.
- **fix_computer_use_linux.py**: Platform gate changed from inline `process.platform==="darwin"` to Set-based `ese = new Set(["darwin","win32"])` with `vee()` checker. Updated patch to add `"linux"` to the Set instead of removing individual gates. This single change fixes all computer-use platform checks (server push, chicagoEnabled, overlay init). handleToolCall regex updated for new code structure (Y5e opted-out block before dispatcher).
- **read_terminal MCP server**: Upstream now natively supports Linux (`LRe = isDarwin || isWin32 || isLinux`). **Removed `fix_read_terminal_linux.py`** — patch no longer needed.

### Upstream Changes
- **Computer use**: Platform gate now uses a Set (`ese`) gating `vee()` function, adding Windows support alongside macOS. Linux still requires our patch to add to the Set.
- **Terminal server**: Now natively supports Linux (variable `LRe` includes all three platforms).
- **Registration function renamed**: `Are()` → `One()` for internal MCP server registration.
- **Feature flag function renames**: Static registry `_b()` → `Uw()`, async merger `Cie` → `Lse`, production gate `fve()` → `I_e()`.
- **GrowthBook expansion**: 38+ flag IDs now in use (was ~33 in v1.1.9669). New flags for floatingAtoll state sync (`1985802636`).
- **Operon**: Static entry now unconditionally returns `{status:"unavailable"}` (`$gn()`). Async override introduces 5-second delay before GrowthBook check.

### Docs
- **CLAUDE_FEATURE_FLAGS.md**: Updated for v1.2.234 — new function names (`Uw`, `Lse`, `I_e`), same 18 features.
- **CLAUDE_BUILT_IN_MCP.md**: Updated for v1.2.234 — registration function `Are()` → `One()`, terminal server now natively supports Linux.

## 2026-04-01 (v1.1.9669)

### Changed
- **fix_computer_use_linux.py**: Replaced external clipboard tools (`xclip`, `xsel`, `wl-clipboard`) with Electron's built-in `clipboard` API. Clipboard read/write and type-via-clipboard now use `electron.clipboard.readText()`/`writeText()` directly — no external packages needed.
- **fix_computer_use_linux.py**: Replaced external display enumeration tools (`xrandr`, `wlr-randr`) with Electron's built-in `screen.getAllDisplays()` API for both X11 and Wayland. Eliminates 2 optional dependencies.
- **fix_computer_use_linux.py**: Added `desktopCapturer` + `nativeImage.crop()` as last-resort screenshot fallback before the error throw. Helps on exotic Wayland compositors where no CLI screenshot tool is available.
- **Packaging**: Removed `xclip`, `xsel`, `wl-clipboard`, `wlr-randr`, `xorg-xrandr` from optional dependencies across all formats (PKGBUILD, deb, rpm). 5 fewer packages to install.

### Fixed
- **fix_computer_use_linux.py**: Computer Use clicks now work on all Wayland compositors (KDE, GNOME, wlroots). Three bugs fixed:
  1. **Window hiding before actions** — Added `setIgnoreMouseEvents` wrapper (matching upstream macOS `lB()` behavior) so clicks pass through Claude Desktop's window to the target app behind it.
  2. **ydotool absolute positioning** — Split `mousemove --absolute X Y` into two commands with 50ms delay (origin reset + relative move). The single-command approach sent both events too fast for libinput to process correctly, causing the cursor to land at (0,0).
  3. **ydotool keyboard input** — `_mapKeyWayland()` now returns raw Linux numeric keycodes (e.g. 29 for Ctrl, 56 for Alt) instead of symbolic names. ydotool v1.0.4 `key` command parses names as `strtol()` = 0, silently dropping all key events.
- **fix_computer_use_linux.py**: Screenshot support on non-wlroots Wayland compositors (GNOME, KDE). New fallback chain: `COWORK_SCREENSHOT_CMD` env override → grim (wlroots) → GNOME Shell D-Bus `ScreenshotArea` → spectacle + crop (KDE) → gnome-screenshot → scrot → import. Fixes [claude-cowork-service#13](https://github.com/patrickjaja/claude-cowork-service/issues/13).
- **fix_computer_use_linux.py**: ydotool robustness — `_checkYdotool()` verifies ydotoold daemon is running before attempting ydotool commands. Falls back to xdotool via XWayland if daemon not found.

### Added
- **scripts/setup-ydotool.sh**: One-command ydotool v1.0.4 setup for Ubuntu/Debian Wayland users. Builds from source, configures uinput permissions, and creates a systemd service. Ubuntu/Debian ship ydotool 0.1.8 which has incompatible command syntax. Usage: `curl -fsSL https://raw.githubusercontent.com/patrickjaja/claude-desktop-bin/master/scripts/setup-ydotool.sh | sudo bash`

### Docs
- **README.md**: Fixed Computer Use dependencies — all Wayland compositors (KDE, GNOME, wlroots) require `ydotool` for input automation, not just wlroots. The `xdotool (XWayland)` fallback cannot click native Wayland windows.
- **README.md**: Added `ydotool setup` section with one-liner for Arch/Fedora and `curl | sudo bash` setup script for Ubuntu/Debian.
- **Packaging**: Updated optional dependency descriptions across all formats (PKGBUILD, deb control, rpm spec, nix) to reflect ydotool requirement for all Wayland compositors.

## 2026-03-31 (v1.1.9669)

### Changed
- **Version bump to v1.1.9669** — New upstream release with structural changes to feature flag system.
- **New `computerUse` feature flag** added to static registry (`jun()`, darwin-only). Added override to `enable_local_agent_mode.py` merger patch (8 features now overridden, up from 7).
- **`chillingSlothFeat` darwin gate re-introduced** — Was removed upstream in v1.1.9134, now back. Our Patch 1 regex already handles it.

### Fixed
- **enable_local_agent_mode.py**: Fixed `yukonSilver` regex — function name `$un()` contains `$` which `\w+` doesn't match. Updated pattern to use `[\w$]+` for function names.

### Docs
- **CLAUDE_FEATURE_FLAGS.md**: Updated for v1.1.9669 — 18 features (was 17), new function names, new GrowthBook flags (`3691521536` stealth updater, `3190506572` Chrome perms), remote orchestrator flag `4201169164` removed.
- **CLAUDE_BUILT_IN_MCP.md**: Updated for v1.1.9669 — registration function renamed `Pee()`→`Are()`.

### New Upstream (not patched — not needed)
- **Stealth updater** (flag `3691521536`) — nudges updates when no sessions active. Works on Linux as-is.
- **Epitaxy route** (flag `1585356617`) — new CCD session URL routing with `spawn_task` tool. Not platform-gated.
- **Org plugins path** — returns `null` on Linux (graceful no-op). Only needed for enterprise deployments.
- **Remote orchestrator (manta)** — hardcoded off (`Qhn=!1`). Flag `4201169164` removed from GrowthBook.

## 2026-03-29 (v1.1.9493)

### Changed
- **Version bump to v1.1.9493** — Upstream metadata-only re-release; JS bundles are byte-for-byte identical to v1.1.9310. No new features, MCP servers, or platform checks.
- **Custom themes: visual polish** — Borders now use accent color with subtle alpha (e.g. `#cba6f718`) instead of neutral gray, matching each theme's palette. Added accent-colored scrollbars, dialog/menu/tooltip glow shadows, button hover glow, smooth transitions on interactive elements, and transparent input borders/focus rings for a cleaner look. All 6 theme JSON files updated.

### Fixed
- **fix_process_argv_renderer.py**: Platform spoof pattern (`platform="win32"`) no longer exists in mainView.js. Added primary pattern matching `exposeInMainWorld("process",<var>)` to insert `argv=[]` before the expose call. Old spoof-based and appVersion-based patterns retained as fallbacks.
- **enable_local_agent_mode.py**: Async feature merger restructured from arrow function `async()=>({...Oh(),...})` to block body with `Promise.all` and explicit `return{...vw(),...}`. Added new regex for the block-body format; old arrow-function pattern retained as fallback.

### Docs
- **CLAUDE_BUILT_IN_MCP.md**: Expanded Claude Preview section with full tool catalog (13 tools), `.claude/launch.json` configuration, and architecture description. Updated to v1.1.9493.
- **CLAUDE.md**: Added CI-managed files section documenting that README install command versions are updated automatically by CI.

## 2026-03-29 (v1.1.9310-5)

### Fixed
- **Nix hash mismatch** (#19) — CI computed the Nix SRI hash from the locally-built tarball artifact, but users download from GitHub Releases. Non-deterministic tar builds across CI re-runs caused the hash to drift from the actual release asset. Fixed by computing the hash from the downloaded release tarball instead of the build artifact. Reverted `package.nix` hash to match the actual released tarball.

## 2026-03-28 (v1.1.9310-4)

### Fixed
- **Dispatch: SendUserMessage now works natively** — CLI v2.1.86 fixed the `CLAUDE_CODE_BRIEF=1` env var parser. The Ditto dispatch orchestrator agent now calls `SendUserMessage` directly — no synthetic transform needed. Removed Patch I (bridge-level text→SendUserMessage workaround)

### Changed
- **Dispatch: removed Patch I** — The synthetic `SendUserMessage` transform in `fix_dispatch_linux.py` is no longer needed. Patch F (rjt bridge filter widening) retained as defense-in-depth for edge cases
- **Dispatch: documented Ditto architecture** — Added [Dispatch Architecture](#dispatch-architecture) section to README documenting the orchestrator agent, session types (`chat`/`agent`/`dispatch_child`), and Linux adaptations
- **SEND_USER_MESSAGE_STATUS.md** — Complete rewrite reflecting fixed state: Ditto architecture, `--disallowedTools` discovery, `present_files` interception, `SendUserMessage` full signature, version bisect updated through v2.1.86

## 2026-03-28 (v1.1.9310-3)

### Fixed
- **Launcher shebang**: Removed two leading spaces before `#!/usr/bin/env bash` that caused `Exec format error` when launched from desktop entries or protocol handlers (kernel requires `#!` at byte 0). Terminal launches were unaffected. (#17)

### Changed
- **Build: shebang validation**: `build-patched-tarball.sh` now validates that the launcher script has `#!` at byte 0 before creating the tarball, preventing this class of bug from reaching users

## 2026-03-27 (v1.1.9310)

### Changed
- **Launcher: native Wayland by default** — Wayland sessions now use native Wayland instead of XWayland. Global hotkeys (Ctrl+Alt+Space) work via `xdg-desktop-portal` GlobalShortcuts API (KDE, Hyprland; Sway/GNOME pending upstream portal support). Set `CLAUDE_USE_XWAYLAND=1` to force XWayland if needed. Niri sessions still auto-forced to native Wayland. The old `CLAUDE_USE_WAYLAND=1` env var is now a no-op (native is the default).
- **CI**: Remove push trigger from release workflow — now runs only on nightly schedule (2 AM UTC) or manual dispatch

### Fixed
- **fix_utility_process_kill.py**: Logger variable changed from `\w+` name to `$` — updated pattern to `[\w$]+` for the `.info()` call
- **fix_detected_projects_linux.py**: Same `$` logger issue — updated pattern to `[\w$]+` for the `.debug()` call
- **fix_dispatch_linux.py**: Same `$` logger issue in sessions-bridge gate pattern and auto-wake parent pattern — updated all logger references to `[\w$]+`. Dispatch now applies 8/8 sub-patches (was 6/8)

### New Upstream
- **Operon (full-stack web agent)**: Still gated behind flag `1306813456`, returns `{status:"unavailable"}` unconditionally. Will need Cowork-style patch when activated
- **Epitaxy (new sidebar mode)**: No platform gate — works on Linux as-is
- **Imagine (visual creation MCP server)**: No platform gate — works on Linux as-is

## 2026-03-27 (v1.1.9134)

### Fixed
- **enable_local_agent_mode.py — Patch 7 (mainView.js platform spoof)**: Variable `$s` contains `$` which isn't matched by `\w+`. Changed regex to use `[\w$]+` for filter variable names in `Object.fromEntries(Object.entries(process).filter(([e])=>$s[e]))`.
- **fix_computer_use_linux.py — Sub-patch 6 rewrite (hybrid handler)**: Replaced full `handleToolCall` replacement with a hybrid early-return injection. Teach tools (`request_teach_access`, `teach_step`, `teach_batch`) now fall through to the upstream chain (which uses `__linuxExecutor` via sub-patches 3-5), enabling the teach overlay on Linux. Normal CU tools keep the fast direct handler. Also fixed: variable name collisions (`var c` hoisting vs upstream `const c`).
- **fix_computer_use_linux.py — Sub-patch 8 rewrite (tooltip-bounds polling)**: Previous fix polled cursor against `getContentBounds()` (= full screen) so `setIgnoreMouseEvents(false)` was permanently set, blocking the entire desktop. Now queries the `.tooltip` card's actual `getBoundingClientRect()` from the renderer via `executeJavaScript`, checks cursor against card bounds with 15px padding. Also fixed stale cursor: Electron's `getCursorScreenPoint()` returns frozen coordinates on X11 when cursor isn't over an Electron window — now uses `xdotool getmouselocation` → `hyprctl cursorpos` → Electron API fallback chain (cached 100ms).
- **fix_computer_use_linux.py — Sub-patches 9a/9b (step transition)**: Neutralized `setIgnoreMouseEvents(true,{forward:true})` calls in `yJt()` (show step) and `SUn()` (working state) on Linux. These fought with the polling loop during step transitions. Polling now has sole control of mouse event state on Linux, with 400ms grace period.
- **fix_computer_use_linux.py — `listInstalledApps()` app resolution**: Teach mode failed with `"reason":"not_installed"` because `.desktop` display names (e.g., "Thunar File Manager") didn't match model requests (e.g., "Thunar"). Now emits multiple name variants per app: full name, short name (first word), exec name, Icon= bundleId (reverse-domain), .desktop filename. Also scans Flatpak app directories.
- **fix_computer_use_linux.py — `switch_display`**: Real implementation using `xrandr` display enumeration and `globalThis.__cuPinnedDisplay` state tracking. Screenshots respect pinned display. Replaces the previous "not available" stub.
- **fix_computer_use_linux.py — `computer_batch`**: Fixed return format to match upstream's `{completed:[...], failed:{index,action,error}, remaining:[...]}` structure instead of only returning the last result.

### Removed
- **fix_tray_path.py** — Deleted: redundant since `fix_locale_paths.py` already replaces ALL `process.resourcesPath` references globally (including the tray path function). Patch count: 33→32.

### New Upstream
- **New MCP server: `ccd_session`** — Provides `spawn_task` tool to spin off parallel tasks into separate Claude Code Desktop sessions. Gated by CCD session + server flag `1585356617`. Already Linux compatible (no platform gates).
- **5 new Computer Use tools** — `switch_display` (multi-monitor), `computer_batch` (batch actions), `request_teach_access`, `teach_step`, `teach_batch` (guided teach mode). Total tools: 22→27. All 5 now Linux compatible.
- **New feature flag: `wakeScheduler`** — macOS-only Login Items scheduling (gated by `Kge()` + darwin). Not needed on Linux — the scheduled tasks engine is platform-independent (`setInterval` + cron evaluation). Tasks fire on wake-up if missed during sleep.
- **Operon expanded**: 18→28 sub-interfaces (9 new: `OperonAgentConfig`, `OperonAnalytics`, `OperonAssembly`, `OperonHostAccessProvider`, `OperonImageProvider`, `OperonQuitHandler`, `OperonServices`, `OperonSessionManager`, `OperonSkillsSync`). Still gated behind flag `1306813456`.
- **New GrowthBook flags**: `66187241` + `3792010343` (tool use summaries), `1585356617` (epitaxy/session routing), `2199295617` (auto-archive PRs), `927037640` (subagent model config), `2893011886` (wake scheduler timing). All cross-platform, no patching needed. Removed: `3196624152` (Phoenix Rising updater).

### Added
- **Unified launcher across all packaging formats** — RPM, DEB, and AppImage now use the full launcher script (Wayland/X11 detection, SingletonLock cleanup, cowork socket cleanup, logging) instead of minimal 2-3 line stubs. Launcher auto-discovers Electron binary and app.asar paths at runtime. Fixes [#13](https://github.com/patrickjaja/claude-desktop-bin/issues/13).
- **GPU compositing fallback (`CLAUDE_DISABLE_GPU`)** — New env var to fix white screen on systems with GBM buffer creation failures (common on Fedora KDE / Wayland). `CLAUDE_DISABLE_GPU=1` disables GPU compositing; `CLAUDE_DISABLE_GPU=full` disables GPU entirely.
- **AppImage auto-update support** — AppImages now embed `gh-releases-zsync` update information and ship with `.zsync` delta files. Users can update via `appimageupdatetool`, `--appimage-update` CLI flag, or compatible tools (AppImageLauncher, Gear Lever). Only changed blocks are downloaded.
- **Wayland support in Computer Use executor** — Full auto-detection via `$XDG_SESSION_TYPE`. On Wayland: `ydotool` for input, `grim` for screenshots (wlroots), `wl-clipboard` for clipboard, Electron APIs for display enumeration and cursor position. On X11: existing tools (`xdotool`, `scrot`, `xclip`, `xrandr`). Falls back to X11/XWayland if Wayland tools are not installed. Compositor-specific window info via `hyprctl` (Hyprland) and `swaymsg` (Sway).
- **Fedora/RHEL DNF repository** — RPM packages now published to GitHub Pages alongside APT. One-line setup: `curl -fsSL .../install-rpm.sh | sudo bash`. Auto-updates via `dnf upgrade`. Scripts: `packaging/rpm/update-rpm-repo.sh`, `packaging/rpm/install-rpm.sh`.

### Changed
- **Dependencies** — Moved `nodejs` from `depends` to optional across all formats (Electron bundles Node.js; system node only needed for MCP extensions requiring specific versions). Added Wayland optdeps (`ydotool`, `grim`, `slurp`, `wl-clipboard`, `wlr-randr`) and `xorg-xrandr` with (X11)/(Wayland) annotations. Updated: PKGBUILD.template, debian/control, rpm/spec, nix/package.nix.
- **CLAUDE_BUILT_IN_MCP.md** — Updated for v1.1.9134: new `ccd_session` server, 5 new computer-use tools, registration function rename `IM()`→`Pee()`, expanded Operon sub-interfaces.
- **CLAUDE_FEATURE_FLAGS.md** — Updated for v1.1.9134: new `wakeScheduler` (17 features total), function renames (`dA`→`rw`, `JX`→`yre`, `Oet`→`Kge`, `Hn`→`kn`, `Hk`→`bC`), 4 new GrowthBook flags, 1 removed flag.
- **README.md** — Fedora section updated from manual download to DNF repo with auto-updates. Computer Use feature description updated with Wayland/X11 tool split.

### CI
- **Parallelized GitHub Actions workflow** — Refactored monolithic single-job pipeline into fan-out/fan-in pattern with 8 jobs. Package builds (AppImage, DEB, RPM × 2 architectures), Nix test, and PKGBUILD generation now run in parallel on separate runners after the tarball build. Estimated ~6 min savings per run.

### Notes
- **All 32 patches pass** with zero failures on v1.1.9134.
- **Computer Use teach mode** now works on Linux — the teach overlay is pure Electron `BrowserWindow` + IPC, not macOS-specific. The hybrid handler routes teach tools through the upstream chain while keeping the fast direct handler for normal tools.
- **No new platform gates** blocking core Linux functionality. The 4 new GrowthBook flags and `ccd_session` MCP server are all platform-independent.
- **Verified all existing patches still needed** — upstream has NOT removed darwin gates for chillingSlothFeat, yukonSilver, or navigator spoofs despite initial false positive (caused by inspecting already-patched files).

## 2026-03-25 (v1.1.8629)

### Fixed
- **fix_dispatch_linux.py — Patch A (Sessions-bridge gate)**: Variable declaration changed from single (`let f=!1;const`) to triple (`let f=!1,p=!1,h=!1;const`). Updated regex to handle comma-separated declarations with `(?:\w+=!1,)*` prefix. The gate variable `h` is now `h = f || p` where `p` is the new remote orchestrator flag.
- **fix_dispatch_linux.py — Patch J (Auto-wake parent)**: Logger variable renamed `B` → `P`. Converted from hardcoded byte string to regex with dynamic capture group for the logger variable.
- **fix_dispatch_linux.py — Patch K (present_files unblock)**: Removed `mcp__cowork__present_files` from `RIt` renderer-dependent disallowed tools list. This tool works through the MCP proxy and doesn't need the local renderer. Without this, dispatch file sharing (e.g. PDF generation from phone) gets "Permission denied".

### New Upstream
- **Feature flag `4201169164`** — Remote Orchestrator (codename "manta" / `yukon_silver_manta_desktop`). Alternative to local Cowork: connects to Anthropic's cloud via WebSocket (`wss://bridge.claudeusercontent.com`) instead of local `cowork-svc`. Enabled via env var `CLAUDE_COWORK_FORCE_REMOTE_ORCHESTRATOR=1` or developer setting `isMantaDesktopEnabled`. Not tested on Linux — likely requires Pro account or server-side enablement.
- **16 i18n locale files** — de-DE, en-US, en-XA, en-XB, es-419, es-ES, fr-FR, hi-IN, id-ID, it-IT, ja-JP, ko-KR, pt-BR, xx-AC, xx-HA, xx-LS. Already handled by build script's i18n copy step.
- **Developer setting `isMantaDesktopEnabled`** — New toggle in developer settings: "Forces yukon_silver_manta_desktop (remote orchestrator mode) regardless of GrowthBook".

### Changed
- **CLAUDE_FEATURE_FLAGS.md** — Updated for v1.1.8629: new flag `4201169164` (remote orchestrator), function renames (`Qn`→`Hn`, `Bx`→`Hk`, `lA`→`dA`, `jY`→`JX`, `VKe`→`Oet`), documented remote orchestrator architecture and env vars.

### Notes
- **No new platform gates** — No new `darwin`/`win32`-only patterns found. All 32 existing patches still required.
- **All 32 patches pass** with zero failures on v1.1.8629. Only variable name renames (handled by `\w+` wildcards).

## 2026-03-24 (v1.1.8359)

### Added
- **fix_computer_use_linux.py** — New patch: enables Computer Use on Linux with 6 sub-patches. Removes 3 upstream platform gates (`b7r()`, `ZM()`, `createDarwinExecutor`), provides a Linux executor using xdotool/scrot/xclip/wmctrl, bypasses macOS TCC permissions (`ensureOsPermissions` returns granted), and replaces the macOS permission model (`rvr()` allowlist/tier system) with direct tool dispatch. 22 tools work immediately without `request_access` — no app tier restrictions, no bundle ID matching, no permission dialogs.
- **fix_detected_projects_linux.py** — New patch: enables Recent Projects on Linux. Maps VSCode (`~/.config/Code/`), Cursor (`~/.config/Cursor/`), and Zed (`~/.local/share/zed/`) workspace detection paths. Home directory scanner already works cross-platform.
- **fix_enterprise_config_linux.py** — New patch: reads enterprise config from `/etc/claude-desktop/enterprise.json` on Linux. Returns `{}` if file doesn't exist (preserving current behavior).

### Changed
- **fix_marketplace_linux.py** — Simplified: removed dead Pattern A (runner selector, refactored upstream) and Pattern B (search_plugins, removed upstream). Only Pattern C (CCD gate) remains.
- **CLAUDE_FEATURE_FLAGS.md** — Updated for v1.1.8359: new `operon` feature (#16), function renames, 4 new GrowthBook flags, 2 removed flags.
- **CLAUDE_BUILT_IN_MCP.md** — Updated for v1.1.8359: Operon IPC system (120+ endpoints), visualize factory rename, all 14 MCP servers unchanged.
- **README.md** — Added new patches to table, removed `fix_mcp_reconnect.py`, added Known Limitations section (Browser Tools).

### Removed
- **fix_mcp_reconnect.py** — Deleted: close-before-connect fix is now upstream (since v1.1.4088+). Patch was a no-op.

### Notes
- **Computer Use MCP is back** — Removed in v1.1.7714 (commit 2c69b13) when upstream dropped the standalone `computer-use-server.js`. Now reintroduced as a built-in internal MCP server integrated into `index.js`. Upstream gates it to macOS-only (`@ant/claude-swift`); our patch provides a Linux-native implementation.
- **Operon (Nest)** — Major new upstream feature (120+ IPC endpoints). Currently server-gated (flag `1306813456`), requires VM infrastructure. Not patched — waiting for Anthropic to enable.
- **Browser Tools** — Documented as known limitation. Server registration requires `chrome-native-host` binary (Rust, proprietary, Windows/macOS only).

## 2026-03-23 (v1.1.8308)

### Added
- **fix_office_addin_linux.py** — New patch: enable Office Addin MCP server on Linux by extending the `(ui||as)` platform gate in 3 locations (MCP isEnabled, init block, connected file detection). The underlying WebSocket bridge is platform-agnostic; this enables future compatibility with web Office or LibreOffice add-ins.
- **fix_read_terminal_linux.py** — New patch: enable `read_terminal` built-in MCP server on Linux (was hardcoded to `darwin` only). Reads integrated terminal panel content in CCD sessions.
- **fix_browse_files_linux.py** — New patch: add `openDirectory` to the browseFiles file dialog on Linux. Electron fully supports directory selection on Linux but upstream only enabled it for macOS.

### Fixed
- **fix_process_argv_renderer.py** — Fix for v1.1.8308: hardcoded `Ie` variable name → dynamic `\w+` capture. Upstream renamed the process proxy from `Ie` to `at`.
- **fix_quick_entry_position.py** — Fix for v1.1.8308: hardcoded `ai` window variable → dynamic `[\w$]+` capture group. Upstream renamed Quick Entry window var from `ai` to `Js`.
- **fix_dispatch_linux.py** — Enhanced Patch I: now also transforms `mcp__cowork__present_files` tool_use blocks into SendUserMessage attachments, so file sharing renders on the phone.

### Previous (2026-03-23)

### Fixed
- **fix_dispatch_linux.py — Restore Patch I (text→SendUserMessage transform)** — Claude Code CLI 2.1.x has a bug where `--brief` + `--tools SendUserMessage` does not expose the `SendUserMessage` tool to the model. The model falls back to plain text, which the sessions API silently drops (only `SendUserMessage` tool_use blocks are rendered on the phone). Patch I injects a transform in `forwardEvent()` that wraps plain text assistant messages as synthetic `SendUserMessage` tool_use blocks before writing to the transport.

### Changed
- ~~fix_dispatch_linux.py — Removed Patch I~~ — Reverted: Patch I is needed as a workaround for the CLI `SendUserMessage` bug

### Added
- **CLAUDE_BUILT_IN_MCP.md — Per-session dynamic MCP servers** — Documented 4 SDK-type MCP servers created dynamically per cowork/dispatch session: `dispatch` (6 tools), `cowork` (4 tools), `session_info` (2 tools), `workspace` (2 tools). Includes tool schemas, registration method, allowedTools/disallowedTools logic, and SDK server architecture diagram comparing Mac/Windows VM vs Linux native paths.
- **fix_updater_state_linux.py** — New patch: add `version`/`versionNumber` empty strings to idle updater state so downstream code calling `.includes()` on `version` doesn't crash with `TypeError: Cannot read properties of undefined`
- **fix_process_argv_renderer.py** — New patch: inject `Ie.argv=[]` into preload so SDK web bundle's `process.argv.includes("--debug")` no longer throws TypeError

### Fixed
- **Dispatch text responses now render** — Patched the sessions-bridge `rjt()` filter (Patch F) to forward text content blocks and SDK MCP tool_use responses (`mcp__dispatch__send_message`, `mcp__cowork__present_files`)
- **Navigator platform timing gap** — Changed navigator.platform spoofing from `dom-ready` only to both `did-navigate` + `dom-ready` fallback, closing the window where page scripts see real `navigator.platform` while `process.platform` is already spoofed to `"win32"`
- **Removed diagnostic patches G/H** — forwardEvent and writeEvent logging removed from fix_dispatch_linux.py (no longer needed)

### Documentation
- **CLAUDE.md** — Added "Dispatch Debug Workflow" section with step-by-step debug commands for bridge events, audit analysis, cowork-service args, and session clearing
- **README.md** — Added "Clear Dispatch session" troubleshooting section

## 2026-03-20

### Added
- **Custom Themes (Experimental)** — New `add_feature_custom_themes.py` patch: inject CSS variable overrides into **all windows** (main chat, Quick Entry, Find-in-Page, About) via Electron's `insertCSS()` API. Ships 6 built-in themes (sweet, nord, catppuccin-mocha, catppuccin-frappe, catppuccin-latte, catppuccin-macchiato). Configure via `~/.config/Claude/claude-desktop-bin.json`.
- **themes/** — Community theme directory with ready-to-use JSON configs, screenshots, CSS variable reference (`css-documentation.html`), and `README.md` documenting how to extract app HTML/CSS for theme creation
- **Full-window theming** — Quick Entry gradient, prose/typography (`--tw-prose-*`), `--always-black/white` shadows, checkbox accents, title bar text now all follow the active theme

### Changed
- **CLAUDE_FEATURE_FLAGS.md** — Comprehensive update for v1.1.7714: new `yukonSilverGemsCache` feature (15 total), complete GrowthBook flag catalog (34 boolean + 9 object/value + 3 listener flags), function renames (fp/cN/r1e/xq), version history table updated

### Added
- **fix_quick_entry_position.py** — Two new sub-patches for v1.1.7714:
  - Patch 3: Override position-save/restore (`T7t()`) to always use cursor's display (short-circuits saved position check)
  - Patch 4: Fix show/positioning + focus on Linux — pure Electron APIs, no external dependencies

### Fixed
- **fix_quick_entry_position.py (Patches 1 & 2)** — Fix stale cursor position on Linux: `Electron.screen.getCursorScreenPoint()` only updates when the cursor passes over an Electron-owned window, causing Quick Entry to always open on the app's monitor. Now uses `xdotool getmouselocation` (X11/XWayland) → `hyprctl cursorpos` (Hyprland/Wayland) → Electron API as defensive fallback chain. Both tools are optional — graceful degradation if unavailable.
- **Packaging** — Added `xdotool` as optional dependency across all formats (AUR `optdepends`, Debian `Suggests`, RPM `Suggests`, Nix optional input with PATH wiring)
- **fix_quick_entry_position.py (Patch 4)** — Complete rewrite of Linux Quick Entry positioning and focus:
  - **Positioning**: `setBounds()` before + after `show()` with retries at 50/150ms to counter X11 WM smart-placement. Works on X11, XWayland, and best-effort on native Wayland.
  - **Focus**: Three-layer focus chain — `focus()` (OS window) → `webContents.focus()` (renderer) → `executeJavaScript` to focus `#prompt-input` DOM element (only auto-focuses on initial page load, not on hide/show cycle).
  - Previously the Quick Entry would always open on Claude Desktop's monitor after interacting with the app, making it unusable in multi-monitor setups.
- **CLAUDE_BUILT_IN_MCP.md** — New documentation: built-in MCP server reference
- **docs/** — Screenshots directory

### Fixed
- **fix_dispatch_linux.py** — Fix sessions-bridge logger variable pattern: hardcoded `T` → `\w+` wildcard (logger renamed `T`→`C` in v1.1.7714)
- **fix_cowork_spaces.py** — Fix `createSpaceFolder` API: takes `(parentPath, folderName)` not `(spaceId, folderName)`; adds duplicate folder name dedup with numeric suffix
- **enable_local_agent_mode.py** — Promote platform spoof patches from WARN to FAIL (patches 5, 5b, 6, 7 are now required — if they don't match, the build should fail)
- **fix_utility_process_kill.py** — Promote from WARN/pass to FAIL (exit 1 on 0 matches so CI catches pattern changes)

### Removed
- **computer-use-server.js** — Linux Computer Use MCP server removed (upstream removed `computer-use-server.js` from app root in v1.1.7714; `existsSync` guard fails at runtime, server never registers)
- **fix_computer_use_linux.py** — Computer Use registration patch removed (no server file to register)
- **PKGBUILD** — Removed `scrot` optional dependency (Computer Use removed); added `hyprland` (hyprctl cursor fallback) and `socat` (cowork socket health check)

### Improved
- **scripts/build-local.sh** — Auto-download latest exe with version comparison: queries version API first, skips download if local exe matches latest, saves downloaded exe for future builds

## 2026-03-19

### Changed
- **Update to Claude Desktop v1.1.7464** (from v1.1.7053)

### Added
- **fix_dispatch_linux.py** — New patch: enables Dispatch (remote task orchestration from mobile) on Linux. Four sub-patches:
  - A: Forces sessions-bridge init gate ON (GrowthBook flag `3572572142` — `let f=!1` → `let f=!0`)
  - B: Bypasses remote session control check (GrowthBook flag `2216414644` — `!Jr(...)` → `!1`)
  - C: Adds Linux to `HI()` platform label (`"Unsupported Platform"` → `"Linux"`)
  - D: Includes Linux in `Xqe` telemetry gate so dispatch analytics are not silently dropped
- **fix_window_bounds.py** — New patch: fixes three window management issues on Linux:
  - Child view bounds fix: hooks maximize/unmaximize/fullscreen/moved events to manually set child view bounds (fixes blank white area on KWin corner-snap)
  - Ready-to-show size jiggle: +1px resize then restore after 50ms to force Chromium layout recalculation on first load
  - Quick Entry blur before hide: adds `blur()` before `hide()` for proper focus transfer
- **scripts/claude-desktop-launcher.sh** — New launcher script replacing the bare `exec electron` one-liner:
  - Wayland/X11 detection (defaults to XWayland for global hotkey support, `CLAUDE_USE_WAYLAND=1` for native Wayland)
  - Auto-detects Niri compositor (forces native Wayland — no XWayland)
  - Electron args: `--disable-features=CustomTitlebar`, `--ozone-platform`, `--enable-wayland-ime`, etc.
  - Environment: `ELECTRON_FORCE_IS_PACKAGED=true`, `ELECTRON_USE_SYSTEM_TITLE_BAR=1`
  - SingletonLock cleanup (removes stale lock files from crashed sessions)
  - Cowork socket cleanup (removes stale `cowork-vm-service.sock`)
  - `CLAUDE_MENU_BAR` support (auto/visible/hidden)

### Fixed
- **Navigator spoof changed from Mac to Windows** — `navigator.platform` now returns `"Win32"` instead of `"MacIntel"` and `userAgentFallback` spoofs as Windows, so the frontend shows Ctrl/Alt shortcuts instead of ⌘/⌥. Server-facing HTTP headers still send "darwin" for Cowork feature gating.

### Notes
- 27/27 patches pass (fix_mcp_reconnect.py: upstream fix, no patch needed)
- Feature flag architecture unchanged from v1.1.7053 — same 14 flags, same 3-layer override
- New upstream features in v1.1.7464: SSH remote CCD sessions, Scheduled Tasks (cron), Teleport to Cloud, Git/PR integration, DXT extensions, Keep-Awake
- New sidebar mode: `"epitaxy"` (purpose unknown)
- CoworkSpaces fully implemented on Linux — file-based `_SpacesService` with JSON persistence, 17 CRUD/file methods, push events, and SpaceManager singleton integration. Spaces UI is rendered by the claude.ai web frontend (server-side gated by Anthropic, not desktop feature flags). Dispatch works independently of Spaces (spaceId is optional in session creation)
- Function renames: rp/zM/$Se/oq (was Kh/$M/Qwe/K9)
- eipc UUID: `fcf195bd-4d6c-4446-98e4-314753dfa766` (dynamically extracted)

## 2026-03-17

### Changed
- **Update to Claude Desktop v1.1.7053** (from v1.1.3189)

### Added
- **fix_cowork_spaces.py** — New patch: injects a full file-based CoworkSpaces service on Linux. The renderer calls `getAllSpaces`, `createSpace`, `getAutoMemoryDir`, etc. via eipc but no handler is registered in the main process on Linux (native backend doesn't load). The `_SpacesService` class provides JSON persistence (`~/.config/Claude/spaces.json`), full CRUD for spaces/folders/projects/links, file operations with security validation, push event notifications, and SpaceManager singleton integration so `resolveSpaceContext` works.

### Fixed
- **enable_local_agent_mode.py** — Fix mC() merger pattern: `\w+` → `[\w$]+` for the async merger variable name (was `$M` in this version, `$` not matched by `\w`)

### Notes
- 24/24 patches pass (fix_mcp_reconnect.py: upstream fix, no patch needed)
- New feature flag `floatingAtoll` added upstream (always `{status:"unavailable"}` — disabled for all platforms, no Linux patch needed)
- New settings: `chicagoEnabled`, `keepAwakeEnabled`, `coworkScheduledTasksEnabled`, `ccdScheduledTasksEnabled`, `sidebarMode`, `bypassPermissionsModeEnabled`, `autoPermissionsModeEnabled`
- New developer flags: `isPhoenixRisingAgainEnabled` (new updater), `isDxtEnabled`/`isDxtDirectoryEnabled` (browser extensions), `isMidnightOwlEnabled`
- eipc UUID changed to `316b9ec7-48bb-494d-b1a8-82f8448548fb` (dynamically extracted by fix_computer_use_tcc.py)
- Function renames: Kh/$M/Qwe/K9 (was nh/rO/Ebe/J5)
- `fix_marketplace_linux.py` Patches A & B return 0 matches (patterns refactored upstream); Patch C (CCD gate) still active

## 2026-03-15

### Fixed
- **fix_dock_bounce.py** — Comprehensive fix for taskbar attention-stealing on KDE Plasma and other Linux DEs ([#10](https://github.com/patrickjaja/claude-desktop-bin/issues/10)). Previous approach only patched `BrowserWindow.prototype` methods but missed `WebContents.focus()` which bypasses those overrides entirely and triggers `gtk_window_present()`/`XSetInputFocus()` at the C++ level, causing `_NET_WM_STATE_DEMANDS_ATTENTION`. New approach:
  - **Layer 1 (prevent):** No-op `flashFrame(true)`/`app.focus()`, guard `BrowserWindow.focus()`/`moveTop()`, use `showInactive()` instead of `show()` when app not focused, enable `backgroundThrottling` on Linux, early-return `requestUserAttention()`, **intercept `WebContents.focus()` via `web-contents-created` event** (the key fix — only allow when parent window is focused)
  - **Layer 2 (cure):** On every window blur, actively call the real `flashFrame(false)` on a 500ms interval to continuously clear demands-attention state set by Chromium internals. Stops on focus.

## 2026-03-11

### Changed
- **Update to Claude Desktop v1.1.6041** (from v1.1.5749)

### Fixed
- **fix_computer_use_tcc.py** — Dynamically extract eipc UUID from source files instead of hardcoding it. The UUID changed from `a876702f-...` to `dbb8b28b-...` between versions, causing `No handler registered for ComputerUseTcc.getState` errors. Now searches index.js (fallback: mainView.js) for the UUID at patch time, making the patch resilient to future UUID rotations.

### Notes
- 22/22 patches pass (fix_mcp_reconnect.py: upstream fix, no patch needed)
- No new platform gates requiring patches — all critical darwin/win32 checks already handled
- Upstream now ships Linux CCD binaries (linux-x64, linux-arm64, musl variants) and Linux VM rootfs images in manifest
- New IPC handler groups: CoworkScheduledTasks, CoworkSpaces, CoworkMemory, LocalSessions SSH/Teleport, expanded Extensions
- New `sshcrypto.node` native addon for SSH support (not yet needed for core functionality)
- `louderPenguin` (Office Addin) remains darwin+win32 only — no action needed for Linux

## 2026-03-09

### Changed
- **Update to Claude Desktop v1.1.5749** (from v1.1.4498)

### Fixed
- **fix_disable_autoupdate.py** — Handle new `forceInstalled` check before platform gate in isInstalled function (pattern: `if(Qm.forceInstalled)return!0;if(process.platform!=="win32")...`)
- **claude-native.js** — Add stubs for new native methods: `readRegistryValues`, `writeRegistryValue`, `readRegistryDword`, `getCurrentPackageFamilyName`, `getHcsStatus`, `enableWindowsOptionalFeature`, `getWindowAbove`, `closeOfficeDocument`, `isProcessRunning`, `readCfPrefValue`
- **fix_marketplace_linux.py** — Downgrade runner selector and search_plugins handler patterns from FAIL to INFO (patterns removed in v1.1.5749 marketplace refactor; CCD gate patch C remains the essential fix)

### Added
- **fix_computer_use_tcc.py** — Register stub IPC handlers for ComputerUseTcc on Linux. The renderer (mainView.js) always calls `ComputerUseTcc.getState` but handlers are only registered by `@ant/claude-swift` on macOS. Stubs return `not_applicable` for permissions, preventing repeated IPC errors.
- **computer-use-server.js** — Linux Computer Use MCP server using xdotool (input) and scrot (screenshots) on X11. Provides 14 actions: left_click, right_click, double_click, triple_click, middle_click, type, key, screenshot, scroll, left_click_drag, hover, wait, zoom, cursor_position.
- **fix_computer_use_linux.py** — Registers computer-use-server.js as an internal MCP server via BR() (registerInternalMcpServer), spawning it as a Node.js child process with ELECTRON_RUN_AS_NODE=1. Only activates on Linux.
- **Packaging** — Added `xdotool` and `scrot` as optional dependencies across all formats: `optdepends` (Arch PKGBUILD), `Suggests` (Debian control, RPM spec), optional inputs with PATH wiring (Nix package.nix)

### Notes
- 22/22 patches pass (fix_mcp_reconnect.py: upstream fix, no patch needed)
- Computer Use requires `xdotool` and `scrot` packages (X11). Wayland not yet supported. Both are declared as optional dependencies across all packaging formats (AUR, Debian, RPM, Nix).
- No new feature flags detected (same 7: quietPenguin, louderPenguin, chillingSlothFeat, chillingSlothLocal, yukonSilver, yukonSilverGems, ccdPlugins)
- getLocalFileThumbnail uses pure Electron nativeImage API — no native stub needed
- Bridge methods (respondPluginSearch, kickBridgePoll, BridgePermission) are Electron IPC only

## 2026-03-02

### Fixed
- **scripts/build-patched-tarball.sh** — Bundle `claude-ssh` binaries from Windows package into `locales/claude-ssh/` to fix SSH remote environment feature ([#8](https://github.com/patrickjaja/claude-desktop-bin/issues/8))
- **patches/fix_0_node_host.py** — Fix shell path worker error (`Shell path worker not found at .../locales/app.asar/...`) by replacing `process.resourcesPath,"app.asar"` with `app.getAppPath()` before the global locale path redirect
- **PKGBUILD.template** — Restore `{{placeholders}}` so `generate-pkgbuild.sh` can substitute version/URL/SHA; hardcoded values caused local builds to use stale cached tarballs missing `claude-ssh` binaries
- **patches/claude-native.js** — Fix patch target from `app.asar.contents/node_modules/claude-native/` to `app.asar.unpacked/node_modules/@ant/claude-native/` to eliminate `ERR_DLOPEN_FAILED` invalid ELF header error
- **scripts/build-patched-tarball.sh** — Remove Windows `claude-native-binding.node` DLL after asar repack to prevent shipping unusable PE32 binary
- **packaging/debian/build-deb.sh** — Set SUID permission (4755) on `chrome-sandbox` after Electron extraction and in `postinst` script to fix startup crash on Ubuntu/Debian
- **packaging/rpm/claude-desktop-bin.spec** — Set SUID permission on `chrome-sandbox` in `%post` and `%files` sections to fix startup crash on RPM-based distros

## 2026-02-27

### Changed
- **PKGBUILD.template** — Set `url` to GitHub packaging repo instead of claude.ai per AUR guidelines

## 2026-02-25

### Changed
- **Update to Claude Desktop v1.1.4328** (from v1.1.4173)

### Fixed
- **enable_local_agent_mode.py** — Make yukonSilver formatMessage `id` field optional in regex (`(?:,id:"[^"]*")?`) to handle v1.1.4328 adding i18n IDs
- **enable_local_agent_mode.py** — Use `[\w$]+` instead of `\w+` for getSystemInfo `total_memory` variable (`$r` contains `$`)

### Notes
- 4 new IPC handlers: `CoworkSpaces.copyFilesToSpaceFolder`, `CoworkSpaces.createSpaceFolder`, `FileSystem.browseFiles`, `LocalSessions.delete`
- All 19 patches pass, no structural changes to platform gating or feature flags
- Key renames: chillingSlothFeat=TMt, quietPenguin=MMt, yukonSilver=RMt, os module=`$r`

## 2026-02-24

### Changed
- **Update to Claude Desktop v1.1.4088** (from v1.1.3918)

### Fixed
- **fix_disable_autoupdate.py** — Use `[\w$]+` instead of `\w+` for Electron module variable (`$e` contains `$`)
- **fix_marketplace_linux.py** — Use `[\w$]+` for all variable patterns; gate function renamed `Hb`→`$S`, managers `gz`→`CK`/`$K`
- **fix_quick_entry_position.py** — Use `[\w$]+` for Electron module variable; make fallback display patch optional (lazy-init pattern removed upstream)
- **fix_tray_icon_theme.py** — Use `[\w$]+` for Electron module variable (`$e`)
- **fix_mcp_reconnect.py** — Detect upstream close-before-connect fix and skip gracefully (upstream added `t.transport&&await t.close()`)
- **enable_local_agent_mode.py** — Add second regex variant for the yukonSilver (NH/WOt) platform gate to support v1.1.4173+ `formatMessage` pattern alongside the old template literal pattern

### Added
- **update-prompt.md** — New "Step 0: Clean Slate" section for removing stale artifacts before version updates
- **CLAUDE.md** — Added log files section documenting runtime logs at `~/.config/Claude/logs/`

### Notes
- Key renames: Electron module `Pe`→`$e`, CCD gate `Hb`→`$S`, marketplace managers `gz`/`mz`→`CK`/`$K`
- MCP reconnect fix is now upstream — patch detects and skips
- Common fix: `$` in minified JS identifiers requires `[\w$]+` in regex patterns

## 2026-02-21

### Changed
- **Update to Claude Desktop v1.1.3918** (from v1.1.3770)

### Added
- **RPM packaging** — `packaging/rpm/build-rpm.sh` + `claude-desktop-bin.spec` for Fedora/RHEL; builds in `fedora:40` container during CI, `.rpm` included in GitHub Release assets
- **NixOS packaging** — `flake.nix` + `packaging/nix/package.nix` using system Electron via `makeWrapper`; `packaging/nix/update-hash.sh` helper for version bumps
- **CI: RPM build/test** — Fedora container builds and smoke-tests the `.rpm` before release
- **CI: Nix build** — Validates `nix build` succeeds during CI; uses local `file://` tarball to avoid hash mismatch with not-yet-created GitHub release

### Fixed
- **enable_local_agent_mode.py** — Use `[\w$]+` instead of `\w+` for async merger function names (`$Pt` contains `$`); also make User-Agent spoof pattern variable-agnostic (`\w+\.set` instead of hardcoded `s\.set`)
- **fix_cowork_linux.py** — Use regex instead of literal match for error detection pattern; variable name changed from `t` to `e` in v1.1.3918

### Added
- **fix_mcp_reconnect.py** — New patch: fix MCP server reconnection error ("Already connected to a transport") by calling `close()` before `connect()` in the `connect-to-mcp-server` IPC handler

### Documentation
- **CLAUDE_FEATURE_FLAGS.md** — Updated for v1.1.3918: function renames (Oh→Fd, mC→mP, QL→o_e), `chillingSlothEnterprise` moved to static layer, `mP` simplified to only override `louderPenguin`, `ccdPlugins` inlined, added version history table

### Notes
- Key renames: Oh()→Fd(), mC()→mP, QL()→o_e(), all individual feature functions renamed
- `chillingSlothLocal` now unconditionally returns supported (no more win32/arm64 gate)
- `louderPenguin` removed from Fd() entirely, only exists in mP async merger

## 2026-02-20

### Changed
- **Update to Claude Desktop v1.1.3770** (from v1.1.3647)

### Fixed
- **fix_quick_entry_position.py** — Use `[\w$]+` instead of `\w+` for function name in position function pattern; minified name `s$t` contains `$` which `\w` doesn't match
- **fix_locale_paths.py / fix_tray_path.py** — Replace hardcoded `/usr/lib/claude-desktop-bin/locales` with runtime expression `require("path").dirname(require("electron").app.getAppPath())+"/locales"` so locale/tray paths resolve correctly for Arch, Debian, and AppImage installs (fixes [#7](https://github.com/patrickjaja/claude-desktop-bin/issues/7))
- **fix_node_host.py → fix_0_node_host.py** — Renamed so it runs before fix_locale_paths.py; regex updated to match original `process.resourcesPath` instead of post-patch hardcoded path
- **build-deb.sh** — Bundle Electron instead of depending on system `electron`; fix dependencies from Arch package names to Ubuntu/Debian shared library deps; fix launcher to use bundled binary

## 2026-02-19

### Changed
- **Update to Claude Desktop v1.1.3647** (from v1.1.3363, +284 builds)

### Fixed
- **fix_tray_path.py** — Use `[\w$]+` instead of `\w+` for function/variable names; minified name `f$t` contains `$` which `\w` doesn't match
- **fix_app_quit.py** — Same `[\w$]+` fix for variables `f$` and `u$` in the cleanup handler
- **fix_claude_code.py** — `getHostPlatform()` pattern updated: win32 block now has arm64 conditional (`e==="arm64"?"win32-arm64":"win32-x64"`) instead of hardcoded `"win32-x64"`. Also tightened the "already patched" idempotency check to prevent false positives from other patches' `if(process.platform==="linux")` injections
- **fix_claude_code.py** / **fix_cowork_linux.py** — Claude Code binary resolution now falls back to `which claude` dynamically when not found at standard paths, supporting npm global, nvm, and other non-standard install locations. `getStatus()` also gains the `which` fallback so the Code tab submit button no longer shows "Downloading dependencies..." for non-standard installs

### Documentation
- **CLAUDE_FEATURE_FLAGS.md** — Updated for v1.1.3770: added `ccdPlugins` (#13), updated `louderPenguin` gate info (async override in mC), added org-level settings section
- **enable_local_agent_mode.py** — Added `ccdPlugins:{status:"supported"}` to mC() override (7 features total)
- **update-prompt.md** — Added Feature Flag Audit prompt (Prompt 3) for version updates

### Notes
- New upstream feature: `ccdPlugins` added to Oh() static registry, `louderPenguin` moved from QL()-wrapped to direct call with `Xi()` feature check
- New settings: `chillingSlothLocation`, `secureVmFeaturesEnabled`, `launchEnabled`, `launchPreviewPersistSession`
- Key renames: function names now use `$` in identifiers (e.g., `f$t`, `f$`, `u$`)

## 2026-02-18

### Changed
- **Update to Claude Desktop v1.1.3363** (from v1.1.3189, 174 builds ahead)

### Fixed
- **fix_claude_code.py** — `getStatus()` regex now uses `[\w$]+` instead of `\w+` for the status enum name, fixing match failure when minifier produces `$`-prefixed identifiers (e.g. `$s`)
- **fix_marketplace_linux.py** — CCD gate function name and runner selector now use flexible `\w+` patterns instead of hardcoded `Hb`/`oAt` (function renamed to `Gw` in v1.1.3363)

### Added
- **update-prompt.md** — Reusable prompts for future version updates (build & fix, diff & discover)

### Notes
- Diff analysis shows only minified variable renames between v1.1.3189 and v1.1.3363
- One new feature flag `4160352601` (VM heartbeat auto-restart) — no Linux patch needed
- Key renames: `la()` → `Xi()` (feature flags), `Hb` → `Gw` (CCD gate), `Cs` → `$s` (status enum), `tt` → `rt` (path module)

## 2026-02-17

### Changed
- **Adapt download pipeline to new CDN structure** — Old `/latest/Claude-Setup-x64.exe` URL now returns 404 and the redirect endpoint returns a 6.7MB bootstrapper instead of the full installer. Updated `build-local.sh` and CI workflow to query the `.latest` JSON API for version+hash, then download the full 146MB installer from the hash-named URL.

### Fixed
- **"Manage" plugin sidebar flashes and closes on Cowork tab** — Patch `Hb()` (the CCD/Cowork gate function) to return true on Linux, routing all plugin operations through host-local CCD paths instead of account-scoped Cowork paths. On Linux there's no VM, so the CCD path is always correct. This single change fixes 5 call sites: runner selection (`oAt`), getPlugins, uploadPlugin, deletePlugin, and setPluginEnabled. The sidebar was closing because `getPlugins` looked in account-scoped directories where `gz` (host runner) hadn't installed anything.
- **Browse Plugins empty on Cowork tab** — New `fix_marketplace_linux.py` forces the host CLI runner (`gz`) for marketplace operations on Linux. Previously, the Cowork tab selected the VM runner (`mz`) which routed `claude plugin marketplace` commands through the daemon, failing with `MARKETPLACE_ERROR:UNKNOWN`. Since marketplace management is a host filesystem operation, the host runner is always correct on Linux.

### Known Issues
- **Cowork sidebar sessions** — Previous local sessions may not appear in the sidebar due to `local_`-prefixed UUIDs failing server-side validation. This is an upstream issue in the claude.ai renderer code.

## 2026-02-16

### Fixed
- **AUR sha256sum mismatch on patch releases** — Source filename now includes `pkgrel` (`claude-desktop-VERSION-PKGREL-linux.tar.gz`) so makepkg cache is busted on patch rebuilds. CI reordered to create GitHub Release before pushing to AUR, with a download verification step to prevent referencing non-existent tarballs.

- **Browse/Web Search in Cowork sessions** — MCP server proxying now works end-to-end. Requires `claude-cowork-service >= 0.3.2` which stops blocking MCP traffic between Claude Code and Desktop.

- **fix_cowork_linux.py** — Use empty bundle file list (`linux:{x64:[]}`) instead of copying win32's list. No VM files are needed since the native Go backend runs Claude Code directly. Empty array makes download status return Ready immediately, avoiding ENOSPC (tmpfs full) and EXDEV errors.
- **fix_cross_device_rename.py** — Use flexible `\w+` pattern for fs module name (changes between versions: `zr`, `ur`, etc.) and negative lookbehind to skip rename calls already inside try blocks

## 2026-02-11

### Changed
- **Multi-distro cowork install docs** — README Cowork section now includes universal curl one-liner alongside AUR instructions

### Added
- **Cowork Linux support (experimental)** — New `fix_cowork_linux.py` patch enables the Cowork VM feature on Linux:
  - Extends TypeScript VM client (`vZe`) to load on Linux instead of requiring `@ant/claude-swift`
  - Adds Unix domain socket path (`$XDG_RUNTIME_DIR/cowork-vm-service.sock`) as Linux alternative to Windows Named Pipe
  - Adds Linux platform to bundle config for VM image downloads
  - Requires `claude-cowork-service` daemon running on the host (QEMU/KVM-based)
- **claude-cowork-service optional dependency** — PKGBUILD now lists `claude-cowork-service` as optional for Cowork VM features
- **Cowork error messages** — New `fix_cowork_error_message.py` replaces Windows-centric "VM service not running" errors with Linux-friendly guidance pointing users to `claude-cowork-service`
- **Cross-device rename fix** — New `fix_cross_device_rename.py` handles EXDEV errors when moving VM bundles from `/tmp` (tmpfs) to `~/.config/Claude/`
- **Force rebuild workflow** — New `force_rebuild` checkbox in GitHub Actions manual trigger to rebuild and release when patches/features change without an upstream version bump. Auto-increments `pkgrel`, generates git changelog grouped by date, and updates AUR + GitHub Release

### Fixed
- **Claude Code binary discovery** — `fix_claude_code.py` and `fix_cowork_linux.py` now check multiple paths (`/usr/bin/claude`, `~/.local/bin/claude`, `/usr/local/bin/claude`) instead of only `/usr/bin/claude`, fixing "Downloading dependencies..." stuck state and cowork spawn failures for npm-installed Claude Code

### Changed
- **fix_vm_session_handlers.py** — Removed Linux platform stubs (getDownloadStatus, getRunningStatus, download, startVM); these methods now call through to the real TypeScript VM client which talks to the daemon via Unix socket. Only the global uncaught exception handler remains as a safety net.

### Removed
- **fix_hide_cowork_tab.py** — Deleted; the Cowork tab is now functional on Linux when the daemon is running. Without the daemon, connection errors appear naturally in the UI.

## 2026-02-10

### Added
- **Runtime smoke testing in CI** — Three layers of defense to prevent broken builds reaching users:
  - Brace mismatch in `fix_vm_session_handlers.py` now fails the build instead of warning
  - `node --check` validates JavaScript syntax on all patched files before repacking
  - New `scripts/smoke-test.sh` runs the Electron app headlessly via `xvfb-run` for 15s to catch runtime crashes
  - CI Docker container now installs `electron` and `xorg-server-xvfb` for smoke testing

### Fixed
- **fix_vm_session_handlers.py** — Replace false-positive absolute brace count check with delta check (comparing before/after patching); add support for new `try/catch` wrapper in `getRunningStatus` pattern (v1.1.2685+)
- **enable_local_agent_mode.py** — Update mC() merger pattern for v1.1.2685: `desktopVoiceDictation` was removed from async merger, now uses flexible pattern matching the full async arrow function instead of hardcoding the last property name

## 2026-02-06

### Fixed
- **fix_hide_cowork_tab.py** — Use flexible `\w+` regex instead of hardcoded `xg` function name, preventing breakage on minified variable name changes across releases

## 2026-02-05

### Added
- **Auto-hide menu bar on Linux** — Native menu bar (File, Edit, View, Help) is now hidden by default; press Alt to show it temporarily
- **Window icon on Linux** — Claude icon now appears in the window title bar

### Fixed
- **Disable non-functional Cowork tab** — Cowork requires ClaudeVM (unavailable on Linux); tab is now visually disabled with reduced opacity and click prevention via `fix_hide_cowork_tab.py`
- **Suppress false update notifications** — New `fix_disable_autoupdate.py` patch makes the isInstalled check return false on Linux, preventing "Update heruntergeladen" popups
- **Stop force-enabling chillingSlothFeat** — `enable_local_agent_mode.py` no longer patches the chillingSlothFeat (Cowork) function or overrides it in the mC() merger; only quietPenguin/louderPenguin (Code tab) are enabled
- **Gate chillingSlothLocal on Linux** — Added Linux platform check to prevent it from returning "supported"
- **Fix startVM parameter capture** — `fix_vm_session_handlers.py` now uses dynamic parameter name capture instead of hardcoded `e`
- **Fix getBinaryPathIfReady pattern** — `fix_claude_code.py` updated for new `getLocalBinaryPath()` code path in v1.1.2102

## 2026-02-02

### Fixed
- **Top bar now clickable on Linux** - Fixed non-clickable top bar elements (sidebar toggle, back/forward arrows, Chat/Code tabs, incognito button):
  - **Root cause**: `titleBarStyle:"hidden"` creates an invisible drag region across the top ~36px on Linux, intercepting all mouse events even with `frame:true`
  - **Fix**: `fix_native_frame.py` now replaces `titleBarStyle:"hidden"` with `"default"` on Linux via platform-conditional (`process.platform==="linux"?"default":"hidden"`), targeting only the main window (Quick Entry window preserved)
  - Removed `fix_title_bar.py` and `fix_title_bar_renderer.py` (no longer needed — the native top bar works correctly once the invisible drag region is eliminated)

## 2026-01-30

### Fixed
- **Code tab and title bar for v1.1.1520** - Fixed two UI regressions after upgrading to Claude Desktop v1.1.1520:
  - **Code tab disabled**: The QL() production gate blocks `louderPenguin`/`quietPenguin` features in packaged builds. Added mC() async merger patch to override QL-blocked features, plus preferences defaults patch (`louderPenguinEnabled`/`quietPenguinEnabled` → true)
  - **Title bar missing**: Electron 39's WebContentsView architecture occludes parent webContents. Created a dedicated WebContentsView (`tb`) for the title bar that loads the same `index.html` with its own IPC handlers, positioned at y=0 with 36px height, pushing the claude.ai view down
  - Removed `fix_browserview_position.py` (title bar is now a separate WebContentsView)

### Added
- **Feature flag documentation** (`CLAUDE_FEATURE_FLAGS.md`) - Documents all 12 feature flags, the 3-layer override architecture (Oh → mC → IPC), and the QL() production gate

### Changed
- **validate-patches.sh** - Fixed exit code checking (was checking sed's exit code instead of python3's due to piping)

## 2026-01-26

### Fixed
- **Title bar and sidebar issues for v1.1.886** - Fixed two related issues where title bar hides and sidebar toggle is not clickable:
  - New patch `fix_browserview_position.py`: Fixes BrowserView y-positioning - changes `c=Ds?eS+1:0` to `c=Pn?0:eS+1` so Linux gets the 37px title bar offset like Windows
  - Updated `fix_title_bar.py`: Disables both early returns in renderer with `false&&` prefix instead of removing negation

## 2026-01-20

### Added
- **Multi-distro packaging** - Claude Desktop now available for multiple Linux distributions:
  - **AppImage** - Portable, runs on any distro without installation (bundles Electron)
  - **Debian/Ubuntu (.deb)** - Native package for apt-based systems
  - All formats built automatically in CI and uploaded to GitHub Releases
- **Pre-built package distribution** - CI now builds and uploads pre-patched tarballs to GitHub Releases:
  - Reduced dependencies for users (no python, asar, p7zip needed)
  - Faster package installation
  - Changelog included in GitHub release notes

### Changed
- **Refactored build architecture** - Separated patching logic from package generation:
  - New `scripts/build-patched-tarball.sh` contains all patching logic in one place
  - `PKGBUILD.template` is now a simple tarball-based installer (no patches)
  - `generate-pkgbuild.sh` simplified to just template substitution
  - CI builds tarball once, then builds AppImage/.deb/Flatpak from it
  - Users download pre-patched tarball (no build-time patching needed)
- **Electron version** - AppImage/Flatpak now fetch latest stable Electron automatically

## 2026-01-19

### Fixed
- **Patch patterns for v1.1.381** - Updated patches to use flexible regex patterns:
  - enable_local_agent_mode.py: Use `\w+` wildcard for minified function names (qWe→wYe, zWe→EYe)
  - fix_claude_code.py: Use regex with capture group for status enum name (Yo→tc)
  - fix_tray_icon_theme.py: Always use light tray icon on Linux (trays are universally dark)
  - fix_vm_session_handlers.py: Use regex patterns for all VM functions (WBe→Wme, Zc→Xc, IS→YS, ty→g0, qd→Qd, Qhe→Hme, Jhe→MB, ce→oe)

## 2026-01-13

### Added
- **Local Agent Mode for Linux** - New patch (enable_local_agent_mode.py) enables the "chillingSloth" feature on Linux:
  - Enables Local Agent Mode sessions with git worktree isolation
  - Enables Claude Code for Desktop integration
  - Patches qWe() and zWe() platform checks to return "supported" on all platforms
  - Note: SecureVM (yukonSilver) and Echo features still require macOS-only Swift modules
- **ClaudeVM Linux handling** - New patch (fix_vm_session_handlers.py) to gracefully handle VM features not supported on Linux:
  - getDownloadStatus returns NotDownloaded on Linux
  - getRunningStatus returns Offline on Linux
  - download/startVM fail with helpful error messages
  - Error handler suppresses unsupported feature errors

### Fixed
- **Claude Code Linux platform support** - Updated fix_claude_code.py to add Linux support:
  - Added Linux platform detection to getHostPlatform() (root cause of "Unsupported platform: linux-x64" error)
  - Linux checks now run BEFORE getHostTarget() to avoid throwing errors

## 2026-01-12

### Fixed
- **Patch patterns for v1.0.3218** - Updated patches to use flexible regex patterns:
  - fix_claude_code.py: Updated for new `getHostTarget()` and `binaryExistsForTarget()` APIs, status enum `Rv→Yo`
  - fix_app_quit.py: Use dynamic capture for variable names (`S_&&he→TS&&ce`)
  - fix_tray_dbus.py: Fix async check to avoid matching similar function names, handle preamble code before first const

## 2026-01-08

### Added
- **App quit fix** - Fix app not quitting after cleanup on Linux (fix_app_quit.py). After `will-quit` handler calls `preventDefault()`, `app.quit()` becomes a no-op. Solution uses `app.exit(0)` with `setImmediate` after cleanup completes.
- **UtilityProcess SIGKILL fix** - Use SIGKILL as fallback when UtilityProcess doesn't exit gracefully (fix_utility_process_kill.py)
- **Custom app icon** - Extract full-color orange Claude logo from setupIcon.ico at build time (requires icoutils)

### Fixed
- Fixed app hanging on exit when using integrated Node.js server for MCP

## 2025-12-17

### Added
- **MCP node host path fix** - Fix incorrect path for MCP server node host on Linux (fix_node_host.py)
- **Startup settings fix** - Handle Linux platform in startup settings to avoid validation errors (fix_startup_settings.py)
- **Tray icon theme fix** - Always use light tray icon on Linux since system trays are universally dark (fix_tray_icon_theme.py)

## 2025-12-02

### Fixed
- **Patch patterns for v1.0.1405** - Updated fix_quick_entry_position.py to use backreference pattern for fallback display variable (r→n)

## 2025-11-26

### Added
- **CLAUDE.md** - Patch debugging guidelines for developers

### Fixed
- **Patch patterns for v1.0.1307** - Updated fix_quick_entry_position.py and fix_tray_path.py to use flexible regex patterns (ce→de, pn→gn, pTe→lPe)

## 2025-11-25

### Added
- **Patch validation in CI pipeline** - Test build in Docker container before pushing to AUR
- **validate-patches.sh script** - Local validation tool for developers to test patches
- **Claude Code CLI integration** - Patch to detect and use system-installed `/usr/bin/claude`
- **AuthRequest stub** - Added AuthRequest class stub to claude-native.js for Linux authentication fallback
- **Native frame patch** - Use native window frames on Linux/XFCE while preserving Quick Entry transparency
- **Quick Entry position patch** - Spawn Quick Entry on the monitor where cursor is located
- **Tray DBus fix** - Prevent DBus race conditions with mutex guard and cleanup delay
- **Tray path fix** - Redirect tray icon path to package directory on Linux
- Isolated patch files in `patches/` directory for easier maintenance
- Local build script `scripts/build-local.sh` for development testing

### Changed
- **Patches now fail on pattern mismatch** - All Python patches exit with code 1 if patterns don't match
- **generate-pkgbuild.sh captures exit codes** - Build fails if any patch fails to apply
- Refactored all inline patches into separate files
- Refactored PKGBUILD generation to use template approach

### Fixed
- **Native frame patch** - Handle upstream code changes in v1.0.1217+ where main window no longer explicitly sets frame:false
- **Patch validation script** - Fixed handling of replace-type patches that create new files
- **CI pipeline** - Improved error handling with pipefail to catch build failures in piped commands
- Fixed tray icon loading - copy TrayIconTemplate PNG files to locales directory for Electron Tray API

### Removed
- Removed .SRCINFO from git tracking (auto-generated file)
- Removed PKGBUILD from repo (generated from template)

## 2025-11-24

### Changed
- Update to version 1.0.1217

## 2025-11-17

### Changed
- Update to version 1.0.734

## 2025-11-13

### Added
- Add GitHub repository link to PKGBUILD
- Add manual download URL input for workflow_dispatch

### Changed
- Update to version 1.0.332

## 2024-09-16

### Added
- Initial working package with patched claude-native module
- GitHub automation for AUR package maintenance
- Locale file loading patches for Linux compatibility
- Desktop entry and icon installation

### Fixed
- Title bar detection on Linux
- Tray icon functionality
- Notification support
