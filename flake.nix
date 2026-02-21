{
  description = "Claude Desktop for Linux — unofficial package";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages = {
          claude-desktop = pkgs.callPackage ./packaging/nix/package.nix { };
          default = self.packages.${system}.claude-desktop;
        };
      }
    );
}
