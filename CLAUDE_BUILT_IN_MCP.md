# Built-in MCP Servers — Claude Desktop v1.5354.0

Claude Desktop registers internal MCP servers via a two-layer architecture:

1. **Renderer-facing layer (`FpA()`)** — servers accessible from the BrowserView via Electron `MessageChannelMain` ports
2. **Backend/session layer** — servers providing tools to CCD/Cowork sessions

A server may appear in both layers (e.g., Chrome, mcp-registry) or only one.

## Registration System

```
qwA(serverName, displayLabel, factoryFn)   // v1.5354.0 (was gpA() in v1.3561.0, DfA() in v1.3109.0, kce() in v1.3036.0)
```

- Lazy singleton factory per server name; stored in `MG` (registry) + `VqA` (display labels)
- UUID display label sent to renderer for identification
- `Y7()` enumerates registered server names via `Object.keys(MG)`

## Renderer-Facing Servers (via `qwA()`)

### 1. Claude in Chrome

| Field | Value |
|-------|-------|
| Server name | `"Claude in Chrome"` |
| Platform | All (socket path adapts per OS) |
| Gating | `chromeExtensionEnabled` preference (default: `true`) |

Communicates with the Chrome browser extension via Unix socket at `/tmp/claude-mcp-browser-bridge-<username>/0.sock`.

**Tools (20):**

| Tool | Description |
|------|-------------|
| `javascript_tool` | Execute JS in page context |
| `read_page` | Accessibility tree of page elements |
| `find` | Find elements by natural language |
| `form_input` | Set form element values by ref |
| `computer` | Mouse/keyboard + screenshots (browser-level) |
| `navigate` | Navigate to URL or go back/forward |
| `resize_window` | Resize browser window |
| `gif_creator` | Record and export browser action GIFs |
| `upload_image` | Upload screenshot/image to file input or drop target |
| `get_page_text` | Extract raw text from page |
| `read_console_messages` | Read browser console messages |
| `read_network_requests` | Read HTTP network requests |
| `shortcuts_list` | List available shortcuts/workflows |
| `shortcuts_execute` | Execute a shortcut/workflow |
| `file_upload` | Upload local files to file input |
| `switch_browser` | Switch which Chrome to control (only with bridge config) |
| `tabs_context_mcp` | Get tab group context and tab IDs |
| `tabs_create_mcp` | Create new tab in MCP tab group |
| `tabs_close_mcp` | Close a tab in MCP tab group |
| `update_plan` | Update a plan in the chat UI |

### 2. MCP Registry

| Field | Value |
|-------|-------|
| Server name | `"mcp-registry"` |
| Platform | All |
| Gating | Always enabled |

The `gpA()` registration is a **stub returning no tools**. Actual tools are provided via the backend session layer.

**Tools (via P8t):**

| Tool | Description |
|------|-------------|
| `search_mcp_registry` | Search for available connectors by keywords |
| `suggest_connectors` | Display connector suggestions with Connect buttons |

### 3. Office Add-in

| Field | Value |
|-------|-------|
| Server name | `"office-addin"` |
| Platform | macOS and Windows only |
| Gating | Triple gate: `(macOS \|\| Windows) && louderPenguinEnabled && serverFlag(4116586025)` |

Currently **disabled in production** — requires both a preference toggle and a server-side experiment flag.

Communicates via WebSocket to `wss://localhost:8766` (configurable via `OFFICE_ADDIN_BRIDGE_URL`).

**Tools (5):**

| Tool | Description |
|------|-------------|
| `list_connected_workbooks` | List Excel workbooks connected via Claude add-in |
| `office_addin_run` | Execute Office.js code in Excel |
| `office_addin_get_context` | Fetch spreadsheet context: selection, sheets, changes |
| `open_office_file` | Open an Office file and the Claude add-in panel |
| `close_office_file` | Close a currently open Office file |

## Backend-Only Servers (not registered via `qwA()`)

These are accessible to CCD/Cowork sessions but not directly from the renderer.

### 4. Plugins

| Field | Value |
|-------|-------|
| Server name | `"plugins"` |
| Gating | Always enabled |

| Tool | Description |
|------|-------------|
| `suggest_plugin_install` | Suggest plugins for the user to install |
| `search_plugins` | Search available plugins |

### 5. Visualize (Imagine)

| Field | Value |
|-------|-------|
| Server name | `"visualize"` (variable `wgi`) |
| Factory | `bgi()` via `getImagineServerDef` |
| Gating | GrowthBook flag `3444158716` + Cowork session only |
| Platform | All (no platform gate) |
| Linux status | **Enabled** via `fix_imagine_linux.nim` — forces flag `3444158716` to bypass GrowthBook |
| Resource URI | `ui://imagine/show-widget.html` |

Renders inline SVG graphics, HTML diagrams, charts, mockups, data visualizations, and elicitation forms directly in the chat UI. Uses a sandboxed iframe renderer with CSP allowing `esm.sh`, `cdnjs.cloudflare.com`, `cdn.jsdelivr.net`, `unpkg.com`.

| Tool | Description |
|------|-------------|
| `show_widget` | Render SVG or HTML content inline. Input: `{loading_messages: string[], title: string, widget_code: string}`. Returns static confirmation text. `widget_code` can be raw SVG (starts with `<svg>`) or HTML (no DOCTYPE/html/head/body). CSS variables available for theming. Scripts run after streaming completes. |
| `read_me` | Returns CSS variables, colors, typography, layout rules, and module-specific guidance for widget rendering. Input: `{modules?: ["diagram"|"mockup"|"interactive"|"data_viz"|"art"|"chart"|"elicitation"][]}`. Read-only (`annotations:{readOnlyHint:true}`). |

**Modules:** diagram (SVG flowcharts/graphs), mockup (UI layouts), interactive (dynamic widgets), data_viz (Chart.js + D3 choropleths), art (illustrations), chart (data charts), elicitation (forms with `.elicit-*` classes, pills, file upload).

**System prompt:** The `imagineSystemPrompt` field comes from the claude.ai backend during session creation. When present AND the flag is enabled, it's injected into the cowork session system prompt. If the backend doesn't send it (depends on account tier/rollout), the tools still appear and work — the model just doesn't get the specialized rendering instructions.

**`sendPrompt(text)`:** Global JS function available inside widgets that sends a message to chat as if the user typed it.

### 6. Claude Preview

| Field | Value |
|-------|-------|
| Server name | `"Claude Preview"` (constant `lNe`) |
| Gating | Server flag `2976814254` + CCD session + `launchEnabled` preference (default: `true`) |
| Platform | All (no platform gate) |
| Linux status | **Not implemented** — server flag `2976814254` is not force-enabled by our patches. The feature works architecturally (no platform blocks), but is waiting for Anthropic to enable the flag server-side. |

Local dev server manager + browser inspector. Lets the model start dev servers, take screenshots, inspect DOM elements, fill forms, click buttons, run JS, and monitor logs/network — all without the user switching windows.

**How it works:**

1. **Configuration:** User creates `.claude/launch.json` in the project root:
   ```json
   {
     "version": "0.0.1",
     "configurations": [
       {
         "name": "frontend",
         "runtimeExecutable": "npm",
         "runtimeArgs": ["run", "dev"],
         "port": 3000,
         "autoPort": true
       }
     ]
   }
   ```
2. **Activation:** When `launchEnabled` is on and the server flag is active, the session system prompt gets a `<preview_tools>` block injected telling the model to use `preview_*` tools instead of Bash for running servers.
3. **Model calls `preview_start`:** Desktop reads `.claude/launch.json`, spawns the configured command as a child process, polls the port until HTTP responds.
4. **Preview panel:** An Electron `WebContentsView` (sandboxed, localhost-only) loads `http://localhost:<port>`. Chrome DevTools Protocol (CDP) is connected for automation.
5. **Feedback loop:** Model edits source code, reloads via `preview_eval`, verifies changes via screenshot/snapshot/inspect, reports back with visual proof.

The preview panel blocks all navigation to non-localhost URLs.

**Tools (13):**

Server management (no timeout):

| Tool | Description |
|------|-------------|
| `preview_start` | Start a dev server by name from `.claude/launch.json`. Reuses if already running |
| `preview_stop` | Stop a running server |
| `preview_list` | List running servers and their IDs |
| `preview_logs` | Server stdout/stderr output (build errors, debug). Filterable by level/search |
| `preview_console_logs` | Browser console output (log/warn/error). Filterable by level |

Browser interaction (30-second timeout each):

| Tool | Description |
|------|-------------|
| `preview_screenshot` | Take JPEG screenshot of the page (layout check, not precise style verification) |
| `preview_snapshot` | Accessibility tree snapshot — text content, roles, element UIDs. Preferred over screenshot |
| `preview_inspect` | Inspect DOM element by CSS selector — computed styles, bounding box, className |
| `preview_click` | Click element by CSS selector. Supports double-click |
| `preview_fill` | Fill input/textarea/select by CSS selector and value |
| `preview_eval` | Execute JS in page context — debugging/inspection only, not for UI changes |
| `preview_network` | List network requests or inspect a response body by requestId |
| `preview_resize` | Resize viewport — presets (mobile/tablet/desktop), custom dimensions, dark mode emulation |

### 7. Terminal

| Field | Value |
|-------|-------|
| Server name | `"terminal"` (constant `Egi`) |
| Factory | `xgi()` via `getTerminalServerDef` |
| Platform | **All** (macOS, Windows, Linux) — upstream uses `bfA` (darwin\|\|win32 only), but `fix_dispatch_linux.nim` patches it to include Linux |
| Gating | `t.sessionType === "ccd"` AND `bfA` platform check AND server flag `397125142` |
| Session types | **CCD only** — NOT available in Cowork sessions. The `sessionType==="ccd"` check is hardcoded in `isEnabled` |
| Backend | `node-pty` — spawns a PTY shell, streams output to xterm.js terminal panel in the UI |
| Linux status | **Works** — `bfA` patched by `fix_dispatch_linux.nim`, node-pty rebuilt from source by `build-patched-tarball.sh` |

| Tool | Description |
|------|-------------|
| `read_terminal` | Read the last ~200 lines of the integrated terminal panel (ANSI codes stripped). Use when the user references test output, errors, or logs visible in their terminal. Returns error if terminal panel is not open |

**Why not in Cowork?** In Cowork sessions, the model has `mcp__workspace__bash` which runs shell commands directly on the host (on Linux — no sandbox). This is strictly more powerful than `read_terminal` (which can only *read* the terminal panel, not execute commands). The terminal server is designed for CCD sessions where the model observes a user-controlled terminal rather than running its own commands.

**node-pty dependency:** The terminal backend requires `node-pty` to spawn PTY processes. Upstream ships only Windows PE32+ binaries. The build script rebuilds node-pty from npm source against Electron headers via `@electron/rebuild`. If the rebuild fails (logged as warning), the terminal panel and `read_terminal` tool are unavailable but Claude Desktop runs normally.

### 8. Cowork Onboarding

| Field | Value |
|-------|-------|
| Server name | `"cowork-onboarding"` |
| Gating | Cowork session + GrowthBook flag `2114777685` |
| Added in | v1.1062.0 |

Renders an interactive role-picker UI during Cowork onboarding so the user can select their job function and get a matching plugin installed.

| Tool | Description |
|------|-------------|
| `show_onboarding_role_picker` | Render a clickable role-picker chip row during Cowork onboarding. Call this when asking the user what kind of work they do so they can pick their role and get a matching plugin installed. The role list is hardcoded in the frontend — call with no args. |

**Restrictions:** Added to `BRIDGE_DISALLOWED_TOOLS` (disabled in dispatch-child sessions) and disabled for scheduled tasks.

### 9. Dev Debug

| Field | Value |
|-------|-------|
| Server name | `"dev-debug"` |
| Gating | Cowork session only |

| Tool | Description |
|------|-------------|
| `get_roots` | Get MCP roots |

### 10. Radar

| Field | Value |
|-------|-------|
| Server name | `"radar"` |
| Gating | Dynamically enabled per-session via `YKt` Map; server registration has `isEnabled:()=>!1` (disabled at MCP level) |
| Platform | All (no platform gate) |
| Added in | v1.1617.0 |

An AI-powered inbox scanner that reads from user's remote MCP servers (Gmail, Slack, GitHub, Linear, etc.) and extracts actionable items directed at the user. Currently **not activatable** — the session creation mechanism lives in the renderer/web layer, and the server-level `isEnabled` returns false.

| Tool | Description |
|------|-------------|
| `record_card` | Record one actionable item pointed at the user. Call once per item — an @-mention waiting on a reply, a review request, a direct ask. The `source_ref` must be the stable upstream identifier (Gmail thread ID, Slack message ts, GitHub owner/repo#N) so re-runs map to the same card. |

**`record_card` input schema:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Short headline naming the ask |
| `context` | string | Yes | Two or three sentences. Who, what, when it landed |
| `source` | string | Yes | Connector name: gmail, slack, github, linear, ... |
| `source_ref` | string | Yes | Stable upstream identifier — thread ID, message ts, issue/PR ref. Dedup key |
| `prompt` | string | Yes | First message for the spawned Cowork session. Self-contained — the new session has not seen this run |
| `urgency` | enum | Yes | `"high"`, `"medium"`, or `"low"` |
| `external_url` | string | No | Direct link to the source item |

**Session type:** `radar` sessions get restricted tool access — only `mcp__radar__record_card` plus remote MCP server tools. All other tools are stripped. Permission requests are auto-denied (`"${tool} requires approval and radar sessions can't prompt — skipped."`). Radar sessions are hidden from the user (classified alongside `agent` and `dispatch_child` in `jL()`).

### 11. Scheduled Tasks

| Field | Value |
|-------|-------|
| Server name | `"scheduled-tasks"` (constant `qBe`, hyphenated) |
| Registration | `createScheduledTasksServer()` (aliased `DHt`), injected per-session into CCD and Cowork session managers |
| Tool prefix | `mcp__scheduled-tasks__` |

| Tool | Description |
|------|-------------|
| `list_scheduled_tasks` | List scheduled tasks |
| `create_scheduled_task` | Create a new scheduled task |
| `update_scheduled_task` | Update an existing scheduled task |

### 12. CCD Session

| Field | Value |
|-------|-------|
| Server name | `"ccd_session"` |
| Gating | CCD session + server flag `1585356617` |
| Platform | All |

**New in v1.1.9134.** Allows the model to spawn a parallel task into its own separate CCD session.

| Tool | Description |
|------|-------------|
| `spawn_task` | Spin off a parallel task into a separate Claude Code Desktop session |

The `spawn_task` tool requires desktop approval card injection — cannot be auto-approved by hooks or permission rules.

## Per-Session Dynamic MCP Servers (SDK-type)

Claude Desktop creates 4 additional MCP servers **dynamically per cowork/dispatch session**. These are NOT registered via `qwA()` — they are created inline in the session manager and passed to the Claude Code CLI via `sdkMcpServers` in `--mcp-config`.

**Communication:** SDK-type servers use `MessagePort` bridges. On Mac/Windows, the VM SDK daemon (`nodeHost.js`) provides this bridge via vsock. On Linux native, `cowork-svc-linux` now **passes `--mcp-config` through unchanged** (since commit `d1dfc3b`). The CLI sends `control_request` messages on stdout, which flow through the event stream to Claude Desktop. Desktop's session manager intercepts them and sends `control_response` back via writeStdin — identical to VM mode on Mac/Windows.

### 13. Dispatch

| Field | Value |
|-------|-------|
| Server name | `"dispatch"` (constant `Of`) |
| Tool prefix | `mcp__dispatch__` |
| Session type | Agent (dispatch parent) sessions only |
| Registration | Dynamic via `f6t()` factory |
| Linux status | **Available** — via `control_request`/`control_response` proxy over event stream (since cowork-svc commit `d1dfc3b`) |

| Tool | Variable | Description |
|------|----------|-------------|
| `start_task` | `Hdt` | Start a new isolated cowork task session. Takes `{prompt, title, space_id?}` |
| `start_code_task` | `gRe` | Start a Claude Code session on host filesystem. Takes `{cwd, prompt, title}` |
| `send_message` | `Vdt` | Send a follow-up message to an existing session. Takes `{session_id, message}` |
| `set_agent_name` | `Wdt` | Set the agent's display name. Gated by flag `3558849738` |
| `list_code_workspaces` | `Gdt` | List available code workspaces. Gated by flag `3723845789` |
| `list_projects` | `Kdt` | List available projects |

**Important:** `mcp__dispatch__send_message` is **NOT** a replacement for the built-in `SendUserMessage` CLI tool — they serve completely different purposes. `send_message` sends a follow-up message **to another session** (inter-session communication, takes `{session_id, message}`). `SendUserMessage` sends a response **to the human user** (renders on phone, takes `{message, attachments?}`). Since `SendUserMessage` is broken ([anthropics/claude-code#35076](https://github.com/anthropics/claude-code/issues/35076) — still open as of 2026-03-27, confirmed on v2.1.85), there is **no native tool** for the model to send user-facing responses. Patch I in `fix_dispatch_linux.py` compensates by transforming plain text assistant messages into synthetic `SendUserMessage` tool_use blocks, which the sessions API renders on phone.

### 14. Cowork

| Field | Value |
|-------|-------|
| Server name | `"cowork"` (constant `lA`) |
| Tool prefix | `mcp__cowork__` |
| Session type | All cowork sessions |
| Registration | Dynamic via `l6t()` factory |
| Linux status | **Available** — via `control_request`/`control_response` proxy over event stream (since cowork-svc commit `d1dfc3b`) |

| Tool | Variable | Description |
|------|----------|-------------|
| `present_files` | `_Re` | Present files to user with interactive cards. Takes `{files: [{file_path}]}`. Handler returns file paths as text content |
| `request_cowork_directory` | `h0` | Request access to a host directory. Opens native folder picker (local sessions) or resolves path (remote). Denied in headless/dispatch-child without explicit `path` |
| `allow_cowork_file_delete` | `uR` | Allow deletion of files in cowork directory. Enriches input with `_folderName` for permission UI |
| `launch_code_session` | — | Launch a Claude Code session from within cowork. Conditional on `canLaunchCodeSession` |
| `create_artifact` | — | Create a self-contained HTML artifact (inline CSS/JS, data: URLs for images). Conditional on GrowthBook flag `2940196192` (**new in v1.1348.0**) |
| `update_artifact` | — | Update an existing artifact. Same constraints as `create_artifact`. Conditional on GrowthBook flag `2940196192` (**new in v1.1348.0**) |
| `save_skill` | — | Save a reusable skill to the user's account. Conditional on `canSaveSkill` (**new in v1.1348.0**) |

**Note:** `present_files`, `allow_cowork_file_delete`, `launch_code_session`, `create_artifact`, and `update_artifact` are added to `disallowedTools` for bridge/dispatch-child sessions. On Linux native, `cowork-svc-linux` removes `present_files` from `disallowedTools` as a workaround for file sharing.

### 15. Session Info

| Field | Value |
|-------|-------|
| Server name | `"session_info"` (constant `Lx`) |
| Tool prefix | `mcp__session_info__` |
| Session type | All except dispatch-child sessions |
| Registration | Dynamic via `p1e()` factory |
| Linux status | **Available** — via `control_request`/`control_response` proxy over event stream (since cowork-svc commit `d1dfc3b`) |

| Tool | Variable | Description |
|------|----------|-------------|
| `list_sessions` | `qdt` | List child sessions and all sessions |
| `read_transcript` | `zdt` | Read transcript of a session |

### 16. Workspace

| Field | Value |
|-------|-------|
| Server name | `"workspace"` (constant `J_`) |
| Tool prefix | `mcp__workspace__` |
| Session type | Cowork sessions |
| Registration | Dynamic per-session |
| Linux status | **Available** — via `control_request`/`control_response` proxy over event stream (since cowork-svc commit `d1dfc3b`) |

| Tool | Variable | Description |
|------|----------|-------------|
| `bash` | `Jdt` | Run bash commands in workspace context |
| `web_fetch` | `Xdt` | Fetch web resources |

**Bash tool description (Edn function):** The tool description is constructed dynamically via string concatenation: `"Run a shell command in the session's isolated Linux workspace. Your connected folders are mounted under /sessions/" + t.vmProcessName + "/mnt/ — ..."`. On macOS/Windows (VM-based), this is accurate. On Linux (native Go backend), there is no VM or `/sessions/` mount — `fix_cowork_sandbox_refs.nim` (Patch A) replaces both string halves with: *"Run a shell command on the host Linux system. There is no VM or sandbox — commands execute directly on the user's computer."* The dynamic concatenation (`+ t.vmProcessName +`) is preserved but made inert.

**System prompt sandbox references:** The upstream cowork system prompt tells the model: *"Claude runs in a lightweight Linux VM (Ubuntu 22) on the user's computer. This VM provides a secure sandbox..."* and *"Shell commands run in an isolated Linux environment."* On Linux, `fix_cowork_sandbox_refs.nim` (Patches B–D) replaces these with host-accurate text. Without this patch, the model hallucinates that it's in "an isolated Linux sandbox (Ubuntu 22)" even though `uname -a` returns the host kernel.

### SDK Server Architecture

```
Mac/Windows (VM):
  Claude Desktop main process
    ├─ creates dispatch/cowork/session_info/workspace server instances
    ├─ passes via sdkMcpServers in --mcp-config to VM
    ├─ VM SDK daemon (nodeHost.js) creates MessagePort bridges
    └─ Claude Code CLI connects via MessagePort → tool calls route back to Desktop

Linux native (current, since cowork-svc commit d1dfc3b):
  Claude Desktop main process
    ├─ creates same server instances
    ├─ passes via sdkMcpServers in --mcp-config to cowork-svc
    ├─ cowork-svc passes --mcp-config through unchanged
    ├─ Claude Code CLI sends control_request on stdout for MCP tool calls
    ├─ cowork-svc forwards via event stream to Desktop session manager
    ├─ Desktop sends control_response back via writeStdin
    └─ SDK MCP tools available (identical to VM mode)
       → Patch I still needed: SendUserMessage CLI built-in is broken
         (anthropics/claude-code#35076), sessions API only renders
         SendUserMessage blocks on phone
```

### Dynamic Per-Artifact MCP Servers (`cowork-artifact-<id>`)

When a Cowork session creates artifacts, Claude Desktop registers **dynamic** MCP servers named `cowork-artifact-<uuid>` for each artifact. These are NOT statically registered via `kce()` — they are created inline per artifact. The `cowork-artifact` string also serves as an Electron custom protocol scheme (`cowork-artifact:`) for rendering artifact content in the UI.

**Not a static server** — no tools to document. Not registered via `DfA()`. Calls route via `callRemoteTool("cowork-artifact-<id>", ...)`.

### Anthropic API Built-in Tool: `web_search`

| Field | Value |
|-------|-------|
| Type | `web_search_20250305` (Anthropic API built-in, like `computer_use`) |
| Name | `web_search` |
| Gating | `enable_web_search` feature flag |

This is NOT a custom MCP tool — it's an Anthropic API built-in tool type passed directly in the API request as `{type:"web_search_20250305",name:"web_search"}`. Referenced in the `Nzn` exclusion set alongside compute tools.

### AllowedTools for Dispatch Sessions

Claude Desktop constructs the `allowedTools` array per session type:

```javascript
// For agent (dispatch parent) sessions:
allowedTools: [
  /* CLI built-ins: */ "Task", "Bash", "Glob", "Grep", "Read", "Edit", "Write", ...
  /* Always allowed: */ "mcp__cowork__present_files",
  /* Dispatch-only: */ "SendUserMessage", "mcp__dispatch__start_task",
                        "mcp__dispatch__send_message", "mcp__dispatch__list_projects",
  /* Conditional: */   "mcp__dispatch__set_agent_name",       // flag 3558849738
                        "mcp__dispatch__list_code_workspaces", // flag 3723845789
]

// disallowedTools for bridge/dispatch-child:
disallowedTools: ["AskUserQuestion", "mcp__cowork__allow_cowork_file_delete",
                   "mcp__cowork__present_files", "mcp__cowork__launch_code_session"]
```

### 17. Computer Use

| Field | Value |
|-------|-------|
| Server name | `"computer-use"` (constant `p6t`) |
| Tool prefix | `mcp__computer-use__` |
| Platform | macOS (native), **Linux (patched)** |
| Gating (macOS/Windows) | Set-based: `nBA()` checks `rwA = new Set(["darwin","win32"])` + `chicagoEnabled` preference |
| Gating (Linux) | Enabled via Set modification (add "linux" to `rwA`) + feature flag and preference bypassed |
| Internal codename | "chicago" |

**Background:** Computer-use was previously a separate `computer-use-server.js` file in the app root (removed in v1.1.7714). As of v1.1.8359, it's fully integrated into `index.js` as an internal MCP server. In v1.1.9134, 5 new tools were added (multi-monitor, batch actions, teach mode).

**Feature flag (v1.3561.0):** Computer-use has a **triple gate**: (1) `rwA` Set platform check (`nBA()`), (2) static registry `computerUse` flag (`status` key), and (3) runtime enabled check (reading GrowthBook `chicago_config.enabled` + `chicagoEnabled` preference). Our patches bypass all three: `fix_computer_use_linux.nim` adds "linux" to `rwA` (gate 1), forces registration gate true on Linux, and forces runtime gate true on Linux (bypasses both GrowthBook and the `chicagoEnabled` preference). `enable_local_agent_mode.nim` Patch 3 overrides `computerUse` to `{status:"supported"}` (gate 2). The Settings toggle for CU is rendered server-side by claude.ai's web UI and hidden on Linux — runtime bypass means no toggle is needed.

**Tools (27):**

Tool definitions are built by `V7r()` with platform-dependent descriptions. On Linux, sub-patch 13 overrides key descriptions to remove macOS-specific references (Finder, bundle identifiers, allowlist gates). Below are the **upstream descriptions** (verbatim from v1.569.0 `index.js`), with platform-variant notes.

**Shared suffix (`Lf`):** Most action tools append: *"The frontmost application must be in the session allowlist at the time of this call, or this tool returns an error and does nothing."* — on Linux this is set to empty string (sub-patch 13a) since the allowlist is bypassed.

| Tool | Upstream description (verbatim, v1.569.0) |
|------|-------------|
| `request_access` | **Platform-dependent prefix:** macOS: *"This computer is running macOS. The file manager is 'Finder'."* / Windows: *"This computer is running Windows. The file manager is 'File Explorer' (not Finder). Elevated processes — Task Manager, UAC prompts, installers running as administrator — cannot be controlled even when granted: Windows UIPI blocks input from lower-integrity processes. If one appears, ask the user to handle it manually."* / **Linux (patched):** *"This computer is running Linux. On Linux, ALL applications are automatically accessible at full tier without explicit permission grants. You do NOT need to call request_access before using other tools. If called, it returns synthetic grant confirmations. The file manager depends on the desktop environment (e.g. Nautilus on GNOME, Dolphin on KDE, Thunar on XFCE)."* **Suffix (all platforms):** *"Request user permission to control a set of applications for this session. Must be called before any other tool in this server. The user sees a single dialog listing all requested apps and either allows the whole set or denies it. Call this again mid-session to add more apps; previously granted apps remain granted. Returns the granted apps, denied apps, and screenshot filtering capability."* |
| `screenshot` | **Platform-dependent (via `screenshotFiltering`):** native: *"Take a screenshot of the primary display. Applications not in the session allowlist are excluded at the compositor level — only granted apps and the desktop are visible."* / mask: *"...masked with a solid rectangle — their content is hidden from you, but the rectangle's position shows where the window is."* / none (**Linux**): *"Take a screenshot of the primary display. All open windows are visible."* (patched; upstream adds *"...Input actions targeting apps not in the session allowlist are rejected."*) **Suffix:** *"Returns an error if the allowlist is empty. The returned image is what subsequent click coordinates are relative to."* (on Linux, patched to remove allowlist-empty error) |
| `left_click` | *"Left-click at the given coordinates. `${Lf}`"* |
| `right_click` | *"Right-click at the given coordinates. Opens a context menu in most applications. `${Lf}`"* |
| `double_click` | *"Double-click at the given coordinates. Selects a word in most text editors. `${Lf}`"* |
| `triple_click` | *"Triple-click at the given coordinates. Selects a line in most text editors. `${Lf}`"* |
| `middle_click` | *"Middle-click (scroll-wheel click) at the given coordinates. `${Lf}`"* |
| `type` | *"Type text into whatever currently has keyboard focus. `${Lf}` Newlines are supported. For keyboard shortcuts use `key` instead."* |
| `key` | *"Press a key or key combination (e.g. 'return', 'escape', 'cmd+a', 'ctrl+shift+tab'). `${Lf}` System-level combos (quit app, switch app, lock screen) require the `systemKeyCombos` grant — without it they return an error. All other combos work."* |
| `scroll` | *"Scroll at the given coordinates. `${Lf}`"* |
| `left_click_drag` | *"Press, move to target, and release. `${Lf}`"* |
| `mouse_move` | *"Move the mouse cursor without clicking. Useful for triggering hover states. `${Lf}`"* |
| `hold_key` | *"Press and hold a key or key combination for the specified duration, then release. `${Lf}` System-level combos require the `systemKeyCombos` grant."* |
| `left_mouse_down` | *"Press the left mouse button at the current cursor position and leave it held. `${Lf}` Use mouse_move first to position the cursor. Call left_mouse_up to release. Errors if the button is already held."* |
| `left_mouse_up` | *"Release the left mouse button at the current cursor position. `${Lf}` Pairs with left_mouse_down. Safe to call even if the button is not currently held."* |
| `cursor_position` | *"Get the current mouse cursor position. Returns image-pixel coordinates relative to the most recent screenshot, or logical points if no screenshot has been taken."* |
| `wait` | *"Wait for a specified duration."* |
| `zoom` | *"Take a higher-resolution screenshot of a specific region of the last full-screen screenshot. Use this liberally to inspect small text, button labels, or fine UI details that are hard to read in the downsampled full-screen image. IMPORTANT: Coordinates in subsequent click calls always refer to the full-screen screenshot, never the zoomed image. This tool is read-only for inspecting detail."* |
| `open_application` | *"Bring an application to the front, launching it if necessary. The target application must already be in the session allowlist — call request_access first."* — **Linux (patched):** *"Bring an application to the front, launching it if necessary. On Linux, all applications are directly accessible."* |
| `list_granted_applications` | *"List the applications currently in the session allowlist, plus the active grant flags and coordinate mode. No side effects."* |
| `read_clipboard` | *"Read the current clipboard contents as text. Requires the `clipboardRead` grant."* |
| `write_clipboard` | *"Write text to the clipboard. Requires the `clipboardWrite` grant."* |
| `switch_display` | *"Switch which monitor subsequent screenshots capture. Use this when the application you need is on a different monitor than the one shown. The screenshot tool tells you which monitor it captured and lists other attached monitors by name — pass one of those names here. After switching, call screenshot to see the new monitor. Pass 'auto' to return to automatic monitor selection."* |
| `computer_batch` | *"Execute a sequence of actions in ONE tool call. Each individual tool call requires a model→API round trip (seconds); batching a predictable sequence eliminates all but one. Use this whenever you can predict the outcome of several actions ahead — e.g. click a field, type into it, press Return. Actions execute sequentially and stop on the first error. `${Lf}` The frontmost check runs before EACH action inside the batch — if an action opens a non-allowed app, the next action's gate fires and the batch stops there. Mid-batch screenshot actions are allowed for inspection but coordinates in subsequent clicks always refer to the PRE-BATCH full-screen screenshot."* |
| `request_teach_access` | *"Request permission to guide the user through a task step-by-step with on-screen tooltips. Use this INSTEAD OF request_access when the user wants to LEARN how to do something (phrases like 'teach me', 'walk me through', 'show me how', 'help me learn'). On approval the main Claude window hides and a fullscreen tooltip overlay appears. You then call teach_step repeatedly; each call shows one tooltip and waits for the user to click Next. Same app-allowlist semantics as request_access, but no clipboard/system-key flags. Teach mode ends automatically when your turn ends."* |
| `teach_step` | *"Show one guided-tour tooltip and wait for the user to click Next. On Next, execute the actions, take a fresh screenshot, and return both — you do NOT need a separate screenshot call between steps. The returned image shows the state after your actions ran; anchor the next teach_step against it. IMPORTANT — the user only sees the tooltip during teach mode. Put ALL narration in `explanation`. Text you emit outside teach_step calls is NOT visible until teach mode ends. Pack as many actions as possible into each step's `actions` array — the user waits through the whole round trip between clicks, so one step that fills a form beats five steps that fill one field each. Returns {exited:true} if the user clicks Exit — do not call teach_step again after that. Take an initial screenshot before your FIRST teach_step to anchor it."* |
| `teach_batch` | *"Queue multiple teach steps in one tool call. Parallels computer_batch: N steps → one model↔API round trip instead of N. Each step still shows a tooltip and waits for the user's Next click, but YOU aren't waiting for a round trip between steps. You can call teach_batch multiple times in one tour — treat each batch as one predictable SEGMENT (typically: all the steps on one page). The returned screenshot shows the state after the batch's final actions; anchor the NEXT teach_batch against it. WITHIN a batch, all anchors and click coordinates refer to the PRE-BATCH screenshot (same invariant as computer_batch) — for steps 2+ in a batch, either omit anchor (centered tooltip) or target elements you know won't have moved. Good pattern: batch 5 tooltips on page A (last step navigates) → read returned screenshot → batch 3 tooltips on page B → done. Returns {exited:true, stepsCompleted:N} if the user clicks Exit — do NOT call again after that; {stepsCompleted, stepFailed, ...} if an action errors mid-batch; otherwise {stepsCompleted, results:[...]} plus a final screenshot. Fall back to individual teach_step calls when you need to react to each intermediate screenshot."* |

#### macOS executor

Uses `createDarwinExecutor()` → `@ant/claude-swift` native module for screen capture, mouse/keyboard control, app management, and TCC permission grants.

#### Linux executor (`fix_computer_use_linux.nim`)

`fix_computer_use_linux.nim` applies 13 sub-patches + 3 system prompt fixes:

| # | Sub-patch | What it does |
|---|-----------|-------------|
| 1 | Inject `__linuxExecutor` | Linux executor using xdotool/scrot/Electron APIs at `app.on("ready")` |
| 2 | Add "linux" to `rwA` Set | `new Set(["darwin","win32"])` → `new Set(["darwin","win32","linux"])` — fixes all `nBA()` gates (server push, chicagoEnabled, overlay init) |
| 3 | Patch `createDarwinExecutor` | Return `__linuxExecutor` on Linux instead of throwing |
| 4 | Patch `ensureOsPermissions` | Return `{granted: true}` on Linux (skip macOS TCC checks) |
| 5 | Bypass permission model | Direct tool dispatch on Linux, skip allowlist/tier system |
| 6 | Teach overlay controller | Verify `vee()` gate runs on Linux (handled by Set fix) |
| 7 | Teach overlay mouse polling | Tooltip-bounds polling for Linux (X11 {forward:true} not supported) |
| 8 | Neutralize setIgnoreMouseEvents | Prevent upstream resets from fighting with polling |
| 9 | VM-aware teach transparency | Dark backdrop on VMs, full transparency on native hardware |
| 10 | Force `mVt()` isEnabled on Linux | Bypass GrowthBook `enabled:false` — tools registered for ALL session types (CCD, cowork, dispatch) |
| 11 | Force `rj()` true on Linux | Bypass both GrowthBook `enabled:false` AND `chicagoEnabled` preference — `isDisabled()` returns false, no config entry needed. The Settings toggle is rendered by claude.ai's web UI (server-side, not patchable), so on Linux CU is always enabled |
| 13 | Linux-aware tool descriptions | 7 sub-patches (13a–13g) fix tool descriptions for Linux: (a) `Lf` allowlist gate warning → empty on Linux, (b) `request_access` says "Linux" not "macOS"/"Finder", (c–d) app identifiers use WM_CLASS not bundle IDs, (e) `open_application` no allowlist needed, (f–g) `screenshot` removes allowlist references. Non-fatal — descriptions don't affect functionality |
| 14 | Linux-aware CU system prompt | 3 sub-patches (14a–14c) fix the CU system prompt injected into CCD/cuOnlyMode sessions: (a) "Separate filesystems" → "Same filesystem" on Linux (no sandbox — CLI and desktop share the same machine), (b) macOS app names "Finder, Photos, System Settings" → generic "the file manager, image viewer, terminal emulator, system settings" (works across all distros: Arch, Ubuntu, Fedora, NixOS), (c) file manager name "Finder" → "Files" on Linux |

**Linux tools used:**

| Tool | Package | Purpose |
|------|---------|---------|
| `xdotool` | `xdotool` | Mouse, keyboard, window info |
| `scrot` | `scrot` | Screenshots (with `-a` for per-monitor capture) |
| `import` | `imagemagick` | Fallback screenshots, zoom/crop |
| `wmctrl` | `wmctrl` | Running application detection |
| Electron `clipboard` | built-in | Clipboard read/write |
| Electron `screen` | built-in | Display/monitor enumeration |
| Electron `desktopCapturer` | built-in | Screenshot fallback (last resort) |

**Key differences from macOS:**
- No TCC permissions — all tools work immediately without `request_access`
- No app tier restrictions — can type into any window (no "click only" for editors)
- No app hiding before screenshots (`screenshotFiltering: "none"`)
- `request_access` returns "granted" immediately (model may still call it)
- X11/XWayland only (native Wayland not yet supported for global input)

**Additional Linux patch:** `fix_computer_use_tcc.nim` registers stub IPC handlers for `ComputerUseTcc` namespace so that renderer-side TCC permission queries don't throw errors.

## Linux Notes

- **Claude in Chrome**: Works on Linux via `fix_browser_tools_linux.py` — redirects native host binary to Claude Code's `~/.claude/chrome/chrome-native-host` and installs NativeMessagingHosts manifests for 6 Linux browsers (Chrome, Chromium, Brave, Edge, Vivaldi, Opera). Requires Claude Code CLI and the [Claude in Chrome](https://chromewebstore.google.com/detail/claude-code/fcoeoabgfenejglbffodgkkbkcdhcgfn) extension.
- **Office Add-in**: Platform-gated to macOS/Windows. Patched to enable on Linux via `fix_office_addin_linux.nim`.
- **Terminal (`read_terminal`)**: CCD sessions only — `isEnabled` checks `sessionType==="ccd"` (hardcoded, not patchable without changing session semantics). NOT available in Cowork sessions. In Cowork, the model uses `mcp__workspace__bash` instead which runs directly on the host. Platform gate `bfA` patched by `fix_dispatch_linux.nim`. node-pty rebuilt by build script.
- **Computer Use**: Works on Linux via `fix_computer_use_linux.nim` — uses xdotool/scrot + Electron built-in APIs (clipboard, screen, desktopCapturer) instead of `@ant/claude-swift`. Available in Cowork and Code sessions.
- **Visualize (Imagine)**: Enabled on Linux via `fix_imagine_linux.nim` — forces GrowthBook flag `3444158716`. No platform gate. Renders SVG/HTML inline in cowork sessions.
- **Radar**: Not yet activatable — server disabled at MCP level, session creation in renderer code. No platform gate. Future feature.
- **MCP Registry / Plugins / Scheduled Tasks**: Cross-platform, work on Linux.
- **Integrated Terminal (node-pty)**: Upstream ships only Windows binaries. Build script (`build-patched-tarball.sh`) rebuilds node-pty from source against Electron headers via `@electron/rebuild`. Enables the integrated terminal panel and `read_terminal` MCP tool on Linux.
- **Cowork sandbox descriptions**: Upstream system prompts and tool descriptions tell the model it runs in "a lightweight Linux VM (Ubuntu 22)" with "an isolated sandbox". On Linux with the native Go backend there is no VM — `fix_cowork_sandbox_refs.nim` replaces these with accurate host-system descriptions.

## Operon IPC System (v1.1617.0)

Not an MCP server, but a new internal IPC layer with 120+ endpoints across 33 sub-interfaces (unchanged from v1.1348.0):

`OperonAgentConfig`, `OperonAgents`, `OperonAnalytics`, `OperonAnnotations`, `OperonApiKeys`, `OperonArtifactDownloads`, `OperonArtifacts`, `OperonAssembly`, `OperonAttachments`, `OperonBootstrap`, `OperonCloud`, `OperonConversations`, `OperonDesktop` (**new**), `OperonEvents`, `OperonExportBundle`, `OperonFolders`, `OperonFrames`, `OperonHostAccess`, `OperonHostAccessProvider`, `OperonImageProvider`, `OperonMcp`, `OperonMcpToolAccessProvider` (**new**), `OperonNotes`, `OperonPreferences`, `OperonProjects`, `OperonQuitHandler`, `OperonReplay`, `OperonSDK`, `OperonSecrets`, `OperonServices`, `OperonSessionManager`, `OperonSkills`, `OperonSkillsSync`, `OperonSystem`

Gated behind GrowthBook flag `1306813456` — currently **unavailable** on all platforms (not enabled server-side). Do NOT force-enable; requires VM infrastructure (Nest).

When active, Operon provides 14 "brain tools" (multi-agent delegation, skills, dashboards, planning), 7 "compute tools" (bash, python, R, artifacts, packages), 1 dynamic tool (`skill`), and 4 internal LLM tools. See [CLAUDE_FEATURE_FLAGS.md — Operon Tool Inventory](CLAUDE_FEATURE_FLAGS.md#operon-tool-inventory-v11348) for the full catalog.

## Version Notes

| Version | Changes |
|---------|---------|
| v1.5354.0 | Registration function renamed `qwA()` (was `gpA()`). Registry storage `RL`→`MG`, labels `VJA`→`VqA`, enumerator `v7()`→`Y7()`. No new MCP servers, no new tools — same 17 servers (3 renderer-facing + 14 backend). Three patches fixed: `fix_window_bounds` (profile title hook insertion reordering), `fix_dispatch_linux` (gate variable position change), `fix_dispatch_outputs_dir` (new `Tc()` path wrapper in `openPath`). All 44 patches compatible. |
| v1.3561.0 | Registration function renamed `gpA()` (was `DfA()`). Platform gate variables `WhA`→`bfA` (darwin\|\|win32), `en` unchanged (darwin), `ws`→`ys` (win32). Computer-use Set `ele`→`rwA`, checker `Jne()`→`nBA()`. No new MCP servers, no new tools — same 17 servers (3 renderer-facing + 14 backend). Webpack re-minify only. All patches compatible. |
| v1.3109.0 | Registration function renamed `DfA()` (was `kce()`). Platform gate variables `UMe`→`WhA` (darwin\|\|win32), `hi`→`en` (darwin), `xce`→`ws` (win32). No new MCP servers, no new tools — same 17 servers (3 renderer-facing + 14 backend). Webpack re-minify only. All patches compatible. |
| v1.3036.0 | Registration function renamed `kce()` (was `ooe()`). Platform gate variable `r6e`→`UMe`, win32 `vs`→`xce`. No new MCP servers, no new tools — same 17 servers. Variable renames only. All patches compatible. |
| v1.2773.0 | Registration function renamed `ooe()` (was `One()`). Computer-use Set variable `ese`→`ele` with `Jne()` checker (was `Lte()`). Platform gate variable `c3e`→`r6e`. `floatingAtoll` now always supported unconditionally (was preference-gated). No new MCP servers, no new tools. Same 17 servers. Variable renames only. All patches compatible. |
| v1.2.234 | Registration function renamed `One()` (was `Are()`). **Terminal server now natively supports Linux** — `LRe = isDarwin \|\| isWin32 \|\| isLinux`, `fix_read_terminal_linux.py` patch removed. Computer-use platform gate changed to Set-based (`ese = new Set(["darwin","win32"])`) with `vee()` function. No new MCP servers or tools. Variable renames only. |
| v1.1.9669 | Registration function renamed `Are()` (was `Pee()`). **New `computerUse` feature flag** in static registry (`jun()`, darwin-only) — computer use now gated by both MCP server registration AND feature flag. No new MCP servers or tools. `chillingSlothFeat` darwin gate re-introduced (was removed in v1.1.9134). Remote orchestrator (`4201169164`) removed from GrowthBook. Same 3 renderer-facing servers (Chrome, mcp-registry, office-addin) and same backend servers. Variable renames only. |
| v1.1.9493 | Metadata-only re-release of v1.1.9310. JS bundles identical — no new MCP servers, tools, or IPC changes. Async feature merger restructured (`Promise.all` pattern). |
| v1.1.9134 | **New MCP server: `ccd_session`** (`spawn_task` tool for parallel session spawning). **5 new computer-use tools** (`switch_display`, `computer_batch`, `request_teach_access`, `teach_step`, `teach_batch` — 22→27 total). Registration function renamed `IM()`→`Pee()`. Operon expanded from 18→28 sub-interfaces. Computer-use constant renamed `zxt`→`p6t`. |
| v1.1348.0 | **3 new cowork tools:** `create_artifact`, `update_artifact` (flag `2940196192`), `save_skill` (conditional). Terminal server regressed to `z5e` (darwin\|\|win32) — Linux support maintained via `fix_dispatch_linux.py` `z5e` patch. New `Buddy` BLE device pairing IPC. Operon 31→33 sub-interfaces (`OperonDesktop`, `OperonMcpToolAccessProvider`). No new MCP servers. All 34 patches applied cleanly. |
| v1.1617.0 | **New MCP server: `radar`** (disabled, `record_card` tool). Platform gate variable renamed `z5e`→`g5e`. Computer-use Set variable `Hae` with `Lte()` checker. Registration function still `One()`. New renderer windows (`buddy_window/`, `find_in_page/`). New deps: `node-pty`, `ws`. No new tools on existing servers. All 35 patches applied cleanly. |
| v1.1062.0 | Registration function renamed to `One()`. **New: `update_plan` Chrome tool** (20 total Chrome tools). **New: `read_me` widget MCP tool** in Visualize server. Scheduled Tasks server name constant `qBe="scheduled-tasks"` (hyphenated). `cowork-artifact-<id>` dynamic per-artifact servers. `web_search` Anthropic API built-in tool (`web_search_20250305`) gated by `enable_web_search`. Operon expanded to 31 sub-interfaces (3 new: `OperonExportBundle`, `OperonReplay`, `OperonSDK`). Operon tool inventory: 14 brain tools, 7 compute tools, 1 dynamic (`skill`), 4 internal LLM tools. Dashboard tools `render_dashboard`/`patch_dashboard` disabled pending sandbox hardening. |
| v1.1.8359 | Visualize server factory renamed to `p3n()` via `getImagineServerDef` (same interface). Operon IPC system added (not MCP). No new MCP servers — all 14 unchanged. |
