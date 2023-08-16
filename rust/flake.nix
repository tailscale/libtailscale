{
  inputs = {
    utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, utils, nixpkgs }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = (import nixpkgs) {
          inherit system;
        };

      in rec {
        # For `nix develop`:
        devShell = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            # go
            go_1_20
            gopls
            gotools
            go-tools

            # Rust
            rustc
            cargo
            rustfmt
            rust-analyzer
            rust-bindgen
            clang
            libllvm
          ];

          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
        };
      }
    );
}
