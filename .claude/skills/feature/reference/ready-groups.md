# Ready groups (Phase 4 concurrent execution)

Phase 4 uses **ready groups** by default: the orchestrator may run up to **3**
write-disjoint tasks concurrently within a single group, then evaluate and fix them
under the rules below. `parallel: false` in `goal.md` restores running one task at a
time in dependency order. Read this reference
when planning or executing Phase 4 — it extends the sequential steps in the feature
skill; it does not replace repository safety or the orchestration log.

Loop slots and ready groups are independent: a slot runs one story; ready groups run
inside that story's Phase 4.

## Definition

A **ready group** is a set of one to three tasks that may run together because:

1. Every task in the set has **PASS** on all entries in its `depends_on` list (goal
   evaluation must already be **PASS** before Phase 4 starts).
2. The tasks' `writes` sets are **pairwise disjoint** under the overlap rule in
   `templates/task.md`: explicit paths only by default; two globs that overlap count
   as intersecting, same as two identical paths.

The orchestrator forms groups by scanning tasks in **dependency/file order** (the same
order Phase 4 would use sequentially). For each not-yet-started task whose dependencies
have PASSed, add it to the current group if its `writes` do not overlap any task already
in that group; otherwise close the group and start a new one. A group never exceeds
three tasks — when a fourth would join, close the group and start the next.

Tasks whose rung 1–2 verification commands write **shared** unfenced state (build
outputs, caches, test databases, fixed ports, a generated or gitignored instance,
regenerated fixtures) must not share a group with anything else; run them alone even
when their `writes` fences are disjoint on tracked paths. A goal's designated closer
task (the `test-ladder` rung-3 carve-out) also runs alone, after every other task has
PASSed.

## Default and opt-out

Ready groups are **on by default**. In `goal.md`'s `phases:` block, `parallel: false`
forces groups of one — the same sequential behavior as before ready groups existed. A
missing `parallel:` key reads as **`true`** (groups allowed). A harness that cannot
launch concurrent spawns also behaves as groups of one (see **Harness fallback**).

## Launch

Before any member executor runs:

1. Write every member's context package to
   `_memory/work/goals/[goal]/spawns/NN-context.md`, assigning **NN in task order**
   within the group (lowest task index first).
2. Run `_kit/log-spawn.sh spawn` for **each** member (Win: `_kit\log-spawn.cmd`) with
   that context file — same fields as the feature skill's orchestration log section.
3. Launch all member executors at once: one message with several spawns where the
   harness supports it; otherwise launch back-to-back without waiting for completion
   between starts until the harness requires serialization.

Each member gets a full context package and its task's **write fence** only.

## Silent-success check

After **every member** returns, run the same **silent-success check** as sequential
Phase 4 step 2: empty or missing report ⇒ verify artifacts in that member's fence;
present ⇒ treat as done ("report lost, files verified"); absent ⇒ failed, respawn once.
Never re-run implementation when artifacts already exist.

## Group repository check

Members share one checkout; `git status` sees tracked and untracked paths, but content changes it cannot show (untracked, ignored, outside the work tree, or any path in a repository with no commits) use the hash baseline below. After **all members** of
the group return (and silent-success checks finish), run **one** repository check for
the whole group instead of per-member checks between parallel work.

**Baseline (before the group):** record `HEAD`, the current branch, and `git config
--local` user entries. Snapshot the working tree with
`git status --porcelain --untracked-files=all`. In a repository with no commits record `no HEAD`; for the paths git cannot show (listed above), also record the sha256/mtime baseline (scope and method as in `.claude/ORCHESTRATION.md` § Repository safety).

**After the group:** compare `HEAD`, branch, and local git user entries to the baseline.
Compare the working tree to the snapshot (and the hash baseline). For every path that is new or changed since
the snapshot, map it to **exactly one** member's `writes` fence. Cross-check each
member's report: a path that appears in one member's fence but another member's report
claims, or that the owning member's report omits, counts as attributable to two
members — except a member accepted by the silent-success check as "report lost, files
verified", whose paths are matched by fence alone (log one `note`). A new path outside every member's fence, or any path attributable to two
members, **stops the goal**: log it, restore from git or backup, fix the cause (same
as `.claude/ORCHESTRATION.md` § Repository safety), then replan or retry — do not
advance Phase 4.

## Shared side effects

No orchestrator write to shared state (e.g. regenerating an instance) runs while any
member is in flight; ledger writes under the goal folder are exempt. Do not refresh
gitignored instances, regenerate shared fixtures, or run other orchestrator-side
writers while executors or fix-cycle writers in this group are still running.

## Evaluation

When every member has passed silent-success and the group repository check, evaluate
each member's work (task evaluator with task file, report, matching rule files, and task-criteria skill).

- Evaluators for members of the same group may run **in parallel** only when the
  evaluator is **read-only** (emitted `readonly`, or the harness refuses its shell)
  **and** no writer (executor, fix cycle, instance refresh) is **in flight**.
- Otherwise run evaluators **one at a time**.

**Evaluator-in-flight rule:** while any evaluator runs, nothing it was told to read or
diff is modified — no executor, fix cycle, orchestrator refresh, or other writer may
change those paths until that evaluator returns.

Log each evaluator spawn and outcome per the usual orchestration log rules.

## Fix cycles

Each member keeps its own fix-cycle accounting: three implement→evaluate cycles, model
rotation, line-patch-only rules, bypass-class escalation, and continuation ladder
eligibility — same as sequential Phase 4 for a single task.

Several members that **NEEDS FIXES** may run fix cycles **in parallel** when their
`writes` fences remain pairwise disjoint. After those fix cycles return, run the same
**group repository check** again before any new evaluation.

A fix cycle (a writer) starts **only after every in-flight evaluator** of the group has
returned. Do not launch fix-cycle implementers while an evaluator for any group member
is still running.

A member that receives **REJECT** or is escalated for any reason (bypass class, cycle-3 exhaustion under `ladder: escalate`, or a continuation-ladder escalation) pauses the goal after
in-flight spawns return; do not start the next group until the user resolves the
escalation.

## Group completion

The next ready group starts only when **every member** of the current group has reached
**PASS** or **PASS (with notes)** on task evaluation (notes via `--note` as usual).
Partial pass within a group is not enough to advance.

## Harness fallback

This file is the complete rule for every harness; there is no per-harness capability
table to consult. On every harness, **try** parallel group launch first.

If a spawn fails with a **concurrency-related** error (not a transient launch failure —
those keep the feature skill's 3-retry rule with backoff), **fall back** to sequential
execution (groups of one) for the **rest of the goal**. Log exactly one
`_kit/log-spawn.sh note --goal [goal] --text "..."` describing the fallback. Do not
retry parallel launch for later groups in the same goal once fallback triggers.

## Logging

- At each group start: one `_kit/log-spawn.sh note` with text `Group N: <task ids>`
  (N = 1-based group index within Phase 4, task ids = each member's task file prefix
  in run order).
- One `note` per harness fallback (see above).
- Per-spawn `spawn` / `outcome` entries as in sequential Phase 4 — one line per member
  executor and per evaluator, including model requested vs reported.
