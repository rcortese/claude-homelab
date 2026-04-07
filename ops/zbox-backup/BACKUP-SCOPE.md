# Backup Scope

This document defines the exact protection contract for the zbox backup flow.

## Included

### network-stack
- `.env`
- `compose.yaml`
- `compose.zbox.yaml`
- `caddy/`
- `cloudflared/`
- `pihole/`
- `wireguard/`

Snapshot destination:
- `network-stack/...`

### infra-stack
- `.env`
- `compose.yaml`
- `diun/`
- `librespeed/`
- `syslog-ng/`
- `portainer/`

Snapshot destination:
- `infra-stack/config/...`
- `infra-stack/portainer/...`

### smart-home-stack
- `.env`
- `compose.yaml`
- `.ssh/`
- `homeassistant/`
- `mosquitto/`

Snapshot destination:
- `smart-home/config/...`
- `smart-home/homeassistant/...`
- `smart-home/mosquitto/...`

Database consistency:
- MariaDB logical dump created separately
- dump destination: `/mnt/user/backups/zbox/dumps/smart-home-mariadb/`
- current container: `smart-home-mariadb-1`
- database restored from dump, not from raw database files

### homelab-sentinel
- `.env`
- `compose.yaml`
- `alertmanager/`
- `blackbox/`
- `bridge/`
- `gatus/`
- `grafana/`
- `prometheus/`
- `state/`
- `data/alertmanager/`
- `data/gatus/`
- `data/grafana/`
- `data/prometheus/`

Snapshot destination:
- `sentinel/config/...`
- `sentinel/state/...`
- `sentinel/runtime/...`
- `sentinel/metrics/...`

### Host-state metadata
Each snapshot also records discovery artifacts under:
- `host-state/docker-ps.txt`
- `host-state/docker-compose-ls.txt`
- `host-state/docker-volume-ls.txt`
- `host-state/systemd-timers.txt`
- `host-state/systemd-service-files.txt`
- `host-state/findmnt-mnt-user.txt`
- `host-state/metadata.txt`

## Excluded intentionally

These are not protected by this flow today:
- `smart-home-stack/export/`
- `homelab-maestro`

These are treated as lower-value or intentionally deferred:
- large export/output trees that are reconstructable or non-critical
- services not yet prioritized into the recovery plan

## Important model notes

- This backup is designed around the real live state under `/srv/homelab`
- The old `${HOME}`-based legacy flow is retired and not part of the contract
- `latest` is the canonical entry point for the newest usable snapshot
- `current` is legacy compatibility only and must not be treated as canonical state

## Executable truth

The exact runtime contract is defined by:
- `backup-paths.txt`
- `backup-excludes.txt`
- `zbox-backup.conf`

When documentation and config disagree, update the docs immediately after correcting the config.
