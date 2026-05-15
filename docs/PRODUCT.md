# Product

Last reviewed: 2026-05-15

The product is a local-session Ultimate Tic Tac Toe game optimized for quick
play in a browser without client-side application state. It supports two human
players, or one human playing X against a deterministic computer opponent as O.

## Game Contract

- A new game starts with X unless the session player settings choose O.
- A move in a cell sends the next player to the corresponding local board.
- If the target local board is already closed, the next player may choose any
  open local board.
- A local board is closed by an X win, O win, or draw.
- The global board is won by three closed local boards owned by the same player;
  it is a draw when all local boards are closed without a global winner.
- Illegal moves do not advance the turn or mutate the board.
- When O is set to Computer, the computer immediately applies a deterministic
  tactical move after each human move and may start the game if O is selected
  first.

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
- The computer opponent is visibly labeled in the player summary.

## Acceptance Signals

Before shipping product behavior changes, verify:

- rules tests cover the pure outcome calculation;
- game tests cover legality and state mutation;
- web tests cover the rendered state or HTTP behavior;
- manual browser play still feels clear at the default `http://127.0.0.1:4242/`.
