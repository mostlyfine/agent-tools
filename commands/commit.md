---
name: Commit
description: "Commit staged/unstaged changes in meaningful units using conventional commit format (English)"
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git add:*), Bash(git apply:*), Bash(git commit:*), Bash(git log:*), AskUserQuestion
---

# Conventional Commit

Commit all pending changes in meaningful logical units using conventional commit format in English. Repeat until the working tree is clean.

## Phase A: Determine Commit Scope

**A-1. Check staging state**

Run `git diff --cached --stat`.

- **If staged changes exist** → those changes are the commit scope. Ignore unstaged and untracked files entirely. The user has already expressed intent by staging. Proceed to Phase C.
- **If nothing is staged** → treat all unstaged changes and untracked files as candidates. Continue to Phase B.

**A-2. Identify session context**

Review the current conversation to identify:
- Changes made, discussed, or observed in this session (these carry intent context)
- Changes unrelated to this session (previous sessions, other agents, manual edits)

**A-3. Determine action basis**
- If the reason for changes is clear from session context → use that context to write the commit message
- If unclear (no conversation context available) → describe only what the diff shows

> **Rule**: The commit message MUST cover ALL changes in scope — not just the ones you worked on. Ignoring unrelated changes is worse than briefly mentioning them.

---

## Phase B: Loop Until Working Tree Is Clean

Repeat the following until `git status` shows no unstaged changes and no untracked files to include:

**B-1. Handle untracked files (first iteration only)**

Run `git status`. If untracked files exist, use `AskUserQuestion` to ask the user which untracked files should be included in commits. Only include explicitly confirmed files.

**B-2. Plan commit units**

Analyze `git diff HEAD` and group changes into logical units. Each unit should represent one coherent change (single responsibility). Present the plan with proposed conventional commit messages and wait for confirmation before proceeding.

**B-3. Stage the next commit unit (fully automated)**

- **Entire file(s)**: `git add <file1> <file2> ...`
- **Specific hunks only**: Use `git apply --cached` to stage selected hunks automatically:
  1. Obtain the full diff: `git diff <file>`
  2. Extract only the hunks belonging to this commit unit (construct patch text)
  3. Apply to the index: `echo "<patch>" | git apply --cached` or write to a temp file and `git apply --cached <patch-file>`

  No user interaction required — the agent handles hunk selection entirely.

Proceed to Phase C, then return here if changes remain.

---

## Phase C: Generate and Execute Commit

**C-1. Verify staged content**

Run `git diff --staged` to confirm only the intended changes are staged.

**C-2. Write the commit message**

Format: `<type>(<scope>): <description>`

Rules:
- **Subject describes WHY** — the background reason, not just what changed
  - Bad: `fix(auth): fix null pointer error`
  - Good: `fix(auth): prevent crash when session expires without refresh`
- `type`: `feat` | `fix` | `docs` | `style` | `refactor` | `test` | `chore` | `build` | `ci` | `perf`
- `scope`: the affected module/area (omit if unclear)
- `description`: imperative mood, lowercase, no trailing period, max 72 characters

**Body (optional, add when subject alone is insufficient):**
- Separate from subject with a blank line
- Use bullet points (`-`), one point per logical reason
- Each bullet answers WHY, not WHAT — avoid restating what the diff already shows
- Example:
  ```
  refactor(recommendation): move task DAGs into recommendation/ subdirectory

  - recommendation_daily/hourly now invokes dbt_run and dump_gcs as separate
    steps, making the monolithic dbt_run_and_dump_gcs DAG redundant
  - move surviving task DAGs under recommendation/ for clearer namespacing
  - remove obsolete trigger_dump_gcs test DAG
  ```

**C-3. Commit**

```
git commit -m "<type>(<scope>): <why-description>"
```

**C-3b. Amend if the user requests message changes**

If the user asks to revise the commit message after the commit:
- Use `git commit --amend -m "..."` (only for commits not yet pushed)
- Apply the same subject/body rules above

**C-4. Check remaining changes (Phase B loop)**

Run `git status` and `git diff HEAD`. If changes remain, return to B-2.

---

## Phase D: PR Description

After all commits are done, output the following:

**What this PR achieves** (1–2 sentence summary)

**Why it was needed** (bullet points):
- Why was this change necessary?
- What problem does it solve?
- What benefit does it provide?
