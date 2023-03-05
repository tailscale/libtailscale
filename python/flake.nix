{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      devEnv = (pkgs.buildFHSUserEnv {
        name = "libtailscale-python";
        targetPkgs = pkgs: (with pkgs; [
          cmake
          python39
        ]);
        runScript = "${pkgs.writeShellScriptBin "runScript" (''
          set -e
          python3 -m venv .venv
          source .venv/bin/activate
          exec bash
          '')}/bin/runScript";
      }).env;
    in {
      devShell = devEnv;
    }
  );
}
