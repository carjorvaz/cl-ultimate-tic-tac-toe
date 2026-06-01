# Architecture

Last reviewed: 2026-06-01

Ultimate Tic Tac Toe is a server-rendered Common Lisp hypermedia app. The
dependency shape is intentionally simple so future agents can inspect the whole
system quickly and can lift the harness into new projects later.

## Components

- `src/package.lisp` declares the public package boundaries.
- `src/rules.lisp` contains the typed Coalton rules slice: local-board outcome,
  global outcome, and winning-line indexes.
- `src/game.lisp` owns mutable game state, legality checks, move application,
  validation, and domain-level outcome updates.
- `src/game-ai.lisp` owns deterministic opponent move selection: first legal,
  tactical, and search-backed moves over the mutable game protocol.
- `src/rooms.lisp` owns the shareable room protocol: room state, room views,
  private seat-token authority, watcher classification, revision checks, and
  repository-generic operations.
- `src/rooms-memory.lisp` implements the in-memory room repository.
- `src/rooms-sqlite.lisp` implements the SQLite room repository, including row
  serialization around room mutations.
- `src/web.lisp` owns Clack responses, Lack session access, optional
  SQLite-backed session storage for room seat authority, shared request parsing,
  and HTTP/session helpers.
- `src/web-render.lisp` owns Spinneret rendering, HTMX fragments, full-page
  HTML, and the room SSE fragment shape.
- `src/web-handlers.lisp` owns Ningle routes, static asset serving, room SSE
  responses, request handlers, and server lifecycle.
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
- The `src/game*.lisp` files may import from `ultimate-tic-tac-toe.rules`; they
  should not render HTML, read request parameters, manage HTTP sessions, or know
  about shareable rooms.
- The `src/rooms*.lisp` files may import from `ultimate-tic-tac-toe.game`; they
  should own room-level authorization, persistence, and concurrency, but they
  should not render HTML, parse requests, know about cookies, or depend directly
  on Coalton rules.
- The `src/web*.lisp` files are the adapter boundary. Convert request strings
  with helpers such as `parse-index` and `parse-player-mark` before calling
  lower layers.
  It may call game APIs directly for the local-session mode and room APIs for
  shareable multiplayer mode.
- LASS is build-time asset tooling. Keep stylesheet generation in `scripts/`
  and `assets/`; the web layer should only link and serve the generated CSS.
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
  declarations, ASDF component order, and Coalton confinement to the pure
  `src/rules.lisp` rules island from Lisp forms, plus the executable client
  scripting boundary with scanner self-checks.
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
