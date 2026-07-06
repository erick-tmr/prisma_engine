# Cloudflare launch cutover

Putting `prismagames.com.br` behind Cloudflare and pointing the apex at our VPS,
while the old meloja site stays live until we flip. Companion to `docs/deployment.md`
(the VPS + Kamal runbook). The UI walkthrough for the one-time Cloudflare setup lives
in the chat handover; this file is the go-live checklist.

## Key facts

- Registrar / DNS root: **registro.br**.
- Current live apex (meloja, on AWS): `54.84.55.102`. This is the rollback target.
- Our VPS (Hostinger, Sao Paulo): the IP in `config/deploy.yml` (`187.127.38.87` at time
  of writing). Confirm before cutover.
- TLS today: kamal-proxy issues Let's Encrypt via HTTP-01. That does **not** survive
  behind the Cloudflare proxy (Cloudflare owns :80/:443), so we move to a Cloudflare
  Origin CA certificate on the VPS with SSL mode Full (Strict). See prerequisites.
- Health endpoint: `GET /up` returns 200 when the app is healthy.

## Prerequisites (all green before Monday)

Do these during the week so Monday is only a DNS flip, never a build-out.

- [x] **Zone added to Cloudflare** and nameservers switched at registro.br to the two
      Cloudflare NS (`bingo`/`jeremy.ns.cloudflare.com`); dashboard reads **Active** (done
      2026-07-05). Every record mirrored as DNS-only (grey), so meloja keeps serving.
- [x] **DNSSEC handled.** The parent `.br` publishes no DS record, so DNSSEC is not active
      on the delegation; the NS switch was safe (done 2026-07-05).
- [x] **All DNS records verified** against the old registro.br zone (11 records: apex `A`,
      `www`, `devblog`/`redirect`/google-verify CNAMEs, brevo1/2 DKIM, SPF/DMARC/brevo-code
      TXT; no MX). All grey. The three custom CNAMEs the auto-import missed were added by hand.
- [ ] **Origin cert installed** and kamal-proxy serving it (no more Let's Encrypt); edge
      SSL mode **Full (Strict)**. Full steps in "TLS: Cloudflare Origin certificate" below.
- [ ] **Staging validated behind the proxy.** `beta.prismagames.com.br` points at the VPS
      IP, **proxied (orange)**, and the full storefront works over it: home, catalog,
      product page, cart, `/checkout`, login/signup, and `/up`. This exercises the exact
      Cloudflare path the apex will use on Monday. No mixed-content or CSP errors in the
      browser console.
- [ ] **TTL lowered.** The apex `A` and `www` records are set to a low TTL (60s, or "Auto"
      which is 300s when proxied) at least a day ahead, so the flip and any rollback
      propagate fast.
- [ ] **App host config right.** `APP_HOST=prismagames.com.br` in `config/deploy.yml`,
      `config.force_ssl = true` and `config.assume_ssl = true` in production, deployed.

## TLS: Cloudflare Origin certificate

kamal-proxy issued Let's Encrypt via HTTP-01, which cannot renew once 80/443 is locked to
Cloudflare IPs (the origin-lock below). So the origin serves a **Cloudflare Origin CA cert**
(15-year, trusted only by Cloudflare) and the edge runs **Full (Strict)**. No ACME, no
port-80 challenge. `config/deploy.yml` already references the cert via `proxy.ssl`
(`certificate_pem` / `private_key_pem`), resolved from `.kamal/secrets`.

1. **Generate the cert** (Cloudflare dashboard → SSL/TLS → Origin Server → Create
   Certificate): let Cloudflare generate the private key; hostnames `prismagames.com.br`
   and `*.prismagames.com.br`; 15-year validity. Copy the **certificate** and the
   **private key** (the key is shown only once).

2. **Store in Bitwarden**, base64-encoded so the multi-line PEM survives Dotenv parsing.
   Save each to a file, then add two hidden custom fields on the `prisma-engine-prod` item:

   ```bash
   base64 -w0 origin-cert.pem   # -> paste as field  CF_ORIGIN_CERT_B64
   base64 -w0 origin-key.pem    # -> paste as field  CF_ORIGIN_KEY_B64
   # macOS: base64 -i origin-cert.pem | tr -d '\n'
   ```

   `.kamal/secrets` fetches both and base64-decodes them into `CLOUDFLARE_ORIGIN_CERT` /
   `CLOUDFLARE_ORIGIN_KEY`. Delete the local `.pem` files afterward.

3. **Set the edge mode** (Cloudflare → SSL/TLS → Overview): **Full (Strict)**. Under Edge
   Certificates: Always Use HTTPS on, Minimum TLS 1.2. Leave Cloudflare HSTS off (Rails
   `force_ssl` already sends it).

4. **Deploy:** `kamal deploy`. kamal-proxy now serves the Origin cert. Verify against the
   `beta` staging host (below) before Monday. Kamal connects over SSH (port 22), so this
   works regardless of the origin-lock.

## Origin-lock (firewall_edge)

Lock published 80/443 to Cloudflare IP ranges so the origin can't be reached directly
(bypassing the WAF/rate-limit). The role is written: `infra/ansible/roles/firewall_cloudflare_lock`.

```bash
cd infra/ansible
source ../bin/infra-env
ansible-playbook -i inventory/production.yml site.yml --tags firewall_edge --check --diff  # preview
ansible-playbook -i inventory/production.yml site.yml --tags firewall_edge                  # apply
```

Apply it **after** the Origin-cert deploy (step 4 above), then re-test the `beta` host
through Cloudflare to confirm the proxied path still reaches the origin while direct hits
to the IP are dropped.

## Monday cutover

1. **Confirm the VPS is healthy on its own.** From your machine:
   `curl -I --resolve prismagames.com.br:443:<VPS_IP> https://prismagames.com.br/up`
   Expect `200`. This hits the VPS directly (bypassing DNS) so we know the origin is good
   before any traffic moves.

2. **Flip the apex and www in Cloudflare DNS.**
   - Edit the apex `A` record: value -> `<VPS_IP>`, and click the cloud to **orange
     (Proxied)**.
   - Edit `www`: point at the VPS (A -> `<VPS_IP>`, or CNAME -> `prismagames.com.br`),
     also **orange**.
   Save. With the low TTL, resolvers pick this up within a minute or two.

3. **Verify end to end** (see Verification below). If anything is wrong, roll back
   immediately (see Rollback) rather than debugging under load.

4. **Enable Always Use HTTPS** (Cloudflare SSL/TLS -> Edge Certificates) if not already on,
   so any `http://` hit is upgraded at the edge.

5. **Announce launch** once verification passes.

## Verification (run right after the flip)

- [ ] `curl -I https://prismagames.com.br/up` returns `200` and the response carries a
      `cf-ray` header (proof it came through Cloudflare, not straight from AWS/meloja).
- [ ] Home page loads over `https://prismagames.com.br` with a valid certificate and no
      browser warning.
- [ ] `http://prismagames.com.br` redirects to `https://`.
- [ ] `www.prismagames.com.br` resolves and lands on the site (redirect to apex is fine).
- [ ] Full path once through: browse catalog, open a product, add to cart, reach
      `/checkout`, and complete a signup or login. No CSP or mixed-content errors in the
      console (images must load from the R2 public host).
- [ ] A test signup delivers its confirmation email (proves the email TXT records survived
      the nameserver move).
- [ ] Product images render (R2 public host reachable, `img-src` CSP satisfied).

## Rollback (any check fails)

The flip is a single DNS change, so rollback is too:

1. In Cloudflare DNS, set the apex `A` back to `54.84.55.102` and `www` back to its old
   meloja value, both **grey (DNS-only)**. Low TTL means meloja is serving again within
   minutes.
2. Confirm `curl -I https://prismagames.com.br/up` (or the meloja home page) reflects the
   old site.
3. Diagnose the VPS/Cloudflare issue off the live path (re-run the staging validation on
   `beta`), fix, and reschedule the flip.

Nothing about the rollback touches nameservers or the registrar, so it is fast and low
risk.

## Post-launch (same day or next)

- [ ] Watch production logs for a spike in 5xx or cert errors (`deploy/fetch-production-logs.sh`).
- [ ] Confirm HSTS is being served (Rails `force_ssl` sends it). Do not also enable
      Cloudflare HSTS with preload until the site has run clean for a while; preload is hard
      to undo.
- [ ] Turn on a Cloudflare managed WAF ruleset and review Security Events for false
      positives against real checkout/login traffic.
- [ ] Once the cutover is proven stable, remove the temporary `beta` staging record.
- [ ] Update `config/deploy.yml` to drop the old sslip.io test host comment now that the
      real domain is live.
