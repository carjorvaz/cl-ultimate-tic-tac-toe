# Agent Map

This scaffold is optimized for small, verifiable agent runs. Keep this file as
a map, not a manual; durable detail lives in `docs/`.

## Start Here

1. Read `README.md` for run and test commands.
2. Read `docs/README.md` to choose the right deeper document.
3. Run `sbcl --script scripts/test.lisp` after code changes.
4. Run `sbcl --script scripts/build-assets.lisp` after editing `assets/style.lass`.
5. Run `sbcl --script scripts/validate-assets.lisp` after changing assets.
6. Run `sbcl --script scripts/validate-architecture.lisp` after changing source boundaries.
7. Run `sbcl --script scripts/validate-docs.lisp` after changing docs or guidance.
8. Run `node scripts/browser-smoke.mjs` after UI changes.

## Source Of Truth

- `docs/ARCHITECTURE.md` describes module boundaries.
- `docs/HARNESS.md` records agent-first harness and Common Lisp taste.
- `docs/PRODUCT.md` describes the app contract.
- `docs/RELIABILITY.md` describes runtime and validation expectations.
- `docs/QUALITY.md` tracks verification coverage and known gaps.
- `docs/PLANS.md` explains when to create execution plans.
- `docs/technical-debt.md` records focused cleanup work.

## Architecture Rules

- Keep domain behavior in `src/domain.lisp`.
- Keep request parsing, HTTP responses, rendering, and static assets in `src/web.lisp`.
- Do not make `src/domain.lisp` depend on Clack, Lack, Ningle, Spinneret, CSS, or browser assets.
- Treat `assets/style.lass` as the source for `static/style.css`.

## Feedback Loop

If an agent learns a reusable rule while fixing a bug, encode it in the repo:
update a focused doc, add a test, or extend a validation script.
