default:
    @just --list

test:
    sbcl --script scripts/test.lisp

assets:
    sbcl --script scripts/build-assets.lisp

validate-assets:
    sbcl --script scripts/validate-assets.lisp

validate-architecture:
    sbcl --script scripts/validate-architecture.lisp

validate-docs:
    sbcl --script scripts/validate-docs.lisp

browser-smoke:
    node scripts/browser-smoke.mjs

flake-check:
    nix flake check --print-build-logs

jj-status:
    jj status

jj-diff:
    jj diff

jj-ops:
    jj op log

review-diff:
    jj diff --tool difft
