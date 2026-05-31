# Harness And Engineering Taste

Last reviewed: 2026-05-30

This repository is an agent-first Common Lisp web-app scaffold.

## Agent-First Harness

- Keep `AGENTS.md` as a map, not a manual.
- Treat code, docs, tests, validators, and scripts as the system of record.
- Make validation commands obvious and runnable locally.
- Prefer short-lived, reviewable changes.
- Convert recurring review feedback into tests, docs, or validators.

## Common Lisp Taste

- Prefer server-rendered HTML and ordinary form/link semantics.
- Keep domain logic independent from HTTP and rendering.
- Prefer plain functions, structs, and conditions before macros or frameworks.
- Keep package boundaries meaningful and mechanically checked.
- Use dependencies when they improve clarity more than local code would.

## Feedback Loops

A good change updates the relevant test, validator, or document when it changes a durable rule.
