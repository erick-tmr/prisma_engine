#!/usr/bin/env bash
#
# Read-only snapshot of the Cloudflare account and zone behind prismagames.com.br.
# Every call is a GET: the script creates, changes and deletes nothing. It exists so
# "treat Cloudflare config as code" has a mechanism, and so docs/cloudflare/inventory.md
# can be re-derived instead of remembered.
#
# Usage:
#   export CF_API_TOKEN=...            # read-only token, see below
#   deploy/cf-inventory.sh             # writes JSON per resource under $OUT
#
# Env:
#   CF_API_TOKEN   required. Cloudflare API token.
#   ZONE_NAME      zone to inventory (default prismagames.com.br)
#   ACCOUNT_ID     pin the account when the token can see more than one
#   OUT            output directory (default ./tmp/cf-inventory)
#
# Token: dashboard -> My Profile -> API Tokens -> Create Token -> Custom. All rows Read:
#   Account: Account Settings, Workers R2 Storage, Notifications, Billing
#   Zone:    Zone, DNS, Zone Settings, Zone WAF, Page Rules, SSL and Certificates,
#            Single Redirect, Firewall Services
# Scope it to the one account and set a short TTL, then delete it when done. Bot
# Management returns an error on Free zones no matter what the token holds; Bot Fight
# Mode is readable in the dashboard under Security -> Bots.
#
set -uo pipefail

: "${CF_API_TOKEN:?export CF_API_TOKEN with a read-only Cloudflare API token}"
ZONE_NAME="${ZONE_NAME:-prismagames.com.br}"
OUT="${OUT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/tmp/cf-inventory}"
API="https://api.cloudflare.com/client/v4"

mkdir -p "$OUT"

get() {
  local path="$1" name="$2" body
  body="$(curl -sS -X GET "${API}${path}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" 2>&1)"
  if printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$body" | jq . > "${OUT}/${name}.json"
    if printf '%s' "$body" | jq -e '.success == false' >/dev/null 2>&1; then
      printf '  %-46s DENIED  %s\n' "$name" \
        "$(printf '%s' "$body" | jq -rc '[.errors[]?.message] | join("; ")')"
    else
      printf '  %-46s ok\n' "$name"
    fi
  else
    printf '%s' "$body" > "${OUT}/${name}.txt"
    printf '  %-46s NON-JSON (see %s.txt)\n' "$name" "$name"
  fi
}

echo "==> Identity and accounts"
get "/user/tokens/verify" "token-verify"
get "/accounts"           "accounts"

echo "    accounts visible to this token:"
jq -r '.result[]? | "      \(.id)  \(.name)"' "${OUT}/accounts.json"

ACCOUNT_ID="${ACCOUNT_ID:-$(jq -r '.result[0].id // empty' "${OUT}/accounts.json")}"
if [ -z "$ACCOUNT_ID" ]; then
  echo "!! no account id readable; the token needs Account Settings:Read" >&2
  exit 1
fi
if [ "$(jq -r '.result | length' "${OUT}/accounts.json")" -gt 1 ]; then
  echo "!! token sees more than one account; using the first. Pin it with ACCOUNT_ID=<id>."
fi
echo "    using account_id = ${ACCOUNT_ID}"

echo "==> Account"
get "/accounts/${ACCOUNT_ID}/members"              "account-members"
get "/accounts/${ACCOUNT_ID}/subscriptions"        "account-subscriptions"
get "/accounts/${ACCOUNT_ID}/alerting/v3/policies" "notification-policies"
get "/accounts/${ACCOUNT_ID}/workers/scripts"      "workers-scripts"
get "/accounts/${ACCOUNT_ID}/cfd_tunnel"           "tunnels"
get "/accounts/${ACCOUNT_ID}/pages/projects"       "pages-projects"

echo "==> R2"
get "/accounts/${ACCOUNT_ID}/r2/buckets" "r2-buckets"
for bucket in $(jq -r '.result.buckets[]?.name // empty' "${OUT}/r2-buckets.json"); do
  echo "    bucket: ${bucket}"
  get "/accounts/${ACCOUNT_ID}/r2/buckets/${bucket}"                 "r2-${bucket}-info"
  get "/accounts/${ACCOUNT_ID}/r2/buckets/${bucket}/lifecycle"       "r2-${bucket}-lifecycle"
  get "/accounts/${ACCOUNT_ID}/r2/buckets/${bucket}/cors"            "r2-${bucket}-cors"
  get "/accounts/${ACCOUNT_ID}/r2/buckets/${bucket}/lock"            "r2-${bucket}-lock"
  get "/accounts/${ACCOUNT_ID}/r2/buckets/${bucket}/domains/custom"  "r2-${bucket}-domain-custom"
  get "/accounts/${ACCOUNT_ID}/r2/buckets/${bucket}/domains/managed" "r2-${bucket}-domain-managed"
done

echo "==> Zone"
get "/zones?per_page=50" "zones"
ZONE_ID="$(jq -r --arg n "$ZONE_NAME" '.result[]? | select(.name == $n) | .id' "${OUT}/zones.json" | head -1)"
if [ -z "$ZONE_ID" ]; then
  echo "!! zone ${ZONE_NAME} not visible to this token" >&2
  exit 1
fi
echo "    zone_id = ${ZONE_ID} (${ZONE_NAME})"

get "/zones/${ZONE_ID}"                                  "zone-detail"
get "/zones/${ZONE_ID}/settings"                         "zone-settings"
get "/zones/${ZONE_ID}/settings/image_resizing"          "setting-image-resizing"
get "/zones/${ZONE_ID}/dns_records?per_page=500"         "dns-records"
get "/zones/${ZONE_ID}/pagerules"                        "page-rules"
get "/zones/${ZONE_ID}/bot_management"                   "bot-management"
get "/zones/${ZONE_ID}/firewall/access_rules/rules"      "ip-access-rules"
get "/zones/${ZONE_ID}/workers/routes"                   "worker-routes"
get "/zones/${ZONE_ID}/email/routing"                    "email-routing"
get "/zones/${ZONE_ID}/ssl/universal/settings"           "ssl-universal"
get "/zones/${ZONE_ID}/ssl/certificate_packs?status=all" "ssl-certificate-packs"
get "/zones/${ZONE_ID}/origin_tls_client_auth/settings"  "ssl-authenticated-origin-pulls"

echo "==> Rulesets"
get "/zones/${ZONE_ID}/rulesets" "zone-rulesets"
for rs in $(jq -r '.result[]?.id // empty' "${OUT}/zone-rulesets.json"); do
  phase="$(jq -r --arg id "$rs" '.result[] | select(.id == $id) | .phase' "${OUT}/zone-rulesets.json")"
  get "/zones/${ZONE_ID}/rulesets/${rs}" "ruleset-${phase}-${rs}"
done

echo
echo "==> Highlights"
printf '  %-24s %s\n' "plan" "$(jq -r '.result.plan.name' "${OUT}/zone-detail.json")"
printf '  %-24s %s\n' "nameservers" "$(jq -r '.result.name_servers | join(", ")' "${OUT}/zone-detail.json")"
printf '  %-24s %s\n' "ssl mode" "$(jq -r '.result[] | select(.id=="ssl") | .value' "${OUT}/zone-settings.json")"
printf '  %-24s %s\n' "transformations" "$(jq -r '.result.value // "unreadable"' "${OUT}/setting-image-resizing.json")"
printf '  %-24s %s\n' "bot fight mode" "$(jq -r '.result.fight_mode // "unreadable"' "${OUT}/bot-management.json")"
printf '  %-24s %s\n' "dns records" "$(jq -r '.result | length' "${OUT}/dns-records.json")"
echo "  redirect rules:"
for f in "${OUT}"/ruleset-http_request_dynamic_redirect-*.json; do
  [ -e "$f" ] || continue
  jq -r '.result.rules[]? | "    \(.description)  ->  \(.action)"' "$f"
done

echo
echo "==> Written to ${OUT}"
