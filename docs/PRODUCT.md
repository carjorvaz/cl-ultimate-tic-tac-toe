# Product

Last reviewed: 2026-05-23

Ultimate Tic Tac Toe should stay immediately playable as a local-session browser
game while growing a shareable room mode for remote humans and observers. The
local quick-play flow supports two human players, or one human playing X against
an Easy, Normal, or Hard deterministic computer opponent as O. Room mode is a
human-vs-human multiplayer layer with read-only watchers.

## Game Contract

- A new game starts with X unless the session player settings choose O.
- A move in a cell sends the next player to the corresponding local board.
- If the target local board is already closed, the next player may choose any
  open local board.
- A local board is closed by an X win, O win, or draw.
- The global board is won by three closed local boards owned by the same player;
  it is a draw when all local boards are closed without a global winner.
- Illegal moves do not advance the turn or mutate the board.
- When O is set to Easy, Normal, or Hard, the computer immediately applies the
  chosen deterministic strategy after each human move and may start the game if
  O is selected first.
- Easy selects the first legal move, Normal scores immediate tactics, and Hard
  uses bounded search with adaptive depth in constrained positions.

## Room Multiplayer Contract

- Local quick-play at `/` remains available without accounts, room codes, or
  persistence.
- `POST /rooms` creates a room with a short, human-readable public code and
  redirects to `/rooms/:code`.
- Room URLs are shareable. The room code is an unlisted discovery handle, not a
  private authorization secret.
- A browser session may claim an open X or O seat. Authority to play that seat
  comes from a private seat token stored in that browser session, never from the
  room code alone.
- At most one active session token owns X and at most one owns O. A duplicate
  claim for an occupied seat is rejected without changing the existing owner.
- Sessions without a seat are watchers. Any number of watchers may observe a
  room.
- Watchers are read-only: they never receive enabled move controls and any
  watcher move submission is rejected without mutating the room.
- Only the seated player whose mark matches the current turn may move. Wrong
  seat, stale turn, illegal board/cell, and game-over moves are rejected without
  mutating the room.
- Room views must state the viewer role, whose turn it is, and the target board.
- Room state carries a monotonic revision so stale duplicate submissions and
  observer updates can be reasoned about mechanically.
- The first room release is human-vs-human only. Computer opponents remain a
  local quick-play feature until room ownership and automation semantics are
  specified separately.
- Room reset/rematch is out of scope for the first room release. A new game means
  creating a new room unless a future product update defines reset authority.
- Persisted rooms may expire after a documented inactivity window in a future
  cleanup pass, but expiry is not required for the first correct implementation.

## Player Experience

- The first screen is the playable board, not a landing page.
- The status area must always show whose turn it is and the current target
  board.
- Completed boards should remain legible while clearly showing their owner or
  draw state.
- HTMX responses update only the game fragment; non-HTMX posts redirect back to
  the full page with a flash notice when needed.
- Player names are session-local, capped at 24 characters, and fall back to
  "X" or "O".
- The computer opponent difficulty is visibly labeled in the player summary.
- Room pages should make sharing and joining obvious without adding an account
  system.
- A seated room player should see whether they are X or O and whether it is their
  turn.
- A watcher should see the same board and status with clear read-only copy, not
  disabled controls that look broken.
- Non-active room views may update through htmx SSE or polling, but a plain page
  refresh must remain a valid way to observe the room.

## Acceptance Signals

Before shipping product behavior changes, verify:

- rules tests cover the pure outcome calculation;
- game tests cover legality and state mutation;
- room tests cover seat claims, watcher role, authorization, revisions, and
  duplicate/stale submissions;
- web tests cover rendered state, HTTP behavior, CSRF, and room authorization;
- browser smoke covers at least one multi-context X/O/watcher room flow once
  room UI exists;
- manual browser play still feels clear at the default `http://127.0.0.1:4242/`.
