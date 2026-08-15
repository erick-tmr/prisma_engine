#!/usr/bin/env bash
set -Eeuo pipefail

# One-off: retire the awaiting_refund order status from production data. Customer
# self-service cancellation is gone and cancellation is now an operator action, so
# awaiting_refund no longer exists in the app's transition graph. Any production
# order still parked there has to land somewhere the new code knows about, and that
# is cancelled: the refund itself was always chased by hand in InfinitePay, never
# tracked by the status.
#
# Run this BEFORE deploying the change, so no order is ever sitting in a status the
# running code has no label for.
#
# It writes one order_status_changes row per order (awaiting_refund -> cancelled,
# automatic) so the history stays honest, then flips the status. Deliberately raw
# SQL rather than Order#transition_to!: that way the script does the same thing
# whether the checkout it runs from still knows the old status or not. Idempotent:
# a second run matches zero rows.
#
# Config from .env: PRODUCTION_LOG_HOST/USER/SSH_PORT (the prod VPS, shared with
# deploy/fetch-production-logs.sh) and PRISMA_ENGINE_DATABASE_PASSWORD (prod DB
# password). SSH auth uses your existing key.

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
LOCAL_PORT="${TUNNEL_LOCAL_PORT:-5455}"
REMOTE_PG="${PRODUCTION_PG_ADDR:-127.0.0.1:5432}"
EXPECTED_DB="${PRODUCTION_DB_NAME:-prisma_engine_production}"

log() { echo "[$(date -Is)] $*"; }

# A local port that is already taken is fatal, never a warning. ssh -N keeps
# running after "Address already in use", so the forward silently does not exist
# and Rails connects to whatever else is on that port with production
# credentials. A developer box with a second project's Postgres on the same port
# is all it takes, which is exactly what happened on 5433.
if (exec 3<>"/dev/tcp/127.0.0.1/${LOCAL_PORT}") 2>/dev/null; then
  exec 3>&- 3<&-
  echo "127.0.0.1:${LOCAL_PORT} is already in use, so the tunnel would not bind and this would talk to the wrong database. Set TUNNEL_LOCAL_PORT to a free port." >&2
  exit 1
fi

log "opening SSH tunnel 127.0.0.1:${LOCAL_PORT} -> ${REMOTE_PG} via ${SSH_USER}@${SSH_HOST}"
ssh -N -o ExitOnForwardFailure=yes -L "${LOCAL_PORT}:${REMOTE_PG}" -p "${SSH_PORT}" "${SSH_USER}@${SSH_HOST}" &
TUNNEL_PID=$!
trap 'kill "${TUNNEL_PID}" 2>/dev/null || true' EXIT

tunnel_up=""
for _ in $(seq 1 20); do
  kill -0 "${TUNNEL_PID}" 2>/dev/null || { echo "SSH tunnel died before it was ready" >&2; exit 1; }
  (exec 3<>"/dev/tcp/127.0.0.1/${LOCAL_PORT}") 2>/dev/null && { exec 3>&- 3<&-; tunnel_up=1; break; }
  sleep 0.5
done
[ -n "${tunnel_up}" ] || { echo "SSH tunnel never came up on 127.0.0.1:${LOCAL_PORT}" >&2; exit 1; }

export RAILS_ENV=production
export DATABASE_HOST=127.0.0.1
export DATABASE_PORT="${LOCAL_PORT}"
export PRISMA_ENGINE_DATABASE_PASSWORD="${DB_PASS}"
export SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(openssl rand -hex 32)}"
export EXPECTED_DB

log "moving every awaiting_refund order to cancelled"
bin/rails runner - <<'RUBY'
  connection = ActiveRecord::Base.connection

  # Belt and braces on top of the port check: name the database we think we are
  # writing to and refuse anything else, so a stray forward can never turn this
  # into an UPDATE against someone else's orders table.
  expected = ENV.fetch("EXPECTED_DB")
  actual = connection.select_value("SELECT current_database()")
  abort "refusing to write: connected to #{actual.inspect}, expected #{expected.inspect}" unless actual == expected
  puts "connected to #{actual}"
  rows = connection.select_all("SELECT id, number FROM orders WHERE status = 'awaiting_refund'").to_a

  if rows.empty?
    puts "no awaiting_refund orders, nothing to do"
  else
    ids = rows.map { |row| connection.quote(row["id"]) }
    puts "found #{rows.size}: #{rows.map { |row| row['number'] }.join(', ')}"

    ActiveRecord::Base.transaction do
      changes = ids.map { |id| "(#{id}, 'awaiting_refund', 'cancelled', TRUE, now(), now())" }
      connection.execute(<<~SQL)
        INSERT INTO order_status_changes (order_id, from_status, to_status, automatic, created_at, updated_at)
        VALUES #{changes.join(', ')}
      SQL
      connection.execute(<<~SQL)
        UPDATE orders SET status = 'cancelled', updated_at = now() WHERE id IN (#{ids.join(', ')})
      SQL
    end
    puts "done"
  end
RUBY

log "done. deploy the new code now: bin/prisma deploy"
