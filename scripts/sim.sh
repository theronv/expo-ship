#!/usr/bin/env bash
# expo-ship: sim.sh
# Build and run the app in the iOS Simulator.
# Use this to verify your changes work before committing to a TestFlight build.
#
# What it does:
#   1. TypeScript check (fail fast before a multi-minute compile)
#   2. npx expo run:ios  →  compiles native code + launches simulator
#
# Usage:
#   make sim                         # default simulator (last used)
#   make sim DEVICE="iPhone 16 Pro"  # specific device

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
source "$SCRIPT_DIR/_common.sh"

fail() { echo -e "  ${RED}❌ $1${NC}"; exit 1; }

# ─── Load config ─────────────────────────────────────────────────────────────
load_config

# Optional: device passed as env var (from Makefile: make sim DEVICE="iPhone 16 Pro")
SIMULATOR_DEVICE="${DEVICE:-}"

echo ""
echo -e "${BOLD}📱  ${APP_NAME:-App} — Simulator Build${NC}"
echo -e "    Compile + launch in iOS Simulator"
if [ -n "$SIMULATOR_DEVICE" ]; then
  echo -e "    Device: ${BLUE}$SIMULATOR_DEVICE${NC}"
fi

# ─── 1. TypeScript ────────────────────────────────────────────────────────────
header "TypeScript"

info "Running tsc --noEmit (fail fast before native compile)..."
if TS_OUT=$(npm run typecheck 2>&1); then
  pass "No type errors"
else
  echo ""
  echo -e "${RED}${BOLD}❌ TypeScript errors — fix these before building:${NC}"
  echo "$TS_OUT" | grep -E "error TS|\.tsx?:" | head -20 | sed 's/^/   /'
  echo ""
  echo -e "${YELLOW}Run 'npm run typecheck' for the full list.${NC}"
  exit 1
fi

# ─── 2. Simulator Build ───────────────────────────────────────────────────────
header "Building for Simulator"

echo ""

if [ -n "$SIMULATOR_DEVICE" ]; then
  info "Running: npx expo run:ios --device \"$SIMULATOR_DEVICE\""
  echo ""
  npx expo run:ios --device "$SIMULATOR_DEVICE"
else
  info "Running: npx expo run:ios"
  echo -e "  ${YELLOW}Tip: specify a device with: make sim DEVICE=\"iPhone 16 Pro\"${NC}"
  echo ""
  npx expo run:ios
fi
