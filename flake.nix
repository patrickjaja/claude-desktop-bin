{
  description = "Claude Desktop for Linux — unofficial package";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        packages = {
          claude-desktop = pkgs.callPackage ./packaging/nix/package.nix {
            # Avoid pulling claude-code from nixpkgs — its npm tarball is
            # frequently yanked between releases, breaking the build.
            # Users can override: claude-desktop.override { claude-code = pkgs.claude-code; }
            claude-code = null;
          };
          default = self.packages.${system}.claude-desktop;
        };
      }
    );
}
