# Quality

Last reviewed: 2026-05-16

## Current Grade

A for a compact app: domain behavior, HTTP flow, session handling, concurrent
duplicate moves, source boundaries, docs, browser behavior, accessibility
structure, browser accessibility-tree coverage, color contrast, and
desktop/mobile screenshot regression are tested. The remaining accessibility
gap is human screen-reader review.

## Verification Matrix

- Pure rules: covered by `t/rules-tests.lisp`.
- Mutable game state: covered by `t/game-tests.lisp`.
- Fragment rendering and HTTP flows: covered by `t/web-tests.lisp`.
- Browser rendering, responsive overflow, visible controls, CSRF form presence,
  DOM accessibility structure, browser accessibility-tree names and roles,
  color contrast, keyboard startup flow, computer-opponent play, game-over
  modal focus behavior, desktop/mobile screenshot regression, and core HTMX
  form flow: covered by
  `scripts/browser-smoke.mjs`.
- Generated CSS freshness: covered by `scripts/validate-assets.lisp`.
- Source boundaries and dependency declarations: covered by
  `scripts/validate-architecture.lisp`.
- Repository harness docs: covered by `scripts/validate-docs.lisp`.
- CI gate: `nix flake check` runs generated-asset validation, behavior tests,
  architecture validation, and repository harness validation. GitHub Actions
  also runs `nix run .#browser-smoke` with screenshot comparison skipped for
  runner-portable rendering.
- Manual browser behavior: expected for larger UI changes beyond the smoke flow.
- Manual screen-reader behavior: follow `docs/accessibility-review.md` when a
  human accessibility pass is needed.

## Quality Invariants

- Tests should assert behavior, not implementation trivia.
- Rejections should carry stable keyword reasons in the game layer.
- User-facing copy belongs in the web layer.
- `static/style.css` is generated from `assets/style.lass`; update the LASS
  source first, then rebuild and validate assets.
- Lisp source files in `src/`, `t/`, and `scripts/` start with the AGPL SPDX
  header.
- Documentation should capture decisions that would otherwise live only in a
  prompt, chat, or memory.

## Known Gaps

- No manual screen-reader pass is tracked in CI; use
  `docs/accessibility-review.md` to run and record one. The local browser smoke
  covers DOM accessibility integrity, Chromium accessibility-tree names and
  roles, and computed color contrast.
- Screenshot regression is limited to the checked-in start and in-progress
  baselines for desktop and mobile viewports.
