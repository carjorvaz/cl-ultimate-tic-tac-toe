# Repository Knowledge

Last reviewed: 2026-05-30

This directory is the system of record for project knowledge that should survive
between agent runs.

## Map

- `ARCHITECTURE.md`: source layout and dependency direction.
- `HARNESS.md`: agent-first harness and Common Lisp taste.
- `PRODUCT.md`: app behavior and user experience contract.
- `RELIABILITY.md`: runtime, configuration, and validation expectations.
- `QUALITY.md`: verification matrix and known gaps.
- `PLANS.md`: execution-plan policy.
- `technical-debt.md`: focused cleanup candidates.

## Maintenance Rules

- Update the narrowest relevant document when a lasting decision changes.
- Promote repeated review comments into tests or validation scripts.
- Keep `AGENTS.md` short enough to work as a table of contents.
- Run `sbcl --script scripts/validate-docs.lisp` after editing this knowledge base.
