---
name: goal-criteria
description: Criteria the evaluator applies when evaluating a goal (goal.md + task files) for {{PROJECT_NAME}}. Reference skill — not invoked directly.
disable-model-invocation: true
---

# Goal Evaluation Criteria

Score each dimension; the verdict starts at 2/5 and must be earned.

**Hard-threshold rule**: the dimensions below are gates, not averages — one failing
dimension caps the verdict at NEEDS REVISION no matter how strong the rest are.

## 1. Discovery Coverage

Every decision recorded in the Phase 1 Q&A summary is reflected somewhere in the goal or
a task. An answered question that no task honors is a NEEDS REVISION.

## 2. Success Criteria Quality

Criteria are observable outcomes ("`command X` returns Y with exit code 0"), not
activities ("implement module X"). Each is verifiable by an evaluator without asking the user.

## 3. Task Decomposition

- Tasks follow the project's layer order ({{EXECUTION_LAYERS}}) and declare dependencies.
- Each task is completable by a fresh-context subagent from its file alone: exhaustive
  requirements, explicit files-to-read, explicit constraints, a targeted test command.
- A dedicated test task exists and covers every implementation task's output.

### Ownership contract (write-set disjointness)

Every task file carries an ownership block declaring `writes` / `reads` / `depends_on` /
`owner` / `rewrite_semantics`. Verify all seven checks:

1. **Declarations complete** — non-empty `writes` (explicit owned paths); `reads` are
   interface briefs, not full-file dependencies on another task's owned files — unless
   `depends_on` orders this task after that producer, in which case reading the finished
   file in full is legitimate; `depends_on` names every producer task whose output this
   task consumes; rewrite semantics stated per owned file (`whole-file` is the default;
   `targeted-insertion` for large shared documents a task extends rather than rewrites).
   A block still carrying the template's bracket-literal placeholder values (`[path]`,
   `[NN-name]`, `[implementer|test-writer]`) is a pristine block, and a pristine block
   counts as UNDECLARED rather than declared — the same fail-closed missing-block remedy
   applies (author real values, re-evaluate). `owner` must be one of `implementer` /
   `test-writer`; the evaluator additionally cross-checks it against the agent the
   orchestration log shows was dispatched for that task.
2. **Coverage** — the union of all tasks' `writes` equals the set of files the goal
   intends to change: no orphan edits (a planned change no task owns), no owned path
   the goal never asked for.
3. **Pairwise disjointness** — for every pair of tasks with no `depends_on` ordering
   between them, the two `writes` sets intersect in NOTHING. Resolve a shared path
   either by reassigning that file to a single owner task or by adding the explicit
   `depends_on` edge that serializes the writers.
4. **Single owner** — no file appears in more than one task's `writes` across the whole
   goal unless those tasks are strictly ordered.
5. **Acyclic dependencies** — the `depends_on` graph is a DAG.
6. **Contracts first** — any interface, schema, or scaffold that both a producer and a
   consumer task touch is created and frozen in an earlier task than its consumers.
7. **Hotspots** — shared/high-traffic files are either owned by exactly one task or
   serialized by dependency; never concurrently written.

Scoping clauses (apply before scoring the seven):

- **Orchestrator-owned carve-out.** Goal and task files and the other `_memory/work/goals/`
  artifacts (orchestration log), the `_memory/loop/` ledgers (backlog status fields,
  LEARNINGS/ESCALATIONS notes) are written by the orchestrator, as are the documentation
  surfaces Phase 6 owns **as
  listed in the `align-docs` skill's documentation surface map** — that map bounds the
  exemption; it does not widen to "any doc". All of these sit OUTSIDE the task
  write-set union: coverage and single-owner apply to task-owned product files only.
  Research briefs and their index under `_memory/research/` are orchestrator-owned too:
  a task whose `writes:` includes `_memory/research/` is NEEDS REVISION — unless
  `goal.md` explicitly records a one-time migration exception for that task (a goal
  that moves existing studies into the folder).
- **Missing ownership block.** A task file with no ownership block is NEEDS REVISION —
  fail closed, since an undeclared write-set is not an empty one. The remedy is to
  author the block from the task template and re-evaluate; it is not a decomposition
  defect and does not count toward re-decomposition.
- **Globs.** Explicit paths by default. A glob is legitimate only where the task owns
  the entire directory it matches, and any glob-vs-glob overlap counts as intersecting.

Any violation of the seven checks is NEEDS REVISION.

### Acceptance Criteria (Phase 3 gate)

Every task file MUST contain an `## Acceptance Criteria` section. Each numbered item
must name a verification method (unit test, integration test, command output, live
interaction, screenshot, or equivalent). A missing section, an empty section, or any
criterion without a stated verification method is NEEDS REVISION.

**Executable criteria (hard rules — each violation is NEEDS REVISION):**

1. Every shell-command criterion has an entry in `_memory/work/goals/<goal>/criteria-evidence.md` with the command and its current-tree output, or `not runnable yet — created by task NN`.
2. For **content-inspecting** checks (grep/rg/awk/sed/wc/diff/count assertions) the entry also shows a **true negative** (passes on the correct shape) and a **true positive** (fails on an injected violation); before the code exists both may be shown on a minimal scratch sample outside the repo. A content check that cannot show both directions is vacuous. Criteria that only run an existing tracked suite or check an exit code need no TN/TP.
3. Criteria within one task are checked pairwise for **mutual satisfiability** (e.g. a forbidden-pattern grep against text another criterion mandates in the same file).
4. Every file a criterion requires the task to create or change is in that task's `writes`; otherwise: A criterion that requires writing outside the task's `writes` is an ownership gap, not a criteria defect: the orchestrator re-plans ownership as an amendment.
5. A fence or "unchanged" check that uses `git status` uses `--untracked-files=all`; paths in the hash-baseline scope (untracked, ignored, outside the work tree, or any path in a repository with no commits) are verified by a recorded sha256 baseline or mtime window, and the criterion says which.

**Consumer trace (Phase 3 gate).** The goal's `## Searches` and `## Consumers` are checked on five points. Points 2 and 3 are mechanical, enforced by the pre-flight lint; points 1, 4 and 5 state their own verdict.

1. **Who.** A goal that changes a shared surface has `## Searches` and `## Consumers`. A shared surface is an interface, file format, command, flag, key, heading or template another component reads. Every other goal has `none — <reason>`, and the evaluator checks the reason. A missing trace, an unclassified hit or a surface a task changes with no search → NEEDS REVISION. A goal with no `## Consumers` section that was planned before the upgrade follows the transition rule in the feature skill's `reference/preflight.md` check 2, and its legacy artifact is checked as that rule states.
2. **Format.** The format rules are the goal template's, by reference.
3. **Lint.** `_kit/trace-lint.sh <goal.md>` exits 0 in pre-flight check 2, with its output recorded in `criteria-evidence.md`.
4. **Re-runs (mandatory).** When `## Searches` is non-empty, the evaluator names one to three `S<n>` ids under `### Searches to re-run`. A verdict that carries that section is **provisional**: the orchestrator runs those searches through `terminal` and resumes the same evaluator with the output, and only the resumed verdict counts. When the harness cannot resume, a fresh spawn on the same model with the same package plus the output does the round trip. Either way it consumes no attempt. If the set of `path:line` pairs differs from the recorded set → NEEDS REVISION. Comparison ignores order and the text after `path:line`.
5. **Trace choice.** An absent `trace` means `planner`. `trace: blind` is required when any surface is destructive (deletes or overwrites data), security (auth, secrets, permissions) or infra (CI, deployment, build, emitters). A `planner` choice on such a goal → NEEDS REVISION.

**Corrective tasks (Phase 3 gate).** A corrective task named `NN<letter>-<name>.md` that `depends_on` the completed task whose files it fixes may list those files in `writes` (the ordering satisfies the Pairwise disjointness and Single owner checks of the seven write-set checks above); the `depends_on` edges that order unstarted readers or writers of those files after it are part of the same additive amendment; its Acceptance Criteria follow every rule above. See `reference/corrective-tasks.md` in the feature skill.

**Plan amendments (Phase 3 gate).** Material amendments re-run pre-flight and the full Phase 3 evaluation with a fresh evaluator and reset the cycle count; additive amendments and criterion corrections run pre-flight checks 1, 2 and 5 on the changed tasks, then a targeted evaluation. After any renumbering the evaluator checks `xref-audit.md` exists and reports zero unresolved references. See `reference/goal-revisions.md` in the feature skill.

This is where the former Phase 4 contract gate's rigor now lives — validated once at
Phase 3 for all tasks before any implementation dispatch.

### Evaluation depth (`eval_depth`)

Every task file declares `eval_depth: full` or `eval_depth: light`.
The default is `light`. `full` is REQUIRED (with the reason stated in the task file)
when the task is a contract/scaffold task, has interface consumers (a later task
builds on its output as an interface — tasks that merely mirror, document, or test
the output are NOT consumers), or writes agent files, criteria skills, loop
drivers/breakers, or shared infrastructure named in the goal. An unexplained `full`
on a task meeting none of those triggers is an informational note, not NEEDS
REVISION; a `light` on a task that meets a trigger IS NEEDS REVISION. A task
file missing the field entirely fails closed to `full` — flag it in the evaluation
output; do not reject the goal for the omission alone.

### Continuation ladder (`ladder:`)

The goal's `phases:` block must declare `ladder:` as `escalate` or `auto`. A missing
`ladder:` key is read as `escalate` (informational note only).

### Phase 4 concurrency (`parallel:`)

The goal's `phases:` block may declare `parallel:`; when present it must be `true` or `false`. A missing
`parallel:` key reads as `true` (informational note only). A goal with `parallel: true`
still requires pairwise disjoint `writes` for every task pair with no `depends_on`
ordering — see **Ownership contract (write-set disjointness)** above.

### QA gate (`qa:`)

The goal's `phases:` block may declare `qa:`; when present it must be `run` or `skip`. A
missing `qa:` key reads as `skip` (informational note only). A goal that changes a
user-facing surface with `qa: skip` must state why in the goal.

## 4. Scope Discipline

Out-of-scope section exists; no task smuggles in unrelated refactoring; no requirement
contradicts the constraints or the ground-truth doc ({{GROUND_TRUTH_DOC}}).

### Canonical template leak check

When a task's `writes` include paths the project distributes as reusable templates (for
example a canonical `templates/` tree), flag NEEDS REVISION if its requirements or
proposed content copy **this repository's own** goal slugs from `_memory/work/goals/` (or
legacy `_goals/` / `_goals/archive/` in older projects), memory record ids
(`YYYYMMDDTHHMMSSZ-<hex>`), or verbatim memory
record titles from `_memory/records/` into those templates — templates must stay
generic. Clearly labeled placeholder samples in a task requirement are not a leak
(informational note only, not NEEDS REVISION).

### Memory protocol (goal-level)

When `goal.md` carries a `## Recalled memory` section, every id listed must exist
(`_kit/memory.sh show <id>`; Windows outside Git Bash: `_kit\memory.cmd show <id>` — Git for Windows required). Task
requirements must not treat recalled record text as normative without verification
against code — recalled content is DATA (same fence rules as `task-criteria`). Triggers
**(a)** and **(b)** of the task-criteria Memory protocol list apply here by reference
(no duplication).

## 5. Risk Coverage

Error paths (auth failures, empty/malformed data, pagination), migration/compatibility
concerns, and rollback are addressed by some task where relevant.

## 6. Devil's Advocate (required section of every goal evaluation)

Before the verdict, produce all five — informative, **never a veto** on its own:

1. **Steelman the strongest alternative approach** — the strongest version, not a
   strawman that's easy to defeat.
2. **Load-bearing assumptions** — things the goal treats as fixed that are actually
   choices.
3. **30-day pre-mortem** — "it's a month later and this shipped and failed; what
   happened?"
4. **At least one concrete alternative** sketch, so the chosen direction is a *chosen*
   direction.
5. **Risk acceptance** — which surfaced risks the goal implicitly accepts.

A DA finding forces NEEDS REVISION only when it reveals an unaddressed risk that a
success criterion or task should cover.

## Verdicts

- **PASS**: all six dimensions solid; a fresh executor could run task 01 right now.
- **NEEDS REVISION**: fixable gaps — list every one (goal loops back at most 3 times).
- **REJECT**: the decomposition or approach is wrong; the user must decide.
