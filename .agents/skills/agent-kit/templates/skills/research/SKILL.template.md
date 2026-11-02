---
name: research
description: Research → Plan workflow for {{PROJECT_NAME}} topics needing external investigation — produces a research prompt, ingests the report, and yields an evaluated goal/task structure.{{OPT_IN_RESEARCH_SUFFIX}}
<!-- IF opt_in -->
disable-model-invocation: true
<!-- ENDIF opt_in -->
---

# Research (Deep Research → Plan Orchestrator)

For domain topics an external research agent must investigate **without codebase
access**. You coordinate four phases; the output enters `feature` at Phase 3 (goal evaluation).

## Phase 1 — Generate the research prompt

**Recall:** search `--kind research-ingest,decision` (≤ 5) per
`{{IDE_DIR}}/skills/feature/reference/memory-protocol.md`; write ids or `none` to
`_memory/work/research/<topic>/recalled-memory.md` (avoid re-researching settled questions).

Write `_memory/work/research/<topic>/prompt.md` from `templates/research-prompt.md`. The prompt must
be self-contained (the researcher cannot see this repo): include the relevant facts from
{{GROUND_TRUTH_DOC}} and the domain skill, the exact questions to answer, and the
required report structure. The user copy-pastes it to their external research tool.

## Phase 2 — Ingest the report

Save the returned report as `_memory/work/research/<topic>/report.md` (structure per
`templates/research-report.md`). Read it critically: flag claims that contradict
{{GROUND_TRUTH_DOC}} or the codebase, and list open questions back to the user. Write
that ingestion review to `_memory/work/research/<topic>/review.md`.

**Promote:** write the curated brief `_memory/research/<topic>.md` from
`templates/research-brief.md` (`status: ingested`), then add or update the topic's row in
`_memory/research/README.md` (create it from `templates/research-index.md` only when
missing, replacing the sample row with this first real row). Only implemented facts go
into {{GROUND_TRUTH_DOC}}; `_memory/work/research/` stays scratch. Briefs are tracked and
orchestrator-owned — worker tasks never write `_memory/research/`.

**Archive:** one `research-ingest` after ingestion review per
`{{IDE_DIR}}/skills/feature/reference/memory-protocol.md`, with `--source` set to the brief
path `_memory/research/<topic>.md`; add the new id to the brief's `memory:` list. Run
`_kit/memory.sh check` on each path `add` writes (or quarantines), then write
`_memory/work/research/<topic>/ingested` per protocol before commit.

## Phase 3 — High-level plan

Collaborative planning with the user (use Plan Mode if available): approach options with
tradeoffs, chosen direction, affected layers ({{EXECUTION_LAYERS}}).

## Phase 4 — Low-level tasks

Create `_memory/work/goals/[goal-name]/` using the `feature` skill's `goal.md`/`task.md`
templates; copy Phase 1 picks (or `none`) from `recalled-memory.md` into the goal's
`## Recalled memory` and log the note per
`{{IDE_DIR}}/skills/feature/reference/memory-protocol.md`. Append the goal name to the
brief's `goals:` list (set `status: adopted` when it was `ingested`, and mirror the status
in its index row). Read `{{IDE_DIR}}/skills/feature/SKILL.md` and continue from its
Phase 3 (goal evaluation) — the goal still must PASS the evaluator before execution.
