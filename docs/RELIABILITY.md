# Reliability

Last reviewed: 2026-05-28

Reliability in this project means every agent can boot, test, and reason about
the app locally without hidden service dependencies. Multiplayer rooms should add
shared state without taking away that local feedback loop.

## Runtime

- Start the app with `direnv exec . sbcl --script scripts/run.lisp`.
- Start the packaged flake app with `nix run .`.
- The default URL is `http://127.0.0.1:4242/`.
- The public deployment is `https://ultimate-tic-tac-toe.carjorvaz.com/`.
- `GET /health` returns `ok` for readiness checks.
- `GET /version` returns the app name and ASDF version for lightweight release
  inspection.
- Set `PORT` to choose a different listener port.
- `start` uses the Woo Clack backend by default. The app itself is still built
  as a Clack application.
- The HTTP test harness uses the Hunchentoot backend because its direct acceptor
  lifecycle makes startup failures synchronous and shutdown clean. Private
  adapter lookups stay quarantined behind `clack-hunchentoot-symbol`.
- Startup logs should expose backend, port, version, room persistence mode, and
  source URL without logging secrets or private seat tokens.

## State And Concurrency

- Local quick-play game state is stored in the Lack session.
- `with-current-game-locked` serializes access to the current session game.
- Concurrent duplicate local moves should produce one accepted move and one
  rejection, preserving turn order.
- Shared room state belongs behind the room repository API, not in web handlers.
- Room updates should serialize by room code and revision so concurrent duplicate
  room moves produce one accepted move and one rejection.
- Room reads for rendering or SSE must not hold write locks while streaming to a
  slow or disconnected client.
- Web handlers should return HTML without leaking backend-specific session URLs,
  private seat tokens, or persistence paths.

## Room Persistence

- Room multiplayer must work in a local development mode without external
  services.
- If `UTTT_ROOM_DB` is unset, the app may use an in-memory room repository for
  development and tests.
- If `UTTT_ROOM_DB` is set, it names the SQLite database path for durable room
  state.
- Database initialization should create the required schema deterministically and
  fail loudly with actionable errors when the path cannot be opened.
- Persist versioned room/game data rather than raw printed implementation
  structs, so migrations and future readers have an explicit contract.
- Seat tokens are authority-bearing secrets. Store only what the server needs to
  verify a session's seat, never render tokens into HTML, logs, or URLs.
- SQLite write transactions should cover seat claims and move application so
  authorization checks and mutations stay atomic.
- Persistence tests should prove a room can be reopened from the database and
  that stale duplicate submissions do not corrupt the game.

## Feedback Loops

- Use `scripts/test.lisp` for behavior validation.
- Use `scripts/validate-architecture.lisp` for source-layer and dependency
  validation.
- Use `scripts/build-assets.lisp` after editing `assets/style.lass`.
- Use `scripts/validate-assets.lisp` after stylesheet-source or generated-CSS
  edits.
- Use `scripts/validate-docs.lisp` for repository-harness validation.
- Use `nix build .#` to verify the packaged app output.
- Use `scripts/browser-smoke.mjs` for browser-driven desktop/mobile rendering,
  HTMX swap, computer-opponent play, independent X-player/O-player/watcher room
  refresh fallback, CSRF-form, accessibility structure, accessibility-tree names
  and roles, color contrast, keyboard flow, modal focus, screenshot regression,
  backend health probes, and overflow validation.
- Keep browser-visible room behavior covered before persistence or SSE work is
  treated as ready; SSE should add live observation coverage without removing the
  refresh fallback.
- Use `nix flake check` before treating a change as ready for CI.
- Run the browser smoke locally before treating UI changes as ready; CI runs
  the same flow through `nix run .#browser-smoke`, with screenshot comparison
  skipped for runner-portable rendering.
- Use `docs/accessibility-review.md` for a manual screen-reader pass when
  accessibility behavior needs human review.
- For larger UI work, still run the app manually when visual judgment matters;
  the smoke flow catches regressions but does not replace taste.

## Boundary Validation

Validate external inputs at the web boundary:

- board and cell parameters become integers through `parse-index`;
- first-player settings become keywords through `parse-player-mark`;
- player names are trimmed and length-limited through `clean-player-name`;
- room codes are parsed, normalized, and rejected when malformed;
- seat marks in URLs become `:x` or `:o` keywords through the same mark parser;
- room move requests validate the submitted revision before calling room logic;
- persistence paths come only from `UTTT_ROOM_DB`, never from request data.
