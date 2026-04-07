# zbox Backup

Centralized zbox backup flow for the homelab.

## Goal

Back up the live production state under `/srv/homelab` into Unraid over SSH, using:
- rsync for directory-shaped state
- logical MariaDB dumps for the smart-home database
- systemd for scheduling

## Current rollout scope

Included in the first rollout:
- `network-stack`
- `infra-stack` config and Portainer data
- `smart-home-stack` Home Assistant config, Mosquitto data, stack config, and MariaDB logical dumps
- `homelab-sentinel` config, state, Grafana/Gatus/Alertmanager runtime, and Prometheus metrics

Excluded from the first rollout:
- `infra-stack/syslog/`
- `smart-home-stack/export/`
- `homelab-maestro`
- the old `${HOME}`-based `remote-backup` tar workflow

## Layout on Unraid

- `/mnt/user/backups/zbox/current/...`
- `/mnt/user/backups/zbox/dumps/smart-home-mariadb/...`
- `/mnt/user/backups/zbox/reports/...`

## Files

- `zbox-backup.conf` - runtime configuration
- `zbox-backup.sh` - backup entrypoint
- `systemd/zbox-backup.service` - oneshot service
- `systemd/zbox-backup.timer` - daily schedule

## Manual run

```bash
sudo /srv/homelab/ops/zbox-backup/zbox-backup.sh
```

## Install or refresh the timer

```bash
sudo ln -sf /srv/homelab/ops/zbox-backup/systemd/zbox-backup.service /etc/systemd/system/zbox-backup.service
sudo ln -sf /srv/homelab/ops/zbox-backup/systemd/zbox-backup.timer /etc/systemd/system/zbox-backup.timer
sudo systemctl daemon-reload
sudo systemctl enable --now zbox-backup.timer
```

## Validation

After the first run, verify:
- `journalctl -u zbox-backup.service`
- new files under `/mnt/user/backups/zbox/current/`
- new MariaDB dump under `/mnt/user/backups/zbox/dumps/smart-home-mariadb/`
- latest report under `/mnt/user/backups/zbox/reports/`
