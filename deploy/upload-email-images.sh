#!/usr/bin/env bash
set -Eeuo pipefail

# Upload the static email brand images (dragon art + Prisma Games logo) to the
# production R2 bucket (prisma-games-prod) under the emails/ prefix, so the
# transactional emails load them from Cloudflare's CDN instead of the app host
# (which is mid-migration and not reachable at APP_HOST yet). Idempotent: R2
# overwrites the same keys, so re-run whenever the art changes.
#
# Runs entirely locally over the S3 API (no SSH). Reads a Cloudflare R2 API token
# from .env: PROD_R2_ACCESS_KEY_ID + PROD_R2_SECRET_ACCESS_KEY (scoped to the prod
# bucket, Object Read & Write) plus PROD_R2_ENDPOINT, which carries the Cloudflare
# account id of whichever account holds prisma-games-prod. The dragon art under
# public/images/emails/ is
# gitignored (served from R2, never from the repo), so it must be present in THIS
# local checkout for the upload to read. dotenv loads .env at boot, so
# `rails runner` sees the vars; the prod bucket + creds are passed explicitly, so
# the development Rails env this boots under is irrelevant. Runbook lives next to
# the other one-off prod scripts in deploy/.

cd "$(dirname "$0")/.."

exec bin/rails runner '
  client = Emails::AssetUploader.r2_client(
    access_key_id: ENV.fetch("PROD_R2_ACCESS_KEY_ID"),
    secret_access_key: ENV.fetch("PROD_R2_SECRET_ACCESS_KEY"),
    endpoint: ENV.fetch("PROD_R2_ENDPOINT")
  )
  keys = Emails::AssetUploader.new(client: client, bucket: "prisma-games-prod").call
  puts "uploaded #{keys.join(%q(, ))} -> prisma-games-prod"
'
