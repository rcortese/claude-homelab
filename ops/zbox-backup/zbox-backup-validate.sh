#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_FILE="${CONFIG_FILE:-/srv/homelab/ops/zbox-backup/zbox-backup.conf}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd ssh
require_cmd date

: "${REMOTE_HOST:?missing REMOTE_HOST}"
: "${REMOTE_USER:?missing REMOTE_USER}"
: "${REMOTE_BASE:?missing REMOTE_BASE}"
: "${SSH_KEY_FILE:?missing SSH_KEY_FILE}"

REMOTE_TARGET="${REMOTE_USER}@${REMOTE_HOST}"
REMOTE_ROOT="${REMOTE_BASE%/}"
REMOTE_SNAPSHOT_ROOT="${REMOTE_ROOT}/snapshots"
REMOTE_LATEST="${REMOTE_ROOT}/latest"
REMOTE_LOGS="${REMOTE_ROOT}/logs"
REMOTE_REPORTS="${REMOTE_ROOT}/reports"

SSH_CMD=(ssh -i "$SSH_KEY_FILE" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
if [[ -n "${SSH_KNOWN_HOSTS:-}" ]]; then
  SSH_CMD+=( -o "UserKnownHostsFile=$SSH_KNOWN_HOSTS" )
fi

remote_eval() {
  "${SSH_CMD[@]}" "$REMOTE_TARGET" "$1"
}

remote_eval "findmnt /mnt/user -n -o TARGET,FSTYPE | grep -q '^/mnt/user[[:space:]]\\+fuse\.shfs'" || {
  echo "validation failed: remote backup target is not the expected Unraid shfs mount" >&2
  exit 1
}

latest_target="$(remote_eval "readlink -f '$REMOTE_LATEST' 2>/dev/null || true")"
if [[ -z "$latest_target" ]]; then
  echo "validation failed: latest symlink missing" >&2
  exit 1
fi

latest_mtime="$(remote_eval "stat -c %Y '$latest_target' 2>/dev/null || true")"
if [[ -z "$latest_mtime" ]]; then
  echo "validation failed: unable to measure latest snapshot age" >&2
  exit 1
fi
latest_age_hours=$(( ( $(date +%s) - latest_mtime ) / 3600 ))
if (( latest_age_hours > 26 )); then
  echo "validation failed: latest snapshot is ${latest_age_hours}h old" >&2
  exit 1
fi

report_exists="$(remote_eval "test -f '$REMOTE_REPORTS/zbox-backup-latest.txt' && echo yes || echo no")"
if [[ "$report_exists" != "yes" ]]; then
  echo "validation failed: latest report is missing" >&2
  exit 1
fi

snapshot_count="$(remote_eval "find '$REMOTE_SNAPSHOT_ROOT' -mindepth 1 -maxdepth 1 -type d | wc -l")"
if [[ "${snapshot_count:-0}" -lt 1 ]]; then
  echo "validation failed: no snapshots found" >&2
  exit 1
fi

sample_ok="$(remote_eval "test -f '$latest_target/network-stack/.env' && test -f '$latest_target/smart-home/config/.env' && test -f '$latest_target/sentinel/state/sentinel.db' && echo yes || echo no")"
if [[ "$sample_ok" != "yes" ]]; then
  echo "validation failed: critical sample files are missing from latest snapshot" >&2
  exit 1
fi

echo "validation ok"
echo "latest_snapshot=$latest_target"
echo "latest_age_hours=$latest_age_hours"
echo "snapshot_count=$snapshot_count"
