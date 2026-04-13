#!/usr/bin/env bash
# expo-ship: preflight.sh
# Pre-flight checklist before building any Expo app for TestFlight.
# Sources ship.config.sh from the current directory for app-specific values.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

fail() { echo -e "  ${RED}❌ $1${NC}"; FAILURES=$((FAILURES + 1)); }

FAILURES=0

# ─── Load config ─────────────────────────────────────────────────────────────
load_config

echo ""
echo -e "${BOLD}🛫  ${APP_NAME:-App} Pre-flight Checks${NC}"
echo -e "    Verifying everything is ready before building..."

# ─── 0. Config Placeholders ───────────────────────────────────────────────────
header "Config Validation"

if [ "${APP_NAME:-}" = "MyApp" ]; then
  fail "APP_NAME is still the default — edit ship.config.sh"
  fix "set APP_NAME to your app's display name"
else
  pass "APP_NAME = $APP_NAME"
fi

if [ "${EXPECTED_API_URL:-}" = "https://api.myapp.com" ]; then
  fail "EXPECTED_API_URL is still the placeholder — edit ship.config.sh"
  fix "set EXPECTED_API_URL to your production API URL"
elif [ -n "${EXPECTED_API_URL:-}" ]; then
  pass "EXPECTED_API_URL = $EXPECTED_API_URL"
fi

if [ "${SMOKE_TEST_URL:-}" = "https://api.myapp.com/health" ]; then
  fail "SMOKE_TEST_URL is still the placeholder — edit ship.config.sh"
  fix "set SMOKE_TEST_URL to your health endpoint, or \"\" to skip"
fi

# ─── 1. Tool Versions ─────────────────────────────────────────────────────────
header "Tools"

if ! command -v node &>/dev/null; then
  fail "Node.js not found"
  fix "install from https://nodejs.org (v18 or later)"
else
  NODE_VER=$(node --version)
  NODE_MAJOR=$(echo "$NODE_VER" | sed 's/v//' | cut -d. -f1)
  if [ "$NODE_MAJOR" -lt 18 ]; then
    fail "Node.js $NODE_VER is too old (need v18+)"
    fix "nvm install 20 && nvm use 20"
  else
    pass "Node.js $NODE_VER"
  fi
fi

if ! npx eas --version &>/dev/null 2>&1; then
  fail "EAS CLI not available"
  fix "npm install -g eas-cli"
else
  EAS_VER=$(npx eas --version 2>/dev/null | head -1 || echo "unknown")
  pass "EAS CLI $EAS_VER"
fi

if ! xcode-select -p &>/dev/null 2>&1; then
  fail "Xcode CLI tools not installed"
  fix "xcode-select --install"
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
  fix "git stash  (or: git add -A && git commit -m 'wip')"
  git status --short | head -10 | sed 's/^/        /'
fi

# ─── 3. Environment Variables ─────────────────────────────────────────────────
header "Environment Variables (eas.json → ${BUILD_PROFILE:-preview})"

PROFILE="${BUILD_PROFILE:-preview}"

# Pass profile and key as argv to avoid shell interpolation inside Python code.
get_eas_env() {
  python3 - "$PROFILE" "$1" <<'PYEOF' 2>/dev/null
import json, sys
profile, key = sys.argv[1], sys.argv[2]
with open('eas.json') as f:
    data = json.load(f)
val = data.get('build', {}).get(profile, {}).get('env', {}).get(key, '')
print(val)
PYEOF
}

if [ ! -f "eas.json" ]; then
  fail "eas.json not found in $(pwd)"
  fix "npx eas build:configure"
else
  for VAR in "${REQUIRED_ENV_VARS[@]:-}"; do
    VALUE=$(get_eas_env "$VAR")
    if [ -z "$VALUE" ]; then
      fail "$VAR is missing from eas.json build.$PROFILE.env"
      fix "add \"$VAR\": \"<value>\" to eas.json build.$PROFILE.env"
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
      fail "EXPO_PUBLIC_API_URL points to localhost — production builds need the real URL"
      fix "change EXPO_PUBLIC_API_URL in eas.json build.$PROFILE.env to $EXPECTED_API_URL"
    elif [ "$ACTUAL_API_URL" != "$EXPECTED_API_URL" ]; then
      warn "EXPO_PUBLIC_API_URL = '$ACTUAL_API_URL' (expected '$EXPECTED_API_URL')"
    fi
  fi

  # Clerk production key check
  if [ "${CHECK_CLERK_KEY:-false}" = "true" ]; then
    CLERK_KEY=$(get_eas_env "EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY")
    if [[ "$CLERK_KEY" == pk_test_* ]]; then
      fail "Clerk key is a TEST key (pk_test_) — TestFlight builds require the live key"
      fix "replace EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY in eas.json with your pk_live_ key"
      fix "find it at: clerk.com/dashboard → API Keys → Production"
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
  fail "TypeScript errors — fix these before building"
  fix "npm run typecheck  (full output below)"
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
    fail "Tests failed"
    fix "$API_TEST_CMD  (full output below)"
    echo "$TEST_OUT" | grep -E "FAIL|Error|expected" | head -15 | sed 's/^/        /'
  fi
fi

# ─── 6. iOS Directory ─────────────────────────────────────────────────────────
header "iOS Build Setup"

if [ ! -d "ios" ]; then
  fail "ios/ directory missing"
  fix "npx expo prebuild --platform ios"
else
  pass "ios/ directory exists"
fi

XCWORKSPACE=$(ls ios/*.xcworkspace 2>/dev/null | head -1 || echo "")
if [ -n "$XCWORKSPACE" ]; then
  pass "Xcode workspace: $(basename "$XCWORKSPACE")"
else
  warn "No .xcworkspace in ios/ — CocoaPods may not have run"
  fix "cd ios && pod install"
fi

if git ls-files --error-unmatch ios/Podfile.lock &>/dev/null 2>&1; then
  pass "ios/Podfile.lock is committed"
elif git check-ignore -q ios/Podfile.lock 2>/dev/null || git check-ignore -q ios/ 2>/dev/null; then
  pass "ios/ is gitignored (EAS manages native build — expected)"
else
  warn "ios/Podfile.lock is not committed — dependency drift risk"
  fix "git add ios/Podfile.lock && git commit -m 'chore: lock CocoaPods'"
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
