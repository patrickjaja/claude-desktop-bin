# Built-in MCP Servers — Claude Desktop v1.1.7714

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

## AllowedTools Reference

The `allowedTools` list also includes `"mcp__computer-use"`, but **no computer-use MCP server is registered** in v1.1.7714. The client-side code (permissions, system prompts) remains as dead code.

## Linux Notes

- **Claude in Chrome**: Works on Linux (Unix socket). No patches needed.
- **Office Add-in**: Platform-gated to macOS/Windows. Not available on Linux.
- **Terminal**: macOS only. Not available on Linux.
- **MCP Registry / Plugins / Visualize / Scheduled Tasks**: Cross-platform, work on Linux.
