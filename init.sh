#!/usr/bin/env bash
# expo-ship init
# Sets up an Expo app to use expo-ship.
#
# Usage:
#   ~/expo-ship/init.sh                    # run from inside your app directory
#   ~/expo-ship/init.sh /path/to/your/app  # or pass the path

set -euo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Target app directory ─────────────────────────────────────────────────────
if [ -n "${1:-}" ]; then
  APP_DIR="$1"
else
  APP_DIR="$(pwd)"
fi

if [ ! -d "$APP_DIR" ]; then
  echo "❌ Directory not found: $APP_DIR"
  exit 1
fi

if [ ! -f "$APP_DIR/app.json" ] && [ ! -f "$APP_DIR/eas.json" ]; then
  echo "❌ $APP_DIR doesn't look like an Expo project (no app.json or eas.json)"
  exit 1
fi

echo ""
echo -e "${BOLD}🚀 expo-ship init${NC}"
echo -e "   Setting up: ${BLUE}$APP_DIR${NC}"

# ─── ship.config.sh ───────────────────────────────────────────────────────────
CONFIG="$APP_DIR/ship.config.sh"
if [ -f "$CONFIG" ]; then
  echo ""
  echo -e "${YELLOW}⚠️  ship.config.sh already exists in $APP_DIR${NC}"
  echo -n "   Overwrite? [y/N] "
  read -r REPLY
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "   Keeping existing ship.config.sh"
  else
    cp "$TOOL_DIR/templates/ship.config.sh" "$CONFIG"
    echo -e "${GREEN}✅ Created ship.config.sh${NC}"
  fi
else
  cp "$TOOL_DIR/templates/ship.config.sh" "$CONFIG"
  echo -e "${GREEN}✅ Created ship.config.sh${NC}"
fi

# ─── Makefile ─────────────────────────────────────────────────────────────────
MAKEFILE="$APP_DIR/Makefile"

# Inject the actual tool path so it works without PATH magic
GENERATED_MAKEFILE="$TOOL_DIR/templates/Makefile"
FINAL_MAKEFILE=$(sed "s|EXPO_SHIP ?= \$(HOME)/expo-ship|EXPO_SHIP ?= $TOOL_DIR|g" "$GENERATED_MAKEFILE")

if [ -f "$MAKEFILE" ]; then
  echo ""
  echo -e "${YELLOW}⚠️  Makefile already exists in $APP_DIR${NC}"
  echo -n "   Overwrite? [y/N] "
  read -r REPLY
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "   Keeping existing Makefile"
  else
    echo "$FINAL_MAKEFILE" > "$MAKEFILE"
    echo -e "${GREEN}✅ Created Makefile${NC}"
  fi
else
  echo "$FINAL_MAKEFILE" > "$MAKEFILE"
  echo -e "${GREEN}✅ Created Makefile${NC}"
fi

# ─── .gitignore ───────────────────────────────────────────────────────────────
GITIGNORE="$APP_DIR/.gitignore"
if [ -f "$GITIGNORE" ] && ! grep -q "build-output" "$GITIGNORE" 2>/dev/null; then
  echo "" >> "$GITIGNORE"
  echo "# expo-ship build artifacts" >> "$GITIGNORE"
  echo "build-output/" >> "$GITIGNORE"
  echo -e "${GREEN}✅ Added build-output/ to .gitignore${NC}"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}Done!${NC} Now:"
echo ""
echo -e "  1. Edit ${BLUE}$CONFIG${NC}"
echo -e "     Fill in APP_NAME, SMOKE_TEST_URL, REQUIRED_ENV_VARS, etc."
echo ""
echo -e "  2. Run ${BLUE}make check${NC} from $APP_DIR"
echo -e "     Fix any issues it finds."
echo ""
echo -e "  3. Run ${BLUE}make build${NC} when ready to ship."
echo ""
