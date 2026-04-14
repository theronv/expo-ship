#!/usr/bin/env bash
# expo-ship: build-and-ship.sh
# Builds an Expo app locally and submits the .ipa to TestFlight.
# Sources ship.config.sh for build profile, submit profile, and checklist.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

fail() { echo -e "  ${RED}❌ $1${NC}"; exit 1; }

big_header() {
  echo ""
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  $1${NC}"
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════${NC}"
}

# ─── Load config ─────────────────────────────────────────────────────────────
load_config

BUILD_PROFILE="${BUILD_PROFILE:-preview}"
SUBMIT_PROFILE="${SUBMIT_PROFILE:-production}"
APP_LABEL="${APP_NAME:-App}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BUILD_DIR="./build-output"
IPA_PATH="$BUILD_DIR/${APP_LABEL// /-}-$TIMESTAMP.ipa"

mkdir -p "$BUILD_DIR"

# ─── Build ────────────────────────────────────────────────────────────────────
big_header "Step 1 of 2 — Building .ipa (local)"

echo ""
echo -e "  App     : ${BLUE}$APP_LABEL${NC}"
echo -e "  Profile : ${BLUE}$BUILD_PROFILE${NC} (TestFlight distribution)"
echo -e "  Output  : ${BLUE}$IPA_PATH${NC}"
echo -e "  Build # : ${YELLOW}auto-incremented by EAS (appVersionSource: remote)${NC}"
echo ""
echo -e "  ${YELLOW}This takes 20–40 minutes. Go get a coffee. ☕${NC}"
echo ""

# Disable errexit for the build step: eas-cli-local-build-plugin sometimes
# exits non-zero during temp-dir cleanup (ENOTEMPTY on .git) even when the
# .ipa was produced successfully. The IPA existence check below is the
# authoritative success signal.
set +e
npx eas build \
  --profile "$BUILD_PROFILE" \
  --platform ios \
  --local \
  --output "$IPA_PATH"
set -e

if [ ! -f "$IPA_PATH" ]; then
  echo ""
  echo -e "${RED}${BOLD}❌ Build failed — .ipa not found at $IPA_PATH${NC}"
  echo -e "${YELLOW}Check the EAS build output above for details.${NC}"
  exit 1
fi

IPA_SIZE=$(du -sh "$IPA_PATH" | cut -f1)
echo ""
echo -e "${GREEN}${BOLD}  ✅  Build complete! ($IPA_SIZE)${NC}"

# ─── Submit ───────────────────────────────────────────────────────────────────
big_header "Step 2 of 2 — Submitting to TestFlight"

# Validate required submit config
if [ -z "${APPLE_ID:-}" ]; then
  fail "APPLE_ID is not set in ship.config.sh"
fi
if [ -z "${KEYCHAIN_ITEM:-}" ]; then
  fail "KEYCHAIN_ITEM is not set in ship.config.sh
       Store your app-specific password first:
         xcrun altool --store-password-in-keychain-item \"${KEYCHAIN_ITEM:-altool}\" \\
           --username \"${APPLE_ID:-your@apple.id}\" --password \"xxxx-xxxx-xxxx-xxxx\""
fi

# Verify the keychain item exists before attempting upload
if ! security find-generic-password -a "$APPLE_ID" -s "$KEYCHAIN_ITEM" &>/dev/null; then
  fail "Keychain item \"$KEYCHAIN_ITEM\" not found for $APPLE_ID
       Store your app-specific password first:
         xcrun altool --store-password-in-keychain-item \"$KEYCHAIN_ITEM\" \\
           --username \"$APPLE_ID\" --password \"xxxx-xxxx-xxxx-xxxx\""
fi

echo ""
echo -e "  Apple ID : ${BLUE}$APPLE_ID${NC}"
echo -e "  File     : ${BLUE}$IPA_PATH${NC}"
echo ""
echo -e "  ${BLUE}Uploading directly to Apple (no cloud queue)...${NC}"
echo ""

ALTOOL_OUT=$(mktemp)
xcrun altool --upload-app \
  --type ios \
  --file "$IPA_PATH" \
  --username "$APPLE_ID" \
  --password "@keychain:$KEYCHAIN_ITEM" \
  --output-format xml > "$ALTOOL_OUT" 2>&1
ALTOOL_EXIT=$?

# Print output, suppressing blank lines
grep -v "^$" "$ALTOOL_OUT" || true

if [ $ALTOOL_EXIT -ne 0 ]; then
  rm -f "$ALTOOL_OUT"
  fail "altool upload failed — see errors above."
fi
rm -f "$ALTOOL_OUT"

# ─── Build log ────────────────────────────────────────────────────────────────
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
APP_VERSION=$(python3 -c "
import json, sys
try:
    with open('app.json') as f:
        d = json.load(f)
    print(d.get('expo', d).get('version', 'unknown'))
except Exception:
    print('unknown')
" 2>/dev/null || echo "unknown")

LOG_LINE="$(date '+%Y-%m-%d %H:%M:%S')  ${APP_LABEL}  v${APP_VERSION}  git:${GIT_SHA}  profile:${BUILD_PROFILE}  ipa:$(basename "$IPA_PATH")"
echo "$LOG_LINE" >> "$BUILD_DIR/builds.log"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  🎉  $APP_LABEL shipped to TestFlight!${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}What happens next:${NC}"
echo -e "  1. Apple processes the build (~15 min)"
echo -e "  2. Open TestFlight on your iPhone and update"
echo ""

if [ ${#POST_BUILD_CHECKLIST[@]:-0} -gt 0 ]; then
  echo -e "  ${BOLD}Post-build checklist:${NC}"
  for item in "${POST_BUILD_CHECKLIST[@]}"; do
    echo -e "  ${YELLOW}□${NC} $item"
  done
  echo ""
fi

echo -e "  Build artifact : $IPA_PATH"
echo -e "  Build history  : $BUILD_DIR/builds.log"
echo ""
