---
description: Free disk space on zbox — clears logs, caches, HA backups, Docker, and audits DBs
allowed-tools: Bash, Read
---

Check disk usage and guide cleanup for zbox. Run all steps in order.

## Step 0: Emergency reserve
`/DISK_FULL_DELETE_ME_TO_FREE_1G` is a 1 GB pre-allocated file at the root filesystem. If the disk is 100% full and nothing else works, delete it first to get breathing room:
```
sudo rm /DISK_FULL_DELETE_ME_TO_FREE_1G
```
After cleanup, recreate it:
```
sudo dd if=/dev/zero of=/DISK_FULL_DELETE_ME_TO_FREE_1G bs=1M count=1024 status=none
```

## Step 1: Assess
```
df -h /
docker system df
```
Report free space and Docker reclaimable.

## Step 2: Health checks (flag failures, do not fix)

### file-mover (smart-home-stack)
```
ls /srv/homelab/smart-home-stack/export/camera/ | wc -l
```
- 0-1 files: OK
- 2+ files: **FAIL** — run `/troubleshoot file-mover` for diagnosis

### Pi-hole FTL DB
```
du -sh /srv/homelab/network-stack/pihole/etc-pihole/pihole-FTL.db
```
Flag if over 500MB. FTL DB grows unbounded without retention config (`MAXDBDAYS`).

### gravity_old.db
```
ls /srv/homelab/network-stack/pihole/etc-pihole/gravity_old.db 2>/dev/null
```
Safe to delete if present: `rm /srv/homelab/network-stack/pihole/etc-pihole/gravity_old.db`

## Step 3: DB bloat audit

### MariaDB (smart-home-stack)
```
docker exec mariadb mysql -u root -p"$MARIADB_ROOT_PASSWORD" -e \
  "SELECT table_schema, ROUND(SUM(data_length+index_length)/1024/1024,1) AS MB \
   FROM information_schema.tables GROUP BY table_schema ORDER BY MB DESC;"
```
Flag schemas over 200MB. HA recorder is the usual culprit — suggest setting `purge_keep_days: 30` in HA `configuration.yaml`.

### Postgres (moss-postgres-1)
```
docker exec moss-postgres-1 psql -U postgres -c \
  "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database ORDER BY pg_database_size(datname) DESC;"
```
Flag DBs over 200MB. Run `VACUUM ANALYZE` if bloated.

## Step 4: Safe cleanup (no sudo needed)
- HA backups: `rm /srv/homelab/smart-home-stack/homeassistant/backups/Automatic_backup_*.tar`
- gravity_old: `rm /srv/homelab/network-stack/pihole/etc-pihole/gravity_old.db` (if present)
- Docker: `docker system prune -f` (safe — skips active containers/images)

## Step 5: Privileged cleanup
```
sudo apt clean
sudo journalctl --vacuum-time=7d
sudo find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) -delete
```

## Step 6: Verify
```
df -h /
```
Report before/after delta.
