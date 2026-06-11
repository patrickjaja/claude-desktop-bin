# ion-dist Baseline - Third-Party Inference SPA

**Last verified:** 2026-06-11 against v1.12603.0 (version bump from v1.11847.5; **modest growth, no structural refactor** - 94 MB / 730 JS / 979 files / 25 CSS, up from 93 MB / 715 JS / 961 files / 23 CSS; config chunk content-hash bump `c71860c77-BBQ3iytl.js` -> `c71860c77-C2vlLTGm.js` (~313 KB, was ~280 KB; chunk family now 19 files, was 18), `mountPath` still mac/win-only (no `linux` key) so `fix_ion_dist_linux.nim` still required and both sub-patterns matched; platform-ternary vars this release `V`/`E`/`xt` (only the object var changed, `yt` -> `xt`); darwin-gated file count unchanged at 11; one new Zod config key `inferenceVertexOAuthLoginHint` (Vertex interactive OAuth login hint); the c30db9bec chunk now darwin-gates NFC path normalization (`"darwin"===process.platform?e.normalize("NFC"):e`) that was previously unconditional - Linux-friendly, no patch needed). Prior: v1.11847.5 = 93 MB / 715 JS / 961 files / 23 CSS (platform-ternary vars `V`/`E`/`yt`; `caption` key dropped from `mountPath`); v1.11187.4 = 92 MB / 706 JS / 950 files / 23 CSS (platform-ternary vars `K`/`C`/`pt`); v1.10628.2 = 90 MB / 691 JS / 909 files / 21 CSS (re-minify of v1.10628.0; major bump from v1.9659.4 = 88 MB / 682 JS / 899 files).

The `ion-dist/` directory is a standalone React SPA bundled inside `locales/ion-dist/`. It powers the **Configure Third-Party Inference** UI (Developer menu). Served by the Electron main process via the `app://` protocol handler.

## Bundle Stats

| Metric | Value |
|--------|-------|
| Total size | 94 MB (v1.12603.0; was 93 MB in v1.11847.5, 92 MB in v1.11187.4, 90 MB in v1.10628.0, 88 MB in v1.9659.4) |
| JS chunks | 730 JS total, 979 files total (v1.12603.0; was 715 JS / 961 files in v1.11847.5, 706 JS / 950 files in v1.11187.4, 691 JS / 909 files in v1.10628.0) |
| CSS | 25 files (v1.12603.0; was 23 in v1.11847.5, 21 before v1.11187.4) |
| Fonts | 31 woff2 + 21 ttf + 20 woff |
| Images | 38 PNG, 19 SVG, 17 GIF (v1.12603.0; was 37 PNG / 19 SVG / 17 GIF in v1.11847.5) |
| Audio | 25 MP3, 1 WebM, 1 MOV |
| WASM | 1 file |
| i18n | 11 languages (de, en, es, es-419, fr, hi, id, it, ja, ko, pt-BR) + `.overrides.json` sidecars + `statsig/` variants |

## Key Files

| File | Size | Role |
|------|------|------|
| `index.html` | 4.1 KB | SPA entry, loads `index-*.js` via `<script type="module">` |
| `assets/v1/index-*.js` | ~6.9 MB | Main bundle (React app, API client, UI components) |
| `assets/v1/vendor-*.js` | ~1.5 MB | Third-party vendor libs |
| `assets/v1/c71860c77-*.js` | 19 files (main: ~313 KB) | 3P config UI, code-split into lazy-loaded chunks - **main chunk patched** (v1.12603.0: `c71860c77-C2vlLTGm.js`; v1.11847.5: `c71860c77-BBQ3iytl.js`; v1.11187.4: `c71860c77-CyMvMS7K.js`; v1.10628.2: `c71860c77-CV0D52ti.js`; v1.10628.0: `c71860c77-CDhE5jkR.js`; v1.9659.1/v1.9659.2/v1.9659.4: `c71860c77-BOyfE2Py.js`; v1.9255.2: `c71860c77-DFJHDHrp.js`) |
| `assets/v1/tree-sitter-*.js` | - | Code parsing (tree-sitter WASM bindings) |

Filenames include content hashes (e.g., `index-DuIwZ1hn.js`) that change every upstream release.

## How It's Served

```
Main process (v1.8089.0 names - these change every release):
  $Mr(path.join(ljt(), "ion-dist"), rendererConfig)

ljt() → locales/ dir (patched by fix_locale_paths.nim)
$Mr()  → registers app:// protocol handler serving files from ion-dist/
```

The 3P setup window opens `app://localhost/setup-desktop-3p` in a `BrowserWindow` with `mainView.js` as preload.

## Platform Detection

The SPA receives platform from the main process via `readLocalConfig()` IPC:
```js
// Main process (v1.6608.1: KNn function - name changes every release):
{ ok: true, config: ..., source: ..., platform: process.platform, ... }
```

Platform enum in the SPA (v1.6608.1: `Y`; previously `U3`, `W` - name changes every release): `Darwin="darwin"`, `Win32="win32"`, `Linux="linux"`.

## Linux-Specific Issues (Patched)

### 1. org-plugins Mount Path

**Upstream (pre-patch):**
```js
mountPath:{mac:"/Library/Application Support/Claude/org-plugins",win:"%ProgramFiles%\\Claude\\org-plugins",caption:"..."}
```
No `linux` key. Since v1.11847.5 the `mountPath` object is `{mac,win}` (the `caption` key was dropped; was `{mac,win,caption}`); sub-patch A still anchors on the `win:` value so it is unaffected. Display component falls back with a platform ternary (variable names change every release - v1.7196.0: `r===W.Win32?t.win:t.mac`; v1.8089.0: `C===V.Win32?Ve.mountPath.win:Ve.mountPath.mac`; v1.8555.2: `C===W.Win32?Ye.mountPath.win:Ye.mountPath.mac`; v1.9659.1: `z===q.Win32?ft.mountPath.win:ft.mountPath.mac`; v1.11187.4: `K===C.Win32?pt.mountPath.win:pt.mountPath.mac`; v1.11847.5: `V===E.Win32?yt.mountPath.win:yt.mountPath.mac`; v1.12603.0: `V===E.Win32?xt.mountPath.win:xt.mountPath.mac`).

**Patched by `fix_ion_dist_linux.nim`:**
- Sub-patch A: Adds `linux:"/etc/claude-desktop/org-plugins"` to mountPath
- Sub-patch B: Changes ternary to `<platVar>===<enumVar>.Win32?<obj>.win:<platVar>===<enumVar>.Linux?<obj>.linux:<obj>.mac` (uses flexible `[\w$]+` wildcards for all variable names)

### 2. Export Formats

Export enum (`as`): `Mobileconfig`, `Reg`, `Json`, `FirewallTxt`, `ClipboardRedacted`. JSON is already available as a menu option - no patch needed. The binary export ternary (`n===as.Reg?Ne.Reg:Ne.Mobileconfig`) only applies to `.mobileconfig`/`.reg` exports.

## What's Already Linux-Compatible (No Patch Needed)

- Enterprise config: reads `/etc/claude-desktop/enterprise.json`
- User config: `~/.config/Claude-3p/claude_desktop_config.json`
- File manager text: `Y.Linux ? "Show in file manager"` (v1.6608.1; var name changes every release)
- Keyboard shortcuts: Ctrl-based when platform !== Darwin
- Platform enum includes Linux
- CLI detection: includes `cli-linux-x64` and `cli-linux-arm64`

## Patterns to Monitor on Upstream Updates

When a new version drops, re-run these checks against the fresh `ion-dist/`:

```bash
ION="$WORK_DIR/app/locales/ion-dist"

# 1. Find the patched config UI chunk (filename changes every release)
rg -l 'org-plugins' "$ION/assets/v1/"*.js

# 2. Verify org-plugins still only has mac/win (or was updated upstream)
rg -o 'mountPath:\{.{0,200}\}' "$ION/assets/v1/"*.js

# 3. Check for new platform-gated code
rg -l 'darwin' "$ION/assets/v1/"*.js | wc -l

# 4. Check for new mac/win-only paths without linux
rg -o '/Library/Application Support.{0,60}' "$ION/assets/v1/"*.js
rg -o '%ProgramFiles%.{0,60}' "$ION/assets/v1/"*.js

# 5. Verify platform enum still exists
rg -o 'Darwin="darwin".*Linux="linux"' "$ION/assets/v1/index-"*.js

# 6. Check for new IPC bridges or native calls
rg -c 'claudeAppBindings' "$ION/assets/v1/index-"*.js

# 7. Bundle size sanity check (large changes = structural refactor)
du -sh "$ION"
find "$ION" -name "*.js" | wc -l
```

If the mountPath pattern changed or new platform-gated paths appeared, update `fix_ion_dist_linux.nim` and this baseline.

## Config Key Schema

The 3P config supports these key categories (defined in the SPA's Zod schema):

- **Connection:** `inferenceProvider`, `deploymentOrganizationUuid`, `disableDeploymentModeChooser`
- **Provider credentials:** Vertex (`inferenceVertex*`), Bedrock (`inferenceBedrock*`), Foundry (`inferenceFoundry*`), Gateway (`inferenceGateway*`)
- **Credential helper:** `inferenceCredentialHelper`, `inferenceCredentialHelperTtlSec`, `inferenceCredentialHelperTimeoutSec`, `inferenceCredentialKind`, `inferenceCustomHeaders`
- **Models:** `inferenceModels` (supports `1m` context variant)
- **Sandbox:** `disabledBuiltinTools`, `allowedWorkspaceFolders`, `coworkEgressAllowedHosts`, `isClaudeCodeForDesktopEnabled`
- **Connectors:** `managedMcpServers`, `isLocalDevMcpEnabled`, `isDesktopExtensionEnabled`, `isDesktopExtensionDirectoryEnabled`, `isDesktopExtensionSignatureRequired`
- **MCP server sub-schema (new in v1.5354.0):** `headersHelper`, `headersHelperTtlSec`, `oauth` (union: boolean or {clientId, tenantId?, scope?}), `transport` (enum: "http"|"sse"), `toolPolicy` (record: tool→"allow"|"ask"|"blocked"), `source` (enum: "mdm"|"org-plugin"|"user")
- **IPC (new in v1.5354.0):** `probeEgressHosts` (egress connectivity probe)
- **Telemetry:** `disableEssentialTelemetry`, `disableNonessentialTelemetry`, `disableNonessentialServices`, `disableAutoUpdates`, `autoUpdaterEnforcementHours`
- **OTLP:** `otlpEndpoint`, `otlpProtocol`, `otlpHeaders`
- **Usage limits:** `inferenceMaxTokensPerWindow`, `inferenceTokenWindowHours`
- **Bootstrap:** `bootstrapEnabled`, `bootstrapUrl`, `bootstrapOidc`
- **Auth/Org:** `forceLoginOrgUUID`
- **Bedrock (new sub-keys):** `inferenceBedrockAwsDir`, `inferenceBedrockBearerToken`, `inferenceBedrockServiceTier` (enum: `"flex"` | `"priority"`), `inferenceBedrockSsoStartUrl`, `inferenceBedrockSsoRoleName`, `inferenceBedrockSsoRegion`, `inferenceBedrockSsoAccountId`, `inferenceBedrockBaseUrl`
- **Vertex (new sub-keys):** `inferenceVertexBaseUrl`, `inferenceVertexCredentialsFile`, `inferenceVertexOAuthClientId`, `inferenceVertexOAuthClientSecret`, `inferenceVertexOAuthScopes`, `inferenceVertexOAuthLoginHint` (new in v1.12603.0; interactive OAuth login hint, shown only when `inferenceVertexWorkforceAudience` is unset)
- **Gateway (new enum):** `inferenceGatewayAuthScheme` now supports `"sso"` (in addition to `"auto"`, `"x-api-key"`, `"bearer"`); `inferenceGatewayOidc`, `inferenceGatewayApiKey`
- **Foundry:** `inferenceFoundryApiKey`
- **OTLP (new sub-key):** `otlpResourceAttributes`
- **Cowork/Sandbox (new keys):** `requireCoworkFullVmSandbox`, `secureVmFeaturesEnabled`
- **Org banners (new in v1.8555.2):** `banner` object with `enabled` (boolean) and `text` (string) sub-keys
- **Bootstrap auth (new in v1.8555.2):** `triggerBootstrapAuth` IPC bridge method for bootstrap OIDC auth flow
