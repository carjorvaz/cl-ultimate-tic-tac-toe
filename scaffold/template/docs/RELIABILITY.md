# Reliability

Last reviewed: 2026-05-30

## Runtime

The app starts with `sbcl --script scripts/run.lisp` and listens on
`127.0.0.1:4242` by default.

Runtime environment variables:

- `PORT`: listen port.
- `SERVER`: Clack backend keyword, default `woo`.
- `SOURCE_CODE_URL`: footer source link.
- `APP_VERSION`: version endpoint text.

## Feedback Loops

- Run `scripts/test.lisp` after code changes.
- Run `scripts/validate-assets.lisp` after asset changes.
- Run `scripts/validate-architecture.lisp` after source-boundary changes.
- Run `scripts/validate-docs.lisp` after docs/guidance changes.
- Run `scripts/browser-smoke.mjs` after UI changes.
