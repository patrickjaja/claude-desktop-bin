# This project moved: claude-desktop-bin is now claude-desktop-extra

**New home: https://github.com/patrickjaja/claude-desktop-extra**

The project was renamed to reflect what it does: the official Claude Desktop Linux build
covers Debian-based distros only, and claude-desktop-extra fills the gaps - Arch, Fedora,
RHEL, NixOS and AppImage packaging - plus extra features on top (Computer Use, custom
themes, multi-profile, Quick Entry, the Extra settings hub).

## Nothing breaks for existing installs

This repository stays in place as a **compatibility mirror** during the transition:

- **pacman** (`[claude-desktop-bin]` section): keeps working - releases here mirror the
  new repository, including the legacy database names. The packages upgrade you to
  `claude-desktop-extra` automatically.
- **APT / DNF** (`patrickjaja.github.io/claude-desktop-bin/...`): keeps working - the
  Pages content here mirrors the new repository's package repos, and upgrading migrates
  your repo configuration to the new URLs.
- **Nix** (`github:patrickjaja/claude-desktop-bin`): keeps evaluating - the flake here
  re-exports the new repository's flake.
- **AppImage self-update**: keeps working - the zsync files are mirrored here.

## Please migrate when convenient

Fresh setup instructions live in the new repository:
https://github.com/patrickjaja/claude-desktop-extra#installation

The mirror will be retired after the transition window; migrated installs are unaffected.
