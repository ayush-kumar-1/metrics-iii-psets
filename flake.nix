{
  description = "Project-local R development shell with Ark";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; };
      rEnv = pkgs.rWrapper.override {
        packages = with pkgs.rPackages; [
          data_table
          fixest
          tidyverse
        ];
      };
      arkSrc = pkgs.fetchFromGitHub {
        owner = "posit-dev";
        repo = "ark";
        rev = "09d4397f12cc51112a83640cc462cb70fed2e2e6";
        hash = "sha256-+z1n62uN7wJ7FoLsm5AuJp6ODRTaR1T/nP7LcPAAnLU=";
      };
      arkUnwrapped = pkgs.rustPlatform.buildRustPackage rec {
        pname = "ark";
        version = "0.1.249";
        src = arkSrc;
        cargoHash = "sha256-DG8EtbqtX+fR5MmodSsQTwCX2trsk1ag6x2Jck3zX/w=";

        nativeBuildInputs = [
          pkgs.pkg-config
        ];

        buildInputs = [
          pkgs.zeromq
        ];

        cargoBuildFlags = [ "-p" pname ];
        cargoTestFlags = cargoBuildFlags;
        doCheck = false;
      };
      ark = pkgs.symlinkJoin {
        name = "ark-wrapped";
        paths = [ arkUnwrapped ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/ark \
            --prefix PATH : ${pkgs.lib.makeBinPath [ rEnv ]} \
            --set-default R_HOME ${rEnv}/lib/R
        '';
      };
      installArkKernel = pkgs.writeShellScriptBin "install-ark-kernel" ''
        set -euo pipefail

        project_dir="$(pwd)"
        export JUPYTER_PATH="$project_dir/.jupyter"

        mkdir -p "$JUPYTER_PATH"
        ${ark}/bin/ark --install

        printf '\nInstalled Ark kernelspec for this project only:\n  %s\n\n' \
          "$JUPYTER_PATH/kernels/ark/kernel.json"
        printf 'Start Zed from this shell so it inherits JUPYTER_PATH:\n  zed %s\n' "$project_dir"
      '';
    in {
      packages.${system}.ark = ark;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          ark
          installArkKernel
          rEnv
        ];

        shellHook = ''
          export JUPYTER_PATH="$PWD/.jupyter"
          export R_HOME="${rEnv}/lib/R"
        '';
      };
    };
}
