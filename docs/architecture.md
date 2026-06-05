# Ecommerce Platform — Architecture & Implementation Plan

**Context:** Small niche ecommerce — limited customers, limited product catalog. Built from scratch (no Shopify/Spree/Solidus). Stack: **Ruby on Rails monolith**.

---

## 0. Project Decisions (locked in)

| Decision | Choice | Implication |
|---|---|---|
| Product domain | **Handmade / made-to-order** | No traditional stock; production capacity + lead times; per-order personalization; returns mostly non-applicable |
| Primary market | **Brazil** (BRL, pt-BR) | PIX is mandatory; parcelamento expected; NF-e issuance; LGPD; Correios/Melhor Envio shipping; ViaCEP |
| Deployment | **Kamal on a VPS** | Single-box friendly choices: Solid Queue + Solid Cache, Postgres co-located or managed; S3-compatible object storage external (R2/B2/Spaces) |
| Codebase | Rails 8 majestic monolith | One repo, one deploy |

These four decisions override any conflicting defaults later in the document.

---

## 0.1. Niche-specific model: handmade / made-to-order

The standard ecommerce stock model **does not apply**. Replace it with:

### Production capacity, not stock

- A product has `lead_time_days` (e.g., "ships in 7–10 business days") — show on PDP and in cart
- Optional `daily_capacity` per product or per artisan to throttle order intake
- "Stock" only exists for ready-made pieces; modeled as a separate `ready_to_ship` flag with `quantity_on_hand`
- For pure made-to-order items: no decrement, but enforce capacity ceiling per day/week

### Personalization

- `LineItem` needs structured `customizations` (JSONB): text engraving, color, size, image upload
- Validate per product (e.g., max 20 chars on engraving) — schema lives on the Product
- Customer uploads (e.g., reference photos) via Active Storage → S3-compatible bucket
- Personalized line items must surface in admin/fulfillment views immediately

### Order lifecycle differs

```
pending → paid → in_production → ready_to_ship → shipped → delivered
                              ↘ cancelled (only before in_production)
```

- Cancellation window closes when production starts (communicate clearly at checkout)
- Production status visible to customer ("We started your piece on X")
- Optional progress photos uploaded by artisan to the order

### Returns under Brazilian law (CDC art. 49)

- 7-day right of regret applies to online sales **except** for personalized/made-to-order goods
- Show this exemption clearly on PDP, cart, and order confirmation (legal protection)
- Ready-made items: full 7-day return window applies — build the flow

---

## 0.2. Brazil-specific stack additions

| Concern | Choice | Notes |
|---|---|---|
| Payments | **Mercado Pago** or **Pagar.me** (Stripe BR is an option but weaker on PIX/parcelamento) | PIX + cards + boleto in one integration |
| PIX | First-class checkout option | ~30–40% of online payments in BR; instant settlement, lowest fees |
| Card installments | Parcelamento up to 6x or 12x sem juros | Cultural expectation; absorb fee or pass to customer |
| Boleto | Optional | High abandonment (~70%) but still expected by some segments |
| NF-e (electronic invoice) | **eNotas**, **NFe.io**, or **Bling** | Mandatory for businesses; issue automatically on payment confirmation |
| Address | **ViaCEP** (free) | Autocomplete from CEP; reduces failed deliveries |
| Shipping | **Melhor Envio** or **Frenet** | Aggregates Correios + private carriers; real-time quotes |
| Anti-fraud | Provider's native (Mercado Pago/Pagar.me have built-in) | **Clearsale** or **Konduto** if scaling |
| Locale | i18n with pt-BR as default | `R$ 1.234,56`, dd/mm/yyyy, brazilian-documents gem for CPF/CNPJ |
| Compliance | **LGPD** (not GDPR) | ANPD authority; same rights (access, deletion, portability) |
| Reputation | Reclame Aqui presence from day 1 | Brazilian buyers check it before purchasing |

**Replaces in the main doc:** Stripe → Mercado Pago/Pagar.me; Stripe Tax → eNotas/NFe.io; flat-rate shipping → Melhor Envio quotes; GDPR/CCPA → LGPD.

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
- Storefront (server-rendered HTML + Hotwire/Turbo)
- Customer accounts and checkout
- Backoffice admin
- Background jobs (Sidekiq or Solid Queue)
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
| Frontend | Hotwire (Turbo + Stimulus) + Tailwind |
| File storage | Active Storage + S3-compatible bucket |
| CDN | Cloudflare or Bunny.net (for images and static assets) |
| Email | Postmark / Resend / SendGrid (transactional) |
| Hosting | **Kamal on VPS** — see §0.3 and § Deferred Decisions |

### Key gems

```ruby
# SEO
gem 'meta-tags'           # per-page <title>, <description>, OG tags
gem 'sitemap_generator'   # XML sitemap + auto-ping to search engines
gem 'friendly_id'         # /products/leather-wallet slugs
gem 'better_seo'          # JSON-LD structured data (Product, Breadcrumb, etc.)

# Domain
gem 'aasm'                # state machine for orders
gem 'paper_trail'         # audit log
gem 'pundit'              # authorization (admin/staff/customer roles)
gem 'pg_search'           # Postgres full-text search

# Payments / external (Brazil — see §0.2)
gem 'mercadopago-sdk'     # or 'pagarme-ruby'
gem 'brazilian-documents' # CPF/CNPJ validation + formatting
gem 'image_processing'    # WebP/AVIF variants

# Operational
gem 'rack-attack'         # rate limiting
gem 'sidekiq'             # if not using Solid Queue
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

Use **Mercado Pago** or **Pagar.me** (see §0.2). Never store card data ourselves.

Critical patterns (provider-agnostic):
- **Idempotency keys** on every payment attempt — prevents double-charging on retries
- **Webhook handling** for async events (payment approved/rejected/refunded) — never trust the synchronous response alone; PIX is async by nature
- **3DS2** on cards — shifts fraud liability from merchant to issuer
- Store `external_payment_id` and `payment_method` (pix/card/boleto) on Order for reconciliation
- PIX-specific: order is `pending` until webhook confirms; show QR code + copy-paste code; expire after 30 min

#### Inventory race conditions (made-to-order variant)

Traditional stock locking only applies to ready-made pieces. For made-to-order, the equivalent is **production capacity**:

```ruby
ActiveRecord::Base.transaction do
  capacity = ProductionSlot.lock.where(product_id: id, date: target_date).first
  raise CapacityExceeded if capacity.booked + qty > capacity.daily_max
  capacity.update!(booked: capacity.booked + qty)
  Order.create!(...)
end
```

For ready-made pieces, fall back to standard `SELECT FOR UPDATE` on `quantity_on_hand`.

### Operational

#### Tax & invoicing (Brazil)

Don't build it. For BR you need **NF-e issuance** (legal requirement for businesses), not just tax calculation. Use **eNotas**, **NFe.io**, or **Bling** — they handle SEFAZ integration, tax bracket lookup (NCM codes), and PDF/XML generation. Issue automatically on payment confirmation via background job.

#### Shipping (Brazil)

Use **Melhor Envio** or **Frenet** — they aggregate Correios (PAC/SEDEX) plus private carriers (Jadlog, Loggi) and return real-time quotes from a single API. Quote at PDP/cart with the customer's CEP.

Must-haves:
- CEP autocomplete via ViaCEP (free) — fills street/neighborhood/city/state
- Address validation (bad addresses = failed deliveries = chargebacks)
- Tracking code capture + customer notification
- Shipping label generation through the same provider

#### Order state machine (made-to-order)

```
pending → paid → in_production → ready_to_ship → shipped → delivered
                              ↘ cancelled (only before in_production) → refunded
                              ↘ returned → refunded   # ready-made only
```

Use `aasm`. Each transition:
- Auditable (who/when/why)
- Triggers side effects via background jobs
- Recoverable

#### Carrier integration layering (anti-corruption layer)

Correios (and any future carrier) is integrated through three layers so the 3rd-party
API stays isolated from our domain — the convention lives in `CLAUDE.md`:

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
behind the `Api` boundary, so swapping Correios for another carrier (e.g. Melhor Envio)
means a new `Api` adapter without touching the domain.

#### Pré-postagem creation (Correios label generation)

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

It's **triggered manually from the backoffice** — an operator presses a button to
generate the label for an order; there's no automatic trigger.

#### Shipment tracking sync (Correios polling)

Our Correios contract has **no webhooks**, so tracking is **polled**. An hourly
orchestrator (`SyncPendingShipmentsJob`) selects shipments still in flight and
fans out one `SyncShipmentJob` per shipment — each syncs in isolation, with its
own retries and a Solid Queue concurrency cap so a large fan-out can't trip
Correios' rate limit. A shipment carries its own `tracking_state`
(`pending → in_transit → delivered / returned / unavailable`) derived from rastro
events; the final states stop the polling loop.

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

The payment provider's native antifraud handles 95% of cases (Mercado Pago / Pagar.me). Add:
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

1. Product catalog + categories with `lead_time_days` and personalization schema (JSONB)
2. Cart (session-based) with customization fields per line item + guest checkout
3. CEP autocomplete (ViaCEP) + Melhor Envio quote at cart
4. Payment integration: PIX first (highest conversion in BR), then card with parcelamento — via Mercado Pago or Pagar.me
5. Order model with made-to-order state machine + cancellation window logic
6. NF-e issuance via eNotas/NFe.io on payment confirmation (background job)
7. Transactional emails (pt-BR) + PIX QR code email
8. Basic admin: order list, production status update, customer customizations visible

### Phase 2 — Can you operate the business?

9. Production capacity model (daily/weekly slots per product)
10. Order fulfillment workflow + Melhor Envio label printing + tracking notifications
11. Refunds + cancellations (PIX refund, card refund/chargeback handling)
12. Returns flow for ready-made items only (CDC art. 49)
13. Sitemap + structured data + Search Console (BR property)

### Phase 3 — Can you grow it?

14. Abandoned cart recovery (PIX-expired carts are a high-recovery segment)
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
4. **Use hosted services for the regulated stuff.** Payments (Mercado Pago/Pagar.me), NF-e (NFe.io/eNotas), email (Postmark/Resend), CDN (Cloudflare) — never reinvent these.
5. **Background everything that's not in the request path.** Emails, webhooks, fulfillment side-effects, analytics events — all in jobs.
6. **Cache aggressively at the edge.** Product pages and category pages are the hot path; CDN them.
7. **Audit everything.** Orders, refunds, admin actions, inventory changes — all logged with who/when/why.

---

# Migration Plan — Prisma Games → `prisma_engine`

## Context

Vinicius runs https://www.prismagames.com.br/ on **Meloja** (Brazilian SaaS), selling ~24 SKUs of retro Game Boy cartridges and ROM-hacked variants. Every order is **fully made-to-order**: he sources/cleans the cartridge, flashes the ROM, builds the box, prints the Correios label, and ships it. The current platform handles the storefront fine but **no SaaS supports the fulfillment workflow he actually needs** — that's the reason for the rebuild. Secondary motivation: the user is doing this as a learning/craft project.

The rebuild is **greenfield** at `/home/ericktmr/Code/prisma_engine`. The made-to-order assumption (§0.1 above) applies in full.

**Migration approach (per user)**: not a data migration. Clone the existing site's visual layout (HTML/CSS) into Rails ERB+Tailwind, manually re-seed the 24 SKUs, then iterate. No Meloja exporter. Cutover strategy deferred — keep prismagames.com.br on Meloja until the new app is ready and Vinicius approves the flip.

**The backoffice is the product.** The storefront is "just to collect orders." Engineering effort should weight ~50/50 storefront/backoffice, not 80/20.

## Recommended approach

A single Rails 8 app at `/home/ericktmr/Code/prisma_engine/` containing storefront, customer-facing checkout, and an `/admin` namespace for Vinicius's production workbench. Hotwire-only (no React, no JS bundler). Importmap + Stimulus + Turbo Streams for live admin updates. PostgreSQL co-located on a VPS via Kamal, with R2 for object storage. Pundit-gated admin with role `admin/fulfillment/support` (Vinicius will be the only admin for now).

The HTML/CSS clone happens in **parallel** with domain modeling in Phase 1 — markup doesn't block models and vice versa.

## Domain model — first cut

UUIDs for public-facing resources (Order, Cart, LineItem, Payment); bigint for internal-only. Encrypt PII (`encrypts :cpf, :phone`) per LGPD.

| Model | Notes |
|---|---|
| **Product** | `slug`, `name`, `price_cents`, `lead_time_days`, `daily_capacity` (nullable → unlimited), `customization_schema` (jsonb), `published`. FriendlyId, PaperTrail, pg_search later. |
| **Variant** | belongs_to Product. `sku`, `price_modifier_cents`, `customization_overrides`. Lets one cart have ROM-hacked + standard SKUs. |
| **ProductionSlot** | `(product_id, date, daily_max, booked_count)`. Locked in checkout transaction (§4 above). For 24 SKUs / 1 fulfiller, may collapse to a global daily slot table — defer the decision until usage shows contention. |
| **Cart** | guest-cookie token; nullable `customer_id`; `expires_at`. |
| **LineItem** | belongs_to Cart **and** Order (two FKs, not polymorphic). `customizations` jsonb validated against Product schema. `fulfillment_progress` jsonb tracks per-step checkboxes for the workbench. |
| **Order** | human-readable `number` (`PG-2026-000123`). AASM lifecycle from §4 above. Address fields snapshotted as jsonb to survive customer edits. PaperTrail. |
| **Address** | reusable for customer book + order snapshot. CEP/street/number/complement/neighborhood/city/state. CPF on shipping. |
| **Payment** | `provider`, `method` (pix/card/boleto), `external_id`, AASM (pending → authorized → captured → refunded → failed), idempotency keys. `qr_code_payload`, `boleto_url`. |
| **Shipment** | `provider` (melhor_envio), `service` (PAC/SEDEX), `tracking_code`, `label_url`, `posted_at`, `delivered_at`. |
| **NfeIssuance** | `provider` (nfe_io), AASM (pending → issued → failed), `pdf_url`, `xml_url`, `numero`, `serie`. Retried on failure. |
| **Customer** | `has_secure_password` (Rails 8 native auth), `cpf` (encrypted), `lgpd_consent_at`. |
| **AdminUser** | role enum, `otp_secret` (2FA optional in Phase 1). |
| **RomFile** | `name`, `version`, `notes`, has_one_attached :file (Active Storage → R2). Linked to Variant by FK or referenced from customization JSONB by `rom_identifier` string. |

**AASM** on Order, Payment, NfeIssuance.
**FriendlyId** on Product.
**PaperTrail** on Product, Variant, Order, Payment, NfeIssuance, AdminUser actions.

**Customization schema example** (per Product):
```json
{
  "fields": [
    { "key": "rom_choice", "label": "ROM", "type": "select",
      "options": ["Stock", "Pokémon Crystal Clear", "Polished Ruby"], "required": true },
    { "key": "shell_color", "label": "Cor do shell", "type": "select",
      "options": ["Cinza original", "Transparente", "Amarelo"], "required": true },
    { "key": "engraving", "label": "Gravação", "type": "text", "max_length": 20 },
    { "key": "label_art", "label": "Arte da etiqueta", "type": "file",
      "accept": ["image/png","image/jpeg"] }
  ]
}
```
A `Customizations::Validator` PORO validates LineItem payloads against this schema (rejects unknown keys, enforces required + length + file type). Same partial renders both storefront input and admin read-only view.

## Phase 1 — "Look like the old site, take a PIX order" (~3 weeks)

End state: Vinicius places a PIX test order on the new app and sees it in his admin queue.

**HTML/CSS clone (parallel track)**
1. `wget --mirror --no-parent --convert-links --page-requisites https://www.prismagames.com.br/` into `tmp/legacy_clone/` (gitignored). Save view-source for homepage, category, PDP into `docs/legacy_html/` so the snapshots survive.
2. Port markup skeletons (header, footer, homepage, category grid, PDP, cart, checkout) into `app/views/storefront/` partials. Rebuild markup from scratch even when it visually matches — do not lift Meloja-templated HTML wholesale (licensing).
3. Drop scraped CSS into `app/assets/stylesheets/legacy/site.css`; Propshaft serves as-is. Strip third-party tracking and Meloja branding selectors.
4. Tailwind-ify component-by-component (header → product card → PDP → cart → checkout); delete legacy CSS rules as they're replaced.
5. **Do not lift product descriptions or customer photos.** Vinicius rewrites copy; new product photos go through Active Storage.

**Domain + checkout**
- Domain models from the table above (`bin/rails g model …` for each).
- Seed 24 SKUs in `db/seeds/products.rb` — explicit `Product.create!` calls per cartridge with customization schemas. Photos staged in `db/seeds/images/`.
- Cart (cookie token), guest checkout, full customizations form.
- ViaCEP autocomplete in checkout (free, no auth).
- Shipping quotes **stubbed** in Phase 1 (fixed PAC/SEDEX rates). Live Melhor Envio integration in Phase 2.
- Mercado Pago **PIX** integration with webhook handler. Use `MERCADO_PAGO_MODE=fake` for local dev — canned QR codes from fixtures, with a Rake task `simulate:mp_webhook[order_id]` that POSTs to the webhook endpoint as if Mercado Pago did.
- Order state machine (AASM, §4 lifecycle) + capacity-booking transaction inside checkout.
- Transactional emails in pt-BR via **Postmark** or **Resend** (decide week 1): order placed, PIX QR + copy-paste, payment confirmed, payment failed.
- Minimal `/admin`: order list with filters, single-order page, manual `mark_as_paid`/`mark_in_production`/`mark_shipped` buttons (kanban comes Phase 2).

**Initial gems beyond Rails 8 defaults**: `aasm`, `friendly_id`, `paper_trail`, `pundit`, `meta-tags`, `sitemap_generator`, `brazilian-documents`, `image_processing`, `rack-attack`, plus dev/test (`factory_bot_rails`, `faker`, `vcr`, `webmock`).

**Webhooks in dev**: ngrok with persistent subdomain documented in `.env.example`.

## Phase 2 — "Operate the business end-to-end" (~3 weeks)

End state: Vinicius fulfills 5 real orders through the new admin, prints labels in batch, NF-e issued automatically.

- **Mercado Pago card + parcelamento sem juros up to 6x** (or 12x — Vinicius decides whether to absorb fees).
- **Live Melhor Envio**: real-time quotes at PDP/cart, label generation post-payment, tracking-code capture + customer email.
- **Production kanban** (`/admin/production`): columns `pending → flashed → boxed → labeled → shipped`. Drag-drop with Stimulus + Turbo Streams (Solid Cable broadcasts updates to all open admin tabs). `Order#fulfillment_stage` enum is **separate** from `Order#status` (AASM tracks customer-facing state; `fulfillment_stage` tracks internal kanban).
- **Per-order workbench** (`/admin/orders/:id`):
  - Customizations checklist auto-generated from LineItem JSONB ("Flash ROM: Pokémon Crystal Clear v2.5.10" with checkbox)
  - ROM file lookup: clicking the customization shows the matching `RomFile` with download link from R2
  - Shipping panel: one-click Melhor Envio label → PDF
  - Timeline of state transitions (PaperTrail)
  - Customer-facing progress photos: drag-drop upload to Active Storage; "visible to customer" toggle. Visible photos appear on the customer's order page.
- **Bulk label printing** (`/admin/shipments/print_batch`): fetches selected orders' labels, merges into one PDF via `combine_pdf` or `prawn`. Trigger from kanban.
- **Daily checklist view**: aggregate ("flash 3 carts, source 1 shell, print 4 labels") — Vinicius's morning standup.
- **NF-e via NFe.io**: mocked first (`NFE_MODE=fake` env var → logs fake invoice number), live before Phase 2 demo. Issue automatically on payment confirmation via Solid Queue job.
- **PaperTrail** wired on key models.
- **`encrypts :cpf, :phone`** on Customer + Address.

## Phase 3 — "Customers come back" (~2 weeks)

End state: existing customers can log in, see their orders, see in-progress photos.

- Customer accounts via Rails 8 native authentication (`bin/rails generate authentication`). No Devise.
- Order history page; in-progress orders show progress photos uploaded by Vinicius.
- Abandoned-PIX-cart recovery email (Solid Queue cron, 1h/24h after PIX expiry).
- Discount codes (simple `Coupon` model: code, percent_off or amount_off_cents, max_uses, expires_at).
- Refunds + cancellation flow: PIX refund through Mercado Pago API; cancellation only allowed before `in_production` per §0.1.
- SEO: sitemap.xml, JSON-LD on PDPs (Product + Offer + BreadcrumbList), Search Console verification, robots.txt.
- LGPD: privacy policy page (pt-BR), cookie consent banner, data-export rake task (`rake lgpd:export[email]`), data-deletion rake task.
- Reclame Aqui link in footer (per §0.2).

## Phase 4 — "Polish for cutover" (~1–2 weeks)

End state: app is deployable, observable, and ready for Vinicius to flip DNS when he says go.

- **Kamal deploy** to chosen VPS (see § Deferred Decisions): Postgres co-located on the same VPS; nightly `pg_dump` to R2 with bucket versioning; test restore documented in `docs/restore_drill.md`.
- **Cloudflare** in front of R2 + the app; Let's Encrypt via Kamal proxy.
- **Sentry** + **Better Stack** (logs + uptime).
- **WebP/AVIF** variants via `image_processing`; `loading="lazy"` below the fold; explicit width/height (CLS).
- **Boleto via Mercado Pago** if Vinicius wants it (high abandonment ~70% — confirm desire before building).
- Staging env (second VPS box, or same box with separate `prisma_engine_staging` deploy) for Vinicius to walk through.
- DNS cutover playbook handed to Vinicius — leave the actual flip to him.

## Decisions to lock in week 1

| Decision | Recommendation | Why |
|---|---|---|
| Payment gateway | **Mercado Pago** | Best PIX UX in BR, native parcelamento sem juros, antifraud included, brand customers already trust |
| NF-e provider | **NFe.io** | Cleaner REST API than eNotas; pay-per-issue pricing fits 24-SKU volume; not an ERP like Bling |
| VPS provider | **See § Deferred Decisions** | Pick at deployment time; Brazilian providers preferred (BR latency on PIX) |
| Postgres | **Co-located on the VPS** for all 4 phases | Daily pg_dump → R2 covers 99% of risk; managed Postgres is a future migration |
| Background jobs | **Solid Queue** | Rails 8 default; Postgres-backed; no Redis to operate |
| Admin auth | **Rails 8 native authentication generator** | No Devise; less ceremony |
| Frontend JS | **Importmap + Stimulus + Turbo** (no bundler) | Aligns with §0 boring-stack principle |
| Test framework | **Minitest** (Rails 8 default) | Learning angle; revisit at Phase 2 if integration tests get awkward |
| Email provider | **Postmark** or **Resend** | Both work from BR; pick one week 1 and stop deciding |

## Open items / needs from Vinicius

These don't block kicking off Phase 1 but block portions of Phase 1–2:

- **CNPJ status** — required for Mercado Pago merchant account, NFe.io account, Melhor Envio account. Confirm he has one and apps are submitted (approvals can take 1–2 weeks).
- **NCM codes** for each cartridge type — wrong NCM = NF-e fines. Lock with Vinicius's accountant before Phase 2.
- **Brand assets** — logo source files, brand fonts, color tokens. Otherwise we lift from current site (visual only, not files he doesn't own).
- **Per-product customization schemas** — Vinicius needs to enumerate ROM choices, shell colors, label art rules per cartridge. Use a shared spreadsheet → seed file.
- **Mercado Pago + NFe.io + Melhor Envio sandbox credentials** — needed by end of Phase 1 dev.
- **Maximum installments policy** — 6x or 12x sem juros? Who eats the fee?
- **Boleto: yes or no?** — Phase 4 flag.

## Critical files to create

- `/home/ericktmr/Code/prisma_engine/` — Rails app root
- `app/models/product.rb` — customization_schema declaration, lead_time_days, FriendlyId, PaperTrail, pg_search hooks
- `app/models/order.rb` — AASM lifecycle, transactional capacity booking (§4 snippet)
- `app/models/line_item.rb` — `Customizations::Validator` integration, fulfillment_progress jsonb
- `app/models/concerns/customizations/validator.rb` — schema-driven validation PORO
- `app/controllers/admin/production_controller.rb` — kanban board controller (the killer feature)
- `app/views/admin/production/index.html.erb` — kanban view with Turbo Streams
- `app/services/mercado_pago/create_pix_payment.rb` — first service object; sets convention for all external integrations
- `app/services/melhor_envio/quote_shipping.rb`, `app/services/melhor_envio/generate_label.rb`
- `app/services/nfe_io/issue_invoice.rb`
- `app/services/via_cep/lookup.rb`
- `app/jobs/issue_nfe_job.rb`, `app/jobs/abandoned_cart_job.rb`
- `db/seeds/products.rb` + `db/seeds/images/` — 24 SKU seed
- `config/deploy.yml` — Kamal config (Phase 4)
- `Procfile.dev`, `bin/dev`, `.env.example`
- `docs/legacy_html/` — frozen HTML snapshots from prismagames.com.br
- `docs/restore_drill.md` — backup/restore playbook (Phase 4)

## Verification (per phase)

Each phase ends with a concrete demo to Vinicius — no phase is "done" until the demo works end-to-end on a real device.

**Phase 1 verification**
- `bin/dev` boots; storefront loads at localhost:3000 visually matching prismagames.com.br
- Place a test order with a ROM-hack customization through the storefront
- PIX QR code email arrives in dev inbox (Letter Opener or Postmark sandbox)
- `rake simulate:mp_webhook[order_number]` flips the order to `paid`
- Order appears in `/admin/orders` with the customization visible

**Phase 2 verification**
- Real Mercado Pago sandbox card payment succeeds with installments
- Melhor Envio quote returns ≥2 services with prices in cart
- Drag a card across the kanban; status persists; second admin browser tab updates live
- Click "Print labels" on 3 selected orders → single merged PDF downloads
- NF-e issuance job runs against NFe.io sandbox; PDF URL stored on Order

**Phase 3 verification**
- Existing customer logs in, sees order history with progress photos
- Apply a discount code at checkout; total updates correctly
- Trigger a refund; PIX refund created in Mercado Pago sandbox; email sent
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

- **VPS provider (Phase 4 — production deployment).** Pick at deployment time. **Brazilian providers preferred** because audience is Brazil-only and 10 ms vs 200 ms on PIX checkout matters. First-look candidates in priority order:
  1. **Magalu Cloud** (São Paulo, BRL billing, BR provider)
  2. **DigitalOcean São Paulo (BRA1)** (well-documented, strong Kamal support, ~10 ms latency)
  3. **AWS Lightsail sa-east-1** (cheap VPS, AWS ecosystem if useful later)
  4. **Hetzner Cloud** (cheapest globally, canonical Kamal pairing, but ~200 ms latency from BR — only if budget dominates latency)
- **CI pipeline** (GitHub Actions or alternative) — wire up once there's app code to gate.
- **Pre-commit hooks** (Lefthook / Overcommit) — same reason.
- **Kamal config** (`config/deploy.yml`, `.kamal/secrets`) — `--skip-kamal` at scaffold time; add at Phase 4 with a target VPS chosen. Production `Dockerfile` itself is generated by `rails new` and lives in the repo from day one.
- **Error monitoring** (Sentry / Honeybadger / AppSignal) — defer to Phase 1 launch.
- **Solid Queue worker process in `bin/dev` Procfile** — add when first background job ships.
- **Auth stack** (Devise vs Rails 8 built-in `bin/rails generate authentication` vs Rodauth) — decide when first user-facing flow lands.
- **GitHub remote** (private repo + push) — gh CLI install pending; revisit after scaffold lands locally.
