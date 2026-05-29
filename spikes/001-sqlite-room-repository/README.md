# 001: SQLite Room Repository Spike

Date: 2026-05-29

## Question

Given the existing Nix/ASDF Common Lisp stack, when SQLite persistence is added
behind the room repository API, can the project use nixpkgs' `sbclPackages.sqlite`
for deterministic schema initialization, parameterized statements, constraint
handling, durable reopen, and revision-gated updates?

## Approach

- Use the locked flake's nixpkgs and add `sqlite` to the same `sbcl.withPackages`
  dependency list used by the app.
- Exercise the public `sqlite` package API from a throwaway Lisp script.
- Keep production source unchanged until the dependency/API is proven.

## Commands

```sh
# Standalone sqlite package/API probe.
nix shell --impure --expr 'let pkgs = import (builtins.getFlake "github:NixOS/nixpkgs/nixpkgs-unstable") { system = builtins.currentSystem; }; in pkgs.sbcl.withPackages (ps: [ ps.sqlite ])' \
  --command sbcl --script spikes/001-sqlite-room-repository/sqlite-probe.lisp

# Locked project dependency-set probe with sqlite added.
nix shell --impure --expr 'let flake = builtins.getFlake "path:/Users/cjv/Documents/ultimate-tic-tac-toe"; pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; }; in pkgs.sbcl.withPackages (ps: with ps; [ coalton named-readtables clack lack lack-middleware-session ningle spinneret lass clack-handler-woo hunchentoot clack-handler-hunchentoot bordeaux-threads ironclad fiveam usocket sqlite ])' \
  --command sbcl --noinform --disable-debugger \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (merge-pathnames "ultimate-tic-tac-toe.asd" (uiop:getcwd)))' \
  --eval '(asdf:load-system :sqlite)' \
  --eval '(asdf:load-system :ultimate-tic-tac-toe)' \
  --eval '(format t "project+sqlite load ok~%")' \
  --quit
```

## Results

The standalone probe validated:

- opening and reopening a file-backed database with `sqlite:with-open-database`;
- deterministic schema creation with `sqlite:execute-non-query`;
- positional parameter binding;
- primary-key constraint errors as `sqlite:sqlite-constraint-error`;
- explicit `sqlite:with-transaction` rollback on error;
- optimistic revision updates with `where code = ? and revision = ?` plus
  `select changes()` to distinguish accepted from stale updates;
- persisted rows survive disconnect/reopen.

The project dependency-set probe validated that adding `sqlite` beside the
current app dependencies allows both `:sqlite` and `:ultimate-tic-tac-toe` to
load in the same SBCL image.

Observed caveats:

- `sbclPackages.sqlite` emits CFFI deprecation warnings about bare struct types
  during load; they did not block loading or execution.
- The package is old (`20190813-git` in nixpkgs), but its small API is sufficient
  for this app's simple repository needs.
- `sqlite:with-transaction` issues plain `begin transaction`; for production
  room writes, prefer explicit `begin immediate transaction` if write-lock timing
  matters under multiple connections.
- The library gives an easy row-count path through `select changes()` after a
  guarded `update`, which is a good fit for stale revision rejection.

## Verdict: VALIDATED

`sbclPackages.sqlite` is feasible for the room persistence layer.

## Recommendation for the real build

1. Add `sqlite` to `mkLisp` in `flake.nix` and `"sqlite"` to the main ASDF
   system dependencies.
2. Refactor `src/rooms.lisp` around a small repository protocol so the existing
   memory repository and a new SQLite repository share `create-room`,
   `view-room`, `claim-seat`, and `play-room-move` behavior.
3. Use `UTTT_ROOM_DB` at the web/startup boundary to select repository type:
   unset => memory repository; set => SQLite repository.
4. Store versioned room payloads, not raw implementation structs. A compact first
   version can serialize room fields explicitly as text columns plus a versioned
   game payload column, then migrate later if needed.
5. For move/seat mutations, do the authorization read and write in one SQLite
   transaction and use revision-gated updates (`where revision = ?`) or equivalent
   row locks to preserve duplicate-submit behavior.
6. Add persistence tests that create a file-backed repository, mutate a room,
   reopen it, and prove stale duplicate writes remain rejected.
