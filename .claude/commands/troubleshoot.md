---
description: Diagnose a service issue — logs, connectivity, known problems
allowed-tools: Bash, Read, Grep, Glob
---

# Troubleshoot Service

**Argument:** `$ARGUMENTS` should be a service name (e.g., `pihole`, `caddy`, `homeassistant`, `n8n`, `mariadb`, `mosquitto`, `deconz`, `file-mover`, `portainer`, `diun`, `syslog-ng`).

If no argument, ask the user which service to troubleshoot.

## Service-to-stack mapping

| Service | Stack | Compose flag |
|---------|-------|-------------|
| pihole, caddy, wireguard, cloudflared, cloudflare-ddns | network-stack | `-f docker-compose.zbox.yml` |
| portainer, diun, syslog-ng, librespeed | infra-stack | (default) |
| homeassistant, mariadb, mosquitto, deconz, file-mover | smart-home-stack | (default) |
| n8n, moss-postgres-1, moss-redis-1, adminer | homelab-maestro | (default) |

## Step 1: Read the stack's CLAUDE.md
Read the CLAUDE.md in the stack directory for stack-specific troubleshooting steps. Follow any documented procedures first.

## Step 2: Container state
```
cd /srv/homelab/<stack-dir>
docker compose <compose-flag> ps <service> --format table
```

If not running, check for restart loops:
```
docker inspect <service> --format '{{.RestartCount}} restarts, last exit: {{.State.ExitCode}}' 2>&1
```

## Step 3: Recent logs
```
docker compose <compose-flag> logs <service> --tail 50 2>&1
```
Look for: errors, connection refused, permission denied, OOM, config parse failures.

## Step 4: Known issues checklist

### Pi-hole
- DNS not resolving → check macvlan: `ip addr show lan0`
- FTL DB bloated → `du -sh pihole/etc-pihole/pihole-FTL.db`

### Caddy
- TLS failures → check cloudflared is running + `CLOUDFLARE_TOKEN` in `.env`
- 502 errors → check upstream service is running on expected port

### Home Assistant
- DB connection → `docker exec mariadb mysqladmin ping -u root -p"$MARIADB_ROOT_PASSWORD" 2>&1 | tail -1`
- Zigbee issues → check deCONZ container + ConBee USB: `ls /dev/ttyACM*`

### file-mover
- Stuck files → `ls /srv/homelab/smart-home-stack/export/camera/ | wc -l` (2+ = SMB down)
- SMB unreachable → `docker logs file-mover --tail 30`

### n8n
- Health check → `curl -sf http://127.0.0.1:5678/healthz --max-time 5`
- DB connection → `docker exec moss-postgres-1 pg_isready -U postgres 2>&1`

### Mosquitto
- MQTT connectivity → `docker exec mosquitto mosquitto_sub -t '$SYS/broker/uptime' -C 1 -W 3`

## Step 5: Report
Table format: `| Check | Result | Action needed |`
