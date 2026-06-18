# Third-Party Inference on Linux

The upstream **Developer → Configure Third-Party Inference** wizard works on Linux as of v1.6259 (after the `ion-dist` packaging fix in #57). This page covers the Linux-specific bits that aren't in the [official Anthropic 3P docs](https://claude.com/docs/cowork/3p/installation) - which only cover macOS and Windows - plus the headless `/etc/claude-desktop/enterprise.json` route for fleet rollouts and remote/CI machines where the wizard isn't practical.

> **Looking for the full `enterprise.json` key reference?** This page is the Linux *how-to*. For the complete, authoritative list of every config key, see Anthropic's official docs:
> - [Configuration reference](https://claude.com/docs/cowork/3p/configuration) - every key, all providers, credential helpers, security profiles.
> - [Enterprise configuration for Claude Desktop](https://support.claude.com/en/articles/12622667-enterprise-configuration-for-claude-desktop) - managed-preferences overview.
> - [Extend Claude Cowork with third-party platforms](https://support.claude.com/en/articles/14680753-extend-claude-cowork-with-third-party-platforms) - how MCP/plugins/skills differ on 3P.

## Two routes

| Route | When to use |
|---|---|
| **In-app wizard** | Single-user laptop install. You can interactively click through provider selection and credential entry. |
| **`/etc/claude-desktop/enterprise.json`** | Fleet/MDM rollouts, headless servers, scripted provisioning, or when you want the same config reproducibly across machines. The app reads this file synchronously at startup; settings here override the wizard. |

Both routes write the same underlying schema. The wizard just builds it for you.

## Route A: in-app wizard

1. **Enable Developer Mode** (the menu item is hidden otherwise):
   - Click your avatar (bottom-left) → **Settings** → toggle **Developer Mode** on.
   - Restart Claude Desktop.
2. New top-level menu **Developer** appears. Click **Developer → Configure Third-Party Inference**.
3. Pick your provider, fill credentials, save. The wizard writes the same JSON as Route B.

If the menu item opens an empty window, you're on a build before #57 landed (`ion-dist` directory missing). Update to v1.6259+ or use Route B.

## Route B: manual `enterprise.json`

The app reads `/etc/claude-desktop/enterprise.json` on every launch. Setting `inferenceProvider` flips the app into 3P mode and bypasses the personal claude.ai sign-in flow.

### Vertex AI (verified)

Tested on Ubuntu 25.10 with v1.6259.1-1, using existing `gcloud auth application-default login` credentials (no service account file).

```bash
# 1. Make sure your gcloud ADC is in place and the project has Vertex AI access:
gcloud auth application-default login
gcloud auth application-default print-access-token   # should print a token
gcloud config get-value project                      # should print your project ID

# 2. Drop the policy file (uses ADC by default; no credential paths needed):
sudo install -d -m 755 /etc/claude-desktop
sudo tee /etc/claude-desktop/enterprise.json >/dev/null <<'JSON'
{
  "inferenceProvider": "vertex",
  "inferenceVertexProjectId": "your-gcp-project-id",
  "inferenceVertexRegion": "global",
  "inferenceModels": [
    { "name": "claude-opus-4-7", "supports1m": true },
    { "name": "claude-sonnet-4-6", "supports1m": true }
  ],
  "disableDeploymentModeChooser": true
}
JSON

# 3. Fully restart the app - config is read once at startup:
pkill -x claude-desktop 2>/dev/null
nohup claude-desktop >/dev/null 2>&1 &
```

**What each key does:**

- `inferenceProvider: "vertex"` - required. Activates 3P mode. Other valid values: `"gateway"`, `"bedrock"`, `"foundry"`.
- `inferenceVertexProjectId` - required. Your GCP project ID.
- `inferenceVertexRegion` - required. Either a GCP region (`us-east5`, `europe-west1`, …) or `"global"` for Vertex's global endpoint. Validator regex: `^([a-z]+-[a-z]+\d{1,2}|global)$`.
- `inferenceModels` - required when not using bootstrap. List of model entries shown in the picker; **first entry is the default**. Each entry is either a string (`"claude-sonnet-4-6"`) or an object (`{ "name": "claude-opus-4-7", "supports1m": true }` to enable the 1M-token context window for models that support it on Vertex).
- `disableDeploymentModeChooser: true` - optional. Hides the personal claude.ai sign-in option entirely. Recommended for 3P-only setups; omit if you want to be able to switch back.

**Authentication options** (any one):

| Option | How |
|---|---|
| Application Default Credentials *(default)* | Leave `inferenceVertexCredentialsFile` unset. The app picks up `~/.config/gcloud/application_default_credentials.json` from `gcloud auth application-default login`. |
| Service account key file | Set `inferenceVertexCredentialsFile: "/etc/claude/vertex-sa.json"` (any absolute path). |
| Vertex OAuth client (Sign-in with Google) | Set `inferenceVertexOAuthClientId` + `inferenceVertexOAuthClientSecret` + `inferenceVertexOAuthScopes`. |

### Bedrock and Foundry

Same shape as Vertex but with provider-specific keys. The full validator schema lives in `app.asar` - these keys are surfaced in the in-app wizard form, so the path of least resistance is:

1. Set `inferenceProvider: "bedrock"` (or `"foundry"`) plus the bare-minimum required keys.
2. Restart, open **Developer → Configure Third-Party Inference**, fill in the rest interactively.
3. Optionally export the resulting config and redeploy via `enterprise.json`.

Bedrock keys: `inferenceBedrockRegion`, `inferenceBedrockBearerToken`, `inferenceBedrockProfile`, `inferenceBedrockSso{StartUrl,Region,AccountId,RoleName}`, `inferenceBedrockServiceTier`.

Foundry keys: `inferenceFoundryResource`, `inferenceFoundryApiKey`.

### Gateway (LiteLLM, Portkey, in-house proxy)

```json
{
  "inferenceProvider": "gateway",
  "inferenceGatewayBaseUrl": "https://your-gateway.example.com/v1",
  "inferenceGatewayApiKey": "...",
  "inferenceGatewayAuthScheme": "bearer",
  "inferenceModels": [{ "name": "claude-sonnet-4-6" }]
}
```

`inferenceGatewayAuthScheme` accepts `"auto"`, `"x-api-key"`, `"bearer"`, or `"sso"`. For gateways that expose a `/v1/models` endpoint, `inferenceModels` is optional - the picker uses model discovery.

#### 5-minute local quickstart (LiteLLM container)

Want to see Linux 3P working end-to-end before wiring it to your real fleet gateway? Stand up a [LiteLLM](https://github.com/BerriAI/litellm) proxy locally, point Claude Desktop at it, and you'll be running Cowork + Code against your own inference endpoint in a few minutes. This is the exact shape used in production - just trimmed to Anthropic-only so it's copy-paste runnable.

**1. Minimal LiteLLM config** - `litellm_config.yaml` (Anthropic passthrough only; no secrets in the file, the key is read from the environment):

```yaml
model_list:
  # model_name MUST match the IDs in enterprise.json inferenceModels.
  # Bare aliases (no dated suffix) are valid Anthropic IDs.
  - model_name: claude-opus-4-8
    litellm_params:
      model: anthropic/claude-opus-4-8
      api_key: os.environ/ANTHROPIC_API_KEY

  - model_name: claude-sonnet-4-6
    litellm_params:
      model: anthropic/claude-sonnet-4-6
      api_key: os.environ/ANTHROPIC_API_KEY

general_settings:
  # The gateway's own bearer token. Clients (Claude Desktop) send this;
  # it is NOT your Anthropic key. Pick any strong string.
  master_key: os.environ/LITELLM_MASTER_KEY

litellm_settings:
  drop_params: true
```

**2. Run the proxy** - one container, two env vars (replace both values; nothing is persisted to the image):

```bash
docker run --rm -p 4000:4000 \
  -v "$(pwd)/litellm_config.yaml:/app/config.yaml:ro" \
  -e ANTHROPIC_API_KEY="sk-ant-…your-anthropic-key…" \
  -e LITELLM_MASTER_KEY="sk-pick-any-strong-gateway-token" \
  ghcr.io/berriai/litellm:main-stable \
  --config /app/config.yaml --port 4000

# sanity check from another terminal - should list claude-opus-4-8 / claude-sonnet-4-6:
curl -s http://127.0.0.1:4000/v1/models \
  -H "Authorization: Bearer sk-pick-any-strong-gateway-token" | python3 -m json.tool
```

**3. Point Claude Desktop at it** - `/etc/claude-desktop/enterprise.json`. The `inferenceGatewayApiKey` here is the gateway's `master_key` from step 2 (**not** your Anthropic key):

```bash
sudo install -d -m 755 /etc/claude-desktop
sudo tee /etc/claude-desktop/enterprise.json >/dev/null <<'JSON'
{
  "inferenceProvider": "gateway",
  "inferenceGatewayBaseUrl": "http://127.0.0.1:4000",
  "inferenceGatewayApiKey": "sk-pick-any-strong-gateway-token",
  "inferenceGatewayAuthScheme": "bearer",
  "inferenceModels": [
    { "name": "claude-opus-4-8" },
    { "name": "claude-sonnet-4-6" }
  ],
  "disableDeploymentModeChooser": true,
  "betaFeaturesEnabled": true,
  "chatTabEnabled": true,
  "coworkTabEnabled": true
}
JSON
sudo chmod 644 /etc/claude-desktop/enterprise.json
```

> **Surface toggles** (all `scopes:["3p"]`): `chatTabEnabled` brings back the **Chat** tab (the claude.ai web surface), `coworkTabEnabled` the **Cowork** tab, and `betaFeaturesEnabled` unlocks the beta-feature set those live under. `isClaudeCodeForDesktopEnabled` controls the **Code** tab. Omit one to hide that surface. See the [maximum example](#maximum-enterprisejson-every-key) below for the full set.

**4. Restart and verify** (see [Verifying it worked](#verifying-it-worked) for the full log signature):

```bash
pkill -x claude-desktop 2>/dev/null
nohup claude-desktop >/dev/null 2>&1 &
tail -f ~/.config/Claude/logs/main.log | grep -E 'custom-3p|account|inference'
```

You should see `[custom-3p] 3P mode active { provider: 'gateway' }` and an identity-changed line within a few seconds. Open a Cowork or Code session and confirm the model picker shows your two models.

> **Don't commit your real values.** `inferenceGatewayApiKey` and `ANTHROPIC_API_KEY` are credentials - keep them in `enterprise.json` / env only. The redacted placeholders above are intentional. LiteLLM reads every secret from the environment (`os.environ/…`), so the config file itself is safe to check into a repo.

> **Beyond Anthropic:** LiteLLM can front Bedrock, Vertex, Azure, or any OpenAI-/Anthropic-compatible upstream - swap the `model_list` block and keep `enterprise.json` identical. That's the point of the gateway provider: one stable client config, any backend behind it.

## Maximum `enterprise.json` (every key)

The quickstart above is intentionally minimal. Below is a **feature-complete** gateway config that turns on every surface and shows the governance, telemetry, sandbox, and plugin knobs an enterprise rollout typically wants. Every key here is a real managed-config setting in v1.14271.0 (`scopes:["3p"]` or `["3p","1p"]`); add only the ones you need. Keys marked **secret** must hold real credentials - keep this file readable only as needed and never commit real values.

```jsonc
{
  // ── Inference backend (pick ONE provider; gateway shown) ────────────────
  "inferenceProvider": "gateway",                 // anthropic | gateway | bedrock | vertex | foundry
  "inferenceGatewayBaseUrl": "http://127.0.0.1:4000",
  "inferenceGatewayApiKey": "sk-your-gateway-token",   // secret
  "inferenceGatewayAuthScheme": "bearer",         // auto | x-api-key | bearer | sso
  "inferenceModels": [
    // For providers with their own model IDs (Bedrock profiles, gateway aliases),
    // set anthropicFamilyTier so the app knows which Claude tier the ID maps to.
    { "name": "claude-opus-4-8",   "anthropicFamilyTier": "opus",   "supports1m": true },
    { "name": "claude-sonnet-4-6", "anthropicFamilyTier": "sonnet", "supports1m": true }
  ],
  "modelDiscoveryEnabled": false,                 // true = pull model list from the gateway's /v1/models
  "inferenceCustomHeaders": { "x-tenant": "acme" },    // extra headers on every inference request
  "disableDeploymentModeChooser": true,           // lock to 3P; hide personal claude.ai sign-in

  // ── Surfaces / tabs ─────────────────────────────────────────────────────
  "betaFeaturesEnabled": true,                    // unlocks the beta-feature set below
  "chatTabEnabled": true,                         // the Chat tab (claude.ai web surface)
  "coworkTabEnabled": true,                       // the Cowork tab
  "isClaudeCodeForDesktopEnabled": true,          // the Code tab (Claude Code)
  "chatAdvancedFileAnalysisEnabled": true,        // code-execution / advanced file analysis in Chat
  "autoModeEnabled": true,                        // allow Cowork "Auto" mode
  "claudeAiImport": true,                         // allow importing claude.ai data

  // ── MCP, plugins, extensions ────────────────────────────────────────────
  "managedMcpServers": [
    { "name": "atlassian-rovo", "transport": "http", "url": "https://mcp.atlassian.com/v1/mcp/authv2" }
  ],
  "organizationPluginsUrl": "https://plugins.acme.example/registry",  // org plugin/skill registry
  "isDesktopExtensionEnabled": true,
  "isDesktopExtensionSignatureRequired": true,    // only load signed extensions

  // ── Sandbox / workspace / egress (governance) ───────────────────────────
  "allowedWorkspaceFolders": ["/home", "/srv/projects"],   // restrict where sessions may operate
  "coworkEgressAllowedHosts": ["api.acme.example", "github.com"],  // network allowlist for Cowork
  "disabledBuiltinTools": [],                     // e.g. ["computer-use"] to block desktop control

  // ── Identity ────────────────────────────────────────────────────────────
  "deploymentOrganizationUuid": "00000000-0000-0000-0000-000000000000",

  // ── Updates ─────────────────────────────────────────────────────────────
  "disableAutoUpdates": false,
  "autoUpdaterEnforcementHours": 72,              // force an update after N hours

  // ── Telemetry (OpenTelemetry; all optional) ─────────────────────────────
  "otlpEndpoint": "https://otel.acme.example:4318",
  "otlpProtocol": "http/protobuf",                // grpc | http/protobuf
  "otlpHeaders": { "authorization": "Bearer <otel-token>" },   // secret
  "otlpResourceAttributes": { "service.name": "claude-desktop", "deployment.environment": "prod" },
  "otlpDesktopLogLevel": "info",

  // ── Usage limits (3P) ───────────────────────────────────────────────────
  "inferenceMaxTokensPerWindow": 2000000,
  "inferenceTokenWindowHours": 24,
  "inferenceSessionLifetimeSec": 28800
}
```

> `jsonc` (comments) is shown for readability - **strip the comments** before deploying; the file must be valid JSON. A few keys are `scopes:["1p"]`-only (claude.ai login deployments) and are therefore **not** valid in a 3P/gateway file: `requireCoworkFullVmSandbox`, `secureVmFeaturesEnabled`, `forceLoginOrgUUID`, `loginSsoOrgDomain`. For provider-specific blocks (Bedrock SSO, Vertex OAuth/workforce, Foundry tenant) and the exact accepted values of every key, see the [official configuration reference](https://claude.com/docs/cowork/3p/configuration).

**Switching the provider block:** keep everything from "Surfaces" down identical and replace only the inference block:

| Provider | Minimum required keys |
|---|---|
| **gateway** | `inferenceGatewayBaseUrl`, `inferenceGatewayApiKey`, `inferenceGatewayAuthScheme` |
| **vertex** | `inferenceVertexProjectId`, `inferenceVertexRegion` (+ ADC or `inferenceVertexCredentialsFile`) |
| **bedrock** | `inferenceBedrockRegion` + one auth: `inferenceBedrockBearerToken` *or* `inferenceBedrockProfile` *or* `inferenceBedrockSso{StartUrl,Region,AccountId,RoleName}` |
| **foundry** | `inferenceFoundryResource`, `inferenceFoundryApiKey` (or `inferenceFoundryTenantId` + `inferenceFoundryClientId`) |
| **anthropic** | `inferenceAnthropicApiKey` (direct to api.anthropic.com) |

For credential rotation without static keys, all providers support an external helper: `inferenceCredentialHelper` (+ `inferenceCredentialHelperTtlSec`, `inferenceCredentialHelperTimeoutSec`, `inferenceCredentialHelperSilentRefreshEnabled`).

## Verifying it worked

After restart, tail the log:

```bash
tail -f ~/.config/Claude/logs/main.log | grep -E 'custom-3p|account|inference'
```

You should see (within a few seconds of launch):

```
[custom-3p] Credentials loaded from enterprise config { provider: 'vertex', mcpServerCount: 0 }
[custom-3p] 3P mode active { provider: 'vertex' }
[custom-3p] Model discovery: not supported by provider; picker = 2 (inferenceModels)
[custom-3p] deploymentMode written { mode: '3p' }
[account] Identity changed (loggedOut: true → false, uuid: <none> → <uuid>)
```

If you see `[oauth] failed to obtain oauth token … Pro or Max subscription`, the policy file didn't load - most likely a JSON parse error. Validate it:

```bash
python3 -c 'import json; json.load(open("/etc/claude-desktop/enterprise.json"))'
```

## Common gotchas

- **The file must be readable by your user.** `install -m 644` (used above) is correct. `chmod 600` will silently make Claude fall back to the default config.
- **The app caches the deployment mode** in `~/.config/Claude/Local State` after the first 3P launch. If you remove `enterprise.json` later, the app may stay in 3P mode until you also clear that cache.
- **`global` region requires Vertex's global endpoint to be enabled** for your project - newer projects have this on by default; older ones may need to be enabled in the Cloud Console under Vertex AI Studio settings.
- **`sqlite3` is needed for project detection.** Unrelated to 3P, but if you hit `[detectedProjects] spawn /usr/bin/sqlite3 ENOENT` in the logs, `apt install sqlite3` clears it.
