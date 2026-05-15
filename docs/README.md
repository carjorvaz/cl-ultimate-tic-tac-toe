# Repository Knowledge

Last reviewed: 2026-05-15

This directory is the system of record for project knowledge that should survive
between agent runs. Keep documents focused and cross-linked; `AGENTS.md` points
here so the agent can progressively disclose only the context it needs.

## Map

- `ARCHITECTURE.md`: source layout, dependency direction, and boundary rules.
- `accessibility-review.md`: manual screen-reader review runbook.
- `hypermedia-architecture.md`: Clack/Lack/Ningle/Spinneret routes and HTML
  contract.
- `PRODUCT.md`: Ultimate Tic Tac Toe behavior and UI expectations.
- `RELIABILITY.md`: local runtime, session state, deployment knobs, and feedback
  loops.
- `QUALITY.md`: current quality grade, verification matrix, and test gaps.
- `PLANS.md`: execution-plan policy for work that needs a durable task log.
- `technical-debt.md`: known cleanup candidates that should not live only in
  chat.
- `exec-plans/README.md`: where active and completed plans should live.

## Maintenance Rules

- Update the narrowest relevant document when a lasting decision changes.
- Promote repeated review comments into a test or validation script.
- Keep `AGENTS.md` short enough to work as a table of contents.
- Run `direnv exec . sbcl --script scripts/validate-docs.lisp` after editing
  this knowledge base.
