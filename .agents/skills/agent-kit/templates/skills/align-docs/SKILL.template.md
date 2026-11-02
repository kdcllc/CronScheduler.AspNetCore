---
name: align-docs
description: Align all repository documentation to shipped code after a feature is implemented — Phase 6 of the {{PROJECT_NAME}} orchestration lifecycle. Updates every markdown surface (READMEs, docs/, agent/skill files) EXCEPT _memory/ (orchestrator-managed scratch, loop ledgers, records, quarantine, kit README — read-only for docs work). Runs after the final audit and Quality Checks pass, or when the user asks to sync documentation with recent changes.
disable-model-invocation: true
---

# Align Docs (Phase 6)

Bring repository **documentation** back in sync with shipped **code** after a feature
lands. Same evaluator-gated subagent workflow as the `feature` skill (discover → plan →
evaluate → execute-per-doc → final audit), but the deliverable is **accurate Markdown,
never code**.

## Core guardrails (NON-NEGOTIABLE — repeat in every subagent context package)

1. **HARD EXCLUSION — `_memory/`.** Never create, edit, or delete anything under this
   tree. You **may READ** `_memory/work/goals/` and `_memory/work/research/` (and other
   `_memory/` files as needed) as source-of-truth for what shipped; you must **never
   WRITE** to `_memory/`.
2. **DOCS-ONLY.** Never modify code, infra, tests, or config. If a doc claims behavior
   that does not exist, **fix the doc** — never change code to match the doc.
3. **ANTI-INVENTION.** Every documented claim must trace to a file you actually read
   this run. If a detail is unconfirmed, **omit it** — do not guess routes, flags,
   names, or behavior.
4. **SCOPE DISCIPLINE.** Update only **stale or missing** content. Preserve
   already-accurate prose **verbatim**. Prefer surgical edits over rewrites; a
   justified no-op for an already-correct doc is a valid outcome.
5. **HISTORICAL LOGS.** Research scratch under `_memory/work/research/` is read-only
   source material; promote only implemented ground truth into {{GROUND_TRUTH_DOC}}.
<!-- BOOTSTRAP[rendered-siblings]: if this project keeps rendered siblings of any markdown doc (e.g. a
     hand-styled .html mirror), add a guardrail here naming the exact pair(s) and
     requiring surgical same-edit syncing — never wholesale regeneration. Otherwise
     delete this comment. -->

## Documentation surface map

In scope: **everything markdown EXCEPT `_memory/`** — READMEs, docs
under `docs/`, per-directory instruction files, and `{{IDE_DIR}}/`
skill/agent files.

<!-- BOOTSTRAP[doc-buckets]: list this project's actual doc buckets and the code-area → doc mapping
     (e.g. "API routes → docs/api.md + README endpoints table"), so Phase 2 can map
     shipped changes to affected docs without guessing. -->

## Subagents

Uses the standard kit subagents: `evaluator` (plan evaluation, per-doc evaluation, final
audit) and `implementer` (per-doc editing). Standard retry rules apply (same subagent,
3 attempts, backoff — never substitute).

## Workflow

### Phase 6.0: Preconditions
Identify the shipped feature (explicit goal name, or the newest completed
`_memory/work/goals/<goal>/goal.md`). The implementation may be committed, staged,
unstaged, or untracked — installs commonly leave changes in the working tree for a
human to commit — so the change set always runs from the merge base to the **working
tree**, never a committed-only range.

From the repository root (`git ls-files` prints cwd-relative paths), run:

```bash
BASE_SHA=$(git merge-base <base> HEAD)   # <base>: branch the work diverged from; on the default branch, the commit HEAD was at when the goal started (plain HEAD when nothing was committed during the goal; if that commit is unknown, ask the user)
git diff --stat "$BASE_SHA"              # overview: committed + staged + unstaged
git diff --name-only --no-renames "$BASE_SHA"   # machine-readable tracked paths (a rename lists as old path + new path)
git ls-files --others --exclude-standard        # untracked files
```

Build the ownership filter and the shipped-facts input list from the `--name-only
--no-renames` listing plus the untracked listing — never from `--stat` output.

**Ownership filter (goal-driven runs):** a path is *goal-owned* when it is inside some
task's `writes:` set. Paths that are not goal-owned — tracked changes and untracked
files alike — are listed as "changed, not owned by this goal" in the Phase 6.1 output and
are **excluded** from the shipped-facts list; they are never treated as shipped and never
edited.

**No ownership data** (standalone run — the user asks to sync documentation with recent
changes — or a goal whose task files have no `writes:` sets): treat every listed path
as a *candidate*, list them as such, and confirm the scope with the user before Phase
6.1 continues (non-interactive runs escalate instead).

Confirm the implementation landed: the in-scope paths (goal-owned, or user-confirmed
candidates) contain the goal's code changes. If none do, stop and say so.

**Snapshot (baseline).** Before any doc edit, snapshot the working tree as a git tree
object using a temporary index:

```bash
PHASE6_INDEX="$(mktemp -d)/index"
PHASE6_TREE=$(GIT_INDEX_FILE="$PHASE6_INDEX" git read-tree HEAD && GIT_INDEX_FILE="$PHASE6_INDEX" git add -A && GIT_INDEX_FILE="$PHASE6_INDEX" git write-tree)
```

The real index is untouched; the snapshot only adds objects under `.git/`. Record
`BASE_SHA` and `PHASE6_TREE` in orchestrator state or a temp file outside the repository
(shell variables may not persist between calls) — never under `_memory/`.
Gitignored paths are outside the snapshot only when they are **untracked**
(the snapshot is seeded with `HEAD`, so tracked files that match `.gitignore` are
captured; same blind spot as `git status` for untracked ignored paths — accepted).

**Delta since the snapshot:** take a fresh snapshot the same way (new temp index) and
run `git diff --name-status --no-renames "$PHASE6_TREE" <new tree>`; every listed path
— added, modified, **deleted, or reverted to base** — changed during Phase 6.

### Phase 6.1: Discover the change surface (READ-ONLY)
Read the goal + task files (read-only), the working-tree diff for in-scope paths
(`git diff "$BASE_SHA" -- <path>` per file; `git diff --stat "$BASE_SHA"` for the
overview), and the full contents of every in-scope untracked file (they have no diff).
Apply the ownership filter from Phase 6.0. Distill a **"what shipped"** fact list —
new/changed routes, modules, CLIs, config keys, UI surfaces, auth behavior, renames,
removals — each fact with its source file.

### Phase 6.2: Map changes to affected docs
Using the surface map above, (1) **grep every in-scope doc** for each shipped fact's
identifiers — old and new names, flags, paths, and stale markers ("TODO", "planned",
"not yet"); (2) build the **per-doc edit list** from ONLY docs with at least one hit.
A doc with zero hits is out of the edit list — it is not evaluated and not reported as
"already accurate". Confirm `_memory/` is excluded.

### Phase 6.3: Evaluate the edit plan (`evaluator`)
**Small-change fold.** When the edit list has ≤ 3 docs, skip 6.3 as a separate spawn:
execute 6.4 directly and have the 6.5 final audit ALSO verify the edit-list criteria
(coverage, scope, anti-invention) in the same spawn. Log 'Phase 6.3 folded into 6.5
(edit list ≤ 3)'. With > 3 docs, 6.3 runs as today.

Criteria: coverage (every stale doc caught?), scope (zero excluded-path or code edits
planned?), anti-invention (every planned edit cites its source file?). Mandatory
re-evaluate loop: PASS → 6.4; NEEDS REVISION → revise + re-evaluate (3 max); REJECT →
escalate.

### Phase 6.4: Execute per doc (`implementer` + `evaluator`)
Docs are independent — executors may run in parallel. Context package per doc: its
edit-list entry, the relevant shipped facts, exact files to READ FIRST, and the full
guardrails. Evaluate each result: accuracy, completeness, scope (the delta since the Phase
6 snapshot contains only edit-list docs — this doc, docs already executed this run, and
docs of concurrently running executors — and this doc's executor changed no path other
than this doc), preserved prose intact, links resolve. Re-evaluate loop, 3 cycles max
per doc.

### Phase 6.5: Final audit (`evaluator`)
The whole change set: every affected doc accurate and **mutually consistent**; no
stale claims remain; the delta since the Phase 6 snapshot contains only in-scope docs;
the feature's own uncommitted code (present in the snapshot and unchanged since) is
expected and is not a scope failure. When the
small-change fold applied, this audit also verifies the 6.3 edit-list criteria (coverage,
scope, anti-invention).
APPROVED → lint markdown if a linter is configured, report which docs changed; ISSUES →
remediate + re-audit (3 max).

## Escalation

Escalate when: an evaluator fails to PASS/APPROVED after 3 cycles; any REJECT; no shipped
feature found; or a guardrail conflict (the only accurate fix would require a code
change — which this skill must not make).
