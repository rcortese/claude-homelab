---
name: warn-rm-rf
enabled: true
event: bash
action: block
pattern: rm\s+(-\w*r\w*f|-rf|-fr)\s
---

⚠️ **`rm -rf` detected**

This will permanently delete files or directories with no recovery path.

**Before proceeding, confirm:**
- Is this a temp/scratch directory (e.g. `/tmp/...`)?
- Is the target path correct and scoped (not `/`, `~`, or a stack data dir)?
- For homelab data dirs (HA, n8n, pihole), use a backup first: `homelab-maestro/scripts/backup.sh`
