# Deployment

Production runs on a single VPS in São Paulo: the Rails app (Docker, via Kamal) and
PostgreSQL (installed on the host) live on the same box. Active Storage is on
Cloudflare R2, email goes through Brevo, and TLS is terminated by kamal-proxy with a
Let's Encrypt certificate. Background jobs run inside Puma (`SOLID_QUEUE_IN_PUMA=1`),
so there is no separate worker process.

```
Internet :443/:80 -> kamal-proxy (host, Let's Encrypt TLS)
                        -> app container :80 (Thruster -> Puma :3000 + solid_queue)
                             -> host PostgreSQL 17 (via host.docker.internal)
nightly: systemd timer -> pg_dump primary -> rclone -> Cloudflare R2
```

The app reaches host Postgres through `host.docker.internal`, which resolves to the
Docker bridge gateway because the container is started with
`--add-host host.docker.internal:host-gateway` (set in `config/deploy.yml`).

## Prerequisites

- A Hostinger (or equivalent) VPS in São Paulo, Ubuntu 24.04 LTS. Launching on KVM 1
  (1 vCPU / 4 GB / 50 GB NVMe); the config is tuned for it (`WEB_CONCURRENCY=1`,
  `RAILS_MAX_THREADS=3`, 4 GB swap). Resize up to KVM 2 (2 vCPU / 8 GB) if memory or CPU
  get tight (see "When to scale up").
- The domain `prismagames.com.br` with DNS you can edit.
- A Cloudflare R2 bucket for production uploads plus a second bucket (or prefix) for
  database backups, and an R2 API token (access key id + secret).
- A GitHub Personal Access Token with `write:packages` (pushes the image to
  `ghcr.io/erick-tmr/prisma_engine`).
- Docker on your workstation (Kamal builds the image locally and pushes it).
- All production secret values available in your own vault (see "Secrets" below).

## 1. Provision and harden the VPS

Create the VPS with São Paulo as the location and Ubuntu 24.04 as the image. Then, as
root over SSH:

```bash
# Timezone (makes the 04:00 backup timer run in Brasília time)
timedatectl set-timezone America/Sao_Paulo

# Add your SSH public key, then lock SSH to key-only.
mkdir -p ~/.ssh && chmod 700 ~/.ssh
# paste your key into ~/.ssh/authorized_keys, then chmod 600 ~/.ssh/authorized_keys

# In /etc/ssh/sshd_config set:
#   PermitRootLogin prohibit-password
#   PasswordAuthentication no
systemctl reload ssh

# Firewall: deny inbound by default; allow SSH + HTTP/HTTPS; allow Postgres only
# from Docker bridge networks (never the public internet).
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow from 172.16.0.0/12 to any port 5432 proto tcp
ufw --force enable

# Swap (guards against OOM during image builds/migrations on a single box)
fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Unattended security updates
apt-get update && apt-get install -y unattended-upgrades
```

Kamal connects as `root` (Docker needs root). Key-only root login is the right balance
here. If you prefer no root SSH at all, create a `deploy` user in the `docker` group
with passwordless sudo and set `ssh: { user: deploy }` in `config/deploy.yml`; that is
an optional hardening step, not required for v1.

Docker itself is installed later by `kamal setup`, so you do not install it here.

## 2. Install and configure PostgreSQL 17

Ubuntu 24.04 ships PostgreSQL 16; the app targets 17 (dev uses `postgres:17-alpine`),
so install from the PGDG repository.

```bash
apt-get install -y curl ca-certificates
install -d /usr/share/postgresql-common/pgdg
curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail \
  https://www.postgresql.org/media/keys/ACCC4CF8.asc
echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y postgresql-17 postgresql-client-17
```

Create the application role with a strong password. `CREATEDB` lets the container's
`db:prepare` create the four databases on first boot.

```bash
sudo -u postgres psql -c \
  "CREATE ROLE prisma_engine LOGIN CREATEDB PASSWORD 'STRONG_DB_PASSWORD';"
```

Edit `/etc/postgresql/17/main/postgresql.conf`:

```
listen_addresses = '*'
password_encryption = scram-sha-256
```

`listen_addresses = '*'` is safe because ufw blocks 5432 from everywhere except the
Docker bridge. Append to `/etc/postgresql/17/main/pg_hba.conf` (the default file already
has a `127.0.0.1/32 scram-sha-256` line that the backup job uses):

```
# App container on the Docker bridge networks
host    all    prisma_engine    172.16.0.0/12    scram-sha-256
```

`172.16.0.0/12` covers every default Docker network range. Restart and confirm the role
stored a scram verifier:

```bash
systemctl restart postgresql
sudo -u postgres psql -c \
  "SELECT rolname, substr(rolpassword,1,11) FROM pg_authid WHERE rolname='prisma_engine';"
# expect rolpassword starting with SCRAM-SHA-2
```

Verify connectivity the way the app will connect (from inside a container). Run this
after `kamal setup` has installed Docker, or install Docker first to test early:

```bash
docker run --rm --add-host=host.docker.internal:host-gateway \
  -e PGPASSWORD='STRONG_DB_PASSWORD' postgres:17-alpine \
  psql -h host.docker.internal -U prisma_engine -d postgres -c '\conninfo'
```

If this fails after ufw is enabled, check the actual bridge subnet with
`docker network inspect kamal` and widen the `pg_hba`/ufw rule to match.

## 3. DNS

Point both names at the VPS before running `kamal setup` (Let's Encrypt HTTP-01 needs
them resolving):

```
A   prismagames.com.br       -> VPS_IP
A   www.prismagames.com.br   -> VPS_IP
```

Also confirm the R2 public bucket is served from the public host committed in
`config/environments/production.rb` (`config.x.r2_public_host`); that host feeds both
image URLs and the CSP `img_src`.

## 4. Fill in config/deploy.yml

Replace the `REPLACE_ME_*` placeholders in `config/deploy.yml`:

- `servers.web.hosts` -> the VPS IP.

The R2 bucket, endpoint, and public host are committed in the app config
(`config/environments/production.rb` + `config/storage.yml`), not in `deploy.yml`.

## 5. Secrets (Bitwarden)

Secrets are fetched from Bitwarden at deploy time via the `bw` CLI, so nothing secret is
stored on disk or in git (`.kamal/secrets` contains only `bw` lookups).

One-time setup:

1. Install the Bitwarden CLI and log in:
   ```bash
   npm install -g @bitwarden/cli   # or: snap install bw
   bw login                        # email + master password + 2FA
   ```
2. Create one Bitwarden item (Login or Secure Note) named exactly `prisma-engine-prod`,
   with a hidden custom field per secret (field name = the variable name):

   | Field | Value |
   |---|---|
   | `KAMAL_REGISTRY_PASSWORD` | GitHub PAT with `write:packages` |
   | `RAILS_MASTER_KEY` | contents of `config/credentials/production.key` |
   | `PRISMA_ENGINE_DATABASE_PASSWORD` | the Postgres role password |

   The R2 API token (`r2.access_key_id` / `r2.secret_access_key`) is no longer a Bitwarden
   field: it lives in `config/credentials/production.yml.enc`, decrypted at boot by
   `RAILS_MASTER_KEY`. Edit it with `bin/rails credentials:edit --environment production`.

   Brevo SMTP and the Correios tokens follow the R2 pattern too: they go in
   `production.yml.enc` (`brevo.smtp_login` / `brevo.smtp_key`, `correios.api_token` /
   `correios.cartao_api_token`), not Bitwarden.

Before deploying, export your Bitwarden account email. Kamal unlocks the vault, prompting
for your master password if it is locked:

```bash
export BW_ACCOUNT="you@example.com"
```

Verify the master key decrypts the production credentials before deploying:

```bash
bundle exec ruby -e 'require "active_support"; require "active_support/encrypted_configuration";
  c = ActiveSupport::EncryptedConfiguration.new(
        config_path: "config/credentials/production.yml.enc",
        key_path: "config/credentials/production.key",
        env_key: "RAILS_MASTER_KEY", raise_if_missing_key: true);
  puts c.config.keys.inspect'
# expect: [:secret_key_base, :devise]
```

## 6. First deploy

From the repo root on your workstation, with the secrets exported:

```bash
bin/kamal setup
```

This installs Docker and kamal-proxy on the host, logs in to ghcr, builds the amd64
image, pushes it, boots the app container (with the host-gateway mapping), and requests
the TLS certificate. On boot, `bin/docker-entrypoint` runs `db:prepare`, which creates
and migrates all four databases.

Routine deploys after that:

```bash
bin/kamal deploy
```

Useful aliases (defined in `config/deploy.yml`): `bin/kamal console`,
`bin/kamal dbconsole`, `bin/kamal logs`.

## 7. Backups to R2

Backups run on the host. Secrets stay on the host and never enter git.

```bash
# rclone + the script location
apt-get install -y rclone
mkdir -p /opt/prisma_engine /etc/prisma_engine
cp deploy/pg_backup.sh /opt/prisma_engine/pg_backup.sh   # from a checkout/copy of the repo
chmod +x /opt/prisma_engine/pg_backup.sh

# R2 credentials for rclone (root-only). Read the token values with
# `bin/rails credentials:show --environment production` (key `r2:`).
mkdir -p /root/.config/rclone
cat > /root/.config/rclone/rclone.conf <<'EOF'
[r2]
type = s3
provider = Cloudflare
access_key_id = R2_ACCESS_KEY_ID
secret_access_key = R2_SECRET_ACCESS_KEY
endpoint = https://ACCOUNT_ID.r2.cloudflarestorage.com
acl = private
EOF
chmod 600 /root/.config/rclone/rclone.conf

# DB password for pg_dump over localhost (root-only)
echo '127.0.0.1:5432:prisma_engine_production:prisma_engine:STRONG_DB_PASSWORD' > /root/.pgpass
chmod 600 /root/.pgpass

# Backup bucket for the systemd unit (optionally add a HC_PING_URL line to enable
# the failure heartbeat; see "Backups" in infra/README.md)
echo 'R2_BUCKET=your-backup-bucket' > /etc/prisma_engine/backup.env
chmod 600 /etc/prisma_engine/backup.env

# Install the schedule
cp deploy/systemd/prisma-pg-backup.service /etc/systemd/system/
cp deploy/systemd/prisma-pg-backup.timer   /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now prisma-pg-backup.timer
systemctl list-timers prisma-pg-backup.timer

# Run once now and watch the log
systemctl start prisma-pg-backup.service
journalctl -u prisma-pg-backup.service -n 50 --no-pager
```

Retention: 14 daily, plus a weekly copy promoted on Sundays and kept 8 weeks. Tune via
`KEEP_DAILY`/`KEEP_WEEKLY` in `/etc/prisma_engine/backup.env`. For the recommended
server-side backstops (R2 lifecycle rules), tamper protection (R2 bucket locks), and
failure alerting (heartbeat monitor), see the "Backups" section of `infra/README.md`.

### Restore drill (do this at go-live)

```bash
rclone copy r2:your-backup-bucket/postgres/daily/<dumpfile> /tmp/restore/
sudo -u postgres createdb -O prisma_engine prisma_engine_restore
pg_restore --no-owner --role=prisma_engine -d prisma_engine_restore /tmp/restore/<dumpfile>
sudo -u postgres psql -d prisma_engine_restore -c \
  "SELECT (SELECT count(*) FROM orders) AS orders, (SELECT count(*) FROM products) AS products;"
```

An untested backup is not a backup. Confirm the counts look right, then drop the
throwaway database.

## 8. Verify end-to-end

- `bin/kamal logs`: `db:prepare` ran, no credential decrypt error, Puma up, solid_queue
  supervisor started.
- `curl -I https://prismagames.com.br/up` returns 200 with a valid Let's Encrypt cert;
  `http://` redirects to `https://` with no loop.
- The storefront loads over HTTPS and product images render from the R2 public host.
- Checkout creates an Order.
- A registration or password-reset email is delivered through Brevo.
- An hourly job (e.g. `SyncPendingShipmentsJob`) appears in the logs.
- `bin/kamal dbconsole` connects to host Postgres.

## Production logs

The app logs structured JSON (one line per request, via lograge) to STDOUT, captured
by Docker's `json-file` driver. `config/deploy.yml` rotates it at `50m` x `3` (~150 MB
of on-box history). `bin/kamal logs` tails it live. To download logs over SSH and query
them locally in a Loki + Grafana stack (no SaaS), see `docs/log-analysis.md`.

## Troubleshooting

- **Boot crash, `ActiveSupport::MessageEncryptor::InvalidMessage`**: `RAILS_MASTER_KEY`
  is wrong. In production it must be the contents of `config/credentials/production.key`,
  not `config/master.key`.
- **App cannot reach the database**: confirm `--add-host` is on the container
  (`docker inspect <container> --format '{{.HostConfig.ExtraHosts}}'`), that Postgres
  `listen_addresses` includes the bridge, and that the `pg_hba`/ufw subnet matches
  `docker network inspect kamal`.
- **Redirect loop on HTTPS**: `config.assume_ssl` must stay `true` (it is, in
  `production.rb`) so Rails trusts kamal-proxy's `X-Forwarded-Proto`.
- **Images blocked / not loading**: the configured public host (`config.x.r2_public_host`
  in `production.rb`) must be a real resolvable host; it is added to the CSP `img_src`.
- **Wrong PostgreSQL version**: make sure you installed `postgresql-17` from PGDG, not
  the Ubuntu default 16, and that `pg_dump`/`pg_restore` are the v17 binaries.

## When to scale up

The box launches on KVM 1 (1 vCPU / 4 GB). That is enough for low launch traffic because
images are served from R2, the Solid stack avoids a separate Redis, and jobs run in-Puma.
Bump to KVM 2 (2 vCPU / 8 GB) from the Hostinger panel (a few-minute reboot; data
persists) when you see any of:

- `free -h` shows swap persistently in heavy use (brief spikes during a deploy are normal).
- Response times climb or requests queue under normal traffic.
- OOM-kill entries in `journalctl -k` (Postgres or Puma killed).
- A deploy fails or hangs under memory pressure.
- Sustained load average above ~1.5 to 2 on the single core.

After a resize to 2+ cores, consider raising `WEB_CONCURRENCY` to 2 in `config/deploy.yml`.

## Out of scope (later)

GitHub Actions auto-deploy, Postgres high availability / failover, read replicas, a CDN
in front of assets, and external uptime/error monitoring.
