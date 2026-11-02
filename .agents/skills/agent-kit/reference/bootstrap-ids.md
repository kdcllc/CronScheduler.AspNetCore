# Bootstrap ids

`<!-- BOOTSTRAP[id]: text -->` is replaced by `answers.bootstrap[id]` (multi-line allowed); `<!-- IF flag -->`…`<!-- ENDIF flag -->` (and `!flag`) keep or drop the span. See `SKILL.md` Step 4 and `docs/agent-kit/guide/contributing.md` (template grammar).
An `""` answer deletes the comment silently; a missing key deletes it silently (no warning, not counted) and is listed by `--check-answers`.
`kit-` prefixed ids are instructions-only: always deleted, never answered, never warned.

| id | template path:line | class | what the LLM writes |
|----|-------------------|-------|---------------------|
| auto-fail-sins-evaluator | agents/evaluator.md:95 | a text | project-specific evaluator auto-fail sins (replacing the examples) |
| auto-fail-sins-qa | agents/qa-evaluator.md:48 | a text | project-specific QA behavioral auto-fail sins (replacing the examples) |
| auto-fail-triggers | ORCHESTRATION.md:1465 (Subagent Behaviors) | a text | auto-fail cell text for the Subagent Behaviors table |
| critical-reference-rows | ORCHESTRATION.md:1354 (Critical Reference Files) | a text | one table row per canonical reference routed into context packages |
| doc-buckets | skills/align-docs/SKILL.template.md:41 | a text | this project's doc buckets and code-area → doc mapping |
| domain-skill-rows | ORCHESTRATION.md:207 (Orchestrator & Reference Skills) | a text | extra Orchestrator & Reference Skills table rows for domain/supporting skills |
| execution-layers | ORCHESTRATION.md:624 (Execution Order) | a text | note on the dependency-ordered layer chain (token fills the diagram) |
| existing-agents | ORCHESTRATION.md:314 (Subagents) | a text | existing project agents and which kit role each overlaps, or deletion when none |
| fallback-chains | models.map.md:76 | a text | fallback-chain table filled with current per-harness model IDs |
| frontier-alt-family | models.map.md:150 | a text | continuation-ladder pin table plus the frontier alt-family ID |
| full-suite-commands | skills/test-ladder/SKILL.template.md:84 | a text | extra per-stack full-suite and cycle-end lint commands |
| greenfield-practices | ORCHESTRATION.md:19 | a text | Engineering practices subsection (test-first + SOLID; stack-agnostic) |
| kit-meta | ORCHESTRATION.md:3 | d always-deleted | (none — template meta instruction) |
| layer-skill-map | skills/feature/SKILL.template.md:79 | a text | layer → skills and path-scoped rule files (Rule files to cite column) routing table |
| loop-fallback | models.map.md:109 | a text | loop fallback-chain table and {{LOOP_MODEL_CHAIN}} resolution |
| mock-boundary | agents/test-writer.md:22 | a text | the mock boundary and available fixtures/tools |
| models-map-caveats | models.map.md:179 | a text | harness caveat bullets for the targeted install |
| models-map-effort | models.map.md:61 | a text | reasoning-effort pins paragraph for the targeted harnesses |
| models-map-fix-cycle | models.map.md:128 | a text | fix-cycle rotation table with current per-harness model IDs |
| models-map-live-check | models.map.md:8 | a text | live-checked model-list confirmation note |
| models-map-title | models.map.md:1 | a text | Model Map heading, optionally with a resolved subtitle |
| path-test-conventions | skills/test-ladder/SKILL.template.md:64 | a text | changed-path → first-impacted-tests convention map |
| preflight-extra | skills/feature/reference/preflight.md:11 | a text | project-specific pre-flight checks (one bullet each) or deletion when none |
| qa-evaluator-surfaces | agents/qa-evaluator.md:37 | a text | this project's surfaces and the evidence each must include |
| qa-surfaces | ORCHESTRATION.md:700 (QA Evaluation) | a text | user-facing surfaces and the evidence each produces |
| qa-surfaces-keep | skills/qa-criteria/SKILL.template.md:22 | a text | per-surface criteria kept and sharpened for this project |
| quality-check-commands | ORCHESTRATION.md:1361 (Quality Checks) | a text | extra Quality Checks rows beyond the test/lint/typecheck flags |
| rendered-siblings | skills/align-docs/SKILL.template.md:30 | a text | rendered-sibling guardrail naming the pair(s), or deletion |
| shared-libs | agents/implementer.md:24 | a text | names of shared infrastructure the implementer must reuse |
| skills-tree | ORCHESTRATION.md:1345 (File Locations) | a text | extra domain/supporting skill entries in the File Locations tree |
| stack-note | ORCHESTRATION.md:12 | a text | extra stack-note sentences beyond {{STACK_SUMMARY}} |

| flag | meaning | governs (paths) |
|------|---------|-----------------|
| research | research skill and Research Flow installed | templates/ORCHESTRATION.md (TOC item, skills row, disable-model-invocation variants, Research Flow section, File Locations tree, Invoking Skills, memory-workflow table Research row) |
| loop | autonomous loop installed | templates/ORCHESTRATION.md (TOC item, disable-model-invocation variants, Autonomous Loop section, File Locations tree, memory-workflow table Loop rows); templates/models.map.md (Loop fallback chain) |
| greenfield | Step 2a accept-and-confirm path (`options.greenfield`) | templates/ORCHESTRATION.md (Engineering practices) |
| lint | a lint command is configured | templates/ORCHESTRATION.md (Quality Checks Lint row) |
| typecheck | a typecheck command is configured | templates/ORCHESTRATION.md (Quality Checks Type check row) |
| models_pinned | model IDs are pinned (not inherit/unpinned) | templates/ORCHESTRATION.md (Subagents Model Tier column; Model tiers paragraph) |
| opt_in | `flags.opt_in` — kit is opt-in (orchestrator skills run only via /feature, /research, /memory-capture) | templates/agents/*.md (description prefix token), templates/skills/{feature,research,memory-capture}/SKILL.template.md (disable-model-invocation line, description tokens), templates/ORCHESTRATION.md (skills note variants), templates/loop/SKILL.template.md (feature path Read) |
| kit_guard | `flags.kit_guard` — kit-owned files are guarded | templates/ORCHESTRATION.md (Repository safety item 4, Workflow State Tracking note), templates/skills/feature/SKILL.template.md (progress location, Phase 5 kit-file gate), templates/agents/{implementer,test-writer,evidence-collector}.md (read-only rule), templates/agents/evaluator.md (auto-fail bullet) |
| hook_telemetry | `flags.hook_telemetry` — stop/subagent-stop hook telemetry | templates/ORCHESTRATION.md (File Locations trees, Orchestration log note), templates/memory/README.md (_memory/ layout tree) |
| is_claude | emitting the Claude Code copy (exactly one `is_*` true per harness; primary's `is_*` for single-copy artifacts) | (none in templates — reserved for per-target emit) |
| is_cursor | emitting the Cursor copy | (none in templates — reserved for per-target emit) |
| is_copilot | emitting the Copilot copy | (none in templates — reserved for per-target emit) |
| is_codex | emitting the Codex copy | (none in templates — reserved for per-target emit) |
| want_claude | `claude-code` ∈ `answers.harnesses` | templates/models.map.md (Resolved-models table variants) |
| want_cursor | `cursor` ∈ `answers.harnesses` | templates/models.map.md (Resolved-models table variants) |
| want_copilot | `copilot` ∈ `answers.harnesses` | templates/models.map.md (Copilot bullet; Copilot fit paragraph) |
| want_codex | `codex` ∈ `answers.harnesses` | templates/models.map.md (Codex bullet) |
