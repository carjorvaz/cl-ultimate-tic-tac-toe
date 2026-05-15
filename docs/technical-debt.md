# Technical Debt

Last reviewed: 2026-05-15

Track durable cleanup candidates here so agents can retire them in small,
focused patches.

## Known Debt

- Add browser-driven UI validation for layout, keyboard flow, and screenshots.
- Add an accessibility check for labels, focus order, and modal behavior.
- Add a structural dependency check for the intended `rules -> game -> web`
  layering.

## Gardening Rule

When a recurring defect or review note appears, either remove the cause, add a
test, add a validation rule, or record the debt here with enough context for a
future agent to act.
