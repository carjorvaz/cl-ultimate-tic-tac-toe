# Accessibility Review

Last reviewed: 2026-05-15

Use this runbook for the manual screen-reader pass that complements the
automated browser smoke checks. Do not mark the pass complete unless a person
has actually listened to the screen-reader output and driven the flows below.

## Scope

- Fresh game setup, including player names, opponent difficulty, and first
  player selection.
- Keyboard-only play through at least one human move and one computer reply.
- Game-over dialog focus behavior and reset.
- Legal notices navigation from the footer and back to the game.

## Preflight

- Run `direnv exec . sbcl --script scripts/test.lisp`.
- Run `direnv exec . node scripts/browser-smoke.mjs`.
- Start the app with `direnv exec . sbcl --script scripts/run.lisp`.
- Open `http://127.0.0.1:4242/` in a browser with a clean session.

## Checklist

- The page announces a clear title and one `Ultimate Tic Tac Toe` heading.
- The status area announces the current turn and target board without needing
  visual context.
- The player-name fields, opponent radios, first-player radios, and start
  button have clear names and a predictable keyboard order.
- Radio groups support arrow-key movement and keep the selected option obvious
  in the screen-reader announcement.
- Playable board cells are announced with player, board, and cell context.
- After a move, the changed turn and target board are discoverable without
  leaving the keyboard flow.
- Easy, Normal, and Hard computer modes announce the CPU difficulty in the
  player summary after setup.
- The game-over dialog takes focus, announces the result, traps tab focus, and
  restores a playable new game after `New game`.
- Footer links expose meaningful names, and the legal page announces its
  heading, license link, source link, and back-to-game link.

## Recording Results

Record the date, browser, screen reader, operating system, and any defects in
the pull request or release note that used this runbook. If the pass finds a
recurring issue, add or update an automated check where practical; otherwise
record a focused item in `docs/technical-debt.md`.
