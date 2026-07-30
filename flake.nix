{
  # Compatibility re-export: claude-desktop-bin was renamed to claude-desktop-extra.
  # This flake keeps existing `github:patrickjaja/claude-desktop-bin` references
  # evaluating by forwarding to the new repository. Please migrate your inputs to
  # github:patrickjaja/claude-desktop-extra - this mirror will be retired after
  # the transition window.
  description = "MOVED - claude-desktop-bin is now claude-desktop-extra (compatibility re-export)";

  inputs.upstream.url = "github:patrickjaja/claude-desktop-extra";

  outputs = { self, upstream }: {
    packages = upstream.packages;
  };
}
