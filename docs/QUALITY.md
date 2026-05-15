# Quality

Last reviewed: 2026-05-15

## Current Grade

B+ for a compact app: domain behavior, HTTP flow, session handling, concurrent
duplicate moves, and a browser smoke flow are tested. The remaining gap is a
deeper accessibility audit.

## Verification Matrix

- Pure rules: covered by `t/rules-tests.lisp`.
- Mutable game state: covered by `t/game-tests.lisp`.
- Fragment rendering and HTTP flows: covered by `t/web-tests.lisp`.
- Browser rendering, responsive overflow, visible controls, and core form flow:
  covered by `scripts/browser-smoke.mjs`.
- Source boundaries, dependency declarations, and repository harness docs:
  covered by `scripts/validate-docs.lisp`.
- Manual browser behavior: expected for larger UI changes beyond the smoke flow.

## Quality Invariants

- Tests should assert behavior, not implementation trivia.
- Rejections should carry stable keyword reasons in the game layer.
- User-facing copy belongs in the web layer.
- Lisp source files in `src/`, `t/`, and `scripts/` start with the AGPL SPDX
  header.
- Documentation should capture decisions that would otherwise live only in a
  prompt, chat, or memory.

## Known Gaps

- No accessibility audit runs in CI.
- Browser automation is a smoke test; it does not yet cover keyboard-only flow
  or screenshot baselines.
- The structural validator is string-based; it catches the intended boundary
  drift but does not parse every Common Lisp form.
