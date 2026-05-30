# Rooms, Watch Mode, SSE, and Scaffold Extraction Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task with spec and quality review gates.

**Goal:** Add shareable room multiplayer with read-only watchers, use htmx SSE where it improves observation, and extract the Common Lisp + Nix/direnv + validation harness into a reusable scaffold.

**Architecture:** Preserve the existing pure boundary style. The target dependency direction is `rules -> game -> rooms -> web`, with `rooms` owning shared room state and authorization while `web` owns HTTP/session/rendering.

**Taste bar:** Server-rendered hypermedia first, ordinary Common Lisp data and conditions, small explicit packages, validators for recurring rules, and repository-local knowledge as the system of record. `docs/HARNESS.md` is the source for agent-first harness and Common Lisp taste guidance.

## Acceptance Criteria

- Local quick-play at `/` keeps working without accounts or rooms.
- `POST /rooms` creates a short-code room and redirects to `/rooms/:code`.
- `/rooms/:code` supports two seated players and any number of watchers.
- Player authority uses private seat tokens in the browser session; room codes are public.
- Watchers can observe but cannot submit moves.
- Non-active players/watchers receive updates through progressive enhancement: htmx SSE if enabled, with a plain `GET /rooms/:code/game`/refresh fallback.
- Room state is durable when `UTTT_ROOM_DB` is configured.
- Tests cover room domain logic, HTTP authorization, concurrent duplicate room moves, SSE/fallback fragments, and browser multi-context play/watch behavior.
- The reusable scaffold can be copied or generated into a new app and run its own validation loop.

## Phase 1: Product And Architecture Contract

- Update `docs/PRODUCT.md` with room, seat, watcher, and reset/expiry rules.
- Update `docs/hypermedia-architecture.md` with room routes and SSE/fallback routes,
  explicitly preserving form POSTs as the only command path.
- Update `docs/RELIABILITY.md` with room persistence, configuration, and concurrency expectations.
- Update `docs/QUALITY.md` with the new verification matrix.
- Keep `docs/HARNESS.md` aligned as the agent-first operating policy.
- Validation: `direnv exec . sbcl --script scripts/validate-docs.lisp`.

## Phase 2: Room Layer

- Add `ultimate-tic-tac-toe.rooms` in `src/package.lisp` and `src/rooms.lisp`.
- Update `ultimate-tic-tac-toe.asd` component order.
- Extend `scripts/validate-architecture.lisp` to enforce `rules -> game -> rooms -> web`.
- Add `t/room-tests.lisp`.
- Model room codes, seat claims, private seat tokens, watcher views, move authorization, revisions, and serialization boundaries.
- Start with an in-memory repository so behavior and API shape stabilize before SQLite.
- Validation: targeted room tests, then `scripts/test.lisp` and architecture validation.

## Phase 3: Persistence

- Spike the Nix/ASDF SQLite package (`sbclPackages.sqlite`) before broad changes.
- Add SQLite dependency to `flake.nix` and ASDF only after the spike proves the API.
- Centralize runtime configuration if the environment surface grows beyond the
  current web startup helpers; at minimum keep `PORT`, `SERVER`,
  `SOURCE_CODE_URL`, `SESSION_SECRET`, `UTTT_VERSION`, and `UTTT_ROOM_DB`
  documented and read at the boundary without logging secrets.
- Use `UTTT_ROOM_DB` from the environment; keep local dev usable without service setup.
- Store versioned game data instead of raw printed structs.
- Wrap move updates in a transaction that serializes duplicate concurrent moves.
- Validation: room persistence tests that restart/reopen the repository.

## Phase 4: Web Routes And Watch Mode

Proposed routes:

```text
POST /rooms
GET  /rooms/:code
GET  /rooms/:code/game
GET  /rooms/:code/events
POST /rooms/:code/seats/:mark
POST /rooms/:code/moves
POST /rooms/:code/reset   # only if product docs allow it
```

- Render role-aware room views for X, O, and watchers.
- Seat holders see move controls only when authorized for the current turn.
- Watchers receive board/status/player summaries with no enabled move forms.
- Unknown room codes return 404 without accidental room creation.
- CSRF remains required on all room POST routes.
- Validation: `t/web-tests.lisp` with separate cookies for X, O, and watcher sessions.

## Phase 5: htmx SSE

Use htmx SSE as progressive enhancement, not as the core command path.

- Vendor `htmx-ext-sse` under `static/` and serve it locally.
- Load it after local `htmx.min.js`; keep CDN-free browser smoke checks.
- Use current extension attributes: `hx-ext="sse"`, `sse-connect`, `sse-swap`; do not use obsolete `hx-sse`.
- Send named events such as `room-update` whose data is the same server-rendered fragment as `GET /rooms/:code/game`.
- Put `sse-connect` on a stable parent and swap the `#room-game` child with `hx-swap="outerHTML"`; do not nest duplicate `#room-game` elements through htmx's default `innerHTML` swap.
- Keep moves as normal POST forms.
- Provide a fallback path through polling or manual refresh.
- Add tests for event stream content type and fragment shape; add browser smoke coverage if Playwright can reliably observe the update.

## Phase 6: Browser And Harness Feedback

- Extend `scripts/browser-smoke.mjs` with three contexts: X player, O player, watcher.
- Verify one move propagates to watcher/non-active views.
- Verify watcher has no enabled move buttons/forms.
- Preserve external-request, accessibility-tree, color-contrast, keyboard, overflow, health/version, and screenshot checks.
- Improve startup logging so agents can see backend, port, version, room DB mode, and source URL without secrets.
- When browser smoke fails, emit an agent-actionable artifact bundle: screenshot,
  relevant HTML snapshot, accessibility tree JSON, browser console/error log,
  request URL, and server log tail.

## Phase 7: Scaffold Extraction

- Create a `scaffold/template/` first; split to a separate repo later only after the template proves useful.
- Include `.envrc`, `flake.nix`, ASDF systems, docs, AGENTS/CLAUDE guidance, scripts, LASS/static CSS, and browser-smoke helpers.
- Parameterize app name, ASDF system, package prefix, default port, source URL, license, optional Coalton, optional SQLite, and optional SSE.
- Add a scaffold self-smoke that generates/copies a temp app and runs docs validation plus Lisp tests.
- Keep scaffold defaults small: domain -> web, with optional rules/domain/web and optional room/persistence extensions.

## Progress Log

- 2026-05-22: Baseline inspection found room/watch/SSE/scaffold work unimplemented; local tests, architecture validation, docs validation, asset validation, and browser smoke were green before planning.
- 2026-05-22: Added `docs/HARNESS.md` as the durable source for agent-first harness, Common Lisp taste, SSE policy, mechanical gates, and garbage-collection rules.
- 2026-05-22: Created this active execution plan so future agent runs can continue from repository-local context instead of chat history.
- 2026-05-23: Phase 1 product/architecture/reliability/quality contracts were updated with room, watcher, SSE, persistence, and verification expectations.
- 2026-05-23: Phase 2 room domain layer landed in `src/rooms.lisp` with private seat tokens, watcher classification, revision checks, room move authorization, immutable views, `t/room-tests.lisp`, ASDF wiring, and architecture validation for `rules -> game -> rooms -> web`.
- 2026-05-28: Initial Phase 4 room web routes landed with `POST /rooms`, role-aware `GET /rooms/:code`, fragment `GET /rooms/:code/game`, seat-claim posts, room move posts, private session-held seat tokens, and HTTP tests for X/O/watcher cookie separation.
- 2026-05-28: Browser multi-context room smoke landed for independent X-player, O-player, and watcher contexts through the manual refresh fallback.
- 2026-05-29: Phase 5 SSE observation landed with local `htmx-ext-sse`, `GET /rooms/:code/events` `text/event-stream` snapshots, stable `#room-stream` -> `#room-game` swaps, same-revision `Last-Event-ID` no-op responses to preserve focus during idle reconnects, HTTP event-stream coverage, and browser smoke assertions that X/O/watcher contexts receive room updates without manual reloads.
- 2026-05-29: Phase 3 SQLite room persistence landed with `sbclPackages.sqlite`, a versioned room row format, transactional seat/move updates, repository reopen coverage, stale duplicate rejection after reopen, and `UTTT_ROOM_DB` web-boundary selection while preserving in-memory rooms when unset.
- 2026-05-30: Phase 7 scaffold extraction started with a focused active plan at `docs/exec-plans/active/2026-05-30-scaffold-extraction.md`, a `scaffold/` docs skeleton, and docs-validator coverage so the extraction track remains visible.

## Decisions

- Room work should preserve `rules -> game -> rooms -> web` dependency direction.
- Room codes are public; X/O seat authority lives in private session-held tokens.
- Watchers are read-only and should never receive enabled move controls.
- htmx SSE is progressive enhancement for observation and inactive views, not a move command channel.
- SSE swaps should use a stable connection parent and `outerHTML` child replacement to avoid nested duplicate room fragments.
- Persistence should align with existing `UTTT_ROOM_DB` deployment configuration and be proven by a SQLite spike before broad wiring.
- Scaffold extraction waits until the room/persistence boundary is proven.
- `docs/exec-plans/active/` is the durable home for this roadmap; local
  `.hermes/plans/` scratch copies should be migrated here or pruned.

## Validation Performed

- `direnv exec . sbcl --script scripts/test.lisp` passed before this plan was created.
- `direnv exec . sbcl --script scripts/validate-assets.lisp` passed before this plan was created.
- `direnv exec . sbcl --script scripts/validate-architecture.lisp` passed before this plan was created.
- `direnv exec . sbcl --script scripts/validate-docs.lisp` passed before this plan was created and after `docs/HARNESS.md` was added.
- `direnv exec . sbcl --script scripts/validate-docs.lisp` passed after the Phase 1 product/architecture/reliability/quality contract updates.
- `git diff --check` passed after the Phase 1 documentation updates.
- Phase 1 revalidation passed: `scripts/test.lisp`, `scripts/validate-architecture.lisp`, `scripts/validate-assets.lisp`, `scripts/validate-docs.lisp`, `scripts/browser-smoke.mjs`, and `nix build .#checks.aarch64-darwin.default --print-build-logs`.
- `direnv exec . node scripts/browser-smoke.mjs` passed before this plan was created and after Phase 1 documentation updates.
- Phase 2 checkpoint validation passed after the room files were added to the Git index and an independent review-found mutable room-code snapshot leak was fixed: `git diff --check`, `direnv exec . sbcl --script scripts/test.lisp` (951/951 checks), `direnv exec . sbcl --script scripts/validate-assets.lisp`, `direnv exec . sbcl --script scripts/validate-architecture.lisp`, `direnv exec . sbcl --script scripts/validate-docs.lisp`, `direnv exec . node scripts/browser-smoke.mjs`, and `nix build .#checks.aarch64-darwin.default --print-build-logs`.
- Phase 4 RED/GREEN room HTTP route cycle: new `t/web-tests.lisp` tests first failed with 404s for missing `/rooms` routes, then passed after the in-memory room web handlers and rendering were added (`direnv exec . sbcl --script scripts/test.lisp`, 981/981 checks).
- Phase 4 browser revalidation passed after the room multi-context browser flow and game-over topbar focus fix landed: `BROWSER_SMOKE_SKIP_SCREENSHOTS=1 direnv exec . node scripts/browser-smoke.mjs`, `UPDATE_SCREENSHOTS=1 direnv exec . node scripts/browser-smoke.mjs`, and `direnv exec . node scripts/browser-smoke.mjs`.

## Gates

- **Pre-flight:** current baseline must be green before implementation phases.
- **Revision:** every phase with code gets spec review and code-quality review before proceeding.
- **Escalation:** ask the maintainer before changing player authority semantics, reset policy, expiry policy, public URL shape, or scaffold repo split.
- **Abort:** stop if validation cannot run, if SQLite package behavior is unclear after the spike, or if the working tree has unexpected unrelated edits.

## Validation Commands

```sh
direnv exec . sbcl --script scripts/test.lisp
direnv exec . sbcl --script scripts/build-assets.lisp      # after LASS edits
direnv exec . sbcl --script scripts/validate-assets.lisp
direnv exec . sbcl --script scripts/validate-architecture.lisp
direnv exec . sbcl --script scripts/validate-docs.lisp
direnv exec . node scripts/browser-smoke.mjs
nix flake check
nix build .#
```
