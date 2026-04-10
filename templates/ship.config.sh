#!/usr/bin/env bash
# ship.config.sh — per-app config for expo-ship
#
# Copy this file to your app root and fill in the values.
# Run `~/expo-ship/init.sh` to do this automatically.
#
# All values below are required unless marked OPTIONAL.

# ─── App ─────────────────────────────────────────────────────────────────────

APP_NAME="MyApp"

# ─── EAS ─────────────────────────────────────────────────────────────────────

# EAS build profile (from eas.json) to use for TestFlight builds
BUILD_PROFILE="preview"

# EAS submit profile (from eas.json) to use for App Store submission
SUBMIT_PROFILE="production"

# ─── Env Var Checks ───────────────────────────────────────────────────────────

# List every env var that must be present in eas.json build.$BUILD_PROFILE.env.
# The preflight will fail if any are missing or empty.
REQUIRED_ENV_VARS=(
  "EXPO_PUBLIC_API_URL"
  "EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY"
  "EXPO_PUBLIC_EAS_PROJECT_ID"
  "EXPO_PUBLIC_SENTRY_DSN"
)

# The value EXPO_PUBLIC_API_URL must have in eas.json (prevents shipping with localhost).
# Set to "" to skip this check.
EXPECTED_API_URL="https://api.myapp.com"

# Set to true if this app uses Clerk and the publishable key must be pk_live_ (not pk_test_).
CHECK_CLERK_KEY=true

# ─── Smoke Tests ──────────────────────────────────────────────────────────────

# Full URL to your production health endpoint. Set to "" to skip smoke tests.
# Must return HTTP 200 with JSON body containing "status": "ok".
SMOKE_TEST_URL="https://api.myapp.com/health"

# ─── API Unit Tests ───────────────────────────────────────────────────────────

# Shell command (run from project root) to execute your API's test suite.
# Set to "" to skip.
# Examples:
#   API_TEST_CMD="cd api && npm test"
#   API_TEST_CMD="npm run test:api"
#   API_TEST_CMD=""   # no API tests
API_TEST_CMD="cd api && npm test"

# ─── Post-Build Checklist ─────────────────────────────────────────────────────

# Shown after a successful TestFlight submission as a reminder of what to verify.
# Add/remove items as appropriate for your app.
POST_BUILD_CHECKLIST=(
  "Sign in with your test account"
  "Core user flow (create / view / edit)"
  "Sign out and sign back in"
)
