#!/usr/bin/env bash
# Push the mayak project to a host with rsync. Run this ON THE DEV MACHINE.
# It only transfers files - it starts nothing. Afterwards, run `make deploy`
# on the target host.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
sync the mayak project to a host (rsync only, no remote commands)

usage: ./sync.sh [-n] [user@host] [remote_dir]

  -n            dry run: show what rsync would transfer, then stop
  -h            this help

  user@host     target (default: $MAYAK_HOST, else asakh@raspberrypi)
  remote_dir    path on target (default: $MAYAK_PATH, else ~/repos/mayak)

.env, data/, and .local-backup/ are never transferred or deleted on the target.
EOF
  exit "${1:-0}"
}

dry=0
while getopts ':nh' opt; do
  case "$opt" in
    n) dry=1 ;;
    h) usage 0 ;;
    *) usage 2 ;;
  esac
done
shift $((OPTIND - 1))

host="${1:-${MAYAK_HOST:-asakh@raspberrypi}}"
remote_dir="${2:-${MAYAK_PATH:-~/repos/mayak}}"
src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/"

rsync_opts=(
  --archive --compress --human-readable --delete
  --exclude '.git/'
  --exclude '.worktrees/'
  --exclude 'data/'
  --exclude '.local-backup/'
  --exclude '.env'
  --exclude '*.log'
)
(( dry )) && rsync_opts+=(--dry-run --verbose)

echo ">> from $src"
echo ">> to   $host:$remote_dir"
rsync "${rsync_opts[@]}" "$src" "$host:$remote_dir/"

if (( dry )); then
  echo ">> dry run complete"
else
  echo ">> synced - now run 'make deploy' on $host"
fi
