# Seeding catalog images

Product-catalog images are **not** committed to the repo. They exist only to bootstrap
the catalog: the seed reads them once and uploads them to Cloudflare R2 via Active
Storage, after which the storefront serves every image straight from R2
(`Product#image` returns the Active Storage URL). Keeping them in git was ~34 MB of dead
weight in every clone, so they are gitignored and kept as a local copy instead.

Once the backoffice product pages exist, new and edited products write their images
directly to R2, so nothing here needs to be committed again.

## What is gitignored

- `public/images/stores/uploads/`: the catalog product images (`<id>/conversions/large.jpg`)
- `db/seeds/hero_banner.jpg`: the homepage hero
- `db/seeds/correios_label_sample.pdf`: the demo Correios label (read by `backoffice_demo.rb`)

The seeds resolve these from their original paths; the files just aren't tracked. Every
seed that reads one is guarded with `File.exist?`, so a checkout that lacks them seeds the
catalog data without images instead of crashing (this is what a fresh teammate clone does).

## The local copy

Keep the gitignored files in this checkout under their original paths. They are not in
git, so a fresh clone starts without them. Obtain them from the team's private archive
(a tarball in R2 or Bitwarden) and unpack into the repo root, preserving paths:

```
public/images/stores/uploads/<id>/conversions/large.jpg
db/seeds/hero_banner.jpg
db/seeds/correios_label_sample.pdf
```

> Worktrees: because `public/images/stores/uploads/` is now gitignored, a `git worktree`
> won't have it. Symlink it from the main checkout the same way `storage/` is linked
> (see CLAUDE.md → Git workflow).

## Dev

With the local copy in place, the normal seed populates the dev R2 bucket
(`prisma-games-dev`):

```sh
bin/rails db:seed
```

Idempotent: Active Storage's checksum compare skips images that are already uploaded.

## Production (one-off bootstrap)

Active Storage couples the R2 blob and its `ProductPhoto` / `active_storage_*` DB rows,
so both are created in one run. We run the seed locally with `RAILS_ENV=production` so
Active Storage routes uploads to `prisma-games-prod`, pointed at the production database
through an SSH tunnel. Run it **once** to bootstrap the catalog; afterwards manage the
catalog from the backoffice.

`config/credentials/production.key` must be present locally (it decrypts the prod R2
keys), and `PRISMA_ENGINE_DATABASE_PASSWORD` + the prod VPS host must be set in `.env`
(`PRODUCTION_LOG_HOST` is reused as the host). Then:

```sh
deploy/seed-prod-catalog.sh
```

The script opens the tunnel, runs **only** `catalog.rb` + `hero_banner.rb` (never full
`db:seed`, which would also load the dev-only `backoffice_demo.rb` into production), and
tears the tunnel down on exit.

To run it by hand instead of via the script:

```sh
ssh -N -L 5433:127.0.0.1:5432 root@<vps> &
RAILS_ENV=production DATABASE_HOST=127.0.0.1 DATABASE_PORT=5433 \
  PRISMA_ENGINE_DATABASE_PASSWORD=<prod-db-password> \
  bin/rails runner 'load Rails.root.join("db/seeds/catalog.rb"); load Rails.root.join("db/seeds/hero_banner.rb")'
```

Verify: open a production product page and confirm the image loads from the prod R2 host.
Re-running is a no-op (checksum skip).
