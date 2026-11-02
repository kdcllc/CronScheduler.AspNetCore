# Fix cycles (Phase 4 step 4)

Read this before acting on **NEEDS FIXES**, **REJECT**, a verdict tagged `destructive`/`security`/`infra`, `failure_class: criteria-defect`, or Phase 4 cycle-3 exhaustion.

Also read it before every Phase 4 task evaluation and Phase 5 audit, the first ones included: the tree snapshot (§ Provenance) and the citation check, backlog append and keys call (§ Citation checks, backlog and keys) apply to every evaluation.

## Cycle cap

- Max 3 evaluation cycles per phase/task; on Phase 4 cycle-3 exhaustion, read
  `phases.ladder` (`escalate` default or key absent → escalate with "Run the
  continuation ladder" as option 1; `auto` → continuation ladder). Other phases escalate.

## Executor resume

Implementer MAY be resumed for fix cycle 1; cycles 2–3 fresh spawns
(rotation applies) except line-patch-only (Phase 4 step 4).

## Line-patch-only

**Line-patch-only** (all `[line-patch]`): resume same executor (`implementer`/`test-writer`) apply-verbatim any cycle (fresh spawn on same model if harness can't resume), no rotation, counts toward 3, re-evaluated; any `[structural]` → normal fix with patches verbatim. `NOT APPLIED` → re-evaluate; next cycle normal.

## Criteria-defect and bypass

**`criteria-defect`** (not bypass): route at detection per `reference/continuation-ladder.md`. **Bypass at detection (every verdict, cycles 1–3).** Verdicts tagged `destructive`,
`security`, or `infra` stop all cycles immediately and escalate — from cycle 1.

## Provenance

The tree snapshot below applies to every evaluator spawn in Phases 4 and 5, first
evaluations included; the provenance tags apply to re-evaluations and re-audits (Phase 4
task re-evaluations and Phase 5 final-audit re-audits). Neither applies to Phase 3 goal
re-checks.

Every re-evaluation and re-audit context package must include every earlier required-fixes list verbatim for that task or audit, labeled by cycle and copied from
the earlier `spawns/NN-report.md`, whether the evaluator is resumed or freshly spawned.

Before routing on a re-evaluation verdict not tagged `destructive`, `security`, or `infra`
(those escalate at detection first), check provenance tags. If any required-fix item lacks
a provenance tag, or any `[new]` item has neither `missed earlier:` nor
`reverses cycle N:`, or any `[new]` or reversal item's justification text is not a
**justification clause** placed **directly before the kind tag** (misplaced or differently punctuated
text fails the check), resume the same evaluator once to complete the tags; when the
harness cannot resume, fresh-spawn the same model with the verdict attached. That round
trip **consumes no cycle**. If tags are still missing, treat the item as `[new]` and log
a note saying so. If a justification clause is still misplaced after the round trip, log
a note saying so.

Phase 5 re-audit packages also list `.claude/skills/task-criteria/SKILL.md` (its
Provenance tags section) alongside the earlier required-fixes lists so the auditor has
the tag rules without relying on the evaluator.md pointer alone.

**Tree snapshot.** At every evaluator spawn in Phases 4 and 5, the orchestrator records a
working-tree snapshot with the temp-index technique of the align-docs skill's Phase 6 tree
snapshot, so the next re-evaluation has a baseline. `<temp>` is a fresh index path inside a
new `mktemp -d` directory, and every command carries it:
`GIT_INDEX_FILE=<temp> git read-tree HEAD && GIT_INDEX_FILE=<temp> git add -A && GIT_INDEX_FILE=<temp> git write-tree`
Then remove the temp index file and log
`_kit/log-spawn.sh note --goal <g> --text "eval-tree [#NN] task <TT|audit>: <sha>"`.
The real index is never touched, and unstaged and untracked edits are captured. The
orchestrator (or `terminal`) runs these commands; the evaluator stays read-only.

**Changed since last evaluation.** Every re-evaluation package (Phase 4 fix cycles after the
first, ladder re-evaluations, Phase 5 re-audits) carries a `## Changed since last evaluation`
section: `git diff --name-only <previous sha> <current sha>`, using the two latest
`eval-tree` shas for the same `<TT|audit>`, limited to the task's write fence (Phase 5: the
union of the goal's fences), or `none`.

From the first re-evaluation onward, log one note per `[new]` item:
`_kit/log-spawn.sh note --goal <g> --text "late finding: <phase> <task-or-audit> cycle N — <item>"`.
Late findings get **no extra cycle**.

A verdict item quoting `reverses cycle N: <verbatim earlier item>` is a reversal. **N**
is the number of the earlier verdict being reversed, counting that task's evaluations from
1 (the first verdict); ladder re-evaluations continue the count, and Phase 5 counts audits
the same way (first audit = 1). In Phase 4, classify the verdict `criteria-defect` and
follow **## Criteria-defect and bypass** (at-detection route). In Phase 5 there is no
ladder — escalate to the user at detection, quoting both items verbatim.

## Citation checks, backlog and keys (every evaluation)

These rules cover every Phase 4 task evaluation, ladder re-evaluation and Phase 5 audit,
first ones included, unless a rule says otherwise. Citations, the required-fix line and the
issue key are defined in `.claude/skills/task-criteria/SKILL.md` (Floor, Citations,
Issue key and Provenance tags sections).

**Orchestrator checks.** The tag-check round trip (§ Provenance) gains two checks. Both are
skipped for verdicts tagged `destructive`, `security`, or `infra`, like the tag check.

- **Citation check** (every Phase 4 task evaluation and Phase 5 audit, the first ones
  included). Each blocking item must cite an `AC<n>` within the task's criteria count (audits:
  `<TT>/AC<n>` within task TT's count), an existing `SC` label in `goal.md`, or one of
  `F1`–`F7`.
- **Late-finding scope check** (re-evaluations only). Each `[new]` item must satisfy a
  blocking condition of the late-finding rule in task-criteria's Provenance tags section, or
  be demoted to a `[backlog] [late]` note.
- A violation of either check asks the evaluator to correct the verdict, through the same
  round trip as the tag check.

**Backlog.** The orchestrator appends every `[backlog]` note (including `[backlog] [late]`)
from each verdict to `_memory/work/goals/<goal>/follow-ups.md`.
Rows use the form `- B<n> (<source>): <finding> — <status>`, where the source is a spawn
`#NN`, a phase, or a quality-check class and the status is `open`, `fixed`, or `wontfix`.
Only the orchestrator writes the file. `fixed` needs evaluator evidence or the user's word.

**Keys.** The keys call runs once per Phase 4 task evaluation, ladder re-evaluation and
Phase 5 audit, after the round trip settles:
`_kit/log-spawn.sh keys --goal <g> --spawn <NN> --task <TT|audit> --report <report>`
Run it inline (one-line output, the same exception as other `_kit/log-spawn.sh` calls).

- `--spawn` is the evaluation's first evaluator spawn number, and `--report` is the settled
  report: the corrected report when a round trip ran, otherwise the original.
- A round-trip respawn's own `OUTCOME` gets no `keys` call, so a correction is never
  compared against its own uncorrected verdict.
- `<TT>` is the task id prefix (`[0-9]{2}[a-z]?`), corrective tasks and rung-6 subtasks
  included (for example `09a`); Phase 5 uses `audit`.
- The call appends one `KEYS` line, and one `REPEAT` line for each key also present in the
  same `--task` value's previous `KEYS` line. A second call for the same spawn number is
  refused as a ledger-integrity error (exit 3).
- Keys never change a verdict. Only `ladder: auto` early entry routes on them (§ Early
  ladder entry).

## On cycle-3 exhaustion

**On cycle-3 exhaustion**, read `goal.md`'s `phases.ladder`: `escalate` (default, or
key absent) → escalate with "Run the continuation ladder" as option 1 (log "ladder:
escalate per goal.md"); the escalation's **Ladder** line reports the **drift** count (the
number of `[new]` items across the cycle 2–3 verdicts).
Demoted `[backlog] [late]` notes count toward this total.
When the count is ≥ 2 the
**Ladder** line adds that **rung 5 runs first** because the drift trigger fired;
`auto` → Read `reference/continuation-ladder.md` and follow
it. Every ladder fix attempt is re-evaluated. Cycle-3 exhaustion is not the only way the
ladder starts: under `ladder: auto`, § Early ladder entry starts it earlier.

## Early ladder entry

Under `ladder: auto`, a repeated `[structural]` issue key ends a Phase 4 task's fix cycles
early. The keys call (§ Citation checks, backlog and keys) logs a `REPEAT` line for each
key that was also in the same task's previous `KEYS` line; read it after each Phase 4 task
evaluation.

- Under `ladder: escalate` (default, or key absent), no decision reads `KEYS` or `REPEAT`;
  keys are log-only.
- Under `ladder: auto`, a `[structural]` `REPEAT` ends fix cycles before cycle 3, and the
  orchestrator proceeds exactly as on cycle-3 exhaustion: bypass check, then rung 5 when its
  triggers fire, then rung 4, then rung 6. Rung 5's unanimity and rung 4's diagnosis read
  every cycle that ran.
- `[line-patch]` repeats never trigger it, Phase 5 never does (it has no ladder), and a
  `REPEAT` during a ladder re-evaluation (rungs 4–6) never does, because the ladder is
  already running.
- Unused fix cycles are not carried over, and the ladder's budget and guards are
  unchanged, so a task never gets more attempts than on cycle-3 exhaustion.
- Log it: `_kit/log-spawn.sh note --goal <g> --text "early ladder entry: <key>"`.

## Fix-cycle model rotation

**Fix-cycle model rotation**: cycle 1 normal; cycle 2 **different family** at comparable tier; cycle 3
**frontier** (model map). Log each rotation (skipped on line-patch-only).
