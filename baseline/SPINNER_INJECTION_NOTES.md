# Spinner / Brand-Glyph Replacement via Webview Injection

**Status:** Design notes (not yet implemented). Needs iterative *live* testing in the
running app by the user (single-instance lock + no auto-install in this project).

**Goal:** Replace the Anthropic 7-point "starburst/asterisk" brand glyph that
claude.ai renders as the greeting icon and the in-progress loading/thinking
spinner, swapping in an arbitrary per-theme shape (e.g. a Super Mario mushroom),
**without** breaking unrelated UI, and keeping the color following the theme accent.

---

## 0. Why injection (not a bundle string-replace)

The star SVG is rendered by **remote claude.ai code**, not the local Electron bundle.
Verified against the freshly-extracted bundle
(`tmp/app.asar.contents/.vite/build/index.js`): none of the candidate signals appear
there:

| Signal | In local bundle? |
|--------|------------------|
| `fill-current` | NO |
| star path prefix `m19.6 66.5` | NO |
| `text-accent-brand` | NO |
| `viewBox="0 0 100 100"` | NO |

So a Nim string-replace patch is impossible. We must inject JS into the webview, the
same way the theme patch already injects CSS.

### Reuse the existing injection hook

`patches/add_feature_custom_themes.nim` already installs (lines ~218-229):

```js
_app.on("web-contents-created", function(_ev, wc){
  wc.on("dom-ready", function(){
    var url = wc.getURL() || "";
    if (url.indexOf("devtools://") === 0) return;
    if (/^https?:\/\/(localhost|127\.0\.0\.1)/.test(url)) return;
    wc.insertCSS(__cdb_css);
    wc.executeJavaScript(__cdb_js); // <-- spinner installer goes here
  });
});
```

`dom-ready` fires once per navigation/document. For a SPA like claude.ai the document
is **not** reloaded on in-app navigation, so the installer must itself be resilient to
later DOM churn (MutationObserver) rather than relying on re-injection. The IIFE below
is also guarded so a second `executeJavaScript` (e.g. on a real reload) is a no-op.

**The spinner spec must be embedded into the injected JS string at Nim build time**
(read from the same `claude-desktop-bin.json` config the theme patch reads, under a new
`spinner` key per theme), exactly like `__cdb_css` is built. The runtime JS does
**not** read the config file itself - the Nim/main-process side serializes the spec to
JSON and string-concatenates it into the script, so the renderer receives a literal
object.

---

## 1. Identifying the glyph reliably

The star glyph appears in multiple places (greeting header, in-progress "thinking"
spinner, possibly app logo / send button). We want to catch the **brand/loading**
instances and not, say, an unrelated icon that happens to share a wrapper class.

### Candidate signals (ranked)

| # | Signal | Precision | Stability | Verdict |
|---|--------|-----------|-----------|---------|
| a | `<svg viewBox="0 0 100 100">` containing exactly one `<path>` whose `d` **starts with the known star coordinates** | **Highest** | The path is the literal Anthropic logo geometry - extremely unlikely to be reused for anything that is *not* the brand glyph. Coordinates are stable across releases (it's the logo). | **PRIMARY matcher** |
| b | Wrapper classes `text-accent-brand` / `fill-current` | Medium | Tailwind utility classes; `text-accent-brand` is reasonably brand-specific but could appear on other accent-colored icons. `fill-current` is extremely generic. | Secondary / confirmation only |
| c | Ancestor context (`.font-display` greeting vs animated thinking state) | Low | Distinguishes *instances* but not the glyph itself; brittle to layout refactors. | Do **not** gate on this - we *want* to catch all instances |

**Decision: match on the path-`d` prefix (signal a).** It is the single most precise,
self-describing signal: the geometry *is* the brand mark. We do not need the wrapper
classes, the viewBox, or the ancestor - though we additionally require
`viewBox="0 0 100 100"` as a cheap pre-filter so the observer skips the vast majority
of SVGs without a substring scan.

### The known star path

From the user-provided live DOM, the path begins:

```
m19.6 66.5 19.7-11 .3-1-.3-.5h-1l-3.3-.2-11.2-.3L14 53l-9.5-.5-2.4-.5L0 49l.2-1.5 2-1.3 ...Z
```

The snippet was truncated (`...`) in the middle, so we do **not** have the complete
path string and must **not** hardcode the full `d` as an equality check. Instead match
on a **distinctive leading substring** that is long enough to be unique but short
enough to survive minor coordinate re-emission:

```
PATH_SIGNATURE = "m19.6 66.5 19.7-11"
```

This 18-char prefix is the start of the upper-left ray of the asterisk and is highly
distinctive (no other icon would start a path at exactly `19.6 66.5` then draw
`19.7-11`). We test with `path.getAttribute("d").trim().startsWith(PATH_SIGNATURE)`
(also try a looser `indexOf` fallback in case claude.ai prepends a `M0 0` or
normalizes whitespace - see code).

> **Maintenance note (version-sensitive):** if Anthropic ever re-exports the logo with
> different coordinates, `PATH_SIGNATURE` must be updated. This is exactly the kind of
> remote-rendered value that this repo cannot pin - so the installer logs a one-line
> diagnostic (`[spinner] matched N glyph(s)`) so the user can tell from the webview
> console whether the signature still matches after an upstream change. Treat a sudden
> `matched 0` as "the logo geometry changed", not "feature removed".

---

## 2. Replacement technique

### Options

| Approach | How | Pros | Cons |
|----------|-----|------|------|
| **(a) Rewrite `<path>` children of the matched `<svg>`** | Keep the `<svg>` element, keep its `viewBox` and `class` (incl. `fill-current`), replace its inner `<path>` markup with the spec's paths | Inherits theme accent via `fill-current` -> `--accent-brand` for any `currentColor` path; keeps claude.ai's own wrapper/animation classes; minimal DOM disturbance; multi-color possible by adding explicit `fill` on extra paths | Must set inner SVG markup; React may later re-render the SVG and revert it (handled by re-observation + idempotency marker) |
| (b) Replace entire inner SVG markup of wrapper | `wrapper.innerHTML = "<svg ...>...</svg>"` | Total control of viewBox/markup | Loses claude.ai's own `class`/animation on the `<svg>`; more to get right; same React-revert risk |
| (c) CSS-only (hide svg + `mask-image`/`background` on wrapper) | `svg{display:none}` + wrapper gets a data-URI mask | No JS DOM writes | Can't swap an inline path with CSS; mask needs a stable box (wrapper size varies: `w-8`, smaller thinking spinner); single-color only (mask) or needs layered backgrounds for multicolor; fragile sizing | 

### Decision: **(a)** - rewrite the `<path>` children, keep the `<svg>`.

Rationale: keeping the original `<svg>` (with its `viewBox="0 0 100 100"` and its
`fill-current` class) means:

- single-color shapes that use `fill="currentColor"` automatically follow the theme
  accent (because `fill-current` resolves `currentColor` to `text-accent-brand`);
- claude.ai's own animation classes on the `<svg>`/wrapper keep working;
- the box size (`w-8` greeting, smaller thinking) is preserved because we don't touch
  the wrapper.

We set the paths by clearing the SVG's existing children and inserting new
`<path>` elements built from the spec (using `document.createElementNS` for correctness
in the SVG namespace - **not** `innerHTML`, which is unreliable for SVG content and
trips strict CSP/Trusted-Types). If the spec provides a different `viewBox`, we update
the `<svg>`'s `viewBox` attribute too (default keeps `0 0 100 100`).

### Idempotency, SPA re-renders, and no observer loops

Three concerns, three guards:

1. **Don't re-process the same node.** After replacing, stamp the `<svg>` with
   `data-cdb-spinner="<specVersion>"`. The matcher skips any `<svg>` already carrying
   the *current* version stamp. (Including a version/hash lets a theme change
   re-process previously-stamped nodes.)

2. **Survive SPA re-renders.** React may unmount/remount the greeting or re-render the
   thinking spinner, producing brand-new `<svg>` nodes (without our stamp). A persistent
   `MutationObserver` on `document.documentElement` (`childList:true, subtree:true`)
   re-runs the matcher on added subtrees, so new instances get replaced too. We also do
   **one** initial full-document sweep at install time for nodes already present.

3. **Avoid infinite observer loops.** Our own DOM writes (clearing children, adding
   paths, setting `data-cdb-spinner`) are mutations the observer would see. Two
   safeguards:
   - The matcher early-returns on any `<svg>` already stamped with the current version,
     so re-seeing our own output is a cheap no-op.
   - We wrap each replacement in a re-entrancy flag (`__cdb_busy`) and, more robustly,
     **disconnect the observer is not needed** because the stamp check already breaks
     the loop; but we additionally **debounce** processing via `requestAnimationFrame`
     so a burst of mutations collapses into one sweep. (Disconnect/reconnect around our
     writes is offered as an even stricter alternative in the code comments, but the
     stamp guard alone is sufficient and avoids missing concurrent external mutations.)

Performance: the observer callback only scans `addedNodes` (and their `querySelectorAll`
for nested svgs), not the whole document, and the per-svg test is a cheap
`viewBox` attribute compare before any `d` substring scan. Cost is negligible.

---

## 3. Per-theme spinner spec format

Add an optional `spinner` object to a theme (in `claude-desktop-bin.json`, either under
a built-in theme override or a custom theme). Shape:

```jsonc
{
  "activeTheme": "mario",
  "themes": {
    "mario": {
      "--accent-brand": "0 84% 52%",
      // ... other CSS vars ...
      "spinner": {
        "viewBox": "0 0 100 100",        // optional, default "0 0 100 100"
        "match": "m19.6 66.5 19.7-11",   // optional override of PATH_SIGNATURE
        "animation": "spin",             // optional: "spin" | "bounce" | "pulse" | null
        "paths": [
          { "d": "M...", "fill": "#E52521" },
          { "d": "M...", "fill": "#FFFFFF" },
          { "d": "M...", "fill": "currentColor" }
        ]
      }
    }
  }
}
```

### Field semantics

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `paths` | array of `{d, fill?}` | (required) | Ordered `<path>` elements. `fill` omitted or `"currentColor"` -> follows theme accent via `fill-current`. Explicit hex/`hsl()` -> fixed color (needed for multi-color shapes like the mushroom). |
| `viewBox` | string | `"0 0 100 100"` | SVG coordinate system. Keep `0 0 100 100` to match the original and avoid resizing surprises. |
| `match` | string | built-in `PATH_SIGNATURE` | Lets a theme override the detection substring if upstream geometry changes, without rebuilding the patch. |
| `animation` | string\|null | `null` | Optional injected animation (see section 4). `null` = inherit whatever claude.ai applies. |

The **default star** is effectively `{ "paths": [{ "d": "<full star path>", "fill":
"currentColor" }] }` - single path, accent-colored. A mushroom needs multiple paths
with explicit fills (red cap, white spots/face, optional dark outline).

### How the injected JS consumes it

The Nim/main side serializes the active theme's `spinner` object to JSON and bakes it
into the script as `var SPEC = <json>;`. The IIFE:

1. bails immediately if `SPEC` is falsy or `SPEC.paths` is empty (feature opt-in);
2. computes a `specVersion` (cheap hash of the JSON) for the idempotency stamp;
3. installs the sweep + observer described above;
4. for each matched `<svg>`: sets `viewBox` if provided, removes existing children,
   appends one `<path>` per `SPEC.paths` entry (namespaced), applies optional animation
   class, stamps `data-cdb-spinner=specVersion`.

---

## 4. Animation

The original is a static glyph; claude.ai animates it during loading via its **own**
CSS classes on the wrapper/`<svg>` (e.g. a pulse/spin while "thinking"). Because we keep
the original `<svg>` and wrapper (approach a), **those classes still apply to our
replaced paths for free** - we generally do nothing and inherit the existing motion.

If a theme wants an *additional* or *custom* motion (`animation: "spin"|"bounce"|
"pulse"`), inject a scoped keyframes block **once** and add a class to the replaced
`<svg>`:

```css
@keyframes cdbSpin   { to   { transform: rotate(360deg); } }
@keyframes cdbBounce { 0%,100%{transform:translateY(0)} 50%{transform:translateY(-12%)} }
@keyframes cdbPulse  { 0%,100%{opacity:1} 50%{opacity:.45} }
svg[data-cdb-spinner].cdb-anim-spin   { animation: cdbSpin 1s linear infinite;        transform-origin:50% 50%; transform-box:fill-box; }
svg[data-cdb-spinner].cdb-anim-bounce { animation: cdbBounce .8s ease-in-out infinite; transform-origin:50% 50%; transform-box:fill-box; }
svg[data-cdb-spinner].cdb-anim-pulse  { animation: cdbPulse 1.2s ease-in-out infinite; }
```

Notes to avoid **fighting** claude.ai's own animation:

- Only add the `cdb-anim-*` class when `SPEC.animation` is set; otherwise leave motion
  entirely to claude.ai.
- Use `transform-box: fill-box; transform-origin: 50% 50%` so a `spin` rotates about the
  glyph's own center regardless of the SVG box.
- If both our animation and claude.ai's apply `transform`/`animation` to the *same*
  element they will conflict (last-wins / shorthand override). Scoping our rule to the
  `<svg>` while claude.ai typically animates a *wrapper* avoids most clashes; if a theme
  reports jitter, prefer `animation: null` and rely on the native motion.
- The keyframes can be injected via the existing `wc.insertCSS()` path (append to
  `__cdb_css`) so it lives in the CSS layer, not the JS string.

---

## 5. Ready-to-test MUSHROOM SVG (Super Mario, viewBox `0 0 100 100`)

Recognizable red-cap mushroom: domed red cap, white circular spots on the cap, pale
stem/face, dark outline optional. Drop the `paths` array straight into a theme's
`spinner`. Colors: `#E52521` cap, `#FFFFFF` spots/face, `#3A2A1A` outline (optional),
`#F2C9A0`/`#FAD9C0` face shading optional.

```jsonc
"spinner": {
  "viewBox": "0 0 100 100",
  "animation": "bounce",
  "paths": [
    {
      "comment": "dark outline (drawn first, behind) - optional; remove for flat look",
      "d": "M50 10c-21 0-38 15-38 35 0 6 3 10 8 12 2 1 4 2 4 5v16c0 5 4 9 9 9h34c5 0 9-4 9-9V67c0-3 2-4 4-5 5-2 8-6 8-12 0-20-17-35-38-35z",
      "fill": "#3A2A1A"
    },
    {
      "comment": "red cap (dome)",
      "d": "M50 14c-19 0-34 13-34 31 0 5 3 8 7 9 3 1 6 1 9 1h36c3 0 6 0 9-1 4-1 7-4 7-9 0-18-15-31-34-31z",
      "fill": "#E52521"
    },
    {
      "comment": "pale face / stem area (lower band)",
      "d": "M30 56h40v16c0 4-3 7-7 7H37c-4 0-7-3-7-7V56z",
      "fill": "#FAD9C0"
    },
    {
      "comment": "white spot - large, center-left of cap",
      "d": "M38 30a8 8 0 1 0 0.01 0z",
      "fill": "#FFFFFF"
    },
    {
      "comment": "white spot - top center",
      "d": "M57 22a5 5 0 1 0 0.01 0z",
      "fill": "#FFFFFF"
    },
    {
      "comment": "white spot - right of cap",
      "d": "M68 36a6 6 0 1 0 0.01 0z",
      "fill": "#FFFFFF"
    },
    {
      "comment": "left eye",
      "d": "M42 64a3 3 0 1 0 0.01 0z",
      "fill": "#3A2A1A"
    },
    {
      "comment": "right eye",
      "d": "M58 64a3 3 0 1 0 0.01 0z",
      "fill": "#3A2A1A"
    }
  ]
}
```

> The `comment` keys are ignored by the consumer (only `d` and `fill` are read); they
> are there for readability and can be stripped. If JSONC comments aren't acceptable in
> the real config, delete the `"comment"` lines. The circle-via-arc trick
> (`a R R 0 1 0 0.01 0z`) draws a full circle of radius `R` for the spots/eyes.

A **minimal flat** variant (no outline, 3 colors) for first testing:

```jsonc
"spinner": {
  "viewBox": "0 0 100 100",
  "paths": [
    { "d": "M50 14c-19 0-34 13-34 31 0 5 3 8 7 9 3 1 6 1 9 1h36c3 0 6 0 9-1 4-1 7-4 7-9 0-18-15-31-34-31z", "fill": "#E52521" },
    { "d": "M30 56h40v16c0 4-3 7-7 7H37c-4 0-7-3-7-7V56z", "fill": "#FAD9C0" },
    { "d": "M38 30a8 8 0 1 0 0.01 0z", "fill": "#FFFFFF" },
    { "d": "M57 22a5 5 0 1 0 0.01 0z", "fill": "#FFFFFF" },
    { "d": "M68 36a6 6 0 1 0 0.01 0z", "fill": "#FFFFFF" }
  ]
}
```

---

## 6. The injected JS (copy-pasteable IIFE)

This is the runtime installer. `SPEC` is injected by the Nim/main side (serialized from
the active theme's `spinner` object). For ad-hoc live testing you can paste this into
the webview DevTools console after defining `SPEC` yourself.

```js
;(function () {
  // SPEC is baked in by the patch (var SPEC = <json from theme.spinner>;).
  // For console testing, define it above this IIFE.
  var SPEC = (typeof __CDB_SPINNER_SPEC !== "undefined") ? __CDB_SPINNER_SPEC : null;
  if (!SPEC || !Array.isArray(SPEC.paths) || SPEC.paths.length === 0) return;

  var SVGNS = "http://www.w3.org/2000/svg";
  var DEFAULT_SIG = "m19.6 66.5 19.7-11";           // start of the Anthropic star ray
  var SIG = (typeof SPEC.match === "string" && SPEC.match) ? SPEC.match : DEFAULT_SIG;
  var VIEWBOX = SPEC.viewBox || "0 0 100 100";

  // Cheap version stamp so a theme change re-processes previously-stamped svgs.
  function hash(s){ var h=5381,i=s.length; while(i) h=(h*33)^s.charCodeAt(--i); return (h>>>0).toString(36); }
  var VER = hash(JSON.stringify(SPEC));
  var STAMP_ATTR = "data-cdb-spinner";

  var ANIM_CLASS = SPEC.animation ? ("cdb-anim-" + String(SPEC.animation)) : null;

  function isTargetSvg(svg) {
    if (!svg || svg.namespaceURI !== SVGNS || svg.tagName.toLowerCase() !== "svg") return false;
    if (svg.getAttribute(STAMP_ATTR) === VER) return false;            // already current
    // cheap pre-filter: viewBox must look like the brand glyph box
    var vb = (svg.getAttribute("viewBox") || "").trim();
    if (vb !== "0 0 100 100") return false;
    // precise: a child <path d> begins with the star signature
    var paths = svg.getElementsByTagNameNS(SVGNS, "path");
    for (var i = 0; i < paths.length; i++) {
      var d = (paths[i].getAttribute("d") || "").trim();
      if (d.indexOf(SIG) === 0 || d.indexOf(SIG) > -1) return true;    // prefix, else substring fallback
    }
    return false;
  }

  function replace(svg) {
    if (SPEC.viewBox) svg.setAttribute("viewBox", VIEWBOX);
    while (svg.firstChild) svg.removeChild(svg.firstChild);            // drop the star <path>(s)
    for (var i = 0; i < SPEC.paths.length; i++) {
      var p = SPEC.paths[i];
      if (!p || !p.d) continue;
      var path = document.createElementNS(SVGNS, "path");
      path.setAttribute("d", p.d);
      // omitted/currentColor -> inherit theme accent via the svg's fill-current class
      if (p.fill && p.fill !== "currentColor") path.setAttribute("fill", p.fill);
      svg.appendChild(path);
    }
    if (ANIM_CLASS) svg.classList.add(ANIM_CLASS);
    svg.setAttribute(STAMP_ATTR, VER);                                // idempotency mark (also breaks observer loop)
  }

  function sweep(root) {
    if (!root) return 0;
    var n = 0, svgs;
    try { svgs = (root.querySelectorAll ? root.querySelectorAll("svg") : []); } catch (e) { return 0; }
    for (var i = 0; i < svgs.length; i++) {
      if (isTargetSvg(svgs[i])) { replace(svgs[i]); n++; }
    }
    // root itself might BE an svg (added directly)
    if (root.tagName && root.tagName.toLowerCase() === "svg" && isTargetSvg(root)) { replace(root); n++; }
    return n;
  }

  // Initial full-document pass for glyphs already present.
  try { var first = sweep(document.documentElement); if (first) console.log("[spinner] matched " + first + " glyph(s) on load"); }
  catch (e) { console.log("[spinner] initial sweep error: " + e.message); }

  // Debounced observer: collapse mutation bursts into one rAF-scheduled sweep.
  // The STAMP_ATTR check makes re-seeing our own writes a no-op, so no infinite loop.
  var pending = false, queued = [];
  var obs = new MutationObserver(function (muts) {
    for (var i = 0; i < muts.length; i++) {
      var added = muts[i].addedNodes;
      for (var j = 0; j < added.length; j++) {
        if (added[j].nodeType === 1) queued.push(added[j]);           // ELEMENT_NODE only
      }
    }
    if (pending || queued.length === 0) return;
    pending = true;
    (window.requestAnimationFrame || window.setTimeout)(function () {
      pending = false;
      var batch = queued; queued = [];
      var total = 0;
      for (var k = 0; k < batch.length; k++) total += sweep(batch[k]);
      if (total) console.log("[spinner] matched " + total + " glyph(s) (observer)");
    }, 16);
  });
  obs.observe(document.documentElement, { childList: true, subtree: true });

  // expose for live debugging / teardown
  window.__cdbSpinner = { spec: SPEC, version: VER, sweep: sweep, disconnect: function(){ obs.disconnect(); } };
})();
```

**Stricter alternative for loop-avoidance** (only if the stamp guard proves
insufficient on some claude.ai layout): in `replace()`, `obs.disconnect()` before the
DOM writes and `obs.observe(...)` again after. The downside is missing any *external*
mutation that lands during our write window, so the stamp-guard approach above is
preferred; this is a fallback.

---

## 7. Risks & live-test checklist

This is inherently fragile (remote-rendered, minified, version-sensitive) and **must be
tested iteratively in the running app by the user** - this repo does not auto-build or
auto-install, and a single-instance lock means the user runs the patched build and
reports back. There is no way to validate the match from the bundle alone.

### Risks

- **`PATH_SIGNATURE` drift.** If Anthropic re-exports the logo geometry, the prefix
  stops matching and `matched 0` appears in the console. Mitigation: the `match` field
  lets a theme override the signature without a rebuild; the console diagnostic makes
  the failure visible.
- **Over-matching.** If the star path is reused by an icon we did *not* want to change
  (e.g. a tiny inline logo in a menu), it'll be swapped too. The `viewBox 0 0 100 100`
  pre-filter plus the very specific path signature make collateral hits unlikely, but
  verify the app logo (see checklist).
- **React revert race.** React may re-render a matched `<svg>` right after we patch it,
  briefly showing the star before the observer re-patches. Usually imperceptible; if it
  flickers, the rAF debounce can be lowered to `0`/microtask.
- **CSP / Trusted Types.** We use `createElementNS` + `setAttribute` (not `innerHTML`),
  which is allowed under strict CSP; do **not** switch to `innerHTML` for SVG.
- **Animation conflict.** Theme `animation` + claude.ai's own animation on overlapping
  elements can clash; default `animation: null` avoids this.

### Live-test checklist (user runs the patched build)

1. **Greeting glyph replaced** - the "Good afternoon, Patrick" header icon shows the
   mushroom, not the star.
2. **Thinking/loading spinner replaced** - start a message; the in-progress spinner
   shows the mushroom (and animates, whether via claude.ai's motion or `SPEC.animation`).
3. **App logo NOT broken** - any window-chrome / titlebar / sidebar brand logo is either
   intentionally changed *consistently* or left intact; confirm nothing is blank or
   mis-sized. (If the logo uses the same path+viewBox and you want it left alone, tighten
   the matcher with an ancestor check - but default is "replace all brand glyphs".)
4. **Color follows theme accent** - single-color/`currentColor` paths render in the
   theme's `--accent-brand`; explicit-fill paths (red cap etc.) render as specified.
5. **No console errors** - open the webview DevTools console; expect only
   `[spinner] matched N glyph(s)` lines, no exceptions, no Trusted-Types violations.
6. **SPA navigation keeps working** - navigate between chats/Projects/settings and back;
   newly rendered greeting/spinner instances still get replaced (observer working), and
   navigation itself is unaffected (no freeze from the observer).
7. **Idempotency** - leave the app open through several re-renders; confirm no runaway
   CPU (observer not looping) and the glyph doesn't flicker between shapes.
8. **Theme switch** - change the active theme's spinner and relaunch; the new shape
   appears (version stamp forces re-process).

### How to iterate fast without rebuilding

Paste section 6's IIFE into the **webview DevTools console** (right-click ->
Inspect on the claude.ai view, or the app's devtools) after defining
`window.__CDB_SPINNER_SPEC = { ...the spinner object... }`. This validates the matcher
and shape live before committing it to the patch. Use `window.__cdbSpinner.sweep(document)`
to re-run manually and `window.__cdbSpinner.disconnect()` to stop the observer.

---

## 8. Implementation outline (when we build it)

- **Where:** extend `add_feature_custom_themes.nim` (it already owns the
  `web-contents-created`/`dom-ready` injection and reads `claude-desktop-bin.json`).
  Add the spinner installer JS as a second `staticRead`-style snippet in `js/` and have
  the Nim build serialize `cfg.themes[active].spinner` (or a top-level `cfg.spinner`) to
  JSON, concatenated as `var __CDB_SPINNER_SPEC = <json>;` ahead of the IIFE.
- **Keyframes:** append the section-4 CSS to `__cdb_css` so it ships via `insertCSS`.
- **Guard:** the IIFE is self-guarding (returns on falsy/empty spec, stamps nodes), so a
  second `executeJavaScript` on reload is safe. Match the existing patch's idempotency
  philosophy: any "already applied" assertion must check the **end state** (e.g. spec
  baked in), per the repo's Rule 6 - do not key off the absence of the star.
- **Break risk:** LOW-MEDIUM. No regex on the local bundle (so the *patch* won't fail to
  apply on upstream bumps), but the **runtime match** depends on remote geometry; that
  risk is surfaced via the console diagnostic, not a build failure.
