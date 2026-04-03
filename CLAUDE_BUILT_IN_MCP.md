# Built-in MCP Servers — Claude Desktop v1.569.0

Claude Desktop registers internal MCP servers via a two-layer architecture:

1. **Renderer-facing layer (`One()`)** — servers accessible from the BrowserView via Electron `MessageChannelMain` ports
2. **Backend/session layer (`zZr`/`VZr`)** — servers providing tools to CCD/Cowork sessions

A server may appear in both layers (e.g., Chrome, mcp-registry) or only one.

## Registration System

```
One(serverName, displayLabel, factoryFn)
```

- Lazy singleton factory per server name
- UUID display label sent to renderer for identification
- Server list and instantiation managed via helper functions

## Renderer-Facing Servers (via `Are()`)

### 1. Claude in Chrome

| Field | Value |
|-------|-------|
| Server name | `"Claude in Chrome"` |
| Platform | All (socket path adapts per OS) |
| Gating | `chromeExtensionEnabled` preference (default: `true`) |

Communicates with the Chrome browser extension via Unix socket at `/tmp/claude-mcp-browser-bridge-<username>/0.sock`.

**Tools (18-19):**

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

### 2. MCP Registry

| Field | Value |
|-------|-------|
| Server name | `"mcp-registry"` |
| Platform | All |
| Gating | Always enabled |

The `One()` registration is a **stub returning no tools**. Actual tools are provided via the backend session layer.

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

## Backend-Only Servers (via `zZr`/`VZr`, not `Are()`)

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

### 5. Visualize

| Field | Value |
|-------|-------|
| Server name | `"visualize"` |
| Factory | `Vzn()` via `getImagineServerDef` |
| Gating | Server flag `3444158716` + Cowork session only |

| Tool | Description |
|------|-------------|
| `show_widget` | Render a visual widget in the UI |

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
| Server name | `"terminal"` |
| Platform | **All** (macOS, Windows, Linux) — natively cross-platform since v1.2.234 (`LRe = isDarwin \|\| isWin32 \|\| isLinux`) |
| Gating | CCD session + `LRe` platform check + server flag `397125142` |

| Tool | Description |
|------|-------------|
| `read_terminal` | Read terminal output |

### 8. Dev Debug

| Field | Value |
|-------|-------|
| Server name | `"dev-debug"` |
| Gating | Cowork session only |

| Tool | Description |
|------|-------------|
| `get_roots` | Get MCP roots |

### 9. Scheduled Tasks

Registered separately via `createScheduledTasksServer()`, injected directly into CCD and Cowork session managers.

| Tool | Description |
|------|-------------|
| `list_scheduled_tasks` | List scheduled tasks |
| `create_scheduled_task` | Create a new scheduled task |
| `update_scheduled_task` | Update an existing scheduled task |

### 10 (new). CCD Session

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

Claude Desktop creates 4 additional MCP servers **dynamically per cowork/dispatch session**. These are NOT registered via `Are()` — they are created inline in the session manager and passed to the Claude Code CLI via `sdkMcpServers` in `--mcp-config`.

**Communication:** SDK-type servers use `MessagePort` bridges. On Mac/Windows, the VM SDK daemon (`nodeHost.js`) provides this bridge via vsock. On Linux native, `cowork-svc-linux` now **passes `--mcp-config` through unchanged** (since commit `d1dfc3b`). The CLI sends `control_request` messages on stdout, which flow through the event stream to Claude Desktop. Desktop's session manager intercepts them and sends `control_response` back via writeStdin — identical to VM mode on Mac/Windows.

### 10. Dispatch

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

### 11. Cowork

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
| `launch_code_session` | `bRe` | Launch a Claude Code session from within cowork |

**Note:** `present_files`, `allow_cowork_file_delete`, and `launch_code_session` are added to `disallowedTools` for bridge/dispatch-child sessions (`rft` array). On Linux native, `cowork-svc-linux` removes `present_files` from `disallowedTools` as a workaround for file sharing.

### 12. Session Info

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

### 13. Workspace

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

### 14. Computer Use

| Field | Value |
|-------|-------|
| Server name | `"computer-use"` (constant `p6t`) |
| Tool prefix | `mcp__computer-use__` |
| Platform | macOS (native), **Linux (patched)** |
| Gating (macOS/Windows) | Set-based: `vee()` checks `ese = new Set(["darwin","win32"])` + `chicagoEnabled` preference |
| Gating (Linux) | Enabled via Set modification (add "linux" to `ese`) + feature flag and preference bypassed |
| Internal codename | "chicago" |

**Background:** Computer-use was previously a separate `computer-use-server.js` file in the app root (removed in v1.1.7714). As of v1.1.8359, it's fully integrated into `index.js` as an internal MCP server. In v1.1.9134, 5 new tools were added (multi-monitor, batch actions, teach mode).

**Feature flag (v1.2.234):** Computer-use has a **triple gate**: (1) `ese` Set platform check (`vee()`), (2) static registry `computerUse` flag (`status` key, checked by `kgn()`), and (3) runtime enabled check (`Rse()`/`rj()` reading GrowthBook `chicago_config.enabled` + `chicagoEnabled` preference). Our patches bypass all three: `fix_computer_use_linux.py` adds "linux" to `ese` (gate 1), forces `mVt()` true on Linux (registration gate), and forces `rj()` true on Linux (runtime gate — bypasses both GrowthBook and the `chicagoEnabled` preference). `enable_local_agent_mode.py` Patch 3 overrides `computerUse` to `{status:"supported"}` (gate 2). The Settings toggle for CU is rendered server-side by claude.ai's web UI and hidden on Linux — `rj()` bypass means no toggle is needed.

**Tools (27):**

| Tool | Description |
|------|-------------|
| `screenshot` | Take screenshot of display |
| `left_click` | Left mouse click at coordinates |
| `right_click` | Right mouse click at coordinates |
| `double_click` | Double-click at coordinates |
| `triple_click` | Triple-click at coordinates |
| `middle_click` | Middle mouse click at coordinates |
| `type` | Type text at current cursor position |
| `key` | Press keyboard key/combo |
| `scroll` | Scroll at coordinates |
| `cursor_position` | Get current cursor position |
| `wait` | Wait for specified duration |
| `zoom` | High-res screenshot of a region |
| `left_click_drag` | Click and drag between coordinates |
| `mouse_move` | Move cursor without clicking |
| `hold_key` | Hold a key for a duration |
| `left_mouse_down` | Press and hold left button |
| `left_mouse_up` | Release left button |
| `open_application` | Open an application by name |
| `read_clipboard` | Read clipboard contents |
| `write_clipboard` | Write text to clipboard |
| `request_access` | Request app access (auto-granted on Linux) |
| `list_granted_applications` | List granted apps (all on Linux) |
| `switch_display` | Switch which monitor subsequent screenshots capture (**new in v1.1.9134**) |
| `computer_batch` | Execute a sequence of actions in one tool call (**new in v1.1.9134**) |
| `request_teach_access` | Request permission for guided teach mode (**new in v1.1.9134**) |
| `teach_step` | Show one guided-tour tooltip, wait for user click, execute actions (**new in v1.1.9134**) |
| `teach_batch` | Queue multiple teach steps in one tool call (**new in v1.1.9134**) |

#### macOS executor

Uses `createDarwinExecutor()` → `@ant/claude-swift` native module for screen capture, mouse/keyboard control, app management, and TCC permission grants.

#### Linux executor (`fix_computer_use_linux.py`)

`fix_computer_use_linux.py` applies 12 sub-patches:

| # | Sub-patch | What it does |
|---|-----------|-------------|
| 1 | Inject `__linuxExecutor` | Linux executor using xdotool/scrot/Electron APIs at `app.on("ready")` |
| 2 | Add "linux" to `ese` Set | `new Set(["darwin","win32"])` → `new Set(["darwin","win32","linux"])` — fixes all `vee()` gates (server push, chicagoEnabled, overlay init) |
| 3 | Patch `createDarwinExecutor` | Return `__linuxExecutor` on Linux instead of throwing |
| 4 | Patch `ensureOsPermissions` | Return `{granted: true}` on Linux (skip macOS TCC checks) |
| 5 | Bypass permission model | Direct tool dispatch on Linux, skip allowlist/tier system |
| 6 | Teach overlay controller | Verify `vee()` gate runs on Linux (handled by Set fix) |
| 7 | Teach overlay mouse polling | Tooltip-bounds polling for Linux (X11 {forward:true} not supported) |
| 8 | Neutralize setIgnoreMouseEvents | Prevent upstream resets from fighting with polling |
| 9 | VM-aware teach transparency | Dark backdrop on VMs, full transparency on native hardware |
| 10 | Force `mVt()` isEnabled on Linux | Bypass GrowthBook `enabled:false` — tools registered for ALL session types (CCD, cowork, dispatch) |
| 11 | Force `rj()` true on Linux | Bypass both GrowthBook `enabled:false` AND `chicagoEnabled` preference — `isDisabled()` returns false, no config entry needed. The Settings toggle is rendered by claude.ai's web UI (server-side, not patchable), so on Linux CU is always enabled |

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

**Additional Linux patch:** `fix_computer_use_tcc.py` registers stub IPC handlers for `ComputerUseTcc` namespace so that renderer-side TCC permission queries don't throw errors.

## Linux Notes

- **Claude in Chrome**: Works on Linux via `fix_browser_tools_linux.py` — redirects native host binary to Claude Code's `~/.claude/chrome/chrome-native-host` and installs NativeMessagingHosts manifests for 6 Linux browsers (Chrome, Chromium, Brave, Edge, Vivaldi, Opera). Requires Claude Code CLI and the [Claude in Chrome](https://chromewebstore.google.com/detail/claude-code/fcoeoabgfenejglbffodgkkbkcdhcgfn) extension.
- **Office Add-in**: Platform-gated to macOS/Windows. Patched to enable on Linux via `fix_office_addin_linux.py`.
- **Terminal**: Natively supports all platforms since v1.2.234 (`LRe` includes Linux). No patch needed.
- **Computer Use**: Works on Linux via `fix_computer_use_linux.py` — uses xdotool/scrot + Electron built-in APIs (clipboard, screen, desktopCapturer) instead of `@ant/claude-swift`. Available in Cowork and Code sessions.
- **MCP Registry / Plugins / Visualize / Scheduled Tasks**: Cross-platform, work on Linux.

## Operon IPC System (v1.1.9134)

Not an MCP server, but a new internal IPC layer with 120+ endpoints across 28 sub-interfaces:

`OperonAgentConfig`, `OperonAgents`, `OperonAnalytics`, `OperonAnnotations`, `OperonApiKeys`, `OperonArtifactDownloads`, `OperonArtifacts`, `OperonAssembly`, `OperonAttachments`, `OperonBootstrap`, `OperonCloud`, `OperonConversations`, `OperonEvents`, `OperonFolders`, `OperonFrames`, `OperonHostAccess`, `OperonHostAccessProvider`, `OperonImageProvider`, `OperonMcp`, `OperonNotes`, `OperonPreferences`, `OperonProjects`, `OperonQuitHandler`, `OperonSecrets`, `OperonServices`, `OperonSessionManager`, `OperonSkills`, `OperonSkillsSync`, `OperonSystem`

Gated behind GrowthBook flag `1306813456` — currently **unavailable** on all platforms (not enabled server-side). Do NOT force-enable; requires VM infrastructure (Nest).

## Version Notes

| Version | Changes |
|---------|---------|
| v1.2.234 | Registration function renamed `One()` (was `Are()`). **Terminal server now natively supports Linux** — `LRe = isDarwin \|\| isWin32 \|\| isLinux`, `fix_read_terminal_linux.py` patch removed. Computer-use platform gate changed to Set-based (`ese = new Set(["darwin","win32"])`) with `vee()` function. No new MCP servers or tools. Variable renames only. |
| v1.1.9669 | Registration function renamed `Are()` (was `Pee()`). **New `computerUse` feature flag** in static registry (`jun()`, darwin-only) — computer use now gated by both MCP server registration AND feature flag. No new MCP servers or tools. `chillingSlothFeat` darwin gate re-introduced (was removed in v1.1.9134). Remote orchestrator (`4201169164`) removed from GrowthBook. Same 3 renderer-facing servers (Chrome, mcp-registry, office-addin) and same backend servers. Variable renames only. |
| v1.1.9493 | Metadata-only re-release of v1.1.9310. JS bundles identical — no new MCP servers, tools, or IPC changes. Async feature merger restructured (`Promise.all` pattern). |
| v1.1.9134 | **New MCP server: `ccd_session`** (`spawn_task` tool for parallel session spawning). **5 new computer-use tools** (`switch_display`, `computer_batch`, `request_teach_access`, `teach_step`, `teach_batch` — 22→27 total). Registration function renamed `IM()`→`Pee()`. Operon expanded from 18→28 sub-interfaces (9 new: `OperonAgentConfig`, `OperonAnalytics`, `OperonAssembly`, `OperonHostAccessProvider`, `OperonImageProvider`, `OperonQuitHandler`, `OperonServices`, `OperonSessionManager`, `OperonSkillsSync`). Computer-use constant renamed `zxt`→`p6t`. |
| v1.1.8359 | Visualize server factory renamed to `p3n()` via `getImagineServerDef` (same interface). Operon IPC system added (not MCP). No new MCP servers — all 14 unchanged. |
