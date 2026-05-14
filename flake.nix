{
  description = "Starling -- Typst library for animated data structures";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    utpm.url = "github:typst-community/utpm";
    tytanic.url = "github:typst-community/tytanic";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      utpm,
      tytanic,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:

      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in
      {
        devShells.default =
          with pkgs;
          mkShell {
            buildInputs = [
              # Core typst tools
              typst
              tinymist
              typstyle
              utpm.packages.${system}.default
              tytanic.packages.${system}.default

              # Utilities
              just
              just-formatter
              just-lsp
            ];
          };
      }
    );
}
