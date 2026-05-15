# Reliability

Last reviewed: 2026-05-15

Reliability in this project means every agent can boot, test, and reason about
the app locally without hidden service dependencies.

## Runtime

- Start the app with `nix develop -c sbcl --script scripts/run.lisp`.
- The default URL is `http://127.0.0.1:4242/`.
- Set `PORT` to choose a different listener port.
- `start` uses the Hunchentoot Clack backend by default. The app itself is still
  built as a Clack application; the default lifecycle keeps the raw Hunchentoot
  acceptor so tests and local runs can stop it cleanly.

## State And Concurrency

- Game state is stored in the Lack session.
- `with-current-game-locked` serializes access to the current session game.
- Concurrent duplicate moves should produce one accepted move and one rejection,
  preserving turn order.
- Web handlers should return HTML without leaking backend-specific session URLs.

## Feedback Loops

- Use `scripts/test.lisp` for behavior validation.
- Use `scripts/validate-docs.lisp` for repository harness, source-layer, and
  dependency validation.
- Use `scripts/browser-smoke.mjs` for browser rendering and core UI flow
  validation.
- Use `nix flake check` before treating a change as ready.
- For larger UI work, still run the app manually because the browser smoke is
  intentionally narrow.

## Boundary Validation

Validate external inputs at the web boundary:

- board and cell parameters become integers through `parse-index`;
- first-player settings become keywords through `parse-player-mark`;
- player names are trimmed and length-limited through `clean-player-name`.
