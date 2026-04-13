#!/usr/bin/env bash
# expo-ship: test.sh
# Runs the API unit test suite defined by API_TEST_CMD in ship.config.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

fail() { echo -e "  ${RED}❌ $1${NC}"; exit 1; }

# ─── Load config ─────────────────────────────────────────────────────────────
load_config

if [ -z "${API_TEST_CMD:-}" ]; then
  echo -e "${YELLOW}⚠️  API_TEST_CMD not set in ship.config.sh — no tests configured${NC}"
  echo -e "   Set API_TEST_CMD in ship.config.sh or set to \"\" to silence this message"
  exit 0
fi

echo ""
echo -e "${BOLD}🧪  ${APP_NAME:-App} API Tests${NC}"
echo -e "    Running: ${BLUE}$API_TEST_CMD${NC}"

if [ -f "api/package.json" ] && [ ! -d "api/node_modules" ]; then
  warn "api/node_modules not found — running npm install in api/"
  (cd api && npm install --silent)
fi

echo ""
eval "$API_TEST_CMD"
