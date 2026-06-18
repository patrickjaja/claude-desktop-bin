# Changelog

All notable changes to claude-desktop-bin AUR package will be documented in this file.

## 2026-06-18 - v1.14271.0 bump (2 patches fixed) + new patch: suppress false VM-download banner on Linux native (#143)

### Upstream (v1.14271.0) - 2 patches fixed, all 52 apply

- **Version bump v1.13576.4 -> v1.14271.0** (~700 builds, full re-minify). Routine re-minify release for Linux: no new platform gates lock out a Linux feature, no new native modules, no new built-in MCP servers, and the Cowork RPC contract is unchanged in both directions. Two patches needed work for the re-minified bundle.
- **`fix_cowork_linux`: fixed C2's idempotency backreference.** The C2 "bundle lookup alias" fallback asserts upstream's hardcoded-win32 VM-bundle lookup (`(<var>=<map>.files["win32"])!=null&&<var>[arch]`) is present, but the deref var was hardcoded as literal `r`; re-minify renamed it `r` -> `i`, so the assertion stopped matching and C2 reported FAIL. Now captures the deref var and backreferences it so it tracks the rename.
- **`fix_browser_tools_linux`: rewrote 3 sub-patches for a real upstream refactor.** The Chrome native-host install path was restructured, not just renamed: the per-browser install loop is gone, and the manifest is now written to a single `userData/ChromeNativeHost` dir on all platforms (which Chrome/Chromium never read on Linux), while the per-browser enumerator became uninstall-only. The binary-path resolver and Chrome user-data-dir lookup likewise collapsed to flat win-only forms. Rewrote Patch A (binary path: inject Linux `~/.claude/chrome/chrome-native-host` short-circuit), Patch B (reuse the manifest writer to install into all 6 real Linux `NativeMessagingHosts` dirs at the start of the installer), and Patch C (return the 5 Linux browser user-data dirs). This native-host area is structurally volatile - watch it on the next release.
- **No baseline-doc internals moved structurally** beyond the usual minified-name churn; flag/ion-dist/platform-gate baselines updated with the new function names, config-chunk hash, and gate counts (see below). `enable_local_agent_mode.nim` (all 25 sub-patches) and `fix_ion_dist_linux.nim` apply unchanged.

### New patch: suppress the false "Download a one-time package" agent-mode banner on Linux native

- **New `fix_cowork_download_status_linux.nim` (52 patches total): the Cowork "Get set up for agent mode - Download a one-time package" banner no longer appears on Linux in native backend mode.** Desktop decides the agent-mode VM-image download status locally (it stopped calling the daemon RPC for this in v1.7196.0) via `getDownloadStatus(){return ...?Downloading:p5()?Ready:NotDownloaded}`, where `p5()` looks for the `claudevm.bundle` VM image on disk. On Linux native there is no VM image (Cowork runs the `claude` CLI on the host via claude-cowork-service), so the check always reported `NotDownloaded` and the remote claude.ai UI rendered a misleading "you're not set up" banner - even though Cowork works (sessions spawn and turns complete behind the banner). The patch rewrites `getDownloadStatus` so Linux native returns the enum's `Ready`; the original expression is preserved byte-for-byte for win32/darwin **and Linux-KVM**, where the guest image genuinely must be downloaded. Gated on `process.platform==="linux"&&!globalThis.__coworkKvmMode` (the KVM flag the cowork mode preamble already sets), so it never suppresses a legitimate KVM download prompt. **Not 3p/enterprise-specific** - it applies to 1p and 3p alike; it was first noticed in a gateway `enterprise.json` setup but a plain 1p Linux native user hits the identical false banner. Anchored on the unique `getDownloadStatus(){return ...}` method with the enum var captured by backreference (verified to survive the v1.14271.0 re-minify: `xX/p5/eN` -> `Z5/Rz/mM`); idempotency asserts the patched end-state.

### Bug fix: CoworkSpaces `getRemoteSessionSpaces is not a function` on Linux

- **`fix_cowork_spaces.nim`: added 6 CoworkSpaces methods the renderer now invokes.** On startup the main process logged `TypeError: (intermediate value).getRemoteSessionSpaces is not a function` (twice) because the renderer's `CoworkSpaces` interface calls 24 methods but our injected Linux file-based service only registered 18 IPC handlers. Six were missing - `getRemoteSessionSpaces`, `setRemoteSessionSpace`, `removeRemoteSessionSpace`, `classifySessions`, `setAutoDescription`, `summarizeSpace` - so those invokes fell through to an unhandled stub and threw. Implemented all six to match the upstream native contract (return types are validated renderer-side): the three remote-session-space methods are real local CRUD backed by a separate `remote-session-spaces.json` (Map, `cse_`->`session_` id normalization, folder-preservation on empty re-set, 1000-entry LRU cap evicting oldest - mirroring upstream `Ajr=1e3`); `setAutoDescription` only updates `origin:"auto"` spaces (returns `null` otherwise); and `classifySessions`/`summarizeSpace` are safe stubs (`[]`/`null`, both valid per the renderer guards) since neither has an inference backend on Linux. Verified: patch applies on the clean v1.14271.0 bundle, `node --check` passes, and the injected remote-session logic passes a standalone assertion suite (normalization, folder preservation, boolean returns, LRU eviction).

### Forward-looking audit fixes (patches + CI hardening, verified against v1.13576.4)

A full audit of patches/docs/CI against the current bundle found the suite healthy (51/51 apply, Cowork contract intact in both native and KVM modes, no new Linux gaps). Four items were worth fixing, all low-risk:

- **`fix_quick_entry_ready_wayland`: fixed a latent runtime bug.** The replacement hardcoded a logger (`R.error`) that does not exist at the patched call site (the live logger is `S`); the patch applied cleanly and passed `node --check`, but a rejected ready-to-show promise would throw a ReferenceError in the very catch meant to swallow it. Now captures and reuses the upstream logger var + catch param so it survives re-minifies.
- **`fix_imagine_linux`: retargeted Patch C to the renamed flag.** The Visualize/Imagine CCD gate `2204227020` was renamed to `3516166472` upstream, so Patch C had silently become a no-op (its standalone uses, including the `read_widget_context` tool registration, were no longer forced ON). Retargeted to the new ID. Also rewrote the Patch B/C idempotency checks to assert the patched end-state and fail loudly if the flag disappears, instead of treating flag-absence as success.
- **`fix_native_frame_renderer`: converted to a regression guard.** Upstream upstreamed the fix (the main-window title-bar component now returns `null` natively), so the patch had been silently no-opping via an accidental guard. It now positively asserts the upstream null short-circuit and fails the build if a future release reintroduces the pointer-absorbing drag region.
- **CI: glibc floors are now enforced, not just logged.** The node-pty rebuild asserts the GLIBC_2.31 floor (Debian 11 / Ubuntu 22.04) and fails loudly instead of silently shipping an un-rebuilt binary when version detection fails; the aarch64 kwin-portal-bridge gained the same objdump-based GLIBC_2.39 gate the x86_64 binary already had.

Docs: added the missing `fix_open_in_editor_linux` row to the README patch table and corrected the obsolete `fix_native_frame_renderer` row; noted the `2204227020 -> 3516166472` rename and fixed contradictory version headers in `CLAUDE_FEATURE_FLAGS.md`. CLAUDE.md gained a strictness rule forbidding false-success reporting - an "already patched" line must assert the patched end-state, never the mere absence of the pre-patch pattern.

### Docs: third-party inference (`enterprise.json`) expanded

- **`docs/third-party-inference.md`: added a 5-minute LiteLLM gateway quickstart and a feature-complete "maximum `enterprise.json`" reference.** The quickstart stands up a local LiteLLM proxy (Anthropic passthrough, secrets via env) and points Claude Desktop at it with one JSON file. The maximum example documents every managed-config key (enumerated from the v1.14271.0 schema) - surfaces, MCP/plugins, sandbox/egress governance, telemetry, usage limits - plus a per-provider "minimum required keys" table.
- **Surface toggles documented (`scopes:["3p"]`): `chatTabEnabled`, `coworkTabEnabled`, `isClaudeCodeForDesktopEnabled`, `betaFeaturesEnabled`.** These bring the Chat / Cowork / Code tabs back in 3P/gateway mode. README and the static site (`site/index.html`) gained matching coverage; README also embeds a Gateway-mode screenshot and links the official Anthropic 3P config docs. No app screenshots on the public static site (copyright) - it uses a copy-paste config block instead.

### Upstream (v1.13576.4) - build bump, no patch work

- **Version bump v1.13576.1 -> v1.13576.4** (patch-level rebuild of build 13576, hash `414f858c`). Re-minify only; bundle functionally identical.
- **All 52 patches apply unchanged.** Package built cleanly; `node --check` passes. The lone validator "FAIL" (`fix_ion_dist_linux`) is a manual-extract artifact - ion-dist lives in the MSIX resources, not `app.asar`; the patch applies fine against the extracted SPA.
- **No semantic changes vs v1.13576.1:** platform-conditional counts (linux 10, darwin 77, win32 +1 vendored path helper), Agent SDK copies (0.3.174 / 0.3.177), built-in MCP servers (1), and all fragile anchors are unchanged - the diff is pure minified-identifier churn.
- **No baseline-doc changes.** Bumped `.upstream-version` -> 1.13576.4.

### Built-in terminal fixed (re: #143)

- **New `fix_terminal_shell_linux.nim` (51 patches total): the built-in agent/Cowork terminal now spawns a Linux shell instead of PowerShell.** Upstream hardcodes the node-pty shell to `powershell.exe` on every platform, so on Linux `execvp(3)` fails and the PTY dies instantly ("Shell exited." / exit code 1). The patch rewrites only the shell string into a platform-aware ternary, anchored on the sole `shell:"powershell.exe"` occurrence. Thanks to **Yannick Schäfer ([@boommasterxd](https://github.com/boommasterxd))** for the fix ([#144](https://github.com/patrickjaja/claude-desktop-bin/pull/144)).
- **Off-Windows shell selection falls back `$SHELL` → `/bin/bash` → `/bin/sh`.** The `/bin/sh` tier was added on top of the PR for **NixOS** (Nix flake target), which ships no `/bin/bash` by default; a runtime `require("fs").existsSync` check keeps the PTY from going dead when `$SHELL` is unset.

## 2026-06-17 (v1.13576.0 / v1.13576.1) - Major version bump: 7 patches fixed, 1 removed, 1 added (50 total), all apply

### Cowork startup-error visibility (re: #142)

- **`fix_cowork_error_message` gained Patch C: replay the stored Cowork startup error once the mainView is ready.** When the Cowork VM startup fails before the web view exists (e.g. `claude-cowork-service` is not running on Linux), the upstream dispatcher stored the error in a module var but only logged `Cannot dispatch startup error (no mainView): <err>` and never replayed it - so the helpful "install claude-cowork-service" message (Patch A/B) never reached the UI, and the uncaught throw crash-looped the app (or bounced the renderer back to the start screen on chat-open). Confirmed in `cowork_vm_node.log` (`[VM:start] VM boot failed: ...` + `Cannot dispatch startup error (no mainView): ...`). Patch C rewrites the no-mainView branch to install a one-shot poller (Linux only, ~30s budget, `globalThis.__cdbStartupErrReplay` guard) that waits for the view's webContents to finish loading, then re-dispatches the stored error through the same dispatcher. Anchored on the unique `Cannot dispatch startup error (no mainView): ` literal; all minified identifiers captured from the match. `EXPECTED_PATCHES` 2 -> 3.

### Launcher `log: command not found` (re: #142)

- **Moved the `log()` definition (and its `LOG_DIR`/`LOG_FILE` setup + rotation block) to the top of `claude-desktop-launcher.sh`, right after `APP_ID`.** `log()` was defined at the bottom (~line 1131), but `_appimage_integrate()` calls it and runs much earlier during startup (`_appimage_integrate quiet || true`, ~line 948). Bash resolves a called function's name at call time, so the early invocation printed `claude-desktop: line 498: log: command not found` to stderr on every AppImage launch (the line-498 call is the "system `.desktop` exists - skipping" branch). Cosmetic only - the `|| true` swallowed the failure and integration still succeeded, but the integrate log line was silently dropped and the stderr noise was alarming. Surfaced in #142's startup output (reproduces on every machine running the AppImage, independent of the Cowork issue in the same report). Pure reordering; behavior otherwise unchanged. Verified with `bash -n`.

### Enterprise config visibility

- **`fix_enterprise_config_linux` now promotes the upstream "Enterprise config loaded" log from `debug` to `info`** so a successful, non-empty managed-config load is visible in `main.log` at the default log level (previously the only signal was a `debug` line below the default threshold, plus upstream's own `managedMcpServers entry N dropped - <reason>` validation warnings). Only the *loaded* variant is promoted (second arg is a redact-fn call); the empty/"none" case stays at `debug` so launches without `/etc/claude-desktop/enterprise.json` don't spam `info`. Applied to both `index.js` and `index.pre.js`; idempotent. The Linux reader injection itself is unchanged.
- **Clarified the `enterprise.json` schema for users (re: #140):** the top-level key the v1.13576 build reads is **`managedMcpServers`** - an **array** of objects each requiring `name` (unique), `transport` (`"http"`/`"sse"`/`"stdio"`), and `url`/`command`. A top-level object-keyed `mcpServers` map (or per-entry `type` instead of `transport`) is silently ignored by the schema parser - no entries reach the per-entry validator, so no "dropped" warning is emitted. Managed servers apply unconditionally (no `allowManagedMcpServers` enable-gate; `allowManagedMcpServersOnly` only restricts the allowlist to managed-only).

### Upstream (v1.13576.1) - build bump, no patch work

- **Version bump v1.13576.0 -> v1.13576.1 (patch-level rebuild of the same major build 13576).** Upstream `.latest` reports `1.13576.1` (hash `772d01ffc175c3795a49154acdecf043d634b5d1`). Bundle re-minified but functionally identical: unpatched `index.js` 15.12 MB, vendored `@anthropic-ai/claude-agent-sdk` copies unchanged at **0.3.174 / 0.3.177** (still two copies). Unpatched platform-conditional counts: darwin 77, win32 137, linux 10 - consistent with v1.13576.0.
- **All 50 patches apply unchanged; 51/51 validate** (`validate-patches.sh`), `node --check` passes on both `index.js` and `index.pre.js`. No regex updates needed.
- **Documented fragile anchors re-verified, all match v1.13576.0:** enterprise wrapper `function Mei(){const A=Rei();...}` (readPlistValue refs still 1), Cowork `yukonSilver:Zce()`, tray-icon `switch(...){case"ico":...}` (build-time const renamed `G1r`->`GJr`, absorbed by the flexible pattern), feature-flag fn present.
- **No baseline-doc changes:** feature flags, built-in MCP servers (1 `registerInternalMcpServer`), ion-dist patterns, and platform gates all unchanged. `.electron-version` stays 42.0.0 (shasums verified OK). Package built as `claude-desktop-bin-1.13576.1-1-x86_64.pkg.tar.zst`.

### CI

- **`version-check.yml` now tracks handled versions via a committed `.upstream-version` file** (mirrors claude-cowork-service) instead of the highest GitHub release tag. Bump + commit `.upstream-version` once a version is handled - even a trivial build bump with no public release - to silence the "new version detected" issue and turn the badge green. Seeded the file at `1.13576.1`.

### Upstream (v1.13576.0)

- **Version bump v1.12603.1 -> v1.13576.0 (~970 builds, full re-minify).** Bundle 15.03 -> 15.12 MB (+0.6%). Vendored `@anthropic-ai/claude-agent-sdk` copies bumped 0.3.170/0.3.167 -> **0.3.174/0.3.177** (still two copies - the duplicated-SDK match-site hazard still applies). Package built as `claude-desktop-bin-1.13576.0-1-x86_64.pkg.tar.zst`; `node --check` passes on the patched bundle.
- **8 patches failed on first build; the failures were upstream refactors, not just renames.** 7 fixed, 1 removed -> **50 -> 49 patches**, all apply.
- **Several macOS/Windows-only platform gates were DROPPED upstream (Linux now covered natively):**
  - **Dispatch platform label:** the `switch(process.platform){...default:return"Unsupported Platform"}` label fn became a ternary `process.platform==="darwin"?"macOS":process.platform==="win32"?"Windows":"Linux"` - Linux is now labelled correctly upstream.
  - **Dispatch telemetry gate:** the `cn=darwin,zo=win32,cAA=cn||zo` triple + `if(!cAA)return;` early-returns are gone; telemetry now runs unconditionally (gated only on `disableNonessentialTelemetry`), so Linux gets dispatch telemetry without a patch.
  - **Office-addin connected-file detection:** `(darwin||win32)&&await FN(e.app,e.document)` lost its platform gate (now `if(await FN(e.app,e.document))`) - the feature is gated only on the `louderPenguinEnabled` flag (which `enable_local_agent_mode` already forces). The whole `fix_office_addin_linux.nim` patch is now **obsolete and removed**.
  - **setTitleBarOverlay theme-update gate:** the win32-only `zo&&...getAllWindows().forEach(...)` guard was removed; the call is unconditional, so the integrated titlebar already receives theme updates on Linux.
- **Enterprise managed-config loader collapsed:** the `process.platform==="darwin"?macReader():process.platform==="win32"?winReader():{}` ternary became a single wrapper `function Mei(){const A=Rei();return Object.keys(A).length>0?A:void 0}` that unconditionally calls the win32 registry reader (mac plist reader removed; `readPlistValue` refs 3 -> 1). `fix_enterprise_config_linux` rebased to inject the Linux `/etc/claude-desktop/enterprise.json` branch into that wrapper (both `index.js` and `index.pre.js`).
- **Cowork (yukonSilver) support gate refactored:** static registry now wires `yukonSilver:Zce()`, where `Zce()` delegates to `Q3i()`/`C3i()` and `C3i()` **hardcodes `const A="win32"`** for the VM-bundle arch lookup (`fo.files["win32"][arch]`) - the explicit `process.platform!=="darwin"&&!=="win32"` Cowork gate is gone. `enable_local_agent_mode` Patch 1b rebased to inject the Linux early-return into `Zce()`; `fix_cowork_linux` Patch A (VM client loader) and Patch C2 (bundle lookup alias) rebased (see below).
- **Tray icon selection refactored:** the win32 `isWin?e=...:e="TrayIconTemplate.png"` ternary became `switch(G1r){case"ico":...case"template-image":...case"png":...}` keyed on a build-time icon-type constant (`G1r="ico"` on Windows builds). `fix_tray_icon_theme` now injects a Linux override after the switch (`process.platform==="linux"&&(e="TrayIconTemplate-Dark.png")`).
- **Sensitive-dirs array** gained two new intervening arrays (`["Scheduled","Artifacts"]`, scheduled-tasks/agents/...) between the win32 block and the old `.zshrc` anchor; `fix_sensitive_dirs_linux` re-anchored on the stable `"PowerShell")]:[]` win32 close.

### Patches fixed (7) + removed (1)

- **`fix_tray_icon_theme`** - rewrote for the new `switch(G1r)` icon selector; injects a post-switch Linux override (forces `TrayIconTemplate-Dark.png`, since the win32 `.ico` files the `"ico"` build-type picks don't ship on Linux). **Note:** trailing `;` on the injected expression is required - it's followed immediately by `const t=...` with no line terminator (ASI does not apply in minified code).
- **`fix_sensitive_dirs_linux`** - re-anchored on `"PowerShell")]:[]` (win32-array close) instead of the now-displaced `.zshrc` next-var.
- **`fix_enterprise_config_linux`** - rebased onto the new `Mei()`/`Rei()` wrapper (captures the registry-reader fn from its `SOFTWARE\Policies` body); applies to `index.js` and `index.pre.js`.
- **`fix_native_frame`** - Patch 2 (setTitleBarOverlay gate) now detects the upstreamed unconditional call and skips without failing; Patches 1 + 3 unchanged.
- **`fix_dispatch_linux`** - Patch C (platform label) and Patch D (telemetry gate) detect their upstreamed forms (ternary returning `"Linux"`; telemetry no longer platform-gated) and skip without failing; A/B/E unchanged.
- **`enable_local_agent_mode`** - Patch 1b (yukonSilver) rebased to inject the Linux early-return into the new `Zce()` delegate-chain (`const A=Q3i();...const e=C3i();if(e.status!=="supported")return AW(e)`), keeping the historical `process.platform` forms as fallbacks. All 25 sub-patches apply.
- **`fix_cowork_linux`** - Patch A (VM client loader) rebased: the old win32 ternary `zo?IM={vm:X}:IM=(await import("@ant/claude-swift"))` became `function d_t(){return tu()?...{vm:qti}...:null}` gated on `tu()` (MSIX/appPath install detection); we widen the gate to `(tu()||process.platform==="linux")`. Patch C2 (bundle lookup alias) detects that the platform-indexed `Io.files[process.platform]` lookup is gone - the only remaining lookup hardcodes `"win32"` (`C3i`), which already gives Linux the win32 bundle, so the linux->win32 alias is now upstream's default; it skips without failing. All 10 sub-patches apply.
- **`fix_office_addin_linux`** - **REMOVED** (obsolete; the connected-file-detection platform gate it widened was dropped upstream - the feature now runs on all platforms gated only on `louderPenguinEnabled`).

### Audits (re-validated against the new bundle)

- **Feature flags:** static registry **37 -> 39** (added `iosSimulatorH264`, `quickEntryGlobalShortcut`; removed none) + 5 async-only (`louderPenguin`/`coworkKappa`/`coworkArtifacts`/`markTaskComplete`/`epitaxyMcpApps`). Function renames: registry `aD()`->`sR()`, async merger `fSA`->`c0A`, prod dev-gate `vR()`->`rM()`, GrowthBook bool reader `dt()`->`Ct()`; electron var `lA` unchanged. **GrowthBook delta vs v1.12603.0:** +3 (`1703762832` onModelRefusalFallback retry [already present in v1.12603.1], `1985784543` an isEnabled gate, `3646818354` shouldKillOnIdlePause), 0 removed. `enable_local_agent_mode` 12-flag override list unchanged - none of the new flags is darwin/win32-gated.
- **Built-in MCP servers:** internal roster unchanged; `registerInternalMcpServer` present. Bundled Microsoft 365 server (`resources/office365-mcp/`) still ships.
- **Platform gates:** darwin 79 -> 77 / win32 141 -> 137 / linux 9 -> 10. The net drop is the upstreamed gates above (dispatch label/telemetry, office-addin, setTitleBarOverlay) collapsing explicit `process.platform` checks. **No new PORTABLE (Linux-compat) opportunity.**
- **ion-dist SPA:** 94 -> 95 MB, 730 JS (unchanged), config chunk `c71860c77-upcFhKtF.js` -> `c71860c77-DXc_sfB9.js`; both `fix_ion_dist_linux.nim` sub-patterns still match (`mountPath` still mac/win-only, platform ternary `_===M.Win32?...win:...mac`). New 3P config keys: Vertex `inferenceVertexProjectId`/`inferenceVertexRegion`/`inferenceVertexWorkforceOidc`/`inferenceVertexWorkforceUserProject`, Gateway `inferenceGatewayBaseUrl`/`inferenceGatewayHeaders`.

### New patch (1)

- **`fix_builtin_mcp_browser_env` - built-in MCP connectors couldn't open a browser for OAuth on Linux ([#139](https://github.com/patrickjaja/claude-desktop-bin/issues/139)).** The Microsoft 365 connector's local sign-in failed with `local_auth_browser_open_failed` / `spawnErrorCode: exit_3` and no browser appeared. Root cause: the built-in MCP host is forked via `utilityProcess.fork` with a **filtered env allowlist** (`vre()`), which on Linux forwards only `["HOME","LOGNAME","PATH","SHELL","TERM","USER"]` - stripping `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_CURRENT_DESKTOP`, `DBUS_SESSION_BUS_ADDRESS`, `BROWSER`, `XDG_DATA_DIRS`, etc. The bundled `office365-mcp.mjs` opens the auth URL with `spawn("xdg-open",[url])` and passes no `env`, so it inherits the stripped environment; `xdg-open`'s `has_display()` is then false, it skips the `x-scheme-handler/https` default-browser resolution, falls through to the text-only browser list, finds none, and exits 3 (`exit_failure_operation_impossible`). The patch widens the Linux allowlist to forward the standard freedesktop / X11 / Wayland session vars, so `xdg-open` inside the MCP process launches the user's default browser exactly as it does from a terminal. Distro- and session-agnostic (only standard env vars; `vre()` forwards each only when set). The win32 branch of the allowlist is untouched. `vre()` is the base env for all stdio MCP server forks (the built-in host plus user-configured stdio servers via `jMt`/`StdioClientTransport`), so the wider session env reaches every one of them - strictly more correct, since it only adds standard vars a terminal-launched process already has. The other `utilityProcess.fork` sites (which pass `{...process.env}`) are unaffected.

### Runtime fix

- **`getSystemInfo` crash on Linux:** v1.13576.0 dropped the `win32`-only guard around the `getWindowsElevationType()` call in `getSystemInfo` (and the `desktop_windows_elevation_detected` telemetry), so it's now invoked on every platform. Our Linux `@ant/claude-native` stub lacked the method -> `TypeError: i.getWindowsElevationType is not a function`, spamming on every Settings/feedback system-info request. Added `getWindowsElevationType: () => "default"` to the stub (`patches/claude-native.js`) - `"default"` is the non-elevated state, matching both call sites' `?? null` / `?? "default"` fallbacks (`can_elevate_to_admin` -> `false` on Linux). Other native methods that lost guards this release (`cuGetOwnBundleId`, `getActiveWindowHandle`) are still safe (darwin-only path / wrapped in try-catch).
- **Remote MCP servers fail with `ERR_MODULE_NOT_FOUND` (issue #140):** connecting a direct/remote MCP server (e.g. atlassian via enterprise.json) crashed the `custom3p-mcp host` utility process immediately - it tried to load `directMcpHost.js` from `resources/locales/app.asar/.vite/build/mcp-runtime/directMcpHost.js`, which does not exist. Root cause: two sidecar loaders build their path as `join(process.resourcesPath,"app.asar",...)`, and `fix_locale_paths` blanket-rewrites every `process.resourcesPath` to `dirname(getAppPath())+"/locales"` - injecting a spurious `locales/` segment before `app.asar`. `fix_0_node_host` already collapsed the same `isPackaged` ternary for nodeHost.js and shellPathWorker.js to `app.getAppPath()`; extended it to also cover the directMcpHost loader (`ohi()`) and the generic worker loader (`l7i()`, used for transcript-search-worker, which had the same latent bug). All four sub-patches now use `[\w$]+` wildcards, capture-group backreferences, and idempotency markers (`fix_0_node_host` is now fully re-run-safe). On Linux the package is always "packaged" and `getAppPath()` already resolves to the real app.asar, so the packaged and non-packaged branches are equivalent.

### Build tooling

- **`build-local.sh` rebuild checksum fix:** the local `claude-desktop-*.tar.gz` is a build artifact regenerated every run (bytes/sha change each build), but makepkg cached it in `cache/` under its download name and re-validated the **stale** cached copy against the freshly-generated `sha256sums` -> `One or more files did not pass the validity check`. The script now purges any cached `claude-desktop-*-linux.tar.gz` before makepkg so it re-copies the fresh artifact; the upstream **electron zip stays cached** (checksummed, reused across builds). Removed the dead `cp` that copied the tarball under a basename makepkg never looked up.
- **CI `test-pkgbuild` Electron-verify fix:** the job sourced `scripts/verify-electron.sh` (added with the shasum checks) but had no `actions/checkout` step, so the script and `.electron-shasums` were absent at runtime -> `scripts/verify-electron.sh: No such file or directory`. Added a checkout step to the job; artifact downloads and the makepkg step are unaffected.

### Docs updated

- `CHANGELOG.md` (this entry), `baseline/CLAUDE_FEATURE_FLAGS.md`, `baseline/CLAUDE_BUILT_IN_MCP.md`, `baseline/ION.md`, `baseline/PLATFORM_GATE_BASELINE.md` refreshed to v1.13576.0. `README.md` patch table - removed `fix_office_addin_linux` row, added `fix_builtin_mcp_browser_env` row, count 50 (50 -> 49 -> 50).

### Security (community audit #137)

- **Electron zip now SHA-256 verified everywhere (was `SKIP`).** Added `.electron-shasums` (per-arch official digests from Electron's `SHASUMS256.txt`, pinned to `.electron-version`), a `scripts/update-electron-shasums.sh` generator/`--check`er, and a sourceable `scripts/verify-electron.sh` (`verify_electron_zip`). Wired into `build-deb.sh`, `build-rpm.sh`, `build-appimage.sh`, the `test-pkgbuild` cache step, and the PKGBUILD (`PKGBUILD.template` + `generate-pkgbuild.sh` now emit real digests so makepkg verifies natively). `lint-scripts` fails the build if `.electron-shasums` drifts from the pinned version. Nix is unaffected (uses nixpkgs Electron). Verified: makepkg reports `electron-...zip ... Passed` on a good build and `FAILED` on a wrong digest.
- **GPG repo signing-key fingerprint published** in `README.md` (`825A 7D15 D78B ABE4 5646  D5DF 3824 09F5 9790 8867`, RSA 4096) so users can verify the APT/DNF key out-of-band.
- **`packaging/apt/install.sh` GPG key hardening:** download the key to a temp file and validate it parses (`gpg --show-keys`) before writing the system keyring, instead of piping `curl` straight into `gpg --dearmor` (guards against a truncated/corrupt download leaving a broken keyring).
- **Documented as non-issues** (in the issue thread): msix integrity rests on TLS - the `.latest` endpoint `hash` is an opaque release ID, not a content digest (no upstream signature to verify); the ydotool `0666` socket lives in user-private `/run/user/$UID` (0700); the Computer-Use TCC/sandbox-ref patches don't weaken a real boundary (macOS-only TCC; Linux genuinely has no VM); the manual CI `download_url` is admin-gated.

## 2026-06-12 (v1.12603.1) - Point release, all 50 patches apply unchanged

### Upstream (v1.12603.1)

- **Point release on v1.12603.0** (+446 bytes, full re-minify of essentially the same code). All 50 patches applied without modification.
- **Static registry renamed:** `sD()` -> `aD()`. All other function names unchanged (`fSA` merger, `vR()` dev-gate, `dt()` flag reader). `[\w$]+` wildcards in patches absorbed the rename.
- **New GrowthBook flag `1703762832`:** gates `onModelRefusalFallback` retry behavior in `AgentModeSessionManager` - when ON, a refusal with `direction:"retry"` triggers a fallback. No platform gate; Linux unaffected.
- **ion-dist config chunk renamed:** `c71860c77-C2vlLTGm.js` -> `c71860c77-upcFhKtF.js` (~307 KB, was ~313 KB). Both `fix_ion_dist_linux.nim` sub-patterns (mountPath mac/win keys, platform ternary) still match. No structural change; file count 730 JS / 978 total (unchanged).
- **Platform gates:** darwin 79 / win32 141 / linux 9 - all identical to v1.12603.0. Zero new gates, zero new PORTABLE opportunities.
- `enable_local_agent_mode.nim` 12-flag override list unchanged; no new darwin/win32-gated features.

### Docs updated

- `baseline/CLAUDE_FEATURE_FLAGS.md` - added v1.12603.1 version history row + new flag `1703762832` catalog entry.
- `baseline/ION.md` - updated last-verified version, config chunk filename, file count.
- `baseline/PLATFORM_GATE_BASELINE.md` - bumped last-audited version and baseline counts.

## 2026-06-11 (v1.12603.0) - Version bump, all 50 patches apply unchanged

### Upstream (v1.12603.0)

- **Version bump:** v1.11847.5 -> v1.12603.0 (~760 builds). Full re-minify - every minified identifier shifted - but zero structural changes hit our patch targets: **all 50 patches applied without modification** (their `[\w$]+` wildcards absorbed the renames). Package built as `claude-desktop-bin-1.12603.0-1-x86_64.pkg.tar.zst`; `node --check` passed on the patched JS (38 `[claude-cu]` markers present).
- **Bundle grew 13.6 -> 15.0 MB (+11%):** the entire growth is a **second vendored copy of `@anthropic-ai/claude-agent-sdk`** (0.3.167 embedded alongside 0.3.170), bringing a ~290-entry `CLAUDE_CODE_*`/`DISABLE_*` env-flag registry module. **Patch-maintenance hazard:** any future patch matching SDK-internal code now has TWO match sites - "exactly 1 match" assertions against SDK code will fail or silently patch only one copy (note added to update-prompt.md).
- **Microsoft 365 MCP server now ships:** `resources/office365-mcp/` (office365-mcp.mjs 6.5 MB + pdfExtractorProcess.mjs + pdf.worker.mjs) is new inside app.asar - the loader existed in v1.11847.5 but the bundle was missing ("not included in this build"). Graph-based Outlook/OneDrive/SharePoint/Teams tools, MSAL auth with encrypted `msal-cache.enc` via `safeStorage`, GovCloud environments, write scopes withheld on public builds (`MCP_GRANTED_DELEGATED_SCOPES`). **No platform gate - works on Linux**; resolved via `app.getAppPath()`, preserved by our repackaging (verified present in the built asar). Worth a runtime smoke test (`safeStorage` without a keyring).
- **New upstream features:** `artifactsPane` feature (new GrowthBook flag `2115990222`, no platform gate - new `claudePagePreview.js` preload embedding claude.ai pages in the preview pane); `device_request_folder_access` remote-device tool with "Always allow this folder on this device" prompts (flag `2745857735`); `oauthScope` passthrough into CLI session env (flag `884132720`); VM optional mounts (value flag `3932491586`, force-OFF upstream). Two new IPC handlers: `ClaudeCode.getPeriodUsage` (CLI usage probe) and `Launch.exportPreview`. Removed: cowork git-init no longer creates an empty initial commit.

### Audits (re-validated against the new bundle)

- **Feature flags:** registry now 37 static + `louderPenguin` async-only = 38 (added `artifactsPane`, removed none). `artifactsPane` is now the FIRST registry key - future `nativeQuickEntry`-anchored searches must re-anchor. `builtinMcpPresets` lost its dev-gate wrapper (now unconditionally supported - upstreamed to all platforms incl. Linux). 4 GrowthBook flags added, 0 removed; new `LC(id,default)` value-with-default reader. Renames: registry `Rw()`->`sD()`, merger `PBA`->`fSA`, prod gate `OS()`->`vR()`, flag reader `lt()`->`dt()`. **`enable_local_agent_mode.nim` needs no changes** - none of the new flags is darwin/win32-gated.
- **Built-in MCP servers:** internal roster unchanged; registration fn `KqA()`->`iAe()`, registry `CT`->`YL`, labels `TUA`->`jVA`, enumerator `J3()`->`s9()`; server-UUID map byte-identical. New doc section for the bundled Microsoft 365 server.
- **Platform gates:** darwin 73->79 / win32 122->141 / linux 5->9 - the entire swing is the duplicated vendored CLI/SDK helper code (which/cross-spawn/isexe/WSL-detect/signal-list duplicates), verified via stable-string counts. Zero new Electron-side platform gates. **No new PORTABLE (Linux-compat) opportunity.**
- **ion-dist SPA:** modest growth (93->94 MB, 715->730 JS, 23->25 CSS); config chunk `c71860c77-BBQ3iytl.js`->`c71860c77-C2vlLTGm.js`; both `fix_ion_dist_linux.nim` sub-patterns still match (`mountPath` still mac/win-only); ternary vars `V`/`E`/`xt`. New Vertex config key `inferenceVertexOAuthLoginHint`. NFC path normalization now darwin-gated upstream (was unconditional - Linux-friendly, no patch impact).
- **claude-cowork-service cross-check:** wire protocol unchanged except Desktop's `spawn` now optionally reads a `failedMounts` array from the response (absent-tolerant - the Go daemon keeps working as-is). Optional follow-ups for that repo: implement `failedMounts` (mount-failure telemetry/UI demotion) and document the pre-existing `pruneSessionCaches` RPC (VMDiskJanitor calls it in both versions; unknown-method null-passthrough covers it).

### Docs updated

- `baseline/CLAUDE_FEATURE_FLAGS.md`, `baseline/CLAUDE_BUILT_IN_MCP.md`, `baseline/ION.md`, `baseline/PLATFORM_GATE_BASELINE.md` - all refreshed to v1.12603.0. `update-prompt.md` - added duplicated-SDK match-site warning. README patch table unchanged (no patch changes).

## 2026-06-10 (v1.11847.5-2) - 2 new patches: Linux memory-pressure metric + suppressed renderer-death logging (#128) + launcher log rotation (#132)

### Issue

- [#128](https://github.com/patrickjaja/claude-desktop-bin/issues/128): `[CliGovernor] memory pressure (critical)` log spam on Linux plus silent renderer "eviction" forcing a claude.ai re-login. Root cause of the spam: Electron's `process.getSystemMemoryInfo().free` is `MemFree` on Linux, which excludes reclaimable page cache. A healthy 32 GB box measured MemFree/MemTotal = 5.3% while MemAvailable/MemTotal = 61.8%, so the governor (warning <5%, critical <2%, 10s poll, `M$r=.05`/`N$r=.02` in v1.11847.5) fires constantly on perfectly healthy systems. The pressure events only log + send telemetry - they never touch the renderer. Separately, the main webview's `render-process-gone` handler early-returns with no log when the reason is `killed`/`clean-exit` or an expected kill is pending - a kernel OOM SIGKILL maps to `killed`, so the renderer death that precedes the re-login was invisible in main.log (the reporter's "no render-process-gone events" proved nothing).

### New patches (2)

- **`fix_cli_governor_memavailable.nim`** - rewrites `getFreeMemoryRatio` to read `MemAvailable`/`MemTotal` from `/proc/meminfo` (clamped with `Math.min(1, ...)`), re-emitting the captured upstream expression verbatim as the fallback if the `/proc` read throws. `require("fs")` is cached by Node's module loader, so the 10s poll costs one ~1.5 KB procfs read. Idempotency marker: `/proc/meminfo` within 200 chars of `getFreeMemoryRatio:`. macOS is unaffected (native pressure events bypass the polling path). Upstream's own MCP timeout diagnostics already compensate with `free + fileBacked` elsewhere - the governor just never got the fix.
- **`fix_renderer_gone_suppressed_log.nim`** - inserts `D.info("Main webview render process gone (suppressed): %o",{reason,exitCode,expectedKills})` inside the early-return branch of the main-webview `render-process-gone` handler, before the counter decrement (`expectedKills > 0` = app-initiated kill via the unresponsive handler; `0` with reason `killed` = external kill, e.g. kernel OOM). All identifiers captured via `[\w$]+` groups; the trailing `"Main webview render process gone: %o"` literal pins the one correct site out of 8 `render-process-gone` registrations. Pure observability - suppression behavior (no reload) unchanged.

### Tooling

- **`scripts/validate-patches.sh`** - added a `nim-dir` branch (copy directory to a temp dir, run the binary on it) and a directory-aware existence check. Previously `fix_ion_dist_linux.nim` always failed standalone validation with "target file not found" because the script `-f`-tested its directory target; suite is now 51/51.

### Not addressed (still open in #128)

- `preferencesChanged` MaxListeners warning - upstream claude.ai web-app bug (the shipped preload's `onPreferencesChanged` correctly returns an unsubscribe closure; the remote web app re-subscribes without cleanup). Trivial magnitude (~KBs per page session); masking it would hide real regressions.
- The re-login mechanism itself - the claude.ai view runs on persistent `session.defaultSession` and the recovery path is a plain `webContents.reload()`, so the web session should survive; needs incident-time evidence from the reporter (asks posted on the issue).

### Verification

- Patch count 48 -> 50; both new patches idempotent (second run exits 0 via marker detection); `node --check` passes on the patched JS; `./scripts/validate-patches.sh` 51/51 green; pure-JS text patches, identical on x86_64 and aarch64.

### Launcher log rotation (#132)

> **Credit:** boommasterxd (Yannick Schäfer) - triaged [#132](https://github.com/patrickjaja/claude-desktop-bin/issues/132) (located the reported awk hang in `aaddrick/claude-desktop-debian`, not this repo) and contributed the rotation fix ([#133](https://github.com/patrickjaja/claude-desktop-bin/pull/133)). Merged after the `-2` release - ships with the next release, not in the v1.11847.5-2 artifacts.

- **Issue:** [#132](https://github.com/patrickjaja/claude-desktop-bin/issues/132): Reported that `_previous_launch_hit_gpu_fatal` hangs the launcher on large log files via an O(n^2) awk scan of the whole `launcher.log` on every startup. **Investigation result:** that function, `setup_logging`, `build_electron_args` and the `~/.cache/claude-desktop-debian/` cache path do not exist anywhere in this repo - they belong to the separate `aaddrick/claude-desktop-debian` project. This launcher writes to `~/.cache/claude-desktop/launcher.log` and only ever reads it via `tail -10` for `--diagnostics`, so the reported O(n^2) hang cannot occur here. The one applicable half of the report - unbounded log growth - did apply: `log()` appended without any size cap.
- **Fix:** **`scripts/claude-desktop-launcher.sh`** - rotate `launcher.log` to `launcher.log.old` once it exceeds 2 MiB, checked once per startup before `log()` is defined. Every step is guarded (`stat` failure -> `0`, numeric regex guard, `mv` failure ignored) so the rotation can never itself prevent Claude from launching.
- **Post-merge fixup:** `_diagnose`'s "Recent launcher log" section now reads across the rotated backup (`cat launcher.log.old launcher.log 2>/dev/null | tail -10 || true`) so the last 10 lines survive a rotation that just happened at startup. The `|| true` is required under the launcher's `set -euo pipefail`: `cat` exits non-zero when one of the files is missing, which is the common state (no `.old` exists before the first rotation) and would otherwise abort `--diagnose` mid-output.

## 2026-06-09 (v1.11847.5) - Version bump, 1 patch fixed for refactored upstream code

> **Credit:** boommasterxd (Yannick Schäfer) independently produced the same update in parallel ([#130](https://github.com/patrickjaja/claude-desktop-bin/pull/130)), reaching identical findings (same `fix_claude_code` getStatus fix, same feature-flag/platform-gate/ion-dist results) and additionally verifying the RPM build on Fedora. The `mountPath` `caption`-key-drop note in `baseline/ION.md` is from his audit.

### Upstream (v1.11847.5)

- **Version bump:** v1.11187.4 -> v1.11847.5 (~660 builds). Full re-minify - every minified identifier shifted. One patch needed a regex update because upstream restructured the code (not just renamed variables); the other 47 patches absorbed the renames via their `[\w$]+` wildcards.

### Patches fixed (1)

- **`fix_claude_code.nim`** (Patch 3, `getStatus()`) - upstream added a second check to the first if-condition: `if(await this.getLocalBinaryPath())` became `if(await this.getLocalBinaryPath()||await this.getHostPreseedInPlacePath())`. The old regex required the bare `getLocalBinaryPath()` call immediately followed by `)return`. New regex captures the whole condition and tolerates an optional run of `||await this.<fn>()` clauses, then re-emits the original condition verbatim in the patched code so the `getHostPreseedInPlacePath()` check is preserved. Patches 1 and 2 (`getHostPlatform`, `getBinaryPathIfReady`) were unaffected.

### No other patch changes needed

- **All 48 patches apply** - package built as `claude-desktop-bin-1.11847.5-1-x86_64.pkg.tar.zst`; `node --check` passed on the patched JS.

### Audits (re-validated against the new bundle)

- **Feature flags:** 3 new static features (`coworkRemoteSessionSpaces`, `coworkBranchSession`, `epitaxyMcpApps`); async merger now 5-way; 8 new GrowthBook flag IDs, 1 removed. `enable_local_agent_mode.nim` needs no changes (`epitaxyMcpApps` intentionally left server-gated - experimental). Function renames: registry `Dw()`->`Rw()`, merger `SBA`->`PBA`, dev-gate `MS()`->`OS()`.
- **Built-in MCP servers:** roster unchanged (22 servers + 4 per-session SDK). Registration fn `uqA()`->`KqA()`, registry `sT`->`CT`, labels `cUA`->`TUA`, enumerator `b3()`->`J3()`.
- **Platform gates:** darwin 72->73 (re-minify noise, both NATIVE - macOS Handoff `setUserActivity` + memory-pressure governor which falls back to `setInterval` polling on Linux), win32/linux unchanged. **No new PORTABLE (Linux-compat) opportunity.**
- **ion-dist SPA:** modest growth (92->93 MB, 706->715 JS chunks); config chunk `c71860c77-CyMvMS7K.js`->`c71860c77-BBQ3iytl.js`. Both `fix_ion_dist_linux.nim` sub-patterns still match (`mountPath` still mac/win-only); no patch change needed.

### Docs updated

- `baseline/CLAUDE_FEATURE_FLAGS.md`, `baseline/CLAUDE_BUILT_IN_MCP.md`, `baseline/ION.md`, `baseline/PLATFORM_GATE_BASELINE.md` - new version-history rows + refreshed stats/counts/minified names.

## 2026-06-06 (v1.11187.4) - Version bump, 2 patches fixed for refactored upstream code

### Upstream (v1.11187.4)

- **Version bump:** v1.10628.2 -> v1.11187.4 (~560 builds). Full re-minify - every minified identifier shifted. Two patches needed regex updates because upstream restructured the code (not just renamed variables); the other 46 patches absorbed the renames via their `[\w$]+` wildcards.

### Patches fixed (2)

- **`fix_utility_process_kill.nim`** - upstream inserted a `r&&this.noteKillOnce(),` statement between `.kill()` and the `\`Killing utiltiy proccess again\`` log call. Old regex required `.kill();[\w$]+.info(\`Killing...` immediately adjacent. New regex tolerates a short run of intervening statements: group 3 is now `;[^\`]{0,80}\.info(\`Killing utiltiy proccess again`. Patched result: `n.kill("SIGKILL");r&&this.noteKillOnce(),D.info(...)`.
- **`fix_asar_folder_drop.nim`** (Patch B, second-instance argv parser) - the `.slice(1).filter(...)` was hoisted into a local var, so the loop changed from `for(const X of Y.slice(1))if(!Z(X))` to `for(const X of <var>)if(!Z(X))`. Rewrote the regex to drop the hardcoded `.slice(1)` and anchor on the trailing `"skill file"` arg for uniqueness (exactly one such loop in the bundle). Patch A (noe file-drop filter) was unaffected. Patched result: `for(const n of r)if(!/\.asar/.test(n)&&!VXr(n)){...`.

### No other patch changes needed

- **All 48 patches apply** - package built as `claude-desktop-bin-1.11187.4-1-x86_64.pkg.tar.zst`; `node --check` passed on the patched JS.

### Semantic verification (not just regex-match)

Traced the **raw unpatched** upstream code around every changed site and the 14 highest-stakes structural patches to confirm intent still holds after the re-minify (a matching regex alone doesn't prove the surrounding logic is unchanged):

- **`fix_utility_process_kill`** - the function has two `.kill()` calls (first SIGTERM via `const i=this.process.kill()`, 5s fallback via `const r=(n=this.process)==null?void 0:n.kill()`). Confirmed our regex matches **only the fallback** (distinct syntactic form), so the first kill stays graceful SIGTERM and only the timeout escalates to SIGKILL. The new `noteKillOnce()` is logging-only and is preserved. Semantics intact.
- **`fix_asar_folder_drop`** - upstream refactored `jXr()` and **added a new pre-filter** `A.slice(1).filter(n=>n.startsWith("-")||resolve(n)!==appPath)`. Verified this does NOT make our guard redundant: upstream only drops the single arg whose resolved path exactly equals `getAppPath()`, whereas our `!/\.asar/.test(n)` rejects any `.asar` path (covers symlinked/non-canonical paths and the case where `getAppPath()` returns the unpacked `app` dir). Our guard sits in the loop condition before the `existsSync(n)->e.push(n)->wQA(e)` dispatch, so a `.asar` arg never reaches the file-drop handler. Still correct defense-in-depth.
- **14 highest-stakes patches verified SOLID** against raw upstream: `enable_local_agent_mode` (25 sub-patches; merger override `{...Dw(),louderPenguin:A,...}` is authoritative), `fix_dispatch_linux`, `fix_cowork_linux` (10 sub-patches), `fix_computer_use_linux`, `fix_tray_dbus`, `fix_quick_entry_position`, `fix_native_frame`(+renderer), `fix_window_bounds`, `fix_locale_paths`, `fix_marketplace_linux`, `fix_startup_settings`, `fix_updater_state_linux`, `fix_vm_session_handlers`, `fix_sensitive_dirs_linux`. Every anchor lands in a semantically correct location.
- **Stale comment fixed:** `enable_local_agent_mode` Patch 1 comment claimed it ungates `chillingSlothFeat + quietPenguin`; in v1.11187.4 `chillingSlothFeat` moved to the non-platform `oW` gate, so only `quietPenguin` (`WEr`) matches here now. Behavior unchanged (Patch 1 already accepts `>=1` matches and Patch 3's merger force-overrides every feature regardless) - updated the comments + the 2-match log label to be version-agnostic.
- **Noted, not changed:** `fix_locale_paths` still does a global replace of all `process.resourcesPath` sites - a long-standing over-broad approach (not a v1.11187.4 regression); the affected non-locale paths are win32/darwin-gated and not exercised on Linux.

### Audit findings

- **Feature flags:** no `enable_local_agent_mode.nim` override changes needed (all 25 sub-patches still match; merger return `{...Dw(),louderPenguin:A,coworkKappa:e,coworkArtifacts:t,markTaskComplete:i}` intact). **1 new static feature** `coworkArtifactPopout:_d` (always supported, no platform gate, no override needed); `bootstrapConfig` changed from `MS()`-gated to bare `_d`. Function renames: registry `Aw()`->`Dw()`, async merger `LCA`->`SBA`, dev-gate `Dm()`->`MS()` (2nd gate `xEr()` for `builtinMcpPresets`), GrowthBook bool reader `It()`->`lt()`, supported constant `Xd`->`_d`, electron var `aA`->`sA`, `louderPenguin` async helper `Fsr()`->`XEr()` (still `darwin||win32` gate, now also reads flag `4116586025`), cowork helper `pRA()`->`mNA()`. **GrowthBook delta** (vs v1.9659.4 baseline, the only local prior bundle): 5 added (`124685897` template-subst, `1323782925` APe qualifier, `1609612026` marketplace install, `2720310975` side-chat tools, `790863764` device_bash), 1 removed (`3638165567`).
- **Built-in MCP:** **no servers added/removed** - identical roster (imagine/visualize/marketplace/skills/radar/echo/Framebuffer/Window Halo, etc.). Registration fn renamed `jHA`->`uqA` (registry obj `sT`, label map `cUA`, enumerator `b3()`). node-pty **1.1.0-beta34** unchanged.
- **Cowork protocol:** **unchanged** - `control_request` 14, `control_response` 46, `sessions-bridge` 3, `environments/bridge` 1, `work/poll` 1, all identical to baseline; 20 `CoworkArtifacts_$_*` IPC handlers byte-for-byte identical (the +8 raw `CoworkArtifacts` occurrences are new log strings, not protocol). **`claude-cowork-service` is NOT affected by this release.**
- **ion-dist (3P config SPA):** still required, applies cleanly. **92 MB / 706 JS / 950 files / 23 CSS** (up from 90 MB / 691 JS / 909 files / 21 CSS - modest growth, no structural refactor). Config chunk `c71860c77-CV0D52ti.js` -> **`c71860c77-CyMvMS7K.js`** (content-hash bump). `mountPath` **still mac/win-only** (no `linux` key, not upstreamed); platform ternary vars this release `K`/`C`/`pt`. Both sub-patterns matched; verified the compiled patch applies (exit 0, 2/2).
- **Platform gates:** darwin **65->72** (+7), win32 **113->122** (+9), linux **5** (unchanged). All new gates classify as NATIVE (path NFC normalization, updater channel msix/squirrel, dock bounce, Mission Control, TouchID, codesign verify, plist/registry reads, endpoint-security SIGKILL classification, dev-only `chrome://inspect` launcher) or STUB/config-gated (chat features gated by config flag, not `process.platform`). **No new PORTABLE (Linux-actionable) gate.** The `louderPenguin` Code-tab gate became async (`XEr()` + flag `4116586025`) but remains PATCHED via the existing override.

## 2026-06-04 (v1.10628.2) - Re-minify point release, all patches clean

### Upstream (v1.10628.2)

- **Version bump:** v1.10628.0 -> v1.10628.2 (webpack re-minify point release on top of v1.10628.0; v1.10628.1 was not observed on the public download channel). **No behavioral change vs v1.10628.0:** same feature-flag architecture, same patch surface, only fresh minified identifiers in a handful of spots.
- **All 48 patches applied without modification** - zero regex changes needed. The flexible `[\w$]+` patterns absorbed every minified rename. `node --check` passed on the patched JS; ion-dist patch matched both sub-patterns; `fix_tray_dbus.nim` this release: tray fn `Y5A`, tray var `VE`.
- **Feature flags unchanged:** still **32 static + `louderPenguin` async-only = 33 total**; identical static feature names (`claudeDesignWindow`/`builtinMcpPresets` both present, none removed); merger return identical (`{...Aw(),louderPenguin:e,coworkKappa:A,coworkArtifacts:t,markTaskComplete:i}` via `Promise.all([Fsr(),pRA(()=>It("123929380")),pRA(()=>It("2940196192")),pRA(()=>It("3732274605"))])`); both new features still in the Zod `.partial()` schema (`...builtinMcpPresets:Mo,surfaceTogglesPreview:Mo,chatTab:Mo,chatCodeExecution:...`).
- **Function names mostly held** (unusually light re-minify): registry `Aw()`, async merger `LCA`, dev-gate `Dm()` (`function Dm(e){return aA.app.isPackaged?{status:"unavailable"}:e()}`, electron var `aA`), `louderPenguin` async helper `Fsr()` (still `darwin||win32` gate), cowork async helper `pRA()`, GrowthBook bool reader `It()`, computer-use Set `MCA` (`new Set(["darwin","win32"])`, `MCA.has(process.platform)`), win32 var `ro`, darwin||win32 var `O$` - **all unchanged from v1.10628.0**. Renamed: supported constant `XQ`->`Xd` (`{status:"supported"}`); chatTab/chatCodeExecution gate fns `R6e`->`R5e` / `M6e`->`M5e`; cowork 5s-delay helper `u9e`->`u6e`; yukonSilver `WjA`->`W8A`; misc `zKA`->`z1A`, `$jA`->`$8A`; tray fn `Y6A`->`Y5A` (`fix_tray_dbus.nim`).
- **No structural changes:** file-level diff vs the installed v1.10628.0 shows only content-hashed renderer asset renames (about/buddy/find_in_page/main/quick) plus the expected patched-vs-raw artifacts (node-pty Linux spawn-helper, `resources/i18n/*.json` are added by the build, not upstream); **IPC `handle()` channel set identical** after normalizing the per-build UUID; **`require()` set identical**; built-in MCP roster unchanged (imagine/visualize/marketplace/skills/radar/echo/Framebuffer/Window Halo); **no cowork protocol changes** (`control_request`/`control_response` 8/7, `sessions-bridge` 3, `environments/bridge` 1, `work/poll` 1, `CoworkArtifacts` 5 - all unchanged); node-pty **1.1.0-beta34** unchanged.
- **GrowthBook:** 68 distinct boolean flag IDs in `It()` calls in the raw v1.10628.2 bundle; all documented key flags present and stable (`123929380`/`2940196192`/`3732274605` cowork, `4116586025` louderPenguin master, `2216414644` dispatch, `2688060585`/`3269331205` autoMode force-ON defaults). No clean prior-version MSIX is served upstream, so a literal old-vs-new flag diff is dominated by our own patch rewrites (`enable_local_agent_mode.nim`/`fix_dispatch_linux.nim` turn several `It("...")` calls into `!0`/`!1` in the installed build); structural flag continuity verified directly in the new bundle instead.
- **ion-dist (3P config SPA):** no structural change - **90 MB / 691 JS / 909 files / 21 CSS** (byte-for-byte counts identical to v1.10628.0). Config chunk `c71860c77-CDhE5jkR.js` -> **`c71860c77-CV0D52ti.js`** (content-hash bump only). `mountPath` **still mac/win-only** (no `linux` key) -> `fix_ion_dist_linux.nim` still required and both sub-patterns matched. Platform enum `Darwin="darwin",Win32="win32",Linux="linux"` intact; only 1 `/Library/Application Support` + 1 `%ProgramFiles%` path (both inside mountPath).
- **Platform gates:** darwin **65**, win32 **113**, linux **5** - **exactly identical to v1.10628.0** (zero swing). The three "not-mac-not-win -> unavailable" gates (`Fsr()` louderPenguin, `Lsr()` quietPenguin inner, `ksr()` cowork architecture check) all map to existing PATCHED rows. **No new PORTABLE (Linux-actionable) gate.**
- **`enable_local_agent_mode.nim` 12-flag override list unchanged** - build applied the patch without modification (12 features overridden, coworkKappa/coworkArtifacts/markTaskComplete/chillingSlothPool flags forced ON).

### No patch changes needed

## 2026-06-03 (v1.10628.0) - 2 new features, all patches clean

### Upstream (v1.10628.0)

- **Version bump:** v1.9659.4 -> v1.10628.0. Feature-flag architecture and patch surface structurally unchanged: minified-identifier renames, 2 new static features, and a GrowthBook flag delta.
- **All 48 patches applied without modification** - zero regex changes needed. The flexible `[\w$]+` patterns absorbed every minified rename. Build sub-pattern health verified in the build log: **166x `[OK]`, 0x `[FAIL]`** (the single `0 matches` is the explicitly `(optional)` `hardcoded electron paths` sub-pattern). `node --check` passed on all patched JS; ion-dist patch matched both sub-patterns (`[OK] org-plugins linux path`, `[OK] mount path platform ternary`); node-pty + spawn-helper rebuilt for Linux (ELF x86-64); RPM built successfully on Fedora.
- **2 new static feature flags** (32 static + `louderPenguin` async-only = **33 total**, was 31):
  - `claudeDesignWindow` - `claudeDesignWindow:XQ` in the registry (always `{status:"supported"}`, **no platform gate**, no dedicated renderer-window directory). Linux-clean, no patch needed.
  - `builtinMcpPresets` - `builtinMcpPresets:Dm(()=>XQ)` (**dev-gated** via the production wrapper -> `{status:"unavailable"}` in all packaged builds, on every platform). Gates the built-in MCP server preset list (e.g. **Microsoft 365 / `m365`**, `https://microsoft365.mcp.claude...`). STUB-class (disabled on all OSes), not a Linux exclusion - no patch needed.
  - **No features removed.** All 30 static features from v1.9659.4 retained; `chatTab`/`surfaceTogglesPreview`/`chatIn3p`/`chatCodeExecution` all still present. Both new features are in the Zod `.partial()` validation schema (`...builtinMcpPresets:Mo,surfaceTogglesPreview:Mo,...).partial()`).
- **Function renames** (re-minify): static registry `Yp()`->`Aw()`, async merger const `IlA`->`LCA` (still `{...Aw(),louderPenguin:e,coworkKappa:A,coworkArtifacts:t,markTaskComplete:i}` via `Promise.all([Fsr(),pRA(()=>It("123929380")),pRA(()=>It("2940196192")),pRA(()=>It("3732274605"))])`), dev-gate wrapper `um()`->`Dm()` (`function Dm(e){return aA.app.isPackaged?{status:"unavailable"}:e()}`, electron var `aA` unchanged), `louderPenguin` async helper `Frr()`->`Fsr()` (still `darwin||win32` gate, `unavailable` on Linux), `quietPenguin` inner `Lsr`, cowork async helper `V0A`->`pRA`, GrowthBook bool reader `Bt()`->`It()`, supported constant -> `XQ` (`{status:"supported"}`), computer-use Set `rlA`->`MCA` (`new Set(["darwin","win32"])`, `MCA.has(process.platform)`), platform vars `Or`/`mo`/`P3` -> `Yr`(darwin)/`ro`(win32)/`O$`(darwin||win32), `fix_tray_dbus.nim` this release: tray fn `Y6A`, tray var `VE`.
- **GrowthBook flags: ~17 newly present, 3 removed** (empirical delta of the **v1.9659.4 install binary** vs the fresh **v1.10628.0** binary; each add/remove confirmed by a **whole-bundle raw presence-check across all `.vite` chunks** - not just call-site grep in `index.js` - so a flag merely moving between chunks is not miscounted as new/removed). Newly present and traced: `124685897` (template-substitution gate, `ru()`), `1609612026` (marketplace install/migration path), `2143883161` (`/code/` deep-link route gate), `2720310975` (side-chat allowed tools), `2688060585`+`3269331205` (`autoModeEnabled` force-ON defaults, `Sa(!0)`); newly present (documented-historical flags re-appearing): `1129419822`, `1496676413`, `1824824999`, `2067027393`, `2114777685`, `2192324205`, `2204227020`, `245679952`, `2800354941`, `3444158716`, `4274871493`. Removed (absent in new): `3242661803`, `3638165567`, `3858743149` (maxThinkingTokens). **Caveat:** upstream serves no prior-version MSIX, so the only available "old" binary is the patched v1.9659.4 install; 3 force-ON flags our patches rewrite (`1992087837`, `2216414644`, `3732274605`) were excluded as patch artifacts. Several "new" IDs are historical flags that were tree-shaken out of v1.9659.4 and re-included here, not brand-new concepts.
- **`enable_local_agent_mode.nim` 12-flag override list unchanged** - all forced flags (`123929380`, `2940196192`, `1992087837`, `3732274605` + the 12 feature overrides) still exist in the new bundle; the 2 new features don't gate any Linux Cowork/Code/Agent-Mode path (`claudeDesignWindow` is ungated, `builtinMcpPresets` is dev-gated on all platforms). Build applied the patch without modification.
- **ion-dist (3P config SPA):** minor growth, no structural refactor - **90 MB** (was 88), **691 JS** (was 682), **909 files** (was 899), 21 CSS unchanged. Config chunk `c71860c77-BOyfE2Py.js` -> **`c71860c77-CDhE5jkR.js`** (content-hash bump). `mountPath` **still mac/win-only** (no `linux` key) -> `fix_ion_dist_linux.nim` still required and both sub-patterns matched. Platform enum `Darwin="darwin",Win32="win32",Linux="linux"` intact.
- **Platform gates:** darwin 64->65, win32 112->113, linux 5 (unchanged). The +1/+1 swing is re-minify/refactor noise: the 2 new features are **not** platform-gated, and every listed darwin/win32 gate maps to NATIVE (TouchID, codesign, ESF endpoint-security, `getSystemVersion`, NFC normalization, efivars), a platform-var declaration, or an already-Linux-handled else-branch. **No new PORTABLE (Linux-actionable) gate.**
- **Built-in MCP servers:** roster unchanged (imagine/visualize/marketplace/skills/radar/echo/Framebuffer/Window Halo present; office/browser-tools/buddy targeted by their Linux patches, all applied cleanly). The internal-registration function name (`LYA()`-line) was **not** separately re-verified this release - quick anchors didn't resolve and `registerInternalMcpServer` appears only as a context-bridge method key, not a verifiable registration call; low-risk for a roster-stable release. The only MCP-adjacent addition is the `builtinMcpPresets` **preset** list (m365 etc.), not a new internal server.
- **No structural changes:** identical renderer windows (about/buddy/find_in_page/main/quick) and main-process chunks; IPC is interface-based RPC (`CoworkArtifacts` etc.), no flat-channel additions; Electron **41.6.1** and node-pty **1.1.0-beta34** unchanged.
- **No cowork protocol changes** - `control_request`/`control_response` (8/7 refs), `sessions-bridge`, `environments/bridge`, `work/poll` all present and unchanged; **claude-cowork-service not affected**.

### No patch changes needed

## 2026-06-02 (v1.9659.4) - Point release on v1.9659.2, all patches clean

### Upstream (v1.9659.4)

- **Version bump:** v1.9659.2 -> v1.9659.4 (webpack re-minify point release - fresh identifiers, no behavioral change vs v1.9659.2). v1.9659.3 was not observed on the public download channel (the version API only serves `latest`).
- **All 47 patches applied without modification** - zero regex changes needed. The flexible `[\w$]+` patterns absorbed every minified variable rename, including `fix_tray_dbus.nim` (this release: tray fn `Jfi`, tray var `RQ`, menu var `mm`). JS syntax valid (`node --check`) on the patched bundle, RPM built successfully on Fedora.
- **Same 31 feature flags** as v1.9659.2 (30 static + `louderPenguin` async-only): exact same 30 static feature names, `chatTab`/`surfaceTogglesPreview` still the 2 newest, no features added or removed.
- **Function renames vs v1.9659.2** (re-minify only): static registry `xp()`->`Yp()`, async merger `olA`->`IlA` (still `{...Yp(),louderPenguin:e,coworkKappa:A,coworkArtifacts:t,markTaskComplete:i}` via `Promise.all([Frr(),V0A(()=>Bt("123929380")),V0A(()=>Bt("2940196192")),V0A(()=>Bt("3732274605"))])`), dev-gate wrapper `Em()`->`um()` (`function um(e){return aA.app.isPackaged?{status:"unavailable"}:e()}`, electron var `aA` unchanged), `louderPenguin` async helper `wrr()`->`Frr()`, cowork async helper `V0A` (`Frr()` keeps the `darwin||win32` gate). GrowthBook bool reader `Bt()` unchanged. Computer-use Set `XEA`->`rlA` (`new Set(["darwin","win32"])`, checked via `rlA.has(process.platform)`).
- **71 GrowthBook flag IDs** unchanged vs v1.9659.2. Note: upstream no longer serves prior-version MSIX metadata, so the flag-ID set was re-confirmed against the fresh v1.9659.4 binary and matches the documented count.
- **ion-dist (3P config SPA):** byte-identical to v1.9659.2 - config chunk still `c71860c77-BOyfE2Py.js`, main `index-C_tZnXTW.js`, 88 MB (682 JS / 21 CSS / 899 files), `mountPath` still mac/win-only (no `linux` key), `fix_ion_dist_linux.nim` still required and both sub-patterns matched (`[PASS]`).
- **Platform gates:** darwin 60->64, win32 111->112, linux 5 (unchanged). The feature registry is byte-identical (same 30 static feature names), so there is **no new feature-flag-borne gate**, and the listed darwin/win32 gates still map to NATIVE / STUB / PATCHED in `baseline/PLATFORM_GATE_BASELINE.md`. **No new PORTABLE (Linux-actionable) gate.** The exact cause of the +4/+1 literal `process.platform===` count delta (spanning the .2 -> .4 jump) can't be pinned to a specific mechanism without an old-binary diff, since upstream no longer serves prior-version MSIX.
- **Built-in MCP servers:** all MCP Linux patches (office, browser-tools, imagine, marketplace, buddy-BLE) applied cleanly, so the code structures they target still exist. The full server roster was **not separately re-enumerated** this release (the internal-registration anchor changed shape and a quick grep returns tool names, not server names); a deep MCP re-audit was deferred as low-risk for a re-minify point release.
- **`enable_local_agent_mode.nim`** 12-flag override list unchanged - the build applied it without modification.

### No patch changes needed

## 2026-06-01 (v1.9659.2) - Point release on v1.9659.1, all patches clean

### Upstream (v1.9659.2)

- **Version bump:** v1.9659.1 -> v1.9659.2 (webpack re-minify point release - fresh identifiers, no behavioral change vs v1.9659.1)
- **All 47 patches applied without modification** - zero regex changes needed. Flexible `[\w$]+` patterns absorbed every minified variable rename, including `fix_tray_dbus.nim` (this release: tray fn `G9A`, tray var `PE`). JS syntax valid (`node --check`) on all targets.
- **Same 31 feature flags** as v1.9659.1 (30 static + `louderPenguin` async-only): `chatTab`, `surfaceTogglesPreview` still the 2 newest, no features added or removed.
- **Function renames vs v1.9659.1** (re-minify only): static registry `Yp()`->`xp()`, async merger `slA`->`olA`, production gate `lm`->`Em()` (`function Em(e){return aA.app.isPackaged?{status:"unavailable"}:e()}`, electron var `aA`), `louderPenguin` async helper -> `wrr()`. GrowthBook bool reader `Bt()` and computer-use Set `XEA` (`new Set(["darwin","win32"])`, checker `AlA()`) unchanged from v1.9659.1.
- **ion-dist (3P config SPA):** unchanged from v1.9659.1 - config chunk still `c71860c77-BOyfE2Py.js` (21 sub-chunks, main `index-C_tZnXTW.js`), 88 MB, `mountPath` still mac/win-only (no `linux` key), `fix_ion_dist_linux.nim` still required and both sub-patterns matched.
- **Built-in MCP servers:** roster unchanged from v1.9659.1. Server-UUID map present (renderer var `mL`); `ios_simulator`/`android_emulator`/`echo` still reserved/inactive labels (no server implementation).
- **No GrowthBook flag changes** vs v1.9659.1. Note: upstream no longer serves prior-version MSIX metadata, so the flag-ID delta was re-confirmed against the v1.9659.1 doc baseline rather than a fresh binary diff.

---

## 2026-05-28 (v1.9659.1) - All patches clean, no new platform gates, no Linux patch needed

### Upstream (v1.9659.1)

- **Version bump:** v1.9255.2 -> v1.9659.1 (~400 builds)
- **All 47 patches applied cleanly** - zero failures, no regex changes needed. The flexible `[\w$]+` patterns absorbed every minified variable rename automatically. No new and no changed Linux patch required.
- **2 new feature flags** (30 static, was 28; +`louderPenguin` async-only = 31 total):
  - `surfaceTogglesPreview` - dev-gated via `PM()` production gate, always `unavailable` in production
  - `chatTab` - 3p-bootstrap-gated (`aze()` = `desktopBootFeatures.chatIn3p.status==="supported"` && `chatTabEnabled===true`), only active in third-party whitelabel builds; does not replace the Code tab (`louderPenguin`) or Chat
- **No feature flags removed.** All 28 static features from v1.9255.2 are still present.
- **Feature flags - function renames** (webpack re-minify only): static registry `Yp()` (was `Gp()`), async merger `slA` (was `mEA`/`pEA`), GrowthBook bool reader `Bt` (was `Ct`), async helper `x0A` (was `A0A`), `PM()`-gate wrapper `lm` (was `wD`), supported constant `Ww` (was `_M`)
- **No GrowthBook flag changes** - 71 boolean flag IDs identical to v1.9255.2 (clean diff, verified against freshly extracted old bundle). One new numeric remote-config value `1629866860` (claude_code session limit, read via `ad()` - not a boolean toggle, not flag-relevant)
- **`enable_local_agent_mode.nim` unchanged** - the 12-flag override list stays correct (the 2 new features are dev-/3p-gated and don't block the Linux Cowork/Code/Agent-Mode paths we force-enable). Validated 25/25 sub-patches, all overridden flags still in the Zod `.partial()` schema, `node --check` OK
- **15 new IPC handlers** (all platform-neutral, no Linux implementation needed): `ClaudeAiImport_*` (OAuth import of claude.ai data: `startAuth`/`runImport`/`getAuthState`/`clearAuth`/`isAvailable`/`reopenAuthTab` + `onAuthStateChange`/`onAuthUserCode` events), `Custom3pSetup_*` (`signInWithAnthropicApi`/`applyAnthropicApiShortcut`), `ClaudeCode_setEnableWorkflows`, `CoworkArtifacts_setArtifactLastModifiedSession`, `Launch_loadFramePreview`, `LocalAgentModeSessions_grantRemoteSessionFolder`, `LocalSessions_getSessionMediaStreamUrl`
- **MCP:** registration function renamed `HHA()` (was `KPA()`), mcp-registry const `mlA` (was `OEA`). **Server roster and tool sets unchanged.** New static `yL` server-UUID map that feeds `server_uuid` into the existing internal-tool telemetry. Three reserved/inactive labels in the map: `ios_simulator` and `android_emulator` (new, no server implementation yet - precursors for future MCP servers), plus `echo`
- **ion-dist SPA:** config chunk `c71860c77-BOyfE2Py.js` (was `c71860c77-DFJHDHrp.js`), 88 MB total (was 87 MB), file counts unchanged (682 JS, 21 CSS, 899 total). `mountPath` is still mac/win only (no `linux` key) - `fix_ion_dist_linux.nim` is still required; both sub-patterns matched ([PASS]). No new platform gates, plugin/config keys unchanged
- **New OS detection** (`ZEA()`): returns `macos`/`windows`/`wsl`/`linux` with proper `/proc/version` WSL sniffing; feeds Claude Code managed-settings path resolution (Linux/WSL falls through to `/etc/claude-code` via the default branch). Linux-clean, no patch needed (`fix_enterprise_config_linux.nim` already covers the consumer paths)
- **macOS/Windows-only upstream features** (Linux-irrelevant, no patch needed): tear-off halo overlay, Cowork VM virtualization (`@ant/claude-swift` entitlement, `secureVmFeaturesEnabled`), device simulator panel, native QuickEntry dictation. New win32-only gates are child-process kill (Linux takes the `SIGTERM` else-branch) and WSL settings inheritance
- **No cowork protocol changes** - `control_request`/`control_response` event-stream proxy unchanged, claude-cowork-service not affected
- **Electron** v41.6.1 and **node-pty** 1.1.0-beta34 - unchanged from v1.9255.2

### No patch changes needed

All 47 Nim patches (44 on `index.js`, 1 on `mainView.js`, 1 on `MainWindowPage-*.js`, 1 ion-dist `nim-dir`) applied without modification, plus the `claude-native.js` replace patch. The flexible regex patterns (`[\w$]+` for minified identifiers) absorbed all upstream variable renames automatically. JS syntax valid (`node --check`) on all targets.

---

## 2026-05-27 (v1.9255.2)

- **Version bump:** v1.8555.2 -> v1.9255.2
- **2 new feature flags:** `chatIn3p`, `chatCodeExecution` (29 total, was 27)
- **Patch fix:** `fix_tray_dbus.nim` rebased for merged variable declarations (#109 by @boommasterxd)
- All other 46 patches applied without modification
- **AppImage: auto-register `claude://` protocol handler** (fixes #111, reported by @vastworks) - OAuth sign-in now works on immutable distros (Bazzite, Silverblue, SteamOS). Launcher auto-registers the protocol handler on every AppImage launch. New `--integrate` / `--unintegrate` subcommands for manual control. Also adds `--no-sandbox` for AppImage X11 sessions

---

## 2026-05-23 (v1.8555.2) - All patches clean, new upstream features, Computer Use toggle fix

### Upstream (v1.8555.2)

- **Version bump:** v1.8089.1 -> v1.8555.2
- **All patches applied cleanly** - zero failures, no regex changes needed. Flexible `[\w$]+` patterns absorbed all minified variable renames.
- **3 new feature flags** (27 total, was 25):
  - `tearOffHalo` - macOS 13+ only, visual halo overlay behind controlled windows (uses `@ant/claude-swift`)
  - `grandPrixRequest` - macOS only, device pairing service request availability
  - `bootstrapConfig` - dev-gated (PM() production gate), bootstrap config access
- **New MCP server: "Window Halo"** - macOS-only, hardcoded disabled. Tools: `halo_attach`, `halo_detach` for visual window highlighting
- **Office add-in no longer an MCP server** - functionality moved to IPC-only bridge pattern (`focusOfficeDocument`, `focusBrowserTab`, etc.)
- **New MCP tools** in existing servers:
  - `mcp-registry`: `list_connectors` (lists installed connectors)
  - `plugins`: `list_plugins` (lists installed plugins)
  - `skills`: `suggest_skills` (renders addable skills widget)
  - `cowork`: `list_artifacts`, `read_widget_context` (artifact listing and widget context reading)
- **Operon fully removed** - zero references remain; startup cleanup paths still delete old caches
- **New GrowthBook flags:**
  - Boolean `434204418` (MCP connection non-blocking mode)
  - Listeners `4150329283` (cloud sync drive detection), `2358734848` (hardware buddy)
  - Removed: `658929541`, `2815031518` (setModel buffer checks)
- **New CLAUDE_CODE env vars:** `CLAUDE_CODE_ENABLE_XAA`, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, `CLAUDE_CODE_DISABLE_AGENTS_FLEET`, `CLAUDE_CODE_DISABLE_AGENT_VIEW`, `CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING`, `CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING`, `CLAUDE_CODE_SUBAGENT_MODEL`, `CLAUDE_CODE_RATE_LIMIT_TIER`, `CLAUDE_CODE_CERT_STORE`, `CLAUDE_CODE_CLIENT_CERT`, `CLAUDE_CODE_CLIENT_KEY`, `CLAUDE_SESSION_INGRESS_TOKEN_FILE`, and more
- **New ANTHROPIC env vars:** `ANTHROPIC_FOUNDRY_API_KEY`, `ANTHROPIC_FOUNDRY_BASE_URL`, `ANTHROPIC_FOUNDRY_RESOURCE`, `ANTHROPIC_SERVICE_ACCOUNT_ID`
- **ion-dist SPA:** 13 new config keys including Bedrock SSO support (`inferenceBedrockSsoStartUrl`, `inferenceBedrockSsoRoleName`, `inferenceBedrockSsoRegion`, `inferenceBedrockSsoAccountId`), credential helpers (`inferenceCredentialKind`, `inferenceCustomHeaders`), gateway auth (`inferenceGatewayOidc`, `inferenceGatewayApiKey`), Foundry (`inferenceFoundryApiKey`), and org banners (`banner.enabled`, `banner.text`)
- **ion-dist bundle:** 667 JS files (was 652), 22 CSS (was 21), 87 MB total (was 86 MB). ZST compressed variants remain removed
- **Voice onboarding audio:** full set of voice onboarding MP3s bundled in ion-dist (`airy`, `buttery`, `glassy`, `mellow`, `round` voices with intro/final/recommendations/pre-voice/pre-recommendations tracks, plus selection samples and SFX)
- **New value/object flag reader split:** `Lh()` for simple values, `Pr()` for structured object reads (was unified in `OQ()`)
- **Session config changes:** removed `artifactMcpConcurrencyLimit` and `artifactSampleConcurrencyLimit` keys; scheduled tasks gained `scheduledTaskOfflineGateEnabled`
- **Feature flags:** function names renamed - `Np()` (static, was `eD()`), `SIA` (async, was `UcA`), `PM()` (gate, was `Nb()`), `wt()` (reader, was `St()`), `Bm()` (listener, was `AS()`)
- **No new platform gates** blocking Linux
- **Electron:** v42.0.0 (check package.json - renderer reports 41.6.1 in extracted bundle but build uses 42.0.0)

### Computer Use toggle fix (#102)

- **Computer Use toggle now works on Linux** - Patch 12 in `fix_computer_use_linux.nim` previously unconditionally bypassed the `chicagoEnabled` preference check. Now reads the user's preference (defaulting to enabled when unset), so users who see the toggle via GrowthBook rollout can actually disable Computer Use.

### No other patch changes needed

All 47+ Nim patches applied without modification. The flexible regex patterns (`[\w$]+` for minified identifiers) absorbed all upstream variable renames automatically.

---

## 2026-05-20 (v1.8089.1) - Point release, integrated titlebar, cowork graceful degradation, landing page, DEB822, build improvements

### Upstream (v1.8089.1)

- **Version bump:** v1.8089.0 -> v1.8089.1
- **All patches applied cleanly** - zero failures, no regex changes needed
- **New upstream: musl/glibc detection** (`bKi()` function) - Linux improvement: properly detects musl vs glibc runtime for `claude-agent-sdk` binary selection
- **New upstream: `getRunningLocalSessions` IPC handler** - auto-updater checks for running cowork/dispatch sessions before applying updates
- **New upstream strings:** OIDC federation env vars (`ANTHROPIC_IDENTITY_TOKEN`, `ANTHROPIC_FEDERATION_RULE_ID`, etc.), device attestation statuses, "claude-mythos-preview" model reference, `CLAUDE_CODE_USE_COWORK_PLUGINS` env var, `ccRemoteControlDefaultEnabled` preference
- **ion-dist SPA:** code unchanged from v1.8089.0 - only change is removal of 704 `.zst` compressed file variants
- **sqlite-worker removed** from upstream build
- **Renderer assets deduplicated** (build tooling cleanup)
- **Feature flags:** identical to v1.8089.0 - same 25 features, same function names (`eD`, `UcA`, `Nb`, `St`, `AS`), same 60 boolean + 5 listener GrowthBook flags
- **No new platform gates** blocking Linux

### Integrated titlebar on Linux

- **Linux now uses the Windows-style integrated titlebar** (`frame:false` + `titleBarOverlay` themed via Anthropic's own background helper, theme-aware) instead of the native frame. Opt out with `CLAUDE_NATIVE_TITLEBAR=1` or the launcher flag `--native-titlebar`. Quick Entry is unaffected.
- New patches: `fix_native_frame.nim` (main process, conditional window options + theme-update gate + opaque overlay color in integrated mode) and `fix_native_frame_renderer.nim` (collapses the upstream `nc-drag` div in `MainWindowPage-*.js` so it no longer absorbs pointer events over the UI buttons).
- Contributed by [@boommasterxd](https://github.com/boommasterxd) ([#100](https://github.com/patrickjaja/claude-desktop-bin/pull/100)).

### Cowork graceful degradation

- **Cowork preamble** now detects socket availability at startup and logs a helpful message with install link when the cowork service is not running.
- **Event subscription guard** (Patch H): skip `createConnection` call when the cowork socket is absent, with a lazy 60s retry that auto-connects once the service appears.
- **Error message URLs** now include full `https://` prefix for clickability.

### Patch fix: restore fix_ion_dist_linux

- **`fix_ion_dist_linux.nim` restored** - the v1.8089.0 update incorrectly claimed Anthropic upstreamed Linux support for the ion-dist 3P config SPA. Verification against the **unpatched** MSIX shows: only the file manager label ("Show in file manager") was upstreamed. The `mountPath` object still lacks a `linux` key, and the platform ternary still falls back to the macOS path on Linux. Both sub-patches are still needed.
- **Regex updated** for v1.8089.0 minified variable names: ternary pattern now uses `[\w$.]+ ` wildcards instead of hardcoded `r`/`t` variable names (v1.8089.0 uses `C===V.Win32?Ve.mountPath.win:Ve.mountPath.mac`).

### APT repo: DEB822 format

- **APT install script now uses DEB822 `.sources` format** instead of legacy one-line `.list` format ([#101](https://github.com/patrickjaja/claude-desktop-bin/issues/101))
- `install.sh` creates `/etc/apt/sources.list.d/claude-desktop.sources` with structured `Types`/`URIs`/`Suites`/`Signed-By`/`Architectures` fields
- **Migration:** re-running `install.sh` automatically removes the old `claude-desktop.list` to prevent duplicate APT entries
- **Manual setup docs** (`packaging/apt/index.html`) updated to match
- Compatible with all supported distros (Debian 11+, Ubuntu 22.04+) - DEB822 has been supported since APT 1.1

### Promotional landing page

- **New static landing page** (`site/index.html`) replaces the minimal APT setup guide at the gh-pages root
- Single-file HTML/CSS/JS - no build step, no framework dependencies
- Dark theme with violet accent, responsive design (mobile/tablet/desktop)
- **UA-based distro detection:** hero terminal and install tabs auto-select the right commands based on visitor's OS
- Sections: hero, tabbed quick-install (Arch/Ubuntu/Fedora/Nix/AppImage), 12-card feature grid, distro+arch compatibility matrix, session type table, Cowork Service (native vs KVM), footer with live badges
- No screenshots included (upstream UI is copyrighted)
- CI change: `build-and-release.yml` now copies `site/index.html` instead of `packaging/apt/index.html` to gh-pages root
- **No impact on package repos** - `deb/`, `rpm/`, `badges/`, `install.sh`, `install-rpm.sh`, `gpg-key.asc` paths all untouched

### Build improvements

- **Smoke tests skipped by default** in all local build scripts (`build-local.sh`, `build-ubuntu-local.sh`, `build-fedora-local.sh`). Pass `--smoke-test` to opt in. CI is unaffected - smoke tests still run there automatically.
- **Electron zip cached across Arch builds** - `build-local.sh` now uses `SRCDEST` to cache `electron-v*.zip` in `cache/`, avoiding ~120MB re-download on every build.
- Removed redundant `--no-smoke-test` flag (default is now skip).
- Updated docs: `CLAUDE.md`, `update-prompt.md`, issue template.

### Update workflow distro-agnostic

- **Issue template, update-prompt, CC prompt** now show build commands for all supported distros (Arch, Ubuntu/Debian, Fedora/RHEL) instead of hardcoding `./scripts/build-local.sh` (Arch-only)
- **Stale extraction paths** replaced: `Claude-Setup-x64.exe` / Squirrel nupkg references updated to `Claude.msix` extraction in issue template, update-prompt.md, and themes/README.md

---

## 2026-05-19 - Enhanced version-check issue template with Linux compatibility checklist

- **Version-check workflow** now creates comprehensive issues with:
  - Copy-paste Claude Code update prompt (injected from `UPDATE-PROMPT-CC-INPUT-MANUAL.md`)
  - Linux compatibility reference tables (5 session types, 7 distros/archs)
  - Full update checklist with dedicated Linux compatibility analysis step
  - Collapsible quick reference commands for platform gate diffs, flag audits
- **New file:** `.github/issue-templates/new-version-body.md` - Markdown template with `{{UPSTREAM}}`, `{{RELEASED}}`, `{{REPO}}`, `{{CC_PROMPT}}` placeholders rendered at workflow runtime
- **UPDATE-PROMPT-CC-INPUT-MANUAL.md** - converted code blocks to indented style (fence-safe for embedding)

---

## 2026-05-19 (v1.8089.0) - Upstream update, ion-dist upstreamed, 12 new flags, Chrome integration, sandbox dirs

- **Version bump:** v1.7196.0 -> v1.8089.0
- **4 patches refreshed** for new minified variable names:
  - `enable_local_agent_mode.nim` - upstream added a compound `&&process.platform!=="win32"` check to the `quietPenguin` inner function (`A5i()`); made regex optional. Async merger terminator changed from `;` to `,` (comma-separated const); updated to match both.
  - `fix_marketplace_linux.nim` - upstream changed scope normalization from a `push(...);continue` loop to a `return` expression. Added new regex for the return-style pattern, old push-style kept as fallback.
  - `fix_tray_dbus.nim` - tray function name `i$A` contains `$` (regex metacharacter). Added `escapeRe()` helper; updated all dynamically-constructed regexes to escape `$`. Also updated listener pattern to handle `zf.on("menuBarEnabled",...)` prefix object.
  - `fix_imagine_linux.nim` - added sub-patch C to force-enable `2204227020` (Visualize in CCD sessions). Total sub-patches: 2 -> 3.
- **1 patch simplified (upstream change):**
  - `fix_office_addin_linux.nim` - office-addin MCP server platform gate `(darwin||win32)&&louderPenguinEnabled` was **removed upstream**. Patches A (isEnabled) and B (init block) are no longer needed. Patch C (connected file detection) remains. Reduced from 3/3 to 1/1 expected patches.
- **1 patch incorrectly removed** (restored in 2026-05-20 fix):
  - `fix_ion_dist_linux.nim` - was removed claiming Anthropic upstreamed Linux support, but only the file manager label was upstreamed. `mountPath` linux key and platform ternary still need patching. See 2026-05-20 entry.
- **1 new patch added:**
  - `fix_sensitive_dirs_linux.nim` - adds Linux-specific sensitive directories to the sandbox protection array: `.local/share/keyrings` (GNOME/KDE credential storage), `.pki` (NSS certificate database), `.config/autostart` (XDG autostart entries). The upstream array had macOS and Windows entries but no Linux-specific ones.
- **12 new GrowthBook flags force-enabled** for Linux (in `enable_local_agent_mode.nim` + `fix_imagine_linux.nim`):
  - High priority: `1129419822` (ENABLE_TOOL_SEARCH auto), `2192324205` (tool use result formatting), `2800354941` (deterministic sorting), `4274871493` (plugin enabled state fetch)
  - Medium priority: `2204227020` (Visualize in CCD sessions - in `fix_imagine_linux.nim`), `2976814254` (Claude Preview dev server), `2067027393` (canLaunchCodeSession), `3246569822` (canSaveSkill)
  - Also enabled: `245679952` (suggestSkills default), `1496676413` (SSH remote MCP/plugin), `1824824999` (consolidate-memory v2), `2114777685` (cowork onboarding)
- **Chrome browser integration improved** (`fix_browser_tools_linux.nim`, 3 new sub-patches):
  - **Chrome user data dir detection** (`O2A` function) - returned `[]` on Linux, breaking extension detection and file watching. Added paths for Chrome (`~/.config/google-chrome`), Chromium (`~/.config/chromium`), Brave (`~/.config/BraveSoftware/Brave-Browser`), Vivaldi (`~/.config/vivaldi`), Opera (`~/.config/opera`). Edge excluded (no Linux version).
  - **Chrome extension auto-install** (`vkr` function) - returned "Unsupported platform" error on non-darwin. Added Linux support: writes External Extensions JSON to both `~/.config/google-chrome` and `~/.config/chromium` directories.
  - **Chrome DevTools opener** (`YOr` function) - had handlers for darwin (`open -a`) and win32 (`start chrome`) but none for Linux. Added `xdg-open "chrome://inspect"` handler.
- **All other patches applied cleanly** without modification
- **Function renames (minification changes):**
  - `pw()`->`eD()` (static registry), `woA`->`UcA` (async merger), `DT()`->`Nb()` (production gate)
  - `pt()`->`St()` (flag reader), `Cm()`->`AS()` (listener)
  - `or`->`Lr` (darwin), `fn`->`Io` (win32), `OiA`->`pj` (darwin||win32)
  - `QoA`->`NcA` (computer-use Set), `saA`->`C5` (supported constant)
- **GrowthBook flags upstream:** 60 boolean (`St()`), 5 listeners (`AS()`). 7 new flags added, 8 removed.
  - New upstream: `1129419822`, `1496676413`, `2049450122`, `2192324205`, `245679952`, `2800354941`, `4274871493`
  - Removed upstream: `982691970`, `1802019210`, `2216480658`, `2860753854`, `3298006781`, `3858743149`, `3885610113`, `4019128077`
  - New listener: `180602792` (midnightOwl prototype)
- **Notable upstream changes:**
  - Visualize (Imagine) MCP server now also enabled for CCD sessions (gated by `2204227020`), not just cowork
  - Office Addin tools refactored: 5 tools reduced to 2 (`office_addin_run`, `office_addin_task`). Bridge architecture changed from MCP server pattern to listener/dispatcher. Platform gate removed.
  - New `floatingPenguinEnabled` preference (config-only, not yet a feature flag in static registry)
- **ion-dist SPA:** 86 MB total (was 100 MB), 652 JS chunks (was 632). File manager label upstreamed (shows "Show in file manager" on Linux), but `mountPath` linux key and platform ternary still need patching.
- **Patch count:** 46 (was 45 - 1 restored + 1 added). All pass, JS syntax validated via `node --check`.

---

## 2026-05-16 - Fix cowork sandbox refs for v1.7196.1

- **`fix_cowork_sandbox_refs.nim` sub-patch A updated** for Claude Desktop v1.7196.1 - upstream collapsed the bash tool description from a three-piece string concat into a single literal, breaking the existing regex. Adds a new pattern for the collapsed literal while keeping the old concat pattern as a fallback for v1.6608.x and v1.7196.0. Contributed by [@boommasterxd](https://github.com/boommasterxd) in [#95](https://github.com/patrickjaja/claude-desktop-bin/pull/95). Fixes [#94](https://github.com/patrickjaja/claude-desktop-bin/issues/94), [#93](https://github.com/patrickjaja/claude-desktop-bin/issues/93).

---

## 2026-05-14 — Sandbox compatibility: systemd user scope optional

- **Launcher skips `systemd-run --user --scope` automatically** when the systemd private socket (`$XDG_RUNTIME_DIR/systemd/private`) is missing or unreachable. Fixes a hard start failure in sandboxes (bwrap, distrobox, containers) where the binary exists but the socket is filtered. Contributed by [@boommasterxd](https://github.com/boommasterxd) in [#92](https://github.com/patrickjaja/claude-desktop-bin/pull/92). Fixes [#89](https://github.com/patrickjaja/claude-desktop-bin/issues/89).
- **`--no-systemd-scope` CLI flag** and **`CLAUDE_DISABLE_SYSTEMD_SCOPE=1` env var** for explicit opt-out when the socket exists but is unreachable (SELinux, bind-mount filters).
- **`--diagnose` output** now shows systemd user socket status.

---

## 2026-05-14 (v1.7196.0) — Upstream update, 3 patch refreshes, no new Linux patches needed

- **Version bump:** v1.6608.2 → v1.7196.0
- **3 patches refreshed** (contributed by @boommasterxd in [#91](https://github.com/patrickjaja/claude-desktop-bin/pull/91)):
  - `fix_imagine_linux.nim` — upstream extended the Visualize MCP server's `isEnabled` callback with an optional `ccd` session type gate (flag `2204227020`). Patch now tries the new disjunction pattern first, falls back to the v1.6608 cowork-only pattern. Forces both `cowork` and `ccd` sessions enabled on Linux.
  - `fix_cowork_first_bash.nim` — upstream may rewrite the events-socket helper from an early-return guard to a Promise-based singleton. Added a second regex for the `Promise.resolve()` pattern. Falls back to the v1.6608 `if(VAR)return` pattern.
  - `fix_dispatch_linux.nim` — upstream added an optional telemetry call (`D8(e,A),`) before the flag return expression in `pt()`. Extended the regex with an optional non-capturing group `(?:[\w$]+\([\w$,]+\),)?`. Existing capture groups unchanged. Falls back to the v1.6608 pattern without telemetry.
- **All other patches applied cleanly** without modification
- **No new features requiring Linux patches** — no new platform gates, no new darwin/win32-only features
- **Function renames (minification changes):**
  - `DoA`→`woA` (async merger — reverted to v1.6608.0 name)
  - `BrA()`→`lrA()` (MCP registration — reverted to v1.6608.0 name)
  - `QoA`→`BoA` (computer-use Set)
  - `xSA`→`FSA` (MCP display labels)
  - `I_` unchanged (MCP registry storage)
  - `or` (darwin), `fn` (win32), `OiA` (darwin||win32) — all unchanged
  - `pw()` (static registry), `pt()` (flag reader), `Cm()` (listener), `OQ()` (value reader), `DT()` (production gate), `Gu` (GrowthBook storage) — all unchanged
- **`wr()` single-value flag reader removed** — function no longer exists. `pr()` now handles all value/object flag reads with nested property access.
- **GrowthBook flags:** 60 boolean (`pt()`), 9 value/object (`pr()`), 5 listeners (`Cm()`), 10 multi-key (`OQ()`). No new or removed flags compared to v1.6608.2.
- **MCP servers unchanged:** Same 22 servers (3 renderer-facing, 14 backend, 4 dynamic per-session, 1 per-artifact). No new servers, no removed servers, no new tools.
- **ion-dist SPA:** 100 MB total, 632 JS chunks, 21 CSS files (unchanged). New `.zst` compressed variants of JS chunks added (704 total). org-plugins mountPath still lacks `linux` key — `fix_ion_dist_linux.nim` patch still required.
- **All 45 patches pass**, JS syntax validated via `node --check`

---

## 2026-05-10 (v1.6608.2) — Point release, doc-only updates

- **Version bump:** v1.6608.1 → v1.6608.2
- **No patch changes required:** All 35+ sub-patches applied cleanly without modification — no minified variable name renames in the main JS (function names `pw()`, `DoA`, `mT()`, etc. all unchanged)
- **MCP registration renames:** `lrA()`→`BrA()` (registration function), `MG`→`I_` (registry storage), `VqA`→`xSA` (display labels), `Y7()`→`pq()` (enumerator)
- **No new MCP servers** — all servers (including Framebuffer, ccd_directory, ccd_session_mgmt) already existed in v1.6608.0; now documented as standalone entries in CLAUDE_BUILT_IN_MCP.md (total documented: 22)
- **21 new GrowthBook server-side flags added** (no feature flag structural changes)
- **Notable new flag capabilities:** session handoff (`2049450122`), cowork memory sync (`975112542`), cowork CU-only mode (`3371831021`), auto-update nudge (`3023518717`), tool-use summaries (`66187241`, `3792010343`)
- **ion-dist SPA:** unchanged (identical build timestamp `1778285308`)
- **All 35+ patches pass**, JS syntax validated

---

## 2026-05-08 (v1.6608.1) — Point release, re-minify only

- **Version bump:** v1.6608.0 → v1.6608.1
- **No patch changes required:** All 35+ sub-patches applied cleanly without modification — this is a pure webpack re-minify with no structural changes
- **No new features, flags, MCP servers, or platform gates**
- **Minified variable renames:** `MW()`→`DT()` (production gate), `woA`→`DoA` (async merger), `fM()`→`Cm()` (listener), `ew()`→`wr()` (single-value reader), `Bn()`→`OQ()` (multi-key reader), `Nvi()`→`vbi()` (louderPenguin async), `D1A()`→`dhA()` (cowork async helper), `Zr`→`sr` (darwin bool), `ys`→`fn` (win32 bool), `BwA`→`YiA` (darwin||win32), `BoA`→`QoA` (computer-use Set), `lrA`→`BrA` (MCP registration)
- **New `1978029737` session config keys:** `coworkWebFetchPrompt`, `memoryIndexSnapshotIdleMs`, `peakHoursStartPst`, `peakHoursEndPst`
- **ion-dist SPA:** JS file count 627→632 (+5), CSS 22→21 (-1), main index bundle ~7.9→~6.9 MB, c71860c77 chunks 12→13; patched patterns unchanged

---

## 2026-05-07 (v1.6608.0) — Upstream update, computer-use patch fix, operon removed

- **Version bump:** v1.6259.1 → v1.6608.0
- **1 patch fix required:** `fix_computer_use_linux.nim` Patch 11 (isEnabled gate) — upstream simplified the function from a ternary `return X(Y)?Z.has(process.platform)&&W():V()` to a direct `return Z.has(process.platform)&&W()`. Updated regex to try new pattern first, old pattern as fallback. All other 42 patches applied cleanly without modification.
- **`operon` feature removed upstream:** Was always `{status:"unavailable"}`, now completely deleted from code. 6 related GrowthBook flags removed: `1306813456`, `1496450144`, `2216480658`, `2433104842`, `2486083521`, `4019128077`. None were referenced by our patches.
- **4 new features added upstream:** `framebufferPreview` (dev-only + flag `1928275548`), `iosSimulator` (dev+darwin-only), `androidEmulator` (dev+darwin-only), `grandPrix` (darwin-only device pairing). None require Linux patches.
- **Async merger reduced:** 5 → 4 overrides (operon evaluator removed); now: louderPenguin, coworkKappa, coworkArtifacts, markTaskComplete
- **New Windows env passthrough:** `$oA()` function passes Windows-specific env vars to CLI spawns; returns `{}` on Linux — no patch needed
- **Function renames:** `v_()→pw()` (static registry), `ZDA→woA` (merger), `Jt()→pt()` (GrowthBook accessor), `qwA→lrA` (MCP registration IPC), computer-use Set `qDA→BoA`, `mVt→ITi` (isEnabled)
- **ion-dist SPA:** minor shrinkage (1612→1552 files, 660→627 chunks, 105→100 MB); patched patterns unchanged
- **No new MCP servers, IPC handlers, or platform gates**

---

## 2026-05-06 — Dispatch hostLoop fix, autostart migration, CLAUDE.md MSIX updates

- **Dispatch patch (`fix_dispatch_linux.nim`):** Force GrowthBook flag `1143815894` (hostLoopMode) OFF alongside dispatch ON. HostLoop bypasses cowork-svc, breaking skills/plugins on Linux. Patch E now handles three states: fully patched, stale combined override, and dispatch-only — adding hostLoop OFF in all cases. Renamed references from `Jr()` to `Pt()` to match v1.6259.1 minified names.
- **Autostart migration (`fix_startup_settings.nim`):** `isStartupOnLoginEnabled()` now migrates old `com.anthropic.claude-desktop[-PROFILE].desktop` files to `claude[-PROFILE].desktop` before checking, so users upgrading from the old APP_ID don't lose their startup-on-login setting.
- **CLAUDE.md:** Updated all references from `Claude-Setup-x64.exe` / nupkg extraction to `Claude.msix` extraction paths. Added per-binary glibc floor table (node-pty 2.31, kwin-portal-bridge 2.39).

---

## 2026-05-06 — Pin Electron version, cache in CI

- **Pinned Electron version:** New `.electron-version` file at project root (currently `42.0.0`). To bump: edit the file and commit — all scripts and CI pick it up automatically.
- **Shared resolution helper:** `scripts/resolve-electron-version.sh` replaces duplicated GitHub API calls in 4 scripts (`generate-pkgbuild.sh`, `build-appimage.sh`, `build-deb.sh`, `build-rpm.sh`). Resolution chain: env override → `.electron-version` → GitHub API fallback.
- **CI caching:** `test-pkgbuild` job now caches the Electron zip (~90MB) with `actions/cache@v4`, avoiding re-download on every run. All packaging jobs receive the pinned version via `ELECTRON_VERSION` env from the `check-version` job output.
- **Removed:** hardcoded `33.2.1` fallback in `build-rpm.sh`, per-build `build/.electron-version` cache in `generate-pkgbuild.sh`.

---

## 2026-05-06 — MSIX migration, APP_ID rename to `claude`, kwin-portal-bridge rebased on Noble

- **MSIX migration:** Anthropic switched the upstream Windows artifact from the Squirrel installer (`Claude-Setup-x64.exe` → nupkg → `lib/net45/resources/`) to a flat MSIX package (`Claude.msix` → `app/resources/`). All build paths updated:
  - `scripts/build-patched-tarball.sh`, `scripts/build-local.sh`, `scripts/build-ubuntu-local.sh`, `scripts/build-fedora-local.sh`, `scripts/extract-version.sh`, and `.github/workflows/build-and-release.yml` now download/extract `Claude.msix`
  - Version is read from `AppxManifest.xml` (`Identity.Version` is `X.Y.Z.0`; trailing `.0` stripped)
  - URL-decoding pass added after extract — MSIX encodes `@` as `%40` (e.g. `@scope` → `%40scope`), which breaks asar's unpacked-file resolver
  - Icon now extracted from `assets/Square150x150Logo.png` (300×300) and resized to 256×256 via ImageMagick; `icotool`/`icoutils` dependency dropped, replaced by `imagemagick`
  - `smol-bin.*.vhdx` now lives under `app/resources/`; missing vhdx is now a hard fail (was best-effort)
  - `.gitignore`: added `/Claude.msix`
- **APP_ID renamed `com.anthropic.claude-desktop` → `claude`:** Chromium auto-generates its inner systemd scope as `app-<app.getName().toLowerCase()>-PID.scope` = `app-claude-…`. Aligning every identifier on the same string (binary basename, `.desktop` filename, `StartupWMClass`, Wayland `app_id`, systemd outer scope, autostart entry, executor `hostBundleId`) makes KDE global shortcuts and persistent xdg-desktop-portal RemoteDesktop authorizations stick across sessions.
  - Launcher: `scripts/claude-desktop-launcher.sh` (`APP_ID='claude'`)
  - Packaging: `PKGBUILD.template`, `packaging/debian/build-deb.sh` + `rules` + new `claude.desktop` (old `com.anthropic.claude-desktop.desktop` deleted), `packaging/rpm/claude-desktop-bin.spec`, `packaging/nix/package.nix`, `packaging/appimage/build-appimage.sh`
  - Patches: `fix_computer_use_linux.nim` (`hostBundleId`), `fix_quick_entry_app_id.nim` (main + Quick Entry app_ids → `claude` / `claude-quick-entry`), `fix_startup_settings.nim` (autostart filename)
  - JS: `js/executor_linux.js` (`DEFAULT_HOST_BUNDLE_ID = 'claude'`)
  - CI smoke tests updated to assert the new binary name
  - **User-visible breaking change:** anyone with the old `com.anthropic.claude-desktop.desktop` pinned to their taskbar must re-pin once after this update; custom WM rules matching `Claude` or `com.anthropic.claude-desktop` need to switch to `claude` (named profiles get `claude-<name>`); GNOME shell extension users (Rounded Window Corners Reborn, Unite, Blur My Shell, ...) who blacklisted `com.anthropic.claude-quick-entry` to hide the shadow rectangle behind Quick Entry must update that entry to `claude-quick-entry`
- **kwin-portal-bridge CI rebased Trixie+zigbuild → Noble+native cross:** Build now uses `ubuntu:noble` with a deb822 multiarch sources file (host=amd64, ports=arm64), `gcc-aarch64-linux-gnu` for cross-link, and rustup-installed toolchain. Removed `cargo-zigbuild` and the glibc 2.31 target. Rationale: kwin-portal-bridge requires KWin 6.6+, and Noble (glibc 2.39) is the oldest base any 6.6+ distro ships — older glibc targeting was buying nothing. The glibc check now version-compares with `sort -V` instead of lexicographic `[[ > ]]` (which would mis-rank `2.10 < 2.4`) and asserts ≤ 2.39.
- **KWin 6.6+ gate in `js/cu_mode_preamble.js`:** Auto-mode now runs `kwin_wayland --version` on KDE Wayland sessions and only enables the kwin-portal-bridge path when `>= 6.6`. Older Plasma sessions fall back to the cross-distro path; the diagnostic line includes the detected KWin version (`auto: cross-distro fallback; KWin 6.5 < 6.6`).
- **`scripts/build-local.sh --pkgrel <REL>`:** New flag (also `-r`) overrides the package release number passed to `generate-pkgbuild.sh`. Unknown args now error out instead of being silently swallowed.
- **`js/executor_linux.js`:** Added `debugLog` calls to `resolvePrepareCapture`, `screenshot`, and `type` for runtime diagnosis of computer-use input/capture issues.

---

## 2026-05-06 (v1.6259.1) — Point release, 3 features removed, new MCP servers & tools

- **Version bump:** v1.6259.0 → v1.6259.1
- **No patch changes needed** — all 43 patches applied cleanly without modification
- **3 features removed upstream:** `floatingAtoll` (was always-supported, now gone), `androidEmulator` (was dev-gated macOS-only), `grandPrix` (was macOS-only device pairing) → static registry 26→23 features
- **New MCP server:** `"skills"` — `list_skills` (interactive skill widget), `search_skills`
- **New tools on existing servers:**
  - Chrome: `browser_batch` (batch browser tool calls), `list_connected_browsers`, `select_browser`
  - ccd_session: `mark_chapter` (flag out-of-scope issues)
  - Radar: `retire_card` (retire no-longer-actionable cards)
  - Cowork: `propose_skills`
- **New Operon tools** (NOT MCP — part of Nest local agent runtime): `copy_file_user_to_claude`, `delete_host_files`, `select_relevant_inputs`
- **Removed tool:** `update_plan` (Chrome)
- **Function renames:** `Y_()→v_()`, `xDA→ZDA`, `UO()→MW()`, `Jt()→Pt()`, `kM()→fM()`, `lp()→ew()`, `dn()→Bn()`; platform vars `Xi→Zr`, `Ds→ys`, `ryA→BwA`; computer-use Set `rwA→qDA`; async helpers `DFA→D1A`, `j_r→evr`, `mFt→jxt`
- **Force-ON defaults:** `2307090146` (plugin OAuth storage) removed from force-ON map; remaining 5 flags unchanged
- **ion-dist SPA:** minor shrinkage (1634→1612 files, 669→660 JS chunks); patched patterns unchanged (same content hashes)
- **New ion-dist config keys:** Bootstrap (bootstrapEnabled/Url/Oidc), Bedrock (AwsDir, BearerToken, ServiceTier), Vertex (BaseUrl, CredentialsFile, OAuth*), Gateway auth scheme `"sso"`, OTLP resource attributes, Cowork/Sandbox (requireCoworkFullVmSandbox, secureVmFeaturesEnabled)
- **All 43 patches pass**, JS syntax validated

---

## 2026-05-06 — Fix duplicate tray icon on theme change

- **Fixed:** Toggling appearance (light/dark/system) in Settings caused a ghost tray icon on XFCE and other StatusNotifierWatcher-based panels. Root cause: the `nativeTheme.on("updated")` handler needlessly destroyed and recreated the tray, even though the Linux icon is always `TrayIconTemplate-Dark.png` regardless of theme. The panel couldn't process the DBus unregistration before the new registration arrived. Fix: `fix_tray_dbus.nim` Step 7 removes the tray function call from the theme handler.

---

## 2026-05-06 (v1.6259.0) — Upstream update, 1 patch fixed, 2 new macOS-only features, auth refactor

- **Version bump:** v1.5354.0 → v1.6259.0
- **Fixed patches:**
  - `fix_asar_workspace_cwd.nim` — upstream removed `return` keyword before `LocalSessions.start:` log statement; regex updated to match standalone log call instead of `return <var>.info(...)` pattern
- **New upstream features (macOS-only, no action needed):**
  - `androidEmulator` — Android emulator integration (dev-gated via `UO()` + macOS-only)
  - `grandPrix` — Device pairing system with pair/disconnect/status IPC bridge (macOS-only + GrowthBook `873030668` partner config)
- **Auth refactor:** Vertex-specific auth (`vertexAuth`, `triggerVertexAuth`, `revokeVertexAuth`) replaced by generic `interactiveAuth` system; gateway SSO endpoints (`gatewaySsoUserCode`, `triggerGatewaySso`) replaced by `authorizeAndProbeMcpServer`
- **New IPC endpoints:** 18 added including `GrandPrix_$_pair`, `interactiveAuth` store, credential helper (`Custom3pHelperRun`, `Custom3pSetup`), `FileSystem_$_writeFileDownload`, `LocalSessions_$_cancelQueuedMessage`, `resolveSSHSettings`, `submitFeedback`
- **New GrowthBook flags:** 3 new boolean flags (`982691970` cowork plugin host ops, `1802019210` cowork plugin upload migration, `2307090146` plugin OAuth storage — added to force-ON defaults); 3 new value flags (`873030668` grandPrix partner config, `1126577245` cowork memory remote sync config, `2921038508` cowork memory guide prompt); 1 removed (`839037100` cowork OAuth configs)
- **New feature:** `desktopTopBar` — always supported (unconditional), new UI chrome element
- **Feature flag renames:** `v_()` → `Y_()`, `ZDA` → `xDA`, `MW()` → `UO()`, `Pt()` → `Jt()`, `fM()` → `kM()`
- **ion-dist SPA:** minor growth (1612→1634 files, 660→669 JS chunks); patched patterns unchanged
- **Cleanup:** Removed duplicate tray implementation from `claude-native.js` — the real tray is created by upstream code (patched by `fix_tray_dbus.nim`); the stub now returns `null` instead of creating a second tray
- **All 43 patches pass**, JS syntax validated

---

## 2026-05-05 — Fix aarch64 tarball path in CI release job

- **Fixed:** `build-aarch64-tarball` job wrote the tarball to `/tmp/` instead of the working directory due to `$(pwd)` resolving inside a subshell after `cd` into a temp dir. Capture absolute path before `cd` (matches DEB/RPM job pattern).

---

## 2026-05-05 — Fix session name leaking into bash tool description (native mode)

- **Fixed:** Patch A in `fix_cowork_sandbox_refs.nim` leaked `vmProcessName` into the native-mode bash tool description — the session name variable was concatenated between two separate ternaries instead of being inside a single ternary's KVM branch. This caused the model to hallucinate `/sessions/<name>/mnt/outputs` paths that don't exist without root.

---

## 2026-05-05 — CI: add PR validation + kwin-portal-bridge cache

- **Added:** `pull_request` trigger on `build-and-release.yml` — contributors now get the full build pipeline on PRs (patches, kwin-portal-bridge, all packaging formats, glibc verification, both architectures)
- **Added:** Concurrency control — pushing new commits to a PR cancels in-progress CI runs
- **Added:** `paths-ignore` — docs-only PRs skip the pipeline
- **Changed:** Release-only jobs (`release`, `deploy-rpm-repo`, `deploy-pages`, `validate-nix`) gated with `github.event_name == 'workflow_dispatch'` — skipped on PRs, no code duplication
- **Optimized:** Cache kwin-portal-bridge binaries keyed on upstream repo HEAD SHA — skips the ~13min Rust build on cache hit, glibc verification still runs every time

---

## 2026-05-04 — AUR: add aarch64 architecture support

- **Added:** `PKGBUILD.template` now declares `arch=('x86_64' 'aarch64')` with arch-specific source arrays and Electron downloads
- **Added:** CI produces a dedicated aarch64 tarball (node-pty + kwin-portal-bridge swapped) uploaded alongside the x86_64 tarball in GitHub releases
- **Updated:** `.SRCINFO` generation emits both architectures and both `source_aarch64`/`sha256sums_aarch64` arrays
- **Updated:** `generate-pkgbuild.sh` accepts `SHA256SUM_AARCH64` and `DOWNLOAD_URL_AARCH64` env vars

---

## 2026-05-01 — kwin-portal-bridge CI: glibc 2.31 compat + aarch64 cross-build

- **Fixed:** Bridge build uses `rust:1-trixie` (PipeWire 1.4, needed for `pw_stream_get_nsec`) + `cargo-zigbuild` targeting glibc 2.31 (was Bullseye/Bookworm which lacked the required PipeWire APIs)
- **Added:** aarch64 cross-compilation in the same Docker step; aarch64 binary uploaded as artifact and swapped into tarball for ARM64 AppImage, DEB, and RPM packages
- **Hardened:** Bridge build failure now stops the pipeline (was a non-fatal warning)

---

## 2026-04-30 — KWin portal bridge & KVM mode for cowork/computer-use

- **New:** Runtime-configured KWin portal bridge support for KDE/Wayland users. `cu_mode_preamble.js` sets `__cuKwinMode` dynamically based on desktop session and environment (detects `kwin-wayland`). `cowork_mode_preamble.js` configures `__coworkKvmMode` based on backend environment or auto-detect (KVM detection via socket presence). ([#54](https://github.com/patrickjaja/claude-desktop-bin/pull/54)) — contributed by [@mosi0815](https://github.com/mosi0815)
- **New:** `executor_linux.js` — full Linux executor implementation (1614 lines) for computer-use input simulation and screenshot capture
- **Refactored:** `fix_computer_use_linux.nim` — major rework with new `cu_mode_preamble.js` dependency
- **Refactored:** `fix_cowork_linux.nim` — reworked with new `cowork_mode_preamble.js` dependency
- **Refactored:** `fix_cowork_sandbox_refs.nim` — Nim port alignment for runtime compatibility
- **Simplified:** `fix_dispatch_linux.nim` — reduced from 89 to 2 lines
- **Removed:** `fix_dispatch_outputs_dir.nim` — no longer needed
- **Bundled:** `kwin-portal-bridge` binary built in CI (`rust:1-bookworm` for glibc compat) and shipped in `locales/` — KDE Plasma Wayland users need zero extra packages for Computer Use
- **Changed:** `cu_mode_preamble.js` resolves bridge binary via `process.resourcesPath` (bundled) before `$PATH` scan; `executor_linux.js` reads resolved path from `globalThis.__cuKwinBridgeBin`

---

## 2026-04-29 — Marketplace plugin scope fix

- **Fix:** Personal plugins installed via Claude Code CLI now appear under "Personal Plugins" instead of the current project header ([#74](https://github.com/patrickjaja/claude-desktop-bin/issues/74), [#75](https://github.com/patrickjaja/claude-desktop-bin/pull/75)). The CLI stores personal plugins with `scope="project"` + `projectPath=$HOME`, and since `$HOME` is a prefix of every project path, they matched the project branch instead of the user branch. New sub-patch B in `fix_marketplace_linux.nim` promotes these entries to `scope="user"` at read time (on-disk JSON unchanged). — contributed by [@boommasterxd](https://github.com/boommasterxd)
- **Hardened:** Moved `patchesApplied` counter inside `proc apply*` (codebase convention), added `process.env.HOME` guard against undefined, added brace-balance verification

---

## 2026-04-29 (v1.5354.0) — Upstream update, 3 patches fixed, 2 new dev-gated features, 13 new GrowthBook flags

- **Version bump:** v1.4758.0 → v1.5354.0
- **Fixed patches:**
  - `fix_window_bounds.nim` — regex now tolerates optional code (profile title hook) between BrowserWindow creation and setup call
  - `fix_dispatch_linux.nim` — sessions-bridge gate variable no longer assumed to be last in `let` declaration; uses two-step find-then-replace approach
  - `fix_dispatch_outputs_dir.nim` — upstream added `Tc()` path-translation wrapper in `shell.openPath()`; regex updated to optionally match wrapper function
- **New upstream features (dev-gated, no action needed):**
  - `framebufferPreview` — VNC framebuffer preview (GrowthBook `1928275548`), gated by `MW()` production gate
  - `iosSimulator` — iOS Simulator integration, macOS-only + dev-gated
- **New GrowthBook flags:** 13 new boolean flags (OAuth configs, memory sync, session notifications, updater rollback, PreToolUse hook, etc.), 2 new value flags, 1 new listener flag; 1 removed (`365342473` telemetry scrub)
- **ion-dist SPA:** bundle grew from 85 MB / 842 files to 105 MB / 1612 files; config UI code-split into 12 lazy-loaded chunks; new MCP server sub-schema fields (`headersHelper`, `oauth`, `transport`, `toolPolicy`, `source`); new `probeEgressHosts` IPC method. Patched patterns unchanged — no patch updates needed.
- **MCP registration:** `gpA()` → `qwA()`, registry `RL` → `MG`, labels `VJA` → `VqA`, enumerator `v7()` → `Y7()`
- **Feature flag renames:** `d_()` → `v_()`, `$yA` → `ZDA`, `yFA()` → `MW()`, `zt()` → `Pt()`, `FG()` → `fM()`
- **All 44 patches pass**, JS syntax validated

---

## 2026-04-26 — Multiple Profiles (multi-instance support)

Run several Claude Desktop windows side by side, each logged in to a different account, with fully isolated state for both Desktop and the Claude Code CLI it spawns. Closes [#58](https://github.com/patrickjaja/claude-desktop-bin/issues/58). — contributed by [@dcelasun](https://github.com/dcelasun) ([#70](https://github.com/patrickjaja/claude-desktop-bin/pull/70))

- New launcher subcommands: `--create-profile=NAME`, `--delete-profile=NAME`, `--list-profiles`
- New flags / env: `--profile=NAME`, `CLAUDE_PROFILE=NAME`, or auto-resolved from basename (`claude-desktop-work`)
- Per-profile isolation: Electron userData, Claude Code config (`~/.claude-NAME`), Quick Entry socket, systemd scope, WM_CLASS / Wayland `app_id`, XDG autostart
- Per-profile Electron binary (hardlink → reflink → copy fallback) for distinct app identity — auto-refreshed on package upgrades
- SSO callback routing via auth-marker mechanism (`fix_profile_url_routing.nim`) — multiple SSO logins work sequentially across profiles
- Profile name in window title: `Claude` → `Claude (work)` in title bar, taskbar, and Alt-Tab (`fix_profile_window_title.nim`)
- Default profile (no flag) is byte-identical to single-instance behavior — no migration needed
- New patches: `fix_profile_url_routing.nim`, `fix_profile_window_title.nim`
- Updated patches: `fix_startup_settings.nim`, `fix_quick_entry_app_id.nim`, `fix_quick_entry_cli_toggle.nim`, `fix_cowork_linux.nim`

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
