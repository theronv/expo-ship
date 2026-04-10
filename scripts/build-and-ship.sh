#!/usr/bin/env bash
# expo-ship: build-and-ship.sh
# Builds an Expo app locally and submits the .ipa to TestFlight.
# Sources ship.config.sh for build profile, submit profile, and checklist.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

header() {
  echo ""
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE}  $1${NC}"
  echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════${NC}"
}

# ─── Load config ─────────────────────────────────────────────────────────────
CONFIG="$(pwd)/ship.config.sh"
if [ ! -f "$CONFIG" ]; then
  echo -e "${RED}❌ ship.config.sh not found in $(pwd)${NC}"
  exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG"

BUILD_PROFILE="${BUILD_PROFILE:-preview}"
SUBMIT_PROFILE="${SUBMIT_PROFILE:-production}"
APP_LABEL="${APP_NAME:-App}"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BUILD_DIR="./build-output"
IPA_PATH="$BUILD_DIR/${APP_LABEL// /-}-$TIMESTAMP.ipa"

mkdir -p "$BUILD_DIR"

# ─── Build ────────────────────────────────────────────────────────────────────
header "Step 1 of 2 — Building .ipa (local)"

echo ""
echo -e "  App     : ${BLUE}$APP_LABEL${NC}"
echo -e "  Profile : ${BLUE}$BUILD_PROFILE${NC} (TestFlight distribution)"
echo -e "  Output  : ${BLUE}$IPA_PATH${NC}"
echo -e "  Build # : ${YELLOW}auto-incremented by EAS (appVersionSource: remote)${NC}"
echo ""
echo -e "  ${YELLOW}This takes 20–40 minutes. Go get a coffee. ☕${NC}"
echo ""

npx eas build \
  --profile "$BUILD_PROFILE" \
  --platform ios \
  --local \
  --output "$IPA_PATH"

if [ ! -f "$IPA_PATH" ]; then
  echo ""
  echo -e "${RED}${BOLD}❌ Build finished but .ipa not found at $IPA_PATH${NC}"
  echo -e "${YELLOW}Check the EAS build output above for the actual file path.${NC}"
  exit 1
fi

IPA_SIZE=$(du -sh "$IPA_PATH" | cut -f1)
echo ""
echo -e "${GREEN}${BOLD}  ✅  Build complete! ($IPA_SIZE)${NC}"

# ─── Submit ───────────────────────────────────────────────────────────────────
header "Step 2 of 2 — Submitting to TestFlight"

echo ""
echo -e "  Submit profile : $SUBMIT_PROFILE"
echo -e "  File           : $IPA_PATH"
echo ""
echo -e "  ${BLUE}Uploading to Apple... (usually 2–5 minutes)${NC}"
echo ""

npx eas submit \
  --platform ios \
  --path "$IPA_PATH" \
  --profile "$SUBMIT_PROFILE"

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

echo -e "  Build artifact: $IPA_PATH"
echo ""
