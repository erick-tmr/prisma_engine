# Prisma Engine

Brazilian retro-game ecommerce. Rails 8 + PostgreSQL, Bootstrap 4 + jQuery storefront ported from prismagames.com.br. Architecture, domain decisions, and state machines live in `docs/architecture.md` — this file is the working contract.

## Commands

- `bin/dev` — Rails server. Run `docker compose up -d` first for Postgres.
- `bin/setup` — fresh-machine setup. Needs `cmake` for `rugged` (undercover): `brew install cmake` / `sudo apt-get install -y cmake pkg-config`.
- `bin/share-dev` — public Cloudflare Tunnel for client previews; reads `SHARE_AUTH_*` from `.env`.
- `bin/pre-push-check` — local CI gauntlet; must pass before push. `SKIP_TESTS=1` for docs-only pushes.

## Stack invariants

- Storefront is **Bootstrap 4.6 + jQuery via CDN** (jsDelivr / cdnjs / code.jquery.com). Tailwind was tried and dropped (CSS reset + class collisions). Do not reintroduce.
- `app/views/layouts/application.html.erb` does **not** emit `javascript_importmap_tags`, Turbo, or Stimulus. Those gems exist for future admin work; dormant on the storefront.
- Images live under `public/images/` (vendored). No `cdn-meloja.*`, `prismagames.com.br`, or `a.meloja.com.br` URLs may appear in `app/` or `public/`.
- `/carrinho` and `/identificacao` are placeholder views — `create` actions are flash-and-redirect no-ops until checkout lands.
- Postgres is bound to `127.0.0.1:5432` in `compose.yaml` (so a LAN-shared `bin/dev` doesn't expose the DB). Do not switch to `0.0.0.0`.

## Conventions

- Commit signing is on (SSH ed25519). Never pass `--no-verify` or `-c commit.gpgsign=false` — fix the underlying cause if a hook fails.
- Greenfield repo: delete unused code rather than commenting it out, renaming `_var`, or adding backwards-compat shims.
- Pin every new gem with a pessimistic version constraint (`gem "foo", "~> 1.2"`). Floor at the installed minor.
- New env vars: document in `.env.example` (committed), set the value in `.env` (gitignored).
- `bundler-audit` + `brakeman` block on findings. Fix the cause; don't add ignores without flagging it in the PR.
- Keep **reek at zero warnings on changed files** (advisory, treated as a gate). Either fix the smell or silence the detector in `.reek.yml` with a comment justifying why.
- Customer-facing strings are **pt-BR**. Brand names follow official source: `Pix` (capital P only — Banco Central style), `InfinitePay` (one word). Never `PIX`, `Mercado Pago`, or `Pagar.me` — InfinitePay is the locked-in PSP. **No boleto** — InfinitePay doesn't issue one.

## Third-party integration pattern

Every external service is wrapped in three layers. Full rationale in `docs/architecture.md` § 1.1.

- **`<Vendor>::Api::*`** (`app/services/correios/api/`) — HTTP, auth, (de)serialization, error mapping. Returns plain data; depends on nothing of ours. Translating a vendor quirk into our own error vocabulary (e.g. an SRO message → `InvalidObjectError`) belongs here.
- **`<Domain>::*`** + AR model (`app/services/shipping/` + `Shipment`) — business rules, factories, lifecycle interpretation. Depends on the `Api` client; never touches HTTP.
- **Jobs / controllers** — thin wiring between the two.

No business rules in `Api::*`. No HTTP in the domain. A new vendor (or a vendor swap) is a new `Api` adapter — the domain shouldn't change.

## Git workflow

- Start every task from a fresh `main`: `git fetch origin && git switch -c <type>/<short-desc> origin/main` (`feat` / `fix` / `chore` / `docs`). Never branch off another feature branch — a not-yet-merged base produces noisy, conflicting PRs.
- To check whether commits are already upstream, use `git cherry -v origin/main` (patch-id based), not `origin/main..HEAD` — squash / rebase merges rewrite SHAs.
- `bin/pre-push-check` must pass before pushing. Branch protection on `main` blocks direct pushes — fix the cause, never `--force` or bypass.
- Open PRs with `gh pr create`; merge from GitHub.
- **After every push (and right after opening), verify CI with `gh pr checks <N>`.** The local gauntlet does not cover `Semgrep (new findings)`, `Dependency review`, or `system-test` — a green pre-push can still produce a red PR. For failing checks: `gh run view <run-id> --log-failed`, plus `gh api repos/<owner>/<repo>/code-scanning/alerts` for security gates and `gh api repos/<owner>/<repo>/issues/<N>/comments` for the sticky `ci-quality` comment.
- Refresh PR title/body after every push that meaningfully changes scope. `gh pr edit` can silently exit 1 on a GraphQL Projects-classic deprecation warning; fall back to `gh api repos/<owner>/<repo>/pulls/<N> -X PATCH -f title="..." --field body=@/tmp/pr-body.md`.

## CI gates

One workflow (`.github/workflows/ci.yml`). **Blocking**: rubocop, brakeman, bundler-audit, importmap audit, tests + system-tests, SimpleCov 100% line + branch floor, undercover (changed-line coverage), semgrep `(new findings)`, gitleaks, dependency review (moderate+ CVEs). **Advisory**: reek findings, reported in the sticky `ci-quality` PR comment. Brakeman + Semgrep findings also surface under **Security ▸ Code scanning**. The 100% SimpleCov floor + undercover together enforce both "every changed line is tested" and "no coverage regressions." Mark genuinely un-testable Ruby lines with `# :nocov:`.

## Gotchas

- Rails 8 checks pending migrations on every dev request → DB must be running (`docker compose up -d` before `bin/dev`).
- `tmp/snapshot/` is a frozen reference of the live site used during the port. Gitignored; do not commit.
- `.env.example` is the only `.env*` that ships in the repo (`.gitignore` carves it out).
