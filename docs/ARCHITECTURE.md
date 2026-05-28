# Architecture

Last reviewed: 2026-05-23

Ultimate Tic Tac Toe is a server-rendered Common Lisp hypermedia app. The
dependency shape is intentionally simple so future agents can inspect the whole
system quickly and can lift the harness into new projects later.

## Components

- `src/package.lisp` declares the public package boundaries.
- `src/rules.lisp` contains the typed Coalton rules slice: local-board outcome,
  global outcome, and winning-line indexes.
- `src/game.lisp` owns mutable game state, legality checks, move application,
  deterministic opponent move selection, and domain-level outcome updates.
- `src/rooms.lisp` owns shareable room state, private seat-token authority,
  watcher classification, revision checks, and serialization around room
  mutations. It is deliberately not an HTTP or HTML layer.
- `src/web.lisp` owns Clack responses, Lack session access, Ningle routes,
  Spinneret rendering, HTMX fragments, static asset serving, and request
  parsing.
- `assets/` contains source assets, including `assets/style.lass`.
- `static/` contains generated CSS and SVG assets served directly by the web
  layer.
- `t/` contains FiveAM tests for rules, game behavior, room behavior, and HTTP
  rendering.
- `scripts/` contains runnable entry points for local app, test, validation, and
  browser-smoke workflows.
- `flake.nix` exposes the default packaged app, browser-smoke app, development
  shell, and deterministic check derivation.

## Boundaries

Dependency direction is:

`rules -> game -> rooms -> web`

Rules:

- `src/rules.lisp` must stay pure rule evaluation. It should not know about
  Clack, Lack, Ningle, Spinneret, sessions, CSS, mutable `game` structs, or
  room state.
- `src/game.lisp` may import from `ultimate-tic-tac-toe.rules`; it should not
  render HTML, read request parameters, manage HTTP sessions, or know about
  shareable rooms.
- `src/rooms.lisp` may import from `ultimate-tic-tac-toe.game`; it should own
  room-level authorization and concurrency, but it should not render HTML, parse
  requests, know about cookies, or depend directly on Coalton rules.
- `src/web.lisp` is the adapter boundary. Convert request strings with helpers
  such as `parse-index` and `parse-player-mark` before calling lower layers.
  It may call game APIs directly for the local-session mode and room APIs for
  shareable multiplayer mode.
- LASS is build-time asset tooling. Keep stylesheet generation in `scripts/`
  and `assets/`; `src/web.lisp` should only link and serve the generated CSS.
- Shared constants should live at the lowest layer that can own them without
  creating an upward dependency.

## Design Invariants

- The mutable `game` struct is the domain payload; local-session play stores it
  directly in the browser session, while room play stores it behind the room
  repository.
- Computer move selection may clone game states for search, but only `play-*`
  functions apply the selected move to a live game.
- Invalid game moves return a `move-rejected` condition with a keyword reason
  that higher layers map to user-facing notices.
- Invalid room actions return a `room-rejected` condition with a keyword reason;
  rejected room moves must not mutate the game or bump the room revision.
- Room views are snapshots. They expose a copied game state and never expose
  private X/O seat tokens or mutable room storage.
- Room revisions bump on accepted seat claims and accepted moves. Submitted
  stale revisions are rejected before applying moves.
- A closed local board sends the next player back to any open board.
- `nil` means open/empty in the game layer; UI labels translate it at render
  time.
- Winning-line indexes use the row-major order documented by `*winning-lines*`.

## Mechanical Guards

- `scripts/test.lisp` runs rules, game, room, and web behavior tests.
- `scripts/validate-architecture.lisp` validates source layering, dependency
  declarations, and ASDF component order from Lisp forms, plus the executable
  client scripting boundary with scanner self-checks.
- `scripts/build-assets.lisp` regenerates `static/style.css` from
  `assets/style.lass`.
- `scripts/validate-assets.lisp` verifies generated assets are current.
- `scripts/validate-docs.lisp` validates the agent map, required knowledge docs,
  and Lisp SPDX headers.
- `scripts/browser-smoke.mjs` drives a real browser through player setup,
  first-move HTMX swapping, computer-opponent play, game-over dialog focus,
  responsive overflow checks, browser accessibility-tree checks, screenshot
  regression, and screenshot refresh.
- `nix flake check` runs asset validation, behavior tests, architecture
  validation, and harness validation.
- `nix build .#` builds the packaged app and runs the package check phase.
