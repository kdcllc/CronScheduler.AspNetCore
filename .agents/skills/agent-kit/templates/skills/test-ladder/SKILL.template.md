---
name: test-ladder
description: Staged test ladder for {{PROJECT_NAME}} — run new tests first, then impacted tests, and the full suites only after all changes in the cycle are applied. Use whenever writing, running, or evaluating tests.
user-invocable: true
disable-model-invocation: true
---

# Test Ladder (Staged)

The full test suites are too slow to run after every edit. Agents and orchestrators
MUST climb this ladder. The same three rungs apply to every stack in the project.

```
Rung 1  New tests          →  only tests created or rewritten in this change
            │ pass
            ▼
Rung 2  Impacted tests     →  existing tests that exercise the files you changed
            │ pass
            ▼
Rung 3  Full suites        →  {{FULL_TEST_COMMAND}}
            ONLY after every planned change in the cycle is applied
```

**Stop on the first failing rung.** Fix, then restart at rung 1 for that fix. Do not
"just run everything" to see what broke.

## When each rung runs

| When | Rungs |
|------|-------|
| TDD red/green, a single task (except a designated closer task — next row), an evaluator-driven fix, mid-cycle implementation | **1 then 2 only** |
| A goal's designated closer task, when its task file mandates the full-suite run as the closing gate | **1 → 2 → 3** (the delegated cycle-end run — see the carve-out below) |
| All planned changes for the request/goal are applied (Phase 5 Quality Checks, or the last step of an ad-hoc change) | **1 → 2 → 3** |
| Docs-only / no testable code | Skip all rungs |

A **cycle** is one user request or one `feature` goal — not one file save and not one
task. Phase 4 tasks and implement→evaluate retries are mid-cycle. One exception: a
goal's **designated closer task** applies the cycle's last planned changes, so
cycle end occurs inside it (see the carve-out below).

Rung 3 runs **every** stack's full suite, even if the cycle only touched one of them.
That is the regression gate; it runs at cycle end — in a goal's
designated closer task when it has one (see the carve-out below), and in the
orchestrator's Phase 5 Quality Checks.

## Rung 1 — New tests

Run only the test files or test ids you just added or substantially rewrote:

```bash
{{TARGETED_TEST_COMMAND}}
```

If you wrote no new tests (implementation-only change), skip rung 1 and say so, then
run rung 2.

## Rung 2 — Impacted tests

Existing tests that exercise the **production** files you changed. Do **not** expand
this to the whole suite.

### Convention map

<!-- BOOTSTRAP[path-test-conventions]: fill with this project's changed-path → test-file conventions, e.g.
| Changed path | First impacted tests |
|--------------|----------------------|
| src/<module>/ | tests/test_<module>*.py |
| src/frontend/**/<name>.tsx | colocated <name>.test.tsx |
Include per-stack command forms and any cd requirements. -->

### Discover extras

Grep the test tree for imports of the changed module and add those files to the rung 2
command. If a shared-core change would pull in most of the suite, list the test files
that import that core and run **those files** — still not a bare full-suite run. If
rung 2 is empty (brand-new module), treat it as a no-op and say so.

## Rung 3 — Full suites (cycle end only)

```bash
{{FULL_TEST_COMMAND}}
```

<!-- BOOTSTRAP[full-suite-commands]: list every stack's full-suite command, plus lint commands that run only
     at cycle end (e.g. frontend lint only if frontend changed). -->

Forbidden until rung 3: any bare full-suite invocation or pattern-less test run.
A `-k <name>`-style selector is a rung 1/2 tool, not a substitute for rung 3.

A rung-3 failure is classified by the orchestrator per ORCHESTRATION.md `### Quality Checks` (flaky, local-edits, pre-existing, introduced) before any fix.

## Failure handling

```
Rung 1 fails  → fix; re-run rung 1; do not start rung 2 or 3
Rung 2 fails  → fix; re-run rung 1 then rung 2; do not start rung 3
Rung 3 fails  → fix; restart at rung 1 for that fix, then 2, then 3 again
```

Never loop on the full suite. A full-suite failure is a signal to narrow, not to
re-run everything immediately.

## Who does what

| Role | Allowed rungs |
|------|---------------|
| `implementer` | 1 then 2. Rung 3 only when executing the goal's designated closer task (see the carve-out below). |
| `test-writer` | 1 then 2. Rung 3 only when executing the goal's designated closer task (see the carve-out below). |
| `evaluator` (via `task-criteria`) | Requires evidence of 1 then 2. Does **not** fail a task for skipping rung 3 (see the carve-out below for a closer task's mandated run). |
| `feature` orchestrator (and ad-hoc main-session work) | After every task is PASS and the final audit is APPROVED: **spawn `terminal`** for rung 3 — the orchestrator's rung-3 authority (when it runs) is unchanged, only its execution is delegated. Never run rung 3 itself in this session. |
| `terminal` | Executes any Bash or PowerShell command it is spawned with. No Edit/Write tools. Returns only the result the caller asked for (default: compact `{exit; excerpt; log path}`). Rung 3 is always a spawn of this agent. |
| `qa-evaluator` | Behavioral evidence only. Does not replace the ladder. |
| `evidence-collector` | None — gathers QA evidence only; never runs ladder rungs. |

## Closer-task carve-out (delegated rung 3)

A goal's **designated closer task** may run rung 3 when its task file mandates
it as the closing gate. All conditions required:

- **Written mandate**: the task file names the full-suite run in its
  requirements. Task files are authored by the orchestrator, so the mandate is
  the orchestrator's cycle-end rung-3 authority delegated in writing — never
  the executor's own initiative.
- **Actually last**: the closer task is the final task in dependency order;
  every other planned change of the cycle lands before or inside it, so its
  completion is the moment "after every planned change in the cycle is
  applied" — the run is the cycle-end run, not a mid-cycle exception.
- **At most one** designated closer task per goal.

On a rung-3 failure outside its write fence, a closer task escalates per the
write-fence rule — it never edits an out-of-fence file to make a suite pass.

Evaluator interplay is unchanged: per `task-criteria`, no task is ever failed *for
skipping rung 3*; a closer task that skips its mandated run fails
requirements-completeness (its task file said so), not the ladder. The
orchestrator's rung-3 authority is unchanged: Phase 5 Quality Checks still
runs the full suites at cycle end — the Who-does-what row above delegates only
the *execution* of that run to a spawned `terminal`, not the authority over
*when* it happens. The closer task's run is an additional, evaluated regression
gate — it never replaces Phase 5.

A spawned `terminal` reporting rung 3 output is **not** a designated closer
task: it has no write fence, no task file, and no mandate of its own — it is a
fenceless command runner, not a worker with a written mandate. The closer-task
carve-out above still requires a *worker* (`implementer`/`test-writer`) with a
task file that names the full-suite run in its requirements; spawning
`terminal` never substitutes for that gate and never replaces Phase 5.

This skill's tables plus this carve-out are the authoritative rung rules;
one-line summaries elsewhere ("executors never run rung 3") are shorthand for
them.

## Report this every time tests run

```markdown
## Test ladder
- Rung 1 (new): `[command]` → pass | fail | skipped ([why])
- Rung 2 (impacted): `[command]` → pass | fail | skipped ([why])
- Rung 3 (full suites): deferred until cycle end | `[commands]` → pass | fail
```

## Hard rules

- Tests still mock all external service/network access. The ladder does not change that.
- Do not invent runners or tools that are not configured in the project.
