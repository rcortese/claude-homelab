---
description: Health check all stacks — container status, key service probes, disk
allowed-tools: Bash, Read
---

Run health checks across all stacks. Report results as tables.

## Step 1: Disk overview
```
df -h / --output=pcent,avail | tail -1
docker system df --format "table {{.Type}}\t{{.Size}}\t{{.Reclaimable}}"
```

## Step 2: Container status (per stack, in order)

For each stack below, run `docker compose ps --format table` in the stack directory.
Use the correct compose file per stack:

| Stack | Directory | Compose flag |
|-------|-----------|-------------|
| network-stack | `/srv/homelab/network-stack` | `-f docker-compose.zbox.yml` |
| infra-stack | `/srv/homelab/infra-stack` | (default) |
| homelab-maestro | `/srv/homelab/homelab-maestro` | (default) |
| smart-home-stack | `/srv/homelab/smart-home-stack` | (default) |

Combine into one summary table: `| Stack | Service | State | Health |`

## Step 3: Key service probes

Run these probes and flag failures:

```
# Pi-hole DNS
docker exec pihole dig +short @127.0.0.1 google.com 2>&1 | tail -1

# Home Assistant
curl -sf -o /dev/null -w "%{http_code}" http://127.0.0.1:8123/api/ --max-time 5

# n8n
curl -sf -o /dev/null -w "%{http_code}" http://127.0.0.1:5678/healthz --max-time 5

# MariaDB
docker exec mariadb mysqladmin ping -u root -p"$MARIADB_ROOT_PASSWORD" 2>&1 | tail -1

# Mosquitto
docker exec mosquitto mosquitto_sub -t '$SYS/broker/uptime' -C 1 -W 3 2>&1 | tail -1
```

## Step 4: File-mover check
```
ls /srv/homelab/smart-home-stack/export/camera/ 2>/dev/null | wc -l
```
- 0-1 files: OK
- 2+ files: **WARN** — run `/troubleshoot file-mover` for diagnosis

## Output

One combined table with all results. Flag anything unhealthy.
