---
name: audit
description: Full review of the claude-desktop-bin + claude-cowork-service projects — patches vs the current upstream msix (still needed? new ones needed? did the surrounding code change?), docs accuracy, Linux compatibility across the distro/session matrix, cross-project Cowork communication (native AND KVM modes), and runtime logs. Orchestrates a team of sub-agents and produces a consolidated report with solution approaches.
disable-model-invocation: true
---

# Audit — orchestrated project review

You are the **coordinator**. Spawn a team of sub-agents to review in parallel, then synthesize ONE report. Run from `/home/patrickjaja/development/claude-desktop-bin` (claude-cowork-service is an added dir). `$ARGUMENTS` may scope the audit (e.g. "cowork only", "patches only"); default = full.

Use the `AskUserQuestion` tool (not limited to 4) whenever a finding needs the user's call. Read `/architecture` and `/linux` context first if unsure of the domain.

## Pre-flight (you do this before fan-out)
1. Ensure a **fresh unpatched** upstream extract exists for patch comparison: if `./tmp/app.asar.contents/.vite/build/index.js` is missing or older than today, run `/fresh-upstream` (or tell the user and run the manual 7z+asar flow). Patches must be judged against the true current upstream, not a stale extract.
2. Note `.upstream-version` vs upstream `.latest`, and which cowork backend the user runs (`COWORK_VM_BACKEND`, default native). Check `~/.config/Claude/logs/` exists for the log workstream.

## Fan out — spawn these workstreams as parallel agents (Explore/general-purpose)
Give each agent the two project paths, the fresh-extract path, and ask for **findings + file:line evidence + a recommended action**, not file dumps.

1. **Patches vs upstream.** For each `patches/*.nim`: does its target still exist in the fresh `./tmp` bundle? Run `./scripts/validate-patches.sh ./tmp/app.asar.contents` and report pass/fail. For failures, classify: pattern renamed / code refactored / feature removed / feature upstreamed (→ needs regression guard). Flag patches that may be **vestigial** (target gone, no longer needed) and **gaps** (new darwin/win32 gates with no Linux patch — diff `process.platform` old vs new). Verify `EXPECTED_PATCHES` strictness + no false-success idempotency (CLAUDE.md Rule 6).
2. **Docs accuracy.** Cross-check `baseline/CLAUDE_FEATURE_FLAGS.md`, `CLAUDE_BUILT_IN_MCP.md`, `ION.md`, `PLATFORM_GATE_BASELINE.md`, `README.md` patch table, and `CLAUDE.md` against the actual current bundle + patches. Flag stale minified names, wrong counts, removed features still documented. (Read `CHANGELOG.md` head only: offset 1, limit 60.)
3. **Linux compatibility.** Walk the support matrix (X11, Wayland-wlroots, Wayland-GNOME, Wayland-KDE, XWayland) × (Arch/Ubuntu/Debian/Fedora/RHEL/NixOS/Jetson, x86_64+aarch64). Check input (`js/cu_linux_executor.js`, `executor_linux.js`) + screenshot cascades still cover each session, glibc floors (node-pty 2.31, kwin-portal-bridge 2.39) hold, launcher session detection is sound. Surface edge cases (ydotoold version, Niri, immutable distros, sandboxed/portal identity).
4. **Cross-project Cowork comms — BOTH modes.** Verify the patched Electron app and `cowork-svc-linux` agree on: socket path (`$XDG_RUNTIME_DIR/cowork-vm-service.sock`), length-prefixed-JSON framing, the 22 RPC methods, event types (`COWORK_RPC_PROTOCOL.md` vs `pipe/handlers.go`/`process/events.go`). **Contrast native vs KVM**: native runs the CLI on the host (no sandbox; strips `--disallowedTools`, remaps `/sessions/...` paths, intercepts `present_files`); KVM boots the guest VM (vsock to sdk-daemon, virtiofs, gVisor). Confirm Desktop's `fix_cowork_linux`/`fix_vm_session_handlers`/`fix_dispatch_linux` patches still match what the daemon expects. Flag any protocol drift.
5. **Runtime logs (if present).** Scan `~/.config/Claude/logs/{main,cowork_vm_node,mcp,claude.ai-web}.log` for errors/exceptions, permission denials, dispatch bridge issues (`DISPATCH-FWD`/`DISPATCH-TRANSFORM`), and renderer crashes. If cowork debugging is in scope, suggest running `cowork-svc-linux -debug` (after `systemctl --user stop claude-cowork` + removing the socket) and grepping `DISPATCH-DEBUG|disallowedTools|injecting --brief`. Defer deep dispatch/cowork debugging to `/debug`.

## Synthesize (you, after agents return)
Produce a report:
- **Summary table:** workstream → status (clean / needs attention / broken) → headline finding.
- **Patches:** vestigial (removable), at-risk (pattern drift), gaps (new Linux opportunities), each with file:line + recommended action.
- **Docs:** what's stale + the exact fix.
- **Linux matrix:** any session/distro/arch combo at risk.
- **Cross-project:** protocol agreement native vs KVM; any drift.
- **Logs:** notable errors + likely cause.
- **Solution approaches:** ranked, with effort estimate. Use `AskUserQuestion` for any decision (delete a patch? add one? change behavior per backend?).

Cross-reference memory (`~/.claude/projects/-home-patrickjaja-development-claude-desktop-bin/memory/`) for prior decisions before recommending changes. This is read-only review — propose, don't apply (unless the user then asks).
