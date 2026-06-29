# Log analysis

Production logs are structured JSON. This runbook covers downloading them off the VPS
and querying them locally in a Loki + Grafana stack. No external service, nothing to pay
for, run on demand. Error tracking (Sentry) is deferred; this covers log search only.

## How logging works in production

- Rails logs to STDOUT, captured by Docker's `json-file` driver
  (`config/deploy.yml` rotates it at `50m` x `3`, about 150 MB of on-box history).
- `lograge` (`config/environments/production.rb`) condenses each controller request
  into a single JSON line: `method`, `path`, `status`, `controller`, `action`,
  `duration` (ms), plus `request_id`, `host`, and `user_id`. Raw request params are
  not logged (PII).
- Solid Queue job logs, boot lines, and other `Rails.logger` output stay plain text.
  They are still queryable in Loki as raw lines, just without parsed fields.
- Every line on disk is double-wrapped: the Docker envelope
  `{"log":"<inner>\n","stream":"stdout","time":"..."}` around the inner stdout line.
  The local stack unwraps this for you.

## Prerequisites

- Docker and Docker Compose on your workstation.
- SSH access to the VPS with your existing key (the same one Kamal uses).
- `PRODUCTION_LOG_HOST` set in `.env` (see `.env.example`). Optionally
  `PRODUCTION_LOG_USER` (default `root`) and `PRODUCTION_LOG_SSH_PORT` (default `22`).

## 1. Fetch logs from the VPS

```bash
deploy/fetch-production-logs.sh
```

This SSHes in, finds every app container (the live one plus Kamal's retained exited
ones, so you get history across recent deploys), and copies each container's
`*-json.log` files (rotation siblings included) into `tmp/production-logs/<container-id>/`.
The download is read-only on the host. `tmp/` is gitignored: these logs may contain
PII, so never commit them.

## 2. Bring up the local stack

```bash
cd deploy/log-analysis
docker compose up -d
```

Loki, Grafana, and Promtail start. Promtail reads `tmp/production-logs/`, unwraps the
Docker envelope, parses the lograge JSON into labels (`method`, `status`, `controller`,
`action`) and structured metadata (`request_id`, `user_id`, `duration`), and ships it
to Loki.

Grafana listens on `http://127.0.0.1:3000`. This collides with a local `bin/dev` Rails
server, so don't run both at once, or remap the Grafana port to `127.0.0.1:3001:3000`
in `compose.yaml`.

## 3. Query in Grafana

Open `http://127.0.0.1:3000`, go to Explore (the Loki datasource is preconfigured).
Set the time range wide (last 7 days): rehydrated logs carry their original production
timestamps, not "now". Example LogQL:

```logql
{job="prisma_engine"}                                      # everything
{job="prisma_engine", status=~"5.."}                       # 5xx responses
{job="prisma_engine", controller="CartController"}         # one controller
{job="prisma_engine"} | json | duration > 500              # requests slower than 500ms
{job="prisma_engine"} | json | request_id="<id>"           # one request, end to end
{job="prisma_engine"} |= "SolidQueue"                      # raw job/boot lines (text match)
sum(count_over_time({job="prisma_engine", status=~"5.."}[5m]))   # 5xx rate
```

## 4. Teardown

```bash
docker compose down       # stop; keeps the ingested data volume
docker compose down -v    # stop and wipe ingested data
rm -rf ../../tmp/production-logs   # delete the downloaded logs (may contain PII)
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
double-wrapped, so extract `.log` first, then the inner field:

```bash
duckdb -c "
  SELECT json_extract_string(json_extract_string(line, '\$.log'), '\$.status') AS status,
         count(*)
  FROM read_csv('tmp/production-logs/**/*-json.log', columns={'line':'VARCHAR'}, delim='\x00')
  GROUP BY status ORDER BY 2 DESC"
```

Or browse interactively with `lnav tmp/production-logs/`. These have no UI or label
filtering, but need zero setup. Loki + Grafana is preferred for real exploration and is
forward-compatible with Grafana Cloud's free tier if logs later ship off-box.

## Troubleshooting

- **No lines in Grafana.** Widen the time range (logs are old). Confirm
  `reject_old_samples: false` in `loki-config.yaml` and that the `timestamp` stage in
  `promtail-config.yaml` parsed the envelope time.
- **Lines show as one opaque JSON blob.** The Docker envelope was not unwrapped. Check a
  raw sample (`head -1 tmp/production-logs/*/*-json.log`): the outer keys are
  `log`/`stream`/`time`, and Promtail's first `json` stage plus `output: source: log`
  must run before the inner parse.
- **Loki rejects high-cardinality labels.** `request_id`, `user_id`, and `duration` are
  structured metadata, not labels, by design. Only `method`/`status`/`controller`/`action`
  are labels.
- **Grafana won't load / port busy.** A `bin/dev` server owns `127.0.0.1:3000`. Stop it or
  remap the Grafana port.
- **`structured_metadata` stage rejected by Promtail.** The image is older than 3.x. Drop
  those fields from the stage and extract them on demand in LogQL with `| json`.
