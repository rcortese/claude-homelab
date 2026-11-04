#!/usr/bin/env bash
set -Eeuo pipefail
CONFIG_FILE="${CONFIG_FILE:-/srv/homelab/ops/zbox-backup/zbox-backup.conf}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi
: "${REMOTE_HOST:?missing REMOTE_HOST}"
: "${REMOTE_USER:?missing REMOTE_USER}"
: "${REMOTE_BASE:?missing REMOTE_BASE}"
: "${SSH_KEY_FILE:?missing SSH_KEY_FILE}"
REMOTE_ROOT="${REMOTE_BASE%/}"
[[ "$REMOTE_ROOT" =~ ^/[a-zA-Z0-9_./-]+$ && "$REMOTE_ROOT" != / && "$REMOTE_ROOT" != *'/../'* ]] || {
  echo 'unsafe remote base' >&2; exit 1;
}
SSH_CMD=(ssh -i "$SSH_KEY_FILE" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
if [[ -n "${SSH_KNOWN_HOSTS:-}" ]]; then
  SSH_CMD+=(-o "UserKnownHostsFile=$SSH_KNOWN_HOSTS")
fi
REMOTE_TARGET="${REMOTE_USER}@${REMOTE_HOST}"
"${SSH_CMD[@]}" "$REMOTE_TARGET" "findmnt /mnt/user -n -o TARGET,FSTYPE | grep -q '^/mnt/user[[:space:]]\\+fuse\.shfs'"
# Capture a relative identity, not mtime/readlink -f over the user share.
# The helper rechecks latest against that identity before validating.
target="$("${SSH_CMD[@]}" "$REMOTE_TARGET" "readlink '$REMOTE_ROOT/latest'")"
[[ "$target" =~ ^snapshots/([0-9]{8}T[0-9]{6}Z)$ ]] || {
  echo 'validation failed: unexpected latest target' >&2; exit 1;
}
run_ts="${BASH_REMATCH[1]}"
"${SSH_CMD[@]}" "$REMOTE_TARGET" "python3 - latest '$REMOTE_ROOT' '$run_ts'" \
  < "$(dirname "${BASH_SOURCE[0]}")/generation.py"
echo "validation ok: coherent generation=$run_ts; restore_tested=false"
