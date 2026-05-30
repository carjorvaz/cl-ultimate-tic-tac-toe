# Scaffold Extraction

This directory is the in-repository proving ground for extracting the Common Lisp web-app harness from Ultimate Tic Tac Toe.

## Status

Phase 7 has started as a repository-local scaffold. The first goal is a copyable `scaffold/template/` starter plus a self-smoke that proves a generated or copied app can run its own validation loop.

Do not split this into a separate repository until the in-repo template has been generated or copied into a temporary app and validated.

## Rules

- Keep the default template small: `domain -> web`.
- Treat Coalton rules, SQLite persistence, and htmx SSE as optional extensions, not default template complexity.
- Preserve the agent-first harness: `AGENTS.md` as a map, focused docs under `docs/`, and mechanical validation scripts.
- Keep CSS source/generated behavior: edit `assets/style.lass`, serve `static/style.css`, and validate freshness.
- Keep browser behavior server-rendered and hypermedia-first.
- Remove game-specific product behavior from the scaffold unless it is a neutral example.

## Validation

The scaffold is not complete until a self-smoke can copy or instantiate `scaffold/template/` into a temporary app and run, at minimum:

```sh
sbcl --script scripts/test.lisp
sbcl --script scripts/validate-docs.lisp
```

The parent repository must still pass its normal validation while the scaffold is under construction.

## Plan

See `docs/exec-plans/active/2026-05-30-scaffold-extraction.md` for the focused implementation plan and `docs/common-lisp-web-template.md` for the template contract.
