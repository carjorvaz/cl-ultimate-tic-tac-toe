# Technical Debt

Last reviewed: 2026-05-15

Track durable cleanup candidates here so agents can retire them in small,
focused patches.

## Known Debt

- Expand browser smoke coverage to keyboard flow and screenshot baselines.
- Add an accessibility check for labels, focus order, and modal behavior.
- Replace the string-based validation rules in `scripts/validate-docs.lisp` with
  form-aware dependency checks if the source layout grows beyond a few Lisp
  files.

## Gardening Rule

When a recurring defect or review note appears, either remove the cause, add a
test, add a validation rule, or record the debt here with enough context for a
future agent to act.
