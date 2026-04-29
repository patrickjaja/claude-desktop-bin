# ion-dist Baseline — Third-Party Inference SPA

**Last verified:** 2026-04-29 against v1.5354.0

The `ion-dist/` directory is a standalone React SPA bundled inside `locales/ion-dist/`. It powers the **Configure Third-Party Inference** UI (Developer menu). Served by the Electron main process via the `app://` protocol handler.

## Bundle Stats

| Metric | Value |
|--------|-------|
| Total size | 105 MB, 1612 files |
| JS chunks | 660 files in `assets/v1/` |
| CSS | 22 files |
| Fonts | 31 woff2 + 21 ttf + 20 woff |
| Images | 25 PNG, 18 SVG, 17 GIF |
| Audio | 25 MP3, 1 WebM, 1 MOV |
| WASM | 1 file |
| i18n | 11 languages (de, en, es, es-419, fr, hi, id, it, ja, ko, pt-BR) + `.overrides.json` sidecars + `statsig/` variants |

## Key Files

| File | Size | Role |
|------|------|------|
| `index.html` | 3.7 KB | SPA entry, loads `index-*.js` via `<script type="module">` |
| `assets/v1/index-*.js` | ~7.9 MB | Main bundle (React app, API client, UI components) |
| `assets/v1/vendor-*.js` | ~1.5 MB | Third-party vendor libs |
| `assets/v1/c71860c77-*.js` | 12 files (main: ~223 KB) | 3P config UI, code-split into 12 lazy-loaded chunks — **main chunk patched** |
| `assets/v1/tree-sitter-*.js` | — | Code parsing (tree-sitter WASM bindings) |

Filenames include content hashes (e.g., `index-BNbM_KX7.js`) that change every upstream release.

## How It's Served

```
Main process (v1.3883.0 names — these change every release):
  $Mr(path.join(ljt(), "ion-dist"), rendererConfig)

ljt() → locales/ dir (patched by fix_locale_paths.nim)
$Mr()  → registers app:// protocol handler serving files from ion-dist/
```

The 3P setup window opens `app://localhost/setup-desktop-3p` in a `BrowserWindow` with `mainView.js` as preload.

## Platform Detection

The SPA receives platform from the main process via `readLocalConfig()` IPC:
```js
// Main process (v1.3883.0: KNn function — name changes every release):
{ ok: true, config: ..., source: ..., platform: process.platform, ... }
```

Platform enum in the SPA (`U3`): `Darwin="darwin"`, `Win32="win32"`, `Linux="linux"`.

## Linux-Specific Issues (Patched)

### 1. org-plugins Mount Path

**Upstream (pre-patch):**
```js
mountPath:{mac:"/Library/Application Support/Claude/org-plugins",win:"%ProgramFiles%\\Claude\\org-plugins",caption:"..."}
```
No `linux` key. Display component falls back: `r===X.Win32?t.win:t.mac`.

**Patched by `fix_ion_dist_linux.nim`:**
- Adds `linux:"/etc/claude-desktop/org-plugins"` to mountPath
- Changes ternary to `r===X.Win32?t.win:r===X.Linux?t.linux:t.mac`

### 2. Export Formats

Export enum (`An`): `Mobileconfig`, `Reg`, `Json`, `FirewallTxt`, `ClipboardRedacted`. JSON is already available as a menu option — no patch needed. The binary export ternary (`n===An.Reg?pe.Reg:pe.Mobileconfig`) only applies to `.mobileconfig`/`.reg` exports.

## What's Already Linux-Compatible (No Patch Needed)

- Enterprise config: reads `/etc/claude-desktop/enterprise.json`
- User config: `~/.config/Claude-3p/claude_desktop_config.json`
- File manager text: `W.Linux ? "Show in file manager"`
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
- **Credential helper:** `inferenceCredentialHelper`, `inferenceCredentialHelperTtlSec`
- **Models:** `inferenceModels` (supports `1m` context variant)
- **Sandbox:** `disabledBuiltinTools`, `allowedWorkspaceFolders`, `coworkEgressAllowedHosts`, `isClaudeCodeForDesktopEnabled`
- **Connectors:** `managedMcpServers`, `isLocalDevMcpEnabled`, `isDesktopExtensionEnabled`, `isDesktopExtensionDirectoryEnabled`, `isDesktopExtensionSignatureRequired`
- **MCP server sub-schema (new in v1.5354.0):** `headersHelper`, `headersHelperTtlSec`, `oauth` (union: boolean or {clientId, tenantId?, scope?}), `transport` (enum: "http"|"sse"), `toolPolicy` (record: tool→"allow"|"ask"|"blocked"), `source` (enum: "mdm"|"org-plugin"|"user")
- **IPC (new in v1.5354.0):** `probeEgressHosts` (egress connectivity probe)
- **Telemetry:** `disableEssentialTelemetry`, `disableNonessentialTelemetry`, `disableNonessentialServices`, `disableAutoUpdates`, `autoUpdaterEnforcementHours`
- **OTLP:** `otlpEndpoint`, `otlpProtocol`, `otlpHeaders`
- **Usage limits:** `inferenceMaxTokensPerWindow`, `inferenceTokenWindowHours`
