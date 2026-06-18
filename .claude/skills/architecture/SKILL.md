---
name: architecture
description: Explains the purpose, features, and architecture of the two sibling projects — claude-desktop-bin (Linux-patched Claude Desktop) and claude-cowork-service (native Linux Cowork backend with native + KVM modes). Use when onboarding, writing docs/READMEs, explaining what the projects do, comparing the two backend modes, or reasoning about how the Electron app and the daemon fit together.
when_to_use: When the user asks what the project does, how the pieces fit, the difference between native and KVM backends, the USPs, or wants an architecture/overview explanation for docs or a new contributor.
---

# Architecture — claude-desktop-bin + claude-cowork-service

Two sibling repos that together bring the **full** Claude Desktop experience to Linux. Anthropic ships Claude Desktop for macOS/Windows only. See `/linux` for compat specifics, `/audit` for review.

## 1. claude-desktop-bin — Linux-patched Claude Desktop
Repackages the upstream, **remotely-managed** `Claude.msix` (Windows Electron app) for Linux by applying ~51 surgical JS patches (`patches/*.nim`, compiled native binaries, regex on minified JS), rebuilding native modules (node-pty) for Linux x86_64+aarch64, and packaging as AUR/deb/rpm/AppImage/Nix. The upstream binary changes without notice and re-minifies every release → patches use `[\w$]+` wildcards anchored on stable strings, count `EXPECTED_PATCHES`, and `quit(1)` on any miss. `.upstream-version` records the last validated version.

**User-facing features the patched app exposes** (derive details from `patches/` + `baseline/`):
- **Chat** — main conversational UI (platform-neutral, works as-is).
- **Claude Code** — auto-detects system `claude` CLI (/usr/bin, ~/.local/bin, /usr/local/bin); Code tab + integrated terminal (`fix_claude_code`, `fix_terminal_shell_linux`).
- **Cowork** — delegate a goal to a sandboxed Claude Code agent that reads/edits/creates files in a designated folder and returns a deliverable; live artifacts, concurrent session pool, memory consolidation. **Requires claude-cowork-service** (the VM/sandbox backend). Enabled by `enable_local_agent_mode` + `fix_cowork_*` + `fix_vm_session_handlers`.
- **Dispatch** — mobile→desktop task routing via Anthropic's dispatch/sessions-bridge; also needs claude-cowork-service (`fix_dispatch_linux`).
- **Computer Use** — desktop automation (screenshot/click/type/scroll); session-aware backends (`fix_computer_use_linux`, see `/linux`).
- **Browser Tools** — Chrome automation via the Claude-in-Chrome extension/MCP (`fix_browser_tools_linux`).
- **3P / Enterprise gateway** — configure external inference (Bedrock/Vertex/Azure/gateway); enterprise.json from `/etc/claude-desktop`; ion-dist 3P-config SPA (`fix_enterprise_config_linux`, `fix_marketplace_linux`, `fix_ion_dist_linux`).
- **Imagine** — in-Cowork image generation (`fix_imagine_linux`).
- **Quick Entry** — global hotkey popup, multi-monitor + Wayland-safe (`fix_quick_entry_*`).
- **Linux-only extras** — custom themes (`add_feature_custom_themes`), multi-profile instances via `CLAUDE_PROFILE` (`fix_profile_*`).

`baseline/` tracks version-sensitive internals (re-validate each release): `CLAUDE_FEATURE_FLAGS.md` (flag catalog, GrowthBook IDs, 3-layer override), `CLAUDE_BUILT_IN_MCP.md` (internal MCP servers), `ION.md` (3P-config SPA stats/hashes), `PLATFORM_GATE_BASELINE.md` (every darwin/win32 gate classified PATCHED/NATIVE/STUB/PORTABLE).

## 2. claude-cowork-service — native Linux Cowork backend
Go daemon (binary `cowork-svc-linux`) that fills the role the macOS/Windows VM layer plays for Cowork/Dispatch. It implements the exact length-prefixed-JSON-over-Unix-socket RPC protocol Claude Desktop expects (macOS: Apple Virtualization/Swift; Windows: Hyper-V/`cowork-svc.exe`). The patched Electron app connects to its socket instead of a Windows NamedPipe.

**Core thesis:** the VM on macOS/Windows boots Linux anyway. On Linux we *are* the target OS, so **native mode skips the VM entirely**; **KVM mode** boots Anthropic's guest image for full sandbox parity.

- **Socket:** `$XDG_RUNTIME_DIR/cowork-vm-service.sock` (native) / `cowork-kvm-service.sock` (KVM); fallback `/tmp/...`. **Not profile-suffixed** — all Desktop profiles share one daemon; sessions are distinguished by `createVM(name)`/`spawn(name,…)` in the RPC payload.
- **Protocol:** `pipe/protocol.go` (4-byte big-endian length + JSON, 10MB cap), `pipe/handlers.go` (22 RPC methods: createVM/startVM/stopVM, spawn/kill/writeStdin, readFile, subscribeEvents, getSessionsDiskInfo, pruneSessionCaches, …), `process/events.go` (events: stdout/exit/apiReachability/startupStep/vmStarted/vmStopped/networkStatus). Full reference: `COWORK_RPC_PROTOCOL.md`.
- **CLI spawning** (`native/process.go`): 3-stage binary resolution (LookPath → `bash -lc which` → `$SHELL -lic command -v`); strips `CLAUDECODE`/`CLAUDE_CODE_ENTRYPOINT` (prevents nested-launch refusal) and empty-string env vars (auth); `Setpgid` for subtree kill; strips plugin prefix in stdin (`/document-skills:pdf` → `/pdf`).
- **Dispatch adaptations** (`native/backend.go`): strips `--disallowedTools` (no VM runtime on native, all tools available), injects `--brief` when `CLAUDE_CODE_BRIEF=1`, appends a system prompt instructing absolute file paths in SendUserMessage attachments, intercepts `present_files` (Desktop rejects native paths).
- **Backend select** (`main.go`): `COWORK_VM_BACKEND=native|kvm` (env, precedence) or `-backend` flag; default native. KVM gated by `CheckKvmPrerequisites()` (/dev/kvm, qemu-system-x86_64, virtiofsd, vhost-vsock).
- **Packaging:** AUR/deb/rpm/Nix; systemd **user** service `claude-cowork.service` (imports WAYLAND_DISPLAY/XDG_SESSION_TYPE/DBUS/YDOTOOL_SOCKET from the session) + OpenRC for Artix. Pure Go, `CGO_ENABLED=0`, PIE.
- **Optional, never forced** (memory `feedback_cowork_service_stays_optional`): Chat + Code work without it; absence must stay visible + actionable.
- **Logs:** stderr → systemd journal; `-debug`/`COWORK_LOG_FULL=1` for verbose RPC (default truncates lines ~160 chars). Desktop side: `~/.config/Claude/logs/cowork_vm_node.log`.

### Native mode (default)
Runs the `claude` CLI **directly on the host** as the logged-in user. No VM, no boot delay, instant spawn, real host paths. **No sandbox / no isolation** (memory/CPU/allowedDomains params ignored). Path-mapping: Desktop sends VM paths `/sessions/<name>/mnt/<mount>`; daemon backs them with `~/.local/share/claude-cowork/sessions/...`, symlinks `/sessions/<name>` if writable, else remaps cwd/args/env on the fly (CLI Glob doesn't follow dir symlinks → must hand the model real paths). Deterministic, resume-aware cwd selection (workspace.go) from `CLAUDE_CODE_WORKSPACE_HOST_PATHS`.

### KVM mode (experimental)
Boots Anthropic's guest image in QEMU/KVM (vhdx→qcow2 cached), shares `$HOME` via unprivileged virtiofs, talks to the in-guest `sdk-daemon` over vsock, network-isolates via gVisor (enforces allowedDomains). Full sandbox parity with macOS/Windows: separate user/namespaces, read-only root, resource limits, session independence.

## USPs
**Project vs upstream:** true Linux Cowork/Dispatch (no official support); reverse-engineered, documented protocol; open source; dual-backend choice.
**Native:** zero VM overhead, instant start, direct host filesystem, no hypervisor/kernel-module deps, trivial troubleshooting (real paths). Best for single-user laptop dev.
**KVM:** full sandbox parity, process/filesystem/network/credential isolation, resource limits, crash containment. Best when isolation matters.

## How they fit
```
Claude Desktop (patched Electron, claude-desktop-bin)
   ├─ Chat / Code / Computer Use / Browser / 3P gateway     (in-app, patched)
   └─ Cowork / Dispatch  ──unix socket──▶  claude-cowork-service (cowork-svc-linux)
                                              ├─ native: claude CLI on host
                                              └─ KVM:   claude CLI in guest VM
```
