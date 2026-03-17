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

## Backlog

Improvement backlog lives in `memory/TODO.md` (Claude auto-memory). Review before large changes.
