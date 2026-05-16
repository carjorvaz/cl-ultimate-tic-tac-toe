# Technical Debt

Last reviewed: 2026-05-15

Track durable cleanup candidates here so agents can retire them in small,
focused patches.

## Known Debt

- Run and record the manual screen-reader pass in
  `docs/accessibility-review.md` to complement the automated DOM,
  accessibility-tree, and color-contrast smoke coverage.
- Refresh or redeploy the public service at
  `https://ultimate-tic-tac-toe.carjorvaz.com/`. On 2026-05-16 it still served
  an older Hunchentoot page with room URLs, numeric cell labels, session IDs in
  form actions, and a 404 for `/version`. Close this only after `/version`
  responds and the positional cell labels from current `master` are visible.

## Gardening Rule

When a recurring defect or review note appears, either remove the cause, add a
test, add a validation rule, or record the debt here with enough context for a
future agent to act.
