# Common Lisp Web Template

Last reviewed: 2026-05-16

Use this document as the extraction target for future small Common Lisp web
apps. It records the stack and repository shape this project has earned through
actual use; it is a template contract before it becomes a generator.

## Purpose

The template should make the boring parts of a serious Common Lisp web app
repeatable:

- start from a pinned local development shell;
- render real HTML on the server;
- keep domain logic independent from HTTP and CSS;
- author CSS in Lisp source form and serve generated static assets;
- validate boundaries, docs, assets, behavior, and browser output with one
  deterministic feedback loop.

The goal is not to put every byte in Lisp. The goal is to keep the application
model, HTML rendering, CSS source, and verification harness close to Lisp while
using small browser-native pieces where they are the simpler public contract.

## Stack

- `SBCL` as the primary implementation.
- `ASDF` systems for app, assets, and tests.
- `Nix` for a reproducible shell and CI check.
- `Clack` for the HTTP application boundary.
- `Lack` for middleware such as sessions.
- `ningle` for small route dispatch.
- `Spinneret` for server-rendered HTML.
- `LASS` for authored CSS, compiled into `static/style.css`.
- `Woo` as the default local/deployed backend.
- `Hunchentoot` as a fallback backend and test target.
- Vendored `htmx` for progressive form swaps.
- Small vanilla JavaScript only for browser behaviors HTML cannot provide.
- `FiveAM` for Lisp behavior tests.
- Playwright-driven browser smoke for layout, accessibility, and screenshots.

Coalton is optional. Use it for a compact pure rules slice when types clarify a
domain kernel. Keep the mutable app state and HTTP boundary in ordinary Common
Lisp unless the typed island is pulling real weight.

## Repository Shape

A new app should start with this layout:

```text
.
├── flake.nix
├── app.asd
├── README.md
├── AGENTS.md
├── assets/
│   └── style.lass
├── docs/
│   ├── README.md
│   ├── ARCHITECTURE.md
│   ├── PRODUCT.md
│   ├── RELIABILITY.md
│   ├── QUALITY.md
│   └── technical-debt.md
├── scripts/
│   ├── run.lisp
│   ├── test.lisp
│   ├── build-assets.lisp
│   ├── validate-assets.lisp
│   ├── validate-architecture.lisp
│   └── validate-docs.lisp
├── src/
│   ├── package.lisp
│   ├── domain.lisp
│   └── web.lisp
├── static/
│   ├── app.js
│   ├── htmx.min.js
│   └── style.css
└── t/
    ├── package.lisp
    ├── domain-tests.lisp
    └── web-tests.lisp
```

Larger apps may split `src/domain.lisp` into more files, but keep dependency
direction explicit. The default direction is:

`domain -> web`

If there is a pure rules kernel, use:

`rules -> domain -> web`

## CSS Policy

Author CSS in `assets/style.lass`, compile it with
`scripts/build-assets.lisp`, and serve only generated CSS from `static/`.

This gives the project the useful part of managing CSS in Lisp: the stylesheet
source lives in a Lisp syntax, can use Lisp-side build tooling, and can be
checked mechanically. It avoids the expensive part: generating CSS during
requests or hiding browser-facing behavior behind clever server abstractions.

Template defaults:

- keep selectors class-based and semantic;
- use stable layout dimensions for repeated controls and boards;
- keep accessibility utility classes, such as `.visually-hidden`, in the base
  stylesheet;
- validate that `static/style.css` matches `assets/style.lass`;
- do not let `src/web.lisp` call `lass` or emit ad hoc inline styles.

## Hypermedia Contract

The template should treat HTML as the public application protocol:

- `GET /` returns the full page.
- `GET /health` returns a plain readiness response.
- `GET /version` returns app identity and version.
- `POST` routes mutate server-side state and redirect for plain forms.
- htmx requests may receive fragments, but those fragments must remain valid
  server-rendered HTML.

Request parsing belongs in `src/web.lisp`. Domain functions should receive
validated Lisp values, not raw query strings, form strings, cookies, Clack envs,
or htmx headers.

## Verification Harness

The template is only useful if it carries the feedback loop with it:

- `scripts/test.lisp` runs unit and HTTP rendering tests.
- `scripts/build-assets.lisp` generates CSS.
- `scripts/validate-assets.lisp` rejects stale generated assets.
- `scripts/validate-architecture.lisp` enforces package direction and forbidden
  boundary references.
- `scripts/validate-docs.lisp` keeps the human map current.
- `scripts/browser-smoke.mjs` drives a browser through the core flow, checks
  accessibility structure, audits accessible names and color contrast, verifies
  no unexpected external requests happen, and compares screenshot baselines.
- `nix flake check` runs the deterministic suite expected in CI.

Keep the browser smoke app-specific but the helpers reusable. The reusable
pieces are page startup, backend probes, external-request detection, accessible
control checks, color-contrast checks, overflow checks, screenshot refresh, and
PNG comparison.

## Extraction Checklist

When turning this project into a starter template:

- replace game-specific packages and docs with neutral app names;
- keep `assets/style.lass` and `static/style.css` as the CSS source/generated
  pair;
- keep the static asset route pattern;
- keep conservative security headers at the Clack boundary;
- keep the Hunchentoot backend smoke even when Woo is the default;
- keep docs validation from the start;
- keep a manual accessibility review runbook when the app has meaningful UI;
- remove Coalton unless the new app has a pure rules kernel that benefits from
  it;
- make the first screen the actual application, not a landing page.

## When To Deviate

Use a different stack only when the app has a real pressure this template does
not serve:

- use Parenscript only when browser-side behavior grows enough to need generated
  JavaScript or shared Lisp macros;
- use a database when session state is no longer enough;
- use a richer router only when route composition becomes a real maintenance
  problem;
- use a frontend framework only when server-rendered HTML plus htmx cannot
  provide the interaction model cleanly.

Until then, prefer the small Common Lisp hypermedia stack. It is inspectable,
debuggable, and easy for future agents to validate.
