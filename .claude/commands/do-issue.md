Orchestrate storybox-mvp issue #$ARGUMENTS.

## Step 1 — Read the issue

```
gh issue view $ARGUMENTS --repo StoryBox-io/storybox-mvp
```

Note the title, milestone, labels, and Domain block.

## Step 2 — Check for an existing planning proposal

```
gh issue comments $ARGUMENTS --repo StoryBox-io/storybox-mvp
```

Look for a comment containing `## Planning proposal`.

---

## If NO planning proposal exists

Trigger the planning workflow:

```
gh workflow run plan-issue.yml --repo StoryBox-io/storybox-mvp --field issue=$ARGUMENTS
```

Report the Actions run URL and tell the user: the planning agent is running and will post a proposal as a comment on the issue. Re-run `/do-issue $ARGUMENTS` once the comment appears to get implementation instructions.

---

## If a planning proposal EXISTS

Summarise the proposal in this order:
1. **What changes** — one sentence from the Schema diff or Actions/changes section
2. **Step-by-step plan** — reproduce the numbered steps verbatim
3. **User testing** — reproduce the User testing section verbatim (either "No user testing required" or the boot instructions + checklist)

Then tell the user:

> The plan is ready. To implement, start a local agent in the storybox-mvp directory:
>
> ```
> cd C:\Users\hidde\Documents\dev\storybox-mvp
> claude
> ```
>
> Open the session and say: **"Implement issue #$ARGUMENTS — follow the planning proposal comment on the issue."**
