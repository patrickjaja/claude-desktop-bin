# SendUserMessage Bug Status

**Upstream issue:** [anthropics/claude-code#35076](https://github.com/anthropics/claude-code/issues/35076)
**Status:** FIXED in CLI v2.1.86 / SDK 0.2.86 (env var path only)
**Last verified:** 2026-03-28 on CLI v2.1.86
**Verdict:** Bug partially fixed. `CLAUDE_CODE_BRIEF=1` env var now correctly enables SendUserMessage. `--brief` CLI flag alone still broken.

---

## Current state (v2.1.86)

| Scenario | SendUserMessage registered? | Tool count |
|---|---|---|
| No flags | **No** | 58 |
| `--brief` only | **No** | 58 |
| `CLAUDE_CODE_BRIEF=1` only | **Yes** | 59 |
| `CLAUDE_CODE_BRIEF=1` + `--brief` | **Yes** | 59 |

The env var `CLAUDE_CODE_BRIEF=1` is sufficient. The `--brief` CLI flag has no effect on its own.

### What changed from v2.1.85 to v2.1.86

The `rH()` env var parser was likely fixed to properly treat `"1"` as truthy. In v2.1.85,
`CLAUDE_CODE_BRIEF=1` had zero effect (tool count stayed at 58). In v2.1.86, it correctly
triggers the entitlement check → `isBriefEntitled()` returns true → `No$()` sets
`userMsgOptIn=true` → `isEnabled()` returns true → tool is registered.

The `--brief` CLI flag path remains broken — it does not set the entitlement independently
of the env var. This may be intentional (env var is the real gate) or a separate bug.

### Impact on claude-cowork-service

**Positive:** The Go backend already sets `CLAUDE_CODE_BRIEF=1` in the CLI spawn environment.
With v2.1.86, this means SendUserMessage is now natively available to the model — it should
call the tool directly instead of falling back to plain text.

**Action items:**
1. Patch I (synthetic SendUserMessage transform) may become redundant — test end-to-end with dispatch
2. Patch F (rjt filter widening) should remain for now — still useful for edge cases
3. `--brief` flag injection in `backend.go` is harmless but not the mechanism that enables the tool

---

## What was the bug?

The `SendUserMessage` CLI built-in tool was **never registered** in the model's tool list
in CLI versions 2.1.79 through 2.1.85. Without this tool, the dispatch model could not send
responses to the user's phone — the sessions API only renders `SendUserMessage` tool_use blocks.

Patch I in `patches/fix_dispatch_linux.py` worked around this by transforming plain text
assistant messages into synthetic `SendUserMessage` tool_use blocks at the sessions-bridge level.

## Dispatch architecture (Ditto)

Desktop spawns a long-running dispatch orchestrator agent internally named "Ditto" (visible in
session directories as `local_ditto_*`). The architecture uses three distinct session types,
identified by the `CLAUDE_CODE_TAGS` environment variable passed to the CLI:

| Session type | `CLAUDE_CODE_TAGS` value | `CLAUDE_CODE_BRIEF` | Has SendUserMessage? | Has dispatch MCP? | Purpose |
|---|---|---|---|---|---|
| Regular cowork (chat) | `lam_session_type:chat` | Not set | No | No | Normal interactive cowork session |
| Ditto orchestrator (agent) | `lam_session_type:agent` | `1` | **Yes** | **Yes** | Long-running dispatch agent that receives user tasks and delegates |
| Dispatch child | `lam_session_type:dispatch_child` | Not set | No | No | Child task spawned by Ditto to do actual work |

The Ditto orchestrator is the only session type that has both `SendUserMessage` (to reply to
the user's phone) and the dispatch MCP tools (to spawn/manage child tasks). Child sessions do
the actual coding work and report back to Ditto via `mcp__dispatch__send_message`.

### --disallowedTools stripping

Desktop passes a `--disallowedTools` flag containing VM-only tools that don't exist on native Linux:
- `AskUserQuestion`
- `mcp__cowork__allow_cowork_file_delete`
- `mcp__cowork__present_files`
- `mcp__cowork__launch_code_session`
- `mcp__cowork__create_artifact`
- `mcp__cowork__update_artifact`

On native Linux (claude-cowork-service), we strip the entire `--disallowedTools` flag since
there is no VM and these tools are not registered anyway.

### present_files interception

Desktop's built-in `present_files` MCP handler rejects native Linux paths as "not accessible on
user's computer" because it expects VM paths. We intercept `present_files` calls locally in the
Go backend (`claude-cowork-service`) and handle them natively.

---

## Common misconception

`mcp__dispatch__send_message` is **NOT** a substitute for `SendUserMessage`. They are
completely different tools:

| | `SendUserMessage` (CLI built-in) | `mcp__dispatch__send_message` (SDK MCP) |
|---|---|---|
| Purpose | Send response **to the human user** (phone) | Send follow-up **to another session** (inter-session) |
| Input | `{message, attachments?, status?}` | `{session_id, message}` |
| Renders on phone? | Yes | No |
| Status | **Fixed in v2.1.86** (via env var) | Works (via --mcp-config proxy) |

### SendUserMessage full signature (CLI v2.1.86, from binary analysis)

| Parameter | Type | Required | Description |
|---|---|---|---|
| `message` | string | **Yes** | The message content. Supports markdown formatting. |
| `attachments` | array of strings | No | File paths (absolute or cwd-relative) for images, diffs, logs, etc. |
| `status` | string | No | `"normal"` (default, replying to user) or `"proactive"` (agent-initiated: scheduled task completion, blocker encountered, needs input). |

---

## Reverse engineering findings (CLI v2.1.85)

The Claude Code CLI is a Bun-compiled ELF binary (~228MB) with embedded JavaScript.
The following was extracted by string-searching the compiled binary.

### Tool definition

```
BRIEF_TOOL_NAME       = "SendUserMessage"
LEGACY_BRIEF_TOOL_NAME = "Brief"
DESCRIPTION           = "Send a message to the user"
```

The tool object (`BriefTool`) has `name: "SendUserMessage"` and `aliases: ["Brief"]`.
It is included in the master tool list function `rKH()` and is NOT a deferred tool
(no `shouldDefer: true`).

### Registration gate: isEnabled()

```js
// BriefTool.isEnabled():
isEnabled() { return V2K(); }

// V2K = isBriefEnabled:
function V2K() {
  return (pT() || lN()) && JE$();
}
```

Requires BOTH:
1. **Opt-in:** `pT()` (Kairos/teammate active) OR `lN()` (`userMsgOptIn` flag)
2. **Entitlement:** `JE$()` = `isBriefEntitled()`

### Entitlement check: isBriefEntitled()

```js
function isBriefEntitled() {
  return pT()                                    // Kairos active
    || rH(process.env.CLAUDE_CODE_BRIEF)         // env var truthy
    || Gk("tengu_kairos_brief", false, 300000);  // feature flag (default: false, 5min cache)
}
```

### --brief flag processing: No$()

```js
function No$(H) {
  let brief = H.brief;                              // CLI --brief flag
  let envBrief = rH(process.env.CLAUDE_CODE_BRIEF); // env var
  if (!brief && !envBrief) return;                   // neither set → bail
  let entitled = isBriefEntitled();
  if (entitled) Vp(true);  // sets userMsgOptIn = true
}
```

### Why it works in v2.1.86

With `CLAUDE_CODE_BRIEF=1`:
- `isBriefEntitled()` checks `rH(process.env.CLAUDE_CODE_BRIEF)` → now returns true (parser fixed)
- `No$()` sees `envBrief=true`, entitled=true → calls `Vp(true)` → sets `userMsgOptIn=true`
- `isEnabled()` = `(false || true) && true` = true

### Why --brief alone doesn't work

With just `--brief` (no env var):
- `No$()` checks `H.brief` → true, but `envBrief` → false
- `isBriefEntitled()` → `pT()` false, `rH(undefined)` false, feature flag false → **false**
- `entitled = false` → `Vp(true)` is never called → tool stays disabled
- The `--brief` flag alone can't enable the tool because it needs `isBriefEntitled()` to pass,
  and the flag doesn't contribute to that check. This appears to be a design bug.

---

## Empirical test results

### v2.1.86 (2026-03-28) — FIXED

| Scenario | SendUserMessage in tools? | Tool count |
|---|---|---|
| `CLAUDE_CODE_BRIEF=1` + `--brief` | **Yes** | 59 |
| `CLAUDE_CODE_BRIEF=1` only | **Yes** | 59 |
| `--brief` only | No | 58 |
| Neither | No | 58 |

### v2.1.85 (2026-03-27) — BROKEN

| Scenario | SendUserMessage in tools? | Tool count |
|---|---|---|
| `CLAUDE_CODE_BRIEF=1` + `--brief` | No | 58 |
| `--brief` only | No | 58 |
| `CLAUDE_CODE_BRIEF=1` only | No | 58 |
| Neither | No | 58 |

---

## Verification procedure (run after CLI updates)

```bash
#!/bin/bash
# Quick check: does SendUserMessage appear in the tool list?
VERSION=$(claude --version 2>/dev/null | head -1)
echo "Testing CLI: $VERSION"

OUTPUT=$(CLAUDE_CODE_BRIEF=1 timeout 60 claude --brief \
  -p "say hi" --output-format stream-json --verbose 2>&1)

HAS_TOOL=$(echo "$OUTPUT" | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
    except: continue
    if d.get('type') == 'system' and d.get('subtype') == 'init':
        print('YES' if 'SendUserMessage' in d['tools'] else 'NO')
        break
" 2>/dev/null)

echo "SendUserMessage registered: $HAS_TOOL"

if [ "$HAS_TOOL" = "YES" ]; then
    echo ""
    echo ">>> BUG APPEARS FIXED! <<<"
    echo ">>> Test end-to-end dispatch before removing Patch I <<<"
    echo ">>> Update SEND_USER_MESSAGE_STATUS.md <<<"
else
    echo ""
    echo "Bug persists. Patch I still required."
fi
```

---

## Affected components

### Workarounds (in claude-desktop-bin)

| Component | File | Purpose | Status after v2.1.86 |
|---|---|---|---|
| Patch F | `patches/fix_dispatch_linux.py` | Widen rjt() bridge filter to accept text + other tool names | **Keep** — still needed for edge cases where model uses plain text |
| ~~Patch I~~ | ~~`patches/fix_dispatch_linux.py`~~ | ~~Transform plain text → synthetic SendUserMessage tool_use~~ | **Removed** — model calls SendUserMessage natively now |

### Belt-and-suspenders (in claude-cowork-service)

| Component | File | Purpose | Status after v2.1.86 |
|---|---|---|---|
| `CLAUDE_CODE_BRIEF=1` env | `native/backend.go` | Set env var for CLI spawn | **Critical** — this is what actually enables the tool |
| `--brief` injection | `native/backend.go` | Inject `--brief` flag | **Optional** — env var alone is sufficient |
| `--disallowedTools` stripping | `native/backend.go` | Strip VM-only disallowed tools list | **Active** — Desktop passes VM tools that don't exist on native Linux |
| `present_files` interception | `native/backend.go` | Handle present_files locally instead of Desktop's MCP handler | **Active** — Desktop rejects native Linux paths as "not accessible" |

---

## VM bundle & Agent SDK versions

The official cowork VM (used on Windows/Mac) ships via `@anthropic-ai/claude-agent-sdk`.
The SDK version maps 1:1 to a CLI version: **SDK `0.2.X` bundles CLI `2.1.X`**
(confirmed via the `claudeCodeVersion` field in the npm registry metadata).

### Latest stable Agent SDK (npm) — 2026-03-28

| Field | Value |
|-------|-------|
| Latest SDK (`dist-tags.latest`) | `@anthropic-ai/claude-agent-sdk@0.2.86` |
| **Bundled CLI** | **2.1.86 (FIXED)** |

Both the SDK (0.2.86) and the native Linux CLI (2.1.86) now have the fix.

### Our extracted VM bundle (Claude Desktop 1.1.9134)

| Field | Value |
|-------|-------|
| Claude Desktop version | 1.1.9134 (from `vm-bundle/.version`) |
| Agent SDK | `@anthropic-ai/claude-agent-sdk@0.2.78` |
| **Bundled CLI** | **2.1.78** (last working version before regression) |
| Future dev SDK in package.json | `0.2.86-dev.20260326` → CLI 2.1.86 (now published stable) |

**Implication:** When Anthropic updates the VM bundle past 0.2.78, dispatch should work on
Windows/Mac as well.

---

## Version bisect (empirical)

All tests run with `CLAUDE_CODE_BRIEF=1` + `--brief` via
`node cli.js -p "say hi" --output-format stream-json --verbose` (or binary),
checking the `tools` array in the stream-json init message.

| CLI version | SendUserMessage registered? | Tool count | Notes |
|-------------|---------------------------|------------|-------|
| **2.1.78** | **Yes** | 89 | Last working version before regression. |
| **2.1.79** | **No** | 57 | **Regression introduced here.** |
| 2.1.80 | No | 57 | |
| 2.1.83 | No | (binary-only) | |
| 2.1.84 | No | (binary-only) | CHANGELOG: fixed cold-start race for Edit/Write |
| 2.1.85 | No | 58 | Full binary analysis confirms tool never registered. |
| **2.1.86** | **Yes** | 59 | **Fix shipped here.** Env var path works; --brief flag alone still broken. |

---

## Upstream issue status (2026-03-28)

- **Issue:** [anthropics/claude-code#35076](https://github.com/anthropics/claude-code/issues/35076)
- **Status:** Still OPEN (not closed despite fix shipping in v2.1.86)
- **Maintainer comments:** None
- **Comments:** 1 (bot duplicate detection, received 3 thumbs-down)
- **Linked PRs:** None

The fix appears to have been shipped silently without closing the issue.

---

## What "fully fixed" looks like

The env var path is fixed. Current checklist:
1. ~~SendUserMessage appears in the tool list~~ DONE (with `CLAUDE_CODE_BRIEF=1`)
2. ~~Remove Patch I (synthetic SendUserMessage transform)~~ DONE — model calls SendUserMessage natively
3. ~~Strip `--disallowedTools` for native Linux~~ DONE — VM-only tools removed from disallow list
4. ~~Intercept `present_files` locally~~ DONE — Desktop's handler rejects native paths
5. Review Patch F (rjt filter) — may still be needed for fallback
6. Keep `CLAUDE_CODE_BRIEF=1` env injection in `backend.go` (this is the mechanism)
7. `--brief` flag injection in `backend.go` can be kept (harmless) or removed (unnecessary)
