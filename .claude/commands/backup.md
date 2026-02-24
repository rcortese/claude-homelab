---
description: Backup a stack's persistent data (stop → copy → restart)
allowed-tools: Bash, Read
---

# Backup Stack Data

**Argument:** `$ARGUMENTS` should be a stack name: `network-stack`, `infra-stack`, `smart-home-stack`, or `homelab-maestro`.

If no argument provided, ask the user which stack to back up.

## Critical data by stack

| Stack | Data paths | Approx size |
|-------|-----------|-------------|
| `network-stack` | `pihole/etc-pihole/`, `wireguard/` | 20-50 MB |
| `infra-stack` | `portainer/portainer.db` | ~1 MB |
| `smart-home-stack` | `homeassistant/`, `mariadb/data/`, `deconz/zll.db` | 150-700 MB |
| `homelab-maestro` | Use `scripts/backup.sh core` instead (has stop/restart logic) | 120 MB-1 GB |

## For homelab-maestro

Maestro has its own backup script with proper stop/restart ordering:
```
cd /srv/homelab/homelab-maestro
./scripts/backup.sh core 2>&1 | tail -20
```
Report the backup path from output.

## For other stacks

### Step 1: Create backup directory
```
STACK="<stack-name>"
BACKUP_DIR="/srv/homelab/backups/${STACK}-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
```

### Step 2: Stop the stack (ask user first)
Ask user for confirmation before stopping services.
```
cd /srv/homelab/$STACK
docker compose ps --format table
docker compose stop 2>&1 | tail -5
```

### Step 3: Copy data
Copy the relevant data paths from the table above into `$BACKUP_DIR`:
```
cp -a <data-path> "$BACKUP_DIR/" 2>&1 | tail -3
```

### Step 4: Restart
```
docker compose up -d 2>&1 | tail -10
```

### Step 5: Verify
```
docker compose ps --format table
du -sh "$BACKUP_DIR"
```

Report: backup path, size, and container status after restart.
