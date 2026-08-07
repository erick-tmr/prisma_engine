# VPS health check

A read-only sanity sweep of the production VPS. Nothing it runs mutates the box: every
check inspects state, none of them restart, prune, migrate or write. Run it whenever you
want to know the box is fine, and after any deploy that touches infrastructure.

```bash
bin/prisma health                    # 24h log window
bin/prisma health --hours 72         # wider window after a quiet weekend
bin/prisma health --verify-restore   # also prove the newest R2 dump is readable
bin/prisma health --html --open      # write an HTML report and open it
bin/prisma health --no-color > /tmp/health.txt
```

Exit status is meaningful, so it works in a pipeline or a cron: **0** all clear,
**1** warnings only, **2** at least one failure.

## How it runs

`deploy/vps-healthcheck.sh` is a thin local wrapper. It reads the same `.env` keys as
`deploy/fetch-production-logs.sh` (`PRODUCTION_LOG_HOST`, optionally
`PRODUCTION_LOG_USER` / `PRODUCTION_LOG_SSH_PORT`), resolves the sha of `origin/main`
and the public hostname from `config/deploy.yml`, then pipes
`deploy/vps-healthcheck.remote.sh` to the VPS over stdin and runs it there.

## HTML report

`--html [PATH]` writes a self-contained report (no external CSS, fonts or scripts) that
defaults to `tmp/vps-health-<timestamp>.html`, which is gitignored. `--open` launches it,
`--quiet` skips the terminal copy when you only want the file.

The remote script then also emits one tab-separated record per check after a sentinel
line. The wrapper splits the stream, prints the human half and pipes the records to
`deploy/vps-healthcheck-report.py`, which renders the page: a verdict pill, passing /
warning / failure tiles, and one table per section. It follows the viewer's colour
scheme and prints cleanly, so it works as an artefact to file after an incident.

The checks execute **on the box** rather than locally on purpose: the durable Rails logs
are ~80 MB on a named volume, and scanning them in place beats downloading them. Use
`deploy/fetch-production-logs.sh` + the Loki stack when you want to *explore* the logs;
use this when you want a verdict.

## What it checks

| Section | Checks |
| --- | --- |
| Host | disk and inode use per filesystem, memory available, swap, load vs core count, pending reboot, NTP sync, uptime |
| Security | ufw active and its open ports, fail2ban jails and ban count, ssh auth failures, unattended-upgrades |
| Docker / app | web container running and restart count, deployed sha vs `origin/main`, kamal-proxy, reclaimable docker space, origin smoke test, Rails `/up`, edge smoke test through Cloudflare, origin TLS cert expiry |
| Postgres | reachable, size, connections vs `max_connections`, idle-in-transaction age, longest active query, cache hit ratio, deadlocks, temp files, dead-tuple ratio, never-vacuumed tables, int4 sequence headroom |
| Solid Queue | failed executions, ready/claimed/scheduled depth, oldest unfinished job, worker heartbeat freshness |
| Backups | timer enabled and active, last run exit status, newest daily age and size, retention count, size sanity against the recent median, weekly promotion age, which databases are deliberately not dumped |
| Downdetector | `HC_PING_URL` present, egress to the ping host, monitor status via the healthchecks.io API when a key is set, coverage gaps |
| Integrations | InfinitePay webhook endpoint reachable and rejecting unknown tokens, Correios reachable and authenticating on both tokens |
| Logs | request volume, 5xx, 404, busiest client, scanner user agents, job failures and retries with exception names, Correios `PPN-`/`SRO-`/`RTL-` codes, raw exception lines |
| Application | labels stuck mid-saga, labels carrying a persisted error, orders parked at `label_issued`, order status mix, unprocessed payment webhooks |

Thresholds live in one block at the top of `deploy/vps-healthcheck.remote.sh`. They are
tuned to the current box (1 core, 3.8 GB RAM, 48 GB disk); revisit them if it is resized.

## Integrations

Both third parties are probed for real, because "the site loads" does not prove either one
works. A networking change once broke outbound Correios calls while the storefront stayed
up, which is exactly the failure this section exists to catch.

- **Correios** runs inside the app container via `bin/rails runner`, so it exercises the
  same network path, credentials and client the jobs use. It makes one `Cep.find` (the
  `api_token`), one `PrePostagemStatus.fetch` (the `cartao_api_token`, which the label
  pipeline depends on and which nothing else exercises between emissions) and one
  `Tracking.fetch`. All three are read-only lookups: nothing is created, no recibo is
  bought. A transient 5xx or timeout reports as a warning, an auth or protocol failure as
  a failure, so a Correios wobble is not mistaken for a broken integration.
- **InfinitePay** is inbound, so it is probed from the outside in: a POST to the real
  public webhook URL with an unknown token, which must come back **401**. That single call
  proves DNS, Cloudflare, the origin lock, kamal-proxy, Rails routing and the per-order
  token check are all intact. A **200** would mean the token check stopped running and is
  reported as a failure. The probe carries a junk token on purpose, so no order matches and
  nothing is written.

Never point the webhook probe at a real `orders.webhook_token`. A valid token with a
fabricated payload would confirm an order that was never paid.

## The downdetector

The heartbeat is a [healthchecks.io](https://healthchecks.io) dead-man's-switch, set up in
`infra/README.md`. `deploy/pg_backup.sh` pings `/start` when the nightly dump begins, the
base URL on success and `/fail` on error, so a backup that stops running raises an alert
even though no process is left to report it. Ansible writes the URL to
`/etc/prisma_engine/backup.env`.

Two things this section is careful about:

- **It never sends a ping.** Hitting the ping URL would be indistinguishable from a real
  signal and would mask a genuinely stalled backup. The checks confirm the URL is set and
  the host is reachable; they do not exercise it.
- **An empty `HC_PING_URL` is a failure, not a warning.** `hc_ping` returns early when it
  is blank, so the backup keeps working and the monitoring silently does not exist. That
  is the exact shape of problem this sweep is meant to catch.

To assert the monitor itself is up rather than merely reachable, put a read-only
healthchecks.io API key in `.env` as `HEALTHCHECKS_API_KEY`. The check then reads
`/api/v3/checks/` and fails when any check is not `up`, and warns when one has not been
pinged today.

### Known coverage gap

The heartbeat covers the **backup job only**. Nothing pings on behalf of the web app, so a
site outage at 3am raises no alert; you would find out from a customer. Closing it does
not need a new vendor: a systemd timer on the VPS that curls `/up` and pings a second
healthchecks.io check turns the same dead-man's-switch into whole-box coverage, because a
dead box stops pinging. An external prober (Cloudflare Health Checks, UptimeRobot,
BetterStack) additionally catches the case where the box is fine but the network path is
not.
