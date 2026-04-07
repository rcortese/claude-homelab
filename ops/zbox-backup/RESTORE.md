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

## homelab-sentinel

1. Stop sentinel services.
2. Restore from `$LATEST/sentinel/config/`, `$LATEST/sentinel/state/`, `$LATEST/sentinel/runtime/`, and `$LATEST/sentinel/metrics/`.
3. Start the stack again.
4. Validate Grafana, Gatus, Prometheus, and Alertmanager.

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
