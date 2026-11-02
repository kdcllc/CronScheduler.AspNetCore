# Model Map — Claude Code

Model IDs are **configuration, not constants**. This file is the single place they are
defined; re-run `/agent-kit` (or edit here and re-emit) when providers rotate model names.

Live-checked 2026-11-02 for Claude Code only: `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5` are the current Claude 5 family IDs reported by the running Claude Code session (`claude --version` = 2.1.316). Full IDs are pinned rather than aliases. **Cost profile (2026-11-02, user request from usage insights "give evaluator subagents a cheaper model")**: the frontier tier (evaluator, qa-evaluator, diagnostician) is pinned to Sonnet at high/xhigh effort; Opus is reserved for fix-cycle 2 rotation only. The orchestrator is the main session — its model is chosen by the user, not pinned here. Re-verify against the Claude Code model-configuration docs when providers rotate model names.

## Tier assignments

| Tier | Roles | Rationale |
|------|-------|-----------|
| `frontier` | orchestrator (main session), `evaluator`, `qa-evaluator`, `diagnostician` | Delegation and evaluation have a capability floor — don't cheap out on the roles that decide and verify; continuation-ladder diagnosis needs frontier-tier reasoning |
| `light` | `implementer`, `test-writer`, `evidence-collector` | Checklist-driven execution retains most quality at a fraction of the cost when the plan and the verification are strong |
| `fast` | `terminal` | Single-command execution and result extraction need no deep reasoning — the cheapest, quickest tier fits |

## Resolved models

| Tier | Claude Code |
|------|-------------|
| `frontier` | claude-sonnet-5-5 |
| `light` | claude-sonnet-5-5 |
| `fast` | claude-haiku-5-5 |

An install that omits `fast` runs `terminal` on the light model (the `fast` row then
repeats the light ID).

Reasoning-effort pins (Claude Code `effort:` frontmatter): evaluators (`evaluator`, `qa-evaluator`) `high`, `diagnostician` `xhigh`, `implementer`/`test-writer`/`evidence-collector` `medium`, `terminal` `low`. Never quote the YAML `model:` value — a quoted or unresolvable value silently falls back to the parent model.

## Fallback chains

| Tier | Chain (first available wins) |
|------|------------------------------|
| `frontier` | `claude-sonnet-5-5` → (omit pin — harness default) |
| `light` | `claude-sonnet-5-5` → (omit pin — harness default) |
| `fast` | `claude-haiku-5-5` → `claude-sonnet-5-5` → (omit pin — harness default) |

Rules (adapted from bradygaster/squad's model selector):

- **Never fall back UP a tier** — a light role must never silently land on a frontier
  model, and a frontier role never degrades below the standard rung of its chain.
  One carve-out: fast → light is allowed, because light is `terminal`'s baseline tier
  (installs without `fast` run it there).
- Fallbacks are silent to the user but **logged in the orchestration log**.
- Max 3 fallback attempts, then omit the model pin and take the harness default.
- Apply at most **one** complexity adjustment per spawn — no cascading bumps.
- **Cost ceiling policy**: an EXPLICIT human model choice above a plan/admin ceiling →
  warn loudly and honor it; an implicit (auto-selected) choice → downgrade to the
  ceiling; no compliant model at all → fail loud — never silently substitute.
- **Prompts are executable — narrowly**: only tasks that edit `templates/agents/*`
  or `templates/skills/*-criteria/*` (the files that shape every later spawn's
  behavior) use the frontier tier; skills, emitters, drivers, docs, and tests stay
  on the light tier.
- **Every spawn names its model.** The orchestrator passes the tier's resolved ID
  explicitly on every spawn and records `requested` vs the agent's self-reported
  model in the orchestration log; `inherit` is legitimate only for a tier the
  install deliberately left unpinned.

### Loop fallback chain

| Chain (first available wins) | Resolves |
|-------------------------------|----------|
| `claude-sonnet-5-5` → `claude-haiku-5-5` → (omit pin — harness default) | `claude-sonnet-5-5,claude-haiku-5-5` |

Light-tier by default — the loop's iterations are implementer/test-writer-shaped work. A trip past the last chain entry clears the model pin and the harness default takes over.

## Fix-cycle rotation (after evaluator rejections)

A model blind to its own class of mistake rarely fixes it on retry. Rotate:

| Fix cycle | Implementer model |
|-----------|-------------------|
| 1 | `claude-sonnet-5-5` (normal) |
| 2 | `claude-opus-5-5` — same-family rotation (reduced diversity; Claude Code is Anthropic-only) to the stronger model for fresh eyes |
| 3 | `claude-sonnet-5-5` (frontier tier, cost profile) |

**Same-family rotation.** When no different-family model at comparable tier is reachable
on a harness, fix cycle 2 may pin a different same-family model (see the table above) and
label the row `same-family rotation (reduced diversity)`. A second harness such as Copilot
or Codex provides cross-family models when targeted. Repeated same-shaped failures across
fix cycle 2 and continuation-ladder rung 4 should escalate to a human sooner.

### After cycle 3 — continuation ladder pins

When fix cycles are exhausted (cycle 3, or earlier on early ladder entry), the continuation ladder (see ORCHESTRATION.md) applies:

| Ladder step | Model pin |
|-------------|-----------|
| Diagnosis-driven implementation attempt (rung 4) | `claude-sonnet-5-5` (frontier tier, xhigh effort for the diagnostician) |
| Evaluator arbitration mode (rung 5) | `claude-sonnet-5-5` — same-family arbiter (reduced independence) |

**Same-family arbiter.** When no different-family frontier model is reachable on a
harness, `frontier_alt_family` may equal `frontier` with `arbiter_same_family: true`
in the answers file (emit otherwise warns); the rung-5 row is then labelled
"same-family arbiter (reduced independence)" and the arbiter's verdict header says
`same-family arbiter`. Reusing the fix-cycle-2 alternate (`alt_family`) for
arbitration stays forbidden — when `frontier_alt_family` equals `alt_family` (and
differs from `frontier`), emit warns even with the flag.

## Harness caveats that shape tiering

- **Claude Code env overrides**: `CLAUDE_CODE_SUBAGENT_MODEL` and `CLAUDE_CODE_EFFORT_LEVEL` override frontmatter; org `availableModels` allowlists can cause pins to be ignored.
- **Claude Code is single-provider**: Anthropic models only, so fix-cycle 2 and the rung-5 arbiter are same-family (see **Same-family arbiter**). Target Copilot or Codex later to get cross-family rotation.
- **Full IDs pinned**: aliases resolve per provider (Bedrock, Vertex, Foundry), so this install pins full IDs.
- **Usage-credit aliases**: headless loop runs must never resolve to `best`/`fable`; emit rejects them in a loop chain.
- **Cost profile**: evaluators run Sonnet (`effort: high`) instead of Opus to cut evaluation cost; Opus appears only at fix-cycle 2. To restore Opus evaluators, set `frontier` back to `claude-opus-5-5` in the answers and re-run `emit.sh --upgrade`.
