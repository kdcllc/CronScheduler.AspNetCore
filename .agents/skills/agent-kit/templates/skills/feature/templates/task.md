# Task NN: [name]

## Objective

[One paragraph: what exists when this task is done.]

## Dependencies

- [Tasks that must be complete first, or "none"]

```yaml
# --- task ownership contract ---
writes:              # [the ONLY paths this task may create or modify]
  - [path]           # [explicit paths by default; use a glob only when this task owns
                     #  the whole directory — two globs that overlap count as
                     #  intersecting, same as two identical paths]
reads:               # [interface briefs this task depends on, read-only]
  - [path]           # [exported symbols and signatures only, never edited here]
depends_on:          # [task ids that must land before this one, or [] for none — always
                     #  QUOTE each id so it stays the task file's name prefix; unquoted
                     #  numerics parse as YAML integers and break id comparisons;
                     #  corrective tasks use NN<letter> ids (e.g. 09a-fix-api)]
  - "NN-name"
owner: [implementer|test-writer]     # [one writer for every path above]
rewrite_semantics: [whole-file|targeted-insertion]
# [whole-file is the default — small single-owner source files: the owner rewrites
#  them wholesale and never assumes another agent will reconcile the result.
#  targeted-insertion is for large shared documents: surgical edits that leave every
#  unrelated line untouched.]
eval_depth: [light|full]
# [orchestrator-set at planning time — never set by a worker. Default: light. full is
#  required (state why) for contract tasks, tasks with interface consumers (mirroring,
#  documenting, or testing the output does not count), and tasks
#  writing agents/criteria/drivers/shared infra — light NEVER skips evaluation, every
#  task still ends in a real verdict.]
```

## Requirements (exhaustive — the evaluator verifies every item)

- [ ] [Specific, verifiable requirement]
- [ ] [Error handling requirement — what happens on failure X]
- [ ] [...]

## Acceptance Criteria

Command criteria need a `criteria-evidence.md` entry (run output; true negative and true positive for content-inspecting checks).

1. [Specific, verifiable criterion] — verification: [unit test | integration test | command output | live interaction | screenshot]
2. [Specific, verifiable criterion] — verification: [unit test | integration test | command output | live interaction | screenshot]
3. [...]

These criteria absorb the former contract's done-definition precision and out-of-scope
note; the Phase 3 goal evaluator validates them once for all tasks.

## Files to Read

- [path] — [why]

## Files to Create / Change

- [path] — [what]
- [Exactly the paths in the ownership contract's write-set above — no extras, no
  omissions; this section is the prose view of that machine block.]

## Constraints

- Must: [reuse shared module X, follow pattern in Y, ...]
- Must NOT: [re-implement Z, touch live services, modify files outside this list, ...]

## Verification

- Targeted test command: `[exact command]`
- [Any manual verification evidence to capture]
