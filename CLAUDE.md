# Prisma Engine

Brazilian retro-game ecommerce. Rails + PostgreSQL, Bootstrap + jQuery storefront ported from prismagames.com.br. Architecture, domain decisions, and state machines live in `docs/architecture.md` — this file is the working contract.

## Commands

- `bin/dev` — Rails server. Run `docker compose up -d` first for Postgres.
- `bin/setup` — fresh-machine setup. Needs `cmake` for `rugged` (undercover): `brew install cmake` / `sudo apt-get install -y cmake pkg-config`.
- `bin/share-dev` — public Cloudflare Tunnel for client previews; reads `SHARE_AUTH_*` from `.env`.
- `bin/pre-push-check` — local CI gauntlet; must pass before push. `SKIP_TESTS=1` for docs-only pushes.
- `npm run test:js` — Vitest+jsdom unit tests for storefront ES modules (`test/javascript/*.test.js`). Node pinned in `.node-version`; `npm install` first. `pre-push-check` runs it too.
- `SKIP_COVERAGE_FLOOR=1 bin/rails test:system` — Capybara + Cuprite (headless Chrome) E2E tests; needs Postgres up. `HEADLESS=0` shows the browser, `DENY_EXTERNAL=0` lifts the no-network fence. Not in `pre-push-check` (CI's `system-test` job runs it). See **System tests (E2E)**.

## Stack invariants

- Storefront is **Bootstrap + jQuery via CDN** (jsDelivr / cdnjs / code.jquery.com). Tailwind was tried and dropped (CSS reset + class collisions). Do not reintroduce.
- `app/views/layouts/application.html.erb` does **not** emit `javascript_importmap_tags`, Turbo, or Stimulus. Those gems exist for future admin work; dormant on the storefront.
- Page JS that warrants unit tests lives in `app/javascript/storefront/*.js` as **self-contained native ES modules**, loaded per-page via `javascript_include_tag "storefront/<name>", type: "module"` in `content_for :scripts` — served by Propshaft, **not** importmap (which stays dormant per above). They read config from `data-*` attributes (no ERB interpolation inside the JS) and self-init via a guarded DOM check, so the same file the browser runs is what the tests import. Third-party plugin-init glue (the jQuery/owl/fancybox/mask block in `application.html.erb`) stays **inline** — it's not unit-testable logic, the JS analogue of `# :nocov:`.
- Images live under `public/images/` (vendored). No `cdn-meloja.*`, `prismagames.com.br`, or `a.meloja.com.br` URLs may appear in `app/` or `public/`.
- `/checkout` (delivery + payment) is the post-cart step — `cart#finalize` routes there (guests log in first). It's a template-first pass: address/payment data are still client-side mocks pending real wiring.
- Postgres is bound to `127.0.0.1:5432` in `compose.yaml` (so a LAN-shared `bin/dev` doesn't expose the DB). Do not switch to `0.0.0.0`.

## Conventions

- Commit signing is on (SSH ed25519). Never pass `--no-verify` or `-c commit.gpgsign=false` — fix the underlying cause if a hook fails.
- Greenfield repo: delete unused code rather than commenting it out, renaming `_var`, or adding backwards-compat shims.
- **No code comments unless asked.** Write self-documenting code (clear names, small methods); do not add explanatory comments. Add a comment only when the user explicitly requests one. Functional pragmas are not "comments" and must stay: `# :nocov:`, `# :reek:…`, `# rubocop:…`, `# nosemgrep:…`, `/* v8 ignore */`, and magic comments.
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

## System tests (E2E)

- **Capybara + Cuprite** (headless Chrome over CDP — no Selenium/WebDriver), in-process, Minitest. Foundation in `test/application_system_test_case.rb`; specs in `test/system/*.rb`. Use `login_as_user` (Warden) for non-auth specs; the auth specs drive the real `/entrar`·`/cadastrar` forms.
- Run **serial** (`parallelize(workers: 1)`) — N headless Chromes on a 2-core CI runner flake. **Never `sleep`**: rely on Capybara's auto-waiting matchers (`assert_selector`, `assert_current_path`); `default_max_wait_time = 2`, animations disabled. Select via the **`data-*` hooks** the views/Vitest specs already share — not Bootstrap classes or pt-BR copy.
- **No test reaches the real network.** Server-side calls (Correios, InfinitePay) are stubbed in-process via `SystemStubs` (`test/system/support/`), exactly like the integration tests; the browser is additionally fenced to localhost via Cuprite's `url_blacklist` of external hosts (`DENY_EXTERNAL=0` lifts it). The InfinitePay hosted-redirect popup is neutralized by stubbing `POST /links` to return a `data:` URL, so the browser popup never leaves the box.
- The CI `system-test` job runs `bin/rails test:system` with `SKIP_COVERAGE_FLOOR=1`: a handful of critical paths must not be held to the whole-app SimpleCov 100% floor (that floor is the unit/integration run's contract). Run it the same way locally.

## Git workflow

- Start every task from a fresh `main`: `git fetch origin && git switch -c <type>/<short-desc> origin/main` (`feat` / `fix` / `chore` / `docs`). Never branch off another feature branch — a not-yet-merged base produces noisy, conflicting PRs.
- **Worktrees live under `~/Code`** named `prisma_engine-<short-desc>` (e.g. `prisma_engine-system-tests`), never inside the repo or `.claude/`. After `git worktree add ~/Code/prisma_engine-<desc> <branch>`, link the Active Storage uploads so product images render: `ln -s ../prisma_engine/storage storage` (relative, points at the main checkout's `storage/` — the gitignored 60M+ of uploads), then `git update-index --skip-worktree storage/.keep` so the dir→symlink swap doesn't show as a deleted `.keep` (leaves only `?? storage`). `public/images` is vendored/tracked, so it needs no linking.
- To check whether commits are already upstream, use `git cherry -v origin/main` (patch-id based), not `origin/main..HEAD` — squash / rebase merges rewrite SHAs.
- `bin/pre-push-check` must pass before pushing. Branch protection on `main` blocks direct pushes — fix the cause, never `--force` or bypass.
- Open PRs with `gh pr create`; merge from GitHub.
- **After every push (and right after opening), verify CI with `gh pr checks <N>`.** The local gauntlet does not cover `Semgrep (new findings)`, `Dependency review`, or `system-test` — a green pre-push can still produce a red PR. For failing checks: `gh run view <run-id> --log-failed`, plus `gh api repos/<owner>/<repo>/code-scanning/alerts` for security gates and `gh api repos/<owner>/<repo>/issues/<N>/comments` for the sticky `ci-quality` comment.
- Refresh PR title/body after every push that meaningfully changes scope. `gh pr edit` can silently exit 1 on a GraphQL Projects-classic deprecation warning; fall back to `gh api repos/<owner>/<repo>/pulls/<N> -X PATCH -f title="..." --field body=@/tmp/pr-body.md`.

## CI gates

One workflow (`.github/workflows/ci.yml`). **Blocking**: rubocop, brakeman, bundler-audit, importmap audit, tests + system-tests, SimpleCov 100% line + branch floor, undercover (changed-line coverage), JS unit tests (Vitest), semgrep `(new findings)`, gitleaks, dependency review (moderate+ CVEs). **Advisory**: reek findings, reported in the sticky `ci-quality` PR comment. Brakeman + Semgrep findings also surface under **Security ▸ Code scanning**. The 100% SimpleCov floor + undercover together enforce both "every changed line is tested" and "no coverage regressions." Mark genuinely un-testable Ruby lines with `# :nocov:`. JS coverage is **separate** (Vitest, `app/javascript/storefront/*.js`) with its **own** 100% threshold in `vitest.config.js` (browser bootstrap excluded via `/* v8 ignore */`, the JS analogue of `# :nocov:`); both Ruby (SimpleCov) and JS (Vitest) totals show in the sticky comment. The `JS unit tests` job is new; add it to main's required-checks list to make it blocking.

## Gotchas

- Rails checks pending migrations on every dev request → DB must be running (`docker compose up -d` before `bin/dev`).
- `tmp/snapshot/` is a frozen reference of the live site used during the port. Gitignored; do not commit.
- `.env.example` is the only `.env*` that ships in the repo (`.gitignore` carves it out).
