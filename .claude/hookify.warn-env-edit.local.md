---
name: warn-env-edit
enabled: true
event: file
action: warn
conditions:
  - field: file_path
    operator: regex_match
    pattern: (\.env$|\.env\.|common\.env|core\.env)
---

⚠️ **`.env` file edit detected**

Changes to `.env` files do not trigger automatic restarts — services keep using old values until the next `docker compose up -d`.

Remember to restart the affected stack after saving.
