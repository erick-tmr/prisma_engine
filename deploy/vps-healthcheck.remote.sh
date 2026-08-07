#!/usr/bin/env bash
set -Eeuo pipefail

# Runs on the production VPS, fed over stdin by deploy/vps-healthcheck.sh.
# Read-only: every check inspects, none of them mutate. Runbook: docs/vps-healthcheck.md.
#
# Inputs arrive as leading environment assignments from the wrapper:
#   HOURS            log window to scan, in hours
#   COLOR            1 to emit ANSI colour
#   VERIFY_RESTORE   1 to also pg_restore --list the newest R2 dump
#   EXPECT_SHA       git sha the wrapper expects the web container to run
#   APP_HOST         public hostname, for the local HTTP smoke test
#   LOG_VOLUME       docker volume holding the durable Rails logs
#   DB_NAME          primary database
#   QUEUE_DB_NAME    Solid Queue database
#   R2_REMOTE        rclone remote:bucket holding the backups
#   HC_API_KEY       healthchecks.io read key, to assert the monitor is itself up

HOURS="${HOURS:-24}"
COLOR="${COLOR:-0}"
VERIFY_RESTORE="${VERIFY_RESTORE:-0}"
EXPECT_SHA="${EXPECT_SHA:-}"
APP_HOST="${APP_HOST:-prismagames.com.br}"
LOG_VOLUME="${LOG_VOLUME:-prisma_engine_logs}"
DB_NAME="${DB_NAME:-prisma_engine_production}"
QUEUE_DB_NAME="${QUEUE_DB_NAME:-prisma_engine_production_queue}"
R2_REMOTE="${R2_REMOTE:-r2:prisma-engine-backups}"
HC_API_KEY="${HC_API_KEY:-}"
EMIT_RECORDS="${EMIT_RECORDS:-0}"
RECORD_SENTINEL="---healthcheck-records---"

DISK_WARN=75;  DISK_FAIL=90
MEM_WARN=15;   MEM_FAIL=8
SWAP_WARN=50
LOAD_WARN_PER_CORE=2
CONN_WARN_PCT=70
CACHE_HIT_WARN=95
IDLE_TX_WARN_SECS=300
LONG_QUERY_WARN_SECS=60
DEAD_TUPLE_WARN_PCT=20
DEAD_TUPLE_MIN_ROWS=1000
QUEUE_READY_WARN=100
QUEUE_AGE_WARN_SECS=3600
BACKUP_AGE_FAIL_HOURS=36
BACKUP_SHRINK_WARN_PCT=60
WEEKLY_AGE_WARN_DAYS=10
CERT_WARN_DAYS=21
CERT_FAIL_DAYS=7
DOCKER_RECLAIM_WARN_GB=2
HTTP_5XX_WARN=1
HTTP_5XX_FAIL=20
SCAN_404_WARN=500
LABEL_STUCK_WARN_MINS=120
ORDER_SHIPPED_WARN_DAYS=3

if [ "$COLOR" = "1" ]; then
  C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_FAIL=$'\033[1;31m'
  C_HEAD=$'\033[1;34m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=; C_WARN=; C_FAIL=; C_HEAD=; C_DIM=; C_OFF=
fi

ok_count=0; warn_count=0; fail_count=0
warn_lines=(); fail_lines=()
records=(); current_section="general"

section() {
  current_section="$1"
  printf '\n%s== %s%s\n' "$C_HEAD" "$1" "$C_OFF"
}

record() {
  [ "$EMIT_RECORDS" = "1" ] || return 0
  local clean_detail="${3//	/ }"
  records+=("${current_section}	$1	$2	${clean_detail//$'\n'/ }")
}

report() {
  local status="$1" name="$2" detail="${3:-}"
  case "$status" in
    OK|WARN|FAIL|INFO) ;;
    *) return 0 ;;
  esac
  record "$status" "$name" "$detail"
  case "$status" in
    OK)   ok_count=$((ok_count + 1))
          printf '  %s[ OK ]%s %-34s %s\n' "$C_OK" "$C_OFF" "$name" "$detail" ;;
    WARN) warn_count=$((warn_count + 1)); warn_lines+=("$name: $detail")
          printf '  %s[WARN]%s %-34s %s\n' "$C_WARN" "$C_OFF" "$name" "$detail" ;;
    FAIL) fail_count=$((fail_count + 1)); fail_lines+=("$name: $detail")
          printf '  %s[FAIL]%s %-34s %s\n' "$C_FAIL" "$C_OFF" "$name" "$detail" ;;
    INFO) printf '  %s[ -- ]%s %-34s %s\n' "$C_DIM" "$C_OFF" "$name" "$detail" ;;
  esac
}

threshold() {
  local value="$1" warn="$2" fail="$3" name="$4" detail="$5"
  if   awk -v v="$value" -v t="$fail" 'BEGIN{exit !(v >= t)}'; then report FAIL "$name" "$detail"
  elif awk -v v="$value" -v t="$warn" 'BEGIN{exit !(v >= t)}'; then report WARN "$name" "$detail"
  else report OK "$name" "$detail"
  fi
}

psql_primary() { sudo -u postgres psql -tAX -F'|' -d "$DB_NAME" -c "$1" 2>/dev/null || true; }
psql_queue()   { sudo -u postgres psql -tAX -F'|' -d "$QUEUE_DB_NAME" -c "$1" 2>/dev/null || true; }

section "HOST"

while read -r fs size used avail pct mount; do
  case "$fs" in tmpfs|devtmpfs|overlay|Filesystem) continue ;; esac
  pct="${pct%\%}"
  threshold "$pct" "$DISK_WARN" "$DISK_FAIL" "disk $mount" "${pct}% used, ${avail} free of ${size}"
done < <(df -Ph | tail -n +2)

while read -r fs inodes iused ifree pct mount; do
  case "$fs" in tmpfs|devtmpfs|overlay|Filesystem) continue ;; esac
  pct="${pct%\%}"
  [ "$pct" = "-" ] && continue
  threshold "$pct" "$DISK_WARN" "$DISK_FAIL" "inodes $mount" "${pct}% used, ${ifree} free"
done < <(df -Pih | tail -n +2)

mem_total=$(awk '/MemTotal/{print $2}' /proc/meminfo)
mem_avail=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
mem_pct=$(awk -v a="$mem_avail" -v t="$mem_total" 'BEGIN{printf "%.1f", 100*a/t}')
mem_human=$(awk -v a="$mem_avail" -v t="$mem_total" 'BEGIN{printf "%.1fGi available of %.1fGi", a/1048576, t/1048576}')
if   awk -v v="$mem_pct" -v t="$MEM_FAIL"  'BEGIN{exit !(v < t)}'; then report FAIL "memory" "${mem_pct}% available, $mem_human"
elif awk -v v="$mem_pct" -v t="$MEM_WARN"  'BEGIN{exit !(v < t)}'; then report WARN "memory" "${mem_pct}% available, $mem_human"
else report OK "memory" "${mem_pct}% available, $mem_human"
fi

swap_total=$(awk '/SwapTotal/{print $2}' /proc/meminfo)
swap_free=$(awk '/SwapFree/{print $2}' /proc/meminfo)
if [ "$swap_total" -gt 0 ]; then
  swap_pct=$(awk -v t="$swap_total" -v f="$swap_free" 'BEGIN{printf "%.1f", 100*(t-f)/t}')
  threshold "$swap_pct" "$SWAP_WARN" 90 "swap" "${swap_pct}% used of $(awk -v t="$swap_total" 'BEGIN{printf "%.1fGi", t/1048576}')"
else
  report WARN "swap" "no swap configured"
fi

cores=$(nproc)
read -r load1 load5 _ < /proc/loadavg
load_warn=$(awk -v c="$cores" -v p="$LOAD_WARN_PER_CORE" 'BEGIN{print c*p}')
load_fail=$(awk -v c="$cores" -v p="$LOAD_WARN_PER_CORE" 'BEGIN{print c*p*2}')
threshold "$load1" "$load_warn" "$load_fail" "load average" "${load1} / ${load5} on ${cores} core(s)"

if [ -f /var/run/reboot-required ]; then
  pkgs=$(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null | cut -c1-60)
  report WARN "reboot required" "pending${pkgs:+: $pkgs}"
else
  report OK "reboot required" "no"
fi

if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q yes; then
  report OK "clock sync" "NTP synchronised, $(date -Is)"
else
  report WARN "clock sync" "NTP not synchronised"
fi

report INFO "uptime" "$(uptime -p 2>/dev/null || true)"

section "SECURITY"

if ufw status 2>/dev/null | grep -q '^Status: active'; then
  open_ports=$(ufw status 2>/dev/null | awk '/ALLOW/{print $1}' | sort -u | tr '\n' ' ')
  report OK "ufw" "active: ${open_ports} (80/443 further scoped by the origin lock)"
else
  report FAIL "ufw" "inactive"
fi

lock_enabled=$(systemctl is-enabled prisma-cf-firewall 2>/dev/null || echo missing)
lock_ranges=$(iptables -S DOCKER-USER 2>/dev/null | grep -c 'multiport --dports 80,443 -j RETURN' || true)
lock_drop=$(iptables -S DOCKER-USER 2>/dev/null | grep -c 'multiport --dports 80,443 -j DROP' || true)
if [ "$lock_enabled" = "enabled" ] && [ "${lock_drop:-0}" -gt 0 ]; then
  report OK "cloudflare origin lock" "enabled, ${lock_ranges} allowed range(s) then DROP in DOCKER-USER"
elif [ "${lock_drop:-0}" -gt 0 ]; then
  report WARN "cloudflare origin lock" "rules live but the unit is ${lock_enabled}: they would not survive a reboot"
else
  report FAIL "cloudflare origin lock" "no DROP rule on 80/443 in DOCKER-USER: the origin is reachable directly"
fi

if command -v fail2ban-client >/dev/null 2>&1; then
  jails=$(fail2ban-client status 2>/dev/null | sed -n 's/.*Jail list:[[:space:]]*//p')
  banned=0
  for jail in ${jails//,/ }; do
    n=$(fail2ban-client status "$jail" 2>/dev/null | awk '/Currently banned/{print $NF}')
    banned=$((banned + ${n:-0}))
  done
  report OK "fail2ban" "active, jails: ${jails:-none}, currently banned: ${banned}"
else
  report WARN "fail2ban" "not installed (infra/ansible role exists but is unapplied)"
fi

ssh_fails=$(journalctl -u ssh --since "${HOURS} hours ago" --no-pager 2>/dev/null | grep -ci 'failed password' || true)
if [ "${ssh_fails:-0}" -gt 50 ]; then
  report WARN "ssh auth failures" "${ssh_fails} in ${HOURS}h"
else
  report OK "ssh auth failures" "${ssh_fails:-0} in ${HOURS}h"
fi

if systemctl is-active unattended-upgrades >/dev/null 2>&1; then
  report OK "unattended-upgrades" "active"
else
  report WARN "unattended-upgrades" "not active"
fi

section "DOCKER / APP"

web_container=$(docker ps --filter "name=prisma_engine-web" --format '{{.Names}}' | head -1)
if [ -n "$web_container" ]; then
  status=$(docker inspect -f '{{.State.Status}}' "$web_container")
  restarts=$(docker inspect -f '{{.RestartCount}}' "$web_container")
  started=$(docker inspect -f '{{.State.StartedAt}}' "$web_container")
  if [ "$status" = "running" ]; then
    report OK "web container" "running since ${started%.*}, restarts=${restarts}"
  else
    report FAIL "web container" "status=${status}"
  fi
  [ "${restarts:-0}" -gt 0 ] && report WARN "web restarts" "${restarts} restart(s) recorded"

  running_sha="${web_container##*-}"
  if [ -n "$EXPECT_SHA" ]; then
    if [ "$running_sha" = "$EXPECT_SHA" ]; then
      report OK "deployed revision" "${running_sha:0:12} matches origin/main"
    else
      report WARN "deployed revision" "running ${running_sha:0:12}, origin/main is ${EXPECT_SHA:0:12}"
    fi
  else
    report INFO "deployed revision" "${running_sha:0:12}"
  fi
else
  report FAIL "web container" "not running"
fi

if docker ps --filter "name=kamal-proxy" --format '{{.Names}}' | grep -q kamal-proxy; then
  report OK "kamal-proxy" "running"
else
  report FAIL "kamal-proxy" "not running"
fi

reclaimable=$(docker system df --format '{{.Type}} {{.Reclaimable}}' 2>/dev/null | awk '
  /^Images|^Containers|^Local|^Build/ {
    v=$2; unit=$3
    gsub(/[^0-9.]/, "", v)
    if (unit ~ /GB/ || $2 ~ /GB/) total += v
    else if (unit ~ /MB/ || $2 ~ /MB/) total += v/1024
  } END { printf "%.2f", total+0 }')
threshold "$reclaimable" "$DOCKER_RECLAIM_WARN_GB" 10 "docker reclaimable" "${reclaimable}GB"

origin_code=$(curl -sSk -o /dev/null -w '%{http_code}' --max-time 15 \
  --resolve "${APP_HOST}:443:127.0.0.1" "https://${APP_HOST}/" 2>/dev/null || true)
if [ "$origin_code" = "200" ]; then
  report OK "origin smoke test" "GET / on 127.0.0.1:443 -> 200"
else
  report FAIL "origin smoke test" "GET / on 127.0.0.1:443 -> ${origin_code:-000}"
fi

origin_up=$(curl -sSk -o /dev/null -w '%{http_code}' --max-time 15 \
  --resolve "${APP_HOST}:443:127.0.0.1" "https://${APP_HOST}/up" 2>/dev/null || true)
if [ "$origin_up" = "200" ]; then
  report OK "rails /up" "200 (the endpoint kamal-proxy polls)"
else
  report FAIL "rails /up" "${origin_up:-000}"
fi

edge_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://${APP_HOST}/up" 2>/dev/null || true)
if [ "$edge_code" = "200" ]; then
  report OK "edge smoke test" "GET /up through Cloudflare -> 200"
else
  report WARN "edge smoke test" "GET /up through Cloudflare -> ${edge_code:-000}"
fi

cert_end=$(echo | openssl s_client -connect 127.0.0.1:443 -servername "$APP_HOST" 2>/dev/null \
  | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)
if [ -n "$cert_end" ]; then
  cert_epoch=$(date -d "$cert_end" +%s 2>/dev/null || echo 0)
  days_left=$(( (cert_epoch - $(date +%s)) / 86400 ))
  if   [ "$days_left" -lt "$CERT_FAIL_DAYS" ]; then report FAIL "origin tls cert" "${days_left}d left (${cert_end})"
  elif [ "$days_left" -lt "$CERT_WARN_DAYS" ]; then report WARN "origin tls cert" "${days_left}d left (${cert_end})"
  else report OK "origin tls cert" "${days_left}d left (${cert_end})"
  fi
else
  report WARN "origin tls cert" "could not read cert on 127.0.0.1:443"
fi

section "POSTGRES"

pg_version=$(psql_primary "SELECT current_setting('server_version');")
if [ -z "$pg_version" ]; then
  report FAIL "postgres" "unreachable"
else
  report OK "postgres" "server ${pg_version}, $(systemctl is-active postgresql 2>/dev/null || echo '?')"

  IFS='|' read -r db_size conns max_conns idle_tx idle_tx_age <<<"$(psql_primary "
    SELECT pg_size_pretty(pg_database_size(current_database())),
           (SELECT count(*) FROM pg_stat_activity),
           current_setting('max_connections'),
           (SELECT count(*) FROM pg_stat_activity WHERE state = 'idle in transaction'),
           (SELECT COALESCE(max(EXTRACT(epoch FROM now() - state_change))::int, 0)
              FROM pg_stat_activity WHERE state = 'idle in transaction');")"
  report INFO "database size" "$db_size (primary)"

  conn_pct=$(awk -v c="${conns:-0}" -v m="${max_conns:-100}" 'BEGIN{printf "%.0f", 100*c/m}')
  threshold "$conn_pct" "$CONN_WARN_PCT" 90 "connections" "${conns}/${max_conns} (${conn_pct}%)"

  if [ "${idle_tx:-0}" -gt 0 ] && [ "${idle_tx_age:-0}" -ge "$IDLE_TX_WARN_SECS" ]; then
    report WARN "idle in transaction" "${idle_tx} session(s), oldest ${idle_tx_age}s"
  else
    report OK "idle in transaction" "${idle_tx:-0} session(s)"
  fi

  long_query=$(psql_primary "
    SELECT COALESCE(max(EXTRACT(epoch FROM now() - query_start))::int, 0)
      FROM pg_stat_activity
     WHERE state = 'active' AND backend_type = 'client backend' AND pid <> pg_backend_pid();")
  threshold "${long_query:-0}" "$LONG_QUERY_WARN_SECS" 300 "longest active query" "${long_query:-0}s"

  IFS='|' read -r cache_hit deadlocks temp_files <<<"$(psql_primary "
    SELECT round(100.0*blks_hit/NULLIF(blks_hit+blks_read,0), 2), deadlocks, temp_files
      FROM pg_stat_database WHERE datname = current_database();")"
  if awk -v v="${cache_hit:-0}" -v t="$CACHE_HIT_WARN" 'BEGIN{exit !(v < t)}'; then
    report WARN "cache hit ratio" "${cache_hit}%"
  else
    report OK "cache hit ratio" "${cache_hit}%"
  fi
  if [ "${deadlocks:-0}" -gt 0 ]; then
    report WARN "deadlocks" "${deadlocks} since stats reset"
  else
    report OK "deadlocks" "0"
  fi
  report INFO "temp files" "${temp_files:-0} since stats reset"

  bloated=$(psql_primary "
    SELECT string_agg(format('%s (%s%% dead, %s rows)', relname,
             round(100.0*n_dead_tup/NULLIF(n_live_tup+n_dead_tup,0)), n_live_tup), ', ')
      FROM pg_stat_user_tables
     WHERE n_live_tup >= ${DEAD_TUPLE_MIN_ROWS}
       AND 100.0*n_dead_tup/NULLIF(n_live_tup+n_dead_tup,0) >= ${DEAD_TUPLE_WARN_PCT};")
  if [ -n "$bloated" ]; then
    report WARN "dead tuples" "$bloated"
  else
    report OK "dead tuples" "no table over ${DEAD_TUPLE_WARN_PCT}% dead above ${DEAD_TUPLE_MIN_ROWS} rows"
  fi

  never_vacuumed=$(psql_primary "
    SELECT count(*) FROM pg_stat_user_tables
     WHERE n_live_tup >= ${DEAD_TUPLE_MIN_ROWS}
       AND last_autovacuum IS NULL AND last_vacuum IS NULL;")
  [ "${never_vacuumed:-0}" -gt 0 ] && report WARN "autovacuum" "${never_vacuumed} sizeable table(s) never vacuumed"

  seq_risk=$(psql_primary "
    SELECT string_agg(format('%s at %s%%', seq, pct), ', ') FROM (
      SELECT c.relname AS seq,
             round(100.0*last_value/NULLIF(2147483647, 0)) AS pct
        FROM pg_sequences s
        JOIN pg_class c ON c.relname = s.sequencename
       WHERE s.last_value IS NOT NULL
         AND 100.0*s.last_value/2147483647 > 50) t;")
  if [ -n "$seq_risk" ]; then
    report WARN "sequence headroom" "$seq_risk of int4 range"
  else
    report OK "sequence headroom" "all sequences well inside range"
  fi
fi

section "SOLID QUEUE"

queue_stats=$(psql_queue "
  SELECT (SELECT count(*) FROM solid_queue_failed_executions),
         (SELECT count(*) FROM solid_queue_ready_executions),
         (SELECT count(*) FROM solid_queue_scheduled_executions),
         (SELECT count(*) FROM solid_queue_claimed_executions),
         (SELECT COALESCE(max(EXTRACT(epoch FROM now() - created_at))::int, 0)
            FROM solid_queue_jobs WHERE finished_at IS NULL);")
if [ -z "$queue_stats" ]; then
  report FAIL "solid queue" "queue database unreachable"
else
  IFS='|' read -r q_failed q_ready q_sched q_claimed q_age <<<"$queue_stats"
  if [ "${q_failed:-0}" -gt 0 ]; then
    report FAIL "failed executions" "${q_failed} row(s) awaiting triage"
  else
    report OK "failed executions" "0"
  fi
  threshold "${q_ready:-0}" "$QUEUE_READY_WARN" 1000 "ready backlog" "${q_ready} ready, ${q_claimed} claimed, ${q_sched} scheduled"
  if [ "${q_age:-0}" -ge "$QUEUE_AGE_WARN_SECS" ]; then
    report WARN "oldest unfinished job" "$((q_age / 60))m old"
  else
    report OK "oldest unfinished job" "${q_age:-0}s old"
  fi

  stale_workers=$(psql_queue "
    SELECT count(*) FROM solid_queue_processes
     WHERE last_heartbeat_at < now() - interval '5 minutes';")
  if [ "${stale_workers:-0}" -gt 0 ]; then
    report WARN "worker heartbeats" "${stale_workers} process(es) stale over 5m"
  else
    report OK "worker heartbeats" "all fresh"
  fi
fi

section "BACKUPS"

if systemctl is-enabled prisma-pg-backup.timer >/dev/null 2>&1; then
  next_run=$(systemctl show prisma-pg-backup.timer -p NextElapseUSecRealtime --value 2>/dev/null)
  report OK "backup timer" "enabled and $(systemctl is-active prisma-pg-backup.timer), next ${next_run:-unknown}"
else
  report FAIL "backup timer" "not enabled"
fi

last_result=$(systemctl show prisma-pg-backup.service -p Result --value 2>/dev/null)
last_status=$(systemctl show prisma-pg-backup.service -p ExecMainStatus --value 2>/dev/null)
if [ "$last_result" = "success" ] && [ "${last_status:-1}" = "0" ]; then
  report OK "last backup run" "exit 0 ($(systemctl show prisma-pg-backup.service -p ExecMainExitTimestamp --value 2>/dev/null))"
else
  report FAIL "last backup run" "result=${last_result:-unknown} exit=${last_status:-unknown}"
fi

daily_listing=$(rclone lsl "${R2_REMOTE}/postgres/daily" 2>/dev/null | sort -k2,3 || true)
if [ -z "$daily_listing" ]; then
  report FAIL "daily backups" "no objects under ${R2_REMOTE}/postgres/daily"
else
  newest_line=$(echo "$daily_listing" | tail -1)
  newest_size=$(echo "$newest_line" | awk '{print $1}')
  newest_date=$(echo "$newest_line" | awk '{print $2" "$3}')
  newest_name=$(echo "$newest_line" | awk '{print $4}')
  newest_epoch=$(date -d "${newest_date%.*}" +%s 2>/dev/null || echo 0)
  age_hours=$(( ($(date +%s) - newest_epoch) / 3600 ))
  if [ "$age_hours" -ge "$BACKUP_AGE_FAIL_HOURS" ]; then
    report FAIL "newest daily backup" "${age_hours}h old ($newest_name)"
  else
    report OK "newest daily backup" "${age_hours}h old, $(numfmt --to=iec "$newest_size") ($newest_name)"
  fi

  daily_count=$(echo "$daily_listing" | wc -l)
  report INFO "daily retention" "${daily_count} object(s) held"

  median_size=$(echo "$daily_listing" | tail -8 | head -7 | awk '{print $1}' | sort -n | awk '{a[NR]=$1} END{print (NR? a[int((NR+1)/2)] : 0)}')
  if [ "${median_size:-0}" -gt 0 ]; then
    pct_of_median=$(awk -v n="$newest_size" -v m="$median_size" 'BEGIN{printf "%.0f", 100*n/m}')
    if [ "$pct_of_median" -lt "$BACKUP_SHRINK_WARN_PCT" ]; then
      report FAIL "backup size sanity" "newest is ${pct_of_median}% of recent median, possible truncated dump"
    else
      report OK "backup size sanity" "newest is ${pct_of_median}% of recent median"
    fi
  fi
fi

weekly_listing=$(rclone lsl "${R2_REMOTE}/postgres/weekly" 2>/dev/null | sort -k2,3 || true)
if [ -z "$weekly_listing" ]; then
  report WARN "weekly backups" "no objects under ${R2_REMOTE}/postgres/weekly"
else
  weekly_newest=$(echo "$weekly_listing" | tail -1)
  weekly_date=$(echo "$weekly_newest" | awk '{print $2" "$3}')
  weekly_epoch=$(date -d "${weekly_date%.*}" +%s 2>/dev/null || echo 0)
  weekly_age_days=$(( ($(date +%s) - weekly_epoch) / 86400 ))
  if [ "$weekly_age_days" -gt "$WEEKLY_AGE_WARN_DAYS" ]; then
    report WARN "newest weekly backup" "${weekly_age_days}d old, promotion may have stopped"
  else
    report OK "newest weekly backup" "${weekly_age_days}d old, $(echo "$weekly_listing" | wc -l) held"
  fi
fi

other_dbs=$(sudo -u postgres psql -tAX -c "
  SELECT string_agg(datname, ', ') FROM pg_database
   WHERE datistemplate = false AND datname NOT IN ('postgres', '${DB_NAME}');" 2>/dev/null || true)
[ -n "$other_dbs" ] && report INFO "not backed up" "${other_dbs} (derivable state, dumped by design: primary only)"

if [ "$VERIFY_RESTORE" = "1" ] && [ -n "${newest_name:-}" ]; then
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  if rclone copyto "${R2_REMOTE}/postgres/daily/${newest_name}" "${tmpdir}/${newest_name}" >/dev/null 2>&1; then
    if table_count=$(pg_restore --list "${tmpdir}/${newest_name}" 2>/dev/null | grep -c 'TABLE DATA'); then
      report OK "restore rehearsal" "archive readable, ${table_count} table(s) with data"
    else
      report FAIL "restore rehearsal" "pg_restore could not read the archive"
    fi
  else
    report FAIL "restore rehearsal" "could not download ${newest_name}"
  fi
fi

section "DOWNDETECTOR"

backup_env="/etc/prisma_engine/backup.env"
ping_url=$(grep -E '^HC_PING_URL=' "$backup_env" 2>/dev/null | cut -d= -f2- || true)
if [ -z "$ping_url" ]; then
  report FAIL "heartbeat configured" "HC_PING_URL empty in ${backup_env}: pg_backup.sh pings nothing, so a backup that stops running raises no alert"
else
  ping_host="${ping_url#*://}"; ping_host="${ping_host%%/*}"
  report OK "heartbeat configured" "pings ${ping_host} (uuid withheld)"

  if curl -sS -o /dev/null --max-time 10 "https://${ping_host}/" >/dev/null 2>&1; then
    report OK "heartbeat egress" "${ping_host} reachable from the VPS"
  else
    report FAIL "heartbeat egress" "${ping_host} unreachable: pings cannot leave the box"
  fi

  if [ -n "$HC_API_KEY" ]; then
    hc_json=$(curl -sS --max-time 15 -H "X-Api-Key: ${HC_API_KEY}" \
      "https://healthchecks.io/api/v3/checks/" 2>/dev/null || true)
    if [ -z "$hc_json" ] || ! echo "$hc_json" | jq -e '.checks' >/dev/null 2>&1; then
      report WARN "monitor status" "healthchecks.io API did not answer or the key was rejected"
    else
      total=$(echo "$hc_json" | jq '.checks | length')
      down=$(echo "$hc_json" | jq -r '[.checks[] | select(.status != "up")] | length')
      detail=$(echo "$hc_json" | jq -r '.checks[] | "\(.name)=\(.status) last=\(.last_ping // "never")"' | tr '\n' ' ')
      if [ "${down:-0}" -gt 0 ]; then
        report FAIL "monitor status" "${down} of ${total} check(s) not up :: ${detail}"
      else
        report OK "monitor status" "${total} check(s) up :: ${detail}"
      fi

      stale=$(echo "$hc_json" | jq -r --arg now "$(date -u +%Y-%m-%dT%H:%M:%S)" '
        [.checks[] | select(.last_ping == null or .last_ping < ($now | sub("T.*"; "T00:00:00")))] | length')
      if [ "${stale:-0}" -gt 0 ]; then
        report WARN "heartbeat freshness" "${stale} check(s) with no ping today"
      else
        report OK "heartbeat freshness" "every check pinged today"
      fi
    fi
  else
    report INFO "monitor status" "set HEALTHCHECKS_API_KEY in .env to assert the monitor itself is up, not just that we can reach it"
  fi

  report INFO "heartbeat coverage" "backup job only; nothing pings on behalf of the web app, so a site outage raises no alert"
fi

section "INTEGRATIONS"

webhook_probe=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 -X POST \
  -H 'Content-Type: application/json' --data '{"probe":"healthcheck"}' \
  "https://${APP_HOST}/pagamentos/webhook/healthcheck-probe" 2>/dev/null || true)
case "$webhook_probe" in
  401) report OK "infinitepay webhook endpoint" "reachable through Cloudflare, unknown token rejected with 401" ;;
  200) report FAIL "infinitepay webhook endpoint" "accepted an unknown token, the per-order check is not running" ;;
  *)   report FAIL "infinitepay webhook endpoint" "POST returned ${webhook_probe:-000}, expected 401" ;;
esac

if [ -n "${web_container:-}" ]; then
  correios_out=$(docker exec -i "$web_container" bin/rails runner - 2>&1 >/dev/null <<'RUBY' | grep '^PROBE|' | cut -d'|' -f2- || true
def probe(label, token_name)
  yield
  warn "PROBE|#{label}|OK|#{token_name} accepted"
rescue Correios::Api::TransientError => error
  warn "PROBE|#{label}|WARN|#{error.message}"
rescue StandardError => error
  warn "PROBE|#{label}|FAIL|#{error.class}: #{error.message}"
end

probe("api_token", "api_token") do
  result = Correios::Api::Cep.find("01310100")
  raise "unexpected body" unless result["uf"] == "SP"
end

code = Shipment.where.not(tracking_code: [ nil, "" ]).order(created_at: :desc).limit(1).pick(:tracking_code)
if code
  probe("cartao_api_token", "cartao_api_token") { Correios::Api::PrePostagemStatus.fetch(code) }
  probe("sro_tracking", "api_token") { Correios::Api::Tracking.fetch(code) }
else
  warn "PROBE|cartao_api_token|INFO|no shipment with a tracking code to probe with"
end
RUBY
)
  if [ -z "$correios_out" ]; then
    report WARN "correios reachability" "probe produced no output"
  else
    while IFS='|' read -r probe_name probe_status probe_detail; do
      [ -n "$probe_name" ] || continue
      report "$probe_status" "correios ${probe_name}" "$probe_detail"
    done <<<"$correios_out"
  fi
else
  report WARN "correios reachability" "no web container to probe from"
fi

section "LOGS (last ${HOURS}h)"

log_dir=$(docker volume inspect "$LOG_VOLUME" --format '{{.Mountpoint}}' 2>/dev/null || true)
if [ -z "$log_dir" ] || [ ! -d "$log_dir" ]; then
  report FAIL "log volume" "${LOG_VOLUME} not found"
else
  log_analysis=$(HOURS="$HOURS" LOG_DIR="$log_dir" python3 - <<'PY' || true
import collections, datetime, glob, json, os, re

hours = int(os.environ["HOURS"])
log_dir = os.environ["LOG_DIR"]
cutoff = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours)).isoformat()

SCANNERS = re.compile(r"feroxbuster|nikto|sqlmap|nuclei|dirbuster|gobuster|wpscan|masscan|zgrab|nmap", re.I)

requests, jobs = [], []
plain_exceptions = 0
correios_codes = collections.Counter()

for path in sorted(glob.glob(os.path.join(log_dir, "*.log*"))):
    try:
        fh = open(path, errors="replace")
    except OSError:
        continue
    with fh:
        position = ""
        for line in fh:
            s = line.strip()
            if s.startswith("{"):
                try:
                    d = json.loads(s)
                except ValueError:
                    continue
                stamp = d.get("time", "")
                if stamp:
                    position = stamp
                if stamp < cutoff:
                    continue
                if d.get("event") == "request":
                    requests.append(d)
                elif d.get("event") == "job":
                    jobs.append(d)
            else:
                if position < cutoff:
                    continue
                for code in re.findall(r"PPN-\d+|SRO-\d+|RTL-\d+", s):
                    correios_codes[code] += 1
                if s.startswith("  ") and "Error" in s:
                    plain_exceptions += 1

status = collections.Counter(str(r.get("status")) for r in requests)
r5xx = sum(c for k, c in status.items() if k.startswith("5"))
r404 = status.get("404", 0)

by_ip = collections.Counter(r.get("remote_ip") for r in requests)
scanners = collections.Counter(
    r.get("remote_ip") for r in requests if SCANNERS.search(r.get("user_agent") or "")
)
job_bad = [j for j in jobs if j.get("outcome") == "errored"
           or j.get("job_event") in ("retry_stopped", "discard")]
job_retry = [j for j in jobs if j.get("job_event") == "enqueue_retry"]
job_exc = collections.Counter(j.get("exception") for j in job_bad + job_retry if j.get("exception"))

out = {
    "requests": len(requests),
    "r5xx": r5xx,
    "r404": r404,
    "top_ip": by_ip.most_common(1)[0] if by_ip else ("none", 0),
    "scanners": scanners.most_common(3),
    "jobs": len(jobs),
    "job_bad": len(job_bad),
    "job_retry": len(job_retry),
    "job_exc": job_exc.most_common(3),
    "correios": correios_codes.most_common(5),
    "plain_exceptions": plain_exceptions,
}
print(json.dumps(out))
PY
)

  if [ -z "$log_analysis" ]; then
    report WARN "log analysis" "parser produced no output"
  else
    get() { echo "$log_analysis" | jq -r "$1"; }

    req_total=$(get '.requests')
    report INFO "requests" "${req_total} in ${HOURS}h"

    r5xx=$(get '.r5xx')
    threshold "$r5xx" "$HTTP_5XX_WARN" "$HTTP_5XX_FAIL" "5xx responses" "${r5xx} in ${HOURS}h"

    r404=$(get '.r404')
    threshold "$r404" "$SCAN_404_WARN" 5000 "404 responses" "${r404} in ${HOURS}h"

    top_ip=$(get '.top_ip[0]'); top_ip_n=$(get '.top_ip[1]')
    report INFO "busiest client" "${top_ip} (${top_ip_n} requests)"

    scanner_hits=$(get '.scanners | length')
    if [ "$scanner_hits" -gt 0 ]; then
      report WARN "scanner user agents" "$(get '.scanners | map("\(.[0]) x\(.[1])") | join(", ")')"
    else
      report OK "scanner user agents" "none seen"
    fi

    job_bad=$(get '.job_bad')
    if [ "$job_bad" -gt 0 ]; then
      report FAIL "job failures" "${job_bad} errored/stopped/discarded: $(get '.job_exc | map(.[0]) | join(", ")')"
    else
      report OK "job failures" "0 of $(get '.jobs') job events"
    fi

    job_retry=$(get '.job_retry')
    if [ "$job_retry" -gt 0 ]; then
      report WARN "job retries" "${job_retry} retried: $(get '.job_exc | map(.[0]) | join(", ")')"
    else
      report OK "job retries" "0"
    fi

    correios=$(get '.correios | length')
    if [ "$correios" -gt 0 ]; then
      report INFO "correios codes" "$(get '.correios | map("\(.[0]) x\(.[1])") | join(", ")')"
    fi

    unlogged=$(get '.plain_exceptions')
    if [ "$unlogged" -gt 0 ]; then
      report INFO "unlogged exceptions" "${unlogged} raw exception line(s); lograge does not emit a request line for RoutingError 404s"
    fi
  fi
fi

section "APPLICATION"

label_stuck=$(psql_primary "
  SELECT count(*) FROM shipping_labels
   WHERE state <> 3 AND updated_at < now() - interval '${LABEL_STUCK_WARN_MINS} minutes';")
if [ "${label_stuck:-0}" -gt 0 ]; then
  report WARN "labels mid-saga" "${label_stuck} not ready and untouched for ${LABEL_STUCK_WARN_MINS}m"
else
  report OK "labels mid-saga" "none stalled"
fi

label_errored=$(psql_primary "SELECT count(*) FROM shipping_labels WHERE error IS NOT NULL;")
if [ "${label_errored:-0}" -gt 0 ]; then
  report WARN "labels with error" "${label_errored} carrying a persisted error"
else
  report OK "labels with error" "0"
fi

orders_unshipped=$(psql_primary "
  SELECT count(*) FROM orders
   WHERE status = 'label_issued' AND updated_at < now() - interval '${ORDER_SHIPPED_WARN_DAYS} days';")
if [ "${orders_unshipped:-0}" -gt 0 ]; then
  report WARN "orders awaiting handover" "${orders_unshipped} at label_issued over ${ORDER_SHIPPED_WARN_DAYS}d"
else
  report OK "orders awaiting handover" "none over ${ORDER_SHIPPED_WARN_DAYS}d"
fi

order_mix=$(psql_primary "
  SELECT string_agg(format('%s=%s', status, n), ' ') FROM (
    SELECT status, count(*) AS n FROM orders GROUP BY status ORDER BY count(*) DESC) t;")
report INFO "order status mix" "${order_mix}"

IFS='|' read -r wh_total wh_7d wh_24h wh_age <<<"$(psql_primary "
  SELECT count(*),
         count(*) FILTER (WHERE created_at > now() - interval '7 days'),
         count(*) FILTER (WHERE created_at > now() - interval '24 hours'),
         COALESCE(EXTRACT(epoch FROM now() - max(created_at))::int, -1)
    FROM payment_webhook_events;")"
if [ "${wh_age:--1}" -lt 0 ]; then
  report WARN "payment webhooks" "no event ever recorded"
else
  report INFO "payment webhooks" "${wh_total} total, ${wh_7d} in 7d, ${wh_24h} in 24h, newest $((wh_age / 3600))h ago"
fi

wh_stuck=$(psql_primary "
  SELECT count(*) FROM orders o
   WHERE o.status = 'awaiting_payment'
     AND EXISTS (SELECT 1 FROM payment_webhook_events e WHERE e.order_id = o.id);")
if [ "${wh_stuck:-0}" -gt 0 ]; then
  report FAIL "webhooks applied" "${wh_stuck} order(s) still awaiting_payment despite a delivered webhook"
else
  report OK "webhooks applied" "every delivered webhook moved its order"
fi

printf '\n%s== SUMMARY%s\n' "$C_HEAD" "$C_OFF"
printf '  %s%d OK%s   %s%d WARN%s   %s%d FAIL%s\n' \
  "$C_OK" "$ok_count" "$C_OFF" "$C_WARN" "$warn_count" "$C_OFF" "$C_FAIL" "$fail_count" "$C_OFF"

if [ "$fail_count" -gt 0 ]; then
  printf '\n%sFailures:%s\n' "$C_FAIL" "$C_OFF"
  printf '  - %s\n' "${fail_lines[@]}"
fi
if [ "$warn_count" -gt 0 ]; then
  printf '\n%sWarnings:%s\n' "$C_WARN" "$C_OFF"
  printf '  - %s\n' "${warn_lines[@]}"
fi

if [ "$EMIT_RECORDS" = "1" ]; then
  printf '%s\n' "$RECORD_SENTINEL"
  printf 'meta\thost\t%s\n' "$(hostname)"
  printf 'meta\tgenerated\t%s\n' "$(date -Is)"
  printf 'meta\twindow\t%s\n' "$HOURS"
  printf 'meta\tuptime\t%s\n' "$(uptime -p 2>/dev/null || true)"
  printf 'meta\ttotals\t%s %s %s\n' "$ok_count" "$warn_count" "$fail_count"
  printf '%s\n' "${records[@]}"
fi

[ "$fail_count" -gt 0 ] && exit 2
[ "$warn_count" -gt 0 ] && exit 1
exit 0
