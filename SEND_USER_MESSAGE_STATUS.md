# SendUserMessage Bug Status

**Upstream issue:** [anthropics/claude-code#35076](https://github.com/anthropics/claude-code/issues/35076)
**Status:** OPEN (no assignees, no maintainer comments)
**Last verified:** 2026-03-27 on CLI v2.1.85
**Verdict:** Bug persists. Workaround (Patch I) is required.

---

## What is the bug?

The `SendUserMessage` CLI built-in tool is **never registered** in the model's tool list.
Without this tool, the dispatch model cannot send responses to the user's phone — the
sessions API only renders `SendUserMessage` tool_use blocks. Plain text is silently dropped.

Patch I in `fix_dispatch_linux.py` works around this by transforming plain text assistant
messages into synthetic `SendUserMessage` tool_use blocks at the sessions-bridge level.

## Common misconception

`mcp__dispatch__send_message` is **NOT** a substitute for `SendUserMessage`. They are
completely different tools:

| | `SendUserMessage` (CLI built-in) | `mcp__dispatch__send_message` (SDK MCP) |
|---|---|---|
| Purpose | Send response **to the human user** (phone) | Send follow-up **to another session** (inter-session) |
| Input | `{message, attachments?}` | `{session_id, message}` |
| Renders on phone? | Yes | No |
| Status | Broken (never registered) | Works (via --mcp-config proxy) |

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

### Why it should work (in theory)

With `CLAUDE_CODE_BRIEF=1`:
- `isBriefEntitled()` checks `rH(process.env.CLAUDE_CODE_BRIEF)` → should be true
- `No$()` sees entitled=true → calls `Vp(true)` → sets `userMsgOptIn=true`
- `isEnabled()` = `(false || true) && true` = true

### Why it doesn't work (empirically)

Despite the code logic suggesting the tool should be enabled, it **never appears** in the
registered tool list. Possible causes:
- The `rH()` parser may not treat `"1"` as truthy
- A cold-start race condition (partially fixed in v2.1.84 for Edit/Write) may still affect
  SendUserMessage — the tool could be filtered before `No$()` runs
- There may be additional gating not visible in string analysis of the compiled binary
- The `-p` (print/non-interactive) mode may use a different initialization path

---

## Empirical test results (v2.1.85)

### Test methodology

Launch the CLI with various flag/env combinations and inspect the `tools` array in the
stream-json init message. This is the authoritative list of tools registered for the session.

```bash
# Capture tool list:
CLAUDE_CODE_BRIEF=1 claude --brief -p "say hi" --output-format stream-json --verbose \
  2>&1 > /tmp/test.json

# Parse:
python3 -c "
import json
with open('/tmp/test.json') as f:
    for line in f:
        d = json.loads(line)
        if d.get('type') == 'system' and d.get('subtype') == 'init':
            print('SendUserMessage' in d['tools'])
            break
"
```

### Results

| Scenario | SendUserMessage in tools? | Tool count |
|---|---|---|
| `CLAUDE_CODE_BRIEF=1` + `--brief` | **No** | 58 |
| `--brief` only | **No** | 58 |
| `CLAUDE_CODE_BRIEF=1` only | **No** | 58 |
| Neither | **No** | 58 |

Tool count is identical in all cases — the flags have zero effect on tool registration.

### Direct invocation test

When explicitly asked to call `SendUserMessage`, the model:
1. Searched for it via `ToolSearch` → not found
2. Responded: *"There is no SendUserMessage tool available"*

### Model hallucination warning

When asked "Do you have a tool called SendUserMessage? Answer YES or NO" the model
sometimes answers **YES** — this is a hallucination. The model recognizes the concept
from training data but does not actually check its tool list. Always verify via
stream-json init, never trust the model's self-report.

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
    echo ">>> Consider removing Patch I from fix_dispatch_linux.py <<<"
    echo ">>> Update SEND_USER_MESSAGE_STATUS.md <<<"
else
    echo ""
    echo "Bug persists. Patch I still required."
fi
```

Save as `scripts/check_send_user_message.sh` and run after each CLI update.

---

## Affected components

### Workarounds (in claude-desktop-bin)

| Component | File | Purpose | Remove when fixed? |
|---|---|---|---|
| Patch F | `patches/fix_dispatch_linux.py` | Widen rjt() bridge filter to accept text + other tool names | Review — may still be needed for edge cases |
| Patch I | `patches/fix_dispatch_linux.py` | Transform plain text → synthetic SendUserMessage tool_use | Yes — primary workaround for this bug |

### Belt-and-suspenders (in claude-cowork-service)

| Component | File | Purpose | Remove when fixed? |
|---|---|---|---|
| `--brief` injection | `native/backend.go:254-271` | Inject `--brief` flag when `CLAUDE_CODE_BRIEF=1` in env | Review — low cost, may aid future fix |

---

## VM bundle & Agent SDK versions

The official cowork VM (used on Windows/Mac) ships via `@anthropic-ai/claude-agent-sdk`.
The SDK version maps 1:1 to a CLI version: **SDK `0.2.X` bundles CLI `2.1.X`**
(confirmed via the `claudeCodeVersion` field in the npm registry metadata).

### Our extracted VM bundle (Claude Desktop 1.1.9134)

| Field | Value |
|-------|-------|
| Claude Desktop version | 1.1.9134 (from `vm-bundle/.version`) |
| Agent SDK | `@anthropic-ai/claude-agent-sdk@0.2.78` |
| **Bundled CLI** | **2.1.78** (last working version) |
| Future dev SDK in package.json | `0.2.86-dev.20260326` → CLI 2.1.86 (not yet published) |

### Latest stable Agent SDK (npm)

| Field | Value |
|-------|-------|
| Latest SDK (`dist-tags.latest`) | `@anthropic-ai/claude-agent-sdk@0.2.85` |
| **Bundled CLI** | **2.1.85 (BROKEN)** |

**Critical implication:** The latest stable SDK (0.2.85) bundles CLI 2.1.85,
which has the same bug. This means:

1. **Our extracted VM (from Desktop 1.1.9134) still uses SDK 0.2.78** —
   Anthropic may be deliberately pinning to 0.2.78 because they know newer
   versions break SendUserMessage. Or our VM extract is simply from before
   they updated.
2. **If/when Anthropic updates the VM to SDK 0.2.85+, dispatch will break
   on Windows/Mac too** — unless they fix the CLI first.
3. **Monitoring:** After each Claude Desktop update, re-extract `vm-bundle`
   and check which SDK version is pinned. If it moves past 0.2.78 AND the
   CLI bug is still present, Windows/Mac dispatch is also affected.

### How to check after a Claude Desktop update

```bash
# Re-extract app.asar from the new Claude Desktop build, then:
grep '"@anthropic-ai/claude-agent-sdk"' vm-bundle/app-asar-extracted/package.json
# If the version moves past 0.2.78, check the CLI version:
curl -s https://registry.npmjs.org/@anthropic-ai/claude-agent-sdk/<VERSION> | python3 -c "
import json, sys; print(json.load(sys.stdin).get('claudeCodeVersion', 'NOT FOUND'))
"
```

---

## Version bisect (empirical, tested 2026-03-27)

All tests run with `CLAUDE_CODE_BRIEF=1` + `--brief` via
`node cli.js -p "say hi" --output-format stream-json --verbose`,
checking the `tools` array in the stream-json init message.

| CLI version | SendUserMessage registered? | Tool count | Notes |
|-------------|---------------------------|------------|-------|
| **2.1.78** | **Yes** | 89 | Last working version. Bundled in VM via Agent SDK 0.2.78. |
| **2.1.79** | **No** | 57 | **Regression introduced here.** |
| 2.1.80 | No | 57 | |
| 2.1.83 | No | (binary-only, not testable via node) | |
| 2.1.84 | No | (binary-only) | CHANGELOG: fixed cold-start race for Edit/Write |
| 2.1.85 | No | 58 | Latest. Full binary analysis confirms tool never registered. |

The tool count dropped from 89 (v2.1.78) to 57 (v2.1.79), suggesting a major
refactoring of the tool system happened at this version boundary (likely the
introduction of deferred tools / ToolSearch).

---

## What "fixed" looks like

When the bug is fixed:
1. `SendUserMessage` appears in the stream-json init `tools` array
2. The model can call the tool directly (no ToolSearch needed)
3. Dispatch responses render on phone without Patch I
4. File attachments via `SendUserMessage({attachments: [...]})` work natively

At that point:
- Remove Patch I from `fix_dispatch_linux.py`
- Review whether Patch F is still needed (rjt() may be updated upstream)
- Keep `--brief` injection in `backend.go` (harmless, matches Electron behavior)
- Update this document
