---
name: warn-compose-down
enabled: true
event: bash
action: warn
pattern: docker\s+compose\s+.*\bdown\b
---

⚠️ **`docker compose down` detected**

This stops containers and removes the stack network. Volumes are preserved, but services go offline.

**Recommended teardown order:** smart-home-stack → homelab-maestro → infra-stack → network-stack

Confirm you want to take down this stack?
