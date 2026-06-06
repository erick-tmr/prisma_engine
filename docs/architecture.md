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

**Replaces in the main doc:** Stripe → InfinitePay; Stripe Tax → eNotas/NFe.io; flat-rate shipping → Correios quotes; GDPR/CCPA → LGPD.

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

## 2. Tech Stack

### Core

| Concern | Choice |
|---|---|
| Framework | Rails 8 |
| Language | Ruby 3.3+ |
| Database | PostgreSQL |
| Cache | Solid Cache (or Redis) |
| Background jobs | Solid Queue (or Sidekiq + Redis) |
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
| Mandatory account creation | ~25–35% | **Always offer guest checkout** |
| Complicated checkout | ~22% | Single page, minimal fields |
| Limited payment options | ~13% | Card + Apple Pay + Google Pay |
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

#### Carrier integration layering (anti-corruption layer) — **shipped**

Correios is integrated through three layers so the 3rd-party API stays isolated
from our domain — the convention lives in `CLAUDE.md`:

- **`Correios::Api::*`** (`app/services/correios/api/`) — infrastructure / ACL: HTTP,
  auth tokens, endpoints, timeouts, (de)serialization, error mapping. Returns plain data,
  depends on nothing of ours. Holds `Api::Tracking` (rastro GET), `Api::PrePostagem`
  (create POST), `Api::Client` (shared Faraday + `raise_for_status`), `Api::Timestamp`,
  and the `Error`/`TransientError`/`InvalidObjectError` hierarchy.
- **`Shipping::*`** (`app/services/shipping/`) + the `Shipment` model — domain: business
  config + request building (`Shipping::CreatePrePostagem`), the response→`Shipment` factory
  (`Shipping::ShipmentFactory`), the rastro-event→lifecycle interpretation
  (`Shipping::TrackingUpdate`), and the service map (`Shipping::SERVICES`). Depends on the
  `Api` client, never on HTTP.
- **Jobs** — thin application entrypoints wiring the two (`SyncShipmentJob` =
  `Correios::Api::Tracking.fetch` → `Shipping::TrackingUpdate.apply`).

Why: the vendor's quirks (token-bucket headers, SRO messages, payload field names) stay
behind the `Api` boundary, so swapping Correios for another carrier later means a new
`Api` adapter without touching the domain.

#### Pré-postagem creation (Correios label generation) — **shipped** (operator trigger pending)

A shipment starts as a **pré-postagem** — we `POST /prepostagem/v1/prepostagens`
(`Shipping::CreatePrePostagem` → `Correios::Api::PrePostagem`) and persist the response as a
`Shipment` (`Shipping::ShipmentFactory.from_pre_postagem`), which the polling below then
tracks. It authenticates with a **separate** "cartão de postagem" bearer token
(`CORREIOS_CARTAO_API_TOKEN`), distinct from the rastro token; both API clients share one
Faraday base and error hierarchy (`Correios::Api::Client`, `Correios::Api::TransientError`).

Most of the request body is **hardcoded for now** — the models that will feed it
don't exist yet. What's placeholder today and where it'll come from:

| Field | Now | Later |
|---|---|---|
| `remetente` | store constant (Prisma Games) | seller settings |
| `destinatario` | placeholder contact | customer profile (after auth/registration) |
| `codigoServico` | required — caller picks a `Shipping::SERVICES` name (`:sedex` / `:mini_envios` / `:pac`), mapped to the code; no default | chosen at checkout |
| `numeroCartaoPostagem` | constant | seller settings |
| `codigoFormatoObjetoInformado` | constant `"2"` (pacote) | maybe per-item |
| `itensDeclaracaoConteudo` | placeholder | order line-items (game name/qty/price) |
| `pesoInformado` / `altura` / `largura` / `comprimento` | placeholder | packing algorithm |
| `observacao` | placeholder | order identifier |
| `cienteObjetoNaoProibido` `"1"`, `solicitarColeta` `"N"`, `logisticaReversa` `"N"`, `emiteDCe` `"S"` | fixed policy | unchanged |

It will be **triggered manually from the backoffice** — an operator presses a button to
generate the label for an order; there's no automatic trigger. The button itself lands
with the admin namespace; today the call is invokable from a console.

#### Shipment tracking sync (Correios polling) — **shipped**

Our Correios contract has **no webhooks**, so tracking is **polled**. An hourly
orchestrator (`SyncPendingShipmentsJob`, scheduled in `config/recurring.yml`)
selects shipments still in flight (`Shipment.awaiting_tracking`) and fans out one
`SyncShipmentJob` per shipment — each syncs in isolation, with its own retries
(`retry_on … wait: :polynomially_longer, attempts: 5`) and a Solid Queue
concurrency cap (`limits_concurrency to: 5, key: "correios_rastro"`) so a large
fan-out can't trip Correios' rate limit. A shipment carries its own
`tracking_state` (`pending → in_transit → delivered / returned / unavailable`,
modeled as an `enum` on `Shipment`) derived from rastro events; the
`FINAL_TRACKING_STATES` set stops the polling loop. The orchestrator also skips
shipments whose pré-postagem hit a terminal status (`TERMINAL_PREPOST_STATUSES =
[4, 5, 6]` — expirado, cancelado, estornado), because they will never become a
real shipment.

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

#### PCI DSS

Using the payment provider's hosted checkout/elements correctly = **SAQ A** (minimal compliance). Card data never touches our server. **Watch out:** misclassifying as SAQ A when partial provider JS could be tampered with — actually requires SAQ A-EP. This is a common, dangerous error.

#### Privacy laws

**LGPD** (Brazil) — administered by ANPD. Same conceptual rights as GDPR.

- Privacy policy + cookie consent banner (pt-BR)
- Right to deletion — implement hard-delete or anonymize flow
- Data export — JSON dump of user's data on request
- Encrypt PII at rest (`encrypts :field` is built into Rails 7+)
- Document a `Encarregado de Dados` (DPO) contact on the site

#### Fraud prevention

The PSP's native antifraud handles 95% of cases (InfinitePay). Add:
- AVS + CVV checks (default)
- 3DS2 enabled for high-risk transactions
- Velocity limits via `rack-attack` (max N orders per IP/email per hour)
- Manual review queue for orders above $X

#### Auth & account security

- Bcrypt passwords (Rails default)
- Rate limiting on login (`rack-attack`)
- Optional 2FA for admin/backoffice users
- Strong CSP headers — prevents Magecart-style card-skimming via injected JS

### Performance & reliability

#### Burst traffic

Small niche stores get press features, influencer mentions, holiday sales — sudden 100x traffic spikes.

- Page caching for product pages (Rails fragment caching + CDN)
- Background jobs for non-critical work
- Tuned database connection pooling
- Optional: queue/waiting room for checkout under extreme load

#### Search

Postgres FTS via `pg_search` works fine up to ~10k products. If we outgrow it: Meilisearch.

### Backoffice

#### Admin

- Role-based access (admin / fulfillment / support) via Pundit
- Audit log of who changed what (PaperTrail)
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

---

# Migration Plan — Prisma Games → `prisma_engine`

## Context

Vinicius runs https://www.prismagames.com.br/ on **Meloja** (Brazilian SaaS), selling ~24 SKUs of retro Game Boy cartridges and ROM-hacked variants. Every order is **fully made-to-order**: he sources/cleans the cartridge, flashes the ROM, builds the box, prints the Correios label, and ships it. The current platform handles the storefront fine but **no SaaS supports the fulfillment workflow he actually needs** — that's the reason for the rebuild. Secondary motivation: the user is doing this as a learning/craft project.

The rebuild is **greenfield** at `/home/ericktmr/Code/prisma_engine`. The made-to-order assumption (§0.1 above) applies in full.

**Migration approach (per user)**: not a data migration. Clone the existing site's visual layout (HTML/CSS) into Rails ERB, manually re-seed the SKUs, then iterate. No Meloja exporter. **The storefront port kept the legacy Bootstrap 4 + jQuery stack** — Tailwind was tried and dropped (CSS reset + class collisions); see `CLAUDE.md`. Cutover strategy deferred — keep prismagames.com.br on Meloja until the new app is ready and Vinicius approves the flip.

**The backoffice is the product.** The storefront is "just to collect orders." Engineering effort should weight ~50/50 storefront/backoffice, not 80/20.

## Recommended approach

A single Rails 8 app at `/home/ericktmr/Code/prisma_engine/` containing storefront, customer-facing checkout, and an `/admin` namespace for Vinicius's production workbench. **Storefront** is server-rendered ERB on Bootstrap 4.6 + jQuery (legacy stack preserved through the port). **Admin** (future) will use Hotwire — Importmap + Stimulus + Turbo Streams for live updates. PostgreSQL co-located on a VPS via Kamal, with R2 for object storage. Pundit-gated admin with role `admin/fulfillment/support` (Vinicius will be the only admin for now).

The HTML/CSS clone happens in **parallel** with domain modeling — markup doesn't block models and vice versa.

## Domain model — first cut

UUIDs for public-facing resources (Order, Cart, LineItem, Payment); bigint for internal-only. Encrypt PII (`encrypts :cpf, :phone`) per LGPD.

Legend: 🟢 shipped · 🟡 partial · ⚪ planned (not yet built).

| Model | Status | Notes |
|---|---|---|
| **Product** | 🟢 | `slug`, `name`, `price_cents`, `published`, `currency` (BRL), `legacy_image_path`, `description`. FriendlyId (history-enabled), `has_many :product_options/:product_photos/:tags/:questions`. PaperTrail + pg_search land later. A `stocked?`/`quantity_on_hand` opt-in lands when the first stocked product appears (see §0.1). |
| **Category** | 🟢 | `name`, `slug` (unique), `has_many :products`. |
| **ProductOption** | 🟢 | belongs_to Product. `group_name`, `name`, `position`, `price_delta_cents`. Per-product variant axis (e.g. "shell color"). |
| **ProductPhoto** | 🟢 | belongs_to Product. `position`, `alt_text`, `has_one_attached :image` (Active Storage). |
| **Tag** / **ProductTag** | 🟢 | many-to-many tagging on products. |
| **Question** | 🟢 | belongs_to Product. `asker_name`, `asker_email`, `body`, `answer_body`, `answered`, `published` — Q&A under the PDP. |
| **Shipment** | 🟢 | belongs_to Order (future). `tracking_code` (unique), `service` / `service_code`, `pre_post_id` (unique), `pre_post_payload` (jsonb), package dims (`weight_grams`, `height/length/width_cm`), `posted_at`, `posting_deadline`, `delivered_at`. **Pré-postagem state:** `correios_status` (1–7 enum), `correios_status_label`, `correios_status_at`. **Tracking state:** `tracking_state` enum (`pending/in_transit/delivered/returned/unavailable`), `last_tracking_status`, `last_tracked_at`, `tracking_error`/`tracking_errored_at`. `awaiting_tracking` scope drives the polling loop. |
| **ShipmentTrackingEvent** | 🟢 | belongs_to Shipment. `(shipment_id, position)` unique. `event_code`, `event_type`, `description`, `occurred_at`, `payload` (jsonb), `tracking_code`. |
| **Cart** | ⚪ | guest-cookie token; nullable `customer_id`; `expires_at`. Today `/carrinho` is a placeholder no-op (see `CLAUDE.md`). |
| **LineItem** | ⚪ | belongs_to Cart **and** Order (two FKs, not polymorphic). Joined to the chosen `ProductOption` rows (one per option group). `fulfillment_progress` jsonb tracks per-step checkboxes for the workbench. |
| **Order** | ⚪ | human-readable `number` (`PG-2026-000123`). AASM lifecycle from §4 above. Address fields snapshotted as jsonb to survive customer edits. PaperTrail. Final shipment state will close back into the order. |
| **Address** | ⚪ | reusable for customer book + order snapshot. CEP/street/number/complement/neighborhood/city/state. CPF on shipping. |
| **Payment** | ⚪ | `provider`, `method` (pix/card), `external_id`, AASM (pending → authorized → captured → refunded → failed), idempotency keys. `qr_code_payload`. |
| **NfeIssuance** | ⚪ | `provider` (nfe_io), AASM (pending → issued → failed), `pdf_url`, `xml_url`, `numero`, `serie`. Retried on failure. |
| **Customer** | ⚪ | `has_secure_password` (Rails 8 native auth), `cpf` (encrypted), `lgpd_consent_at`. |
| **AdminUser** | ⚪ | role enum, `otp_secret` (2FA optional). |
| **RomFile** | ⚪ | `name`, `version`, `notes`, has_one_attached :file (Active Storage → R2). Linked to the ROM `ProductOption` row chosen on the line item. |

**AASM** on Order, Payment, NfeIssuance.
**FriendlyId** on Product (already wired).
**PaperTrail** on Product, Order, Payment, NfeIssuance, AdminUser actions.

Variant axes (ROM, shell color, label art, etc.) are `ProductOption` rows grouped by `group_name` (see `app/models/product_option.rb`). The checkout form picks one row per group; the line item references those rows directly. No extra JSON schema, no separate validator — the AR-level `(product, group, name)` uniqueness is the contract.

## Phase 1 — "Look like the old site, take a Pix order"

End state: Vinicius places a Pix test order on the new app and sees it in his admin queue.

**HTML/CSS clone — 🟢 shipped**

The storefront port from prismagames.com.br is in place:

- Routes mirror the legacy URL shape: `/produtos`, `/produtos/:slug` (category), `/produto/:slug` (PDP), `/carrinho`, `/identificacao`, `/pagina/...`.
- Five thin controllers: `pages`, `products`, `categories`, `cart`, `identification`. `cart#create` and `identification#create` are no-op flash-and-redirect placeholders until checkout is wired.
- Layout uses **Bootstrap 4.6 + jQuery via CDN**. Shared partials: `shared/_header`, `_nav`, `_footer`, `_cookie_banner`, `_drawer`. **Tailwind was deliberately dropped** during the port (CSS reset + class collisions). Hotwire (turbo/stimulus) is installed but dormant — see `CLAUDE.md`.
- 143 product images vendored under `public/images/`; no remote `cdn-meloja.*` / `prismagames.com.br` / `a.meloja.com.br` URLs anywhere in `app/` or `public/`.
- Markup was rebuilt from scratch, not lifted wholesale — Meloja-templated HTML is not relicensable. Vinicius rewrites product copy; new product photos go through Active Storage.

**Domain — 🟡 partial**

- Catalog migrated from a YAML PORO to ActiveRecord: `Category`, `Product` (FriendlyId-slugged, history-enabled), `ProductOption`, `ProductPhoto` (Active Storage), `Tag` / `ProductTag`, `Question`. 🟢 shipped.
- Shipping primitives wired: `Shipment` + `ShipmentTrackingEvent`. 🟢 shipped (see § "Carrier integration layering" for the full stack).
- Still ⚪ to land:
  - Cart (cookie token), guest checkout, variant picker (one row per `ProductOption.group_name`). Today `/carrinho` is a placeholder.
  - CEP autocomplete in checkout via the Correios API (reuses the existing `Correios::Api::Client`).
  - Shipping quotes — start stubbed (fixed PAC/SEDEX rates), then swap for a Correios quote call sharing the existing `Correios::Api::Client`.
  - InfinitePay **Pix** with webhook handler. Use `INFINITE_PAY_MODE=fake` for local dev — canned QR codes from fixtures, with a Rake task `simulate:infinitepay_webhook[order_id]` that POSTs to the webhook endpoint as if InfinitePay did.
  - Order state machine (AASM, §4 lifecycle) + capacity-booking transaction inside checkout.
  - Transactional emails in pt-BR via **Postmark** or **Resend** (decide before checkout lands): order placed, Pix QR + copy-paste, payment confirmed, payment failed.
  - Minimal `/admin`: order list with filters, single-order page, manual transitions for any state in the order lifecycle (kanban comes later).

**Gems still to add** (beyond Rails 8 defaults + what's already in `Gemfile`): `aasm`, `paper_trail`, `pundit`, `meta-tags`, `sitemap_generator`, `brazilian-documents`, `rack-attack`, plus dev/test (`factory_bot_rails`, `faker`, `vcr`). `webmock` already pinned for the Correios specs.

**Webhooks in dev**: ngrok with persistent subdomain to be documented in `.env.example` when the first webhook lands.

## Phase 2 — "Operate the business end-to-end"

End state: Vinicius fulfills real orders through the new admin, prints labels in batch, NF-e issued automatically.

- **InfinitePay card + parcelamento sem juros up to 6x** (or 12x — Vinicius decides whether to absorb fees).
- **Live Correios** — 🟡 partial. **Shipped:** pré-postagem creation (`Shipping::CreatePrePostagem` → `Correios::Api::PrePostagem`), the `Shipment` factory + lifecycle, and hourly rastro polling (`SyncPendingShipmentsJob` → `SyncShipmentJob`). **Still to land:** real-time quotes at PDP/cart (a `Correios::Api::Precos` adapter sharing the existing `Client`), wiring the operator-triggered label button into `/admin/shipments`, customer notification email on `tracking_code` capture, and once `Order` exists, transitioning the order on a final `tracking_state`.
- **Production kanban** (`/admin/production`): columns `pending → flashed → boxed → labeled → shipped`. Drag-drop with Stimulus + Turbo Streams (Solid Cable broadcasts updates to all open admin tabs). `Order#fulfillment_stage` enum is **separate** from `Order#status` (AASM tracks customer-facing state; `fulfillment_stage` tracks internal kanban).
- **Per-order workbench** (`/admin/orders/:id`):
  - Per-option checklist auto-generated from the line item's chosen `ProductOption` rows ("Flash ROM: Pokémon Crystal Clear v2.5.10" with checkbox)
  - ROM file lookup: clicking the ROM option shows the matching `RomFile` with download link from R2
  - Shipping panel: one-click Correios pré-postagem label → PDF
  - Timeline of state transitions (PaperTrail)
  - Customer-facing progress photos: drag-drop upload to Active Storage; "visible to customer" toggle. Visible photos appear on the customer's order page.
- **Bulk label printing** (`/admin/shipments/print_batch`): fetches selected orders' labels, merges into one PDF via `combine_pdf` or `prawn`. Trigger from kanban.
- **Daily checklist view**: aggregate ("flash 3 carts, source 1 shell, print 4 labels") — Vinicius's morning standup.
- **NF-e via NFe.io**: mocked first (`NFE_MODE=fake` env var → logs fake invoice number), live before Phase 2 demo. Issue automatically on payment confirmation via Solid Queue job.
- **PaperTrail** wired on key models.
- **`encrypts :cpf, :phone`** on Customer + Address.

## Phase 3 — "Customers come back"

End state: existing customers can log in, see their orders, see in-progress photos.

- Customer accounts via Rails 8 native authentication (`bin/rails generate authentication`). No Devise.
- Order history page; in-progress orders show progress photos uploaded by Vinicius.
- Abandoned-Pix-cart recovery email (Solid Queue cron, 1h/24h after Pix expiry).
- Discount codes (simple `Coupon` model: code, percent_off or amount_off_cents, max_uses, expires_at).
- Refunds + cancellation flow: Pix refund through InfinitePay API; cancellation only allowed before `em_producao` (3.2) per §0.1.
- SEO: sitemap.xml, JSON-LD on PDPs (Product + Offer + BreadcrumbList), Search Console verification, robots.txt.
- LGPD: privacy policy page (pt-BR), cookie consent banner, data-export rake task (`rake lgpd:export[email]`), data-deletion rake task.
- Reclame Aqui link in footer (per §0.2).

## Phase 4 — "Polish for cutover"

End state: app is deployable, observable, and ready for Vinicius to flip DNS when he says go.

- **Kamal deploy** to chosen VPS (see § Deferred Decisions): Postgres co-located on the same VPS; nightly `pg_dump` to R2 with bucket versioning; test restore documented in `docs/restore_drill.md`.
- **Cloudflare** in front of R2 + the app; Let's Encrypt via Kamal proxy.
- **Sentry** + **Better Stack** (logs + uptime).
- **WebP/AVIF** variants via `image_processing`; `loading="lazy"` below the fold; explicit width/height (CLS).
- Staging env (second VPS box, or same box with separate `prisma_engine_staging` deploy) for Vinicius to walk through.
- DNS cutover playbook handed to Vinicius — leave the actual flip to him.

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

## Critical files

🟢 In place today:

- `/home/ericktmr/Code/prisma_engine/` — Rails app root.
- `app/models/product.rb`, `category.rb`, `product_option.rb`, `product_photo.rb`, `tag.rb`, `product_tag.rb`, `question.rb` — catalog (ActiveRecord, FriendlyId on Product).
- `app/models/shipment.rb`, `shipment_tracking_event.rb` — Correios pré-postagem state + tracking lifecycle.
- `app/services/correios/api/` (`client.rb`, `tracking.rb`, `pre_postagem.rb`, `timestamp.rb`) — infrastructure / ACL.
- `app/services/shipping/` (`create_pre_postagem.rb`, `pre_postagem_request.rb`, `shipment_factory.rb`, `tracking_update.rb`) — domain.
- `app/jobs/sync_pending_shipments_job.rb`, `sync_shipment_job.rb` — application wiring (hourly orchestrator + per-shipment worker).
- `app/views/{layouts,pages,products,categories,cart,identification,shared}/*` — Bootstrap 4 + jQuery storefront port.
- `config/routes.rb` — legacy URL shape mirrored.
- `config/recurring.yml` — `SyncPendingShipmentsJob` hourly.
- `Procfile.dev`, `bin/dev`, `bin/setup`, `bin/share-dev`, `bin/pre-push-check`, `.env.example`, `compose.yaml`.
- `.github/workflows/ci.yml` — single workflow (see § CI in `CLAUDE.md`).

⚪ Still to create:

- `app/models/order.rb` — AASM lifecycle, transactional capacity booking (§4 snippet).
- `app/models/cart.rb`, `line_item.rb`, `payment.rb`, `address.rb`, `customer.rb`, `admin_user.rb`, `nfe_issuance.rb`, `rom_file.rb`.
- `app/controllers/admin/production_controller.rb` — kanban board (the killer feature).
- `app/views/admin/production/index.html.erb` — kanban view with Turbo Streams.
- `app/services/infinite_pay/api/` + `app/services/payments/` — InfinitePay client + domain use cases, mirroring `Correios::Api` + `Shipping`.
- `app/services/correios/api/precos.rb` + `app/services/shipping/quote.rb` — live shipping quotes (reuses the existing `Client`).
- `app/services/nfe_io/issue_invoice.rb`.
- `app/jobs/issue_nfe_job.rb`, `abandoned_cart_job.rb`.
- `db/seeds/products.rb` + `db/seeds/images/` — production seed (today the catalog seed is hand-curated).
- `config/deploy.yml` — Kamal config (deployment).
- `docs/legacy_html/` — frozen HTML snapshots from prismagames.com.br (currently in `tmp/snapshot/`, gitignored — promote to `docs/` once stable).
- `docs/restore_drill.md` — backup/restore playbook.

## Verification (per phase)

Each phase ends with a concrete demo to Vinicius — no phase is "done" until the demo works end-to-end on a real device.

**Phase 1 verification**
- 🟢 `bin/dev` boots; storefront loads at localhost:3000 visually matching prismagames.com.br.
- 🟢 Catalog renders from ActiveRecord (Category / Product / ProductPhoto / Question), legacy URL shape works (`/produtos`, `/produto/:slug`, etc.).
- ⚪ Place a test order with a ROM-hack variant chosen through the storefront.
- ⚪ Pix QR code email arrives in dev inbox (Letter Opener or Postmark sandbox).
- ⚪ `rake simulate:infinitepay_webhook[order_number]` flips the order to `pagamento_confirmado`.
- ⚪ Order appears in `/admin/orders` with the chosen options visible.

**Phase 2 verification**
- ⚪ Real InfinitePay sandbox card payment succeeds with installments.
- ⚪ Correios quote returns ≥2 services (PAC + SEDEX) with prices in cart.
- 🟢 `Shipping::CreatePrePostagem` returns a tracking_code against the Correios sandbox and persists a `Shipment`; `SyncShipmentJob` reconciles its rastro events into `tracking_state`.
- ⚪ Drag a card across the kanban; status persists; second admin browser tab updates live.
- ⚪ Click "Print labels" on 3 selected orders → single merged PDF downloads.
- ⚪ NF-e issuance job runs against NFe.io sandbox; PDF URL stored on Order.

**Phase 3 verification**
- Existing customer logs in, sees order history with progress photos
- Apply a discount code at checkout; total updates correctly
- Trigger a refund; Pix refund created in InfinitePay sandbox; email sent
- View source on a PDP shows valid `application/ld+json` Product schema (validate at search.google.com/test/rich-results)
- `rake lgpd:export[customer@example.com]` produces a JSON dump

**Phase 4 verification**
- `kamal deploy` from clean checkout deploys to the chosen VPS staging in <5 min
- Restore the latest pg_dump into a fresh DB and the staging app boots
- Sentry captures a deliberately-thrown error in staging
- Cloudflare serves WebP for product images on a mobile UA
- PageSpeed Insights ≥90 mobile on PDP

## What's deferred / cut (project-specific)

**Cut entirely**: multi-warehouse, ML recs, ML fraud, A/B framework, GraphQL, mobile app, subscription billing, wholesale/B2B tier, loyalty/referrals, Meilisearch (`pg_search` is enough at 24 SKUs; defer even that until catalog grows past ~200).

**Deferred past Phase 4**: real-time inventory races (24 SKUs + 1 fulfiller — capacity contention is rare), 2FA on admin, reviews/ratings (Reclame Aqui covers this), faceted search SEO, dashboards beyond a simple "orders this week" view.

---

# Deferred Decisions

Recorded so we don't lose them. Pick at the time the decision actually matters, not before.

- **VPS provider** (production deployment). Pick at deployment time. **Brazilian providers preferred** because audience is Brazil-only and 10 ms vs 200 ms on Pix checkout matters. First-look candidates in priority order:
  1. **Magalu Cloud** (São Paulo, BRL billing, BR provider)
  2. **DigitalOcean São Paulo (BRA1)** (well-documented, strong Kamal support, ~10 ms latency)
  3. **AWS Lightsail sa-east-1** (cheap VPS, AWS ecosystem if useful later)
  4. **Hetzner Cloud** (cheapest globally, canonical Kamal pairing, but ~200 ms latency from BR — only if budget dominates latency)
- ~~**CI pipeline**~~ — 🟢 `.github/workflows/ci.yml` shipped: rubocop, brakeman, bundler-audit, importmap audit, semgrep (diff mode), gitleaks, dependency review, tests + system-tests + 100% SimpleCov + undercover (changed-line coverage), reek (advisory), sticky `ci-quality` PR comment. Local parity via `bin/pre-push-check`. See `CLAUDE.md`.
- ~~**Pre-commit hooks**~~ — 🟢 `bin/pre-push-check` (script-based, not Lefthook) runs the same gauntlet locally before push.
- ~~**GitHub remote**~~ — 🟢 hosted at `github.com/erick-tmr/prisma_engine`.
- **Kamal config** (`config/deploy.yml`, `.kamal/secrets`) — `--skip-kamal` at scaffold time; add at deployment with a target VPS chosen. Production `Dockerfile` itself is generated by `rails new` and lives in the repo from day one.
- **Error monitoring** (Sentry / Honeybadger / AppSignal) — defer until first deploy.
- **Solid Queue worker process in `bin/dev` Procfile** — Solid Queue runs via `bin/jobs` today; revisit `SOLID_QUEUE_IN_PUMA` for the single-VPS deploy.
- **Auth stack** (Devise vs Rails 8 built-in `bin/rails generate authentication` vs Rodauth) — decide when first user-facing flow lands. Current bias: Rails 8 native.
