# Built-in MCP Servers — Claude Desktop v1.1.8359

Claude Desktop registers internal MCP servers via a two-layer architecture:

1. **Renderer-facing layer (`IM()`)** — servers accessible from the BrowserView via Electron `MessageChannelMain` ports
2. **Backend/session layer (`P8t`/`R8t`)** — servers providing tools to CCD/Cowork sessions

A server may appear in both layers (e.g., Chrome, mcp-registry) or only one.

## Registration System

```
IM(serverName, displayLabel, factoryFn)
```

- `wg[serverName] = factoryFn` — lazy singleton factory
- `LH[serverName] = displayLabel` — UUID sent to renderer for identification
- `Px()` = `Object.keys(wg)` — list all registered names
- `E2e(name)` — instantiate/retrieve cached server
- `x2e(name)` — get display label

## Renderer-Facing Servers (via `IM()`)

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

The `IM()` registration is a **stub returning no tools**. Actual tools are provided via the backend session layer (`P8t`).

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

## Backend-Only Servers (via `P8t`/`R8t`, not `IM()`)

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
| Gating | Server flag `3444158716` + Cowork session only |

| Tool | Description |
|------|-------------|
| `show_widget` | Render a visual widget in the UI |

### 6. Claude Preview

| Field | Value |
|-------|-------|
| Server name | `"Claude Preview"` |
| Gating | Server flag `2976814254` + CCD session + `launchEnabled` preference |

Provides 13 `preview_*` tools for web preview functionality.

### 7. Terminal

| Field | Value |
|-------|-------|
| Server name | `"terminal"` |
| Platform | macOS only |
| Gating | CCD session + macOS + server flag `397125142` |

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

## Per-Session Dynamic MCP Servers (SDK-type)

Claude Desktop creates 4 additional MCP servers **dynamically per cowork/dispatch session**. These are NOT registered via `IM()` — they are created inline in the session manager and passed to the Claude Code CLI via `sdkMcpServers` in `--mcp-config`.

**Communication:** SDK-type servers use `MessagePort` bridges. On Mac/Windows, the VM SDK daemon (`nodeHost.js`) provides this bridge via vsock. On Linux native, `cowork-svc-linux` currently **strips** all SDK servers (replacing `--mcp-config` with `{"mcpServers":{}}`), because there is no MessagePort bridge implementation.

### 10. Dispatch

| Field | Value |
|-------|-------|
| Server name | `"dispatch"` (constant `Of`) |
| Tool prefix | `mcp__dispatch__` |
| Session type | Agent (dispatch parent) sessions only |
| Registration | Dynamic via `f6t()` factory |
| Linux status | **Not available** — stripped by `cowork-svc-linux` (no MCP proxy) |

| Tool | Variable | Description |
|------|----------|-------------|
| `start_task` | `Hdt` | Start a new isolated cowork task session. Takes `{prompt, title, space_id?}` |
| `start_code_task` | `gRe` | Start a Claude Code session on host filesystem. Takes `{cwd, prompt, title}` |
| `send_message` | `Vdt` | Send a follow-up message to an existing session. Takes `{session_id, message}` |
| `set_agent_name` | `Wdt` | Set the agent's display name. Gated by flag `3558849738` |
| `list_code_workspaces` | `Gdt` | List available code workspaces. Gated by flag `3723845789` |
| `list_projects` | `Kdt` | List available projects |

**Key role:** `mcp__dispatch__send_message` is the **primary fallback** when the built-in `SendUserMessage` CLI tool isn't available (which happens due to a CLI initialization timing bug). On Mac/Windows, this SDK tool routes through the MessagePort bridge back to Desktop. On Linux, it's stripped, so Patch I in `fix_dispatch_linux.py` compensates by transforming plain text responses into synthetic `SendUserMessage` at the sessions-bridge level.

### 11. Cowork

| Field | Value |
|-------|-------|
| Server name | `"cowork"` (constant `lA`) |
| Tool prefix | `mcp__cowork__` |
| Session type | All cowork sessions |
| Registration | Dynamic via `l6t()` factory |
| Linux status | **Not available** — stripped by `cowork-svc-linux` (no MCP proxy) |

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
| Linux status | **Not available** — stripped by `cowork-svc-linux` (no MCP proxy) |

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
| Linux status | **Not available** — stripped by `cowork-svc-linux` (no MCP proxy) |

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

Linux native (current):
  Claude Desktop main process
    ├─ creates same server instances
    ├─ passes via sdkMcpServers in --mcp-config to cowork-svc
    ├─ cowork-svc STRIPS --mcp-config → {"mcpServers":{}}
    └─ Claude Code CLI has NO access to SDK tools
       → Patch I compensates at sessions-bridge level for text/file responses
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
| Server name | `"computer-use"` (constant `zxt`) |
| Tool prefix | `mcp__computer-use__` |
| Platform | macOS (native), **Linux (patched)** |
| Gating (macOS) | Triple gate: `process.platform==="darwin" && featureFlagEnabled && chicagoEnabled` preference |
| Gating (Linux) | Always enabled (feature flag and preference bypassed) |
| Internal codename | "chicago" |

**Background:** Computer-use was previously a separate `computer-use-server.js` file in the app root (removed in v1.1.7714). As of v1.1.8359, it's fully integrated into `index.js` as an internal MCP server, registered via the `t7r()` factory function.

**Tools (22):**

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

#### macOS executor

Uses `createDarwinExecutor()` → `@ant/claude-swift` native module for screen capture, mouse/keyboard control, app management, and TCC permission grants.

#### Linux executor (`fix_computer_use_linux.py`)

`fix_computer_use_linux.py` applies 6 sub-patches:

| # | Sub-patch | What it does |
|---|-----------|-------------|
| 1 | Inject `__linuxExecutor` | Linux executor using xdotool/scrot/xclip at `app.on("ready")` |
| 2 | Remove `b7r()` gate | Let `t7r()` register the server on all platforms (was darwin-only) |
| 3 | Extend `ZM()` | Return `true` on Linux (bypass feature flag + `chicagoEnabled` preference) |
| 4 | Patch `createDarwinExecutor` | Return `__linuxExecutor` on Linux instead of throwing |
| 5 | Patch `ensureOsPermissions` | Return `{granted: true}` on Linux (skip macOS TCC checks) |
| 6 | Bypass permission model | Direct tool dispatch on Linux, skip `rvr()` allowlist/tier system |

**Linux tools used:**

| Tool | Package | Purpose |
|------|---------|---------|
| `xdotool` | `xdotool` | Mouse, keyboard, window info |
| `scrot` | `scrot` | Screenshots (with `-a` for per-monitor capture) |
| `import` | `imagemagick` | Fallback screenshots, zoom/crop |
| `xrandr` | `xorg-xrandr` | Display/monitor enumeration |
| `xclip` | `xclip` | Clipboard read/write |
| `wmctrl` | `wmctrl` | Running application detection |

**Key differences from macOS:**
- No TCC permissions — all tools work immediately without `request_access`
- No app tier restrictions — can type into any window (no "click only" for editors)
- No app hiding before screenshots (`screenshotFiltering: "none"`)
- `request_access` returns "granted" immediately (model may still call it)
- X11/XWayland only (native Wayland not yet supported for global input)

**Additional Linux patch:** `fix_computer_use_tcc.py` registers stub IPC handlers for `ComputerUseTcc` namespace so that renderer-side TCC permission queries don't throw errors.

## Linux Notes

- **Claude in Chrome**: Works on Linux (Unix socket). No patches needed.
- **Office Add-in**: Platform-gated to macOS/Windows. Patched to enable on Linux via `fix_office_addin_linux.py`.
- **Terminal**: macOS only. Patched to enable on Linux via `fix_read_terminal_linux.py`.
- **Computer Use**: Works on Linux via `fix_computer_use_linux.py` — uses xdotool/scrot/xclip instead of `@ant/claude-swift`. Available in Cowork and Code sessions.
- **MCP Registry / Plugins / Visualize / Scheduled Tasks**: Cross-platform, work on Linux.
