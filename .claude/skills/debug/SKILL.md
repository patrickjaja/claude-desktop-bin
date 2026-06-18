---
name: debug
description: Debug a problem in claude-desktop-bin / claude-cowork-service by pulling the right local evidence — the most recent local-agent-mode session transcript (your last prompt + the model's tool calls/errors), the Claude Desktop logs, cowork-svc debug output — and asking you for anything else worth collecting for the specific issue. Invoke as "/debug <short description of what's broken>".
disable-model-invocation: true
argument-hint: "<what is broken>"
---

# Debug — collect evidence, then diagnose

The issue to debug: **$ARGUMENTS**

You are debugging the patched Claude Desktop and/or the cowork daemon. Gather the relevant local evidence below (skip what's clearly irrelevant to "$ARGUMENTS"), form a hypothesis, then ask the user for anything you can't collect yourself. Read `/architecture` for how the pieces fit and `/linux` for session/CU specifics if relevant.

## 1. Last local-agent-mode session transcript (the single source of truth for Cowork/Dispatch/agent runs)
`audit.jsonl` records exactly what the model saw and did. Find the newest one and read **the user's last prompt + the assistant tool calls + any errors**:
```bash
AUDIT=$(find ~/.config/Claude/local-agent-mode-sessions -name audit.jsonl -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2)
echo "newest audit: $AUDIT"
python3 -c "
import json,sys
p='$AUDIT'
if not p: sys.exit('no audit.jsonl found')
rows=[json.loads(l) for l in open(p) if l.strip()]
# user's first/last prompt
users=[r for r in rows if r.get('type')=='user']
def text(m):
    c=(m or {}).get('content')
    if isinstance(c,str): return c
    if isinstance(c,list): return ' '.join(x.get('text','') for x in c if isinstance(x,dict))
    return str(c)
if users: print('FIRST USER PROMPT:', text(users[0].get('message'))[:500])
if len(users)>1: print('LAST USER PROMPT:', text(users[-1].get('message'))[:500])
# tool calls + errors
for i,r in enumerate(rows):
    t=r.get('type')
    if t=='assistant':
        for c in (r.get('message',{}).get('content') or []):
            if isinstance(c,dict) and c.get('type')=='tool_use': print(f'[{i}] tool_use: {c.get(\"name\")} {str(c.get(\"input\",{}))[:120]}')
    elif t=='user' and ('Error' in str(r) or 'Permission' in str(r) or 'denied' in str(r)):
        print(f'[{i}] error/result: {str(r)[:200]}')
    elif t=='result': print(f'[{i}] RESULT: {str(r.get(\"result\",r))[:200]}')
"
```
If "$ARGUMENTS" is about dispatch/cowork/skills not working, this transcript usually shows the failing tool call, a permission denial, or a wrong path.

## 2. Claude Desktop logs (whatever exists — globbed, not hardcoded)
```bash
ls -la ~/.config/Claude/logs/ 2>/dev/null
rg -i -a 'error|exception|fatal|denied|ENOENT|EACCES' ~/.config/Claude/logs/ 2>/dev/null | tail -40
```
Known logs (presence varies): `main.log` (Electron main), `cowork_vm_node.log` (Cowork sessions), `mcp.log` + `mcp-server-*.log`, `claude.ai-web.log` (BrowserView), plus others like `ssh.log`, `unknown-window.log`. Tail the one(s) relevant to "$ARGUMENTS". Also check crash reports: `ls -la ~/.config/Claude/crash* 2>/dev/null`.

### Dispatch-specific (if relevant)
```bash
grep -a 'DISPATCH-FWD.*PASSING\|DISPATCH-TRANSFORM\|DISPATCH-WRITE' ~/.config/Claude/logs/main.log | tail -20
grep -a 'Permission.*denied' ~/.config/Claude/logs/main.log | tail -10
```

## 3. cowork-svc daemon (if Cowork/Dispatch backend is implicated)
Quick state, then optional verbose run:
```bash
pgrep -a cowork-svc; ls -la "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/cowork-*service.sock 2>/dev/null
systemctl --user status claude-cowork 2>/dev/null | head -15
```
For a live debug session (verbose RPC):
```bash
systemctl --user stop claude-cowork 2>/dev/null || pkill cowork-svc
rm -f "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/cowork-vm-service.sock
nohup cowork-svc-linux -debug > /tmp/cowork-debug.log 2>&1 &
# reproduce the issue in the app, then:
grep -E 'DISPATCH-DEBUG|disallowedTools|injecting --brief|spawn|RPC' /tmp/cowork-debug.log | tail -40
```
(`COWORK_LOG_FULL=1` disables the ~160-char line truncation.) Note native vs KVM (`COWORK_VM_BACKEND`) — behavior differs (see `/architecture`).

## 4. Ask the user for what you can't collect
Based on "$ARGUMENTS", use `AskUserQuestion` to request anything missing — only ask for what the task actually needs. Examples to consider:
- Exact repro steps + which feature (Chat/Code/Cowork/Dispatch/Computer Use/3P/Quick Entry).
- Session/distro: output of `claude-desktop --diagnose` and the `[claude-cu] diagnostics:` lines from terminal (for Computer Use / Wayland issues).
- Whether to run the verbose `cowork-svc-linux -debug` capture (step 3) and reproduce now.
- A screenshot / the exact error text shown in the UI.
- For stale-state bugs: permission to clear `~/.config/Claude/local-agent-mode-sessions/` (the model can otherwise "remember" past errors).

## 5. Diagnose
State the hypothesis grounded in the evidence (cite the log line / audit record / file:line). If it's a patch/upstream issue, point at the patch and suggest `/fresh-upstream` + `/update`. If it's a protocol drift, point at `COWORK_RPC_PROTOCOL.md` vs the daemon. Propose the fix; apply only if the user asks. Cross-reference memory (`~/.claude/projects/-home-patrickjaja-development-claude-desktop-bin/memory/`, e.g. dispatch-linux-debug, cowork-crash-debug) for prior findings before concluding.
