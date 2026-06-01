# Scaffold Extraction

This directory records the extraction history for the reusable Common Lisp web
app scaffold that began in this repository.

## Status

The scaffold has been split into the standalone public template repository:

- <https://github.com/carjorvaz/cl-web-template>

`cl-web-template` is now the canonical place for the copyable starter, template
smoke, CI, and future optional-module work. This repository keeps only the
historical extraction notes and product-specific game code.

## Rules

- Do not reintroduce a duplicate template tree under this game repository.
- Put reusable template changes in `carjorvaz/cl-web-template`.
- Keep this repository focused on Ultimate Tic Tac Toe product behavior.
- Keep app-local harness lessons here only when they affect this game repo; move
  generic scaffold improvements to the template repo.

## Validation

Validate the separated template in its own repository:

```sh
cd /Users/cjv/Documents/cl-web-template
nix flake check
nix run .#template-smoke
nix run .#browser-smoke
```

This game repository no longer runs scaffold smoke in CI. It still runs its own
Lisp tests, architecture/docs/assets validators, Nix checks, and browser smoke.

## Plan

See `docs/exec-plans/completed/2026-05-30-scaffold-extraction.md` for the
baseline implementation history and `docs/common-lisp-web-template.md` for the
historical template contract that was promoted into `cl-web-template`.
