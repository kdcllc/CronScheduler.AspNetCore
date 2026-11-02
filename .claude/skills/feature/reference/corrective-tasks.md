# Corrective tasks (defects in completed work)

When an executor **report-and-stop** on a defect in files a **completed** task owns
(out-of-fence for the reporting task):

1. Create `NN<letter>-<name>.md` from `templates/task.md` — lettered after the last
   completed task's number (`09a-…`, `09b-…`), inserted before the next unstarted task.
2. Set `depends_on` to the task whose files it fixes.
3. Set `writes` to the minimal set of those files (plus their tests).
4. Add `depends_on` edges so every unstarted task that **reads or writes** those files runs after
   the corrective task, then re-check write-set disjointness against every remaining task.
5. Write its own Acceptance Criteria (executable-criteria rules apply).
6. Treat as an **additive** amendment: run pre-flight checks 1, 2, and 5 and a targeted
   evaluation before dispatch.
7. Log a `note` (finding, source task, corrective id).

The reporting task **never** edits the defective files itself.

## Worked example (generic)

Task `03-api-layer` PASSed but task `04-ui` discovers the API response shape is wrong.
Orchestrator adds `03a-fix-response-shape.md` before `04-ui`, `depends_on: ["03-api-layer"]`,
`writes` the API module and its tests, adds `depends_on: ["03a-fix-response-shape"]` on
`04-ui`, runs pre-flight and a targeted evaluation, then dispatches `03a` before resuming
`04-ui`. Task `04-ui`'s report only flags the defect — it does not patch `03`'s files.
