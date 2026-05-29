# Quality

Last reviewed: 2026-05-29

## Current Grade

A for the current compact local-session app: domain behavior, HTTP flow, session
handling, concurrent duplicate moves, source boundaries, docs, browser behavior,
accessibility structure, browser accessibility-tree coverage, color contrast,
and desktop/mobile screenshot regression are tested. The remaining current-app
accessibility gap is human screen-reader review.

The room domain, web layer, SQLite persistence path, SSE observation path, and
browser smoke are now tested for room-code creation, private X/O seat authority,
watcher rejection, turn authorization, revision checks, game move rejection
propagation, immutable room views, room creation redirects, role-aware room
pages, seat claims, watcher read-only HTTP behavior, event-stream
content/fragment shape, durable reopen from SQLite, stale duplicate rejection
after reopen, durable room-seat session restoration after restart, and an
X/O/watcher browser flow whose inactive player and watcher views update
through the local htmx SSE path.

## Verification Matrix

- Pure rules: covered by `t/rules-tests.lisp`.
- Mutable game state: covered by `t/game-tests.lisp`.
- Fragment rendering and HTTP flows: covered by `t/web-tests.lisp`.
- Browser rendering, responsive overflow, visible controls, CSRF form presence,
  DOM accessibility structure, browser accessibility-tree names and roles,
  color contrast, keyboard startup flow, computer-opponent play, room
  X/O/watcher SSE observation with refresh fallback preserved, game-over modal
  focus behavior, desktop/mobile screenshot regression, and core HTMX form flow:
  covered by `scripts/browser-smoke.mjs`.
- Generated CSS freshness: covered by `scripts/validate-assets.lisp`.
- Source boundaries and dependency declarations: covered by
  `scripts/validate-architecture.lisp`.
- Repository harness docs: covered by `scripts/validate-docs.lisp`.
- CI gate: `nix flake check` runs generated-asset validation, behavior tests,
  architecture validation, and repository harness validation. GitHub Actions
  also runs `nix run .#browser-smoke` with screenshot comparison skipped for
  runner-portable rendering.
- Room domain behavior: covered by `t/room-tests.lisp` for code creation,
  private seat-token authority, watcher rejection, turn authorization,
  revision checks, game move rejection propagation, and immutable room views.
- Room HTTP authorization: covered by `t/web-tests.lisp` with separate cookie
  jars for X, O, and watcher sessions.
- Room browser behavior: covered by `scripts/browser-smoke.mjs` with independent
  browser contexts for X player, O player, and watcher, including watcher
  read-only rendering, SSE propagation to inactive views, and refresh fallback
  coverage for room URLs.
- SSE behavior: covered by `t/web-tests.lisp` for event stream content type,
  cache/security headers, `Last-Event-ID` duplicate suppression, and room-update
  fragment shape, plus browser-smoke coverage of X/O/watcher update propagation
  and idle reconnect focus preservation under Playwright.
- SQLite persistence: covered by `t/room-tests.lisp` for repository reopen and
  stale duplicate rejection after reopen, and by `t/web-tests.lisp` for the
  `UTTT_ROOM_DB` configured repository/session-store path, including claimed-seat
  session restoration across restart.
- Manual browser behavior: expected for larger UI changes beyond the smoke flow.
- Manual screen-reader behavior: follow `docs/accessibility-review.md` when a
  human accessibility pass is needed.

## Quality Invariants

- Tests should assert behavior, not implementation trivia.
- Rejections should carry stable keyword reasons in the game or room layer.
- User-facing copy belongs in the web layer.
- Room seat authority must come from private session-held tokens, not public room
  codes.
- Watcher rendering must be read-only by construction, not just visually
  disabled.
- SSE is an observation path only; commands remain ordinary CSRF-protected form
  posts.
- `static/style.css` is generated from `assets/style.lass`; update the LASS
  source first, then rebuild and validate assets.
- Lisp source files in `src/`, `t/`, and `scripts/` start with the AGPL SPDX
  header.
- Documentation should capture decisions that would otherwise live only in a
  prompt, chat, or memory.
- Agent-first harness and Common Lisp taste decisions belong in
  `docs/HARNESS.md`; recurring deviations should become validators or focused
  debt items.

## Known Gaps

- No manual screen-reader pass is tracked in CI; use
  `docs/accessibility-review.md` to run and record one. The local browser smoke
  covers DOM accessibility integrity, Chromium accessibility-tree names and
  roles, and computed color contrast.
- Screenshot regression is limited to the checked-in start and in-progress
  baselines for desktop and mobile viewports.
- Room persistence is now implemented through an optional SQLite repository and
  SQLite-backed Lack session store selected by `UTTT_ROOM_DB`; future
  persistence work should focus on migration and expiry policy, not the first
  durable storage path.
