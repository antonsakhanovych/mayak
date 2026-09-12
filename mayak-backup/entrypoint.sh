#!/usr/bin/env bash
# mayak backup sidecar: pause world saves, snapshot /data to restic (cloud),
# prune, resume saves. Loops on BACKUP_INTERVAL.
# Run with --once for a single cycle (used by `make backup`).
set -euo pipefail

: "${RESTIC_PASSWORD:?}"
: "${RESTIC_REPOSITORY:?}"
: "${RCON_PASSWORD:?}"

RCON_HOST="${RCON_HOST:-server}"
RCON_PORT="${RCON_PORT:-25575}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-3600}"
BACKUP_STARTUP_DELAY="${BACKUP_STARTUP_DELAY:-60}"
RETENTION_HOURLY="${RETENTION_HOURLY:-24}"
RETENTION_DAILY="${RETENTION_DAILY:-7}"
RETENTION_WEEKLY="${RETENTION_WEEKLY:-4}"

DATA_DIR="/data"
BACKUP_TAG="mayak"
BACKUP_HOST="${BACKUP_HOSTNAME:-mayak}"

log() { printf '%s [backup] %s\n' "$(date -u +%FT%TZ)" "$*"; }

rcon() { rcon-cli --host "$RCON_HOST" --port "$RCON_PORT" --password "$RCON_PASSWORD" "$@"; }

ensure_repo() {
  local repo="$1"
  if restic -r "$repo" cat config >/dev/null 2>&1; then
    return 0
  fi
  log "initializing restic repo: $repo"
  restic -r "$repo" init
}

backup_to() {
  local repo="$1"
  log "backup -> $repo"
  restic -r "$repo" backup --host "$BACKUP_HOST" --tag "$BACKUP_TAG" "$DATA_DIR"
  log "forget/prune -> $repo"
  restic -r "$repo" forget --host "$BACKUP_HOST" --tag "$BACKUP_TAG" \
    --keep-hourly "$RETENTION_HOURLY" \
    --keep-daily "$RETENTION_DAILY" \
    --keep-weekly "$RETENTION_WEEKLY" \
    --prune
}

run_once() {
  local saves_paused=0

  if rcon save-off >/dev/null 2>&1 && rcon save-all flush >/dev/null 2>&1; then
    saves_paused=1
    sync
    sleep 2
  else
    log "WARN: could not pause saves via RCON; backing up live files"
  fi
  # always resume saves, even if a backup step fails
  trap 'if [ "$saves_paused" = 1 ]; then rcon save-on >/dev/null 2>&1 || true; fi' RETURN

  if ensure_repo "$RESTIC_REPOSITORY"; then
    backup_to "$RESTIC_REPOSITORY" || log "ERROR: cloud backup failed"
  else
    log "ERROR: cloud repo unreachable; skipping cloud backup"
  fi
}

case "${1:-}" in
  "")        ;;                      # no args: fall through to the backup loop
  --once)    run_once; exit 0 ;;     # single cycle (make backup)
  *)         exec "$@" ;;            # anything else: run it verbatim (make restore, debugging)
esac

log "starting; interval=${BACKUP_INTERVAL}s, startup delay=${BACKUP_STARTUP_DELAY}s"
sleep "$BACKUP_STARTUP_DELAY"
while true; do
  run_once || log "ERROR: backup cycle failed"
  log "sleeping ${BACKUP_INTERVAL}s"
  sleep "$BACKUP_INTERVAL"
done
