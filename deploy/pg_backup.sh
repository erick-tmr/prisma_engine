#!/usr/bin/env bash
set -Eeuo pipefail

# Nightly pg_dump of the primary database to Cloudflare R2 via rclone.
# Secrets stay on the host and out of git: DB auth from ~/.pgpass, R2 keys from
# rclone.conf. Install + scheduling are documented in docs/deployment.md.
#
# Only the primary database is backed up; the cache/queue/cable databases are
# disposable (rebuilt by db:prepare/migrations).

DB_NAME="${DB_NAME:-prisma_engine_production}"
DB_USER="${DB_USER:-prisma_engine}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
RCLONE_REMOTE="${RCLONE_REMOTE:-r2}"
R2_BUCKET="${R2_BUCKET:?set R2_BUCKET to the backup bucket name}"
KEEP_DAILY="${KEEP_DAILY:-14d}"
KEEP_WEEKLY="${KEEP_WEEKLY:-56d}"

log() { echo "[$(date -Is)] $*"; }

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

dumpfile="${workdir}/${DB_NAME}_$(date -u +%Y%m%d_%H%M%S).dump"

log "dumping ${DB_NAME}"
pg_dump --format=custom --no-owner --no-privileges \
  --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USER" \
  --file="$dumpfile" "$DB_NAME"

daily_dir="${RCLONE_REMOTE}:${R2_BUCKET}/postgres/daily"
log "uploading to ${daily_dir}"
rclone copyto --s3-no-check-bucket "$dumpfile" "${daily_dir}/$(basename "$dumpfile")"

if [ "$(date -u +%u)" -eq 7 ]; then
  weekly_dir="${RCLONE_REMOTE}:${R2_BUCKET}/postgres/weekly"
  log "promoting weekly copy to ${weekly_dir}"
  rclone copyto --s3-no-check-bucket "$dumpfile" "${weekly_dir}/$(basename "$dumpfile")"
  rclone delete --min-age "$KEEP_WEEKLY" "$weekly_dir"
fi

log "pruning daily backups older than ${KEEP_DAILY}"
rclone delete --min-age "$KEEP_DAILY" "$daily_dir"

log "backup complete"
