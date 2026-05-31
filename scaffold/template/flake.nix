{
  description = "Common Lisp web app scaffold.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkPkgs = system: import nixpkgs { inherit system; };
      mkLisp = pkgs: pkgs.sbcl.withPackages (ps: with ps; [
        clack lack ningle spinneret lass clack-handler-woo hunchentoot
        clack-handler-hunchentoot fiveam
      ]);
      mkPackage = pkgs:
        let lisp = mkLisp pkgs;
        in pkgs.stdenvNoCC.mkDerivation {
          pname = "common-lisp-web-app";
          version = "0.1.0";
          src = self;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          doCheck = true;
          checkPhase = ''
            runHook preCheck
            export HOME="$TMPDIR"
            ${lisp}/bin/sbcl --script scripts/validate-assets.lisp
            ${lisp}/bin/sbcl --script scripts/test.lisp
            ${lisp}/bin/sbcl --script scripts/validate-architecture.lisp
            ${lisp}/bin/sbcl --script scripts/validate-docs.lisp
            runHook postCheck
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/share/common-lisp-web-app" "$out/bin"
            cp -R . "$out/share/common-lisp-web-app/"
            makeWrapper ${lisp}/bin/sbcl "$out/bin/common-lisp-web-app" \
              --add-flags "--script $out/share/common-lisp-web-app/scripts/run.lisp"
            runHook postInstall
          '';
          meta = {
            description = "Server-rendered Common Lisp web app scaffold";
            license = nixpkgs.lib.licenses.agpl3Plus;
            mainProgram = "common-lisp-web-app";
            platforms = nixpkgs.lib.platforms.unix;
          };
        };
    in {
      packages = forAllSystems (system: let pkgs = mkPkgs system; in { default = mkPackage pkgs; });
      devShells = forAllSystems (system:
        let pkgs = mkPkgs system; lisp = mkLisp pkgs;
        in { default = pkgs.mkShell { packages = [ lisp pkgs.nodejs pkgs.playwright ]; shellHook = ''
          export PLAYWRIGHT_CORE_PATH="${pkgs.playwright}/index.js"
          export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright.browsers}"
          echo "Run app: sbcl --script scripts/run.lisp"
          echo "Run tests: sbcl --script scripts/test.lisp"
          echo "Browser smoke: node scripts/browser-smoke.mjs"
        ''; }; });
      apps = forAllSystems (system:
        let
          pkgs = mkPkgs system;
          lisp = mkLisp pkgs;
          browserSmokeRunner = pkgs.writeShellScriptBin "common-lisp-web-app-browser-smoke" ''
            set -euo pipefail
            cd ${self}
            export PATH="${pkgs.lib.makeBinPath [ lisp pkgs.nodejs ]}:$PATH"
            export PLAYWRIGHT_CORE_PATH="${pkgs.playwright}/index.js"
            export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright.browsers}"
            exec ${pkgs.nodejs}/bin/node scripts/browser-smoke.mjs
          '';
        in {
          default = { type = "app"; program = "${self.packages.${system}.default}/bin/common-lisp-web-app"; };
          browser-smoke = { type = "app"; program = "${browserSmokeRunner}/bin/common-lisp-web-app-browser-smoke"; };
        });
      checks = forAllSystems (system:
        let pkgs = mkPkgs system; lisp = mkLisp pkgs;
        in { default = pkgs.runCommand "common-lisp-web-app-tests" { nativeBuildInputs = [ lisp ]; } ''
          export HOME="$TMPDIR"
          cd ${self}
          sbcl --script scripts/validate-assets.lisp
          sbcl --script scripts/test.lisp
          sbcl --script scripts/validate-architecture.lisp
          sbcl --script scripts/validate-docs.lisp
          touch "$out"
        ''; });
    };
}
