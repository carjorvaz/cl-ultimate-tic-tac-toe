# Quality

Last reviewed: 2026-05-15

## Current Grade

B+ for a compact app: domain behavior, HTTP flow, session handling, and
concurrent duplicate moves are tested. The remaining gap is browser-driven
visual and accessibility validation.

## Verification Matrix

- Pure rules: covered by `t/rules-tests.lisp`.
- Mutable game state: covered by `t/game-tests.lisp`.
- Fragment rendering and HTTP flows: covered by `t/web-tests.lisp`.
- Repository harness docs: covered by `scripts/validate-docs.lisp`.
- Manual browser behavior: expected for UI changes, not automated yet.

## Quality Invariants

- Tests should assert behavior, not implementation trivia.
- Rejections should carry stable keyword reasons in the game layer.
- User-facing copy belongs in the web layer.
- Lisp source files in `src/`, `t/`, and `scripts/` start with the AGPL SPDX
  header.
- Documentation should capture decisions that would otherwise live only in a
  prompt, chat, or memory.

## Known Gaps

- No browser automation captures screenshots or checks responsive layout.
- No accessibility audit runs in CI.
- No structural linter enforces the `rules -> game -> web` dependency direction
  beyond package review and tests.
