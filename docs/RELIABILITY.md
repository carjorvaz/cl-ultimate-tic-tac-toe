# Reliability

Last reviewed: 2026-05-15

Reliability in this project means every agent can boot, test, and reason about
the app locally without hidden service dependencies.

## Runtime

- Start the app with `direnv exec . sbcl --script scripts/run.lisp`.
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

## State And Concurrency

- Game state is stored in the Lack session.
- `with-current-game-locked` serializes access to the current session game.
- Concurrent duplicate moves should produce one accepted move and one rejection,
  preserving turn order.
- Web handlers should return HTML without leaking backend-specific session URLs.

## Feedback Loops

- Use `scripts/test.lisp` for behavior validation.
- Use `scripts/validate-architecture.lisp` for source-layer and dependency
  validation.
- Use `scripts/build-assets.lisp` after editing `assets/style.lass`.
- Use `scripts/validate-assets.lisp` after stylesheet-source or generated-CSS
  edits.
- Use `scripts/validate-docs.lisp` for repository-harness validation.
- Use `scripts/browser-smoke.mjs` for browser-driven desktop/mobile rendering,
  HTMX swap, computer-opponent play, CSRF-form, accessibility structure,
  accessibility-tree names and roles, keyboard flow, modal focus, screenshot
  regression, backend health probes, and overflow validation.
- Use `nix flake check` before treating a change as ready for CI.
- Run the browser smoke locally before treating UI changes as ready.
- For larger UI work, still run the app manually when visual judgment matters;
  the smoke flow catches regressions but does not replace taste.

## Boundary Validation

Validate external inputs at the web boundary:

- board and cell parameters become integers through `parse-index`;
- first-player settings become keywords through `parse-player-mark`;
- player names are trimmed and length-limited through `clean-player-name`.
