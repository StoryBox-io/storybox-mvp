Orchestrate storybox-mvp issue #$ARGUMENTS.

## Step 1 — Read the issue

```
gh issue view $ARGUMENTS --repo StoryBox-io/storybox-mvp
```

Note the title, milestone, labels, and Domain block.

## Step 2 — Check for an existing planning proposal

```
gh issue view $ARGUMENTS --repo StoryBox-io/storybox-mvp --comments
```

Look for:
- A comment containing `## Planning proposal` (the plan)
- A comment containing `## Orchestrator review` (the approval)

---

## If NO planning proposal exists

Trigger the planning workflow:

```
gh workflow run plan-issue.yml --repo StoryBox-io/storybox-mvp --field issue=$ARGUMENTS
```

Report the Actions run URL and tell the user: the planning agent is running and will post a proposal as a comment on the issue. Re-run `/do-issue $ARGUMENTS` once the comment appears.

---

## If a planning proposal EXISTS but NO orchestrator review exists

Check the **Questions / ambiguities** section of the proposal:
- If it says `None` — the plan is self-contained. Proceed with implementation.
- If it lists open questions — tell the user the plan has unresolved questions that need orchestrator review. Do not implement. Stop here.

---

## If BOTH a planning proposal AND an orchestrator review exist

Read both comments in full. The orchestrator review may override or constrain the plan — its instructions take precedence over the planning proposal where they conflict.

Implement now.

1. Read the planning proposal and the orchestrator review comment in full.
2. Create and check out a feature branch: `git checkout -b issue-$ARGUMENTS-<slug>` where `<slug>` is a short kebab-case description of the change (e.g. `issue-115-unique-version-identity`).
3. Follow the **Step-by-step plan** from the proposal, applying any constraints or overrides from the orchestrator review.
4. Obey the **Domain** block from the issue — stay within ALLOWED scope, do not touch NOT ALLOWED areas.
5. After completing all steps, run `mix precommit` and fix any failures.
6. Commit the changes with a message referencing the issue number (e.g. `Closes #$ARGUMENTS`) and push the branch.
7. Open a pull request from the feature branch to `main`. The PR body **must** include `Closes #$ARGUMENTS` on its own line so GitHub links and closes the issue on merge.
8. Check the **User testing** section of the proposal:
   - If it says "No user testing required" — report completion and the commit.
   - If it lists validation steps — print them clearly so the user knows what to verify.
