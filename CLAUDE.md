# Prisma Engine

Brazilian retro-game ecommerce. Rails + PostgreSQL, Bootstrap + jQuery storefront ported from prismagames.com.br. Architecture, domain decisions, and state machines live in `docs/architecture.md`; this file is the working contract.

## Commands

- `bin/dev`: Rails server. Run `docker compose up -d` first for Postgres.
- `bin/setup`: fresh-machine setup. Needs `cmake` for `rugged` (undercover): `brew install cmake` / `sudo apt-get install -y cmake pkg-config`.
- `bin/share-dev`: public Cloudflare Tunnel for client previews; reads `SHARE_AUTH_*` from `.env`.
- `bin/rails dev:emails`: development only. Delivers one example of every mailer e-mail (every method of every preview in `test/mailers/previews/`) to the letter_opener inbox at `/cartas`, so the whole set can be reviewed side by side. Run `bin/rails db:seed` first: the previews pick real records, and the seeds guarantee an order with tracking data plus clients on 1, 2 and 3 strikes so the shipping and strike e-mails render in full.
- `bin/pre-push-check`: local CI gauntlet; must pass before push. `SKIP_TESTS=1` for docs-only pushes.
- `npm run test:js`: Vitest+jsdom unit tests for storefront ES modules (`test/javascript/*.test.js`). Node pinned in `.node-version`; `npm install` first. `pre-push-check` runs it too.
- `SKIP_COVERAGE_FLOOR=1 bin/rails test:system`: Capybara + Cuprite (headless Chrome) E2E tests; needs Postgres up. `HEADLESS=0` shows the browser, `DENY_EXTERNAL=0` lifts the no-network fence. Not in `pre-push-check` (CI's `system-test` job runs it). See **System tests (E2E)**.
- `bin/prisma <action>`: project CLI. `bin/prisma deploy` is the routine production deploy: fetches, moves to `main`, hard-resets onto `origin/main` and runs `kamal deploy`, so what ships is exactly the remote. Refuses on a dirty tree or when `main` holds commits `origin/main` does not; `--yes` skips the confirmation. `bin/prisma help` lists the actions. Runbook: `docs/deployment.md`.
- `deploy/fetch-production-logs.sh`: download production logs over SSH, then query them in the local Loki + Grafana stack under `deploy/log-analysis/`. Production logs are structured JSON (lograge). Runbook: `docs/log-analysis.md`.
- `deploy/seed-prod-catalog.sh`: one-off upload of the initial catalog + hero banner images to the prod R2 bucket via an SSH tunnel to the prod DB. Runbook: `docs/seeding-images.md`. Catalog images are gitignored, not committed.

## Stack invariants

- Storefront is **Bootstrap + jQuery, self-hosted via Propshaft**: third-party libs are vendored under `app/assets/{stylesheets,javascripts}/vendor/` (provenance-verified, no CDN). Tailwind was tried and dropped (CSS reset + class collisions). Do not reintroduce. Do not re-add CDN `<link>`/`<script>` tags or `preconnect` hints.
- The storefront ships **no application JavaScript through the importmap**. The `application`/Turbo/Stimulus pins in `config/importmap.rb` stay **inert** (listed but never imported), so Turbo/Stimulus do not boot on the storefront, so don't start emitting `application`. **Bootstrap is CSS-only** (`vendor/bootstrap.min.css` for the reset + utility classes); its JS bundle is not loaded. Interactive widgets are **self-contained native ES modules** under `app/javascript/storefront/*.js` (e.g. the FAQ accordion in `storefront/faq.js`), loaded per-page via `javascript_include_tag`; see the next bullet. A new dropdown/modal/accordion is a new such module, not a Bootstrap JS import.
- Page JS that warrants unit tests lives in `app/javascript/storefront/*.js` as **self-contained native ES modules**, loaded per-page via `javascript_include_tag "storefront/<name>", type: "module"` in `content_for :scripts`, served by Propshaft, **not** via the importmap. They read config from `data-*` attributes (no ERB interpolation inside the JS) and self-init via a guarded DOM check, so the same file the browser runs is what the tests import. jQuery + its plugins (owl/fancybox/mask/input-spinner) are classic vendored `<script>`s. Their plugin-init glue (the jQuery block in `application.html.erb`) stays **inline** in a nonce'd `javascript_tag`; it's not unit-testable logic, the JS analogue of `# :nocov:`.
- A strict **Content Security Policy** is enforced (`config/initializers/content_security_policy.rb`): everything is `:self` (script/style/font/img/connect), `object-src 'none'`, with a per-session nonce on `script-src` for the inline glue. **No `'unsafe-inline'`.** New inline `<script>`/`<style>`, inline `on*=` handlers, inline `style=` attributes, or external asset hosts will be blocked. Vendor the asset (Propshaft) or use `data-*` + CSSOM (see the `--avatar-gradient` pattern in `_drawer`/`_nav`) instead.
- Images live under `public/images/` (vendored). No `cdn-meloja.*`, `prismagames.com.br`, or `a.meloja.com.br` URLs may appear in `app/` or `public/`.
- **Active Storage does no image processing**: `config.active_storage.variant_processor = :disabled`. Resizing is Cloudflare Image Transformations at the edge, and `Storefront::ImageSource` hands out the blob URL untouched. So `.variant(...)` silently returns the original. The whole toolchain is gone to match: no `image_processing` gem, no `libvips` in the Dockerfile or CI. Re-enabling server-side variants means restoring all four (processor, gem, `ruby-vips`, and the `libvips` package in both Dockerfile stages and both CI jobs), so treat it as an infrastructure change, not a config flip.
- `/checkout` (delivery + payment) is the post-cart step; `cart#finalize` routes there (guests log in first). It's a template-first pass: address/payment data are still client-side mocks pending real wiring.
- Postgres is bound to `127.0.0.1:5432` in `compose.yaml` (so a LAN-shared `bin/dev` doesn't expose the DB). Do not switch to `0.0.0.0`.

## Conventions

- Commit signing is on (SSH ed25519). Never pass `--no-verify` or `-c commit.gpgsign=false`; fix the underlying cause if a hook fails.
- Greenfield repo: delete unused code rather than commenting it out, renaming `_var`, or adding backwards-compat shims.
- **No code comments unless asked.** Write self-documenting code (clear names, small methods); do not add explanatory comments. Add a comment only when the user explicitly requests one. Functional pragmas are not "comments" and must stay: `# :nocov:`, `# :reek:…`, `# rubocop:…`, `# nosemgrep:…`, `/* v8 ignore */`, and magic comments.
- Pin every new gem with a pessimistic version constraint (`gem "foo", "~> 1.2"`). Floor at the installed minor.
- New env vars: document in `.env.example` (committed), set the value in `.env` (gitignored).
- `bundler-audit` + `brakeman` block on findings. Fix the cause; don't add ignores without flagging it in the PR.
- Keep **reek at zero warnings on changed files**: advisory in CI (it only annotates the sticky `ci-quality` comment), but blocking in `bin/pre-push-check`. Either fix the smell or silence the detector in `.reek.yml` with a comment justifying why.
- Customer-facing strings are **pt-BR**. Brand names follow official source: `Pix` (capital P only, Banco Central style), `InfinitePay` (one word). Never `PIX`, `Mercado Pago`, or `Pagar.me`; InfinitePay is the locked-in PSP. **No boleto**: InfinitePay doesn't issue one.
- **No em-dashes (`—`) anywhere in the repo**: storefront strings, backoffice copy, code comments, docs, commit messages, PR descriptions. They read as AI-generated. Use commas, periods, parentheses, colons or a rewrite instead. Page titles use a pipe (`<Page> | Prisma Games`); an interpunct (`·`) separates values in a line (`Itajubá · MG · CEP ...`) and an en-dash (`–`) marks an empty table cell. The only surviving em-dashes are in vendored assets, which are never edited.

## Third-party integration pattern

Every external service is wrapped in three layers. Full rationale in `docs/architecture.md` § 1.1.

- **`<Vendor>::Api::*`** (`app/services/correios/api/`): HTTP, auth, (de)serialization, error mapping. Returns plain data; depends on nothing of ours. Translating a vendor quirk into our own error vocabulary (e.g. an SRO message → `InvalidObjectError`) belongs here.
- **`<Domain>::*`** + AR model (`app/services/shipping/` + `Shipment`): business rules, factories, lifecycle interpretation. Depends on the `Api` client; never touches HTTP.
- **Jobs / controllers**: thin wiring between the two.

No business rules in `Api::*`. No HTTP in the domain. A new vendor (or a vendor swap) is a new `Api` adapter; the domain shouldn't change.

### Correios wire logging is a production requirement

`Correios::Api::Client#trace_requests` attaches Faraday's `:logger` middleware with `headers: true, bodies: true` at `:info`, so **every Correios call logs in full**: method, URL, request headers, request body, response status, response headers, response body. This is deliberate and must stay on in production. Correios is the hardest provider we integrate: the documentation is thin and often wrong, failures arrive as undocumented `PPN-*` / `SRO-*` codes buried in a 200 body, and the gateway's real behaviour (rate-limit headers, async label generation, DCe validation) was only ever learned by reading actual traffic. When a pré-postagem sticks or a label never generates, the exact bytes we sent and received are the only evidence we have.

- **Do not remove, downgrade to `:debug`, sample, or narrow it to headers-only** as a log-volume optimization. It is the majority of `production.log` by line count, and that cost is accepted.
- **`REDACT_BEARER` is the part to preserve.** Tokens are filtered out of the dump; keep that filter working when touching this code, and keep new secrets out of the logged bodies.
- If retention becomes the problem, raise the rotation budget in `config/environments/production.rb`, do not cut the tracing. Structured request/job lines already live in their own files (`production.log` / `production.jobs.log`), so verbose wire traces never hide the lograge signal.
- `Meta::Api::Client` uses the same middleware for the same reason.

### The label pipeline is a saga

`Shipping::EmitLabel.resume(order)` reads the persisted `ShippingLabel#state` and enqueues the job for that step. It is safe to call at any time, from anywhere, any number of times: progress lives in the database, never in an in-memory handoff, so a replay after a crash, a deploy, a Correios timeout, or a repeated operator click converges on the same result. **Do not add deduplication to `resume`, and do not treat repeated enqueues as a correctness bug.** Re-deriving the next step from stored state is the mechanism that makes the chain resumable.

Idempotency is enforced at the write boundaries instead:

- `Order#claim_status` is a compare-and-swap (`where(id:, status: previous).update_all(...)` must affect exactly one row). Losers no-op, so N duplicate `advance_to_label_issued!` calls still produce one `status_changes` row and one customer email.
- `ShippingLabel#claim_requesting!` is the same CAS on `prepost_confirmed → requesting`, so only one `RequestLabelJob` ever buys a recibo.
- `mark_ready!` is a plain column update (no Active Storage attachment), and `DownloadLabel` reads `label.recibo_id` fresh off the row rather than from a captured argument. Parallel downloads therefore hit the same recibo, get the same PDF, and write the same bytes. That harmlessness is a property to preserve, not an accident: passing the recibo as a job argument would break it.

**Every job that reaches Correios carries backoff and a concurrency cap**, and a new one must too:

```ruby
retry_on Correios::Api::TransientError,
         ActiveRecord::Deadlocked,
         ActiveRecord::LockWaitTimeout,
         wait: :polynomially_longer, attempts: 5

limits_concurrency to: 5, key: "correios_cartao"
```

`:polynomially_longer` is Rails' current name for what it used to call `:exponentially_longer` (`attempt ** 4` seconds plus jitter, so waits of roughly 3s, 20s, 95s, 290s). It lives on `Shipping::LabelStep` (inherited by `CreatePrePostagemJob` / `RequestLabelJob` / `DownloadLabelJob`), on `Shipping::ConfirmPrePostagemJob`, and on `SyncShipmentJob` (keyed per shipment instead). Two traps in that snippet, both real:

- **`retry_on` governs only the exceptions it names.** A poll loop that raises and rescues its own error inside the job never reaches it and needs its own schedule. `ConfirmPrePostagemJob` is exactly that: `PrePostagemPending` is rescued internally and rescheduled by hand, so its spacing comes from `PREPOSTAGEM_POLL_BASE_DELAY * 2**(attempt - 1)`, capped at `PREPOSTAGEM_POLL_MAX_DELAY`. Correios promises no promotion deadline (one object sat at `Pendente` for 9m39s while siblings created the same second promoted instantly), so that window must stay generous.
- **`limits_concurrency` is scoped per job class, not per key.** Solid Queue's default group is `self.class.name`, so the real key is `"<JobClass>/correios_cartao"` and the four label jobs hold four independent 5-slot budgets, not one shared 5. Within a class the key is a static string, so every order does contend for those 5 slots. Pass an explicit `group:` to actually share a budget across classes.

Failures must stay loud. `Api::*` maps 429 / 5xx / timeout to `TransientError` (retried) and everything else to a non-retryable `Error`; a label-less 200 is definitive, not transient. `LabelGenerationFailedError` triggers `reset_for_relabel!`, capped at `MAX_RELABEL_ATTEMPTS`, after which `record_error!` persists the message and the job raises for an operator to pick up.

Rate limiting the **operator** belongs in the UI, not in the saga: the backoffice bulk bar holds back a repeat of the same action on the same order for `BULK_THROTTLE_MS` (`app/javascript/backoffice/orders.js`).

## System tests (E2E)

- **Capybara + Cuprite** (headless Chrome over CDP, no Selenium/WebDriver), in-process, Minitest. Foundation in `test/application_system_test_case.rb`; specs in `test/system/*.rb`. Use `login_as_user` (Warden) for non-auth specs; the auth specs drive the real `/entrar`·`/cadastrar` forms.
- Run **serial** (`parallelize(workers: 1)`): N headless Chromes on a 2-core CI runner flake. **Never `sleep`**: rely on Capybara's auto-waiting matchers (`assert_selector`, `assert_current_path`); `default_max_wait_time = 2`, animations disabled. Select via the **`data-*` hooks** the views/Vitest specs already share, not Bootstrap classes or pt-BR copy.
- **No test reaches the real network.** Server-side calls (Correios, InfinitePay) are stubbed in-process via `SystemStubs` (`test/system/support/`), exactly like the integration tests; the browser is additionally fenced to localhost via Cuprite's `url_blacklist` of external hosts (`DENY_EXTERNAL=0` lifts it). The InfinitePay hosted-redirect popup is neutralized by stubbing `POST /links` to return a `data:` URL, so the browser popup never leaves the box.
- The CI `system-test` job runs `bin/rails test:system` with `SKIP_COVERAGE_FLOOR=1`: a handful of critical paths must not be held to the whole-app SimpleCov 100% floor (that floor is the unit/integration run's contract). Run it the same way locally.

## Git workflow

- Start every task from a fresh `main`: `git fetch origin && git switch -c <type>/<short-desc> origin/main` (`feat` / `fix` / `chore` / `docs`). Never branch off another feature branch: a not-yet-merged base produces noisy, conflicting PRs.
- **Worktrees live under `~/Code`** named `prisma_engine-<short-desc>` (e.g. `prisma_engine-system-tests`), never inside the repo or `.claude/`. After `git worktree add ~/Code/prisma_engine-<desc> <branch>`, link the Active Storage uploads so product images render: `ln -s ../prisma_engine/storage storage` (relative, points at the main checkout's `storage/`, the gitignored 60M+ of uploads), then `git update-index --skip-worktree storage/.keep` so the dir→symlink swap doesn't show as a deleted `.keep` (leaves only `?? storage`). Copy the gitignored credentials key the same way (`cp ../prisma_engine/config/master.key config/master.key`); without it `Rails.application.credentials` silently decrypts to empty, so Correios/R2/Devise-pepper all break (blank `Bearer` tokens → 403s, password hashes computed with the wrong pepper) with no boot error. Most of `public/images` is vendored/tracked, but the catalog seed images (`public/images/stores/uploads/`) plus `db/seeds/hero_banner.jpg` and `db/seeds/correios_label_sample.pdf` are gitignored (see `docs/seeding-images.md`); link `public/images/stores/uploads` from the main checkout the same way as `storage/` if you need to seed images in the worktree.
- To check whether commits are already upstream, use `git cherry -v origin/main` (patch-id based), not `origin/main..HEAD`, because squash / rebase merges rewrite SHAs.
- `bin/pre-push-check` must pass before pushing. Branch protection on `main` blocks direct pushes; fix the cause, never `--force` or bypass.
- Open PRs with `gh pr create`; merge from GitHub.
- **After every push (and right after opening), verify CI with `gh pr checks <N>`.** The local gauntlet does not cover `Semgrep (new findings)`, `Dependency review`, or `system-test`, so a green pre-push can still produce a red PR. For failing checks: `gh run view <run-id> --log-failed`, plus `gh api repos/<owner>/<repo>/code-scanning/alerts` for security gates and `gh api repos/<owner>/<repo>/issues/<N>/comments` for the sticky `ci-quality` comment.
- Refresh PR title/body after every push that meaningfully changes scope. `gh pr edit` can silently exit 1 on a GraphQL Projects-classic deprecation warning; fall back to `gh api repos/<owner>/<repo>/pulls/<N> -X PATCH -f title="..." --field body=@/tmp/pr-body.md`.

## CI gates

One workflow (`.github/workflows/ci.yml`). **Blocking**: rubocop, brakeman, bundler-audit, importmap audit, tests + system-tests, SimpleCov 100% line + branch floor, undercover (changed-line coverage), JS unit tests (Vitest), semgrep `(new findings)`, gitleaks, dependency review (moderate+ CVEs). **Advisory**: reek findings, reported in the sticky `ci-quality` PR comment. Brakeman + Semgrep findings also surface under **Security ▸ Code scanning**. The 100% SimpleCov floor + undercover together enforce both "every changed line is tested" and "no coverage regressions." Mark genuinely un-testable Ruby lines with `# :nocov:`. JS coverage is **separate** (Vitest, `app/javascript/storefront/*.js`) with its **own** 100% threshold in `vitest.config.js` (browser bootstrap excluded via `/* v8 ignore */`, the JS analogue of `# :nocov:`); both Ruby (SimpleCov) and JS (Vitest) totals show in the sticky comment. The `JS unit tests` job is new; add it to main's required-checks list to make it blocking.

## Gotchas

- Rails checks pending migrations on every dev request → DB must be running (`docker compose up -d` before `bin/dev`).
- `tmp/snapshot/` is a frozen reference of the live site used during the port. Gitignored; do not commit.
- `.env.example` is the only `.env*` that ships in the repo (`.gitignore` carves it out).
