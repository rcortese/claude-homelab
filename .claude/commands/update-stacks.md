---
description: Pull and update containers across all stacks in dependency order
allowed-tools: Bash, Read
---

Update containers across all stacks. Follow the strict order below. **Stop immediately on any rate-limit or timeout error.**

## Rules
- One attempt per stack. Do not retry on failure.
- On rate limit (`toomanyrequests`, `429`, `Too Many Requests`), stop and report which stacks remain.
- On timeout, stop and report.
- Pipe output through `| tail` as per project rules.

## Update order

Process stacks sequentially in this exact order:

### 1. network-stack
```
cd /srv/homelab/network-stack
docker compose -f docker-compose.zbox.yml pull --quiet 2>&1 | tail -5
docker compose -f docker-compose.zbox.yml up -d 2>&1 | tail -10
```
**Note:** Caddy uses a local build — do not pull it. If Caddy base image needs updating, use `/rebuild-caddy` instead.

### 2. infra-stack
```
cd /srv/homelab/infra-stack
docker compose pull --quiet 2>&1 | tail -5
docker compose up -d 2>&1 | tail -10
```

### 3. homelab-maestro
```
cd /srv/homelab/homelab-maestro
docker compose pull --quiet 2>&1 | tail -5
docker compose up -d 2>&1 | tail -10
```

### 4. smart-home-stack
```
cd /srv/homelab/smart-home-stack
docker compose pull --quiet 2>&1 | tail -5
docker compose up -d 2>&1 | tail -10
```

## Post-update

After all stacks complete, run a quick status check:
```
docker ps --format "table {{.Names}}\t{{.Status}}" | sort
```

Report: `| Stack | Result | Notes |`
