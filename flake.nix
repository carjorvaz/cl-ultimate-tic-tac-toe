{
  description = "Common Lisp and HTMX Ultimate Tic Tac Toe.";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      mkPkgs = system: import nixpkgs { inherit system; };

      mkLisp = pkgs:
        pkgs.sbcl.withPackages (ps: with ps; [
          coalton
          named-readtables
          clack
          lack
          lack-middleware-session
          ningle
          spinneret
          lass
          clack-handler-woo
          hunchentoot
          clack-handler-hunchentoot
          bordeaux-threads
          ironclad
          fiveam
          usocket
        ]);

      mkPackage = pkgs:
        let
          lisp = mkLisp pkgs;
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = "ultimate-tic-tac-toe";
          version = "0.1.0";

          src = self;

          nativeBuildInputs = [
            pkgs.makeWrapper
          ];

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

            mkdir -p "$out/share/ultimate-tic-tac-toe" "$out/bin"
            cp -R . "$out/share/ultimate-tic-tac-toe/"

            makeWrapper ${lisp}/bin/sbcl "$out/bin/ultimate-tic-tac-toe" \
              --add-flags "--script $out/share/ultimate-tic-tac-toe/scripts/run.lisp"

            runHook postInstall
          '';

          meta = {
            description = "Server-rendered Ultimate Tic Tac Toe in Common Lisp with HTMX";
            homepage = "https://ultimate-tic-tac-toe.carjorvaz.com";
            license = nixpkgs.lib.licenses.agpl3Plus;
            mainProgram = "ultimate-tic-tac-toe";
            platforms = nixpkgs.lib.platforms.unix;
          };
        };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = mkPkgs system;
        in
        {
          default = mkPackage pkgs;
        });

      devShells = forAllSystems (system:
        let
          pkgs = mkPkgs system;
          lisp = mkLisp pkgs;
        in
        {
          default = pkgs.mkShell {
            packages = [
              lisp
              pkgs.nodejs
              pkgs.playwright
              pkgs.rlwrap
            ];

            shellHook = ''
              export PLAYWRIGHT_CORE_PATH="${pkgs.playwright}/index.js"
              export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright.browsers}"
              echo "Ultimate Tic Tac Toe: sbcl --script scripts/run.lisp"
              echo "Build assets: sbcl --script scripts/build-assets.lisp"
              echo "Browser smoke: node scripts/browser-smoke.mjs"
            '';
          };
        });

      apps = forAllSystems (system:
        let
          pkgs = mkPkgs system;
          lisp = mkLisp pkgs;
          browserSmokeRunner = pkgs.writeShellScriptBin "ultimate-tic-tac-toe-browser-smoke" ''
            set -euo pipefail
            cd ${self}
            export PATH="${pkgs.lib.makeBinPath [ lisp pkgs.nodejs ]}:$PATH"
            export PLAYWRIGHT_CORE_PATH="${pkgs.playwright}/index.js"
            export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright.browsers}"
            exec ${pkgs.nodejs}/bin/node scripts/browser-smoke.mjs
          '';
        in
        {
          default = {
            type = "app";
            program = "${self.packages.${system}.default}/bin/ultimate-tic-tac-toe";
          };
          browser-smoke = {
            type = "app";
            program = "${browserSmokeRunner}/bin/ultimate-tic-tac-toe-browser-smoke";
          };
        });

      checks = forAllSystems (system:
        let
          pkgs = mkPkgs system;
          lisp = mkLisp pkgs;
        in
        {
          default = pkgs.runCommand "ultimate-tic-tac-toe-tests"
            {
              nativeBuildInputs = [
                lisp
              ];
            }
            ''
              export HOME="$TMPDIR"
              cd ${self}
              sbcl --script scripts/validate-assets.lisp
              sbcl --script scripts/test.lisp
              sbcl --script scripts/validate-architecture.lisp
              sbcl --script scripts/validate-docs.lisp
              touch "$out"
            '';
        });
    };
}
