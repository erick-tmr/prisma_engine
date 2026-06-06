# Prisma Engine

Brazilian retro-game e-commerce. Rails 8 backend; first phase is a Bootstrap 4 + jQuery storefront ported from prismagames.com.br. Domain models, real cart, Mercado Pago, NF-e, Melhor Envio land in later phases — see `docs/architecture.md`.

## Commands

- `bin/dev` — Rails server. Needs `docker compose up -d` first for Postgres.
- `bin/setup` — fresh-machine setup, idempotent. Needs **cmake** present (builds the `rugged` native ext that `undercover` uses for changed-line coverage): `brew install cmake` / `sudo apt-get install -y cmake pkg-config`.
- `bin/share-dev` — public Cloudflare Tunnel for client previews. Reads `SHARE_AUTH_USER` / `SHARE_AUTH_PASSWORD` / `SHARE_TIMEOUT` from `.env`.
- `bin/pre-push-check` — **run before `git push`**. Local subset of CI: rubocop → brakeman → bundler-audit → importmap audit → reek (advisory) → gitleaks (if installed) → tests → undercover changed-line coverage. Fail-fast. `SKIP_TESTS=1` skips tests + undercover (docs-only pushes). **Does not run** `Semgrep (new findings)`, `Dependency review`, or `system-test` — those only run in GitHub Actions, so a green local gauntlet is necessary, not sufficient (see Git workflow).

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
- **After every push to an open PR, and immediately after opening one, verify CI** with `gh pr checks <N>`. The local gauntlet does not cover `Semgrep (new findings)`, `Dependency review`, or `system-test`, so a green pre-push can still produce a red PR. For each failing check: `gh run view <run-id> --log-failed` and, for security gates, `gh api repos/<owner>/<repo>/code-scanning/alerts` to read the actual finding. Also re-read the sticky `ci-quality` comment (`gh api repos/<owner>/<repo>/issues/<N>/comments`) — its content updates after each push. Don't report the work as done while a check is red or while you haven't actually checked.
- After every push that meaningfully changes scope, refresh the PR title/body (`gh pr edit <N>`) so they describe the current state, not the first commit.
- Branch protection on `main` blocks direct pushes — fix the cause, never `--force` or bypass.

## Conventions

- Commit signing is on (SSH ed25519). Never pass `--no-verify` or `-c commit.gpgsign=false` — fix the underlying cause if a hook fails.
- Greenfield repo: delete unused code rather than commenting it out, renaming `_var`, or adding backwards-compat shims.
- `bundler-audit` and `brakeman` block on findings. Fix the cause; don't add ignores without flagging it in the PR.
- New env vars: document the variable in `.env.example` (committed) and add to local `.env` (gitignored).
- Pin every new gem with a pessimistic version constraint (`gem "foo", "~> 1.2"`) — never add an unversioned gem. Use the installed minor as the floor.
- Keep **reek at zero warnings on changed files** (advisory, but treat it as a gate). `bin/pre-push-check` and the CI `ci-quality` comment report them — before each push, check them and either fix the smell or, if it's framework-idiom noise, silence that detector in `.reek.yml` with a comment justifying why. Don't push new reek warnings.

## Third-party integrations (anti-corruption layer)

External API integrations are split into three layers — keep them separate:

- **Infrastructure** — `<Vendor>::Api::*` (e.g. `Correios::Api`). Owns HTTP, auth/tokens, endpoints, timeouts, (de)serialization, and error mapping. Returns **plain data** (hashes/arrays), never a domain model, and **depends on nothing of ours**. Translating a vendor quirk into our error vocabulary (e.g. an SRO message → `InvalidObjectError`) belongs here.
- **Domain** — models + `Shipping::*` (and future bounded-context namespaces). Holds business rules, the interpretation of vendor data, and persistence. Depends on the `Api` client; **never touches Faraday/HTTP**.
- **Application** — jobs / use-case services. Thin: call the `Api` client, hand the data to the domain.

Rules: don't put business rules or persistence in an `Api` client; don't put HTTP in the domain. A new carrier/provider is a new `Api` adapter — the domain shouldn't change. Reference implementation: `app/services/correios/api/` (infra) + `app/services/shipping/` (domain), wired by `SyncShipmentJob`. Rationale in `docs/architecture.md`.

## Sharing the prototype

- `bin/share-dev` boots Rails in `SHARE_MODE=1` behind HTTP basic auth and a hardened middleware stack (no source-leaking error pages, no web-console, `/rails/info|conductor|mailers|db` paths 404'd). Safe for unattended public exposure.
- Postgres is bound to `127.0.0.1:5432` only in `compose.yaml`. Do not switch to `0.0.0.0`.

## CI quality gates

Two workflows run on every PR. `ci.yml` keeps the existing hard gates (rubocop, brakeman, bundler-audit, importmap audit, tests, system-tests) and now prints a `$GITHUB_STEP_SUMMARY` of *what broke* when one fails. `quality.yml` adds **diff-aware** gates — they only judge the lines a PR changes, so existing untested code is grandfathered but all new code is held to the bar:

- **Changed-line coverage** (undercover) — new/changed Ruby lines must be covered by a test, or the PR fails. Mark genuinely un-testable lines with `# :nocov:`.
- **New security findings** (Semgrep `--baseline-commit`) and **secrets** (gitleaks) and **new high-severity gem CVEs** (dependency-review) block the PR. Brakeman + Semgrep findings also show under **Security ▸ Code scanning**.
- **Code smells** (reek, changed files) are advisory — reported in the sticky `ci-quality` PR comment, never blocking.

These `quality.yml` jobs must be added to `main`'s required status checks in branch protection to actually block merges.

## Investigating memory

Memory profiling is local and on-demand — not a CI gate (too noisy for a storefront this small). `derailed_benchmarks` + `memory_profiler` live in the `:development` group:

- `bundle exec derailed exec perf:mem` — memory each `require` adds at boot, by source.
- `bundle exec derailed exec perf:objects` — object allocation by call site (via memory_profiler).
- `bundle exec derailed exec perf:mem_over_time` — RSS across repeated requests; steady growth signals a leak, a plateau is healthy.

Reach for these when a feature looks heavy; track production memory via APM once there's real traffic.

## Gotchas

- Rails 8 checks pending migrations on every dev request → DB must be running. `docker compose up -d` before `bin/dev`.
- `tmp/snapshot/` is a frozen reference of the live site used during the port. Gitignored; do not commit.
- `.env.example` is the only `.env*` file that ships in the repo (`.gitignore` carves it out).
