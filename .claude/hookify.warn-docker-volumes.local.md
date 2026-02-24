---
name: warn-docker-volumes
enabled: true
event: bash
action: block
pattern: docker\s+(compose|volume)\s+.*(--volumes|-v\b|prune|rm\b)
---

⚠️ **Docker volume destruction detected**

This command will **permanently delete Docker volumes** — including persistent data such as:
- Home Assistant database (`homeassistant_db`)
- n8n workflows and credentials
- Pihole lists and configuration

**Before proceeding:**
1. Run a backup first: `homelab-maestro/scripts/backup.sh`
2. Confirm which volumes will be affected: `docker compose config --volumes`
3. Verify no other stack depends on the volume
