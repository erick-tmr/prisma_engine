# Prisma Engine

Brazilian retro-game e-commerce. Rails 8 backend; first phase is a Bootstrap 4 + jQuery storefront ported from prismagames.com.br. Domain models, real cart, Mercado Pago, NF-e, Melhor Envio land in later phases — see `docs/architecture.md`.

## Commands

- `bin/dev` — Rails server. Needs `docker compose up -d` first for Postgres.
- `bin/setup` — fresh-machine setup, idempotent.
- `bin/share-dev` — public Cloudflare Tunnel for client previews. Reads `SHARE_AUTH_USER` / `SHARE_AUTH_PASSWORD` / `SHARE_TIMEOUT` from `.env`.
- `bin/pre-push-check` — **run before `git push`**. Mirrors CI: rubocop → brakeman → bundler-audit → importmap audit → tests. Fail-fast. `SKIP_TESTS=1` for docs-only pushes.

## Frontend stack — non-obvious

- Storefront uses **Bootstrap 4.6 + jQuery** loaded from public CDNs (jsDelivr / cdnjs / code.jquery.com). Tailwind was deliberately dropped (CSS reset + class collisions). Do not reintroduce.
- `app/views/layouts/application.html.erb` does **not** emit `javascript_importmap_tags`, Turbo, or Stimulus. Those gems stay installed for future admin work but are dormant on the storefront.
- Images live under `public/images/` (vendored). `cdn-meloja.*`, `prismagames.com.br`, and `a.meloja.com.br` URLs must not appear anywhere in `app/` or `public/`.

## Data

- Products are a YAML-backed PORO (`config/products.yml` + `app/models/product.rb`) until a real `Product` ActiveRecord model lands.
- Cart and identification are placeholder views; their `create` actions are no-ops that flash + redirect. Form targets are real Rails routes ready for backend wiring.

## Git workflow

All changes flow through a branch + PR. No direct commits to `main`.

- Start every task from a fresh `main`: `git fetch origin && git switch -c <type>/<short-desc> origin/main` (e.g. `feat/cart-badge`, `fix/pre-push-rails-shutdown`). Never branch off another feature branch — a not-yet-merged base produces conflicting, noisy PRs. Use the same `<type>` prefixes as commit messages (`feat`, `fix`, `chore`, `docs`).
- To check whether commits are already upstream, use `git cherry -v origin/main` (patch-id based). Don't trust `origin/main..HEAD`: squash/rebase merges rewrite SHAs, so that range still lists work that's already in `main`.
- `bin/pre-push-check` must pass before pushing.
- Open a PR with `gh pr create` once the branch is pushed; merge from GitHub.
- Branch protection on `main` blocks direct pushes — fix the cause, never `--force` or bypass.

## Conventions

- Commit signing is on (SSH ed25519). Never pass `--no-verify` or `-c commit.gpgsign=false` — fix the underlying cause if a hook fails.
- Greenfield repo: delete unused code rather than commenting it out, renaming `_var`, or adding backwards-compat shims.
- `bundler-audit` and `brakeman` block on findings. Fix the cause; don't add ignores without flagging it in the PR.
- New env vars: document the variable in `.env.example` (committed) and add to local `.env` (gitignored).

## Sharing the prototype

- `bin/share-dev` boots Rails in `SHARE_MODE=1` behind HTTP basic auth and a hardened middleware stack (no source-leaking error pages, no web-console, `/rails/info|conductor|mailers|db` paths 404'd). Safe for unattended public exposure.
- Postgres is bound to `127.0.0.1:5432` only in `compose.yaml`. Do not switch to `0.0.0.0`.

## Gotchas

- Rails 8 checks pending migrations on every dev request → DB must be running. `docker compose up -d` before `bin/dev`.
- `tmp/snapshot/` is a frozen reference of the live site used during the port. Gitignored; do not commit.
- `.env.example` is the only `.env*` file that ships in the repo (`.gitignore` carves it out).
