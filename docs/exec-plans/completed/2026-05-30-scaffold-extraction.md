# Scaffold Extraction Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task with spec and quality review gates once the skeleton and self-smoke shape are stable.

> Historical note: this plan closed the first repository-local slice. On
> 2026-06-01, the maintained template was deliberately split to
> <https://github.com/carjorvaz/cl-web-template>; this game repository now keeps
> only extraction history and points reusable template work there.

**Goal:** Extract this repository's proven Common Lisp web-app harness into a small `scaffold/template/` starter that can generate or copy a new app and validate itself.

**Architecture:** Keep extraction repository-local first. The template should default to a small Common Lisp hypermedia app with a domain layer and a web adapter, and expose optional extension points for Coalton rules, SQLite persistence, and htmx SSE rather than baking Ultimate Tic Tac Toe assumptions into the starter.

**Source contracts:** `docs/common-lisp-web-template.md` defines the target shape; `docs/HARNESS.md` defines agent-first taste; the broader roadmap was `docs/exec-plans/completed/2026-05-22-rooms-watch-sse-scaffold.md` Phase 7.

## Acceptance Criteria

- `scaffold/README.md` explains status, scope, and non-goals.
- `scaffold/template/` contains the starter template source or a manifest-backed skeleton.
- Template defaults include `.envrc`, `flake.nix`, ASDF systems, `AGENTS.md`, focused docs, scripts, `assets/style.lass`, generated `static/style.css`, minimal static JS, `src/package.lisp`, `src/domain.lisp`, `src/web.lisp`, and tests.
- Template parameters are explicit: app name, ASDF system, package prefix, default port, source URL, license, and optional Coalton/SQLite/SSE toggles.
- A scaffold self-smoke can generate/copy a temporary app and run docs validation plus Lisp tests.
- Existing game validation remains green.
- No separate repository is created until the in-repo template proves useful.

## Non-Goals For The First Slice

These non-goals applied only to the first repository-local slice before the
maintainer decision to split the proven template.

- Do not publish a separate scaffold repo.
- Do not build a clever generator before a copyable template exists.
- Do not include game-specific rules, board UI, or room product behavior in the default template.
- Do not require manual screen-reader review for this private-app extraction milestone.

## Implementation Tasks

### Task 1: Scaffold Contract Skeleton

**Objective:** Make Phase 7 visible in the repository without copying app code prematurely.

**Files:**
- Create: `scaffold/README.md`
- Create: `scaffold/template/README.md`
- Modify: `scripts/validate-docs.lisp`
- Modify: `docs/exec-plans/completed/2026-05-22-rooms-watch-sse-scaffold.md`

**Steps:**
1. Create scaffold docs that describe status, rules, template parameters, required files, and validation.
2. Add docs-validator markers for the scaffold docs so future agents cannot miss or delete them silently.
3. Add a progress-log entry to the broad active roadmap.
4. Validate with `direnv exec . sbcl --script scripts/validate-docs.lisp` and `git diff --check`.
5. Commit as `docs: start scaffold extraction plan`.

### Task 2: Minimal Copyable Template

**Objective:** Add a neutral starter app under `scaffold/template/` that is small enough to inspect.

**Files:**
- Create template copies of `.envrc`, `flake.nix`, `app.asd`, `AGENTS.md`, `README.md`, `docs/`, `scripts/`, `src/`, `static/`, `assets/`, and `t/`.
- Avoid copying Ultimate Tic Tac Toe game state, rooms, screenshots, or product docs except as neutral placeholders.

**Steps:**
1. Start from the layout in `docs/common-lisp-web-template.md`.
2. Make the app render a single useful page plus `/health` and `/version`.
3. Keep local htmx as optional/static, but avoid SSE by default.
4. Keep CSS source/generated pair and asset validation.
5. Keep docs validation and architecture validation.
6. Run template-local tests manually from the generated/copy location before adding self-smoke.

### Task 3: Scaffold Self-Smoke

**Objective:** Prove the template works after copy/generation, not just that files exist.

**Files:**
- Create: `scripts/scaffold-smoke.mjs` or `scripts/scaffold-smoke.lisp`.
- Modify: `flake.nix` to expose a check/app if appropriate.
- Modify: `docs/common-lisp-web-template.md` and `scaffold/README.md` with exact commands.

**Steps:**
1. Copy or instantiate `scaffold/template/` into a temporary directory.
2. Replace parameters if the first version uses tokens.
3. Run docs validation and Lisp tests inside the temporary app.
4. Keep the smoke command independent from private paths and credentials.
5. Add it to the repo validation matrix only after it is stable locally.

### Task 4: Optional Feature Gates

**Objective:** Add optional template modules only after the baseline template is proven.

**Candidate switches:**
- `:coalton-rules` for typed pure kernels.
- `:sqlite` for durable repository/session examples.
- `:sse` for htmx SSE observation paths.

**Rule:** Each optional switch needs its own self-smoke coverage. Do not let optional modules complicate the default starter.

## Risks And Decisions

- **Risk:** Copying too much of the game fossilizes game-specific complexity. Mitigation: start with docs skeleton, then neutral minimal app.
- **Risk:** A generator hides simple file relationships. Mitigation: make the first template copyable before automating parameter substitution.
- **Risk:** Nix flakes ignore untracked scaffold files during checks. Mitigation: stage new scaffold files before running Nix checks that depend on them.
- **Decision:** Manual screen-reader review remains a runbook, not a routine blocker for this private scaffold extraction.

## Validation Commands

```sh
direnv exec . sbcl --script scripts/validate-docs.lisp
direnv exec . sbcl --script scripts/test.lisp
direnv exec . sbcl --script scripts/validate-architecture.lisp
direnv exec . sbcl --script scripts/validate-assets.lisp
direnv exec . node scripts/browser-smoke.mjs
nix flake check
nix build .#
```

## Progress Log

- 2026-05-30: Started focused Phase 7 scaffold extraction plan after room, SSE, and SQLite persistence landed and CI was green on `master`.
- 2026-05-31: Added the first copyable `scaffold/template/` app, repository `scripts/scaffold-smoke.mjs`, `nix run .#scaffold-smoke`, and CI scaffold-smoke wiring. Verified `direnv exec . node scripts/scaffold-smoke.mjs`, `nix run .#scaffold-smoke`, template-local `nix develop -c node scripts/browser-smoke.mjs`, `nix flake check --print-build-logs`, and `BROWSER_SMOKE_SKIP_SCREENSHOTS=1 nix run .#browser-smoke`.
- 2026-05-31: Closed the baseline extraction plan after the copyable template
  and self-smoke were validated; optional Coalton, SQLite, and SSE template
  modules remain future feature gates rather than baseline requirements.
- 2026-06-01: Split the proven template into the standalone public repository
  `carjorvaz/cl-web-template`; the game repository now points there and no
  longer carries the duplicate template tree or scaffold-smoke CI job.

## Completion Criteria

Completed first slice: `scaffold/template/` could be copied into a temporary app
that passed its own docs validation, asset validation, architecture validation,
and Lisp tests through `scripts/scaffold-smoke.mjs`.

Superseded maintenance location: <https://github.com/carjorvaz/cl-web-template>.
