# Agent Map

This repository is optimized for small, verifiable agent runs. Keep this file as
a map, not a manual; the durable source of truth lives in `docs/`.

## Start Here

1. Read `README.md` for run and test commands.
2. Read `docs/README.md` to choose the right deeper document.
3. Run `direnv exec . sbcl --script scripts/test.lisp` after code changes.
4. Run `direnv exec . sbcl --script scripts/build-assets.lisp` after editing
   `assets/style.lass`.
5. Run `direnv exec . sbcl --script scripts/validate-assets.lisp` after
   changing `assets/style.lass` or `static/style.css`.
6. Run `direnv exec . sbcl --script scripts/validate-architecture.lisp` after
   changing source boundaries, dependency declarations, or system layout.
7. Run `direnv exec . sbcl --script scripts/validate-docs.lisp` after changing
   repository guidance, docs, scripts, or Lisp file headers.
8. Run `direnv exec . node scripts/browser-smoke.mjs` after UI changes.

## Source Of Truth

- `docs/ARCHITECTURE.md` describes module boundaries and dependency direction.
- `docs/hypermedia-architecture.md` describes the HTTP and HTML contract.
- `docs/PRODUCT.md` describes the game contract and expected player experience.
- `docs/RELIABILITY.md` describes runtime, session, and validation expectations.
- `docs/QUALITY.md` tracks verification coverage and known quality gaps.
- `docs/PLANS.md` explains when to create execution plans.
- `docs/technical-debt.md` records small cleanup work agents should retire over
  time.

## Architecture Rules

- Keep rule evaluation in `src/rules.lisp`, game state transitions in
  `src/game.lisp`, and HTTP/session/rendering concerns in `src/web.lisp`.
- Parse strings and request data at the web boundary before calling game logic.
- Do not make `src/game.lisp` depend on Clack, Lack, Ningle, Spinneret, HTMX,
  or CSS.
- Preserve the existing Common Lisp style unless a local doc says otherwise.
- Add or update tests when behavior changes.
- Treat `assets/style.lass` as the source for `static/style.css`.

## Feedback Loop

If an agent learns a reusable rule while fixing a bug, encode it in the repo:
update a focused doc, add a test, or extend a validation script.
Prefer mechanical checks for recurring rules and short docs for human judgment.
