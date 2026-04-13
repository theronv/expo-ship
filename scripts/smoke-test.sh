#!/usr/bin/env bash
# expo-ship: smoke-test.sh
# Verifies the production API is healthy before shipping a build.
# Sources ship.config.sh for SMOKE_TEST_URL.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

fail() { echo -e "  ${RED}❌ $1${NC}"; FAILURES=$((FAILURES + 1)); }

FAILURES=0

# ─── Load config ─────────────────────────────────────────────────────────────
load_config

# Skip if not configured
if [ -z "${SMOKE_TEST_URL:-}" ]; then
  echo -e "${YELLOW}⚠️  SMOKE_TEST_URL not set in ship.config.sh — skipping smoke tests${NC}"
  exit 0
fi

echo ""
echo -e "${BOLD}🔍  ${APP_NAME:-App} API Smoke Tests${NC}"
echo -e "    Verifying production API at ${BLUE}$SMOKE_TEST_URL${NC}"

# ─── Health check ─────────────────────────────────────────────────────────────
header "Health Endpoint"

info "GET $SMOKE_TEST_URL"

CURL_OUT=$(curl -s \
  -w "\n---STATUS:%{http_code}---TIME:%{time_total}" \
  --max-time 15 \
  "$SMOKE_TEST_URL" 2>/dev/null) || {
  fail "Could not reach $SMOKE_TEST_URL — check internet connection or service status"
  echo ""
  echo -e "${RED}${BOLD}  ❌  Smoke tests failed — API is unreachable.${NC}"
  exit 1
}

HTTP_BODY=$(echo "$CURL_OUT" | grep -v "^---STATUS:")
HTTP_CODE=$(echo "$CURL_OUT" | grep -o "STATUS:[0-9]*" | cut -d: -f2)
TIME_TOTAL=$(echo "$CURL_OUT" | grep -o "TIME:[0-9.]*" | cut -d: -f2)

if [ "$HTTP_CODE" = "200" ]; then
  pass "HTTP $HTTP_CODE OK"
else
  fail "HTTP $HTTP_CODE (expected 200) — API may be down or misconfigured"
  echo "        Response: $HTTP_BODY"
fi

# Expect JSON with "status": "ok"
if echo "$HTTP_BODY" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    assert data.get('status') == 'ok', f'Expected status=ok, got: {data.get(\"status\")}'
    sys.exit(0)
except AssertionError as e:
    print(str(e), file=sys.stderr); sys.exit(1)
except json.JSONDecodeError as e:
    print(f'Not valid JSON: {e}', file=sys.stderr); sys.exit(1)
" 2>/tmp/expo_ship_smoke_err; then
  pass "Response JSON: {status: ok, ...}"
else
  fail "Response JSON malformed — $(cat /tmp/expo_ship_smoke_err)"
  echo "        Raw response: $HTTP_BODY"
fi

# Response time
TIME_MS=$(python3 -c "print(round(float('$TIME_TOTAL') * 1000))" 2>/dev/null || echo "?")
if python3 -c "exit(0 if float('$TIME_TOTAL') < 10 else 1)" 2>/dev/null; then
  if python3 -c "exit(0 if float('$TIME_TOTAL') < 3 else 1)" 2>/dev/null; then
    pass "Response time: ${TIME_MS}ms"
  else
    warn "Slow response: ${TIME_MS}ms (cold start?) — continuing"
  fi
else
  fail "Response time: ${TIME_MS}ms — exceeded 10s threshold"
fi

# ─── Headers ─────────────────────────────────────────────────────────────────
header "Response Headers"

HEADERS=$(curl -s -I --max-time 10 "$SMOKE_TEST_URL" 2>/dev/null || echo "")
if echo "$HEADERS" | grep -qi "content-type:.*json"; then
  pass "Content-Type: application/json"
else
  warn "Content-Type is not application/json (may be OK depending on your framework)"
fi

# ─── Result ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}──────────────────────────────────────────────────────${NC}"
if [ "$FAILURES" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}  ✅  Smoke tests passed. Production API is healthy.${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}  ❌  $FAILURES smoke test(s) failed. Fix the API before shipping.${NC}"
  exit 1
fi
