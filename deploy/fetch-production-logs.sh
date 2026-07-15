#!/usr/bin/env bash
set -Eeuo pipefail

# Download the app's durable Rails logs off the production VPS into a local dir,
# ready for the local Loki stack (deploy/log-analysis). The host side is read-only:
# this only copies files. Runbook: docs/log-analysis.md.
#
# Rails writes lograge JSON to log/production.log on the persistent named volume
# (config/deploy.yml), so the history survives deploys. We resolve that volume's
# mountpoint on the host and copy production.log plus its rotation siblings
# (production.log.0, .1, ...). Each line is a raw lograge JSON object (or a plain
# Rails log line): no Docker json-file envelope, unlike the previous approach.
#
# Config comes from .env (PRODUCTION_LOG_HOST, optionally PRODUCTION_LOG_USER /
# PRODUCTION_LOG_SSH_PORT / PRODUCTION_LOG_DIR / PRODUCTION_LOG_VOLUME). SSH auth
# uses your existing key, the same one Kamal uses to reach the VPS (root, so it can
# read the volume mountpoint under /var/lib/docker).

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
LOG_VOLUME="${PRODUCTION_LOG_VOLUME:-prisma_engine_logs}"
DEST_DIR="${PRODUCTION_LOG_DIR:-/tmp/prisma-production-logs}"

log() { echo "[$(date -Is)] $*"; }

ssh_remote() { ssh -p "$SSH_PORT" "${LOG_USER}@${LOG_HOST}" "$@"; }

log "resolving log volume ${LOG_VOLUME} mountpoint on ${LOG_HOST}"
mountpoint="$(ssh_remote "docker volume inspect ${LOG_VOLUME} --format '{{.Mountpoint}}'" 2>/dev/null || true)"

if [ -z "$mountpoint" ]; then
  log "volume ${LOG_VOLUME} not found on ${LOG_HOST} (has the deploy that adds it run yet?); nothing to fetch"
  exit 0
fi

dest_sub="${DEST_DIR}/${LOG_VOLUME}"
mkdir -p "$dest_sub"
log "copying ${mountpoint}/*.log* -> ${dest_sub}/"
scp -P "$SSH_PORT" "${LOG_USER}@${LOG_HOST}:${mountpoint}/*.log*" "${dest_sub}/"

log "done. next:"
log "  cd deploy/log-analysis && docker compose up -d"
log "  open http://127.0.0.1:4000  ->  Explore  ->  Loki"
