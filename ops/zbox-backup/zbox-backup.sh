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

sync_file() {
  local src="$1"
  local rel="$2"
  [[ -f "$src" ]] || return 0
  local parent="$(dirname "$rel")"
  mkdir_remote "$REMOTE_CURRENT/$parent"
  log "sync file: $src -> $REMOTE_CURRENT/$parent/" | tee -a "$REPORT_FILE"
  "${RSYNC_CMD[@]}" "$src" "$REMOTE_TARGET:$REMOTE_CURRENT/$parent/"
}

sync_dir() {
  local src="$1"
  local rel="$2"
  [[ -d "$src" ]] || return 0
  mkdir_remote "$REMOTE_CURRENT/$rel"
  log "sync dir: $src -> $REMOTE_CURRENT/$rel/" | tee -a "$REPORT_FILE"
  "${RSYNC_CMD[@]}" "$src/" "$REMOTE_TARGET:$REMOTE_CURRENT/$rel/"
}

require_root
require_cmd rsync
require_cmd ssh
require_cmd docker
require_cmd gzip
require_cmd find
require_cmd awk
require_cmd du

: "${REMOTE_HOST:?missing REMOTE_HOST}"
: "${REMOTE_USER:?missing REMOTE_USER}"
: "${REMOTE_BASE:?missing REMOTE_BASE}"
: "${SSH_KEY_FILE:?missing SSH_KEY_FILE}"
: "${SMART_HOME_ENV_FILE:?missing SMART_HOME_ENV_FILE}"
: "${MARIADB_CONTAINER:?missing MARIADB_CONTAINER}"

REMOTE_TARGET="${REMOTE_USER}@${REMOTE_HOST}"
REMOTE_CURRENT="${REMOTE_BASE%/}/current"
REMOTE_DUMPS="${REMOTE_BASE%/}/dumps/smart-home-mariadb"
REMOTE_REPORTS="${REMOTE_BASE%/}/reports"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"
LOCAL_STAGING="${LOCAL_STAGING_ROOT%/}/${RUN_TS}"
REPORT_FILE="${LOCAL_STAGING}/zbox-backup-${RUN_TS}.txt"
LATEST_REPORT="${LOCAL_STAGING}/zbox-backup-latest.txt"

mkdir -p "$LOCAL_STAGING"
trap 'rm -rf "$LOCAL_STAGING"' EXIT

SSH_CMD=(ssh -i "$SSH_KEY_FILE" -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
if [[ -n "${SSH_KNOWN_HOSTS:-}" ]]; then
  SSH_CMD+=( -o "UserKnownHostsFile=$SSH_KNOWN_HOSTS" )
fi
SSH_CMD_STR="$(printf '%q ' "${SSH_CMD[@]}")"
RSYNC_CMD=(rsync -aH --numeric-ids --delete -e "$SSH_CMD_STR")

log "starting zbox backup run $RUN_TS" | tee "$REPORT_FILE"
mkdir_remote "$REMOTE_CURRENT"
mkdir_remote "$REMOTE_DUMPS"
mkdir_remote "$REMOTE_REPORTS"

echo >> "$REPORT_FILE"
echo "[network-stack]" | tee -a "$REPORT_FILE"
sync_file /srv/homelab/network-stack/.env network-stack/.env
sync_file /srv/homelab/network-stack/compose.yaml network-stack/compose.yaml
sync_file /srv/homelab/network-stack/compose.zbox.yaml network-stack/compose.zbox.yaml
sync_dir /srv/homelab/network-stack/caddy network-stack/caddy
sync_dir /srv/homelab/network-stack/cloudflared network-stack/cloudflared
sync_dir /srv/homelab/network-stack/pihole network-stack/pihole
sync_dir /srv/homelab/network-stack/wireguard network-stack/wireguard

echo >> "$REPORT_FILE"
echo "[infra-stack]" | tee -a "$REPORT_FILE"
sync_file /srv/homelab/infra-stack/.env infra-stack/config/.env
sync_file /srv/homelab/infra-stack/compose.yaml infra-stack/config/compose.yaml
sync_dir /srv/homelab/infra-stack/diun infra-stack/config/diun
sync_dir /srv/homelab/infra-stack/librespeed infra-stack/config/librespeed
sync_dir /srv/homelab/infra-stack/syslog-ng infra-stack/config/syslog-ng
sync_dir /srv/homelab/infra-stack/portainer infra-stack/portainer

echo >> "$REPORT_FILE"
echo "[smart-home-stack]" | tee -a "$REPORT_FILE"
sync_file /srv/homelab/smart-home-stack/.env smart-home/config/.env
sync_file /srv/homelab/smart-home-stack/compose.yaml smart-home/config/compose.yaml
sync_dir /srv/homelab/smart-home-stack/.ssh smart-home/config/.ssh
sync_dir /srv/homelab/smart-home-stack/homeassistant smart-home/homeassistant
sync_dir /srv/homelab/smart-home-stack/mosquitto smart-home/mosquitto

echo >> "$REPORT_FILE"
echo "[homelab-sentinel]" | tee -a "$REPORT_FILE"
sync_file /srv/homelab/homelab-sentinel/.env sentinel/config/.env
sync_file /srv/homelab/homelab-sentinel/compose.yaml sentinel/config/compose.yaml
sync_dir /srv/homelab/homelab-sentinel/alertmanager sentinel/config/alertmanager
sync_dir /srv/homelab/homelab-sentinel/blackbox sentinel/config/blackbox
sync_dir /srv/homelab/homelab-sentinel/bridge sentinel/config/bridge
sync_dir /srv/homelab/homelab-sentinel/gatus sentinel/config/gatus
sync_dir /srv/homelab/homelab-sentinel/grafana sentinel/config/grafana
sync_dir /srv/homelab/homelab-sentinel/prometheus sentinel/config/prometheus
sync_dir /srv/homelab/homelab-sentinel/state sentinel/state
sync_dir /srv/homelab/homelab-sentinel/data/alertmanager sentinel/runtime/alertmanager
sync_dir /srv/homelab/homelab-sentinel/data/gatus sentinel/runtime/gatus
sync_dir /srv/homelab/homelab-sentinel/data/grafana sentinel/runtime/grafana
sync_dir /srv/homelab/homelab-sentinel/data/prometheus sentinel/metrics/prometheus

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
"${SSH_CMD[@]}" "$REMOTE_TARGET" "find '$REMOTE_DUMPS' -type f -name '*.sql.gz' -mtime +${DUMP_RETENTION_DAYS:-14} -delete"
DUMP_SIZE="$(du -h "$DUMP_FILE" | awk '{print $1}')"
echo "dump_file=$(basename "$DUMP_FILE")" | tee -a "$REPORT_FILE"
echo "dump_size=$DUMP_SIZE" | tee -a "$REPORT_FILE"

echo >> "$REPORT_FILE"
echo "status=success" | tee -a "$REPORT_FILE"
cp "$REPORT_FILE" "$LATEST_REPORT"
"${RSYNC_CMD[@]}" "$REPORT_FILE" "$REMOTE_TARGET:$REMOTE_REPORTS/"
"${RSYNC_CMD[@]}" "$LATEST_REPORT" "$REMOTE_TARGET:$REMOTE_REPORTS/"
log "zbox backup run finished successfully" | tee -a "$REPORT_FILE"
