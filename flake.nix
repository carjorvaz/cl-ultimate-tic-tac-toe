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
          hunchentoot
          clack-handler-hunchentoot
          bordeaux-threads
          ironclad
          fiveam
          usocket
        ]);
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = mkPkgs system;
          lisp = mkLisp pkgs;
        in
        {
          default = pkgs.mkShell {
            packages = [
              lisp
              pkgs.rlwrap
            ];

            shellHook = ''
              echo "Ultimate Tic Tac Toe: sbcl --script scripts/run.lisp"
            '';
          };
        });

      apps = forAllSystems (system:
        let
          pkgs = mkPkgs system;
          lisp = mkLisp pkgs;
          runner = pkgs.writeShellScriptBin "ultimate-tic-tac-toe" ''
            set -euo pipefail
            cd ${self}
            exec ${lisp}/bin/sbcl --script scripts/run.lisp
          '';
        in
        {
          default = {
            type = "app";
            program = "${runner}/bin/ultimate-tic-tac-toe";
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
              nativeBuildInputs = [ lisp ];
            }
            ''
              export HOME="$TMPDIR"
              cd ${self}
              sbcl --script scripts/test.lisp
              sbcl --script scripts/validate-architecture.lisp
              sbcl --script scripts/validate-docs.lisp
              touch "$out"
            '';
        });
    };
}
