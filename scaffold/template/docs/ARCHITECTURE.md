# Architecture

Last reviewed: 2026-05-30

This scaffold is a server-rendered Common Lisp hypermedia app.

## Components

- `src/package.lisp` declares package boundaries.
- `src/domain.lisp` owns app-domain behavior.
- `src/web.lisp` owns Clack responses, Ningle routes, Spinneret rendering, static assets, and request parsing.
- `assets/style.lass` is the source stylesheet.
- `static/style.css` is generated CSS served by the web layer.
- `t/` contains FiveAM tests.
- `scripts/` contains run, test, and validation entry points.

## Boundaries

Layer order is:

`domain -> web`

Compile-time dependencies point from adapters toward lower layers: `src/web.lisp`
may call `src/domain.lisp`, but `src/domain.lisp` must not call or import
`src/web.lisp`.

Rules:

- `src/domain.lisp` must not depend on Clack, Lack, Ningle, Spinneret, CSS, or browser assets.
- `src/web.lisp` is the adapter boundary; convert request data before calling domain code.
- `assets/style.lass` is build-time input; `src/web.lisp` serves generated `static/style.css` only.

## Mechanical Guards

- `scripts/test.lisp` runs domain and web tests.
- `scripts/validate-architecture.lisp` validates system order and forbidden boundary references.
- `scripts/validate-assets.lisp` verifies generated CSS freshness.
- `scripts/validate-docs.lisp` validates required guidance docs and SPDX headers.
- `scripts/browser-smoke.mjs` verifies browser-visible behavior.
