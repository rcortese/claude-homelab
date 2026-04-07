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

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "this script must run as root" >&2
    exit 1
  fi
}

log() {
  printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

mkdir_remote() {
  local dir="$1"
  "${SSH_CMD[@]}" "$REMOTE_TARGET" "mkdir -p '$dir'"
}

remote_run() {
  "${SSH_CMD[@]}" "$REMOTE_TARGET" "$1"
}

sync_file() {
  local src="$1"
  local rel="$2"
  [[ -f "$src" ]] || return 0
  local parent
  parent="$(dirname "$rel")"
  mkdir_remote "$REMOTE_SNAPSHOT/$parent"
  log "sync file: $src -> $REMOTE_SNAPSHOT/$parent/" | tee -a "$REPORT_FILE"
  "${RSYNC_CMD[@]}" "$src" "$REMOTE_TARGET:$REMOTE_SNAPSHOT/$parent/"
}

sync_dir() {
  local src="$1"
  local rel="$2"
  [[ -d "$src" ]] || return 0
  mkdir_remote "$REMOTE_SNAPSHOT/$rel"
  log "sync dir: $src -> $REMOTE_SNAPSHOT/$rel/" | tee -a "$REPORT_FILE"
  "${RSYNC_CMD[@]}" "$src/" "$REMOTE_TARGET:$REMOTE_SNAPSHOT/$rel/"
}

capture_host_state() {
  mkdir -p "$HOST_STATE_DIR"
  {
    echo "run_ts=$RUN_TS"
    echo "host=$(hostname)"
    date -u
    uname -a
  } > "$HOST_STATE_DIR/metadata.txt"
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' > "$HOST_STATE_DIR/docker-ps.txt" || true
  docker volume ls > "$HOST_STATE_DIR/docker-volume-ls.txt" || true
  docker compose ls --all > "$HOST_STATE_DIR/docker-compose-ls.txt" 2>&1 || true
  systemctl list-timers --all --no-pager > "$HOST_STATE_DIR/systemd-timers.txt" || true
  systemctl list-unit-files --type=service --no-pager > "$HOST_STATE_DIR/systemd-service-files.txt" || true
  findmnt -rn -o TARGET,SOURCE,FSTYPE,OPTIONS /mnt/user > "$HOST_STATE_DIR/findmnt-mnt-user.txt" 2>&1 || true
}

load_backup_paths() {
  [[ -f "$BACKUP_PATHS_FILE" ]] || {
    echo "missing backup paths file: $BACKUP_PATHS_FILE" >&2
    exit 1
  }
  mapfile -t BACKUP_PATH_LINES < "$BACKUP_PATHS_FILE"
  for line in "${BACKUP_PATH_LINES[@]}"; do
    [[ -n "${line:-}" ]] || continue
    [[ "$line" == \#* ]] && continue
    IFS='|' read -r kind src rel <<< "$line"
    case "$kind" in
      file) sync_file "$src" "$rel" ;;
      dir) sync_dir "$src" "$rel" ;;
      *) echo "unknown backup kind in $BACKUP_PATHS_FILE: $kind" >&2; exit 1 ;;
    esac
  done
}

prune_snapshots() {
  local keep="${SNAPSHOT_KEEP:-14}"
  remote_run "cd '$REMOTE_SNAPSHOT_ROOT' && ls -1dt [0-9]* 2>/dev/null | tail -n +$((keep + 1)) | xargs -r -I{} rm -rf -- '$REMOTE_SNAPSHOT_ROOT/{}'"
}

write_status() {
  local dump_size
  dump_size="$(du -h "$DUMP_FILE" | awk '{print $1}')"
  {
    echo "run_ts=$RUN_TS"
    echo "status=success"
    echo "snapshot=$REMOTE_SNAPSHOT"
    echo "latest=$REMOTE_LATEST"
    echo "dump_file=$(basename "$DUMP_FILE")"
    echo "dump_size=$dump_size"
  } | tee -a "$REPORT_FILE" > "$STATUS_FILE"
}

require_root
require_cmd rsync
require_cmd ssh
require_cmd docker
require_cmd gzip
require_cmd find
require_cmd awk
require_cmd du
require_cmd flock

: "${REMOTE_HOST:?missing REMOTE_HOST}"
: "${REMOTE_USER:?missing REMOTE_USER}"
: "${REMOTE_BASE:?missing REMOTE_BASE}"
: "${SSH_KEY_FILE:?missing SSH_KEY_FILE}"
: "${SMART_HOME_ENV_FILE:?missing SMART_HOME_ENV_FILE}"
: "${MARIADB_CONTAINER:?missing MARIADB_CONTAINER}"
: "${BACKUP_PATHS_FILE:?missing BACKUP_PATHS_FILE}"

REMOTE_TARGET="${REMOTE_USER}@${REMOTE_HOST}"
REMOTE_ROOT="${REMOTE_BASE%/}"
REMOTE_SNAPSHOT_ROOT="${REMOTE_ROOT}/snapshots"
REMOTE_DUMPS="${REMOTE_ROOT}/dumps/smart-home-mariadb"
REMOTE_REPORTS="${REMOTE_ROOT}/reports"
REMOTE_LOGS="${REMOTE_ROOT}/logs"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
REMOTE_SNAPSHOT="${REMOTE_SNAPSHOT_ROOT}/${RUN_TS}"
REMOTE_LATEST="${REMOTE_ROOT}/latest"
REMOTE_CURRENT="${REMOTE_ROOT}/current"
LOCAL_STAGING="${LOCAL_STAGING_ROOT%/}/${RUN_TS}"
REPORT_FILE="${LOCAL_STAGING}/zbox-backup-${RUN_TS}.txt"
STATUS_FILE="${LOCAL_STAGING}/zbox-backup-${RUN_TS}.json"
HOST_STATE_DIR="${LOCAL_STAGING}/host-state"

mkdir -p "$LOCAL_STAGING"
trap 'rm -rf "$LOCAL_STAGING"' EXIT

exec 9>"$LOCK_FILE"
flock -n 9 || { echo "backup already running" >&2; exit 1; }

SSH_CMD=(ssh -i "$SSH_KEY_FILE" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
if [[ -n "${SSH_KNOWN_HOSTS:-}" ]]; then
  SSH_CMD+=( -o "UserKnownHostsFile=$SSH_KNOWN_HOSTS" )
fi
SSH_CMD_STR="$(printf '%q ' "${SSH_CMD[@]}")"
RSYNC_CMD=(rsync -aHAX --numeric-ids --delete --info=stats2 -e "$SSH_CMD_STR")

mkdir_remote "$REMOTE_SNAPSHOT_ROOT"
mkdir_remote "$REMOTE_DUMPS"
mkdir_remote "$REMOTE_REPORTS"
mkdir_remote "$REMOTE_LOGS"
remote_run "findmnt /mnt/user -n -o TARGET,FSTYPE | grep -q '^/mnt/user[[:space:]]\\+fuse\.shfs'" || {
  echo "remote backup target is not the expected Unraid shfs mount" >&2
  exit 1
}

log "starting zbox backup run $RUN_TS" | tee "$REPORT_FILE"
{
  echo "run_ts=$RUN_TS"
  echo "host=$(hostname)"
  echo "remote_root=$REMOTE_ROOT"
  echo "remote_snapshot=$REMOTE_SNAPSHOT"
  echo "remote_latest=$REMOTE_LATEST"
  echo "remote_current=$REMOTE_CURRENT"
} | tee -a "$REPORT_FILE"

echo >> "$REPORT_FILE"
echo "[stateful paths]" | tee -a "$REPORT_FILE"
load_backup_paths

capture_host_state
mkdir_remote "$REMOTE_SNAPSHOT/host-state"
"${RSYNC_CMD[@]}" "$HOST_STATE_DIR/" "$REMOTE_TARGET:$REMOTE_SNAPSHOT/host-state/"

echo >> "$REPORT_FILE"
echo "[smart-home mariadb dump]" | tee -a "$REPORT_FILE"
set -a
# shellcheck disable=SC1090
source "$SMART_HOME_ENV_FILE"
set +a
DUMP_FILE="${LOCAL_STAGING}/homeassistant-${RUN_TS}.sql"
log "dump database: $MARIADB_DATABASE from $MARIADB_CONTAINER" | tee -a "$REPORT_FILE"
docker exec "$MARIADB_CONTAINER" mariadb-dump \
  --single-transaction \
  --routines \
  --triggers \
  -u"$MARIADB_USER" \
  -p"$MARIADB_PASSWORD" \
  "$MARIADB_DATABASE" > "$DUMP_FILE"
gzip -f "$DUMP_FILE"
DUMP_FILE="${DUMP_FILE}.gz"
"${RSYNC_CMD[@]}" "$DUMP_FILE" "$REMOTE_TARGET:$REMOTE_DUMPS/"
remote_run "find '$REMOTE_DUMPS' -type f -name '*.sql.gz' -mtime +${DUMP_RETENTION_DAYS:-14} -delete"

write_status
cp "$REPORT_FILE" "$LOCAL_STAGING/zbox-backup-latest.txt"
"${RSYNC_CMD[@]}" "$REPORT_FILE" "$REMOTE_TARGET:$REMOTE_REPORTS/"
"${RSYNC_CMD[@]}" "$STATUS_FILE" "$REMOTE_TARGET:$REMOTE_REPORTS/"
"${RSYNC_CMD[@]}" "$REPORT_FILE" "$REMOTE_TARGET:$REMOTE_LOGS/"
"${RSYNC_CMD[@]}" "$STATUS_FILE" "$REMOTE_TARGET:$REMOTE_LOGS/"
remote_run "mkdir -p '$REMOTE_SNAPSHOT_ROOT' && ln -sfn 'snapshots/$RUN_TS' '$REMOTE_LATEST' && ln -sfn 'snapshots/$RUN_TS' '$REMOTE_CURRENT'"
prune_snapshots
log "zbox backup run finished successfully" | tee -a "$REPORT_FILE"
