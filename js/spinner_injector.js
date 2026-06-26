/*
 * spinner_injector.js - runtime brand-glyph -> custom spinner replacement.
 *
 * Injected into the claude.ai webview by patches/add_feature_custom_themes.nim on
 * `dom-ready` (the same hook that injects the theme CSS). The Nim/main side PREPENDS
 *   var __CDB_SPINNER_SPEC = <json|null>;
 * (serialized from the active theme's `spinner` object) ahead of this IIFE. The runtime
 * does NOT read the config file; it only consumes the baked-in global.
 *
 * Behavior (see baseline/SPINNER_INJECTION_NOTES.md for the full design):
 *   - No-ops cleanly when __CDB_SPINNER_SPEC is null/undefined/empty (feature opt-in).
 *   - Finds the Anthropic 7-point brand-star SVGs via a cheap viewBox "0 0 100 100"
 *     pre-filter + a child <path d> matching the signature "m19.6 66.5 19.7-11"
 *     (overridable per spec via spec.match).
 *   - Replaces the matched <svg>'s <path> children using document.createElementNS
 *     (NOT innerHTML -> CSP / Trusted-Types safe). Keeps the <svg> wrapper so the
 *     `fill-current` class + box size are preserved.
 *   - Multi-path with optional per-path `fill` (omitted/"currentColor" -> inherits the
 *     theme accent; explicit hex/hsl -> fixed color, needed for the Mario mushroom).
 *   - Idempotent via a data-cdb-spinner=<versionHash> stamp; the stamp also breaks the
 *     MutationObserver loop (re-seeing our own writes is a cheap no-op).
 *   - MutationObserver on document.documentElement scans ONLY addedNodes, rAF-debounced.
 *   - Optional cdb-anim-<spin|bounce|pulse> class when spec.animation is set (keyframes
 *     ship via the theme CSS / insertCSS path).
 *   - window.__cdbSpinner = { spec, version, sweep, disconnect } for live debugging.
 *   - Logs "[spinner] matched N glyph(s)" on load and on observer hits, so a sudden 0
 *     means the logo geometry drifted (update the signature) - NOT "feature removed".
 *
 * ES5 ONLY (var / function; no arrow / let / const). This file is concatenated into a
 * Nim string and run inside a webview; it must `node --check` clean even though the DOM
 * APIs it calls cannot execute under node.
 */
;(function () {
  "use strict";

  // SPEC is baked in by the patch (var __CDB_SPINNER_SPEC = <json>;). For console
  // testing, define window.__CDB_SPINNER_SPEC before pasting this IIFE.
  var SPEC = (typeof __CDB_SPINNER_SPEC !== "undefined") ? __CDB_SPINNER_SPEC : null;
  if (!SPEC || !isArray(SPEC.paths) || SPEC.paths.length === 0) return;

  var SVGNS = "http://www.w3.org/2000/svg";
  // Detection signatures: distinctive fragments of the Anthropic 7-point star path.
  // Matching on the literal logo geometry is what keeps us from reshaping unrelated
  // 0 0 100 100 icons. We keep SEVERAL fragments from different rays so that if upstream
  // re-emits/normalizes one coordinate run, another fragment still matches (robustness).
  // A theme's `match` (string or array of strings) overrides this set entirely.
  var DEFAULT_SIGS = [
    "m19.6 66.5 19.7-11",  // upper-left ray (the original, confirmed live on v1.15962)
    "19.7-11 .3-1-.3-.5",  // continuation of that ray
    "66.5 19.7-11"         // looser fragment of the same run
  ];
  var SIGS = (function () {
    var m = SPEC.match;
    if (typeof m === "string" && m) return [m];
    if (isArray(m) && m.length) return m;
    return DEFAULT_SIGS;
  })();
  var VIEWBOX = SPEC.viewBox || "0 0 100 100";
  var HAS_VIEWBOX = (typeof SPEC.viewBox === "string" && SPEC.viewBox.length > 0);
  var STAMP_ATTR = "data-cdb-spinner";

  // Cheap djb2 hash of the serialized spec -> the idempotency stamp. Including a version
  // means a theme/spec change re-processes previously-stamped svgs instead of skipping.
  var VER = hash(safeStringify(SPEC));
  var ANIM_CLASS = SPEC.animation ? ("cdb-anim-" + String(SPEC.animation)) : null;

  // --- helpers (ES5-safe; Array.isArray exists in webviews but stay defensive) -------

  function isArray(x) {
    return Array.isArray ? Array.isArray(x) :
      (Object.prototype.toString.call(x) === "[object Array]");
  }

  function safeStringify(x) {
    try { return JSON.stringify(x); } catch (e) { return String(x); }
  }

  function hash(s) {
    var h = 5381, i = s.length;
    while (i) { h = (h * 33) ^ s.charCodeAt(--i); }
    return (h >>> 0).toString(36);
  }

  function log(msg) {
    try { if (window.console && console.log) console.log("[spinner] " + msg); } catch (e) {}
  }

  // --- matcher -----------------------------------------------------------------------

  function isTargetSvg(svg) {
    if (!svg || svg.namespaceURI !== SVGNS) return false;
    if (!svg.tagName || String(svg.tagName).toLowerCase() !== "svg") return false;
    if (svg.getAttribute(STAMP_ATTR) === VER) return false; // already current version
    // cheap pre-filter: brand glyph lives in a 0 0 100 100 box
    var vb = (svg.getAttribute("viewBox") || "").replace(/\s+/g, " ").trim();
    if (vb !== "0 0 100 100") return false;
    // precise: a child <path d> contains any of the star signatures
    var paths = svg.getElementsByTagNameNS(SVGNS, "path");
    for (var i = 0; i < paths.length; i++) {
      var d = (paths[i].getAttribute("d") || "").trim();
      if (d.length === 0) continue;
      for (var k = 0; k < SIGS.length; k++) {
        if (d.indexOf(SIGS[k]) > -1) return true;
      }
    }
    return false;
  }

  // --- replacement (createElementNS, never innerHTML) --------------------------------

  function replace(svg) {
    if (HAS_VIEWBOX) svg.setAttribute("viewBox", VIEWBOX);
    while (svg.firstChild) svg.removeChild(svg.firstChild); // drop the star <path>(s)
    for (var i = 0; i < SPEC.paths.length; i++) {
      var p = SPEC.paths[i];
      if (!p || !p.d) continue;
      var path = document.createElementNS(SVGNS, "path");
      path.setAttribute("d", p.d);
      // omitted / "currentColor" -> inherit theme accent via the svg's fill-current class.
      // explicit hex/hsl -> fixed color (multi-color shapes like the mushroom).
      if (p.fill && p.fill !== "currentColor") path.setAttribute("fill", p.fill);
      svg.appendChild(path);
    }
    if (ANIM_CLASS && svg.classList) svg.classList.add(ANIM_CLASS);
    svg.setAttribute(STAMP_ATTR, VER); // idempotency mark (also breaks the observer loop)
  }

  // --- sweep -------------------------------------------------------------------------

  function sweep(root) {
    if (!root) return 0;
    var n = 0, svgs, i;
    // the root node might itself BE a target svg (added directly)
    if (root.tagName && String(root.tagName).toLowerCase() === "svg") {
      if (isTargetSvg(root)) { replace(root); n++; }
    }
    try {
      svgs = root.querySelectorAll ? root.querySelectorAll("svg") : null;
    } catch (e) { svgs = null; }
    if (svgs) {
      for (i = 0; i < svgs.length; i++) {
        if (isTargetSvg(svgs[i])) { replace(svgs[i]); n++; }
      }
    }
    return n;
  }

  // --- initial full-document pass (glyphs already present) ----------------------------

  try {
    var first = sweep(document.documentElement);
    log("matched " + first + " glyph(s) on load");
  } catch (e) {
    log("initial sweep error: " + (e && e.message ? e.message : e));
  }

  // --- debounced observer -------------------------------------------------------------
  // Scans ONLY addedNodes (+ their nested svgs), never the whole document. The STAMP_ATTR
  // check makes re-seeing our own writes a no-op, so there is no infinite loop. A burst of
  // mutations collapses into a single rAF-scheduled sweep.

  var pending = false;
  var queued = [];
  var schedule = window.requestAnimationFrame
    ? function (fn) { window.requestAnimationFrame(fn); }
    : function (fn) { window.setTimeout(fn, 16); };

  function flush() {
    pending = false;
    var batch = queued;
    queued = [];
    var total = 0;
    for (var k = 0; k < batch.length; k++) {
      try { total += sweep(batch[k]); } catch (e) {}
    }
    if (total) log("matched " + total + " glyph(s) (observer)");
  }

  var obs = new MutationObserver(function (muts) {
    for (var i = 0; i < muts.length; i++) {
      var added = muts[i].addedNodes;
      if (!added) continue;
      for (var j = 0; j < added.length; j++) {
        if (added[j].nodeType === 1) queued.push(added[j]); // ELEMENT_NODE only
      }
    }
    if (pending || queued.length === 0) return;
    pending = true;
    schedule(flush);
  });

  try {
    obs.observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {
    log("observer attach error: " + (e && e.message ? e.message : e));
  }

  // --- expose for live debugging / teardown ------------------------------------------

  window.__cdbSpinner = {
    spec: SPEC,
    version: VER,
    sweep: sweep,
    disconnect: function () { try { obs.disconnect(); } catch (e) {} }
  };
})();
