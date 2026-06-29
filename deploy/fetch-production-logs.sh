#!/usr/bin/env bash
set -Eeuo pipefail

# Download the Rails app container's Docker json-file logs off the production VPS
# into a local dir, ready for the local Loki stack (deploy/log-analysis). The host
# side is read-only: this only copies files. Runbook: docs/log-analysis.md.
#
# Gathers ALL of the app service's containers (the live one plus Kamal's retained
# exited ones), so you get history across recent deploys, not just the current
# boot. Each container's logs land in their own subdir, rotation siblings included.
#
# Config comes from .env (PRODUCTION_LOG_HOST, optionally PRODUCTION_LOG_USER /
# PRODUCTION_LOG_SSH_PORT / PRODUCTION_LOG_DIR). SSH auth uses your existing key,
# the same one Kamal uses to reach the VPS.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

LOG_HOST="${PRODUCTION_LOG_HOST:?set PRODUCTION_LOG_HOST (VPS IP/hostname) in .env}"
LOG_USER="${PRODUCTION_LOG_USER:-root}"
SSH_PORT="${PRODUCTION_LOG_SSH_PORT:-22}"
SERVICE="${KAMAL_SERVICE:-prisma_engine}"
DEST_DIR="${PRODUCTION_LOG_DIR:-tmp/production-logs}"

log() { echo "[$(date -Is)] $*"; }

ssh_remote() { ssh -p "$SSH_PORT" "${LOG_USER}@${LOG_HOST}" "$@"; }

log "discovering ${SERVICE} containers on ${LOG_HOST}"
remote_cmd="docker ps -a --filter name=${SERVICE}-web --format '{{.ID}}' \
  | xargs -r -I{} docker inspect --format '{{.LogPath}}' {}"
mapfile -t log_paths < <(ssh_remote "$remote_cmd")

if [ "${#log_paths[@]}" -eq 0 ] || [ -z "${log_paths[0]}" ]; then
  log "no ${SERVICE} containers found on ${LOG_HOST}; nothing to fetch"
  exit 0
fi

log "found ${#log_paths[@]} container log path(s); downloading to ${DEST_DIR}/"
for remote_path in "${log_paths[@]}"; do
  [ -n "$remote_path" ] || continue
  cid="$(basename "$(dirname "$remote_path")")"
  dest_sub="${DEST_DIR}/${cid}"
  mkdir -p "$dest_sub"
  log "  ${remote_path}* -> ${dest_sub}/"
  scp -P "$SSH_PORT" "${LOG_USER}@${LOG_HOST}:${remote_path}*" "${dest_sub}/"
done

log "done. next:"
log "  cd deploy/log-analysis && docker compose up -d"
log "  open http://127.0.0.1:3000  ->  Explore  ->  Loki"
