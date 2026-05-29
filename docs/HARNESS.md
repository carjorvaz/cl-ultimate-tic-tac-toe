# Harness And Engineering Taste

Last reviewed: 2026-05-23

This repository is both a game and a proving ground for a reusable Common Lisp
web-app harness. The goal is not only that the app works; the goal is that a
future agent can understand, modify, verify, and extract it without relying on
chat history or maintainer folklore.

## Agent-First Harness

The repository should make the right next action obvious to an agent with a
fresh context window.

- Keep `AGENTS.md` as a map, not a manual. Durable knowledge belongs in focused
  docs under `docs/`.
- Treat repository-local artifacts as the system of record: code, tests, docs,
  executable plans, screenshots, validation scripts, and CI definitions.
- Promote repeated review comments into a mechanical check, a focused doc, or a
  small refactor. Do not leave important taste in chat.
- Make the app bootable and inspectable locally with one command path:
  `direnv exec . sbcl --script scripts/run.lisp` for the app, and the validation
  scripts listed in `AGENTS.md` for feedback.
- Prefer short-lived, reviewable changes. Complex work needs a checked-in plan
  under `docs/exec-plans/active/` with decisions and validation notes.
- Keep failure output actionable. Custom validators should explain both what
  failed and the command or file an agent should use to repair it.

The harness is successful when a capable agent can:

1. validate the current state;
2. reproduce a reported behavior;
3. make a scoped change;
4. validate through Lisp tests and browser inspection;
5. update the relevant docs or validators when it learns a reusable rule.

## Hypermedia And Common Lisp Taste

The design bar is deliberately conservative: boring, inspectable Common Lisp;
server-rendered hypermedia; small client-side enhancements; and mechanical
boundaries.

- HTML is the application protocol. Forms and links should express state
  transitions before inventing JSON endpoints or browser-side application state.
- Request parsing stays at the web boundary. Game and room functions should
  receive validated Lisp values, not raw Clack envs or form strings.
- Keep domain state in ordinary data structures with clear invariants. Use
  structs, conditions, and plain functions until generic functions or macros pay
  for themselves.
- Use macros sparingly and locally. A macro should remove real duplication or
  encode a small language; it should not hide control flow from future readers.
- Prefer clear names and small functions over cleverness. If a future agent must
  simulate too much context to understand a function, split it or document the
  invariant it relies on.
- Keep packages meaningful. A package boundary should correspond to a dependency
  boundary that `scripts/validate-architecture.lisp` can enforce.
- Preserve Lisp-native error modeling where useful. Stable condition reasons,
  such as `move-rejected` reasons, are better than ad hoc strings in lower
  layers; user-facing prose belongs in the web layer.
- Avoid fashion-driven complexity. A dependency is welcome when it is stable,
  inspectable, and cheaper than local code; otherwise a small local helper with
  tests can be better for agent legibility.

## SSE Policy

Room multiplayer should start from the hypermedia model and add server push only
where it improves the model.

- Moves remain ordinary CSRF-protected `POST` forms. SSE is one-way and should
  not become a command channel.
- Watchers and non-active seated players are the primary SSE consumers. Active
  players should not need push to make a move, though their view may subscribe
  for opponent updates.
- Use the htmx SSE extension when adopting SSE: vendor the extension in
  `static/`, load it after local `htmx.min.js`, and use the current attributes
  `hx-ext="sse"`, `sse-connect`, and `sse-swap`. Do not use the obsolete
  built-in `hx-sse` attribute.
- Keep event payloads as server-rendered HTML fragments. A room update event can
  swap the same fragment that `GET /rooms/:code/game` returns.
- Use named events, e.g. `event: room-update`, so the DOM states exactly what it
  listens for.
- Provide a polling fallback or a plain refresh path. SSE is progressive
  enhancement, not a requirement for legal play.
- Add backend and browser-smoke coverage for connection behavior before relying
  on SSE in production.
- Reconsider WebSockets only if a real bidirectional feature appears. Room
  moves, seat claims, and resets do not require WebSockets.

Recommended room event shape when replacing the whole room fragment:

```text
event: room-update
data: <section id="room-game" ...>...</section>
```

For multiline HTML fragments, frame the SSE payload correctly by emitting one
`data:` line per payload line or by rendering the fragment as a single line.

Recommended markup shape keeps the SSE connection and swap instructions on a
stable parent and swaps a child fragment with `outerHTML`, avoiding nested
duplicate `#room-game` nodes:

```html
<div id="room-stream"
     hx-ext="sse"
     sse-connect="/rooms/ABCD23/events"
     sse-swap="room-update"
     hx-target="#room-game"
     hx-swap="outerHTML">
  <section id="room-game">
    ...server-rendered room fragment...
  </section>
</div>
```

## Mechanical Gates

Use explicit gates for large work so agents know when to stop, revise, or ask.

- Pre-flight gates: required docs exist, tests are green before refactor work,
  room database configuration is valid before persistence starts.
- Revision gates: plan reviews, spec compliance reviews, code quality reviews,
  and browser-smoke findings loop back with specific fixes.
- Escalation gates: product choices that change authority, privacy, persistence,
  or public URLs go to the maintainer instead of being guessed.
- Abort gates: stop rather than continue if validation cannot run, the working
  tree is unexpectedly dirty, or a required dependency is unavailable.

## Garbage Collection

Agent-friendly repositories need continuous cleanup so bad patterns do not
become training examples for future edits.

- Retire stale technical-debt items as soon as a check proves they are obsolete.
- Keep `docs/QUALITY.md` honest: update the grade, known gaps, and verification
  matrix when coverage changes.
- Prefer small recurring cleanup patches over large rewrites.
- When a defect recurs, choose one durable remedy: remove the cause, add a test,
  add a validation rule, or record a precise debt item.
- Scaffold extraction should copy the harness discipline, not game-specific
  assumptions. Optional pieces such as Coalton, SQLite rooms, and SSE belong
  behind clear template switches or documented extension points.
