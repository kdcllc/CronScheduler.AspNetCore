# Continuation ladder (cycle-3 exhaustion)

When `goal.md`'s `phases.ladder` is `auto` (loop-created goals set it; interactive
goals default to `escalate`, where the user is offered the ladder as an explicit
option), this ladder applies after **cycle-3 exhaustion** (NEEDS FIXES after three
implement→evaluate cycles without PASS). Under `ladder: auto` the ladder may also start
early, per `reference/fix-cycles.md` § Early ladder entry. **Early arbitration at detection** is the
exception — see below. Apply rungs in order; every ladder fix attempt is
re-evaluated — there is no exception.

## Early `criteria-defect` routing (detection)

`criteria-defect` stops fix cycles at detection on any cycle: with `ladder: auto` run rung 5 arbitration now; with `ladder: escalate` escalate with arbitration offered as option 1.
Early arbitration costs no implementation attempt; criteria-defective, or any arbiter/primary disagreement, escalates to the user, a criterion correction the user approves is a criterion-correction amendment, and a criterion the user upholds resumes the task at its next fix cycle.
The unanimity heuristic does **not** gate this path. Pass the verdict(s) so far into
arbitration. `criteria-defect` routing wins over line-patch-only resume.

## Rung 5 — arbitration (unanimity check)

Arbitration also runs when the **drift trigger** fires: the cycle 2–3 verdicts recorded
in the orchestration log together carry ≥ 2 `[new]` items.
Demoted `[backlog] [late]` notes count toward this total.
The unanimity heuristic and
the drift trigger are alternatives; either one runs rung 5, and the outcomes are unchanged.
For a drift-triggered arbitration, the arbiter gets the same inputs as a unanimity-triggered one. The verdicts
already carry the tags, and `ambiguous` is the defect type the drift most often points to.

If the evaluator verdicts in the orchestration log for
every cycle that ran (three, fewer on early ladder entry) flagged the same
required-fix item (unanimous-failure heuristic — compare items after stripping the
justification clause (from its start (` — missed earlier:` or ` — reverses cycle `)
through the end of the item) when present, otherwise with trailing
`[line-patch]` / `[structural]` tags stripped and trailing provenance tags (`[carried]` /
`[regression]` / `[new]`) stripped — tags stripped so a tag change across cycles does not
make the same item count as different), spawn `evaluator` in
**arbitration mode** on `claude-opus-5-5` with the task file
(including its Acceptance Criteria), and the verdicts and implementer reports of
every cycle that ran (three, fewer on early ladder entry). Outcomes:
`criteria-defective` → escalate to the user carrying the named defective criterion
**verbatim**; arbiter/primary disagreement → escalate (never auto-resolve);
`criteria-sound` → continue to rung 4.

## Rung 4 — diagnosis-first

Spawn `diagnostician` with the task file (including its Acceptance Criteria), the
implementer reports and evaluator verdicts of
every cycle that ran (three, fewer on early ladder entry), and the targeted
verification command. If its
**Signature Declaration** matches a previously tried fix signature → skip to rung 6
if it recommended a split, else escalate. Otherwise run **ONE** diagnosis-driven
implementation attempt: fresh `implementer` on `claude-opus-5-5` using the
diagnostician's **Rewritten Required-Fixes** list; then mandatory re-evaluation.

## Rung 6 — decomposition + selective retry

Only on a diagnostician split recommendation. Derive subtask files with ownership
contracts whose write sets are subsets of the parent task's, from the **failing
pieces only** — unflagged work from earlier cycles stays as-is, is not re-run, and
gets no separate evaluation. Each derived subtask gets one implement→evaluate
cycle; the parent task completes when every derived subtask has an evaluator PASS;
evaluator spawns never consume the attempt budget — only implementation attempts do.

## Terminal escalation

Escalate to the user with the full ladder history.

## Hard guards

Character-consistent with `.claude/ORCHESTRATION.md`:

- At most **3 additional implementation attempts** after the last fix cycle (cycle 3, or earlier on early entry),
  summed across rungs 4 and 6.
- The diagnosis-driven implementation attempt costs 1 of the 3. Each rung-6 subtask
  implement→evaluate cycle costs 1 of the 3. Before splitting, compare the
  failing-subtask count against the remaining budget — if the count exceeds the
  remaining budget, escalate instead of splitting.
- A **repeated failure signature** stops the ladder immediately: the evaluator's
  required-fixes list as recorded in the orchestration log, identical to an earlier
  cycle's list item-for-item after normalizing whitespace and list numbering and
  stripping trailing `[line-patch]` / `[structural]` tags and trailing provenance tags
  (`[carried]` / `[regression]` / `[new]`) from each item and the justification clause
  (from its start (` — missed earlier:` or ` — reverses cycle `) through the end of the
  item) from each item when present (signature identity ignores those kind and provenance
  tags). Issue keys are logged per the task-criteria skill's `### Issue key` rule, and the
  signature rule above is unchanged.
- Every rung transition, spawn, and guard trip is an orchestration-log entry recording
  the rung name.

Token/cost budgets are not a guard in interactive mode (no harness exposes true usage to the
orchestrator); the headless loop records real usage per iteration via
`LOOP_USAGE_FORMAT` — the bash loop driver's opt-in `LOOP_*_BUDGET_*` knobs gate on it at loop level, not in this ladder.
