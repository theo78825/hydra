#!/usr/bin/env bash
#
# update-hydra.sh — build the latest Hydra and install it on your iPhone.
#
# One command: pulls the latest code, builds a signed Release with your paid
# Apple Developer team, and installs it on your iPhone over USB or Wi-Fi.
#
# ── FIRST-TIME SETUP (do these once) ──────────────────────────────────────
#   1. Sign your Apple ID into Xcode:  Xcode ▸ Settings ▸ Accounts ▸ (＋).
#      This lets automatic signing create the App ID / provisioning profile
#      for team 3U345JAS74 ("Sam Albert").
#   2. Plug the iPhone in by USB the FIRST time, unlock it, and tap
#      "Trust This Computer". The first build registers the device with your
#      team (that's why run #1 must be over USB).
#   3. In Xcode ▸ Window ▸ Devices and Simulators, pick the iPhone and tick
#      "Connect via network" — then later runs can install over Wi-Fi.
#   After that: keep the phone unlocked and on the same Wi-Fi, and just run
#   this script (or /update-hydra in Claude Code).
#
# Usage:  scripts/update-hydra.sh [device-name-or-udid]
#   Pass a name/UDID to target a specific device; otherwise the first paired
#   iPhone is used.
#
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────
TEAM_ID="3U345JAS74"               # paid "Sam Albert" Apple Developer team
BUNDLE_ID="com.theo78825.hydra"    # App ID registered under your team
SCHEME="Hydra"
WORKSPACE="ios/Hydra.xcworkspace"
XCODE_APP="/Applications/Xcode.app"
DERIVED="build"

# ── Environment ───────────────────────────────────────────────────────────
cd "$(dirname "$0")/.."                                   # repo root
export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"      # use Xcode, no sudo
export HYDRA_BUNDLE_ID="$BUNDLE_ID"                        # override in app.config.ts
export LANG="${LANG:-en_US.UTF-8}"                         # keep CocoaPods happy
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

bold() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ⚠ %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[ -d "$XCODE_APP" ] || die "Xcode not found at $XCODE_APP — install it from the App Store."
command -v pod >/dev/null || die "CocoaPods not found — run: brew install cocoapods"

# ── 1. Latest code ────────────────────────────────────────────────────────
bold "Pulling latest code (origin/master)…"
if ! git pull --ff-only origin master; then
  warn "Couldn't fast-forward (local changes or divergence) — building the current checkout."
fi

# ── 2. JS dependencies ────────────────────────────────────────────────────
bold "Installing dependencies (npm ci)…"
npm ci

# ── 3. Generate the native iOS project ────────────────────────────────────
bold "Generating iOS project (expo prebuild → $BUNDLE_ID)…"
npx expo prebuild --platform ios --clean --no-install --non-interactive

# Same Swift-concurrency fix the CI build uses, so local builds match.
bold "Patching Podfile (Swift concurrency)…"
python3 - <<'PYEOF'
import re
with open('ios/Podfile') as f:
    content = f.read()
if "SWIFT_STRICT_CONCURRENCY" not in content:
    m = re.search(r'^( *)post_install do \|installer\|$', content, re.MULTILINE)
    if m:
        indent = m.group(1)
        patch = (
            f"{indent}  installer.pods_project.targets.each do |target|\n"
            f"{indent}    target.build_configurations.each do |config|\n"
            f"{indent}      config.build_settings['SWIFT_STRICT_CONCURRENCY'] = 'minimal'\n"
            f"{indent}    end\n"
            f"{indent}  end\n"
        )
        content = content[:m.end() + 1] + patch + content[m.end() + 1:]
        with open('ios/Podfile', 'w') as f:
            f.write(content)
        print("  Podfile patched.")
else:
    print("  Already patched.")
PYEOF

bold "Installing CocoaPods…"
( cd ios && pod install )

# ── 4. Find the iPhone ────────────────────────────────────────────────────
bold "Looking for your iPhone…"
DEVICES_JSON="$(mktemp)"
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1 || true
UDID="$(python3 - "$DEVICES_JSON" "${1:-}" <<'PYEOF'
import json, sys
path = sys.argv[1]
want = (sys.argv[2] if len(sys.argv) > 2 else "").strip().lower()
try:
    devices = json.load(open(path)).get("result", {}).get("devices", [])
except Exception:
    print(""); sys.exit()

def is_iphone(d):
    hw = d.get("hardwareProperties", {})
    return hw.get("deviceType") == "iPhone" or "iphone" in str(hw.get("productType", "")).lower()

fallback = ""
for d in devices:
    if not is_iphone(d):
        continue
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    name = str(d.get("deviceProperties", {}).get("name", "")).lower()
    udid = hw.get("udid") or d.get("identifier", "")
    if not udid:
        continue
    if want:                                   # explicit target requested
        if want == udid.lower() or want in name:
            print(udid); sys.exit()
        continue
    if conn.get("pairingState") == "paired":   # prefer a paired device
        print(udid); sys.exit()
    fallback = fallback or udid
print(fallback)
PYEOF
)"
rm -f "$DEVICES_JSON"
[ -n "$UDID" ] || die "No iPhone found. First run: connect by USB, unlock, tap 'Trust'. Later: unlock the phone, same Wi-Fi, and enable 'Connect via network' in Xcode ▸ Devices."
echo "  Using device: $UDID"

# ── 5. Build (Release, automatic signing under your team) ─────────────────
bold "Building Hydra (Release) — this can take several minutes…"
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  clean build

APP="$(/usr/bin/find "$DERIVED/Build/Products/Release-iphoneos" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$APP" ] || die "Build finished but no .app was produced under $DERIVED/Build/Products/Release-iphoneos."

# ── 6. Install + launch ───────────────────────────────────────────────────
bold "Installing on device…"
xcrun devicectl device install app --device "$UDID" "$APP"

bold "Launching Hydra…"
xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || \
  warn "Installed, but couldn't auto-launch — open Hydra from the home screen."

VERSION="$(node -p "require('./package.json').version" 2>/dev/null || echo "")"
printf '\n\033[1;32m✓ Done — Hydra %s installed on your iPhone.\033[0m\n' "$VERSION"
