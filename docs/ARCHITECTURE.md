# Architecture

Last reviewed: 2026-05-15

Ultimate Tic Tac Toe is a server-rendered Common Lisp hypermedia app. The
dependency shape is intentionally simple so future agents can inspect the whole
system quickly.

## Components

- `src/package.lisp` declares the public package boundaries.
- `src/rules.lisp` contains the typed Coalton rules slice: local-board outcome,
  global outcome, and winning-line indexes.
- `src/game.lisp` owns mutable game state, legality checks, move application,
  and domain-level outcome updates.
- `src/web.lisp` owns Clack responses, Lack session access, Ningle routes,
  Spinneret rendering, HTMX fragments, static asset serving, and request
  parsing.
- `assets/` contains source assets, including `assets/style.lass`.
- `static/` contains generated CSS and SVG assets served directly by the web
  layer.
- `t/` contains FiveAM tests for rules, game behavior, and HTTP rendering.
- `scripts/` contains runnable entry points for local app, test, validation, and
  browser-smoke workflows.

## Boundaries

Dependency direction is:

`rules -> game -> web`

Rules:

- `src/rules.lisp` must stay pure rule evaluation. It should not know about
  Clack, Lack, Ningle, Spinneret, sessions, CSS, or mutable `game` structs.
- `src/game.lisp` may import from `ultimate-tic-tac-toe.rules`; it should not
  render HTML, read request parameters, or manage HTTP sessions.
- `src/web.lisp` is the adapter boundary. Convert request strings with
  `parse-index` and `parse-player-mark` before calling game functions.
- LASS is build-time asset tooling. Keep stylesheet generation in `scripts/`
  and `assets/`; `src/web.lisp` should only link and serve the generated CSS.
- Shared constants should live at the lowest layer that can own them without
  creating an upward dependency.

## Design Invariants

- The mutable `game` struct is the session payload; moves mutate it in place.
- Invalid moves return a `move-rejected` condition with a keyword reason that
  web code maps to user-facing notices.
- A closed local board sends the next player back to any open board.
- `nil` means open/empty in the game layer; UI labels translate it at render
  time.
- Winning-line indexes use the row-major order documented by
  `*winning-lines*`.

## Mechanical Guards

- `scripts/test.lisp` runs rules, game, and web behavior tests.
- `scripts/validate-architecture.lisp` validates source layering, dependency
  declarations, and ASDF component order.
- `scripts/build-assets.lisp` regenerates `static/style.css` from
  `assets/style.lass`.
- `scripts/validate-assets.lisp` verifies generated assets are current.
- `scripts/validate-docs.lisp` validates the agent map, required knowledge docs,
  and Lisp SPDX headers.
- `scripts/browser-smoke.mjs` drives a real browser through player setup,
  first-move HTMX swapping, computer-opponent play, game-over dialog focus,
  responsive overflow checks, screenshot regression, and screenshot refresh.
- `nix flake check` runs asset validation, behavior tests, architecture
  validation, harness validation, and browser smoke flow.
