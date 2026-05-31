# Common Lisp Web App

A small server-rendered Common Lisp web app scaffold using Clack, Lack, Ningle,
Spinneret, LASS, FiveAM, Nix, and Playwright.

## Run

```sh
direnv allow
sbcl --script scripts/run.lisp
```

or without enabling direnv:

```sh
nix develop -c sbcl --script scripts/run.lisp
```

The app listens on `http://127.0.0.1:4242/` by default. Set `PORT` to change
the port, `SERVER=hunchentoot` to use the fallback backend, `SOURCE_CODE_URL` to
change the footer link, and `APP_VERSION` to change `/version` output.

## Test

```sh
sbcl --script scripts/test.lisp
sbcl --script scripts/validate-docs.lisp
sbcl --script scripts/validate-architecture.lisp
sbcl --script scripts/validate-assets.lisp
node scripts/browser-smoke.mjs
```

Regenerate CSS after editing `assets/style.lass`:

```sh
sbcl --script scripts/build-assets.lisp
```

Run all deterministic checks with:

```sh
nix flake check
```

## Template Parameters

The first copyable version is intentionally literal. Rename these values after
copying the directory into a new repository:

- app name: `Common Lisp Web App`;
- ASDF system: `app` and `app/test`;
- package prefix: `app`, with packages such as `app.web`;
- default port: `4242`;
- source URL: `SOURCE_CODE_URL` environment variable;
- license: `AGPL-3.0-or-later` SPDX headers;
- optional features: Coalton, SQLite, and htmx SSE are not enabled by default.

## Required Files

Keep the starter as an inspectable repository, not a hidden generator output:

- `.envrc`, `flake.nix`, `app.asd`, `README.md`, and `AGENTS.md`;
- focused docs under `docs/`;
- validation and run scripts under `scripts/`;
- Lisp source under `src/` and tests under `t/`;
- authored CSS in `assets/style.lass` and generated CSS in `static/style.css`;
- small static browser assets in `static/`.

## Generation Contract

A scaffold smoke may copy this directory into a temporary app and run the local
validation loop there. The copied app must pass without relying on private paths,
Ultimate Tic Tac Toe packages, generated chat history, or credentials.

If a future generator replaces literal copying, it must preserve the same public
file layout and validation commands before adding parameter substitution.

## Non-Goals

- Do not include Ultimate Tic Tac Toe rules, room state, or product behavior.
- Do not enable Coalton, SQLite, WebSockets, or SSE in the default starter.
- Do not hide normal Common Lisp files behind a clever generator.
- Do not publish this as a separate repository before the in-repo smoke stays
  green.

## Repository Knowledge

`AGENTS.md` is the short agent map. Durable project knowledge lives under
`docs/`.
