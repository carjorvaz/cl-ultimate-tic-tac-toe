# Quality

Last reviewed: 2026-05-30

## Current Grade

Bootstrap scaffold: enough tests and validators exist to prove the neutral app
runs, renders, validates docs/assets/source boundaries, and passes a browser
smoke check.

## Verification Matrix

- Domain behavior: `t/domain-tests.lisp`.
- Web rendering: `t/web-tests.lisp`.
- Full Lisp suite: `scripts/test.lisp`.
- Asset freshness: `scripts/validate-assets.lisp`.
- Source boundaries: `scripts/validate-architecture.lisp`.
- Repository guidance: `scripts/validate-docs.lisp`.
- Browser behavior: `scripts/browser-smoke.mjs`.

## Known Gaps

- This scaffold intentionally starts small; add app-specific tests as product behavior grows.
- Manual screen-reader review is not a routine gate for private scaffold work.
