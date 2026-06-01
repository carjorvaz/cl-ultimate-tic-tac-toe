default:
    @just --list

test:
    direnv exec . sbcl --script scripts/test.lisp

assets:
    direnv exec . sbcl --script scripts/build-assets.lisp

validate-assets:
    direnv exec . sbcl --script scripts/validate-assets.lisp

validate-architecture:
    direnv exec . sbcl --script scripts/validate-architecture.lisp

validate-docs:
    direnv exec . sbcl --script scripts/validate-docs.lisp

browser-smoke:
    direnv exec . node scripts/browser-smoke.mjs

flake-check:
    nix flake check --print-build-logs

jj-status:
    jj status

review-diff:
    jj diff --tool difft
