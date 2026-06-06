# prisma_engine

Rails 8 ecommerce platform for Prisma Games — a Brazilian retro Game Boy cartridge store. Made-to-order fulfillment workflow with Pix/parcelamento payments, Correios shipping, NF-e issuance, and an operator workbench for the artisan.

See `docs/architecture.md` for the full architecture and `CLAUDE.md` for the working contract used during AI-assisted development.

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

`bin/pre-push-check` runs the local subset of the CI gauntlet — rubocop → brakeman → bundler-audit → importmap audit → reek (advisory) → gitleaks (if installed) → semgrep diff-mode (if semgrep or docker is installed) → tests → undercover (changed-line coverage). Fail-fast. `SKIP_TESTS=1 bin/pre-push-check` skips tests + undercover for docs-only pushes. The local pass does **not** cover `Semgrep (new findings)`, `Dependency review`, or `system-test` — those run only in GitHub Actions, so verify CI on the PR (`gh pr checks <N>`). See `CLAUDE.md` § CI quality gates for the full contract.

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

- Routes mirroring the live site URL shape (`/produtos`, `/produtos/:slug`, `/produto/:slug`, `/pagina/:slug`, `/carrinho`, `/identificacao`).
- Five thin controllers (`pages`, `products`, `categories`, `cart`, `identification`). `cart#create` and `identification#create` are no-op flash-and-redirect placeholders until checkout is wired.
- Bootstrap 4 + jQuery storefront layout, four shared partials (`shared/_header`, `_nav`, `_footer`, `_cookie_banner`), plus a left-side category drawer (`shared/_drawer`).
- 143 product images vendored under `public/images/`.

ActiveRecord catalog is in place — `Category`, `Product` (FriendlyId-slugged, history-enabled), `ProductOption`, `ProductPhoto` (Active Storage), `Tag` / `ProductTag`, `Question`.

Correios integration shipped: pré-postagem creation (`Shipping::CreatePrePostagem` → `Correios::Api::PrePostagem`) and hourly rastro polling (`SyncPendingShipmentsJob` → `SyncShipmentJob`). See `docs/architecture.md` § 1.1 for the three-layer pattern any new vendor follows.

Cart, checkout, InfinitePay, NF-e issuance, and the admin workbench land next — see `docs/architecture.md` § 4 (Domain Problems) and § 5 (MVP Build Order).
