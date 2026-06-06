# Ecommerce Platform — Architecture & Implementation Plan

**Context:** Small niche ecommerce — limited customers, limited product catalog. Built from scratch (no Shopify/Spree/Solidus). Stack: **Ruby on Rails monolith**.

---

## 0. Project Decisions (locked in)

| Decision | Choice | Implication |
|---|---|---|
| Product domain | **Handmade / made-to-order** | Default: no stock — sell as many as orders come in; some products may opt into a small ready-made stock (see §0.1). Per-order variant choices (ROM, shell color, …) modeled as `ProductOption` rows. Returns mostly non-applicable. |
| Primary market | **Brazil** (BRL, pt-BR) | Pix is mandatory; parcelamento expected; NF-e issuance; LGPD; Correios shipping |
| Deployment | **Kamal on a VPS** | Single-box friendly choices: Solid Queue + Solid Cache, Postgres co-located or managed; S3-compatible object storage external (R2/B2/Spaces) |
| Codebase | Rails 8 majestic monolith | One repo, one deploy |

These four decisions override any conflicting defaults later in the document.

---

## 0.1. Niche-specific model: handmade / made-to-order

The standard ecommerce stock model **does not apply**. Replace it with:

### Stock is optional, not the model

The default is **no stock** — Vinicius makes each cart on demand, so a product can be sold as many times as orders come in. Some products may carry an occasional ready-made piece, and that's it.

Direction (not built yet, no premature columns): a product opts in to "I have units sitting on the shelf" by being marked as stocked; the count decrements when an order ships. Everything else stays unlimited.

### Variants (already implemented)

Per-product variation is modeled as `ProductOption` — `(group_name, name, position, price_delta_cents)` rows hung off `Product` (see `app/models/product_option.rb` + the migration in `db/migrate/`). Each row is one selectable choice within a group ("ROM" / "Shell color" / etc.), with an optional price delta. The line item will reference the chosen options when checkout lands; the validator that today rejects duplicate `(product, group, name)` rows is enough.

### Order lifecycle differs

Six customer-facing states (pt-BR) with two branch points — full table in §4. Key principles:

- Cancellation window closes when production starts (communicate clearly at checkout)
- Every state has a short customer-facing description in pt-BR visible on the order page
- Optional progress photos uploaded by Vinicius surface on the customer's order page

### Returns under Brazilian law (CDC art. 49)

- 7-day right of regret applies to online sales **except** for personalized/made-to-order goods
- Show this exemption clearly on PDP, cart, and order confirmation (legal protection)
- Ready-made items: full 7-day return window applies — build the flow

---

## 0.2. Brazil-specific stack additions

| Concern | Choice | Notes |
|---|---|---|
| Payments | **InfinitePay** | Brazilian PSP — Pix + card + parcelamento in one integration. **No boleto** (InfinitePay doesn't issue one). |
| Pix | First-class checkout option | ~30–40% of online payments in BR; instant settlement, lowest fees |
| Card installments | Parcelamento up to 6x or 12x sem juros | Cultural expectation; absorb fee or pass to customer |
| Boleto | **Out of scope** | Would require a second PSP. Skip until there's clear demand. |
| NF-e (electronic invoice) | **eNotas**, **NFe.io**, or **Bling** | Mandatory for businesses; issue automatically on payment confirmation |
| Shipping + addresses | **Correios** | PAC + SEDEX + Mini Envios via the Correios API (rastro + pré-postagem); real-time quotes; CEP autocomplete + address validation also come from Correios — no separate ViaCEP integration. |
| Anti-fraud | InfinitePay's native | **Clearsale** or **Konduto** if scaling |
| Locale | i18n with pt-BR as default | `R$ 1.234,56`, dd/mm/yyyy, brazilian-documents gem for CPF/CNPJ |
| Compliance | **LGPD** (not GDPR) | ANPD authority; same rights (access, deletion, portability) |
| Reputation | Reclame Aqui presence from day 1 | Brazilian buyers check it before purchasing |

---

## 0.3. Kamal + VPS infrastructure

| Concern | Choice | Notes |
|---|---|---|
| App server | Puma on VPS, deployed with Kamal 2 | Rails 8 default; single command deploys |
| Database | Postgres on the same VPS to start, **migrate to managed when revenue justifies** (Neon, Supabase, RDS) | Backups via `pg_dump` to S3 nightly — non-negotiable |
| Background jobs | **Solid Queue** | DB-backed, no Redis needed; perfect for this scale |
| Cache | **Solid Cache** | Same |
| WebSockets | Solid Cable (only if real-time needed) | |
| Object storage | **Cloudflare R2** or **Backblaze B2** | S3-compatible, far cheaper than AWS S3 for product images + customer uploads; egress is free on R2 |
| CDN | **Cloudflare** | Free tier covers small store; sits in front of R2 too |
| TLS | Let's Encrypt via Kamal proxy | Automatic |
| Email | **Resend** or **Postmark** | Both work from BR; SES if cost-sensitive |
| Monitoring | **Sentry** + **Better Stack** (logs + uptime) | Cheap, BR-friendly latency |
| Backups | Postgres dumps + R2 bucket versioning | Test restore monthly |
| VPS provider | See § Deferred Decisions for the Brazilian-providers-first shortlist | |

---

## 1. Architecture Decision

### Chosen approach: Rails majestic monolith

A single Rails application that contains:
- Storefront (server-rendered HTML — Bootstrap 4.6 + jQuery, ported from the legacy site)
- Customer accounts and checkout (future)
- Backoffice admin (future — Hotwire/Turbo Streams)
- Background jobs (Solid Queue)
- All business logic and persistence

### Why not the alternatives

| Option | Why rejected |
|---|---|
| **Hugo / SSG + headless commerce** | Backoffice still needs to be built separately; rebuilds required for catalog changes; 3 systems to maintain instead of 1 |
| **Spree / Solidus** | Inherits a large opinionated codebase; we don't need most of its features; customizing checkout/pricing means fighting the framework |
| **Next.js + Rails API** | Two codebases, two deploys, double the engineering overhead; requires explicit SSR/ISR setup or SEO breaks (20–40% organic traffic loss risk) |
| **Headless CMS + Rails** | Adds a second service to deploy and sync; only useful when non-technical content editors need autonomy. Catalog data belongs in Rails models, not a CMS |

### Why Rails monolith wins for this case

- Fastest time to value with the smallest team
- Storefront + backoffice in one codebase, one deploy
- Server-rendered HTML = SEO works by default, no hydration risk
- Rails 8 ships with Solid Queue / Solid Cache / Solid Cable — fewer external dependencies
- Shopify itself runs on Rails (proves the ceiling is high)
- Can extract an API layer later if/when needed; the inverse is much harder

---

## 1.1. Third-party integration pattern (anti-corruption layer)

Every external service we depend on — payments, shipping, NF-e, transactional email — gets wrapped in the same three layers. The boundary is what keeps a vendor's quirks (auth flows, retry semantics, payload field names, status enums) from leaking into our domain. The convention also lives in `CLAUDE.md`.

**Infrastructure** — `<Vendor>::Api::*` (e.g. `Correios::Api`, future `InfinitePay::Api`, `NfeIo::Api`). Owns HTTP, auth tokens, endpoints, timeouts, (de)serialization, and error mapping. Returns **plain data** (hashes/arrays), never a domain model. Depends on nothing of ours. Translating a vendor quirk into our own error vocabulary (e.g. an SRO message → `InvalidObjectError`, a 429 → `TransientError`) belongs here. Adapters under the same vendor share a Faraday base + a tiny error hierarchy.

**Domain** — models + bounded-context service namespaces (`Shipping::*`, future `Payments::*`, `Invoicing::*`). Holds business rules, the interpretation of vendor data, and persistence. Depends on the `Api` client; **never touches Faraday/HTTP**. Recurring idioms:

- a `<Context>::*Factory` builds the AR record from the plain-data response,
- a `<Context>::*Update` interprets webhook / poll events into lifecycle transitions,
- a service / method map (`Shipping::SERVICES`, future `Payments::METHODS`) lives here.

**Application** — jobs and use-case services. Thin wiring: pull from the `Api` client, hand the data to the domain. The webhook controller, the polling orchestrator, the scheduled sync — all live here.

**Rules:**

- No business rules or persistence inside an `Api::*` client.
- No HTTP, retry, or auth inside the domain.
- A new vendor (or a vendor swap) is a new `Api` adapter — the domain shouldn't change.
- A vendor that needs more than one token / contract / base URL splits into multiple `Api::*` modules sharing a single `Api::Client` (Correios already does this — rastro vs. cartão de postagem).

**Reference implementation** (🟢 shipped): `app/services/correios/api/` (infrastructure) + `app/services/shipping/` (domain), wired by `SyncShipmentJob`.

**Planned** (⚪): `app/services/infinite_pay/api/` + `app/services/payments/` for the PSP; `app/services/nfe_io/api/` + `app/services/invoicing/` for NF-e. Same three-layer shape.

---

## 2. Tech Stack

### Core

| Concern | Choice |
|---|---|
| Framework | Rails 8 |
| Language | Ruby 3.3+ |
| Database | PostgreSQL |
| Cache | Solid Cache (or Redis) |
| Background jobs | Solid Queue |
| Frontend | **Storefront:** Bootstrap 4.6 + jQuery via CDN (ported from the legacy site; Tailwind deliberately dropped — see `CLAUDE.md`). **Admin (future):** Hotwire (Turbo + Stimulus) over Importmap. |
| File storage | Active Storage + S3-compatible bucket |
| CDN | Cloudflare or Bunny.net (for images and static assets) |
| Email | Postmark / Resend / SendGrid (transactional) |
| Hosting | **Kamal on VPS** — see §0.3 and § Deferred Decisions |

### Key gems

Already in `Gemfile` (installed, in use):

```ruby
gem 'friendly_id'         # product slugs (history-enabled)
gem 'image_processing'    # WebP/AVIF variants via Active Storage
gem 'faraday'             # HTTP client used by the Correios API layer
# Rails 8 defaults wired up: solid_queue, solid_cache, solid_cable, propshaft,
# importmap-rails, turbo-rails, stimulus-rails (turbo/stimulus dormant on the
# storefront — see CLAUDE.md).
# Dev/test: dotenv, webmock, simplecov, undercover, reek, brakeman,
# bundler-audit, rubocop-rails-omakase, derailed_benchmarks, memory_profiler.
```

Add when their use case lands (not preinstalled):

```ruby
# SEO
gem 'meta-tags'           # per-page <title>, <description>, OG tags
gem 'sitemap_generator'   # XML sitemap + auto-ping to search engines

# Domain
gem 'aasm'                # state machine for orders, payments, NF-e issuance
gem 'paper_trail'         # audit log
gem 'pundit'              # authorization (admin/staff/customer roles)
gem 'pg_search'           # Postgres full-text search

# Payments / external (Brazil — see §0.2)
# InfinitePay needs no extra gem — write the client over the already-pinned
# `faraday`, mirroring the `Correios::Api` shape.
gem 'brazilian-documents' # CPF/CNPJ validation + formatting

# Operational
gem 'rack-attack'         # rate limiting
```

---

## 3. SEO

Rails server-renders HTML, which already solves the hardest SEO problems. The remaining work is a checklist.

### Per-page must-haves

- Unique `<title>` and `<meta description>` per product/category page (`meta-tags` gem)
- Open Graph + Twitter Card tags for social sharing
- Canonical URLs (`<link rel="canonical">`) — critical when products appear in multiple categories or via filters
- Friendly slug URLs (`/products/leather-wallet`, not `/products/123`)

### Structured data (JSON-LD)

Highest-leverage SEO action. Enables Google rich results (price, stock, ratings in search). Add to every product page:

```json
{
  "@context": "https://schema.org/",
  "@type": "Product",
  "name": "...",
  "image": "...",
  "offers": {
    "@type": "Offer",
    "price": "...",
    "priceCurrency": "...",
    "availability": "https://schema.org/InStock"
  }
}
```

Also add `BreadcrumbList` and `Organization` schemas.

### Site-wide

- XML sitemap submitted to Google Search Console (`sitemap_generator`)
- robots.txt configured to disallow filter/sort URLs and admin
- HTTPS sitewide (free via Let's Encrypt or host)
- Mobile-first responsive design (mandatory — Google indexes mobile version)

### Core Web Vitals targets

| Metric | Target | Main risk |
|---|---|---|
| LCP | < 2.5s | Unoptimized hero/product images |
| INP | < 200ms | Heavy JS blocking main thread |
| CLS | < 0.1 | Images without `width`/`height`, late-loading fonts |

### Image optimization

- WebP/AVIF via Active Storage variants
- `loading="lazy"` below the fold
- Always set explicit `width` and `height` (prevents CLS)
- Descriptive `alt` text including product name
- Serve via CDN

### What to skip at this scale

- Incremental Static Regeneration (only matters for 10k+ products)
- Edge rendering / dedicated SSR infra
- Faceted navigation SEO (only matters with hundreds of filter combinations)
- Separate SSG for marketing pages

---

## 4. Domain Problems Beyond SEO

### Critical revenue path

#### Cart & checkout abandonment (~70% industry average)

| Cause | % of abandons | Fix |
|---|---|---|
| Unexpected shipping costs | ~50% | Show shipping early, on product/cart page |
| Complicated checkout | ~22% | Single page, minimal fields |
| Hidden total cost | ~16–21% | Running total visible at all times |
| Technical errors | ~14–17% | Idempotency, retries, clear errors |

Implementation rules:
- One-page checkout, not a wizard
- Persist cart for logged-in users; cookie-based for guests
- Full price breakdown (subtotal + shipping + tax) before payment step
- Abandoned cart emails via background job (1h / 24h / 72h)

#### Payment processing

Use **InfinitePay** (see §0.2). Never store card data ourselves.

Critical patterns (provider-agnostic):
- **Idempotency keys** on every payment attempt — prevents double-charging on retries
- **Webhook handling** for async events (payment approved/rejected/refunded) — never trust the synchronous response alone; Pix is async by nature
- **3DS2** on cards — shifts fraud liability from merchant to issuer
- Store `external_payment_id` and `payment_method` (pix/card) on Order for reconciliation
- Pix-specific: order is `aguardando_pagamento` until the webhook confirms; show QR code + copy-paste code; expire after 30 min

#### Inventory race conditions

Only relevant when a product opts into stock (see §0.1). For unlimited / made-to-order products there is nothing to race over — checkout always succeeds.

When stock is on, lock the row inside the checkout transaction (`SELECT FOR UPDATE`) and decrement at checkout, not at ship — same shape as any standard ecommerce decrement. Build it when the first stocked product appears, not before.

### Operational

#### Tax & invoicing (Brazil)

Don't build it. For BR you need **NF-e issuance** (legal requirement for businesses), not just tax calculation. Use **eNotas**, **NFe.io**, or **Bling** — they handle SEFAZ integration, tax bracket lookup (NCM codes), and PDF/XML generation. Issue automatically on payment confirmation via background job.

#### Shipping (Brazil)

Use the **Correios** API directly — PAC, SEDEX, and Mini Envios cover the cartridge envelope. Quote at PDP/cart with the customer's CEP; create the label as a pré-postagem on payment confirmation.

Must-haves:
- CEP autocomplete + address validation via the same Correios API (no separate ViaCEP integration — Correios covers it)
- Tracking code capture + customer notification
- Shipping label generation through the same provider

#### Order state machine (made-to-order)

Six customer-facing states in pt-BR. The flow is **not linear** — two branch points (after payment, and during production).

| # | State | Description shown to the customer | Trigger |
|---|---|---|---|
| 1 | `aguardando_pagamento` | "O pedido foi criado e encontra-se aguardando pagamento." | Auto on order creation |
| 2 | `pagamento_confirmado` | "O seu pedido está aguardando para entrar em produção, de acordo com a ordem de chegada." | InfinitePay webhook |
| 3.1 | `aguardando_componentes` | "Estamos com falta de alguns componentes para produção do seu pedido." | Manual (operator) |
| 3.2 | `em_producao` | "Seu pedido está em produção e em breve será enviado para os correios." | Auto — order surfaces on the production report |
| 4.1 | `problema_na_producao` | "Tive problemas com a produção, entre em contato para esclarecimentos." | Auto — 2 calendar days in `em_producao` without progress |
| 4.2 | `etiqueta_emitida` | "Etiqueta dos Correios emitida, seu pedido será enviado em breve." Email + WhatsApp carry the tracking code plus the delivery details. | Auto — on successful pré-postagem creation |
| 5 | `enviado` | "Seu pedido foi enviado aos correios." + mini-envios disclaimer; Correios sub-statuses surfaced AliExpress-style for the in-transit timeline. | Correios rastro first transit event (via `Shipping::TrackingUpdate`) |
| 6 | `entregue` | "Seu pedido foi entregue." | Correios rastro delivery event |

**Branch points** (the flow is not linear):

- After **2 `pagamento_confirmado`** → either **3.1 `aguardando_componentes`** (manual; operator flags missing parts) or **3.2 `em_producao`** (auto; the order first appears on the production report). From 3.1, an operator move flips to 3.2 once components arrive.
- During **3.2 `em_producao`** → either **4.2 `etiqueta_emitida`** (auto; `Shipping::CreatePrePostagem` succeeded) or **4.1 `problema_na_producao`** (auto; 2 calendar days without progress). Recovery from 4.1 back to 3.2 is a manual operator transition.

**Cross-cutting:**

- Modeled with `aasm`. Each transition is auditable (who/when/why), triggers side effects via background jobs, and is recoverable.
- The 2-day stuck-in-production rule and the production-report scan run as recurring jobs (same Solid Queue + `config/recurring.yml` shape as `SyncPendingShipmentsJob`).
- 4.2 → 5 → 6 are driven by `Shipping::TrackingUpdate` interpreting rastro events (§ "Shipment tracking sync") — the order subscribes to the same final-state signals the `Shipment` already exposes.
- Cancellation is allowed only before `em_producao` (3.2) per §0.1. Refund flow attaches to `Payment`, not the order state machine.

#### Shipment tracking sync (Correios polling) — **shipped**

Our Correios contract has **no webhooks**, so tracking is **polled**.

**Event interpretation:** `Shipping::TrackingUpdate` maps confirmed `(code, type)`
pairs to a signal via its `EVENT_SIGNALS` hash (delivered / postado / label); anything
else that isn't the label counts as in-transit. We **don't know the `returned` code
yet** — uncatalogued `(code, type)` pairs are persisted as events *and* logged
(`unmapped event …`) so we can identify them from real data and extend the map.

**Rate limit:** the rastro gateway returns its token-bucket limits in response
headers — `x-ratelimit-replenish-rate: 50` (50 req/s), `x-ratelimit-burst-capacity: 55`,
per contract key. The concurrency cap (`limits_concurrency to: 5`, ~30 req/s) sits
well under that; a 429 (empty body) is mapped to `Correios::Api::TransientError` and
retried with backoff.

**Invalid codes:** a 200 can carry no events and a `mensagem`. `SRO-020` (not in
Correios' base yet) is benign — we keep polling. `SRO-019` (objeto inválido) is
permanent — the client raises `Correios::Api::InvalidObjectError`, and the job stops
polling that shipment (`tracking_state: unavailable`) and records the message in
`tracking_error` / `tracking_errored_at` so we can debug how a bad code reached our
DB (it shouldn't — codes come from Correios' own pré-postagem).

**Loop closure (future, not built yet):** once the `Order` model exists, the
orchestrator filters to shipments whose **order is not yet in a final state**, and
a shipment reaching a final `tracking_state` becomes the trigger that transitions
its order — `shipped → delivered` (or `returned`) — closing the loop. Today the
job updates the shipment only; there is no `Order` yet.

#### Transactional emails

All of these break trust if missing:
- Order confirmation
- Payment received
- Shipping notification with tracking
- Delivery confirmation
- Abandoned cart recovery
- Refund confirmation
- Password reset

Use a transactional provider — never raw SMTP/Gmail.

### Security & compliance

#### Privacy laws

**LGPD** (Brazil) — administered by ANPD. Same conceptual rights as GDPR.

- Privacy policy + cookie consent banner (pt-BR)
- Right to deletion — implement hard-delete or anonymize flow
- Data export — JSON dump of user's data on request
- Encrypt PII at rest (`encrypts :field` is built into Rails 7+)
- Document a `Encarregado de Dados` (DPO) contact on the site

#### Fraud prevention

The PSP's native antifraud handles 95% of cases (InfinitePay). Add:
- Velocity limits via `rack-attack` (max N orders per IP/email per hour)
- Manual review queue for orders above $X

#### Auth & account security

- Bcrypt passwords (Rails default)
- Rate limiting on login (`rack-attack`)
- Optional 2FA for admin/backoffice users
- Strong CSP headers — prevents Magecart-style card-skimming via injected JS

### Performance & reliability

#### Burst traffic

Small niche stores get press features, influencer mentions, holiday sales — sudden 100x traffic spikes. The same edge that absorbs them also absorbs DDoS / scraper / credential-stuffing waves, so configure it for both at once.

- **Cloudflare configured to absorb the spike, not just route it.** Bot Fight Mode + Managed Challenge on traffic anomalies; edge rate-limit rules on `/carrinho`, the checkout endpoints, and every webhook URL; the free-tier WAF Managed Rules (OWASP basics) on; a geo rule scoping traffic to **BR** (the audience is Brazil-only, so foreign-IP storms are abuse by default — allowlist any partner CIDR explicitly). L3/L4/L7 DDoS protection is always-on on the free plan; **Under Attack Mode** is a one-toggle escalation when a real wave hits. Treat Cloudflare config as code — keep a snapshot in the repo (`docs/cloudflare/`) so a rebuild is reproducible.
- Page caching for product pages (Rails fragment caching + CDN)
- Background jobs for non-critical work
- Tuned database connection pooling
- Optional: queue/waiting room for checkout under extreme load

#### Search

Postgres FTS via `pg_search` works fine up to ~10k products. If we outgrow it: Meilisearch.

### Backoffice

#### Admin

- Simple double admin account, hardcoded, there will be just two admins, Vinicius and I
- Bulk operations (product import/edit, order updates)
- Refund workflow (partial refunds, restocking, customer notification)

#### Reporting

- Daily/weekly sales reports
- Best-selling products
- Inventory turnover
- Cohort retention
- GA4 / Plausible for traffic
- Ecommerce events (`view_item`, `add_to_cart`, `purchase`) for conversion funnels

#### Customer support

- Order lookup by email/order number for guests
- Self-service order cancellation (within X minutes)
- Self-service return request flow
- Help/FAQ pages (Rails views, not a CMS)

---

## 5. MVP Build Order (generic)

The Migration Plan below adapts this generic order to Prisma Games specifically.

### Phase 1 — Can you take a single order?

1. Product catalog + categories with variant options (ProductOption rows)
2. Cart (session-based) with chosen `ProductOption` ids per line item + guest checkout
3. CEP autocomplete + Correios quote at cart (both via the Correios API)
4. Payment integration: Pix first (highest conversion in BR), then card with parcelamento — via InfinitePay
5. Order model with made-to-order state machine + cancellation window logic
6. NF-e issuance via eNotas/NFe.io on payment confirmation (background job)
7. Transactional emails (pt-BR) + Pix QR code email
8. Basic admin: order list, production status update, customer's chosen options visible

### Phase 2 — Can you operate the business?

9. Production capacity model (daily/weekly slots per product)
10. Order fulfillment workflow + Correios label printing + tracking notifications
11. Refunds + cancellations (Pix refund, card refund/chargeback handling)
12. Returns flow for ready-made items only (CDC art. 49)
13. Sitemap + structured data + Search Console (BR property)

### Phase 3 — Can you grow it?

14. Abandoned cart recovery (Pix-expired carts are a high-recovery segment)
15. Customer accounts + order history + production progress photos
16. Reviews/ratings (with Reclame Aqui link in footer)
17. Discount codes / promotions
18. Analytics + reporting dashboards (GA4 + ecommerce events)

### Phase 4 — Polish

19. CDN (Cloudflare in front of R2), image optimization (WebP/AVIF)
20. Search improvements (pg_search → Meilisearch if needed)
21. Loyalty / referrals
22. Wholesale/B2B pricing tier (only if demand appears)

---

## 6. Explicitly Out of Scope

For a small niche store, these are pure overengineering:

- Microservices
- Headless / decoupled frontend
- Multi-warehouse real-time inventory
- ML-based recommendations (use category-based "related products")
- ML-based fraud detection (provider's native antifraud suffices)
- A/B testing infrastructure (use PostHog if needed)
- Subscription billing (unless that's the business model)
- Separate CMS for product content
- GraphQL API
- Dedicated mobile app

---

## 7. Key Principles

1. **Boring stack, interesting business logic.** All engineering effort goes into solving real business problems (tax, fulfillment, refunds, inventory accuracy), not fighting infrastructure.
2. **Server-rendered first.** SEO and performance come for free; reach for JS only where it adds clear UX value.
3. **One codebase, one deploy.** Avoid distributed systems until the pain justifies them.
4. **Use hosted services for the regulated stuff.** Payments (InfinitePay), NF-e (NFe.io/eNotas), email (Postmark/Resend), CDN (Cloudflare) — never reinvent these.
5. **Background everything that's not in the request path.** Emails, webhooks, fulfillment side-effects, analytics events — all in jobs.
6. **Cache aggressively at the edge.** Product pages and category pages are the hot path; CDN them.
7. **Audit everything.** Orders, refunds, admin actions, inventory changes — all logged with who/when/why.

## Decisions locked in

| Decision | Choice | Why |
|---|---|---|
| Payment gateway | **InfinitePay** | Brazilian PSP — Pix + card + parcelamento + native antifraud in one integration. No boleto. |
| NF-e provider | **NFe.io** | Cleaner REST API than eNotas; pay-per-issue pricing fits the SKU volume; not an ERP like Bling. |
| Shipping carrier | **Correios** (direct API) | Only carrier in scope; PAC + SEDEX + Mini Envios cover cartridge-sized parcels. `Correios::Api::*` + `Shipping::*` shipped. |
| Postgres | **Co-located on the VPS** | Daily `pg_dump` → R2 covers 99% of risk; managed Postgres is a future migration. |
| Background jobs | **Solid Queue** | Rails 8 default; Postgres-backed; no Redis to operate. Recurring jobs via `config/recurring.yml`. |
| Storefront stack | **Bootstrap 4.6 + jQuery via CDN** | Preserves the legacy site's look during the port. Tailwind was tried and dropped — see `CLAUDE.md`. |
| Admin auth | **Rails 8 native authentication generator** | No Devise; less ceremony. |
| Admin JS (future) | **Importmap + Stimulus + Turbo** (no bundler) | Aligns with §0 boring-stack principle; gems installed, dormant on the storefront. |
| Test framework | **Minitest** (Rails 8 default) | Revisit if integration tests get awkward. |
| HTTP client | **Faraday** | Shared base in `Correios::Api::Client`; reuse for future external APIs. |

Still to pick:

| Decision | Recommendation | Why |
|---|---|---|
| VPS provider | **See § Deferred Decisions** | Pick at deployment time; Brazilian providers preferred (BR latency on Pix). |
| Email provider | **Postmark** or **Resend** | Both work from BR; pick before the first transactional email lands and stop deciding. |

## Open items / needs from Vinicius

These don't block kicking off Phase 1 but block portions of Phase 1–2:

- **CNPJ status** — required for the InfinitePay merchant account, NFe.io account, and the Correios contract (rastro + pré-postagem API tokens). Confirm he has one and apps are submitted (approvals can take 1–2 weeks).
- **NCM codes** for each cartridge type — wrong NCM = NF-e fines. Lock with Vinicius's accountant before Phase 2.
- **Brand assets** — logo source files, brand fonts, color tokens. Otherwise we lift from current site (visual only, not files he doesn't own).
- **Per-product variant options** — Vinicius enumerates ROM choices, shell colors, label art per cartridge; each becomes a `ProductOption` row. Use a shared spreadsheet → seed file.
- **InfinitePay + NFe.io + Correios API credentials** (rastro token + cartão de postagem token) — needed by end of Phase 1 dev.
- **Maximum installments policy** — 6x or 12x sem juros? Who eats the fee?