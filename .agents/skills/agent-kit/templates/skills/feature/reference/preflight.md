# Pre-flight (before Phase 3 evaluation attempt 1)

The orchestrator runs this checklist **once** after Phase 2 goal and task files exist
and **before Phase 3 evaluation attempt 1**. Never run it between evaluation attempts.
Pre-flight is **read-only** toward product code: it reads goal/task files and the workspace.
It may write goal artifacts under `_memory/work/goals/<goal>/` (`criteria-evidence.md`)
and scratch samples outside the repo; other changes stay in goal/task
files only. Material amendments re-run pre-flight and the full Phase 3 evaluation with a fresh evaluator and reset the cycle count; additive amendments and criterion corrections run pre-flight checks 1, 2 and 5 on the changed tasks, then a targeted evaluation.
It produces **no score or verdict** and **never replaces** the evaluator.

<!-- BOOTSTRAP[preflight-extra]: List project-specific pre-flight checks here, one bullet each (e.g. "migration file paired with its model change"), or answer "" when there are none. -->

## Checks (stack-agnostic)

Run every check below, plus any project-specific checks listed above (if any).
Count all of them when forming the log line (N in `Pre-flight: N/N pass`).

### 1. Acceptance criteria and paths

For each task, confirm every acceptance criterion's verification method can run in
this workspace — no live service, credential, or unshipped feature required.

For every shell-command criterion, run it against the current tree and record the exact
command and its output in `_memory/work/goals/<goal>/criteria-evidence.md`, or
`not runnable yet — created by task NN` when the criterion depends on files a later
task creates. For **content-inspecting** checks (grep/rg/awk/sed/wc/diff/count assertions)
also record a true negative (passes on the correct shape) and a true positive (fires on
an injected violation); use a minimal scratch sample outside the repo when the code does
not exist yet.

Flag criteria in one task that cannot both pass (mutually unsatisfiable pairs). Flag any
file a criterion requires the task to create or change that is missing from that task's
`writes` — A criterion that requires writing outside the task's `writes` is an ownership gap, not a criteria defect: the orchestrator re-plans ownership as an amendment.
Flag any fence or unchanged check that uses `git status` without `--untracked-files=all`.

For every path in the task's `reads` list and every path in `writes` that the task
**modifies** rather than creates, run `test -e <path>`. Skip paths that are
placeholders containing `<`, `>`, `[`, `]`, or `*`.

**Failure:** a criterion cannot be verified locally, evidence is missing or wrong,
mutually unsatisfiable criteria, an ownership gap, a bad `git status` fence check,
or `test -e` fails for a non-placeholder path the task depends on or modifies.

### 2. Missed callers

`goal.md` carries `## Searches` and `## Consumers` in the goal template's format, or
`## Consumers` with `none — <reason>`. Each search was run by `terminal` and its hits are
pasted verbatim. The searches cover exact-word and derived uses of every changed surface
(derived identifiers such as `Get<symbol>Async`; fallback `grep -rnw` / `grep -rn` when
`rg` is unavailable). A changed surface means identifiers, string keys, commands, flags,
headings, file names and serialized fields, including fields whose type, visibility or
nullability changes.

Run `_kit/trace-lint.sh _memory/work/goals/<goal>/goal.md` and record the command and its
output in `criteria-evidence.md`. Where the stack provides one, also run a trial build or
type-checker scoped to affected modules and record it there.

**Failure:** `trace-lint` exits non-zero; a surface a task changes has no search; or a goal
that changes a shared surface has `none`.

**Transition:** a goal planned before this rule (no `## Consumers` section, with a
`reference-sweep.md`) is checked against that artifact until its next material amendment.
That artifact lists the exact search commands and their hits, and every hit is owned by a
task or justified.

### 3. Scope drift

Every task requirement must trace to a Success Criterion or a Phase 1 Q&A row in
`goal.md`. Nothing listed under `## Out of Scope` in `goal.md` may be required by any
task.

**Failure:** an orphan requirement, or a task that requires out-of-scope work.

### 4. Default-value semantics

Every new optional input, flag, or parameter a task introduces must state its default
explicitly in the task requirements.

**Failure:** a default is missing, or "absent" is treated as meaning "all" without
saying so.

### 5. Stated facts

Prose counts (e.g. "ten files") must equal the enumerated list they describe. Every
value a requirement cites (default, constant, path, line number) must appear in a path
listed in that task's Files to Read — locate each with `rg -n`. The task file's
`writes` YAML block is the single source the orchestrator copies verbatim into context
packages; drift between prose and that block is a failure.

**Failure:** count mismatch, a cited value not found in Files-to-Read paths, or
`writes` prose that does not match the YAML block.

## On failure

The orchestrator **fixes the goal/task files itself** (planning bookkeeping under
`_memory/work/goals/`, not product code), then launches the evaluator. Never escalate
for a pre-flight failure alone.

A fix that would change a **Phase 1 decision** is not a pre-flight fix — route it
through the user like any decision gate.

## Running commands

Commands whose output is short (`test -e`, a scoped search) may run **inline**.

Anything with long output goes through a **`terminal` spawn** per the feature skill's
**Terminal spawn rule** (exact command, shell, and the result needed back — not the
full stream).

## Logging

Record exactly **one** line via `_kit/log-spawn.sh note --goal <g> --text "..."`:

- All checks pass: `Pre-flight: N/N pass` (N = checks run, including project-specific).
- One or more fixes applied: `Pre-flight: fixed K: <one line per fix, semicolon-separated>`.
