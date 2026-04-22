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
          xgboost
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
          r_libs_site="$(env -u R_HOME ${rEnv}/bin/Rscript -e 'cat(Sys.getenv("R_LIBS_SITE"))')"

          wrapProgram $out/bin/ark \
            --prefix PATH : ${pkgs.lib.makeBinPath [ rEnv ]} \
            --set-default R_HOME ${rEnv}/lib/R \
            --set-default R_LIBS_SITE "$r_libs_site"
        '';
      };
      installArkKernel = pkgs.writeShellScriptBin "install-ark-kernel" ''
        set -euo pipefail

        project_dir="$(pwd)"
        export JUPYTER_PATH="$project_dir/.jupyter"
        kernel_dir="$JUPYTER_PATH/kernels/ark"
        export ARK_R_HOME="$(env -u R_HOME ${rEnv}/bin/R RHOME)"
        export ARK_R_LIBS_SITE="$(env -u R_HOME ${rEnv}/bin/Rscript -e 'cat(Sys.getenv("R_LIBS_SITE"))')"
        export ARK_R_LIBS_USER="$(env -u R_HOME ${rEnv}/bin/Rscript -e 'cat(Sys.getenv("R_LIBS_USER"))')"

        mkdir -p "$kernel_dir"

        ${pkgs.python3}/bin/python3 <<'PY'
import json
import os
from pathlib import Path

kernel_dir = Path(os.environ["JUPYTER_PATH"]) / "kernels" / "ark"
kernel_json = kernel_dir / "kernel.json"

env = {
    "RUST_LOG": "error",
    "R_HOME": os.environ["ARK_R_HOME"],
    "R_LIBS_SITE": os.environ["ARK_R_LIBS_SITE"],
}

if os.environ.get("ARK_R_LIBS_USER"):
    env["R_LIBS_USER"] = os.environ["ARK_R_LIBS_USER"]

spec = {
    "argv": [
        "${ark}/bin/ark",
        "--connection_file",
        "{connection_file}",
        "--session-mode",
        "notebook",
    ],
    "display_name": "Ark R Kernel",
    "language": "R",
    "env": env,
}

kernel_json.write_text(json.dumps(spec, indent=2) + "\n")
PY

        printf '\nInstalled Ark kernelspec for this project only:\n  %s\n\n' \
          "$kernel_dir/kernel.json"
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
