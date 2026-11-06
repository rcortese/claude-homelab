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

generation() {
  "${SSH_CMD[@]}" "$REMOTE_TARGET" "python3 - '$1' '$REMOTE_ROOT' '$RUN_TS'" \
    < "$(dirname "${BASH_SOURCE[0]}")/generation.py"
}

load_exclude_patterns() {
  EXCLUDE_PATTERNS=()
  [[ -f "$BACKUP_EXCLUDES_FILE" ]] || return 0
  while IFS= read -r line; do
    [[ -n "${line:-}" ]] || continue
    [[ "$line" == \#* ]] && continue
    EXCLUDE_PATTERNS+=("$line")
  done < "$BACKUP_EXCLUDES_FILE"
}

sync_file() {
  local src="$1"
  local rel="$2"
  [[ -f "$src" ]] || { echo "missing required file: $src" >&2; return 1; }
  local parent
  parent="$(dirname "$rel")"
  mkdir_remote "$REMOTE_SNAPSHOT/$parent"
  log "sync file: $src -> $REMOTE_SNAPSHOT/$parent/" | tee -a "$REPORT_FILE"
  "${RSYNC_CMD[@]}" "$src" "$REMOTE_TARGET:$REMOTE_SNAPSHOT/$rel"
}

sync_dir() {
  local src="$1"
  local rel="$2"
  [[ -d "$src" ]] || { echo "missing required directory: $src" >&2; return 1; }
  mkdir_remote "$REMOTE_SNAPSHOT/$rel"
  log "sync dir: $src -> $REMOTE_SNAPSHOT/$rel/" | tee -a "$REPORT_FILE"
  local -a cmd=("${RSYNC_CMD[@]}")
  local pattern
  for pattern in "${EXCLUDE_PATTERNS[@]:-}"; do
    cmd+=(--exclude="$pattern")
  done
  local sqlite_stage="$LOCAL_STAGING/sqlite/$rel"
  local sqlite_excludes="$LOCAL_STAGING/sqlite-excludes.txt"
  python3 "$(dirname "${BASH_SOURCE[0]}")/sqlite-backup.py" \
    "$src" "$sqlite_stage" "$sqlite_excludes" | tee -a "$REPORT_FILE"
  "${cmd[@]}" --exclude-from="$sqlite_excludes" "$src/" "$REMOTE_TARGET:$REMOTE_SNAPSHOT/$rel/"
  # No --delete here: this overlay contains databases only.
  rsync -aHAX --numeric-ids -e "$SSH_CMD_STR" \
    "$sqlite_stage/" "$REMOTE_TARGET:$REMOTE_SNAPSHOT/$rel/"
}

check_sources() {
  local kind src rel
  [[ -s "$BACKUP_PATHS_FILE" ]] || { echo "missing backup manifest" >&2; return 1; }
  python3 - "$BACKUP_PATHS_FILE" <<'PY'
import pathlib, sys
seen = set()
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    if not line or line.startswith('#'):
        continue
    kind, source, dest = line.split('|')
    p = pathlib.PurePosixPath(dest)
    if (kind not in ('file', 'dir') or not dest or p.is_absolute()
            or '..' in p.parts or dest == '.' or p.parts[0] == '.generation'
            or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-' for c in dest)
            or dest in seen):
        raise ValueError('unsafe or duplicate manifest destination')
    seen.add(dest)
PY
  while IFS='|' read -r kind src rel; do
    [[ -n "$kind" && "$kind" != \#* ]] || continue
    case "$kind" in
      file) [[ -f "$src" ]] ;;
      dir) [[ -d "$src" ]] ;;
      *) echo "invalid manifest kind: $kind" >&2; return 1 ;;
    esac || { echo "missing required $kind: $src" >&2; return 1; }
  done < "$BACKUP_PATHS_FILE"
  [[ -s "$SMART_HOME_ENV_FILE" ]] || { echo "missing database environment" >&2; return 1; }
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

write_status() {
  local dump_size
  dump_size="$(du -h "$DUMP_FILE" | awk '{print $1}')"
  {
    echo "run_ts=$RUN_TS"
    echo "status=captured-pending-validation"
    echo "snapshot=$REMOTE_SNAPSHOT_ROOT/$RUN_TS"
    echo "validation=gzip-sql-structure-sqlite-integrity-and-file-hashes"
    echo "restore_tested=false"
    echo "latest=$REMOTE_LATEST"
    echo "dump_file=.generation/homeassistant.sql.gz"
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
require_cmd python3

: "${REMOTE_HOST:?missing REMOTE_HOST}"
: "${REMOTE_USER:?missing REMOTE_USER}"
: "${REMOTE_BASE:?missing REMOTE_BASE}"
: "${SSH_KEY_FILE:?missing SSH_KEY_FILE}"
: "${SMART_HOME_ENV_FILE:?missing SMART_HOME_ENV_FILE}"
: "${MARIADB_CONTAINER:?missing MARIADB_CONTAINER}"
: "${BACKUP_PATHS_FILE:?missing BACKUP_PATHS_FILE}"
BACKUP_EXCLUDES_FILE="${BACKUP_EXCLUDES_FILE:-/srv/homelab/ops/zbox-backup/backup-excludes.txt}"
check_sources
if [[ "${1:-}" == --check-sources ]]; then
  echo "required sources ok"
  exit 0
fi
umask 077

REMOTE_TARGET="${REMOTE_USER}@${REMOTE_HOST}"
REMOTE_ROOT="${REMOTE_BASE%/}"
REMOTE_SNAPSHOT_ROOT="${REMOTE_ROOT}/snapshots"
[[ "$REMOTE_ROOT" =~ ^/[a-zA-Z0-9_./-]+$ && "$REMOTE_ROOT" != / && "$REMOTE_ROOT" != *'/../'* ]] || {
  echo 'unsafe remote base' >&2; exit 1;
}
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
REMOTE_SNAPSHOT="${REMOTE_ROOT}/attempts/${RUN_TS}"
REMOTE_LATEST="${REMOTE_ROOT}/latest"
REMOTE_CURRENT="${REMOTE_ROOT}/current"
LOCAL_STAGING="${LOCAL_STAGING_ROOT%/}/${RUN_TS}"
REPORT_FILE="${LOCAL_STAGING}/zbox-backup-${RUN_TS}.txt"
STATUS_FILE="${LOCAL_STAGING}/zbox-backup-${RUN_TS}.json"
HOST_STATE_DIR="${LOCAL_STAGING}/host-state"

exec 9>"$LOCK_FILE"
flock -n 9 || { echo "backup already running" >&2; exit 1; }
mkdir -p "${LOCAL_STAGING_ROOT%/}"
mkdir "$LOCAL_STAGING"
trap 'rm -rf -- "$LOCAL_STAGING"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

SSH_CMD=(ssh -i "$SSH_KEY_FILE" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
if [[ -n "${SSH_KNOWN_HOSTS:-}" ]]; then
  SSH_CMD+=( -o "UserKnownHostsFile=$SSH_KNOWN_HOSTS" )
fi
SSH_CMD_STR="$(printf '%q ' "${SSH_CMD[@]}")"
RSYNC_CMD=(rsync -aHAX --numeric-ids --info=stats2 -e "$SSH_CMD_STR")

remote_run "findmnt /mnt/user -n -o TARGET,FSTYPE | grep -q '^/mnt/user[[:space:]]\\+fuse\.shfs'" || {
  echo "remote backup target is not the expected Unraid shfs mount" >&2
  exit 1
}
generation begin
# Freeze the selection and exclusions used for this attempt.
cp "$BACKUP_PATHS_FILE" "$LOCAL_STAGING/backup-paths.txt"
if [[ -f "$BACKUP_EXCLUDES_FILE" ]]; then
  cp "$BACKUP_EXCLUDES_FILE" "$LOCAL_STAGING/backup-excludes.txt"
else
  : > "$LOCAL_STAGING/backup-excludes.txt"
fi
BACKUP_PATHS_FILE="$LOCAL_STAGING/backup-paths.txt"
BACKUP_EXCLUDES_FILE="$LOCAL_STAGING/backup-excludes.txt"

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
load_exclude_patterns
if [[ ${#EXCLUDE_PATTERNS[@]} -gt 0 ]]; then
  printf "exclude_patterns=%s\n" "$(IFS=,; echo "${EXCLUDE_PATTERNS[*]}")" | tee -a "$REPORT_FILE"
fi
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
"${RSYNC_CMD[@]}" "$DUMP_FILE" "$REMOTE_TARGET:$REMOTE_SNAPSHOT/.generation/homeassistant.sql.gz"
# Every generation carries the exact policy inputs and producer provenance.
python3 - "$LOCAL_STAGING/capture.json" "$RUN_TS" "${BASH_SOURCE[0]}" <<'PY'
import hashlib, json, pathlib, subprocess, sys
out, run, script = sys.argv[1:]
script = pathlib.Path(script).resolve()
version = subprocess.run(['git', '-C', str(script.parent), 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True).stdout.strip()
hashes = {name: hashlib.sha256((script.parent / name).read_bytes()).hexdigest()
          for name in ('zbox-backup.sh', 'sqlite-backup.py', 'generation.py')}
pathlib.Path(out).write_text(json.dumps({'run_ts': run, 'producer_commit': version, 'producer_sha256': hashes}))
PY
write_status
for name in backup-paths.txt backup-excludes.txt capture.json; do
  "${RSYNC_CMD[@]}" "$LOCAL_STAGING/$name" "$REMOTE_TARGET:$REMOTE_SNAPSHOT/.generation/$name"
done
"${RSYNC_CMD[@]}" "$REPORT_FILE" "$REMOTE_TARGET:$REMOTE_SNAPSHOT/.generation/report.txt"
"${RSYNC_CMD[@]}" "$STATUS_FILE" "$REMOTE_TARGET:$REMOTE_SNAPSHOT/.generation/status.txt"
generation seal
generation publish
log "zbox backup publication acknowledged; run=$RUN_TS restore_tested=false"
