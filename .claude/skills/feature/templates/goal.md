# Goal: [name]

## Problem Statement

[What is broken/missing, for whom, and why it matters. 2–5 sentences.]

## Discovery Summary (Phase 1 Q&A)

| # | Question | Answer |
|---|----------|--------|
| 1 | <question> | <answer> |

The goal evaluator checks tasks against this table — every answered decision must be reflected in a task.

## Recalled memory

[Record ids picked at recall, or `none`.]

## Success Criteria

- [ ] [Observable, verifiable outcome — behavior, not activity]
- [ ] [...]

## Constraints

- [Must reuse / must not touch / performance / compatibility constraints]

```yaml
phases:
  align_docs: true|false    # recorded from Phase 1 answers; checked after Phase 5 APPROVED (default false)
  pull_request: true|false  # recorded from Phase 1 answers; checked after Phase 5 APPROVED (default true)
  ladder: escalate|auto      # escalate (default): on cycle-3 exhaustion, escalate to the user with the continuation ladder offered; auto: run the ladder (loop-created goals); auto may enter it early (reference/fix-cycles.md § Early ladder entry).
  parallel: true|false       # default true; false runs Phase 4 one task at a time
  qa: run|skip               # default skip; run → evidence-collector + qa-evaluator after Phase 5 approval
  trace: planner|blind       # planner (default): the planner-written trace only; blind also runs the consumer-trace evaluator mode before Phase 3, for goals whose surfaces are destructive, security or infra. An absent trace key means planner, so existing goals and loop-created goals behave as today.
```

## Out of Scope

- [Explicitly excluded work, so the evaluator can flag scope creep]

## Searches

> Guidance — replace this block with one item per search; the example below shows the shape.
> Omit `## Searches` when the goal changes no shared surface (see `## Consumers`).
>
> 1. An item is one line matching ``^- \*\*S<n>\*\* (`+)<command>\1 — <N> hits?$``: `S<n>` in bold, the literal command in a code span, then a space, an em dash (U+2014), a space and the count.
>    - The command may be wrapped in a double-backtick span when it contains a backtick.
>    - It may contain ` — ` and `|`, because the parse anchors on the line end.
>    - Write `1 hit` for one and `<N> hits` otherwise (`0 hits`); `1 hits` is invalid.
> 2. A fenced `text` block follows on the next lines, indented with the item. It holds one hit per line, and the number of non-empty lines equals N. For 0 hits the block is empty.
> 3. Every hit line is `<path>:<line>:<text>`. Searches use `-H` / `--with-filename` (or pass a directory) so single-file searches still print the path. A leading `./` is allowed and ignored.
> 4. Searches exclude `_memory/` (for example `--glob '!_memory/**'`). Hits under `_memory/` are ignored, so a goal's own files never become consumers.
> 5. Every command was run by the `terminal` agent, and its output is pasted verbatim.

- **S1** `rg -n -H '<pattern>' <paths> --glob '!_memory/**'` — 1 hit
  ```text
  <path>:<line>:<text>
  ```

## Consumers

> Guidance — replace the example rows with one row per consumer of each surface a task changes.
>
> - Cells split on unescaped `|`. A literal pipe inside a cell is written `\|`.
> - Consumer is one backticked repo-relative path.
> - Class is exactly `changes`, `unaffected` or `owner-excluded`.
> - `changes` evidence names `task NN` (two digits, optional letter), or is exactly `Phase 6` for a doc consumer that Phase 6 align-docs updates. `Phase 6` is valid only when the goal's `phases:` block sets `align_docs: true`.
> - `unaffected` evidence starts with `test: ` (a covering test path), `diff: ` (a command showing the interface is unchanged) or `search: S<n>` (a search with 0 hits).
> - `owner-excluded` evidence names `Q&A row <n>`, a row of the Discovery Summary table.
> - Every hit path in `## Searches` (outside `_memory/`) appears as a Consumer.
> - A goal that changes no shared surface omits `## Searches`, and `## Consumers` holds one body line, `none — <reason>`, on the line after the heading.

| Surface | Consumer | Class | Evidence |
|---------|----------|-------|----------|
| `<surface>` | `<path>` | changes | task NN |
| `<surface>` | `<path>` | unaffected | test: `<path>` |
| `<surface>` | `<path>` | owner-excluded | Q&A row <n> |

## Tasks (dependency order)

| # | Task file | Layer | Depends on |
|---|-----------|-------|------------|
| 01 | `01-[name].md` | [layer] | — |
| 02 | `02-[name].md` | [layer] | 01 |
| NN | `NN-tests.md` | tests | all |

**Contract first.** If this goal touches a shared boundary or interface, the first task
is a dedicated contract/scaffold task — it defines the types, schemas, and port
interfaces and creates the empty file skeletons — and every task that consumes them
lists it in `depends_on`. Consumers then build against that frozen interface instead of
each other's files.
