# Plans

Last reviewed: 2026-05-15

Most changes in this repository are small enough for an ephemeral checklist.
Create a checked-in execution plan when the work needs durable context across
multiple runs or when the implementation has meaningful uncertainty.

## When To Create A Plan

Create a plan for:

- cross-layer behavior changes that touch rules, game state, web rendering, and
  tests;
- substantial UI redesigns;
- reliability or deployment work with multiple validation steps;
- refactors where the target architecture matters more than a single patch.

Skip a checked-in plan for:

- single-test fixes;
- copy changes;
- narrow documentation edits;
- small bug fixes with obvious validation.

## Plan Location

- Active plans belong under `docs/exec-plans/active/`.
- Completed plans move to `docs/exec-plans/completed/`.
- One-off cleanup candidates belong in `docs/technical-debt.md` instead.

## Plan Shape

A useful plan includes:

- goal and acceptance criteria;
- files or modules likely to change;
- progress log with dated entries;
- decisions made during implementation;
- validation performed before completion.
