;/*__CDB_GB_OVERRIDES__*/(function () {
  "use strict";
  if (typeof process === "undefined" || !process.versions || !process.versions.electron) return;

  var lastRaw = null;
  var lastParsed = null;
  var announced = "";

  function diag(msg) {
    try { (globalThis.__cdbDiag || console.log)(msg); } catch (e) {}
  }

  // Both filenames are honored and merged (.jsonc wins per key) so existing
  // plain-JSON configs (themes) keep working; the commented template lives in
  // .jsonc where editors expect comments.
  function configPaths() {
    var path = require("path");
    var ud = require("electron").app.getPath("userData");
    return {
      json: path.join(ud, "claude-desktop-bin.json"),
      jsonc: path.join(ud, "claude-desktop-bin.jsonc")
    };
  }

  // JSONC: strip // and /* */ comments outside of strings so the shipped
  // template can list flags commented out and users just uncomment them.
  function stripJsonComments(s) {
    var out = "";
    var inStr = false;
    var i = 0;
    while (i < s.length) {
      var c = s[i];
      if (inStr) {
        out += c;
        if (c === "\\" && i + 1 < s.length) { out += s[i + 1]; i++; }
        else if (c === '"') inStr = false;
        i++;
        continue;
      }
      if (c === '"') { inStr = true; out += c; i++; continue; }
      if (c === "/" && s[i + 1] === "/") { while (i < s.length && s[i] !== "\n") i++; continue; }
      if (c === "/" && s[i + 1] === "*") { i += 2; while (i < s.length && !(s[i] === "*" && s[i + 1] === "/")) i++; i += 2; continue; }
      out += c;
      i++;
    }
    return out;
  }

  var TEMPLATE = [
    "// claude-desktop-bin - local configuration (custom themes + feature-flag overrides)",
    "//",
    "// This .jsonc file is merged over claude-desktop-bin.json in the same directory",
    "// (per key; .jsonc wins) - an existing .json config keeps working unchanged.",
    "// Comments (// and /* */) are allowed in both files.",
    "//",
    "// activeTheme: pick a custom theme - mario, sweet, nord, catppuccin-mocha,",
    "// catppuccin-macchiato, catppuccin-frappe, catppuccin-latte - or author your own",
    "// (see themes/README.md in the repo). Needs an app restart.",
    "//",
    "// growthbookOverrides (advanced, unsupported territory):",
    "// Every GrowthBook flag observed being read from the feature store in Claude",
    "// Desktop v1.19367.0 is listed below, commented out. Uncomment a line to force",
    "// it; separate multiple active entries with commas (JSON rules apply after",
    "// comments are stripped). true/false for switches; flags marked (value flag)",
    "// carry numbers/strings/objects - a bare true may be meaningless for those.",
    "// Read on every flag (re)load: startup, the periodic refresh (~1h) and account",
    "// changes - edits apply without a restart. Overrides win over Anthropic's",
    "// server rollout. Flags force-enabled by claude-desktop-bin's binary patches",
    "// (Code / Cowork / Computer Use enablement) are NOT listed - they bypass this",
    "// file entirely. Active overrides are logged to logs/claude-patches.log.",
    "// Flag IDs are Anthropic-internal and can vanish or change meaning in any",
    "// release (this list reflects v1.19367.0). If the app misbehaves, empty this",
    "// file first.",
    "{",
    "  // \"activeTheme\": \"mario\",",
    "  \"growthbookOverrides\": {",
    "    // \"17519066\": true,     // external-browser URL block",
    "    // \"66187241\": true,     // CLAUDE_CODE_EMIT_TOOL_USE_SUMMARIES for local-agent sessions",
    "    // \"124685897\": true,    // prompt template substitution",
    "    // \"130970054\": true,    // rt('130970054') read into a prompt/feature enable check (Ve({enabled:...}))",
    "    // \"144158705\": true,    // LAM remote folder-access consent network call",
    "    // \"162211072\": true,    // Prompt suggestions enable",
    "    // \"180602792\": true,    // midnightOwl (macOS) - live listener",
    "    // \"227459766\": true,    // documents list config (value flag)",
    "    // \"254738541\": true,    // proactive dispatch-orchestrator prompt (value flag)",
    "    // \"286376943\": true,    // Plugin skills for system prompt — gates getPluginSkillsForSystemPrompt (new in v1.2278.0)",
    "    // \"397125142\": true,    // Terminal server — gated: sessionType==='ccd'&&!isSSH AND this flag. CCD only, NOT cowork. ",
    "    // \"416245092\": true,    // GPU crash-streak marker file (default ON)",
    "    // \"434204418\": true,    // MCP non-blocking connection",
    "    // \"451382573\": true,    // DISABLE_BRIEF_MODE_STOP_HOOK env var for cowork/LAM sessions",
    "    // \"476513332\": true,    // check_interval_ticks config (value flag)",
    "    // \"552157343\": true,    // plugin add gating (default ON)",
    "    // \"554317356\": true,    // timeout ms (value flag)",
    "    // \"629684104\": true,    // Assistant-error-recovery — gates synthesizing a recovery result (assistantUuid/resultUuid)",
    "    // \"714014285\": true,    // CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING",
    "    // \"720735283\": true,    // Marketplace migration",
    "    // \"748063099\": true,    // VM client retry on pipe close",
    "    // \"763725229\": true,    // Developer menu label/visibility",
    "    // \"770567414\": true,    // VM service routing (direct vs persistent pipe)",
    "    // \"790863764\": true,    // device_bash - combined gate with yukonSilver VM support",
    "    // \"873030668\": true,    // sorted-list source config (value flag)",
    "    // \"884132720\": true,    // OAuth scope passthrough - forwards the OAuth token scope into the CLI session env build: o",
    "    // \"939257113\": true,    // Dispatch child session detection — isRemoteDispatchChild qualifier",
    "    // \"975112542\": true,    // Cowork memory remote sync — canSyncCoworkMemoryRemotely()",
    "    // \"982691970\": true,    // Cowork plugin host ops gate (dynamic import)",
    "    // \"1004628546\": true,   // consolidate-memory skill description overrides (value flag)",
    "    // \"1109029378\": true,   // macOS tray usage menu",
    "    // \"1126577245\": true,   // sync/pull config object (value flag; purpose not catalogued)",
    "    // \"1129419822\": true,   // ENABLE_TOOL_SEARCH='auto' env var for LAM sessions",
    "    // \"1143815894\": true,   // DO NOT ENABLE: bypasses the Cowork VM service and silently breaks skills/plugins",
    "    // \"1197768857\": true,   // spaceMemoryBridge feature gate — registry entry rt('1197768857')?Ed:{status:'unavailable'}",
    "    // \"1295378343\": true,   // CLI stream robustness: gapSurviveEnabled/stdinOffset",
    "    // \"1323782925\": true,   // dispatch APe qualifier",
    "    // \"1412563253\": true,   // askUserQuestion preview format ('html')",
    "    // \"1434290056\": true,   // Dispatch code tasks permission mode — bypass-permissions for dispatch sessions (new in v1.",
    "    // \"1544796833\": true,   // session-concurrency limits, e.g. maxConcurrentPerSession (value flag)",
    "    // \"1569828280\": true,   // Binary-asset-fetch gate — if(!et('1569828280')){...gate_off...skipping binary asset fetch}",
    "    // \"1629866860\": true,   // claude_code numeric tuning value (value flag)",
    "    // \"1677081600\": true,   // dispatch orchestrator base URL override (value flag)",
    "    // \"1696890383\": true,   // CLAUDE_COWORK_MEMORY_GUIDE env — passes memory guide to cowork sessions (also in force-ON ",
    "    // \"1703762832\": true,   // onModelRefusalFallback retry - when ON, a refusal response with direction:'retry' in Agent",
    "    // \"1707927936\": true,   // size limit tuning, bytes (value flag)",
    "    // \"1748356779\": true,   // prompt template config: system_prompt/user_prompt (value flag)",
    "    // \"1893165035\": true,   // enabled+categories config object (value flag)",
    "    // \"1928275548\": true,   // framebufferPreview feature — dev-gated (inside MW())",
    "    // \"1936081873\": true,   // system-prompt build-skip",
    "    // \"1942781881\": true,   // Prompt suggestions in sessions",
    "    // \"1947305033\": true,   // augments a tool description",
    "    // \"1972091654\": true,   // askClaude device RPC",
    "    // \"1978029737\": true,   // pluginsSyncIntervalMs (value flag)",
    "    // \"2049450122\": true,   // Session handoff — gates cross-device session activity broadcasting (com.anthropic.claude.s",
    "    // \"2051751800\": true,   // Chrome permission-mode skip_all_permission_checks resolver gate",
    "    // \"2051942385\": true,   // CIC can-use-tool",
    "    // \"2115990222\": true,   // artifactsPane feature gate - NEW static registry feature artifactsPane:DPt() where functio",
    "    // \"2140326016\": true,   // Author-supplied bin stubs error enforcement",
    "    // \"2143883161\": true,   // /code/ route gate",
    "    // \"2216414644\": true,   // Remote session control (Dispatch mobile)",
    "    // \"2216901299\": true,   // Org policy backend check — remote management policy enforcement",
    "    // \"2229805612\": true,   // remote_control_at_startup default",
    "    // \"2246535838\": true,   // Local MCP server prefix (local:)",
    "    // \"2307090146\": true,   // Plugin OAuth storage gate (also added to force-ON defaults map)",
    "    // \"2309422447\": true,   // mergeMessageBufferIfActive",
    "    // \"2339084909\": true,   // VM monitoring fallback (non-heartbeat)",
    "    // \"2340532315\": true,   // Plugin sync on session start",
    "    // \"2345107588\": true,   // GrowthBook cache persistence — persist/seed GrowthBook cache from/into sessions (new in v1",
    "    // \"2345515473\": true,   // Sessions-bridge account-change reevaluation",
    "    // \"2349950458\": true,   // Scheduled task notifications",
    "    // \"2392971184\": true,   // Replay user messages — adds --replay-user-messages to CLI args for session resume; also en",
    "    // \"2393677837\": true,   // PreToolUse hook for worktree-aware tool input validation",
    "    // \"2427043945\": true,   // numeric rate/threshold (value flag)",
    "    // \"2438134137\": true,   // Figma/design OAuth scope expansion",
    "    // \"2614807392\": true,   // Session feature A",
    "    // \"2720310975\": true,   // side-chat tools",
    "    // \"2724639973\": true,   // Session governor evictionEnabled - memory-pressure-based session eviction",
    "    // \"2725876754\": true,   // Org CLI exec policies — gates reading orgCliExecPolicies for plugin tool permission checks",
    "    // \"2726556121\": true,   // INVERTED: ON disables the SSH file-transfer fast-path",
    "    // \"2795002549\": true,   // Projects OAuth scopes",
    "    // \"2860753854\": true,   // consent text override string (value flag)",
    "    // \"2893011886\": true,   // enabled toggle read via value store",
    "    // \"2979038612\": true,   // Session notifications — queueSessionNotification for model switch, folder access",
    "    // \"3045399524\": true,   // session config: enabled/alwaysLoad (value flag)",
    "    // \"3300773012\": true,   // scheduled-task skill description override (value flag)",
    "    // \"3302457740\": true,   // hosts allowlist config (value flag)",
    "    // \"3371831021\": true,   // cuOnlyMode — computer-use-only session variant",
    "    // \"3377630395\": true,   // overlay/window mount toggle",
    "    // \"3531779070\": true,   // agent-mode thinking-display=summarized CLI arg",
    "    // \"3555657854\": true,   // org-scoped plugin-bridge MCP config loading",
    "    // \"3572572142\": true,   // sessions-bridge init - live listener",
    "    // \"3586389629\": true,   // APe interval ms (value flag)",
    "    // \"3602524236\": true,   // isOpenInDefaultAppEnabled file preview",
    "    // \"3633961296\": true,   // plugin enabled-state backfill",
    "    // \"3646818354\": true,   // shouldKillOnIdlePause() returns !Ct('3646818354') - when ON, the session is NOT killed on ",
    "    // \"3691521536\": true,   // Stealth updater — nudge updates when no active sessions",
    "    // \"3723845789\": true,   // Additional Cowork tools",
    "    // \"3758515526\": true,   // official plugins repo override (value flag)",
    "    // \"3778159589\": true,   // Device-stale-relogin — rt('3778159589')?e():A() selecting the relogin path (markDeviceStal",
    "    // \"3807767338\": true,   // seedPolicyLimitsIntoSession / refreshPolicyLimitsPersist - org policy-limit persistence",
    "    // \"3982397363\": true,   // stale-model-clear robustness toggle",
    "    // \"4034153053\": true,   // isEpitaxyPreviewEnabled (gated on native support probe)",
    "    // \"4066504968\": true,   // guided Cowork setup skill description (value flag)",
    "    // \"4116586025\": true,   // louderPenguin / Code tab master gate",
    "    // \"4141490266\": true,   // Framebuffer system prompt injection — adds instructions when Framebuffer server active",
    "    // \"4153934152\": true,   // CLAUDE_CODE_SKIP_PRECOMPACT_LOAD",
    "    // \"4160352601\": true,   // VM heartbeat monitoring",
    "    // \"4282876673\": true,   // async module gate (default ON)",
    "    // \"4293378213\": true,   // device-app tools - INERT in v1.19367.0 (hardcoded off after the flag)",
    "  }",
    "}",
    ""
  ].join("\n");

  function readFileOrNull(fs, p) {
    try {
      return fs.readFileSync(p, "utf8");
    } catch (e) {
      if (e && e.code !== "ENOENT") diag("[cdb-flags] cannot read " + p + ": " + (e && e.message));
      return null;
    }
  }

  function parseOverrides(raw, p) {
    if (raw === null) return null;
    try {
      var cfg = JSON.parse(stripJsonComments(raw));
      var o = cfg && cfg.growthbookOverrides;
      if (o && typeof o === "object" && !Array.isArray(o)) return o;
      if (o !== undefined && o !== null) diag("[cdb-flags] growthbookOverrides in " + p + " must be an object - ignoring");
      return null;
    } catch (e) {
      diag("[cdb-flags] failed to parse " + p + ": " + (e && e.message) + " - ignored");
      return null;
    }
  }

  function readOverrides() {
    var fs = require("fs");
    var paths = configPaths();
    var rawJ = readFileOrNull(fs, paths.json);
    var rawC = readFileOrNull(fs, paths.jsonc);
    if (rawC === null) {
      try {
        fs.writeFileSync(paths.jsonc, TEMPLATE, { flag: "wx" });
        diag("[cdb-flags] created config template at " + paths.jsonc);
      } catch (e2) {}
    }
    var combined = String(rawJ) + " " + String(rawC);
    if (combined === lastRaw) return lastParsed;
    lastRaw = combined;
    var oJ = parseOverrides(rawJ, paths.json);
    var oC = parseOverrides(rawC, paths.jsonc);
    if (!oJ && !oC) { lastParsed = null; return null; }
    var merged = {};
    var k;
    for (k in (oJ || {})) merged[k] = oJ[k];
    for (k in (oC || {})) merged[k] = oC[k];
    lastParsed = merged;
    return merged;
  }

  // Called by the patched features-store setter with the freshly loaded feature
  // map (network / disk cache / deployment-mode). Returns a shallow copy with
  // overrides applied so the caller's raw object (used for the disk cache)
  // stays untouched. Must never throw - flag loading is boot-critical.
  globalThis.__cdbApplyGbOverrides = function (features) {
    try {
      var o = readOverrides();
      if (!o || !features || typeof features !== "object") return features;
      var ids = Object.keys(o);
      if (!ids.length) return features;
      var out = {};
      for (var k in features) out[k] = features[k];
      var applied = [];
      for (var j = 0; j < ids.length; j++) {
        var id = ids[j];
        var v = o[id];
        if (v === null || v === undefined) continue;
        out[id] = typeof v === "boolean"
          ? { on: v, value: v, source: "cdb-override" }
          : { on: true, value: v, source: "cdb-override" };
        applied.push(id + "=" + JSON.stringify(v));
      }
      if (applied.length) {
        var msg = "[cdb-flags] applying " + applied.length + " GrowthBook override(s): " + applied.join(", ");
        if (msg !== announced) { announced = msg; diag(msg); }
      }
      return out;
    } catch (e) {
      diag("[cdb-flags] override hook error: " + (e && e.message));
      return features;
    }
  };
})();
