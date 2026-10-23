#!/usr/bin/env bash
# Smoke test: use the API the way a real user does, through the public address.
# Creates a throwaway Cognito user, signs in, saves an item, reads it back, and
# deletes the user. Exits non-zero on the first failed check.
#
# Required env: API_URL, USER_POOL_ID, CLIENT_ID (AWS credentials come from the environment)
set -euo pipefail

: "${API_URL:?set API_URL}"
: "${USER_POOL_ID:?set USER_POOL_ID}"
: "${CLIENT_ID:?set CLIENT_ID}"
REGION="${AWS_REGION:-us-east-1}"

USERNAME="smoke-$(date +%s)@example.com"
PASSWORD="$(openssl rand -base64 24)Aa1!"
ITEM_ID="smoke-$(date +%s)"
BODY_FILE="$(mktemp)"

cleanup() {
  aws cognito-idp admin-delete-user --region "$REGION" \
    --user-pool-id "$USER_POOL_ID" --username "$USERNAME" >/dev/null 2>&1 || true
  rm -f "$BODY_FILE"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

status_of() { curl -s -o "$BODY_FILE" -w '%{http_code}' "$@"; }

echo "1. Without a token the API must refuse (expect 401)"
# CloudFront can take a few minutes to start answering after a first deploy.
code=000
for _ in $(seq 1 20); do
  code="$(status_of "$API_URL/items?id=x" || true)"
  [ "$code" = "401" ] && break
  sleep 15
done
[ "$code" = "401" ] || fail "expected 401 without token, got $code"

echo "2. Create a temporary user and sign in"
aws cognito-idp admin-create-user --region "$REGION" \
  --user-pool-id "$USER_POOL_ID" --username "$USERNAME" \
  --message-action SUPPRESS \
  --user-attributes Name=email,Value="$USERNAME" Name=email_verified,Value=true >/dev/null
aws cognito-idp admin-set-user-password --region "$REGION" \
  --user-pool-id "$USER_POOL_ID" --username "$USERNAME" \
  --password "$PASSWORD" --permanent
TOKEN="$(aws cognito-idp admin-initiate-auth --region "$REGION" \
  --user-pool-id "$USER_POOL_ID" --client-id "$CLIENT_ID" \
  --auth-flow ADMIN_USER_PASSWORD_AUTH \
  --auth-parameters "USERNAME=$USERNAME,PASSWORD=$PASSWORD" \
  --query 'AuthenticationResult.IdToken' --output text)"
[ -n "$TOKEN" ] && [ "$TOKEN" != "None" ] || fail "could not get a token"

echo "3. POST saves an item (expect 200)"
code="$(status_of -X POST "$API_URL/items" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d "{\"id\":\"$ITEM_ID\",\"note\":\"smoke test\"}")"
[ "$code" = "200" ] || fail "POST returned $code: $(cat "$BODY_FILE")"

echo "4. GET reads the same item back (expect 200 and our id)"
code="$(status_of "$API_URL/items?id=$ITEM_ID" -H "Authorization: Bearer $TOKEN")"
[ "$code" = "200" ] || fail "GET returned $code: $(cat "$BODY_FILE")"
grep -q "\"$ITEM_ID\"" "$BODY_FILE" || fail "GET body did not contain $ITEM_ID: $(cat "$BODY_FILE")"

# 5. The WAF rate limit. Skipped when the front door is off (direct API Gateway URL),
# because WAF only sits in front of CloudFront.
case "$API_URL" in
  *execute-api*)
    echo "5. Skipped: no front door, so no WAF rate limit to test"
    ;;
  *)
    echo "5. WAF rate limit: over 1000 requests in 5 minutes from one IP must be blocked (expect 403)"
    # Send a burst of 1500 requests, 40 at a time, and ignore the answers.
    seq 1 1500 | xargs -P 40 -I{} curl -s -o /dev/null "$API_URL/items?id=x" || true
    # WAF counts requests in the background, so blocking starts a little later.
    # Keep probing for up to four minutes until the first 403 appears.
    code=000
    for _ in $(seq 1 24); do
      code="$(status_of "$API_URL/items?id=x" || true)"
      [ "$code" = "403" ] && break
      sleep 10
    done
    [ "$code" = "403" ] || fail "WAF did not block after 1500 requests, last status $code"
    ;;
esac

echo "Smoke test passed."
