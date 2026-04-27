# prisma_engine

Rails 8 ecommerce platform for Prisma Games — a Brazilian retro Game Boy cartridge store. Made-to-order fulfillment workflow with PIX/parcelamento payments, Correios/Melhor Envio shipping, NF-e issuance, and an operator workbench for the artisan.

See `docs/architecture.md` for the full architecture and the migration plan from Meloja.

## Prerequisites

- Docker Engine + `docker-compose-plugin` (host install — see Docker docs)
- `libpq-dev` (host install via apt)
- `mise` for Ruby version management — `curl https://mise.run | sh`

## Setup

```bash
mise install                  # installs Ruby per .tool-versions
bundle install                # gems into mise's Ruby gem dir
docker compose up -d postgres # starts Postgres 17 in Compose
bin/setup                     # idempotent: bundle check, db:prepare, log clear, then bin/dev
```

## Daily commands

```bash
bin/dev                            # Puma + Tailwind watch (foreman, see Procfile.dev)
bin/rails test                     # Minitest, with SimpleCov coverage report at coverage/index.html
bin/rails console                  # Rails console
bin/brakeman --no-pager            # static security analysis
bundle exec bundle-audit check --update  # CVE check on Gemfile.lock
bin/rubocop                        # rubocop-rails-omakase
```

## Database

Postgres 17 in Compose (see `compose.yaml`). Defaults: user/password/dev-db all `prisma_engine`. Override via env: `DATABASE_HOST`, `DATABASE_USER`, `DATABASE_PASSWORD`. Production credentials in encrypted credentials.

## Project structure (current)

The app is greenfield. Today the repo only contains the Rails 8 scaffold + Postgres compose + tooling. Domain modeling, storefront views, and the admin workbench come in subsequent phases — see `docs/architecture.md` § Migration Plan.
