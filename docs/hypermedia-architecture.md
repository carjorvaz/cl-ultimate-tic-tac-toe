# Hypermedia Architecture

Last reviewed: 2026-05-29

Ultimate Tic Tac Toe is a server-rendered Common Lisp hypermedia app. The
browser receives HTML representations and asks for state transitions through
ordinary forms. htmx narrows those transitions to replace only the current game
fragment when JavaScript is available. Room observation may add server-sent
fragment updates, but commands remain form posts.

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
- The optional vendored htmx SSE extension may stream server-rendered fragments
  for room observation; `docs/HARNESS.md` records the SSE policy.
- `static/app.js` contains the small progressive-enhancement script for
  game-over dialog focus.

## Contract

The app treats HTML as its public application protocol:

- `GET /` returns the full current-game page.
- `GET /legal` returns the legal notices page.
- `GET /health` returns a plain-text liveness response for deployment checks.
- `GET /version` returns a plain-text application name and ASDF version.
- `GET /games/current` returns the current local-session game representation.
- `POST /games` creates a fresh local-session game and may update player
  settings.
- `POST /games/current/moves` applies a move to the current local-session game.

Room multiplayer extends the same HTML contract:

- `POST /rooms` creates a shareable room and redirects to `/rooms/:code`.
- `GET /rooms/:code` returns the role-aware room page for the current browser
  session.
- `GET /rooms/:code/game` returns the room game fragment used by htmx and manual
  refresh fallbacks.
- `POST /rooms/:code/seats/:mark` claims an open `x` or `o` seat for the current
  browser session.
- `POST /rooms/:code/moves` applies a move only when the current browser session
  owns the seat whose mark has the turn and submitted the current room revision.
- `GET /rooms/:code/events` returns `text/event-stream` `room-update` events
  whose data is the room game fragment. The connection lives on the stable
  `#room-stream` parent and swaps the `#room-game` child, so room observation can
  update inactive players and watchers without inventing a command API.

Non-htmx `POST` requests receive a `303 See Other` redirect back to the relevant
page. htmx `POST` requests receive a fresh game fragment and, when needed, an
out-of-band footer refresh so source and license links stay outside modal dialog
tab order. This keeps the app usable as plain HTML while giving htmx a smaller
response shape.

The pure rules stay in `ultimate-tic-tac-toe.rules`. Mutable local-session game
state stays in `ultimate-tic-tac-toe.game`. Shared room state and authorization
belong in `ultimate-tic-tac-toe.rooms`. The web layer translates HTTP forms into
validated Lisp values and returns HTML representations. The intended dependency
direction is `rules -> game -> rooms -> web`.

Browser assets are local: `GET /htmx.min.js` serves the vendored HTMX asset,
`GET /htmx-ext-sse.js` serves the vendored SSE extension, and `GET /app.js`
serves the app's progressive-enhancement script from `static/`.

Responses receive conservative default security headers at the Clack boundary:
`X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`,
`Permissions-Policy`, and a self-only `Content-Security-Policy`.

## Client Scripting Policy

Browser scripting should stay hypermedia-friendly: no client-side game state,
no JSON/RPC application API, no browser routing, and no command path outside
the normal form-driven HTML exchange. A documented SSE stream may update
read-only or currently inactive room views with server-rendered fragments, but
moves still go through ordinary forms. Small vanilla JavaScript is acceptable for
browser-only affordances that HTML cannot provide by itself, such as trapping
focus inside the game-over dialog after an htmx swap.

Prefer keeping `static/app.js` tiny and boring over adding a Lisp-to-JavaScript
build step. Parenscript would become worth considering only if client behavior
grows enough to need shared Lisp macros, generated scripts, or repeated
browser-side abstractions. If the goal is to remove the app script entirely,
prefer a product change, such as replacing the modal with an inline
server-rendered game-over panel, over reimplementing the same focus behavior in
generated JavaScript.

## SSE Fragment Contract

Room SSE is progressive enhancement for observation, not a new command channel.
The event stream emits named `room-update` events with the same server-rendered
`#room-game` fragment that `GET /rooms/:code/game` returns. Reconnect requests
whose `Last-Event-ID` is already current return no event payload, preventing
idle duplicate swaps from stealing keyboard focus. The stable `#room-stream`
parent owns `hx-ext="sse"`, `sse-connect`, `sse-swap`, `hx-target="#room-game"`,
and `hx-swap="outerHTML"`; event data contains only the child fragment. This
avoids nested duplicate `#room-game` nodes through htmx's default `innerHTML`
swap. The current implementation sends bounded snapshot events and relies on
normal `EventSource` reconnects for subsequent room revisions, which keeps Woo
and Hunchentoot behavior simple while preserving the manual refresh fallback.

If SSE is unavailable, room pages must remain useful through normal form posts,
fragment polling, or manual refresh.
