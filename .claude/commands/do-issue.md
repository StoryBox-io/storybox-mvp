Orchestrate storybox-mvp issue #$ARGUMENTS.

## Step 1 — Read the issue

```
gh issue view $ARGUMENTS --repo StoryBox-io/storybox-mvp
```

Note the title, milestone, labels, and Domain block.

## Step 2 — Identify the current planning proposal

```
gh issue view $ARGUMENTS --repo StoryBox-io/storybox-mvp --comments
```

Find every comment whose body contains the heading `## Planning proposal`. There may be more than one — issues can be replanned when the orchestrator updates scope or design. **The current plan is the comment with the most recent `createdAt` timestamp.** Older `## Planning proposal` comments are superseded historical context — ignore them when implementing. (A current plan should also have a `_Supersedes [previous plan](...)_` line at the top if it superseded an earlier one; absence of that line on a sole plan comment is normal for first-time plans.)

Then look for an **orchestrator review** that applies to the current plan: a comment containing `## Orchestrator review` whose `createdAt` timestamp is **after** the current plan's timestamp. Reviews older than the current plan reviewed a superseded plan and do not apply.

---

## If NO planning proposal exists

Trigger the planning workflow:

```
gh workflow run plan-issue.yml --repo StoryBox-io/storybox-mvp --field issue=$ARGUMENTS
```

Report the Actions run URL and tell the user: the planning agent is running and will post a proposal as a comment on the issue. Re-run `/do-issue $ARGUMENTS` once the comment appears.

---

## If a current planning proposal EXISTS but NO orchestrator review (newer than the plan) exists

Check the **Questions / ambiguities** section of the current plan:
- If it says `None` — the plan is self-contained. Proceed with implementation.
- If it lists open questions — tell the user the current plan has unresolved questions that need orchestrator review. Do not implement. Stop here.

---

## If BOTH a current planning proposal AND a newer orchestrator review exist

Read both comments in full. The orchestrator review may override or constrain the plan — its instructions take precedence over the current planning proposal where they conflict. Do **not** read superseded older `## Planning proposal` or `## Orchestrator review` comments — they have no bearing on what to implement now.

Implement now.

1. Read the planning proposal and the orchestrator review comment in full.
2. Create and check out a feature branch: `git checkout -b issue-$ARGUMENTS-<slug>` where `<slug>` is a short kebab-case description of the change (e.g. `issue-115-unique-version-identity`).
3. Mark the issue's project card as **In Progress** so the execution-start timestamp is recorded (paired with the issue's close timestamp from `Closes #$ARGUMENTS`, this gives us execution-cycle metrics).

   First, look up the project item ID for the issue (project #3 — "StoryBox MVP"):

   ```
   gh api graphql -f query='query($n: Int!) { repository(owner: "StoryBox-io", name: "storybox-mvp") { issue(number: $n) { projectItems(first: 5) { nodes { id project { number } } } } } }' -F n=$ARGUMENTS --jq '.data.repository.issue.projectItems.nodes[] | select(.project.number == 3) | .id'
   ```

   Then set the Status field to "In Progress" using that item ID (substitute `<ITEM_ID>` with the value returned above):

   ```
   gh project item-edit --project-id PVT_kwDODn_Yk84BT0ym --id <ITEM_ID> --field-id PVTSSF_lADODn_Yk84BT0ymzhBBB8w --single-select-option-id 47fc9ee4
   ```

   The project ID, Status field ID, and "In Progress" option ID are stable — do not change them. If the issue isn't on the project board (item ID lookup returns empty), skip this step and continue.
4. Follow the **Step-by-step plan** from the proposal, applying any constraints or overrides from the orchestrator review.
5. Obey the **Domain** block from the issue — stay within ALLOWED scope, do not touch NOT ALLOWED areas.
6. After completing all steps, run `mix precommit` and fix any failures.
7. Commit the changes with a message referencing the issue number (e.g. `Closes #$ARGUMENTS`) and push the branch.
8. Open a pull request from the feature branch to `main`. The PR body **must** include `Closes #$ARGUMENTS` on its own line so GitHub links and closes the issue on merge.
9. Check the **User testing** section of the proposal:
   - If it says "No user testing required" — report completion and the commit.
   - If it lists validation steps — print them clearly so the user knows what to verify.
