# Operations Runbook

## Units and timers

Units:
- `zbox-backup.service`
- `zbox-backup.timer`
- `zbox-backup-validate.service`
- `zbox-backup-validate.timer`

Current cadence:
- backup daily at `03:15`
- validation weekly on Sunday at `04:30`

## Commands

Show timers:

```bash
systemctl list-timers --all | grep -E "zbox-backup|zbox-backup-validate"
```

Run backup now:

```bash
sudo systemctl start zbox-backup.service
```

Run validation now:

```bash
sudo systemctl start zbox-backup-validate.service
```

Follow logs:

```bash
journalctl -u zbox-backup.service -f
journalctl -u zbox-backup-validate.service -f
```

## Output locations

- snapshots: `/mnt/user/backups/zbox/snapshots/`
- latest pointer: `/mnt/user/backups/zbox/latest`
- dumps: `/mnt/user/backups/zbox/dumps/smart-home-mariadb/`
- reports: `/mnt/user/backups/zbox/reports/`
- logs: `/mnt/user/backups/zbox/logs/`

## Retention

Configured today:
- snapshots kept: `14`
- MariaDB dump retention days: `14`

## Troubleshooting

### SSH or auth failures
Check:
- `SSH_KEY_FILE` in `zbox-backup.conf`
- `SSH_KNOWN_HOSTS` in `zbox-backup.conf`
- permissions on the private key
- direct SSH connectivity from zbox to Unraid

### Target validation failures
The backup expects the Unraid destination to resolve under:
- `/mnt/user`
- filesystem type `fuse.shfs`

If this changes, update the validation logic and docs together.

### rsync failures
Check:
- destination path exists and is writable
- remote SSH access still works
- source path still exists
- excluded files are not masking required data unexpectedly

### Freshness validation failures
Check:
- `latest` points to a real snapshot
- snapshot age is within the expected threshold
- critical sample files exist in the snapshot
- the last backup report did not finish early

## Known environment assumptions

- Unraid backup target is mounted under `/mnt/user`
- zbox holds the runtime SSH key locally at `/home/rcortese/.ssh/moss_homelab_ed25519`
- the old legacy `remote-backup` project is gone and must not be reintroduced as an implicit dependency
