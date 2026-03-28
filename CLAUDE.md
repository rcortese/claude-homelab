# Homelab Administration

## Rules

- Pipe verbose commands through `| tail`, use `--quiet` flags.
- On transient errors (rate limits, timeouts), stop immediately.
- Tables over prose. No summaries unless asked.
- For stack-specific details, read the CLAUDE.md inside that stack directory.
- Git commits: never add `Co-Authored-By` trailers.
- Stack repos: CLAUDE.md must be in `.gitignore` (AI config, not stack config).

## Autonomy

Freely: health checks, logs/configs, validation, querying state.
Ask first: start/stop/restart, deploy, config changes, backups, destructive ops.

## Safety Guardrails

- Ask first before `docker compose down`, restarts, deploys, backups, or config changes.
- Never remove Docker volumes without explicit confirmation and a verified backup.
- Treat `rm -rf`, `git reset --hard`, `git clean`, and force-push as destructive operations requiring confirmation.
- After editing `.env` files, recreate the affected services with `docker compose up -d` so new values take effect.

## Host

zbox (`10.18.19.0/24`). See `INFRASTRUCTURE.md` for topology and DR.

## Stacks

Each stack is a **git submodule** with its own CLAUDE.md (services, env vars, troubleshooting).

| Stack | Summary |
|-------|---------|
| `network-stack` | DNS, VPN, reverse proxy, DDNS (macvlan) |
| `infra-stack` | Portainer, Diun, syslog-ng, LibreSpeed |
| `smart-home-stack` | Home Assistant, deCONZ, MariaDB, MQTT |
| `homelab-maestro` | n8n + Moss ops engine (compose is **generated**) |
| `homelab-n8n-workflows` | Workflow definitions only, no runtime |
| `homelab-template` | Reusable IaC template for maestro (upstream) |
| `n8n-gitops` | CLI tool for n8n workflow sync to git |

Env: all stacks use `.env`. Maestro also uses `env/local/common.env`, `env/local/core.env`.

## Stack Integrations

Documented cross-stack links to keep in mind before changes:

| Source | Target | Mechanism | Why it matters |
|-------|--------|-----------|----------------|
| `network-stack` | `homelab-maestro` | Pi-hole local DNS/CNAME for `n8n.rodolflix.com`; Caddy reverse proxy `n8n.rodolflix.com` → `zbox.lan:5678` | n8n UI, webhooks, and Diun notifications depend on DNS + proxy path staying intact. |
| `infra-stack` | `homelab-maestro` | Diun webhook `POST https://n8n.rodolflix.com/webhook/diun-updates` | Image update alerts flow into n8n through the public endpoint exposed by `network-stack`. |
| `homelab-maestro` | `homelab-n8n-workflows` | Bind mount `/srv/homelab/homelab-n8n-workflows` into `/home/node/.n8n-files/export`; `util.git.backup.workflows` exports runtime workflows there | Workflow backups/export live in git outside the runtime container. |
| `homelab-maestro` | `n8n-gitops` | Deployed n8n can drift from git; re-sync path uses `n8n-gitops` when workflow JSON and runtime diverge | Git is not automatically the source of truth unless workflows are re-synced. |
| `smart-home-stack` | `network-stack` | Home Assistant and `file-mover` use LAN names such as `media.lan` and `zbox.lan`; Pi-hole is the managed DNS layer in this homelab | Name resolution issues can look like HA, SSH, or SMB failures when the real fault is DNS/ingress. |
| `smart-home-stack` | Unraid | Home Assistant uses SSH to `root@media.lan` and remote scripts under `/mnt/user/appdata/unraid-scripts/` | Some HA automations manage VMs and Docker on Unraid, so this stack is not self-contained. |
| `smart-home-stack` | host SMB mount | `file-mover` writes to `${FILEMOVER_DEST}`; production expects `/mnt/media_home_assistant` mounted from `//media.lan/home-assistant` | Camera/file export can silently fall back to local disk if the host mount is wrong. |
| `infra-stack` | other stacks | `syslog-ng` classifies remote/manual Docker syslog into `network.log`, `smarthome.log`, `maestro.log` | Central log collection exists, but forwarding is not the default compose logging path for every service. |
| `homelab-template` | `homelab-maestro` | Maestro compose/env are generated from template scripts and fragments | Structural maestro changes belong in template/fragments, not hand-edited generated compose output. |

| Integration class | Meaning |
|-------------------|---------|
| Publication / automation | Breaking DNS, proxy, webhook, SSH, workflow sync, or SMB export paths changes behavior across stacks and can justify startup-order or rollout coordination. |
| Observability | Syslog and similar collectors help debugging, but losing them should not be treated as the same class of outage as ingress, automation, or storage/export failures. |

Container updates: use `/update-stacks` skill.

## Agent Delegation

Use scoped agents to avoid loading unrelated context into the main conversation.

| Pattern | When | How |
|---------|------|-----|
| `Explore` single stack | Debugging one stack ("why is pihole failing?") | `Task(Explore)` scoped to that stack's directory |
| `Bash` parallel probes | Health checks across stacks | One `Task(Bash)` per stack, run in parallel |
| `Plan` cross-stack | Adding a service, architectural changes | `Task(Plan)` to explore architecture in isolation |

Rules:
- Prefer scoping `Explore` agents to the relevant stack directory when the question targets one stack.
- For single-stack questions, delegate rather than reading all stack files in main context.
- Run independent stack probes in parallel via background `Bash` agents.
- Agents cannot Edit/Write files in submodules (permission denied). Read submodule files in agents, but apply edits from main context.
- Agents are denied Edit/Write on submodule files — do submodule edits from main context, use agents only for read/research tasks.

## Common Commands

| Op | Command |
|----|---------|
| Status | `docker compose ps --format table` |
| Logs | `docker compose logs <svc> --tail 50` |
| Startup order | `network → maestro → infra → smart-home` |
| Syslog (host file) | `tail -100 /srv/homelab/infra-stack/syslog/messages` |
| HASS SMB mount | `sudo mount /mnt/media_home_assistant` |
| HASS SMB verify | `findmnt -T /mnt/media_home_assistant` / `df -T /mnt/media_home_assistant` |

## Learned Behavior

- `smart-home-stack` `file-mover` now expects SMB destination validation by env:
  `FILEMOVER_DEST`, `FILEMOVER_DEST_REQUIRE_MOUNT`, `FILEMOVER_DEST_EXPECTED_FSTYPE`, `FILEMOVER_DEST_EXPECTED_SOURCE`.
- Expected production values for Home Assistant export:
  `FILEMOVER_DEST=/mnt/media_home_assistant`
  `FILEMOVER_DEST_REQUIRE_MOUNT=true`
  `FILEMOVER_DEST_EXPECTED_FSTYPE=cifs`
  `FILEMOVER_DEST_EXPECTED_SOURCE=//media.lan/home-assistant`
- New `file-mover` image versions expose a Docker healthcheck and log `DEST_VALIDATION_OK` when the mount check passes.
- Failure markers to grep for: `DEST_MOUNT_INVALID`, `DEST_FSTYPE_MISMATCH`, `DEST_SOURCE_MISMATCH`.
- If `rcortese/file-mover:latest` was republished, `docker compose up -d` alone may keep the old local image. Pull first, then recreate the service.

## Backlog

Improvement backlog lives in `memory/TODO.md` (Claude auto-memory). Review before large changes.
