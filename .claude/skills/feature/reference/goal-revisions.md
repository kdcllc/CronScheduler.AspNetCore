# Goal revisions and plan amendments

## Phase 3 re-checks

After **NEEDS REVISION**, revise flagged items and re-evaluate (max 3 attempts).

**Attempts 1→2:** Resume the same `evaluator` with a delta that quotes **verbatim** every
passage newly written or changed in the revision (label each *newly written — review
adversarially*), not only a list of fixes. The evaluator reviews those quoted passages first.

**Attempt 3:** Fresh `evaluator` spawn pinned to `claude-opus-5-5`, full goal
evaluation (not a delta). Attach as a review-first appendix the attempt-2 quoted passages plus every passage newly written or changed since attempt 2, quoted verbatim.
Log the rotation; when the pin equals the frontier ID or the spawn uses `inherit`, log
same-family / `unverified` per the model map. New attempt-3 findings with no attempt left
→ escalate. The 3-attempt cap is unchanged.

## Plan amendments after Phase 3 PASS

Definitions:

- **material** — changes Success Criteria or a Phase 1 decision, renumbers tasks, or
  changes an existing task's `writes`/`reads`/Acceptance Criteria (other than a criterion
  correction).
- **additive** — adds tasks without renumbering (including corrective tasks and the
  `depends_on` edges that order unstarted readers or writers after them), or clarifies without
  changing a requirement.
- **criterion correction** — a single criterion fixed after a `criteria-defect` verdict,
  approved by the user.

Material amendments re-run pre-flight and the full Phase 3 evaluation with a fresh evaluator and reset the cycle count; additive amendments and criterion corrections run pre-flight checks 1, 2 and 5 on the changed tasks, then a targeted evaluation.

When unsure, treat as **material**. A Phase 1 decision change goes to the user first.
Log a `note` with the class and rationale. Targeted evaluations are capped at 3 cycles,
like Phase 3.

A surface the Phase 5 audit finds changed but not listed in `## Consumers` is an amendment: add the search, its hits and the row with evidence, re-run `_kit/trace-lint.sh`, then a targeted evaluation. It is additive; when a missed consumer needs an edit, it is a corrective task (`reference/corrective-tasks.md`).

## Cross-reference audit (after any renumbering)

Mandatory before re-evaluation. Write results to `_memory/work/goals/<goal>/xref-audit.md`
(zero unresolved references).

1. List task ids: `ls _memory/work/goals/<goal>/[0-9]*.md`
2. Extract referenced ids from `goal.md` and task files:
   `rg -o '\b[0-9]{2}[a-z]?-[a-z][a-z0-9-]*' _memory/work/goals/<goal>/goal.md _memory/work/goals/<goal>/[0-9]*.md`
   (a letter must follow the hyphen so dates like `10-20` do not match).
3. Confirm each id exists as a task file. Hits that are artifact names under `spawns/` or
   `evidence/` are listed as non-task and resolved.
4. Confirm every `reads`/`writes` path exists or is created by some task's `writes`.
5. Confirm every `changes` row in `goal.md` `## Consumers` names a task that still exists after the renumbering.

Report a TN/TP demonstration of the regex on a scratch sample (id list with a date
fragment and a bad id) when auditing.
