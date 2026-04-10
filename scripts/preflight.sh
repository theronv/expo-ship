#!/usr/bin/env bash
# expo-ship: preflight.sh
# Pre-flight checklist before building any Expo app for TestFlight.
# Sources ship.config.sh from the current directory for app-specific values.

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

FAILURES=0

pass()   { echo -e "  ${GREEN}✅ $1${NC}"; }
fail()   { echo -e "  ${RED}❌ $1${NC}"; FAILURES=$((FAILURES + 1)); }
warn()   { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
info()   { echo -e "  ${BLUE}→  $1${NC}"; }
header() { echo -e "\n${BOLD}${BLUE}── $1 ──────────────────────────────────────────────${NC}"; }

# ─── Load config ─────────────────────────────────────────────────────────────
CONFIG="$(pwd)/ship.config.sh"
if [ ! -f "$CONFIG" ]; then
  echo -e "${RED}❌ ship.config.sh not found in $(pwd)${NC}"
  echo -e "   Run: ~/expo-ship/init.sh to set up this project"
  exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG"

echo ""
echo -e "${BOLD}🛫  ${APP_NAME:-App} Pre-flight Checks${NC}"
echo -e "    Verifying everything is ready before building..."

# ─── 1. Tool Versions ─────────────────────────────────────────────────────────
header "Tools"

if ! command -v node &>/dev/null; then
  fail "Node.js not found — install from https://nodejs.org"
else
  NODE_VER=$(node --version)
  NODE_MAJOR=$(echo "$NODE_VER" | sed 's/v//' | cut -d. -f1)
  if [ "$NODE_MAJOR" -lt 18 ]; then
    fail "Node.js $NODE_VER is too old (need v18+)"
  else
    pass "Node.js $NODE_VER"
  fi
fi

if ! npx eas --version &>/dev/null 2>&1; then
  fail "EAS CLI not available — run: npm install -g eas-cli"
else
  EAS_VER=$(npx eas --version 2>/dev/null | head -1 || echo "unknown")
  pass "EAS CLI $EAS_VER"
fi

if ! xcode-select -p &>/dev/null 2>&1; then
  fail "Xcode CLI tools not installed — run: xcode-select --install"
else
  pass "Xcode CLI tools: $(xcode-select -p)"
fi

# ─── 2. Git State ─────────────────────────────────────────────────────────────
header "Git State"

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  pass "On $CURRENT_BRANCH branch"
else
  warn "On branch '$CURRENT_BRANCH' — builds should ship from main/master"
fi

if git diff-index --quiet HEAD -- 2>/dev/null; then
  pass "Working tree is clean"
else
  fail "Uncommitted changes — commit or stash before building"
  git status --short | head -10 | sed 's/^/        /'
fi

# ─── 3. Environment Variables ─────────────────────────────────────────────────
header "Environment Variables (eas.json → ${BUILD_PROFILE:-preview})"

PROFILE="${BUILD_PROFILE:-preview}"

get_eas_env() {
  python3 -c "
import json, sys
with open('eas.json') as f:
    data = json.load(f)
val = data.get('build', {}).get('$PROFILE', {}).get('env', {}).get('$1', '')
print(val)
" 2>/dev/null
}

if [ ! -f "eas.json" ]; then
  fail "eas.json not found in $(pwd)"
else
  for VAR in "${REQUIRED_ENV_VARS[@]:-}"; do
    VALUE=$(get_eas_env "$VAR")
    if [ -z "$VALUE" ]; then
      fail "$VAR is missing from eas.json build.$PROFILE.env"
    else
      if [[ "$VAR" == *"KEY"* ]] || [[ "$VAR" == *"DSN"* ]] || [[ "$VAR" == *"SECRET"* ]]; then
        DISPLAY="${VALUE:0:16}..."
      else
        DISPLAY="$VALUE"
      fi
      pass "$VAR = $DISPLAY"
    fi
  done

  # Check API URL is not localhost
  if [ -n "${EXPECTED_API_URL:-}" ]; then
    ACTUAL_API_URL=$(get_eas_env "EXPO_PUBLIC_API_URL")
    if [ "$ACTUAL_API_URL" = "http://localhost:3000" ] || [[ "$ACTUAL_API_URL" == *"localhost"* ]]; then
      fail "EXPO_PUBLIC_API_URL points to localhost — change to $EXPECTED_API_URL"
    elif [ "$ACTUAL_API_URL" != "$EXPECTED_API_URL" ]; then
      warn "EXPO_PUBLIC_API_URL = '$ACTUAL_API_URL' (expected '$EXPECTED_API_URL')"
    fi
  fi

  # Clerk production key check
  if [ "${CHECK_CLERK_KEY:-false}" = "true" ]; then
    CLERK_KEY=$(get_eas_env "EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY")
    if [[ "$CLERK_KEY" == pk_test_* ]]; then
      fail "Clerk key is a TEST key (pk_test_) — use the production key (pk_live_) for TestFlight"
    elif [[ "$CLERK_KEY" == pk_live_* ]]; then
      pass "Clerk key is production (pk_live_)"
    fi
  fi
fi

# ─── 4. App TypeScript ────────────────────────────────────────────────────────
header "App TypeScript"

info "Running tsc --noEmit..."
if TS_OUT=$(npm run typecheck 2>&1); then
  pass "No type errors"
else
  fail "TypeScript errors — run 'npm run typecheck' to see full output"
  echo "$TS_OUT" | grep -E "error TS|\.tsx?:" | head -10 | sed 's/^/        /'
fi

# ─── 5. API Unit Tests ────────────────────────────────────────────────────────
if [ -n "${API_TEST_CMD:-}" ]; then
  header "API Unit Tests"

  if [ -f "api/package.json" ] && [ ! -d "api/node_modules" ]; then
    warn "api/node_modules not found — running npm install in api/"
    (cd api && npm install --silent)
  fi

  info "Running: $API_TEST_CMD"
  if TEST_OUT=$(eval "$API_TEST_CMD" 2>&1); then
    SUMMARY=$(echo "$TEST_OUT" | grep -E "Tests.*passed|Tests.*failed" | tail -1 || echo "")
    if [ -n "$SUMMARY" ]; then
      pass "$SUMMARY"
    else
      pass "All tests passed"
    fi
  else
    fail "Tests failed — run '$API_TEST_CMD' to see details"
    echo "$TEST_OUT" | grep -E "FAIL|Error|expected" | head -15 | sed 's/^/        /'
  fi
fi

# ─── 6. iOS Directory ─────────────────────────────────────────────────────────
header "iOS Build Setup"

if [ ! -d "ios" ]; then
  fail "ios/ directory missing — run 'npx expo prebuild --platform ios'"
else
  pass "ios/ directory exists"
fi

XCWORKSPACE=$(ls ios/*.xcworkspace 2>/dev/null | head -1 || echo "")
if [ -n "$XCWORKSPACE" ]; then
  pass "Xcode workspace: $(basename "$XCWORKSPACE")"
else
  warn "No .xcworkspace in ios/ — CocoaPods may not have run"
fi

if git ls-files --error-unmatch ios/Podfile.lock &>/dev/null 2>&1; then
  pass "ios/Podfile.lock is committed"
else
  warn "ios/Podfile.lock is not committed — dependency drift risk"
fi

# ─── Result ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}──────────────────────────────────────────────────────${NC}"
if [ "$FAILURES" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}  ✅  All pre-flight checks passed. Safe to build.${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}  ❌  $FAILURES check(s) failed. Fix issues above before building.${NC}"
  exit 1
fi
