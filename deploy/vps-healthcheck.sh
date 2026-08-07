#!/usr/bin/env bash
set -Eeuo pipefail

# Read-only sanity sweep of the production VPS: host resources, firewall, containers,
# TLS, Postgres, Solid Queue, the nightly R2 backup, the heartbeat monitor, the durable
# Rails logs and a few application invariants. Nothing here mutates the box.
# Runbook: docs/vps-healthcheck.md.
#
# The checks run on the VPS (deploy/vps-healthcheck.remote.sh, fed over stdin) rather
# than here, so the 80 MB of durable logs are scanned in place instead of downloaded.
# With --html the remote also emits one TSV record per check after a sentinel line,
# which this wrapper renders into a self-contained report.
#
# Exit status: 0 all clear, 1 warnings only, 2 at least one failure.
#
# Config comes from .env, the same keys deploy/fetch-production-logs.sh reads:
# PRODUCTION_LOG_HOST, optionally PRODUCTION_LOG_USER / PRODUCTION_LOG_SSH_PORT, plus
# an optional HEALTHCHECKS_API_KEY for the downdetector section.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  cat <<'TXT'
Usage: deploy/vps-healthcheck.sh [options]

Options:
  --hours N          Log window to scan, in hours (default 24)
  --verify-restore   Also download the newest R2 dump and pg_restore --list it,
                     proving the archive is readable rather than merely present
  --html [PATH]      Also write a self-contained HTML report
                     (default tmp/vps-health-<timestamp>.html)
  --open             With --html, open the report in the default browser
  --quiet            With --html, skip the terminal report
  --no-color         Plain terminal output, for redirecting to a file
  -h, --help         Show this message

Exit status: 0 all clear, 1 warnings only, 2 at least one failure.
TXT
}

HOURS=24
VERIFY_RESTORE=0
COLOR=1
HTML_PATH=""
WANT_HTML=0
OPEN_HTML=0
QUIET=0
[ -t 1 ] || COLOR=0

while [ $# -gt 0 ]; do
  case "$1" in
    --hours)          HOURS="${2:?--hours needs a value}"; shift 2 ;;
    --verify-restore) VERIFY_RESTORE=1; shift ;;
    --html)
      WANT_HTML=1
      if [ "${2:-}" ] && [ "${2#-}" = "$2" ]; then HTML_PATH="$2"; shift 2; else shift; fi ;;
    --open)           OPEN_HTML=1; shift ;;
    --quiet)          QUIET=1; shift ;;
    --no-color)       COLOR=0; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "unknown option: $1" >&2; usage >&2; exit 64 ;;
  esac
done

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

LOG_HOST="${PRODUCTION_LOG_HOST:?set PRODUCTION_LOG_HOST (VPS IP/hostname) in .env}"
LOG_USER="${PRODUCTION_LOG_USER:-root}"
SSH_PORT="${PRODUCTION_LOG_SSH_PORT:-22}"

EXPECT_SHA="$(git ls-remote origin refs/heads/main 2>/dev/null | awk '{print $1}')"
APP_HOST="$(awk '/^[[:space:]]+APP_HOST:/{print $2; exit}' config/deploy.yml 2>/dev/null || true)"

if [ "$WANT_HTML" = "1" ] && [ -z "$HTML_PATH" ]; then
  mkdir -p tmp
  HTML_PATH="tmp/vps-health-$(date +%Y%m%d-%H%M%S).html"
fi

SENTINEL="---healthcheck-records---"

run_remote() {
  ssh -p "$SSH_PORT" "${LOG_USER}@${LOG_HOST}" \
    "HOURS='${HOURS}' COLOR='${COLOR}' VERIFY_RESTORE='${VERIFY_RESTORE}'" \
    "EXPECT_SHA='${EXPECT_SHA}' APP_HOST='${APP_HOST:-prismagames.com.br}'" \
    "HC_API_KEY='${HEALTHCHECKS_API_KEY:-}' EMIT_RECORDS='${WANT_HTML}'" \
    "bash -s" < deploy/vps-healthcheck.remote.sh
}

echo "prisma engine :: VPS health check"
echo "host ${LOG_USER}@${LOG_HOST}  window ${HOURS}h  $(date -Is)"

if [ "$WANT_HTML" != "1" ]; then
  run_remote
  exit $?
fi

output=""
status=0
output="$(run_remote)" || status=$?

text_part="${output%%$SENTINEL*}"
records_part=""
case "$output" in
  *"$SENTINEL"*) records_part="${output#*$SENTINEL}" ;;
esac

[ "$QUIET" = "1" ] || printf '%s' "$text_part"

if [ -z "$records_part" ]; then
  echo "no records emitted; HTML report skipped" >&2
  exit "$status"
fi

printf '%s' "$records_part" | HTML_PATH="$HTML_PATH" \
  REPORT_HOST="${LOG_USER}@${LOG_HOST}" REPORT_STATUS="$status" \
  python3 deploy/vps-healthcheck-report.py

echo
echo "HTML report: ${HTML_PATH}"

if [ "$OPEN_HTML" = "1" ]; then
  (xdg-open "$HTML_PATH" >/dev/null 2>&1 || open "$HTML_PATH" >/dev/null 2>&1 || true) &
fi

exit "$status"
