# Cloudflare inventory

The shape of the Cloudflare account and zone that serve `prismagames.com.br`, captured
**2026-08-16** with `deploy/cf-inventory.sh`. This is the snapshot `docs/architecture.md`
asks for: a rebuild reference that does not depend on anyone remembering which toggles
were flipped.

**This repository is public, so this file is deliberately partial.** It records what a
rebuild needs and what is observable from outside anyway. The full capture, including the
security posture and every identifier, is written by the script to `tmp/cf-inventory/`,
which is gitignored. Read that for detail; keep it out of git.

In particular, do not add to this file: a list of which protections are **not** enabled,
account or zone identifiers, member e-mail addresses, or the timing of any window during
which the origin or the edge behaves differently from normal. Each of those is more useful
to an attacker than to a rebuilder.

Refresh with:

```bash
export CF_API_TOKEN=...        # read-only, see the header of deploy/cf-inventory.sh
deploy/cf-inventory.sh         # writes tmp/cf-inventory/*.json
```

## Account

One account, one member with the Super Administrator role. Free zone plan plus usage
billed R2, currently at no cost. No Workers, Pages projects, named tunnels or Email
Routing. It also holds unrelated personal zones and buckets that this project never
touches.

The account id lives in `config.x.r2_endpoint` in `config/environments/*.rb`, where it
forms the R2 S3 endpoint. It is not repeated here.

`bin/share-dev` uses an anonymous `cloudflared` quick tunnel (`*.trycloudflare.com`), so
it is **not** an account resource and there is no named tunnel to maintain.

## R2

All three buckets are **ENAM** (Eastern North America), Standard class. R2 offers no South
America location, and for production it does not matter because Cloudflare caches at the
edge in front of the bucket.

| Bucket | Purpose | Public access | Lifecycle |
|---|---|---|---|
| `prisma-games-prod` | Active Storage, production | custom domain `cdn.prismagames.com.br`, min TLS 1.2; `r2.dev` disabled so all traffic passes the cache and WAF | default multipart abort only |
| `prisma-games-dev` | Active Storage, development | `r2.dev` subdomain | default multipart abort only |
| `prisma-engine-backups` | Postgres dumps | none | `postgres/daily/` deleted after 21 days · `postgres/weekly/` after 70 days |

The "Default Multipart Abort Rule" (abort incomplete multipart uploads after 7 days) is
created automatically by R2 on every bucket. It is not ours and needs no replication.

**No CORS policy is set on any bucket, and none is needed.** Nothing in the app uses
Active Storage direct uploads (uploads go browser to Rails to the S3 API), images load
through plain `<img>`, and fonts are self hosted under the `:self` CSP. A cross-origin XHR
or an `@font-face` served from the bucket would change that.

Three separate API tokens exist, each scoped to a single bucket with Object Read and
Write: the development and production Active Storage tokens (Rails credentials, default
and production vaults) and the backup token used by `rclone` on the VPS (Bitwarden).
Keeping the backup token unable to touch catalog images is deliberate, and so is keeping
the app's tokens unable to delete backups.

## Zone `prismagames.com.br`

Free plan, active since 2026-07-05, delegated from **registro.br** to a Cloudflare
nameserver pair. Not a Cloudflare registrar zone.

### DNS records

Eleven records. Values are all publicly resolvable, so the table lists what each record is
**for** rather than restating opaque tokens; take actual values from a zone export when
rebuilding.

| Type | Name | Points at | Proxied |
|---|---|---|---|
| A | `@` | the VPS (`config/deploy.yml`) | yes |
| CNAME | `www` | the apex | yes |
| CNAME | `cdn` | the R2 custom domain binding | yes |
| CNAME | `devblog` | Blogger | no |
| CNAME | *(opaque label)* | Google Search Console verification | no |
| CNAME | `brevo1._domainkey` | Brevo DKIM | no |
| CNAME | `brevo2._domainkey` | Brevo DKIM | no |
| TXT | `@` | SPF, `include:spf.brevo.com` | – |
| TXT | `@` | Brevo domain verification | – |
| TXT | `@` | Meta domain verification | – |
| TXT | `_dmarc` | DMARC, currently `p=none`, reporting to Brevo | – |

The `cdn` CNAME is created by R2 when the custom domain is bound, not by hand. There are
no MX records: mail is outbound only, through Brevo. **Five of the eleven belong to
Brevo**, which couples this zone to the e-mail provider (see `account-migration.md`).

### Redirect rule (the only rule we wrote)

A single redirect sends `https://www.*` to the apex with a 301, preserving the query
string.

This is edge-level defence in depth, not the only guard: `Middleware::CanonicalHost`
performs the same 301 at the origin (inserted at position 0 in
`config/environments/production.rb`). The `www` CNAME points at the apex but a CNAME is
not a redirect, so without one of the two, `www` and the apex are separate origins with
separate cookie jars and customers arriving from e-mail links land logged out. Losing the
Cloudflare rule alone therefore costs a round trip to the origin rather than correctness,
but recreate it anyway: it is the cheap half.

### Settings a rebuild has to match

Everything below is observable from outside with a TLS handshake or a request, so listing
it costs nothing and getting it wrong is expensive.

| Setting | Value |
|---|---|
| SSL mode | Full (Strict) |
| Always Use HTTPS | on |
| Minimum TLS | 1.2 |
| Cloudflare HSTS | off (Rails `force_ssl` sends the header) |
| Transformations (`image_resizing`) | **on** |
| Bot Fight Mode | on |
| Managed WAF, Cloudflare free ruleset | on |
| Brotli, HTTP/2, HTTP/3, TLS 1.3 | on |

Cache tuning, security level and the remaining toggles are in the gitignored capture.

Transformations being on is a hard dependency: `Storefront::CdnImage` rewrites every image
URL to `https://cdn.prismagames.com.br/cdn-cgi/image/...`. With it off, the
`onerror=redirect` option keeps images visible by falling back to the original object, so
nothing 404s, but every page ships full size images. The Free plan allows 5,000 unique
transformations per month, counted **per account**, which is the reason for the account
migration in the first place.

### TLS certificates

Universal SSL is enabled: an active pack plus a backup pack, both covering the apex and
`*.prismagames.com.br`, 90 day validity, renewed by Cloudflare.

The origin serves a separate **Cloudflare Origin CA certificate** (15 year, generated in
the dashboard, stored base64 encoded in Bitwarden as `CF_ORIGIN_CERT_B64` and
`CF_ORIGIN_KEY_B64`, read through `.kamal/secrets`). It is not listed by the API token
used here, since Origin CA certificates need the Origin CA Key instead. Certificates do
**not** transfer between accounts: a rebuild issues a fresh one.

### Notifications

Two policies, both e-mailing the account owner: the Transformations free-quota warning
(auto created when Transformations was enabled) and a budget alert. A rebuild must point
them at whoever actually owns the account, or nobody hears about a quota or billing event.

## Rebuilding

`docs/architecture.md` once described a `cdn.` cache rule, a per-IP rate limit, hotlink
protection and a CORS policy as though they were configured. They were proposals. When
rebuilding, take the live capture as truth rather than any prose, including this file:
run `deploy/cf-inventory.sh` against the account and diff. Hardening that is worth adding
is tracked outside this repository.
