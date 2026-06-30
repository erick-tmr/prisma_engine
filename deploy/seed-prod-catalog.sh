#!/usr/bin/env bash
set -Eeuo pipefail

# One-off: upload the initial product catalog + hero banner images to the
# production R2 bucket (prisma-games-prod) and create their Active Storage rows in
# the production database. Run once to bootstrap prod; after that the catalog is
# managed from the backoffice. Idempotent: Active Storage's checksum compare skips
# images that are already uploaded, so re-running is safe.
#
# The seed images are gitignored and read from THIS local checkout
# (public/images/stores/uploads + db/seeds/hero_banner.jpg), so they must be
# present locally. This opens an SSH tunnel to the VPS's localhost Postgres and
# runs ONLY the catalog + hero_banner seeds with RAILS_ENV=production, so Active
# Storage routes the uploads to the prod bucket. It deliberately does NOT run
# db:seed (that would also load db/seeds/backoffice_demo.rb, which is dev-only
# demo data, into production). Runbook: docs/seeding-images.md.
#
# Config from .env: PRODUCTION_LOG_HOST/USER/SSH_PORT (the prod VPS, shared with
# deploy/fetch-production-logs.sh) and PRISMA_ENGINE_DATABASE_PASSWORD (prod DB
# password). config/credentials/production.key must be present locally so prod
# credentials (the R2 keys) decrypt. SSH auth uses your existing key.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

SSH_HOST="${PRODUCTION_SSH_HOST:-${PRODUCTION_LOG_HOST:?set PRODUCTION_LOG_HOST (prod VPS) in .env}}"
SSH_USER="${PRODUCTION_SSH_USER:-${PRODUCTION_LOG_USER:-root}}"
SSH_PORT="${PRODUCTION_SSH_PORT:-${PRODUCTION_LOG_SSH_PORT:-22}}"
DB_PASS="${PRISMA_ENGINE_DATABASE_PASSWORD:?set PRISMA_ENGINE_DATABASE_PASSWORD (prod DB password) in .env}"
LOCAL_PORT="${TUNNEL_LOCAL_PORT:-5433}"
REMOTE_PG="${PRODUCTION_PG_ADDR:-127.0.0.1:5432}"

log() { echo "[$(date -Is)] $*"; }

if [ ! -f config/credentials/production.key ] && [ -z "${RAILS_MASTER_KEY:-}" ]; then
  echo "config/credentials/production.key (or RAILS_MASTER_KEY) is required so prod R2 credentials decrypt" >&2
  exit 1
fi

log "opening SSH tunnel 127.0.0.1:${LOCAL_PORT} -> ${REMOTE_PG} via ${SSH_USER}@${SSH_HOST}"
ssh -N -L "${LOCAL_PORT}:${REMOTE_PG}" -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" &
TUNNEL_PID=$!
trap 'kill "${TUNNEL_PID}" 2>/dev/null || true' EXIT

for _ in $(seq 1 20); do
  (exec 3<>"/dev/tcp/127.0.0.1/${LOCAL_PORT}") 2>/dev/null && { exec 3>&- 3<&-; break; }
  sleep 0.5
done

export RAILS_ENV=production
export DATABASE_HOST=127.0.0.1
export DATABASE_PORT="${LOCAL_PORT}"
export PRISMA_ENGINE_DATABASE_PASSWORD="${DB_PASS}"
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(openssl rand -hex 32)}"

log "seeding catalog + hero banner into prisma-games-prod (R2) and the production DB"
bin/rails runner '
  load Rails.root.join("db/seeds/catalog.rb")
  load Rails.root.join("db/seeds/hero_banner.rb")
'

log "done. open a product page on production and confirm images load from the prod R2 host."
