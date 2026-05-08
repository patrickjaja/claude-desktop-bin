# Third-Party Inference on Linux

The upstream **Developer → Configure Third-Party Inference** wizard works on Linux as of v1.6259 (after the `ion-dist` packaging fix in #57). This page covers the Linux-specific bits that aren't in the [official Anthropic 3P docs](https://claude.com/docs/cowork/3p/installation) — which only cover macOS and Windows — plus the headless `/etc/claude-desktop/enterprise.json` route for fleet rollouts and remote/CI machines where the wizard isn't practical.

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

# 3. Fully restart the app — config is read once at startup:
pkill -x claude-desktop 2>/dev/null
nohup claude-desktop >/dev/null 2>&1 &
```

**What each key does:**

- `inferenceProvider: "vertex"` — required. Activates 3P mode. Other valid values: `"gateway"`, `"bedrock"`, `"foundry"`.
- `inferenceVertexProjectId` — required. Your GCP project ID.
- `inferenceVertexRegion` — required. Either a GCP region (`us-east5`, `europe-west1`, …) or `"global"` for Vertex's global endpoint. Validator regex: `^([a-z]+-[a-z]+\d{1,2}|global)$`.
- `inferenceModels` — required when not using bootstrap. List of model entries shown in the picker; **first entry is the default**. Each entry is either a string (`"claude-sonnet-4-6"`) or an object (`{ "name": "claude-opus-4-7", "supports1m": true }` to enable the 1M-token context window for models that support it on Vertex).
- `disableDeploymentModeChooser: true` — optional. Hides the personal claude.ai sign-in option entirely. Recommended for 3P-only setups; omit if you want to be able to switch back.

**Authentication options** (any one):

| Option | How |
|---|---|
| Application Default Credentials *(default)* | Leave `inferenceVertexCredentialsFile` unset. The app picks up `~/.config/gcloud/application_default_credentials.json` from `gcloud auth application-default login`. |
| Service account key file | Set `inferenceVertexCredentialsFile: "/etc/claude/vertex-sa.json"` (any absolute path). |
| Vertex OAuth client (Sign-in with Google) | Set `inferenceVertexOAuthClientId` + `inferenceVertexOAuthClientSecret` + `inferenceVertexOAuthScopes`. |

### Bedrock and Foundry

Same shape as Vertex but with provider-specific keys. The full validator schema lives in `app.asar` — these keys are surfaced in the in-app wizard form, so the path of least resistance is:

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

`inferenceGatewayAuthScheme` accepts `"auto"`, `"x-api-key"`, `"bearer"`, or `"sso"`. For gateways that expose a `/v1/models` endpoint, `inferenceModels` is optional — the picker uses model discovery.

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

If you see `[oauth] failed to obtain oauth token … Pro or Max subscription`, the policy file didn't load — most likely a JSON parse error. Validate it:

```bash
python3 -c 'import json; json.load(open("/etc/claude-desktop/enterprise.json"))'
```

## Common gotchas

- **The file must be readable by your user.** `install -m 644` (used above) is correct. `chmod 600` will silently make Claude fall back to the default config.
- **The app caches the deployment mode** in `~/.config/Claude/Local State` after the first 3P launch. If you remove `enterprise.json` later, the app may stay in 3P mode until you also clear that cache.
- **`global` region requires Vertex's global endpoint to be enabled** for your project — newer projects have this on by default; older ones may need to be enabled in the Cloud Console under Vertex AI Studio settings.
- **`sqlite3` is needed for project detection.** Unrelated to 3P, but if you hit `[detectedProjects] spawn /usr/bin/sqlite3 ENOENT` in the logs, `apt install sqlite3` clears it.
