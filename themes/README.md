# Claude Desktop Custom Themes

Create your own themes for Claude Desktop on Linux by overriding CSS variables.
Themes are now **dual light/dark**: each theme defines a `light` and a `dark`
palette, and the app's own light/dark toggle (Settings -> Appearance) picks the
matching one live.

## Preview - Mario theme (light + dark)

The same theme, both variants - toggle Settings -> Appearance to switch:

| Light (overworld) | Dark (underground) |
|-------------------|--------------------|
| ![Mario light](mario/2026-06-26_14-46-chat-light.png) | ![Mario dark](mario/2026-06-26_14-46-chat-dark.png) |

Note the loading glyph: each theme can replace Claude's starburst with a custom
SVG spinner (Mario gets a mushroom). See [SPINNER_SHAPES.md](../baseline/SPINNER_SHAPES.md).

## What's new: dual light/dark variants

Each theme ships **two** palettes - a `light` block and a `dark` block. The patch
injects them on mode-scoped selectors:

- `light` -> `:root, [data-mode=light]`
- `dark` -> `.darkTheme, [data-mode=dark], .dark` (emitted second so it wins a
  specificity tie)

Because both blocks are always present and scoped by mode, **Claude Desktop's own
light/dark toggle (Settings -> Appearance) now works** and picks the variant that
matches the current mode. This is the headline fix. Previously a single palette was
forced regardless of mode (everything was injected with `!important` on `:root`),
which broke light mode - switching to light still showed the dark palette. You no
longer need to pin the app to dark mode for a theme to look right.

The element overrides (sidebar, content panes, popovers, scrims, scrollbars, etc.)
reference the semantic tokens, so they are emitted **once** and are automatically
correct in whichever mode is active. Only the decorative glow shadows are gated to
dark mode (they look gaudy on a light surface).

## JSON schema

Place your theme config at `~/.config/Claude/claude-desktop-bin.json`. The
dual-variant shape:

```jsonc
{
  "activeTheme": "<name>",
  "themes": {
    "<name>": {
      "light":  { /* full token set, LIGHT-mode values */ },
      "dark":   { /* full token set, DARK-mode values  */ },
      "chatFont": "optional CSS font-family string",   // optional, shared both modes
      "spinner": { /* optional loading-glyph override, see below */ }
    }
  }
}
```

A minimal real example (only the tokens you want to change; unspecified tokens fall
through to claude.ai's stock values for that mode):

```jsonc
{
  "activeTheme": "my-theme",
  "themes": {
    "my-theme": {
      "light": {
        "--bg-000": "0 0% 100%",
        "--bg-100": "30 30% 97%",
        "--text-000": "30 10% 12%",
        "--accent-brand": "15 63% 50%",
        "--border-100": "30 8% 20%",            // DARK-ish in light mode (see polarity tip)
        "--claude-background-color": "#fbfaf7",
        "--claude-foreground-color": "#1a1814"
      },
      "dark": {
        "--bg-000": "30 6% 16%",
        "--bg-100": "30 6% 12%",
        "--text-000": "40 30% 96%",
        "--accent-brand": "15 70% 62%",
        "--border-100": "40 14% 84%",           // LIGHT-ish in dark mode (see polarity tip)
        "--claude-background-color": "#27241f",
        "--claude-foreground-color": "#f5f2ea"
      }
    }
  }
}
```

- Set `activeTheme` to a built-in name (see below) or a key in your `themes` object.
- Restart Claude Desktop to apply changes.

> **Backward compatibility:** a **flat** theme object - one with `--token` keys
> directly and **no** `light`/`dark` blocks (the old schema) - still works. The patch
> treats the whole object as **both** light and dark, so old single-palette configs
> keep applying exactly as before.

## Built-in themes (dual-variant)

All built-ins now ship dual light + dark. Setting just `activeTheme` to one of these
works with **no `themes` block needed** - the built-ins were regenerated to
dual-variant and live inside the patch:

| `activeTheme` | Light identity | Dark identity | Spinner |
|---------------|----------------|---------------|---------|
| `sweet` | white / soft-pink surfaces, magenta-rose accent | deep plum-violet surfaces, hot-pink accent | blossom (`spin`) |
| `nord` (alias: `nordic`) | Nord Snow Storm: cool off-white surfaces, frost-blue accent | Nord Polar Night: slate-blue surfaces, frost-cyan accent | snowflake (`spin`) |
| `catppuccin-mocha` | Catppuccin **Latte** (light) | Catppuccin **Mocha** (dark) - mauve accent | cat head (`pulse`) |
| `catppuccin-macchiato` | Catppuccin **Latte** (light) | Catppuccin **Macchiato** (dark) - mauve accent | cat head (`pulse`) |
| `catppuccin-frappe` | Catppuccin **Latte** (light) | Catppuccin **Frappe** (dark) - mauve accent | cat head (`pulse`) |
| `catppuccin-latte` | Catppuccin **Latte** (light) | Catppuccin **Mocha** (dark) | coffee cup (`pulse`) |
| `mario` | sky-blue overworld: pale-blue surfaces, dark-navy text, Mario-red accent | warm-brick underground: brown surfaces, cream text, Mario-red accent + coin-gold/pipe-green status | mushroom (`bounce`) |

Notes:

- **`nord` / `nordic`:** the canonical built-in key is `nord`; `nordic` is an alias
  that resolves to it. The `themes/nordic/` folder's config uses `"activeTheme":
  "nord"` to match. Either name works.
- The three dark Catppuccin variants (`-mocha`, `-macchiato`, `-frappe`) all use
  **Latte** as their light variant - Catppuccin only defines one light flavour.
- A built-in resolves entirely from the patch. If `activeTheme` matches nothing (not
  a custom theme, not a built-in, not an alias) the patch logs a **loud** console
  line listing the valid built-in names and applies nothing - it never silently
  succeeds.

## Spinner reshape (per-theme loading glyph)

A theme can replace the Anthropic loading "star" with its own SVG shape via an
optional `spinner` field. The patch injects a small renderer-side script that finds
claude.ai's brand-star glyph (matched by its path signature) and swaps in your paths,
keeping the `<svg>` wrapper so the accent color and box size are preserved. Animation
keyframes ship alongside the theme CSS.

The seven shapes that ship with the built-ins:

| Theme | Shape | Color | Animation |
|-------|-------|-------|-----------|
| `mario` | Mario mushroom | multi-color (baked hex) | `bounce` |
| `sweet` | 5-petal blossom | accent (`currentColor`) | `spin` |
| `nord` | 6-point snowflake | accent (`currentColor`) | `spin` |
| `catppuccin-mocha` | cat head | accent (`currentColor`) | `pulse` |
| `catppuccin-macchiato` | cat head | accent (`currentColor`) | `pulse` |
| `catppuccin-frappe` | cat head | accent (`currentColor`) | `pulse` |
| `catppuccin-latte` | coffee cup | accent (`currentColor`) | `pulse` |

Shape format (in your theme object):

```jsonc
"spinner": {
  "viewBox": "0 0 100 100",          // optional, default "0 0 100 100"
  "match": "m19.6 66.5 19.7-11",     // optional override of the star path signature
  "animation": "spin|bounce|pulse|null",
  "paths": [ { "d": "...", "fill": "#hex" }, ... ]   // omit "fill" => currentColor (follows accent)
}
```

See [baseline/SPINNER_SHAPES.md](../baseline/SPINNER_SHAPES.md) for the full spec,
the literal path data for each shape, and a DevTools-console recipe for swapping a
shape live (no rebuild).

> **The spinner is remote-rendered, so it is version-sensitive.** The star glyph
> lives in claude.ai's bundle, which this repo cannot pin. If you see
> `[spinner] matched 0` in the console, the upstream glyph geometry changed - set a
> per-theme `match` override to the new path signature (no rebuild needed). A
> `matched 0` is **not** "feature removed", it is "geometry drifted".

## Token reference (v1.15962)

> **This section was corrected for v1.15962.** The accent token families
> `--accent-main-*`, `--accent-secondary-*`, and the prose tokens `--tw-prose-*`
> **do not exist** in this build - older versions of this doc listed them as
> themeable. They are gone. See
> [baseline/THEME_TOKEN_MAP.md](../baseline/THEME_TOKEN_MAP.md) for the full,
> mined-from-the-live-app token reference.

Values are HSL components **without** the `hsl()` wrapper - `"hue sat% light%"`
(e.g. `"285 50% 8%"`). Tailwind utilities compile to `hsl(var(--bg-000))`, so
overriding the variable themes every utility that reads it.

### Backgrounds & text

| Variable | Purpose |
|----------|---------|
| `--bg-000` | Lightest surface - panels / cards / popovers float here |
| `--bg-100` | Content panes / dialogs |
| `--bg-200` | Sidebar |
| `--bg-300` | "Darker" sidebar sub-variant |
| `--bg-400` / `--bg-500` | Content backdrop (darkest) / deepest |
| `--text-000` / `--text-100` | Primary text (`000` == `100`) |
| `--text-200` / `--text-300` | Secondary text |
| `--text-400` / `--text-500` | Muted text |

> **Surface hierarchy gotcha:** the main content backdrop is the **darkest** level
> (`--bg-400`); panels and popovers float **above** it at `--bg-000` (the lightest).
> Don't flatten everything onto one `--bg` level or you lose the depth.

### Accents (the real tokens)

| Variable | Purpose |
|----------|---------|
| `--accent-brand` | The brand accent (clay by default). The single most visible accent: checkboxes, scrollbars, selection, focus glow, spinner all read it. |
| `--accent-000` `--accent-100` `--accent-200` `--accent-900` | Blue accent ramp (`100` == `200`). Used for focus rings and links. |
| `--accent-pro-000` ... `--accent-pro-900` | Violet (Pro / Max) accent ramp (`100` == `200`). |
| `--brand-000` ... `--brand-900` | Clay ramp (`--brand-900` is `--always-black`). |

> You **do not** author `--accent-main-*` / `--accent-secondary-*`. They don't exist
> in stock v1.15962, but some legacy refs (and a couple of our element overrides)
> still mention them. The patch **auto-derives** them from your real accents
> (`--accent-main-100 -> var(--accent-brand)`, etc.) plus `--always-black` /
> `--always-white`, so everything resolves without you touching them.

### Borders, status, on-color, pictograms

| Variable | Purpose |
|----------|---------|
| `--border-100` ... `--border-400` | Border colors (all four are typically the same value within a mode) |
| `--danger-000` ... `--danger-900` | Error / destructive (`100` == `200`) |
| `--warning-000` ... `--warning-900` | Warning (`100` == `200`) |
| `--success-000` ... `--success-900` | Success (`100` == `200`) |
| `--oncolor-100` ... `--oncolor-300` | Text / icon color **on** a filled accent button |
| `--pictogram-100` ... `--pictogram-400` | Icon / illustration fills |

> **Border polarity - the #1 authoring gotcha.** claude.ai applies borders at a low
> alpha at the use site, so the **raw token must be the OPPOSITE polarity of the
> surface**:
> - **Dark variant:** `--border-*` must be a **light-ish** HSL (stock dark is
>   `51 16.5% 84.5%`, near-white). A dark border value in dark mode = **invisible
>   borders**.
> - **Light variant:** `--border-*` must be a **dark-ish** HSL (stock light is
>   `30 3.3% 11.8%`).
> - Rule of thumb: border lightness ~= opposite of the bg lightness in that mode.

> **`--oncolor-*` polarity:** this is the text on filled accent buttons, so it must
> contrast with `--accent-brand` / `--accent-200`. Near-white for dark themes - but
> if your accent is light/pastel, `oncolor` must be **dark** (e.g. `sweet`'s dark
> variant uses a near-black oncolor on its hot-pink accent). Verify `oncolor-100`
> against both `accent-200` and `accent-brand` at >= 4.5.

### Legacy hex variables (renderer chrome)

These color the renderer windows (Quick Entry, title bar, About) and use **hex**,
per mode:

| Variable | Purpose |
|----------|---------|
| `--claude-accent-clay` | Accent (logo, highlights) |
| `--claude-foreground-color` | Primary text |
| `--claude-background-color` | Window background |
| `--claude-secondary-color` | Secondary / muted text |
| `--claude-border` / `--claude-border-300` / `--claude-border-300-more` | Borders (include alpha, e.g. `#b496b420`) |
| `--claude-text-100` / `-200` / `-400` / `-500` / `--claude-description-text` | Text ramp / hint text |

### The other token layers (handled for you)

Newer surfaces don't read `--bg-*` directly - the patch maps them onto your
`--bg-*` / `--text-*` automatically, so the whole UI recolors out of the box:

- **`--cds-*`** (Console Design System): popovers, the Cowork / Code frame, Settings
  dialogs. The patch maps `--cds-surface-*`, `--cds-text-*`, `--cds-border`,
  `--cds-clay` onto your semantic tokens.
- **`--df-*`** (Desktop Frame): the window chrome - sidebar (`--df-z2`), content
  panes (`--df-z1`). These are a neutral gray ramp independent of `--bg-*`; the
  patch overrides `.dframe-sidebar` / `.dframe-content` and the `--df-z*` /
  `--df-surface-primary` / `--df-sidebar-bg` tokens to match your `--bg-*` hue.

You author only `--bg-*` / `--text-*` / `--accent-*` (+ the `--claude-*` hex chrome);
the CDS and DF layers follow.

## Contrast (WCAG-checked)

The built-in themes are WCAG-checked: text on background (`text-000/200/400` on
`bg-000`/`bg-100`) and on-color on accent are kept at **>= 4.5** contrast, and
`accent-100` on `bg-000` at >= 3.0. When authoring your own, nudge lightness until
those pairs clear the threshold (a contrast checker lives in the project scratchpad).

## Chat font override

Override the chat font per-theme or globally. The value is any valid CSS
`font-family` string:

```jsonc
{
  "activeTheme": "nord",
  "chatFont": "'Fira Sans', sans-serif",
  "themes": {
    "my-custom-theme": {
      "light": { "--bg-000": "0 0% 100%" },
      "dark":  { "--bg-000": "220 17% 20%" },
      "chatFont": "'JetBrains Mono', monospace"
    }
  }
}
```

- Per-theme `chatFont` (inside a theme object) takes precedence over the global one.
- It overrides the `font-claude-response-body` / `font-claude-response-title` classes
  used by Claude's message text in both Chat and Cowork tabs, plus user message
  bubbles.
- Only **system-installed** fonts work (no Google Fonts / remote loading).

To find available fonts:

```bash
fc-list : family | sort -u           # all installed font families
fc-list : family | grep -i "fira"    # search for a specific font
```

## Custom CSS (raw rules)

`customCss` lets a theme inject raw CSS rules (beyond `--` variables) into the windows
the theme system styles. It accepts a single string or an array of strings (arrays are
joined with newlines), at the **top level** (applies under whatever theme is active)
and/or **inside a theme object** (applies only when that theme is active). Both are
injected **after** the variable declarations and the built-in element overrides;
per-theme `customCss` is appended after the global one, so it wins.

```jsonc
{
  "activeTheme": "nord",
  "customCss": ".some-renderer-element{ /* raw rule */ }",
  "themes": {
    "nord": {
      "light": { "--bg-000": "220 16% 96%" },
      "dark":  { "--bg-000": "220 16% 22%" },
      "customCss": ".container{ box-shadow: 0 0 0 1px hsl(var(--accent-brand) / 0.4) !important }"
    }
  }
}
```

On startup (run `claude-desktop` from a terminal) you'll see
`[CustomThemes] customCss appended (N chars)` confirming your rules were injected.

> **`customCss` reaches the chat UI, and most surfaces are already recolored for you.**
> The patch injects CSS with Electron's `webContents.insertCSS()` on every WebContents
> it creates, including the chat webview and the nested
> `https://a.claude.ai/isolated-segment.html` iframe - so both `customCss` and the
> built-in element overrides apply there. The built-in overrides already map the
> `dframe-*`, CDS surface, semantic-surface, and scrim layers back onto your `--bg-*`
> variables, so the sidebar, main content, Settings, popovers, cards and scrims
> recolor for **every** theme with no extra `customCss`. Use `customCss` for anything
> those overrides don't cover.
>
> Two things stay out of reach: the **OS window-control buttons** (min/max/close) are
> drawn by your window manager's decorations, not by any web frame, so they're themed
> from your desktop environment - not here.

## Inspecting HTML, CSS & tokens for reference

The authoritative token reference is
[baseline/THEME_TOKEN_MAP.md](../baseline/THEME_TOKEN_MAP.md) - it documents every
themeable token family, the four coexisting token layers (v1/v2 semantic, CDS, DF),
stock light vs dark values, and the gotchas above, mined from a live v1.15962
extract. Read it before authoring; re-validate it on each upstream bump (token
*names* are stable, but the selector architecture and primitive layer can shift).

To inspect the actual HTML structure and CSS classes used by each renderer window,
extract the app bundle:

```bash
# Place Claude.msix in the project root, then:
mkdir -p /tmp/claude-inspect
7z x -o/tmp/claude-inspect Claude.msix -y
asar extract /tmp/claude-inspect/app/resources/app.asar /tmp/claude-inspect/app
```

```bash
# List all renderer HTML files
find /tmp/claude-inspect/app/.vite/renderer -name "*.html"

# Quick Entry (the floating prompt box - the only HTML with real body content)
cat /tmp/claude-inspect/app/.vite/renderer/quick_window/quick-window.html

# Extract just the CSS variable definitions from the main window
grep -E '^\s*--' /tmp/claude-inspect/app/.vite/renderer/main_window/index.html | head -80
```

Each renderer HTML file has an inline `<style>` block (~4000 lines) with compiled
Tailwind utilities, the `window-shared.css` variable definitions, and
window-specific styles. The main chat UI loads from `claude.ai` as a separate
WebContentsView and uses the **same** HSL design tokens; inspect it with
`CLAUDE_DEV_TOOLS=detach claude-desktop` and the webview DevTools console.

Cleanup:

```bash
rm -rf /tmp/claude-inspect
```

## Tips for theme creators

1. **Start from a built-in** - copy one of the `themes/*/claude-desktop-bin.json`
   files (they're all dual-variant now) and edit both the `light` and `dark` blocks.
2. **HSL format** - `"hue saturation% lightness%"` (e.g. `"285 50% 8%"`), no
   `hsl(...)` wrapper. Legacy `--claude-*` variables are **hex** (with alpha for
   borders, e.g. `"#b496b420"`).
3. **Mind border polarity** - dark borders light-ish, light borders dark-ish (see
   the border gotcha above). This is the most common mistake.
4. **Check contrast** - keep text/oncolor against their backgrounds at >= 4.5.
5. **Test both modes** - toggle Settings -> Appearance between light and dark and
   confirm each variant; the app now picks the matching block.
6. **Check all windows** - open Quick Entry (hotkey), Find-in-Page (Ctrl+F), and
   About to verify the `--claude-*` chrome.
