# Reference:
# - https://nixos.org/manual/nixpkgs/stable/#lisp

# Enter the dev shell with: nix develop
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in {
        devShell = pkgs.mkShell {
          buildInputs = with pkgs;
            [
              (sbcl.withPackages (ps:
                with ps;
                # Quicklisp packages
                [ alexandria ]))
            ];
        };
      });

}
