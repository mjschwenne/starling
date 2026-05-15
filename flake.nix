{
  description = "Starling -- Typst library for animated data structures";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Use typst flake to get other versions of typst if needed
    typst = {
      url = "github:typst/typst-flake";
      inputs.typst.url = "github:typst/typst/0.14";
    };
    utpm.url = "github:typst-community/utpm";
    tytanic.url = "github:typst-community/tytanic/v0.3.4";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      typst,
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
              typst.packages.${system}.default
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
