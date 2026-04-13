#!/usr/bin/env bash
# expo-ship: _common.sh
# Shared colors, output helpers, and config loader sourced by all pipeline scripts.
# Do not execute this file directly — source it.

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Output helpers ──────────────────────────────────────────────────────────
# NOTE: fail() is intentionally omitted — preflight/smoke count failures and
# continue, while sim/build exit immediately. Each script defines its own fail().
pass()   { echo -e "  ${GREEN}✅ $1${NC}"; }
warn()   { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
info()   { echo -e "  ${BLUE}→  $1${NC}"; }
fix()    { echo -e "     ${YELLOW}fix: $1${NC}"; }
header() { echo -e "\n${BOLD}${BLUE}── $1 ──────────────────────────────────────────────${NC}"; }

# ─── Config loader ────────────────────────────────────────────────────────────
load_config() {
  local config
  config="$(pwd)/ship.config.sh"
  if [ ! -f "$config" ]; then
    echo -e "${RED}❌ ship.config.sh not found in $(pwd)${NC}"
    echo -e "   Run: ~/expo-ship/init.sh to set up this project"
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$config"
}
