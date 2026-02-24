---
name: warn-git-destructive
enabled: true
event: bash
action: block
pattern: git\s+(reset\s+--hard|clean\s+-[fdxX]+|push\s+.*--force|push\s+.*-f\b|branch\s+-D\b)
---

⚠️ **Destructive git operation detected**

| Command | Risk |
|---------|------|
| `reset --hard` | Discards all uncommitted changes — unrecoverable |
| `clean -f/fd/fx` | Deletes untracked files permanently |
| `push --force` | Overwrites remote history; affects collaborators |
| `branch -D` | Force-deletes branch even with unmerged commits |

**Before proceeding:**
- `git status` and `git stash` to preserve any in-progress work
- For force push: confirm the branch and remote are correct
- For maestro: generated `docker-compose.yml` files are in `.gitignore` — safe to lose
