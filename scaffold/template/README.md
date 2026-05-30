# Common Lisp Web App Template

This directory will become the copyable starter app described by `docs/common-lisp-web-template.md`.

## Template Parameters

The template must make these values easy to replace before it is considered complete:

- app display name;
- ASDF system name;
- package prefix;
- default HTTP port;
- source-code URL;
- license text and SPDX headers;
- optional Coalton rules support;
- optional SQLite persistence support;
- optional htmx SSE support.

## Required Files

The complete template should contain:

```text
.envrc
flake.nix
app.asd
README.md
AGENTS.md
assets/style.lass
docs/README.md
docs/ARCHITECTURE.md
docs/HARNESS.md
docs/PRODUCT.md
docs/RELIABILITY.md
docs/QUALITY.md
docs/PLANS.md
docs/technical-debt.md
scripts/run.lisp
scripts/test.lisp
scripts/build-assets.lisp
scripts/validate-assets.lisp
scripts/validate-architecture.lisp
scripts/validate-docs.lisp
scripts/browser-smoke.mjs
src/package.lisp
src/domain.lisp
src/web.lisp
static/app.js
static/htmx.min.js
static/style.css
t/package.lisp
t/domain-tests.lisp
t/web-tests.lisp
```

Optional extension files may exist under clearly named subdirectories or template switches, but they must not be required for the default starter.

## Generation Contract

The first implementation may be a copyable directory rather than a parameterized generator. Before adding a generator, prove that the copied template can validate in a temporary directory.

A generated or copied app must be able to:

1. start a local server;
2. run Lisp behavior tests;
3. validate docs and source boundaries;
4. validate generated CSS freshness;
5. optionally run a minimal browser smoke when Playwright is available.

## Non-Goals

- No Ultimate Tic Tac Toe product behavior in the default template.
- No room, watcher, SQLite, or SSE code in the default template unless enabled as an optional extension.
- No separate scaffold repository until this in-repo template proves useful.
