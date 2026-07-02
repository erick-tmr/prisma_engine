# infra/ — reproducible VPS configuration

This directory captures the production host's configuration as code so a blank
Ubuntu 24.04 box can be brought to the exact production state deterministically and
re-run safely. It is the automated counterpart to the manual runbook in
`docs/deployment.md`.

## Layers

| Layer | Owned by | Where |
|-------|----------|-------|
| Create the VPS + DNS records | **manual checklist** (rare, done by hand) | this file, below |
| OS config (SSH, firewall, Postgres, backups) | **Ansible** | `infra/ansible/` |
| Docker + app + TLS | **Kamal** (unchanged) | `config/deploy.yml` |
| Data restore | `rclone` + `pg_restore` | rebuild runbook, below |

Ansible does **not** install Docker: `kamal setup` owns that. Ansible stops at the
edge of Docker and picks back up only for the Cloudflare origin-lock, which needs
Docker's `DOCKER-USER` iptables chain to already exist.

## Prerequisites (control machine / your laptop)

```bash
pipx install ansible          # or: pip install --user ansible
cd infra/ansible
ansible-galaxy collection install -r requirements.yml
```

For a real (non-local) run you also need `bw` (Bitwarden CLI) and `jq` to load
secrets, and this repo checked out with `config/master.key` present.

## Provisioning checklist (replaces Terraform)

Done by hand in the Hostinger + Cloudflare panels. Rare enough that a checklist beats
a state file and the young Hostinger Terraform provider's recreate-is-data-loss risk.

1. **Hostinger → create VPS**: plan **KVM1**, image **Ubuntu 24.04**, datacenter **São
   Paulo**. Attach the `prisma-vps-deploy` SSH public key. Note the assigned IP.
2. **Cloudflare → DNS** (once the domain is live): `A  prismagames.com.br → <IP>` and
   `A  www → <IP>`. Leave **grey cloud** (unproxied) until Let's Encrypt has issued via
   `kamal setup`, then switch to **orange cloud** (proxied).

## Secrets

Bitwarden stays the single source of truth (same as `.kamal/secrets`). `bin/infra-env`
unlocks it and exports the two secrets the roles read from the environment:

- `PRISMA_ENGINE_DATABASE_PASSWORD` (Bitwarden item `prisma-engine-prod`) → Postgres
  role password + `/root/.pgpass`.
- R2 access key / secret (Rails `credentials:show`) + endpoint (`config/storage.yml`)
  → `/root/.config/rclone/rclone.conf`.

```bash
source infra/bin/infra-env      # for real runs only
```

Nothing secret is committed. The three secret files on the host are written `0600`.

## Running Ansible

The play splits into two tag passes because the `DOCKER-USER` chain only exists after
`kamal setup` installs Docker:

```bash
cd infra/ansible

# Pass A — everything except the origin-lock (safe on a bare box, before Kamal)
ansible-playbook -i inventory/production.yml site.yml --tags base --check --diff   # preview
ansible-playbook -i inventory/production.yml site.yml --tags base                  # apply

# Pass B — the Cloudflare origin-lock only (after `kamal setup`)
ansible-playbook -i inventory/production.yml site.yml --tags firewall_edge
```

`--check --diff` is a dry run: it changes nothing and prints exactly what would change.
Always run it first against a real box.

## Local testing (no cloud, no cost)

Validate the whole `base` pass against a throwaway Ubuntu 24.04 VM. A VM (not a bare
container) is required because the roles install systemd units.

```bash
# 1. Launch a local Ubuntu 24.04 VM with your SSH key injected
multipass launch 24.04 --name prisma-test \
  --cloud-init - <<EOF
ssh_authorized_keys:
  - $(cat ~/.ssh/id_ed25519.pub)
EOF

# 2. Point the inventory at it (ubuntu user, become: true handles sudo)
export PRISMA_TEST_IP="$(multipass info prisma-test | awk '/IPv4/{print $2}')"

# 3. A local run needs no real secrets — a dummy DB password is enough
export PRISMA_ENGINE_DATABASE_PASSWORD=localtestpassword

# 4. Converge, then prove idempotency (second run must report 0 changed)
cd infra/ansible
ansible-playbook -i inventory/local.yml site.yml --tags base
ansible-playbook -i inventory/local.yml site.yml --tags base   # expect changed=0

# 5. Spot-check inside the VM
multipass exec prisma-test -- sudo systemctl status postgresql@17-main --no-pager
multipass exec prisma-test -- sudo -u postgres psql -c '\du'
multipass exec prisma-test -- sudo ufw status
multipass exec prisma-test -- sudo fail2ban-client status sshd
multipass exec prisma-test -- systemctl list-timers prisma-pg-backup.timer

# 6. Tear down
multipass delete --purge prisma-test
```

**Not covered locally** (verified the first time we apply to a real box): the
`firewall_cloudflare_lock` role (needs Docker's `DOCKER-USER` chain) and Kamal +
Let's Encrypt TLS (need public DNS + inbound 80/443). Neither is part of the local pass.

## Backups: retention, immutability, and monitoring

The `pg_backup` role installs the nightly job (`deploy/pg_backup.sh` + the systemd
timer). Three things are configured outside Ansible, in the R2 dashboard and a
heartbeat monitor:

### Retention (R2 lifecycle rules)

The script prunes its own uploads (daily kept 14 days, weekly 56 days), but that is
client-side and fails silently if the job stops running. Add server-side lifecycle
rules as a backstop (bucket → Settings → Object lifecycle rules), scoped by prefix
and set a bit longer than the script so they only catch stragglers:

| Prefix | Action |
|--------|--------|
| `postgres/daily/` | Delete after 21 days |
| `postgres/weekly/` | Delete after 70 days |

### Immutability (R2 bucket locks, optional but recommended)

If the VPS is compromised the attacker holds the R2 token and could wipe every
backup. An R2 **bucket lock** (WORM retention, ~14 days) makes recent dumps
undeletable even with valid credentials. It can be added to an existing bucket.
The backup script's prune is deliberately **non-fatal**: a locked object that cannot
yet be deleted logs a warning instead of failing the job, and the lifecycle rules
above reclaim it once the lock expires. Keep the lock retention shorter than or equal
to the lifecycle delete age.

### Failure monitoring (dead-man's-switch)

The common failure is the job silently not running at all (box off, timer disabled),
which a `systemd OnFailure` handler cannot catch. Instead the script pings a heartbeat
URL: `/start` at the beginning, the base URL on success, `/fail` on error. If no
success ping arrives on schedule, the monitor alerts you.

- Create a check on [healthchecks.io](https://healthchecks.io) (hosted free tier or
  self-hosted) with a daily schedule and a grace period.
- Set its ping URL as `HC_PING_URL`, either as a field on the Bitwarden
  `prisma-engine-prod` item (picked up by `infra/bin/infra-env`) or exported before the
  run. The role writes it into `/etc/prisma_engine/backup.env`; leave it unset to
  disable pings. Any URL works, so hosted vs self-hosted is just a different base URL.

## Full rebuild runbook (disaster recovery)

1. Create the VPS + DNS (checklist above). Note the IP.
2. `export PRISMA_PROD_IP=<ip>` and `source infra/bin/infra-env`.
3. `ansible-playbook -i inventory/production.yml site.yml --tags base`
4. Set `servers.web.hosts` + `proxy.hosts` in `config/deploy.yml` to the IP, then
   `kamal setup && kamal deploy`.
5. `ansible-playbook -i inventory/production.yml site.yml --tags firewall_edge`
6. Restore data:
   ```bash
   rclone copy r2:$BACKUP_BUCKET/postgres/daily/<latest>.dump /tmp/restore/
   sudo -u postgres createdb -O prisma_engine prisma_engine_production   # if not pre-created
   pg_restore --no-owner --role=prisma_engine -d prisma_engine_production /tmp/restore/<latest>.dump
   ```
7. Flip the Cloudflare A records to proxied; verify `/up`, TLS, and
   `systemctl list-timers prisma-pg-backup.timer`.
