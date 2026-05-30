# Technical Debt

Last reviewed: 2026-05-23

Track durable cleanup candidates here so agents can retire them in small,
focused patches.

## Known Debt

- Manual screen-reader review is not routine debt for this mostly private app.
  Keep `docs/accessibility-review.md` as a runbook, and run it before a public
  release, accessibility-sensitive audience, or major UI overhaul where human
  assistive-tech behavior is part of the acceptance bar.

## Gardening Rule

When a recurring defect or review note appears, either remove the cause, add a
test, add a validation rule, or record the debt here with enough context for a
future agent to act.
