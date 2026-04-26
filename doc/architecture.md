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
| VPS provider | Hetzner (best price/perf) or DigitalOcean (BR latency via NYC/SF; consider Magalu Cloud for in-country) | |

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
| Hosting | **Kamal on VPS** (Hetzner / DO / Magalu Cloud) — see §0.3 |

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

Using Stripe Checkout/Elements correctly = **SAQ A** (minimal compliance). Card data never touches our server. **Watch out:** misclassifying as SAQ A when partial Stripe JS could be tampered with — actually requires SAQ A-EP. This is a common, dangerous error.

#### Privacy laws

**LGPD** (Brazil) — administered by ANPD. Same conceptual rights as GDPR.

- Privacy policy + cookie consent banner (pt-BR)
- Right to deletion — implement hard-delete or anonymize flow
- Data export — JSON dump of user's data on request
- Encrypt PII at rest (`encrypts :field` is built into Rails 7+)
- Document a `Encarregado de Dados` (DPO) contact on the site

#### Fraud prevention

Stripe Radar handles 95% of cases. Add:
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

## 5. MVP Build Order

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
- ML-based fraud detection (Stripe Radar suffices)
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
4. **Use hosted services for the regulated stuff.** Payments (Stripe), tax (Stripe Tax), email (Postmark), CDN (Cloudflare) — never reinvent these.
5. **Background everything that's not in the request path.** Emails, webhooks, fulfillment side-effects, analytics events — all in jobs.
6. **Cache aggressively at the edge.** Product pages and category pages are the hot path; CDN them.
7. **Audit everything.** Orders, refunds, admin actions, inventory changes — all logged with who/when/why.
