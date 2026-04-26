# Prisma Games — Migration Plan to Rails 8 Monolith

## Context

Vinicius runs https://www.prismagames.com.br/ on **Meloja** (Brazilian SaaS), selling ~24 SKUs of retro Game Boy cartridges and ROM-hacked variants. Every order is **fully made-to-order**: he sources/cleans the cartridge, flashes the ROM, builds the box, prints the Correios label, and ships it. The current platform handles the storefront fine but **no SaaS supports the fulfillment workflow he actually needs** — that's the reason for the rebuild. Secondary motivation: the user is doing this as a learning/craft project.

The rebuild is **greenfield**. `/home/ericktmr/Code/` is empty except for the architecture doc, which is already comprehensive (Rails 8, Kamal/VPS, Solid Queue/Cache, Mercado Pago/Pagar.me, ViaCEP/Melhor Envio, NF-e, LGPD, made-to-order capacity, JSON-LD SEO). **The architecture doc stays as written** — its made-to-order assumption was correct after all. This plan adapts it to Prisma Games specifics.

**Migration approach (per user)**: not a data migration. Clone the existing site's visual layout (HTML/CSS) into Rails ERB+Tailwind, manually re-seed the 24 SKUs, then iterate. No Meloja exporter. Cutover strategy deferred — keep prismagames.com.br on Meloja until the new app is ready and Vinicius approves the flip.

**The backoffice is the product.** The storefront is "just to collect orders." Engineering effort should weight ~50/50 storefront/backoffice, not 80/20.

---

## Recommended approach

A single Rails 8 app at `/home/ericktmr/Code/prisma_games/` containing storefront, customer-facing checkout, and an `/admin` namespace for Vinicius's production workbench. Hotwire-only (no React, no JS bundler). Importmap + Stimulus + Turbo Streams for live admin updates. PostgreSQL co-located on a Hetzner VPS via Kamal, with R2 for object storage. Pundit-gated admin with role `admin/fulfillment/support` (Vinicius will be the only admin for now).

The HTML/CSS clone happens in **parallel** with domain modeling in Phase 1 — markup doesn't block models and vice versa.

---

## Locked architecture (from arch doc)

Re-read `/home/ericktmr/Code/ecommerce-architecture.md` at each phase boundary. Key sections that govern day-to-day decisions:

- §0 — four locked decisions (made-to-order, Brazil, Kamal/VPS, Rails 8 monolith)
- §0.1 — production capacity replaces stock; personalization JSONB on LineItem; cancellation closes when production starts; CDC art. 49 exemption applies
- §0.2 — Mercado Pago/Pagar.me, eNotas/NFe.io, ViaCEP, Melhor Envio, LGPD
- §0.3 — Hetzner/DO + Kamal + Solid Queue + R2 + Cloudflare
- §3 — SEO checklist (JSON-LD, sitemap, Core Web Vitals)
- §4 — order state machine, idempotency, capacity-locking transaction snippet

---

## Domain model — first cut

UUIDs for public-facing resources (Order, Cart, LineItem, Payment); bigint for internal-only. Encrypt PII (`encrypts :cpf, :phone`) per LGPD.

| Model | Notes |
|---|---|
| **Product** | `slug`, `name`, `price_cents`, `lead_time_days`, `daily_capacity` (nullable → unlimited), `customization_schema` (jsonb), `published`. FriendlyId, PaperTrail, pg_search later. |
| **Variant** | belongs_to Product. `sku`, `price_modifier_cents`, `customization_overrides`. Lets one cart have ROM-hacked + standard SKUs. |
| **ProductionSlot** | `(product_id, date, daily_max, booked_count)`. Locked in checkout transaction (arch §4). For 24 SKUs / 1 fulfiller, may collapse to a global daily slot table — defer the decision until usage shows contention. |
| **Cart** | guest-cookie token; nullable `customer_id`; `expires_at`. |
| **LineItem** | belongs_to Cart **and** Order (two FKs, not polymorphic). `customizations` jsonb validated against Product schema. `fulfillment_progress` jsonb tracks per-step checkboxes for the workbench. |
| **Order** | human-readable `number` (`PG-2026-000123`). AASM lifecycle from arch §4. Address fields snapshotted as jsonb to survive customer edits. PaperTrail. |
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

---

## Phase 1 — "Look like the old site, take a PIX order" (~3 weeks)

End state: Vinicius places a PIX test order on the new app and sees it in his admin queue.

**Bootstrap**
```
rails new prisma_games \
  --database=postgresql --css=tailwind --javascript=importmap \
  --skip-jbuilder --asset-pipeline=propshaft
```
- `Procfile.dev`: `web` (puma) + `css` (tailwindcss --watch) + `jobs` (`bin/jobs` for Solid Queue). Run via `bin/dev`.
- `.tool-versions`, `.editorconfig`, `.rubocop.yml` (omakase), `.env.example` checked in.
- Initial gems beyond defaults: `aasm`, `friendly_id`, `paper_trail`, `pundit`, `meta-tags`, `sitemap_generator`, `brazilian-documents`, `image_processing`, `rack-attack`, plus dev/test (`factory_bot_rails`, `faker`, `vcr`, `webmock`).
- Test framework: **stick with Rails 8 default Minitest** for the learning angle. Re-evaluate at Phase 2 boundary if integration test ergonomics push toward RSpec.

**HTML/CSS clone (parallel track)**
1. `wget --mirror --no-parent --convert-links --page-requisites https://www.prismagames.com.br/` into `tmp/legacy_clone/` (gitignored). Save view-source for homepage, category, PDP into `doc/legacy_html/` so the snapshots survive.
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
- Order state machine (AASM, arch §4 lifecycle) + capacity-booking transaction inside checkout.
- Transactional emails in pt-BR via **Postmark** or **Resend** (decide week 1): order placed, PIX QR + copy-paste, payment confirmed, payment failed.
- Minimal `/admin`: order list with filters, single-order page, manual `mark_as_paid`/`mark_in_production`/`mark_shipped` buttons (kanban comes Phase 2).

**Webhooks in dev**: ngrok with persistent subdomain documented in `.env.example`.

---

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

---

## Phase 3 — "Customers come back" (~2 weeks)

End state: existing customers can log in, see their orders, see in-progress photos.

- Customer accounts via Rails 8 native authentication (`bin/rails generate authentication`). No Devise.
- Order history page; in-progress orders show progress photos uploaded by Vinicius.
- Abandoned-PIX-cart recovery email (Solid Queue cron, 1h/24h after PIX expiry).
- Discount codes (simple `Coupon` model: code, percent_off or amount_off_cents, max_uses, expires_at).
- Refunds + cancellation flow: PIX refund through Mercado Pago API; cancellation only allowed before `in_production` per arch §0.1.
- SEO: sitemap.xml, JSON-LD on PDPs (Product + Offer + BreadcrumbList), Search Console verification, robots.txt.
- LGPD: privacy policy page (pt-BR), cookie consent banner, data-export rake task (`rake lgpd:export[email]`), data-deletion rake task.
- Reclame Aqui link in footer (per arch §0.2).

---

## Phase 4 — "Polish for cutover" (~1–2 weeks)

End state: app is deployable, observable, and ready for Vinicius to flip DNS when he says go.

- **Kamal deploy to Hetzner**: Postgres co-located on the same VPS; nightly `pg_dump` to R2 with bucket versioning; test restore documented in `doc/restore_drill.md`.
- **Cloudflare** in front of R2 + the app; Let's Encrypt via Kamal proxy.
- **Sentry** + **Better Stack** (logs + uptime).
- **WebP/AVIF** variants via `image_processing`; `loading="lazy"` below the fold; explicit width/height (CLS).
- **Boleto via Mercado Pago** if Vinicius wants it (high abandonment ~70% — confirm desire before building).
- Staging env on a second Hetzner box (or same box, separate `prisma_games_staging` deploy) for Vinicius to walk through.
- DNS cutover playbook handed to Vinicius — leave the actual flip to him.

---

## Decisions to lock in week 1

| Decision | Recommendation | Why |
|---|---|---|
| Payment gateway | **Mercado Pago** | Best PIX UX in BR, native parcelamento sem juros, antifraud included, brand customers already trust |
| NF-e provider | **NFe.io** | Cleaner REST API than eNotas; pay-per-issue pricing fits 24-SKU volume; not an ERP like Bling |
| VPS provider | **Hetzner Falkenstein** | Best price/perf; ~200–250ms BR latency is acceptable. Migrate to Magalu Cloud later if latency hurts conversion |
| Postgres | **Co-located on the VPS** for all 4 phases | Daily pg_dump → R2 covers 99% of risk; managed Postgres is a future migration |
| Background jobs | **Solid Queue** | Rails 8 default; Postgres-backed; no Redis to operate |
| Admin auth | **Rails 8 native authentication generator** | No Devise; less ceremony |
| Frontend JS | **Importmap + Stimulus + Turbo** (no bundler) | Aligns with arch §0 boring-stack principle |
| Test framework | **Minitest** (Rails 8 default) | Learning angle; revisit at Phase 2 if integration tests get awkward |
| Email provider | **Postmark** or **Resend** | Both work from BR; pick one week 1 and stop deciding |

---

## Open items / needs from Vinicius

These don't block kicking off Phase 1 but block portions of Phase 1–2:

- **CNPJ status** — required for Mercado Pago merchant account, NFe.io account, Melhor Envio account. Confirm he has one and apps are submitted (approvals can take 1–2 weeks).
- **NCM codes** for each cartridge type — wrong NCM = NF-e fines. Lock with Vinicius's accountant before Phase 2.
- **Brand assets** — logo source files, brand fonts, color tokens. Otherwise we lift from current site (visual only, not files he doesn't own).
- **Per-product customization schemas** — Vinicius needs to enumerate ROM choices, shell colors, label art rules per cartridge. Use a shared spreadsheet → seed file.
- **Mercado Pago + NFe.io + Melhor Envio sandbox credentials** — needed by end of Phase 1 dev.
- **Maximum installments policy** — 6x or 12x sem juros? Who eats the fee?
- **Boleto: yes or no?** — Phase 4 flag.

---

## Critical files to create

- `/home/ericktmr/Code/prisma_games/` — Rails app root
- `app/models/product.rb` — customization_schema declaration, lead_time_days, FriendlyId, PaperTrail, pg_search hooks
- `app/models/order.rb` — AASM lifecycle, transactional capacity booking (arch §4 snippet)
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
- `doc/legacy_html/` — frozen HTML snapshots from prismagames.com.br
- `doc/restore_drill.md` — backup/restore playbook (Phase 4)

---

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
- `kamal deploy` from clean checkout deploys to Hetzner staging in <5 min
- Restore the latest pg_dump into a fresh DB and the staging app boots
- Sentry captures a deliberately-thrown error in staging
- Cloudflare serves WebP for product images on a mobile UA
- PageSpeed Insights ≥90 mobile on PDP

---

## What's deferred / cut

**Cut entirely**: multi-warehouse, ML recs, ML fraud, A/B framework, GraphQL, mobile app, subscription billing, wholesale/B2B tier, loyalty/referrals, Meilisearch (`pg_search` is enough at 24 SKUs; defer even that until catalog grows past ~200).

**Deferred past Phase 4**: real-time inventory races (24 SKUs + 1 fulfiller — capacity contention is rare), 2FA on admin, reviews/ratings (Reclame Aqui covers this), faceted search SEO, dashboards beyond a simple "orders this week" view.
