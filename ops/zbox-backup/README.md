# zbox Backup

Centralized backup flow for the zbox host.

This backup protects the live production state under `/srv/homelab` and writes backup artifacts to Unraid under `/mnt/user/backups/zbox`.

## Overview

The backup model is:
- path-preserving `rsync` copies for filesystem state
- logical MariaDB dumps for the smart-home database
- dated snapshots under `snapshots/<timestamp>/`
- `latest` symlink as the canonical pointer to the newest successful snapshot
- `systemd` timers for scheduled backup and scheduled validation

## Source of truth

Operational source of truth:
- tooling: `/srv/homelab/ops/zbox-backup`
- source data: `/srv/homelab/...`
- backup destination: `/mnt/user/backups/zbox`

Legacy notes:
- the old `${HOME}`-based `remote-backup` project was removed
- `current/` exists only as a legacy compatibility path
- `snapshots/ + latest` is the current source of truth

## Destination layout

- `/mnt/user/backups/zbox/snapshots/<timestamp>/` - dated filesystem snapshots
- `/mnt/user/backups/zbox/latest` - symlink to the latest successful snapshot
- `/mnt/user/backups/zbox/dumps/smart-home-mariadb/` - MariaDB logical dumps
- `/mnt/user/backups/zbox/reports/` - human-readable and JSON run summaries
- `/mnt/user/backups/zbox/logs/` - execution logs

## Included backup areas

High-level included scope:
- `network-stack`
- `infra-stack` config and Portainer data
- `smart-home-stack` config, Home Assistant, Mosquitto, and MariaDB dumps
- `homelab-sentinel` config, state, runtime data, and Prometheus metrics
- host-state metadata captured per snapshot

See `BACKUP-SCOPE.md` for the exact contract.

## Scheduling

Installed `systemd` units:
- `zbox-backup.service`
- `zbox-backup.timer`
- `zbox-backup-validate.service`
- `zbox-backup-validate.timer`

Current schedule:
- backup: daily at `03:15` with randomized delay
- validation: weekly on Sunday at `04:30` with randomized delay

## Key files

- `zbox-backup.conf` - runtime configuration
- `backup-paths.txt` - exact included paths mapped into the snapshot
- `backup-excludes.txt` - rsync exclusions
- `zbox-backup.sh` - backup entrypoint
- `zbox-backup-validate.sh` - freshness and structure validation
- `systemd/` - repo-managed unit files

## Manual commands

Run a backup now:

```bash
sudo /srv/homelab/ops/zbox-backup/zbox-backup.sh
```

Run validation now:

```bash
sudo /srv/homelab/ops/zbox-backup/zbox-backup-validate.sh
```

Inspect timers:

```bash
systemctl list-timers --all | grep -E "zbox-backup|zbox-backup-validate"
```

Inspect backup logs:

```bash
journalctl -u zbox-backup.service -n 100 --no-pager
journalctl -u zbox-backup-validate.service -n 100 --no-pager
```

Inspect destination:

```bash
readlink -f /mnt/user/backups/zbox/latest
find "$(readlink -f /mnt/user/backups/zbox/latest)" -maxdepth 2 -mindepth 1 | sort
```

## Further docs

- `BACKUP-SCOPE.md`
- `RESTORE.md`
- `OPERATIONS.md`
