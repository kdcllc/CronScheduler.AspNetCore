---
name: ship-pr
description: Summarize all commits on the current branch into a rich pull request — an executive (manager-facing) summary plus a technical breakdown — then create it on GitHub, Azure DevOps, or GitLab, or print a draft/hand-over fallback. Phase 7 of the {{PROJECT_NAME}} orchestration lifecycle; also usable standalone when the user says "open a PR" or "ship this branch".
disable-model-invocation: true
---

# Ship PR (Phase 7)

Turn the commits on the current branch into a polished pull request or merge request. The
body has two audiences: a **manager-facing executive summary** (what was accomplished and
why it matters) and a **technical breakdown** (what changed, grouped by area). The
description is **drafted and shown for approval before any create or update** or
hand-over. The human-approval invariant holds in all four branches (`github`,
`azuredevops`, `gitlab`, `none`).

Never update git config, never force-push, never skip hooks, and only push/commit work
the user expects.

## Workflow

```
- [ ] Step 1: Gather branch + commit context
- [ ] Step 2: Detect the forge
- [ ] Step 3: Resolve the base branch from the chosen remote
- [ ] Step 4: Analyze the diff and commits
- [ ] Step 5: Draft the PR title + body
- [ ] Step 6: Show the draft and get approval
- [ ] Step 7: Push the branch (tracking remote if set, else origin)
- [ ] Step 8: Create or update via the forge branch
- [ ] Step 9: Return the PR URL or hand-over artifact
```

### Step 1: Gather branch + commit context

```bash
git rev-parse --abbrev-ref HEAD          # current branch
git status --short                       # uncommitted changes?
```

If there are uncommitted changes, surface them and ask whether to include them (do not
silently commit).

### Step 2: Detect the forge

Restated from ORCHESTRATION.md § "Forge adapter (Phase 7 delivery)"; this skill is
self-contained — follow the procedure here.

**Override first.** In `orchestration-kit.manifest.json`, `options.forge` (one of the
four taxonomy values) and optional `options.forgeHost` (self-hosted host mapping)
beat detection. The adapter never writes `git config`.

**Taxonomy.** Four values; each names its create mechanism:

| Value | Create mechanism |
|-------|------------------|
| `github` | `gh pr create` |
| `azuredevops` | `az repos pr create` |
| `gitlab` | `glab mr create` |
| `none` | draft + hand-over; never creates |

**Detection.** Classify the chosen remote's URL by domain. Host patterns:

| Host pattern | Forge |
|--------------|-------|
| `github.com` | `github` |
| `dev.azure.com`, `ssh.dev.azure.com`, `*.visualstudio.com`, `vs-ssh.visualstudio.com` | `azuredevops` |
| `gitlab.com` | `gitlab` |

The `_git` path segment is the strong signal on Azure DevOps URLs. Anything else
classifies to `none` unless overridden. Self-hosted GitLab, GHE (GitHub Enterprise),
and on-prem Azure DevOps Server are pattern-undetectable — override-only.

**Remote selection.** Choose the PR-target remote with this procedure:

1. Classify every remote's URL per the taxonomy.
2. A candidate is a remote that classifies to a known forge (`github`, `azuredevops`, `gitlab`). `none`-classified remotes (for example a deploy remote) are NOT candidates and can never trigger disagreement.
3. If candidates span two or more different forges, stop and ask the human — never pick silently.
4. Otherwise pick the PR-target remote by precedence `upstream` → a remote named for its forge (`github`, `azuredevops`/`azure`, `gitlab`) → `origin` → remaining candidates in `git remote` listed order.
5. Zero candidates → the `none` branch unless the manifest override names a forge.

**PR-target remote vs push remote.** Forge classification and base-branch resolution use
the chosen PR-target remote. Push uses the branch's existing tracking remote if set,
else origin. A GitHub fork setup (`origin` = fork, `upstream` = parent) keeps pushing
to the fork while targeting the parent, exactly as `gh` behaves.

### Step 3: Resolve the base branch from the chosen remote

Resolve the base branch from the chosen PR-target remote via `git ls-remote --symref`.
Name that remote explicitly in every `git ls-remote` / `git fetch` / `git log` /
`git diff` command.

```bash
git ls-remote --symref "$PR_TARGET_REMOTE" HEAD
```

Offline fallback: the cached symref `refs/remotes/<remote>/HEAD` (repair with
`git remote set-head "$PR_TARGET_REMOTE" -a`).
On the github branch, `gh repo view --json defaultBranchRef` remains an accepted resolver:

```bash
gh repo view --json defaultBranchRef -q .defaultBranchRef.name
```

If the current branch IS the resolved base, stop and tell the user — a PR needs a
feature branch.

```bash
git fetch "$PR_TARGET_REMOTE" "$BASE" --quiet
git log --oneline "$PR_TARGET_REMOTE/$BASE"..HEAD
```

If that range is empty, stop — there is nothing to open a PR for.

**Stop and ask** when:

- (a) the chosen remote's HEAD is unresolvable (cached symref unset AND `ls-remote` fails or is auth-blocked);
- (b) two candidate remotes resolve to different forges;
- (c) the resolved base differs from the branch the current commits diverged from.

### Step 4: Analyze the diff and commits

```bash
git log "$PR_TARGET_REMOTE/$BASE"..HEAD --pretty=format:'%h %s%n%b' --reverse
git diff "$PR_TARGET_REMOTE/$BASE"...HEAD --stat
```

Inspect the actual changes in the most-changed files. Group changes by area so the
technical breakdown reflects real structure — use the project's layers:
{{EXECUTION_LAYERS}}.

### Step 5: Draft the PR title + body

**Title**: one concise line in the repo's commit style (imperative, no trailing period).

**Body** template:

```markdown
## Summary
<2–4 sentence executive summary for a manager/stakeholder: what was accomplished,
the user/business impact. No jargon, no file names.>

## What changed
- **<Area>** — <plain-language outcome>

## Technical details
<Grouped breakdown for reviewers: design decisions, new dependencies,
schema/contract changes, anything risky.>

## Testing
- <How it was verified. Cycle-end gate is rung 3 of the test-ladder:
  {{FULL_TEST_COMMAND}}.>

## Backlog (not fixed here)
- B<n> (<source>): <finding>
<One bullet per `open` row of each delivered goal's `follow-ups.md`; with more than one
goal, write each bullet as `- <goal>/B<n> (<source>): <finding>`. Omit this section when
there are no open rows.>

## Notes for reviewers
<Optional: call-outs, follow-ups, open questions. Omit if empty.>

## Self-evaluated gates
<Include only when any delivered goal's orchestration log contains
`self-evaluation, not independent`. List each gate: goal, phase/task, verdict.
Omit this section otherwise.>
```

Before finalizing the body, read `_memory/work/goals/<goal>/orchestration-log.md`
for **every goal delivered on this branch** (one PR may carry several goals). When
any log contains `self-evaluation, not independent`, include `## Self-evaluated gates`
in the draft with one bullet per gate (goal id, phase/task, verdict); otherwise omit
that section entirely.

Also read `_memory/work/goals/<goal>/follow-ups.md` for every goal delivered on this
branch. List every row whose status is `open` under `## Backlog (not fixed here)` as
`- B<n> (<source>): <finding>`, dropping the row's ` — <status>` suffix. With no open rows
(or no `follow-ups.md`), omit the section entirely.
Backlog rows are never described as fixed in the PR body; the section lists what this PR
leaves open, and no other section claims one of those findings as resolved.
The section belongs to the one approved body, so every forge branch (`github`,
`azuredevops`, `gitlab`, `none`) carries it unchanged.

When the PR carries more than one goal, prefix each row with its goal:
`- <goal>/B<n> (<source>): <finding>`.

Drafting rules: the Summary is outcomes and impact, never a commit log; derive content
from the diff, not just commit subjects; omit empty sections; match the repo's tone.

### Step 6: Show the draft and get approval

Present the title and full body and wait for approval or edits. Do not create or update
yet. This approval covers create or update, push, and hand-over in all four branches
(`github`, `azuredevops`, `gitlab`, `none`).

### Step 7: Push the branch (only if needed)

git push uses the tracking remote if set, else origin — never implicitly the PR-target remote.

```bash
git status -sb            # ahead/behind + upstream
git push -u "$PUSH_REMOTE" HEAD   # only if no upstream or local is ahead
```

Never force-push. If the push is rejected, report it instead of forcing. Only after the
draft is approved. A GitHub fork keeps pushing to the fork (`origin`) while the PR
targets `upstream`.

### Step 8: Create or update via the forge branch

Branch on the detected forge. On-prem Azure DevOps Server takes the `none` branch
even if detection or override said `azuredevops`.

#### github

```bash
gh pr create --base "$BASE" --title "<approved title>" --body "$(cat <<'EOF'
<approved body>
EOF
)"
```

If a PR already exists for the branch, `gh pr edit` it instead of creating a duplicate.
If `gh` fails with an auth error, tell the user to run `gh auth login`.

#### azuredevops

Ensure the CLI extension: `az extension add --name azure-devops` (also auto-installs on first use).
Auth via `az login` or `AZURE_DEVOPS_EXT_PAT`. Footgun: an active `az login` Entra token overrides a scoped PAT.
`--detect` is on by default. If it cannot resolve context, pass explicit `--org` / `--project` / `--repository` parsed from the remote URL as fallback (e.g. `https://dev.azure.com/<org>/<project>/_git/<repo>`).
On-prem Azure DevOps Server routes to the `none` branch — `az repos` is Services-only.
Existence check: `az repos pr list --source-branch <b> --target-branch "$BASE" --status active`. Test both branch-name forms (the short name and `refs/heads/<b>`) before concluding no PR exists (short-form-only can duplicate-create). If a match exists, `az repos pr update --id <id>`; otherwise `az repos pr create`.
Pass `--description` as multiple args (each arg = one line of the approved body). `--draft true` is supported. If passing `--reviewers`, de-duplicate the list first (duplicate reviewers raise TF400898).

```bash
az extension add --name azure-devops
az repos pr create --source-branch <b> --target-branch "$BASE" --title "<approved title>" --description "<line 1>" "<line 2>" --draft true
az repos pr update --id <id> --title "<approved title>" --description "<line 1>" "<line 2>"
```

#### gitlab

Existence check: `glab mr list` (source-branch filter) routes create vs update.
For self-hosted GitLab, set `GITLAB_HOST` from `options.forgeHost`.

```bash
glab mr create -t "<approved title>" -d "<approved body>" --target-branch "$BASE" --draft
```

#### none

The `none` branch never creates a PR/MR (no PR/MR create invocation — it never executes a create). After the approved push, print a ready hand-over artifact (command or URL) and STOP. Printing a ready create command as the hand-over artifact is allowed and is not a violation.
Ready artifacts, in preference order: the PR URL if the push output surfaces one; a constructed Azure DevOps create URL when the host pattern is known (`https://dev.azure.com/<org>/<project>/_git/<repo>/pullrequestcreate?sourceRef=<branch>&targetRef=<base>`); or the exact create command for the human.

### Step 9: Return the PR URL or hand-over artifact

Print the URL (or the hand-over artifact) and note whether a PR/MR was created or
updated, or that the `none` branch stopped after printing the artifact. Cite the base
branch, the PR-target remote, the push remote, and the detected forge.

## Guardrails

- **Approval first** — always show the drafted description and wait before any create or update, push, or hand-over. This invariant holds in all four branches (`github`, `azuredevops`, `gitlab`, `none`).
- If `gh` fails with an auth error, tell the user to run `gh auth login`.
- **Never** update git config (the forge override is manifest-only — `options.forge` / `options.forgeHost`; never write a git-config key), force-push, or use `--no-verify`.
- Don't commit uncommitted work without explicit approval.
- Cite the **base branch**, the **PR-target remote**, the **push remote**, and the **detected forge** in the final report.
