---
name: 3p
description: Reference for the 3p / enterprise / inference-gateway deployment of Claude Desktop on Linux - how /etc/claude-desktop/enterprise.json is read, what "3p mode" changes (separate ~/.config/Claude-3p userData, hidden Chat tab, the false VM-download banner), how Cowork still runs natively under it, which hardcoded paths are safe vs split under the -3p switch, and how to verify it all from logs. Use when working on enterprise.json, inferenceProvider/gateway/Bedrock/Vertex configs, the 3p setup SPA (ion-dist), the Claude-3p directory, or debugging managed-deployment Cowork.
when_to_use: When the user mentions enterprise.json, managed/MDM config, 3p / third-party deployment, inferenceProvider (gateway/bedrock/vertex/foundry/mantle), an inference gateway / LiteLLM, the Claude-3p config dir, the "Download a one-time package" banner, deploymentMode, the 3P setup window, or edits fix_enterprise_config_linux / fix_marketplace_linux / fix_ion_dist_linux / fix_cowork_download_status_linux.
paths: patches/fix_enterprise_config_linux.nim, patches/fix_marketplace_linux.nim, patches/fix_ion_dist_linux.nim, patches/fix_cowork_download_status_linux.nim, baseline/ION.md
---

# 3p / enterprise / inference-gateway deployment on Linux

"3p" = **third-party / managed deployment**: Claude Desktop pointed at a non-Anthropic inference
backend (Bedrock, Vertex, Azure, or a self-hosted **gateway** like LiteLLM) and/or an MDM-managed config.
On Linux it is driven by `/etc/claude-desktop/enterprise.json` (injected by `fix_enterprise_config_linux`).
Minified names below are version-specific (they churn every release - see `/linux`); anchor on stable
strings. Verified against v1.14271.0.

## enterprise.json (`/etc/claude-desktop/enterprise.json`)

Read by `fix_enterprise_config_linux.nim` (replaces upstream's win32-registry/macOS-plist reader with a
Linux JSON file reader; also promotes the upstream "Enterprise config loaded" log debug->info). Schema is
documented in memory `project_enterprise_json_schema` - the load-bearing facts:
- Top-level **`managedMcpServers`** is an **array** (`name`+`transport`+`url`/`command`), NOT an object-keyed
  `mcpServers` map (that is silently dropped by the schema parser - no warning).
- Inference-gateway keys: `inferenceProvider` (`"gateway"`/`"bedrock"`/`"vertex"`/…), `inferenceGatewayBaseUrl`,
  `inferenceGatewayApiKey`, `inferenceGatewayAuthScheme`, `inferenceModels` (array; first is default),
  `disableDeploymentModeChooser:true`.
- **Any** of `inferenceProvider` / `bootstrapUrl` present + (`disableDeploymentModeChooser` OR persisted
  `deploymentMode!=="1p"`) flips the app into 3p mode.

## What "3p mode" changes (all upstream behavior, not our patches)

| Effect | Why | Our stance |
|---|---|---|
| **userData -> `~/.config/Claude-3p/`** | Upstream `setPath("userData", base+"-3p")` at bootstrap (`index.pre.js`), guarded by `!process.env.CLAUDE_USER_DATA_DIR`. Logs `[custom-3p] ...`. | **Intended** - isolates 1p login from 3p. Keep it. (To collapse: export `CLAUDE_USER_DATA_DIR` in the launcher - it short-circuits the suffix. Not done by default.) |
| **Chat tab hidden** | `chatTabEnabled:A=>A.chatTabEnabled===!0` (strict; default off in 3p). Cowork/Code stay (`!==!1`). | **Intended.** To restore: add `"chatTabEnabled": true` to enterprise.json (config-only, no patch). |
| **"Download a one-time package" banner** | `getDownloadStatus()` -> `NotDownloaded` because the local VM-image check (`claudevm.bundle`) never matches on Linux. Banner copy is remote claude.ai. | **Patched** - `fix_cowork_download_status_linux` (Linux native -> `Ready`). See below. |
| **3P setup SPA** at `app://localhost/setup-desktop-3p` | The ion-dist config UI. | `fix_ion_dist_linux` + `fix_marketplace_linux`. Config-key schema in `baseline/ION.md`. |

`[custom-3p]` in `main.log` is **upstream's own** log namespace (0 hits in our patches) - do not mistake it
for a patch tag.

## Cowork under 3p: works natively, same as 1p

A gateway/3p deployment runs Cowork over **claude-cowork-service** exactly like 1p - the native socket path
is provider-agnostic (`js/cowork_mode_preamble.js` + `fix_cowork_linux`). Confirmed end-to-end: under an
active gateway `enterprise.json`, sessions spawn the host `claude` CLI and `Turn succeeded`. The 3p OAuth
bounce (issue #142 / `session_stale_relogin`) only fires for a genuinely broken token; a logged-in account
with credits + valid Anthropic models does **not** bounce. (Provider model names matter: `inferenceModels`
must be Anthropic models or the config-health gate reports `config_model_rejected`. A `gpt-*` entry, or no
credits -> `billing_error`, makes a *turn* fail and looks like a bounce - it is not.)

### `fix_cowork_download_status_linux.nim` (the banner fix)
Rewrites `getDownloadStatus(){return <dl>?<E>.Downloading:<rdy>?<E>.Ready:<E>.NotDownloaded}` so that on
**Linux native** it returns `<E>.Ready`; win32/darwin **and Linux-KVM** keep the original `claudevm.bundle`
check (KVM genuinely needs the guest image). Gated on `process.platform==="linux"&&!globalThis.__coworkKvmMode`
(the KVM flag the cowork preamble sets). **Not 3p-specific** - a plain 1p Linux native user hits the same
false banner; it is gated on platform+backend, not deployment.

## Does the `Claude-3p` split break anything? (hardcoded-path audit, verified)

**No load-bearing path breaks.** State *isolates* between `Claude` (1p) and `Claude-3p` (3p) by design;
nothing crashes or cross-leaks. Rules:
- **Sockets/markers** (cowork, quick-entry, SSO-callback) live in `$XDG_RUNTIME_DIR` (+`CLAUDE_PROFILE`),
  not `.config` -> **unaffected** by the userData switch. App and daemon compute the cowork socket
  identically from `XDG_RUNTIME_DIR`.
- **All Electron userData** (sessions, logs, `claude_desktop_config.json`, custom-themes JSON, screenshot
  restore-token) goes through `app.getPath("userData")`, which **auto-relocates** to `Claude-3p`. So it
  *follows* the split (e.g. a custom-theme set in 1p won't carry into 3p - cosmetic only).
- **CLI config** uses `CLAUDE_CONFIG_DIR` (launcher); **autostart** `.desktop` files live in the XDG
  `~/.config/autostart/` spec dir and are `CLAUDE_PROFILE`-aware - both correctly **not** tied to the
  `-3p` userData.
- **The rule for new patches:** write user state via `app.getPath("userData")` (auto-isolates), never a
  literal `os.homedir()+"/.config/Claude"`. The Python screenshot fallback `~/.config/Claude/...` in
  `js/cu_linux_executor.js` is dead code (the JS always passes the real `getPath` value via
  `CLAUDE_PORTAL_TOKEN_PATH`) - harmless, but don't copy that pattern.

## Verify it loaded / works (logs at `~/.config/Claude-3p/logs/`)

**Note the dir: 3p logs to `~/.config/Claude-3p/`, NOT `~/.config/Claude/`.** Reading the wrong dir gives
stale/1p evidence.
```bash
L=~/.config/Claude-3p/logs/main.log
rg -a 'Enterprise config loaded|custom-3p\] (3P mode active|Credentials loaded|ConfigHealth)' "$L" | tail
# healthy gateway:  [custom-3p] ConfigHealth recomputed { state: 'healthy', provider: 'gateway' }
rg -a 'LocalAgentModeSessions.start|Turn succeeded|cycle_health|session_stale_relogin|config_model_rejected|billing_error' "$L" | tail
# Cowork native spawn proof:
rg -a 'Using Claude VM spawn|Spawn succeeded|claude-cowork|mode=native' ~/.config/Claude-3p/logs/cowork_vm_node.log | tail
```

## Related
- `baseline/ION.md` - 3P setup SPA bundle, patched patterns, config-key schema (`inferenceProvider`,
  `deploymentOrganizationUuid`, …) and the `~/.config/Claude-3p/claude_desktop_config.json` path.
- memory `project_enterprise_json_schema` - the exact enterprise.json shape + how to confirm it loaded.
- memory `issue142_cowork_3p_oauth_regression` - the OAuth-bounce mechanism (only bites a broken token).
