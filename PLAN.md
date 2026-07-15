# PLAN: Align app identity to upstream `com.anthropic.Claude`

Branch: `align-app-identity-upstream`
Status: implementation in progress (review target - not for merge until verified on live Wayland)

## Issue

Our build ships a Linux app identity of **`claude-desktop`**, which diverges from
the identity Anthropic's official `.deb` uses: **`com.anthropic.Claude`**.

The divergence is not a passive fallback - we **actively pin** it. During the
build, `scripts/build-patched-tarball.sh` rewrites the bundle's
`package.json` `desktopName` from upstream's `com.anthropic.Claude.desktop` back
to `claude-desktop.desktop`. Chromium's `GetXdgAppId()` derives a window's
Wayland `app_id` / X11 `WM_CLASS` from that `desktopName` (when `$CHROME_DESKTOP`
is unset and no `--class` is passed - both true in our launcher), so the pin is
what makes every window report `claude-desktop`. Every `.desktop` file, every
`StartupWMClass`, and the `systemd-run` scope we emit exist to *agree with* that
pinned value.

Two problems with staying on `claude-desktop`:

1. **It is single-segment (no dots).** The freedesktop / xdg-desktop-portal
   convention wants a reverse-DNS app id for reliable activation routing and, on
   KDE, for **persistent** screen-share / Computer Use permission grants. A
   single-segment id is effectively broken for KDE persistent grants (see the
   `project_portal_app_identity` project note). `com.anthropic.Claude` is a
   valid reverse-DNS id - adopting it *fixes* this, it does not just rename it.

2. **It is drift from official for no ongoing benefit.** The pin existed because
   our `.desktop` machinery (issue #148) was built around `claude-desktop`
   before upstream shipped its own identity. Now that upstream ships a good
   reverse-DNS id, riding it removes a whole class of "keep our name and
   upstream's name in sync" maintenance.

## Goal

Ship the **same app identity as the official build** (`com.anthropic.Claude`)
across every axis - window `app_id`/`WM_CLASS`, `.desktop` filename,
`StartupWMClass`, and the `systemd-run` scope - so:

- Wayland dock grouping / Alt-Tab / taskbar pinning match on the upstream id.
- xdg-desktop-portal activation routing and **KDE persistent permission grants**
  work (reverse-DNS id).
- We carry less packaging divergence from upstream.

Non-goals (explicitly out of scope for this change):
- **Do NOT change `productName`** (stays `Claude`). userData stays
  `~/.config/Claude` - no data migration, no login loss. This is the hard safety
  invariant.
- **Do NOT rename the launcher binary** `/usr/bin/claude-desktop` or the
  per-profile launcher symlinks `claude-desktop-<name>` - the profile-resolution
  regex keys off that basename. `Exec=claude-desktop` lines stay.
- **Do NOT rename the icon** `claude-desktop.png` (`Icon=` is just a theme lookup
  key, orthogonal to app_id).
- **Do NOT** try to give each profile a distinct per-profile `app_id` - that
  needs an unimplemented per-profile `desktopName` override and is a separate
  effort.

## Solution

One coordinated, atomic change across the identity axes. `productName`, the
launcher binary name, and the icon are deliberately left alone.

### 1. Remove the pin (root change)
`scripts/build-patched-tarball.sh`: stop rewriting `desktopName`. Keep an
adapted tripwire: assert upstream's `desktopName` is still present **and equals
`com.anthropic.Claude.desktop`** (fail loud if upstream renames again, so our
fixed `.desktop` filenames can't silently desync a third time).

### 2. Rename the `.desktop` identity everywhere (must move together)
`claude-desktop.desktop` -> `com.anthropic.Claude.desktop`, and
`StartupWMClass=claude-desktop` -> `StartupWMClass=com.anthropic.Claude`, in:
- `scripts/claude-desktop-launcher.sh`: `DESKTOP_ID` base (drives generated
  `.desktop` filename, `systemd-run` scope middle-token, xdg-mime handler),
  the two generated-`.desktop` `StartupWMClass` lines, and the two hardcoded
  `/usr/share/applications/claude-desktop.desktop` lookups (`_create_profile`
  source-inherit, `_diagnose` portal anchor).
- `packaging/debian/` (`build-deb.sh` heredoc + `claude-desktop.desktop`
  committed file + `rules` install line).
- `packaging/rpm/claude-desktop-bin.spec` (heredoc target, StartupWMClass,
  `%files` entry).
- `packaging/appimage/build-appimage.sh` (AppDir `.desktop` + StartupWMClass +
  copy into `usr/share/applications/`; appimagetool needs the AppDir `.desktop`
  basename == AppRun/binary name - handle carefully).
- `packaging/nix/package.nix` (`makeDesktopItem name=` and `startupWMClass`).
- `PKGBUILD.template` (AUR `.desktop` heredoc + StartupWMClass).

`Exec=` lines keep pointing at the launcher binary `claude-desktop` (unchanged).

### 3. Keep `fix_quick_entry_app_id.nim` as-is (already alignment-ready)
Its reset already reads `desktopName` from `package.json` at runtime, so with
the pin gone it naturally resolves to `com.anthropic.Claude` - and its fallback
literal is already `com.anthropic.Claude`. The QE window's own distinct id
`claude-quick-entry` stays (our value-add). No patch drops; only the comments
become accurate. No complexity reduction is safe (the runtime read is what
survives future upstream renames - keep it).

### 4. Backward-compat for existing installs (mitigation)
- **Launcher source-inherit + portal-anchor lookups now probe BOTH names**
  (new `com.anthropic.Claude.desktop` first, legacy `claude-desktop.desktop`
  fallback) - implemented at launcher `_create_profile` source-inherit and
  `_diagnose` portal anchor. So a profile created on a not-yet-upgraded install
  still resolves.
- **Per-profile `.desktop` renamed to `com.anthropic.Claude-<name>.desktop`**
  in `_profile_paths` + `_create_profile`; `_delete_profile` removes BOTH the
  new and legacy (`claude-desktop-<name>.desktop`) names so old profiles clean
  up fully. IMPLEMENTED.
- **Still open (reviewer decision):** default-profile pinned taskbar shortcuts
  referencing the old `claude-desktop.desktop` will orphan on upgrade. A
  compat symlink from the old name -> new is NOT yet shipped (would live in each
  packager's install step). Users re-pin once; documented as a one-time break.
  Decide whether to add the symlink or just document.

## Risks (reviewer: verify these on live Wayland before trusting the change)

1. **All-or-nothing.** A partial rename (pin removed but one packager's `.desktop`
   still `claude-desktop.desktop`) is a **silent** Wayland dock regression - the
   build passes, only a live Wayland session shows the generic-icon / duplicate
   Alt-Tab symptom (issue #148, inverted). Every axis in step 2 must land together.
2. **Pinned-shortcut orphaning** for existing users (step 4 mitigation).
3. **Stale per-profile `.desktop` files** for users who already made profiles.
4. **systemd scope with a dotted middle-token**
   (`app-com.anthropic.Claude-$$.scope`) - follows the freedesktop convention
   (Flatpak/GNOME do this) but was not live-exercised; verify `systemd-run
   --unit=` accepts it here.
5. **Per-profile distinct app_id is still unsolved** - not in scope; don't expect
   per-profile icons from this change.

## Verification checklist (for review over the coming days)

- [ ] Build each package format; grep the built `.desktop` + bundle `desktopName`
      all report `com.anthropic.Claude`.
- [ ] KDE Plasma Wayland: main window `resourceClass = com.anthropic.Claude`,
      Quick Entry = `claude-quick-entry`, dock grouping correct.
      (`scripts/diagnose-window-appid.sh`)
- [ ] GNOME Wayland: same via Window Calls.
- [ ] X11/XWayland: `WM_CLASS = com.anthropic.Claude`, taskbar grouping correct.
- [ ] Computer Use screen-share consent on KDE **persists** across restarts
      (the concrete payoff of the reverse-DNS id).
- [ ] `claude://` link still opens the app (xdg-mime handler renamed).
- [ ] Named profile: `--create-profile work`, launch, confirm it still works and
      old stale `.desktop` (if any) is handled.
- [ ] Existing pinned taskbar shortcut from the old name still launches (compat).
- [ ] userData still `~/.config/Claude` (unchanged) - no re-login.
