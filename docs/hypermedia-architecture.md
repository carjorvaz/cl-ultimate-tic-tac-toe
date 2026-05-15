# Hypermedia Architecture

Last reviewed: 2026-05-15

Ultimate Tic Tac Toe is a server-rendered Common Lisp hypermedia app. The
browser receives HTML representations and asks for state transitions through
ordinary forms. htmx narrows those transitions to replace only the current game
fragment when JavaScript is available.

## Stack

- `SBCL` runs the app.
- `ASDF` defines the systems.
- `Nix` pins the local dependency set.
- `Clack` is the HTTP application boundary.
- `Lack` provides middleware, currently session state.
- `ningle` routes requests to application handlers.
- `Spinneret` renders full-page and fragment HTML.
- `Woo` is the default Clack backend.
- `Hunchentoot` remains available as a fallback and HTTP-test backend.
- Vendored `htmx` submits forms and swaps the returned game fragment.
- `static/app.js` contains the small progressive-enhancement script for
  game-over dialog focus.

## Contract

The app treats HTML as its public application protocol:

- `GET /` returns the full current-game page.
- `GET /legal` returns the legal notices page.
- `GET /health` returns a plain-text liveness response for deployment checks.
- `GET /version` returns a plain-text application name and ASDF version.
- `GET /games/current` returns the current game representation.
- `POST /games` creates a fresh session game and may update player settings.
- `POST /games/current/moves` applies a move to the current game.

Non-htmx `POST` requests receive a `303 See Other` redirect back to `/`. htmx
`POST` requests receive a fresh `#game` fragment and an out-of-band footer
refresh so source and license links stay outside modal dialog tab order. This
keeps the app usable as plain HTML while giving htmx a smaller response shape.

The rules and mutable game state stay in `ultimate-tic-tac-toe.game`; the web
layer translates HTTP forms into state transitions and returns HTML
representations.

Browser assets are local: `GET /htmx.min.js` serves the vendored HTMX asset,
and `GET /app.js` serves the app's progressive-enhancement script from
`static/`.

Responses receive conservative default security headers at the Clack boundary:
`X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`,
`Permissions-Policy`, and a self-only `Content-Security-Policy`.

## Client Scripting Policy

Browser scripting should stay hypermedia-friendly: no client-side game state,
no JSON/RPC application API, no browser routing, and no network requests outside
the normal form-driven HTML exchange. Small vanilla JavaScript is acceptable for
browser-only affordances that HTML cannot provide by itself, such as trapping
focus inside the game-over dialog after an htmx swap.

Prefer keeping `static/app.js` tiny and boring over adding a Lisp-to-JavaScript
build step. Parenscript would become worth considering only if client behavior
grows enough to need shared Lisp macros, generated scripts, or repeated
browser-side abstractions. If the goal is to remove the app script entirely,
prefer a product change, such as replacing the modal with an inline
server-rendered game-over panel, over reimplementing the same focus behavior in
generated JavaScript.
