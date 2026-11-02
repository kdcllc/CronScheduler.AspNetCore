# Degraded mode (spawn limitations)

When the harness cannot honor a spawn as the feature skill expects, the orchestrator
follows the rules below instead of abandoning the goal or substituting a different agent
type. Read this reference during Phases 3–7 whenever a spawn fails for a reason other
than a normal evaluator verdict, or when the session has no spawn tool at all. It extends the feature skill's iron rules and
orchestration log; it does not replace repository safety or the 3-retry rule for
**transient** launch failures.

## Scope

Degraded mode applies **only** in the two cases documented below.

- **Transient** subagent-launch failures (timeouts, rate limits, temporary unavailability)
  keep the feature skill's **3-retry rule** with exponential backoff (2s, 4s, 8s). They
  **never** trigger degraded mode and **never** substitute a different agent type.
- Degraded mode **never** substitutes a different agent type for the one you intended
  to spawn.

All other spawn failures after retries are escalated unless they match Case 1, Case 2, or the concurrency fallback in `reference/ready-groups.md` § Harness fallback.

## Case 1 — model argument rejected

When a spawn fails because the **`model` argument is rejected or not allowed** (policy,
capability, or harness restriction — **not** a transient error):

1. Log exactly one `_kit/log-spawn.sh note --goal <goal> --text "..."` naming the
   agent type and the rejected model id (Win: `_kit\log-spawn.cmd`).
2. Close the rejected spawn: save the rejection error as its `spawns/NN-report.md` and
   log `outcome` with `--verdict "spawn rejected: model argument" --model-reported "not launched"`.
   Copy the package to the **next free** `spawns/NN-context.md` with its `## Model` line set
   to `requested: inherit`, and log a new `spawn` with `--model-requested inherit`
   (append-only — never reuse the rejected spawn's NN).
3. After those ledger entries, re-spawn the **same agent type** with the **same context
   package** and **no** `model` argument (harness default / **`inherit`**).
4. Continue the phase normally once the re-spawn succeeds.

### Persistence for the rest of the goal

After the **first** model-argument rejection in a goal, **every later spawn** in that
goal omits `model`, sets its context package's `## Model` line to `requested: inherit`, and logs `--model-requested inherit` — do **not** retry pinned models
on each spawn. Log the persistence decision **once** (in the same note as step 1 or a
follow-up note immediately after).

**Fix-cycle model rotation** cannot apply while spawns run without `model`. Log rotation
as **skipped** with one `note` per skipped rotation (e.g. `Rotation skipped (degraded mode): <task id> cycle N`).

Case 1 does **not** by itself put the orchestrator in Case 2; subagents still run when
the harness can spawn them.

## Case 2 — no spawn tool

When the harness exposes **no way to spawn subagents** (no subagent-spawn tool in the
orchestrator session), the orchestrator **performs each role itself**, reading the same
`.claude/agents/<role>.md` file and criteria skill it would have sent in the context
package. Treat the session as degraded for the **rest of the goal** unless **Exit**
(below) applies.

### Iron-rule exceptions (Case 2 only)

These apply **only** while Case 2 is active:

| Normal rule | Degraded behavior |
|-------------|-------------------|
| **You never write or edit product code yourself** | The orchestrator may implement and test **only** inside each task's **write fence**, one task at a time, acting as `implementer` or `test-writer`. Log one `note` per task: `Degraded implementer: <task id>` or `Degraded test-writer: <task id>`. |
| **Terminal spawn rule** | Bash or PowerShell runs **inline** in the orchestrator session (including rung 3 / the full test command). Save long output to a file under the goal folder; **Read** only the slice needed for the verdict — never paste the full stream into chat. |

Re-evaluation after fixes and the **max 3 evaluation cycles** per phase/task still apply.
Every fix-cycle attempt and every re-evaluation is its own ledger entry — a new
`spawns/NN-context.md`, `spawn`, report, and `outcome`; never reuse an NN.
**Never self-perform** verdict roles when a spawn tool exists (see below).

### Worker roles (implementer, test-writer, terminal, evidence-collector)

**`evidence-collector`** under Case 2: the orchestrator runs the smoke commands and writes
`_memory/work/goals/<goal>/qa/index.md` itself (logged as a degraded step); record
visual QA as `visual QA not run (no browser tool)` or `visual QA not run (skipped: <reason>)` — never fabricate screenshots.

For each task (or terminal batch — see **Inline terminal logging**):

1. Write `spawns/NN-context.md` with the same structure as a normal context package
   (you are performing the role named in the package).
2. **Before** doing the work:
   `_kit/log-spawn.sh spawn --goal <goal> --agent <role> --phase "…" --model-requested self --context <that file> …`
3. Perform the work (respect the task **write fence** for implementer/test-writer).
4. Write the verbatim report to `spawns/NN-report.md`.
5. `_kit/log-spawn.sh outcome --goal <goal> --spawn NN --report <that file> --verdict "…" --model-reported self --note "self-performed (degraded mode)"`
   (`model_check: unverified` is expected.)

### Verdict roles (evaluator, qa-evaluator, diagnostician)

Same ledger shape as workers, but outcomes use:

`--model-reported self --note "self-evaluation, not independent"`

While performing a verdict role:

- Run **every** acceptance-criterion verification command yourself.
- Keep **verbatim** command output with the verdict (same evidence discipline as a
  read-only evaluator using `terminal` evidence).
- Do **not** treat your own PASS as sufficient to advance silently — see **Gate rule**.

### Ready groups under Case 2

Run **one task at a time** (ready groups of one). Do not launch concurrent member
executors. Fix-cycle **rotation** is skipped — log each skip. Group repository checks
collapse to the single-task post-spawn check in `.claude/ORCHESTRATION.md` §
Repository safety.

### Inline terminal logging

Case 2 runs commands inline, but the ledger still records terminal work **once per
phase**, not once per command:

- One `spawn` / `outcome` pair for agent `terminal` per phase (e.g. Phase 4 task batch,
  Phase 5 Quality Checks, Phase 3 preflight long commands if any).
- Write the context package and log `spawn` before the phase's first command; it lists the
  commands **planned** for the phase (acceptance-criterion commands, rung 3). The report,
  written when the phase ends, lists **every command actually run** with exit codes and
  points at any saved log files; log `outcome` then. Never edit the context after its `spawn` line.
- Use `--model-requested self` on spawn and `--model-reported self --note "self-performed (degraded mode)"` on outcome.

## Gate rule (self-evaluated PASS / APPROVED)

When **you** performed the evaluator (or qa-evaluator / diagnostician) under Case 2, a
**PASS**, **PASS (with notes)**, or **APPROVED** verdict may advance the workflow **only
after** you **tell the user** that the gate was **self-evaluated** and was not reviewed
by an independent subagent.

Collect every self-evaluated gate in:

1. The **final report** (end-of-goal summary to the user) — a dedicated list of phases/tasks
   and verdicts that were self-evaluated.
2. The Phase 7 **PR draft** — a **"Self-evaluated gates"** section with the same list
   before the user approves the PR.

Do not skip user-visible disclosure on interactive runs. On unattended runs, the PR draft and final report
disclosures satisfy the checkpoint (see **Unattended runs**); when Phase 7 is skipped, the final report alone carries the list.

## Never self-perform when spawning works

If a spawn tool **exists** and accepts spawns:

- **Verdict roles** (`evaluator`, `qa-evaluator`, `diagnostician`) are **never**
  self-performed. Spawn them normally.
- Spawn failures use the **transient** retry rule or **Case 1** (model argument), not
  Case 2.

Case 2 applies only when there is genuinely **no** spawn path for subagents in the current
session.

## Exit — spawn tool returns mid-goal

If a spawn tool becomes available **mid-goal**, return to **normal spawning** for all
**remaining** work. Already completed self-evaluated gates stay **disclosed** in the
final report and PR draft; do not re-run them unless a fix cycle requires re-evaluation
under normal rules.

## Unattended runs

When no user is present (cloud agent, headless loop, or equivalent), human checkpoints
are limited to what the workflow can produce asynchronously:

- The Phase 7 **PR draft** (including **Self-evaluated gates** when Case 2 applied).
- The **final report** — the orchestrator's **end-of-goal summary to the user** (success,
  escalations, PR link or hand-over, and every self-evaluated gate).

Those artifacts are the **only** human checkpoint in unattended mode; do not assume
mid-goal chat approval.

## Logging summary

| Event | Ledger action |
|-------|----------------|
| Case 1 first rejection | One `note` (agent + rejected model); close the rejected spawn with `outcome`, then new `NN-context.md` + `spawn` with `--model-requested inherit`, then re-spawn |
| Case 1 persistence | One `note`; all later spawns omit `model` |
| Skipped rotation (Case 1 or 2) | One `note` per skipped rotation |
| Case 2 per role | `NN-context.md` → `spawn … --model-requested self` → work → `NN-report.md` → `outcome … --model-reported self` with the appropriate `--note` |
| Case 2 terminal batch | One `terminal` spawn/outcome pair **per phase** listing commands |
| Self-evaluated gate passed | User told (interactive) or PR draft + final report (unattended) |

Append-only rules in the feature skill's orchestration log section still apply; degraded
entries are normal spawn/outcome/note/keys lines, not placeholders.
