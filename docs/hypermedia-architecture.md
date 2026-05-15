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
- `Hunchentoot` is the default Clack backend.
- Vendored `htmx` submits forms and swaps the returned game fragment.

## Contract

The app treats HTML as its public application protocol:

- `GET /` returns the full current-game page.
- `GET /games/current` returns the current game representation.
- `POST /games` creates a fresh session game and may update player settings.
- `POST /games/current/moves` applies a move to the current game.

Non-htmx `POST` requests receive a `303 See Other` redirect back to `/`. htmx
`POST` requests receive a fresh `#game` fragment. This keeps the app usable as
plain HTML while giving htmx a smaller response shape.

The rules and mutable game state stay in `ultimate-tic-tac-toe.game`; the web
layer translates HTTP forms into state transitions and returns HTML
representations.

The browser dependency is local: `GET /htmx.min.js` serves the vendored HTMX
asset from `static/`.
