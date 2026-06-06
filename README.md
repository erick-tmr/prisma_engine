# prisma_engine

Rails 8 ecommerce platform for Prisma Games — a Brazilian retro Game Boy cartridge store. Made-to-order fulfillment workflow with PIX/parcelamento payments, Correios shipping, NF-e issuance, and an operator workbench for the artisan.

See `docs/architecture.md` for the full architecture and the migration plan from Meloja, and `CLAUDE.md` for the working contract used during AI-assisted development.

## Prerequisites

- Docker Engine + `docker-compose-plugin` (host install — see Docker docs)
- `libpq-dev` (host install via apt)
- `mise` for Ruby version management — `curl https://mise.run | sh`

## Setup

```bash
mise install                # installs Ruby per .tool-versions
cp .env.example .env        # local env overrides; gitignored. Pin SHARE_AUTH_* if sharing.
bin/setup                   # bundle install, docker compose up postgres, db:prepare, then bin/dev
```

`.env` is read at Rails boot via `dotenv` (development + test). Document any new variable in `.env.example` (committed) when adding one.

## Daily commands

```bash
bin/dev                  # Rails server (Puma) — needs `docker compose up -d` first
bin/rails console        # Rails console
bin/rails test           # Minitest, SimpleCov report at coverage/index.html
bin/pre-push-check       # CI parity gate — run before `git push`
bin/share-dev            # public Cloudflare Tunnel for client previews (basic-auth gated)
```

`bin/pre-push-check` runs the same five jobs as CI: `bin/rubocop`, `bin/brakeman --no-pager -q`, `bin/bundler-audit`, `bin/importmap audit`, `bin/rails test`. Use `SKIP_TESTS=1 bin/pre-push-check` for docs-only pushes.

## Sharing the prototype

`bin/share-dev` boots Rails in `SHARE_MODE=1` behind HTTP basic auth, removes web-console, suppresses source-leaking error pages, 404s the `/rails/info|conductor|mailers|db` introspection routes, and opens a Cloudflare Tunnel at a random `https://*.trycloudflare.com` URL. Safe for unattended overnight client demos.

```bash
# Pin stable creds for a bookmarkable URL (otherwise random per run):
echo 'SHARE_AUTH_USER=demo'                       >> .env
echo 'SHARE_AUTH_PASSWORD=at-least-16-chars-long' >> .env
echo 'SHARE_TIMEOUT=8h'                           >> .env  # optional; unset = run forever

bin/share-dev    # prints local + LAN + public URLs and the basic-auth creds
```

## Database

Postgres 17 in Compose (see `compose.yaml`), bound to `127.0.0.1:5432` so a LAN-shared dev server doesn't expose the DB. Defaults: user/password/dev-db all `prisma_engine`. Override via `DATABASE_HOST`, `DATABASE_USER`, `DATABASE_PASSWORD` in `.env`. Production credentials live in encrypted credentials, not `.env`.

## Project structure

Storefront frontend port from prismagames.com.br has shipped:

- Routes mirroring the live site URL shape (`/produtos`, `/produtos/:slug`, `/produto/:slug/:id`, `/pagina/:slug`, `/carrinho`, `/identificacao`).
- Five thin controllers (`pages`, `products`, `categories`, `cart`, `identification`) with no DB yet.
- Bootstrap 4 + jQuery storefront layout, four shared partials (`shared/_header`, `_nav`, `_footer`, `_cookie_banner`), plus a left-side category drawer (`shared/_drawer`).
- `Product` PORO backed by `config/products.yml` (26 products extracted from the live-site snapshot) until a real ActiveRecord model lands.
- 143 product images vendored under `public/images/`.

Domain models, real cart/checkout, InfinitePay, Correios, NF-e, and the admin workbench come in subsequent phases — see `docs/architecture.md` § Migration Plan.
