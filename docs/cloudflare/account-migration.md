# Moving Cloudflare to the client's account

Prisma Games' Cloudflare resources currently live in a developer's personal account. They
belong to the owner of the business. This is the runbook for moving them. Current state of
everything being moved: `inventory.md`.

The Brevo account moves too. The two are coupled through this zone (five of the eleven
DNS records are Brevo's), so the ordering between them matters and is covered below.

## What kind of move this is

**Per resource, not an account handover.** Every Prisma resource is recreated in the
destination account and the source copies are retired afterwards.

Cloudflare does support the opposite approach (add the client as a second Super
Administrator, remove yourself, and the account changes hands with nothing moving and no
downtime at all). It was considered and rejected: the R2 free allowance and the
Transformations quota are **per account**, so the store would keep sharing them with
unrelated personal projects, which is the reason for the migration in the first place.
The client also already has his own accounts. Recorded here so the cheaper-looking option
is not rediscovered and re-proposed later.

Two ordering constraints fall out of that, and they drive the whole plan:

1. **An R2 custom domain requires the zone to be in the same account as the bucket.**
   `cdn.prismagames.com.br` cannot be bound in the destination account until the zone
   itself is there. The bucket can exist and hold data before that; it just cannot serve.
2. **The zone move changes the nameservers**, which means a registro.br change and a
   propagation window. Everything else should be finished and verified before that
   window opens.

## Stage 1: R2 (safe, no user impact, do it any time)

Nothing here touches live traffic. The production bucket in the destination account is
dark until stage 2 binds the custom domain.

**State as of 2026-08-16:** buckets created (all ENAM, lifecycle rules and the 14 day
lock on backups), development fully cut over, and the production bucket copied and
hash-verified (70 objects, 34.463 MiB) but **not** switched. Backups were deliberately
left for after the migration. What remains for production is the switch itself, in the
stage 2 window.

1. Create three buckets in the destination account: `prisma-games-prod`,
   `prisma-games-dev`, `prisma-engine-backups`. All **ENAM**, Standard class, no
   jurisdiction. Names stay identical, because they are committed in
   `config/environments/{development,production}.rb`.
2. `prisma-games-dev`: enable the `r2.dev` subdomain, record the new `pub-*.r2.dev` host.
3. `prisma-games-prod` and `prisma-engine-backups`: leave all public access off.
4. `prisma-engine-backups`: recreate the two lifecycle rules (`postgres/daily/` delete
   after 21 days, `postgres/weekly/` delete after 70 days), and add a **bucket lock**
   with 14 day retention, so recent dumps cannot be deleted even by a holder of the backup
   token. Keep lock retention at or below the lifecycle delete age or locked objects can
   never be reclaimed.
5. Mint three API tokens, each scoped to a single bucket with Object Read and Write:
   Active Storage dev, Active Storage production, and backups. Never one token for all
   three: the VPS backup token must not be able to reach catalog images.
6. Copy the data with `rclone` between two R2 remotes (no egress charge on either side).
   `--metadata` is required: `config/storage.yml` stamps
   `Cache-Control: public, max-age=31536000, immutable` on upload and a copy without that
   flag silently drops it. Verify with `rclone check --one-way`, which must report zero
   differences. One remote per (account, bucket) pair, since the tokens are bucket scoped.
7. Do **not** update production credentials or `config.x.r2_endpoint` yet. Production
   keeps writing to the source account until stage 2, because its public URLs resolve
   through `cdn.`, which is still bound to the source bucket. Flipping early means new
   uploads land somewhere `cdn.` cannot read and 404 for everyone.
8. The rclone config ends up holding several live R2 key pairs in plaintext. Keep it
   `0600` and delete the migration remotes once stage 2 is verified.

## Stage 2: the zone

### How the move actually works

The domain is added to the destination account **while it is still active in the source
account**, so there is no interval where the zone exists nowhere. The destination zone
sits `Pending` until Cloudflare sees the nameservers pointing at the new pair, then flips
to `Active`. The source zone becomes `Moved away`, and on a Free plan is deleted seven
days later. That seven day tail is the rollback window.

### Why the `Pending` interval matters

While a zone is `Pending` it cannot proxy: Cloudflare answers with the origin address
directly. For a typical site that is only a loss of edge caching. This origin does not
serve traffic that arrives outside the proxy, by design and in more than one layer, so
for us the interval is a real gap rather than a degradation.

The response is to keep it short and to take it behind a maintenance page, **not** to
weaken the origin so it can serve strangers for a few minutes. Lowering those defences on
a schedule trades a brief planned gap for a window of genuine exposure, which is a bad
trade even when nobody is watching.

Two things do shrink the gap, and neither touches the origin's posture:

**Take the deploy off the critical path.** Public image reads never touch the S3 API:
`Storefront::ImageSource` builds `#{public_host}/#{key}`, so the storefront only needs
`cdn.` to resolve. Credentials and the endpoint matter only for **writes**. Freeze
backoffice uploads for the window and the app can be deployed before or after it without
affecting what customers see.

**Have an image fallback ready but unused.** An R2 custom domain only works proxied, so
images are the one thing still dark while `Pending`. Keep a ready-to-deploy commit that
points `config.x.r2_public_host` at the destination bucket's `r2.dev` URL and sets
`config.x.cdn_image_transforms = false` (the transform path would otherwise build
`cdn-cgi/image` URLs against a host that has no such route). Ship it only if activation
drags; images come back full size and uncached, which beats absent.

Beyond that, keep `Pending` short: flip at a quiet hour and drive activation with
Cloudflare's re-check button rather than waiting for it.

### Pre-flight (days before, nothing user visible)

- [ ] Confirm working registro.br credentials. The delegation lives there, and it is the
      one step nobody else can do.
- [ ] Confirm DNSSEC is still inactive: the `.br` parent publishes no DS record for this
      domain, so there is nothing to disable, but re-check rather than assume.
- [ ] Lower the TTL on the apex `A` and `www` at least a day ahead.
- [ ] Export the DNS records from the source zone (BIND format) and keep the file.
- [ ] Add the domain in the destination account and import the export, **excluding the
      `cdn` record**: binding the R2 custom domain creates that record itself.
- [ ] Compare the two zones record by record against the table in `inventory.md`. Eleven
      records, and anything missing fails for whichever visitors reach the new zone first.
- [ ] Note the nameserver pair the destination account assigns. It will differ from
      `bingo`/`jeremy`.
- [ ] In the destination zone, pre-set everything from `inventory.md` that can be set
      while `Pending`: SSL mode Full (Strict), Always Use HTTPS, minimum TLS 1.2,
      Cloudflare HSTS off, Bot Fight Mode on, Transformations on, and the
      **`Redirect from WWW to root` rule**. That rule is not optional: without it `www`
      and the apex are separate cookie jars and customers arriving from e-mail links land
      logged out.
- [ ] Issue a fresh Origin CA certificate in the destination account (certificates do not
      move between accounts), store it base64 encoded in Bitwarden as
      `CF_ORIGIN_CERT_B64` / `CF_ORIGIN_KEY_B64`, and **deploy it before the window while
      still on the source zone**. That answers, safely and in advance, whether a
      certificate issued by one account validates at the edge for a zone in the other. If
      the site keeps serving, both directions are proven. If it does not, roll back and
      plan the swap for inside the window, where the failure would otherwise have taken
      the maintenance page down with it.
- [ ] Prepare, but do not ship, the `r2.dev` image fallback commit.
- [ ] Announce an upload freeze: no backoffice image uploads from the start of the
      window until the delta sync is done.
- [ ] Recreate both notification policies against **the new account owner's** address: the
      Transformations quota alert and the billing budget alert.

### Maintenance mode

The window is taken behind a maintenance page rather than trying to keep the storefront
serving through it. That is the safer trade: a customer who sees "voltamos já" is mildly
inconvenienced, whereas an order placed against a half-migrated backend is a mess found
days later. Set `MAINTENANCE_MODE=1` (`kamal env push` plus a restart) and the app
answers 503 with `Retry-After` everywhere except `/up` and the payment webhook.
`MAINTENANCE_ALLOW_IPS` lets the operator walk the whole site through the new path while
customers still see the page, which is what makes it possible to verify **before**
reopening.

**Background jobs keep running, deliberately.** The VPS and its database are not part of
the migration, no job writes to Active Storage (the only attachment path is
`Catalog::SaveProduct`, reached from the backoffice, which the gate closes), and pausing
would stop payment verification and tracking updates for no gain. A payment landing
mid-window reaches the webhook and confirms normally.

The one consequence to keep in mind is that anything a job emits while the `r2.dev`
fallback below is active carries `r2.dev` image URLs. For the Meta catalog that is
self-healing, since the nightly reconciliation rewrites it. For e-mail it is permanent,
because `EmailHelper#email_asset_url` bakes the host into the message body and a sent
message cannot be rewritten. At a quiet hour the volume is negligible, and it is a further
reason to keep the fallback measured in hours.

### Images during the window

`cdn.prismagames.com.br` is the one thing that cannot follow the zone instantly: an R2
custom domain only serves proxied, and binding it provisions a certificate that takes an
unpredictable few minutes. Rather than hold the store closed waiting for it, production
degrades to the bucket's own `pub-*.r2.dev` host with `config.x.cdn_image_transforms =
false`, which is independent of the zone entirely and therefore also immune to the
nameserver tail below. Images come back unoptimised and full size, which is worse than
the CDN and much better than absent. Cloudflare rate-limits `r2.dev` and does not intend
it for production traffic, so this is an hours arrangement, not a days one: rebind `cdn.`
and deploy back as soon as the certificate is active.

### The nameserver tail

The NS records carry an **86400 second TTL** and neither Cloudflare nor registro.br lets
you shorten it, so for up to 24 hours after the change some resolvers still ask the old
pair. Reports of what those resolvers get are mixed: sometimes the old zone keeps
answering with its old records, sometimes REFUSED.

The mitigation is to make both halves of the split serve the same thing, which they
naturally do if **nothing in the source account is torn down for at least 48 hours**. The
apex A record is the same VPS either way, the old zone still has the same rules, and the
old bucket still serves the old `cdn.` binding. Leave it all alone and a straggling
resolver sees a working site. Combined with the upload freeze (uploads happen roughly
monthly, around the game of the month, so this costs nothing), the two buckets stay
identical for the duration and no visitor can tell which zone answered them.

There is no mitigation for the REFUSED case. It self-heals as caches expire, and flipping
at the quietest hour is what keeps the affected population small.

### The window

0. Turn on maintenance mode and confirm the page is being served.
1. Change the nameservers at registro.br to the destination account's pair.
2. In the destination zone, use Cloudflare's re-check button immediately, and keep using
   it. Activation is what ends the outage window, so do not wait passively for it.
3. The moment the zone reads `Active`, start the `cdn.prismagames.com.br` binding against
   the destination `prisma-games-prod` bucket, minimum TLS 1.2. Do not wait on it.
4. Deploy production against the destination account: `config.x.r2_endpoint`, the
   re-encrypted Active Storage credentials, and `config.x.r2_public_host` pointed at the
   destination bucket's `pub-*.r2.dev` with `config.x.cdn_image_transforms = false`.
   Reads need only the public host, so this is what makes the store servable again
   regardless of how the certificate for `cdn.` is progressing.
5. Verify through `MAINTENANCE_ALLOW_IPS` while customers still see the page.
6. Turn maintenance mode off. The store reopens and the job queue drains whatever the
   window accumulated.
7. Once the `cdn.` certificate is active, deploy again to restore
   `config.x.r2_public_host = "https://cdn.prismagames.com.br"` and
   `cdn_image_transforms = true`. Same day, not same week: `r2.dev` is rate limited.

### Verification

- [ ] `curl -I https://prismagames.com.br/up` returns 200 with a `cf-ray` header.
- [ ] `https://www.prismagames.com.br/qualquer-coisa?a=1` 301s to the apex **with the
      query string preserved**. This is the redirect rule; test it explicitly.
- [ ] A product image loads from `cdn.prismagames.com.br` and its URL contains
      `/cdn-cgi/image/`. If the URL is right but the image is full size, Transformations
      is off in the new account.
- [ ] Log in, then follow a link from a delivered e-mail: still logged in.
- [ ] A test signup delivers its confirmation e-mail, proving the Brevo records survived.
- [ ] Backoffice image upload writes to the destination bucket and renders.
- [ ] `systemctl start prisma-pg-backup.service` on the VPS, then confirm the object
      lands in the destination backup bucket.

### Rollback

Revert the nameservers at registro.br to `bingo.ns.cloudflare.com` /
`jeremy.ns.cloudflare.com`. The source zone stays in `Moved away` for seven days and the
source bucket still holds the data, so this works for as long as that tail lasts. After
seven days there is no rollback, only a rebuild.

## Stage 3: Brevo

Move Brevo **after** the zone is `Active` in the destination account, so there is exactly
one authoritative zone to edit. Verifying the domain in a new Brevo account mints a new
`brevo-code` TXT value, and possibly new DKIM targets; doing that while the zone is
mid-move means editing records in two places and betting the export caught the change.

Outbound e-mail keeps flowing from the old Brevo account until its API key is replaced,
so this stage can be taken slowly.

## Afterwards

- Re-run the `firewall_edge` play so the origin's allowlist matches the current published
  Cloudflare ranges, and confirm the origin is serving the destination account's Origin CA
  certificate.
- Restore `config.x.r2_public_host` to `cdn.` and `cdn_image_transforms` to true if the
  `r2.dev` fallback was used. Same day: `r2.dev` is rate limited and not meant for
  production traffic.
- Delete the read-only inventory API token from the source account, and the migration
  remotes from the local rclone config.
- Re-run `deploy/cf-inventory.sh` against the destination account and update
  `inventory.md`, remembering that the file is public and partial by design.
- Retire the source buckets once the destination has been serving cleanly for a while,
  keeping the last backup copies until then.
- Revisit edge hardening separately, once the move has settled, so that any breakage has a
  single cause. Track the specifics outside this repository.
