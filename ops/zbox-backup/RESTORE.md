# Restore Guide

This is the canonical restore playbook for the zbox backup flow.

## Principles

- Restore from `latest` only after confirming the last validation or report status
- Prefer restoring one stack or component at a time
- Stop affected services before overwriting live state
- Restore MariaDB from logical dump, not from raw container internals
- Preserve permissions and ownership carefully after restore

## Preparation

Useful commands:

```bash
LATEST=$(readlink -f /mnt/user/backups/zbox/latest)
echo "$LATEST"
ls -la /mnt/user/backups/zbox/reports/
ls -la /mnt/user/backups/zbox/dumps/smart-home-mariadb/
```

## network-stack

1. Stop the stack if required.
2. Restore the needed files from `$LATEST/network-stack/`.
3. Recreate or restart the affected services.
4. Validate DNS, reverse proxy, Pi-hole, and WireGuard behavior.

## infra-stack

1. Stop the affected services.
2. Restore from `$LATEST/infra-stack/config/` and `$LATEST/infra-stack/portainer/`.
3. Start the stack again.
4. Validate Portainer access and config-backed services.

## smart-home Home Assistant and Mosquitto

1. Stop the smart-home stack.
2. Restore from `$LATEST/smart-home/config/`, `$LATEST/smart-home/homeassistant/`, and `$LATEST/smart-home/mosquitto/`.
3. Start MariaDB first if needed, then the rest of the stack.
4. Validate Home Assistant login, entity availability, and MQTT connectivity.

## smart-home MariaDB

1. Identify the desired dump file:

```bash
ls -1t /mnt/user/backups/zbox/dumps/smart-home-mariadb/*.sql.gz | head
```

2. Stop services that write heavily to the database.
3. Restore via containerized import flow, for example:

```bash
gzip -dc /mnt/user/backups/zbox/dumps/smart-home-mariadb/<dump>.sql.gz \
  | docker exec -i smart-home-mariadb-1 mariadb -u<user> -p<password> <database>
```

4. Restart dependent services.
5. Validate Home Assistant history and recorder-backed views.

## sentinel-stack

1. Stop sentinel services.
2. Restore `$LATEST/sentinel/config/` into `/srv/homelab/sentinel-stack/`, `sentinel/state/` into its `state/`, `sentinel/runtime/{alertmanager,gatus,grafana}/` into its corresponding `data/` directories, and `sentinel/metrics/prometheus/` into `data/prometheus/`.
3. Restore `$LATEST/sentinel/shield-v2/operational/` to `/srv/homelab/sentinel-runtime/shield-v2/` plus manifest private/state/units. Retain root-only custody; verify full-model digest. Old generations require their original complete vector, never mixed inputs.
4. Use frozen operational Compose and reconciler drop-in after checking Shield guard. Gatus/Prometheus use canonical config.
5. Validate Grafana, Gatus, Prometheus, and Alertmanager.

## Backup guarantees and limits

- Every manifest source is mandatory; missing files/directories fail before remote writes. Retired Diun and the nonexistent smart-home `.ssh` source are no longer claimed as covered. Smart-home Compose is `docker-compose.yml`.
- SQLite files identified by their header are copied using Python's SQLite online backup API, validated with `PRAGMA integrity_check`, and published without live WAL/SHM/journal sidecars. This is per-database consistency, not a coordinated cross-service snapshot. Databases created during discovery/rsync and symlinked databases are not covered by this guarantee.
- Non-SQLite mutable data (Prometheus TSDB, Portainer BoltDB, MQTT persistence, etc.) remains a live rsync copy, not application-consistent recovery proof.
- The validator binds the latest report, timestamped report, snapshot generation and gzip-tested MariaDB dump. Gzip integrity and SQLite integrity are not a full MariaDB import or application restore drill.
- The existing destination/transport and retention policy remain unchanged. Backups contain credentials in plaintext at rest; no encryption, immutability, OS rebuild, Docker image archive, or disaster-recovery completeness is implied.
- Source self-tests: `sudo python3 ops/zbox-backup/test-backup.py`; preflight: `sudo ops/zbox-backup/zbox-backup.sh --check-sources`. No service lifecycle is required for either test.

## Post-restore validation

After any restore, check:
- services are running
- data directories have expected ownership and permissions
- app login works
- expected dashboards, configs, and recent data are visible
- no repeated container crashes appear after startup

## Notes

- If the restore is emergency-only and the repo is unavailable, use the destination-side `RESTORE-QUICKSTART.md`
- If a restore drill is performed, record it in the workspace backup project docs

Shield operational source: two Compose files only; restore guard, egress and deployment.env alongside source/. Retain private/state/unit selections. No SQLite restore for config rollback. Existing backup semantics unchanged.
