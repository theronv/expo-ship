# expo-ship

A reusable build pipeline for Expo apps. One command to verify, build, and ship to TestFlight — with safety checks that prevent the most common ways builds break or ship broken.

---

## What it does

```
make sim      TypeScript check → compile → launch in iOS Simulator
make build    Pre-flight checks → smoke test → build .ipa → submit to TestFlight
make check    Pre-flight checks only (fast, ~60s, no build)
make smoke    Ping production API health endpoint
make test     Run API unit tests
make clean    Delete local build artifacts
```

Each app keeps a `ship.config.sh` with its specific values. The shared scripts in `~/expo-ship/scripts/` read that config and handle the rest.

---

## Installation

Clone this repo once. It lives at `~/expo-ship/` by default — the generated Makefiles assume this location.

```bash
git clone <this-repo> ~/expo-ship
```

---

## Adding expo-ship to an app

Run `init.sh` from anywhere, passing the path to your Expo project:

```bash
~/expo-ship/init.sh ~/path/to/your-app
```

Or run it from inside the project directory:

```bash
cd ~/path/to/your-app
~/expo-ship/init.sh
```

This creates two files in your app:

| File | Purpose |
|---|---|
| `ship.config.sh` | App-specific config — edit this |
| `Makefile` | Build commands — do not edit |

It also adds `build-output/` to `.gitignore` if not already present.

### Then edit ship.config.sh

Open `ship.config.sh` and fill in the values for your app. Every option is documented in the file. At minimum, set:

- `APP_NAME`
- `SMOKE_TEST_URL` (your production API `/health` endpoint, or `""` to skip)
- `REQUIRED_ENV_VARS` (all `EXPO_PUBLIC_` vars that must be in `eas.json`)
- `EXPECTED_API_URL` (the production API URL — prevents shipping with localhost)
- `API_TEST_CMD` (command to run your tests, or `""` to skip)

### Then verify

```bash
cd ~/path/to/your-app
make check
```

Fix anything it reports. Once all checks pass, you're ready to use the pipeline.

---

## Daily workflow

### Before building for TestFlight

Run the simulator build first. This compiles the native app and opens it in the iOS Simulator so you can verify your changes work before committing to the 30–40 minute TestFlight build.

```bash
make sim
```

Target a specific device:

```bash
make sim DEVICE="iPhone 16 Pro"
make sim DEVICE="iPhone SE (3rd generation)"
```

`make sim` will:
1. Run TypeScript (`tsc --noEmit`) — fails immediately if there are type errors, before wasting minutes on a native compile
2. Run `npx expo run:ios` — compiles and opens the simulator automatically

### Ship to TestFlight

Once the simulator build looks good:

```bash
make build
```

`make build` will:
1. **Pre-flight checks** (`make check`) — fast safety gates (~60s)
2. **Smoke test** (`make smoke`) — verify production API is up
3. **Build** — `npx eas build --profile <BUILD_PROFILE> --platform ios --local`
4. **Submit** — `npx eas submit --platform ios --path <ipa> --profile <SUBMIT_PROFILE>`

The build number is auto-incremented by EAS (`appVersionSource: remote` in `eas.json`). You do not need to bump it manually.

After submission, Apple takes ~15 minutes to process the build before it appears in TestFlight.

---

## Pre-flight checks (make check)

The preflight runs automatically as part of `make build`. You can also run it standalone at any time.

| Check | What it catches |
|---|---|
| Node.js ≥ 18 | Prevents incompatible tooling |
| EAS CLI installed | Prevents "command not found" during build |
| Xcode CLI tools | Prevents native compile failure |
| On main/master branch | Warns if shipping from a feature branch |
| Clean git tree | Prevents shipping uncommitted changes |
| All `REQUIRED_ENV_VARS` present in `eas.json` | Catches missing keys that cause silent runtime failures |
| `EXPO_PUBLIC_API_URL` is not localhost | Prevents shipping with a dev API URL |
| Clerk key is `pk_live_` (if `CHECK_CLERK_KEY=true`) | Prevents shipping with a test Clerk key |
| App TypeScript (`tsc --noEmit`) | Catches type regressions before build |
| API unit tests (`API_TEST_CMD`) | Catches logic regressions |
| `ios/` directory exists | Catches missing prebuild |
| `ios/Podfile.lock` is committed | Catches CocoaPods version drift |

---

## ship.config.sh reference

Full list of all config options with their defaults:

```bash
# ── Required ──────────────────────────────────────────────────────────────────

# Display name used in build output and checklist headers
APP_NAME="MyApp"

# EAS build profile from eas.json to use for TestFlight builds
BUILD_PROFILE="preview"

# EAS submit profile from eas.json to use for App Store / TestFlight submission
SUBMIT_PROFILE="production"

# ── Environment Variable Checks ───────────────────────────────────────────────

# Env vars that must exist and be non-empty in eas.json build.$BUILD_PROFILE.env
# The preflight fails if any are missing.
REQUIRED_ENV_VARS=(
  "EXPO_PUBLIC_API_URL"
  "EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY"
  "EXPO_PUBLIC_EAS_PROJECT_ID"
  "EXPO_PUBLIC_SENTRY_DSN"
)

# EXPO_PUBLIC_API_URL must exactly match this value.
# Set to "" to skip. Used to prevent shipping with http://localhost:3000.
EXPECTED_API_URL="https://api.myapp.com"

# If true, verifies EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY starts with pk_live_
# Set to false if your app doesn't use Clerk
CHECK_CLERK_KEY=true

# ── Smoke Tests ───────────────────────────────────────────────────────────────

# Full URL to your production health endpoint.
# Must return HTTP 200 with JSON body { "status": "ok" }.
# Set to "" to skip smoke tests entirely.
SMOKE_TEST_URL="https://api.myapp.com/health"

# ── API Unit Tests ────────────────────────────────────────────────────────────

# Shell command run from the project root to execute your test suite.
# Set to "" to skip.
API_TEST_CMD="cd api && npm test"

# ── Post-Build Checklist ──────────────────────────────────────────────────────

# Shown after a successful TestFlight submission.
# List the manual flows you want to verify in the new build.
POST_BUILD_CHECKLIST=(
  "Sign in with your test account"
  "Core user flow (create / view / edit)"
  "Sign out and sign back in"
)
```

---

## eas.json requirements

expo-ship expects your `eas.json` to be structured with:

- A build profile matching `BUILD_PROFILE` (e.g. `"preview"`) with `distribution: "store"` for TestFlight
- `autoIncrement: true` so EAS manages the build number
- `appVersionSource: "remote"` at the top level
- A submit profile matching `SUBMIT_PROFILE` (e.g. `"production"`) with your Apple credentials
- All `REQUIRED_ENV_VARS` present in `build.<BUILD_PROFILE>.env`

Minimal working example:

```json
{
  "cli": {
    "version": ">= 12.0.0",
    "appVersionSource": "remote"
  },
  "build": {
    "preview": {
      "autoIncrement": true,
      "distribution": "store",
      "ios": { "simulator": false },
      "env": {
        "EXPO_PUBLIC_API_URL": "https://api.myapp.com",
        "EXPO_PUBLIC_CLERK_PUBLISHABLE_KEY": "pk_live_..."
      }
    }
  },
  "submit": {
    "production": {
      "ios": {
        "appleId": "you@example.com",
        "ascAppId": "1234567890",
        "appleTeamId": "XXXXXXXXXX"
      }
    }
  }
}
```

---

## File layout

### In this repo (`~/expo-ship/`)

```
expo-ship/
├── init.sh                    # Run once per app to scaffold files
├── scripts/
│   ├── preflight.sh           # Pre-flight safety checks
│   ├── smoke-test.sh          # Production API health check
│   ├── sim.sh                 # TypeScript check + simulator build
│   └── build-and-ship.sh      # eas build --local + eas submit
└── templates/
    ├── ship.config.sh         # Config template (heavily commented)
    └── Makefile               # Makefile template (do not edit the copy in apps)
```

### In each app

```
your-app/
├── ship.config.sh             # App-specific config — edit this
├── Makefile                   # Generated by init.sh — do not edit
└── build-output/              # .ipa files land here (gitignored)
    └── MyApp-20260409-143022.ipa
```

---

## Updating the scripts

Since all apps reference `~/expo-ship/scripts/` directly, updating the scripts in this repo immediately applies to every app — no per-app changes needed.

```bash
cd ~/expo-ship
git pull
```

---

## Troubleshooting

**`ship.config.sh not found`**
Run `~/expo-ship/init.sh` from your app's root directory.

**`EXPO_PUBLIC_API_URL is localhost`**
Your `eas.json` `preview.env.EXPO_PUBLIC_API_URL` is set to a local URL. Change it to your production API URL before building.

**`Clerk key is pk_test_`**
Your `eas.json` contains a Clerk test key. Replace it with the production `pk_live_` key from your Clerk dashboard.

**`ios/ directory missing`**
Run `npx expo prebuild --platform ios` to generate the native project.

**EAS build fails immediately**
Make sure you're logged in: `npx eas whoami`. If not, run `npx eas login`.

**Apple credential prompt during submit**
This is normal on first run or after credential expiry. Log in when prompted and EAS will cache the session.

**Build artifact not found after `eas build --local`**
EAS may have output the `.ipa` to a different path than `--output` specifies. Check the EAS build log for the actual file location.
