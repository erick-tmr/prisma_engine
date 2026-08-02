# Log analysis

Production logs are structured JSON. This runbook covers downloading them off the VPS
and querying them locally in a Loki + Grafana stack. No external service, nothing to pay
for, run on demand. Error tracking (Sentry) is deferred; this covers log search only.

## Shortcuts

`bin/log-analysis` wraps the whole flow (the sections below explain each step):

```bash
bin/log-analysis download    # fetch production logs over SSH
bin/log-analysis rehydrate   # start the stack + ingest -> http://127.0.0.1:4000
bin/log-analysis prune       # stop the stack and wipe ingested data (down -v)
bin/log-analysis down        # stop the stack, keep ingested data
```

## How logging works in production

- Rails broadcasts its log to two sinks (`config/environments/production.rb`):
  STDOUT (captured by Docker's `json-file` driver, a bounded ~150 MB live-tail
  buffer for `kamal app logs`), and a rotating **file** `log/production.log`
  (`50m` x `5`, ~300 MB). That file lives on the **persistent named volume**
  `prisma_engine_logs` (`config/deploy.yml`), which is stored on the VPS disk and
  **survives container replacement**, so a deploy no longer discards history. The
  durable copy we download and analyze is this volume file, not the per-container
  Docker log.
- `lograge` (`config/environments/production.rb`) condenses each controller request
  into a single JSON line tagged `event: "request"`: `method`, `path`, `status`,
  `controller`, `action`, `duration` (ms), plus `request_id`, `host`, `remote_ip`
  (the real client IP, read from Cloudflare's `CF-Connecting-IP` header, falling
  back to `request.remote_ip`), `user_agent`, and `user_id`. Raw request params are
  not logged (PII).
- Active Job runs (Solid Queue is in-Puma, so jobs log to the same STDOUT) emit one
  JSON line per event tagged `event: "job"`, via
  `StructuredLogging::ActiveJobLogSubscriber`: `job_event` (enqueue/enqueue_at/perform/
  enqueue_retry/retry_stopped/discard), `job_class`, `job_id`, `queue`, `outcome`
  (e.g. performed/errored), `duration` (ms), `executions`, `arguments`, and `exception` /
  `exception_message` on failure. Arguments are filtered through Rails'
  `config.filter_parameters` (`config/initializers/filter_parameter_logging.rb`), the same
  redaction the request logs use, so PII/secret keys (`email`, `token`, `passw`, ...) log as
  `[FILTERED]`; Active Record records log as their GlobalID, never their attributes. A job can
  drop arguments entirely with `self.log_arguments = false`.
- Solid Queue's own supervisor/worker lifecycle lines, boot lines, and other
  `Rails.logger` output stay plain text. They are still queryable in Loki as raw
  lines, just without parsed fields.
- Active Job lines go to their own durable file, `log/production.jobs.log`
  (`500m` x `5`), on the same named volume. Background work produces far more
  lines than requests do, so it gets 10x the rotation budget and its own file
  rather than competing with request logs for the same window of history.
  `deploy/fetch-production-logs.sh` copies every `*.log*` on the volume, so it
  comes down with the rest.
- Each line in `log/production.log` is a single raw JSON object (the lograge
  request line or the job line), or a plain-text Rails line for boot / SolidQueue
  lifecycle output. There is no Docker json-file envelope to unwrap: Rails writes
  these lines directly to the file.

## Prerequisites

- Docker and Docker Compose on your workstation.
- SSH access to the VPS with your existing key (the same one Kamal uses).
- `PRODUCTION_LOG_HOST` set in `.env` (see `.env.example`). Optionally
  `PRODUCTION_LOG_USER` (default `root`) and `PRODUCTION_LOG_SSH_PORT` (default `22`).

## 1. Fetch logs from the VPS

```bash
deploy/fetch-production-logs.sh
```

This SSHes in, resolves the `prisma_engine_logs` volume's mountpoint on the host
(`docker volume inspect`), and copies `production.log` plus its rotation siblings
(`production.log.0`, `.1`, ...) into `/tmp/prisma-production-logs/prisma_engine_logs/`.
Because the volume outlives containers, this is the full retained history, not just
the current boot. The download is read-only on the host. Writing under the system
`/tmp` keeps these logs out of the repo and lets the OS reclaim the space; override
the location with `PRODUCTION_LOG_DIR` (and the volume name with `PRODUCTION_LOG_VOLUME`).

## 2. Bring up the local stack

```bash
cd deploy/log-analysis
docker compose up -d
```

Loki, Grafana, and Promtail start. Promtail reads `/tmp/prisma-production-logs/`, parses
each raw JSON line into labels (`event`, plus `method`/`status`/`controller`/`action` for
requests and `job_class`/`queue`/`outcome` for jobs) and structured metadata (`request_id`,
`user_id`, `remote_ip`, `user_agent`, `duration`, `job_event`, `job_id`, `executions`), and
ships it to Loki.

Grafana listens on `http://127.0.0.1:4000` (4000, not 3000, so it does not collide with a
local `bin/dev` Rails server).

## 3. Query in Grafana

Open `http://127.0.0.1:4000`, go to Explore (the Loki datasource is preconfigured).
Set the time range wide (last 7 days): rehydrated logs carry their original production
timestamps, not "now". Example LogQL:

```logql
{job="prisma_engine"}                                      # everything
{job="prisma_engine", event="request"}                     # requests only
{job="prisma_engine", status=~"5.."}                       # 5xx responses
{job="prisma_engine", controller="CartController"}         # one controller
{job="prisma_engine"} | json | duration > 500              # requests slower than 500ms
{job="prisma_engine"} | json | request_id="<id>"           # one request, end to end
{job="prisma_engine"} | json | user_id="25"                # every request by one user (abuse trace)
{job="prisma_engine"} | json | remote_ip="203.0.113.7"     # every request from one client IP

{job="prisma_engine", event="job"}                         # all job events
{job="prisma_engine", event="job", outcome="errored"}      # failed job runs
{job="prisma_engine", job_class="SyncShipmentJob"}         # one job class
{job="prisma_engine"} | json | job_id="<id>"               # one job, end to end
{job="prisma_engine"} |= "SolidQueue"                      # raw lifecycle/boot lines (text match)

sum(count_over_time({job="prisma_engine", status=~"5.."}[5m]))        # 5xx rate
sum by (job_class) (count_over_time({job="prisma_engine", outcome="errored"}[1h]))  # job errors by class
```

## 4. Teardown

```bash
docker compose down       # stop; keeps the ingested data volume
docker compose down -v    # stop and wipe ingested data
rm -rf /tmp/prisma-production-logs   # delete the downloaded logs (the OS would reclaim /tmp anyway)
```

To re-ingest fresh logs later, fetch again and `docker compose up -d`. Promtail tracks
read offsets in a named volume, so re-running only ingests new content.

## Sanity-check lograge output locally

The lograge config lives in `production.rb`, so it does not run under `bin/dev`. To eyeball
the JSON format without deploying, temporarily set in `config/environments/development.rb`:

```ruby
config.lograge.enabled = true
config.lograge.formatter = Lograge::Formatters::Json.new
```

Start `bin/dev`, hit any page, confirm the request log is one JSON line, then revert.
The authoritative check is post-deploy: fetch real logs and confirm they parse in Grafana.

## Lighter alternative (no running service)

For a quick look without the stack, query the downloaded ndjson directly. The lines are
raw JSON now (no envelope), so read the field straight off each line:

```bash
duckdb -c "
  SELECT json_extract_string(line, '\$.status') AS status, count(*)
  FROM read_csv('/tmp/prisma-production-logs/**/*.log*', columns={'line':'VARCHAR'}, delim='\x00')
  GROUP BY status ORDER BY 2 DESC"
```

Or browse interactively with `lnav /tmp/prisma-production-logs/`. These have no UI or label
filtering, but need zero setup. Loki + Grafana is preferred for real exploration and is
forward-compatible with Grafana Cloud's free tier if logs later ship off-box.

## Troubleshooting

- **No lines in Grafana.** Widen the time range (logs are old). Confirm
  `reject_old_samples: false` in `loki-config.yaml` and that the `timestamp` stage in
  `promtail-config.yaml` parsed the lograge `time` field.
- **Nothing to fetch / empty download.** `deploy/fetch-production-logs.sh` reads the
  `prisma_engine_logs` volume. It only exists once the deploy that adds it (`volumes:` in
  `config/deploy.yml`) has run; before that, there is no volume to copy from. Confirm with
  `ssh <host> docker volume inspect prisma_engine_logs`.
- **Loki rejects high-cardinality labels.** `request_id`, `user_id`, `remote_ip`,
  `user_agent`, and `duration` are structured metadata, not labels, by design. Only
  `method`/`status`/`controller`/`action` are labels.
- **Grafana won't load / port busy.** Something else owns `127.0.0.1:4000`. Remap the
  Grafana port in `compose.yaml` (`127.0.0.1:<port>:3000`).
- **`structured_metadata` stage rejected by Promtail.** The image is older than 3.x. Drop
  those fields from the stage and extract them on demand in LogQL with `| json`.
