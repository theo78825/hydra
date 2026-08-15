#!/usr/bin/env bash
# Build Hydra and install it on the iPhone from anywhere — no cable, no VPN,
# no being on the same Wi-Fi.
#
#   scripts/install-ota.sh          pull, build, sign, publish, print the URL
#   scripts/install-ota.sh --fast   skip pull/npm/prebuild/pods, reuse ios/
#   scripts/install-ota.sh --off    tear the endpoint down now
#
# WHY THIS EXISTS
# `scripts/update-hydra.sh` installs over USB or Wi-Fi with `xcrun devicectl`,
# which needs the phone on the same network as this Mac. devicectl cannot reach
# the phone remotely, and Tailscale does not fix that: Apple discovers devices
# over Bonjour/mDNS (the `.coredevice.local` hostname), which is link-local
# multicast, and Tailscale is a unicast WireGuard mesh that deliberately does
# not forward multicast. Connecting the Mac to the tailnet changes nothing, and
# devicectl will not accept an IP address either.
#
# So this goes around it: package an IPA, serve it with an itms-services
# manifest from the always-on host over Funnel, and tap a link in Safari. It
# works because the phone is already in the development provisioning profile.
#
# Each run mints a NEW random path and deletes the old one, so yesterday's link
# stops working rather than leaving a signed app binary on a public URL forever.
#
# The signing recipe below is deliberately identical to update-hydra.sh. If you
# change it in one, change it in the other.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Absolute, resolved before the cd, so the teardown path below can re-invoke
# this script no matter where it was called from.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$ROOT"

bold() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ⚠ %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# CocoaPods needs LANG/LC_ALL set to en_US.UTF-8 locally, but ssh forwards them
# and the Pi has no such locale, so every remote command answers with three
# lines of setlocale warnings. Strip them at the boundary.
rsh() { env -u LC_ALL -u LANG ssh "$@"; }
rcp() { env -u LC_ALL -u LANG scp "$@"; }

# ── Config ────────────────────────────────────────────────────────────────
# Everything machine- or network-specific lives in an untracked file, because
# this repository is public. See scripts/ota.env.example.
ENV_FILE="${OTA_ENV:-$ROOT/scripts/ota.env}"
[[ -f "$ENV_FILE" ]] || die "no $ENV_FILE — copy scripts/ota.env.example to scripts/ota.env and fill it in."

# A gitignored secret is only secret while it stays gitignored.
if git -C "$ROOT" ls-files --error-unmatch "${ENV_FILE#$ROOT/}" >/dev/null 2>&1; then
  die "$ENV_FILE is TRACKED BY GIT and this repo is public. Run:
    git rm --cached ${ENV_FILE#$ROOT/}
  and confirm .gitignore still lists it before running this again."
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${PI:?set PI in $ENV_FILE}"
: "${HOSTNAME_TS:?set HOSTNAME_TS in $ENV_FILE}"
: "${DEVICE_UDID:?set DEVICE_UDID in $ENV_FILE}"

TEAM_ID="${TEAM_ID:-3U345JAS74}"
BUNDLE_ID="${BUNDLE_ID:-com.theo78825.hydra}"
FUNNEL_PATH="${FUNNEL_PATH:-/hydra}"   # NOT /h — that risks shadowing the relay's /health
PORT="${PORT:-8791}"                   # 8790 belongs to the Unpack OTA endpoint
SCHEME="Hydra"
WORKSPACE="ios/Hydra.xcworkspace"
XCODE_APP="${XCODE_APP:-/Applications/Xcode.app}"
DD="$ROOT/build"

# The link is a signed binary on a public URL. It should outlive the install by
# as little as possible, so a reaper on the host kills it without needing this
# Mac to still be awake, reachable, or running this script.
# TTL is the "you have not tapped it yet" window and has to cover a human
# reading a message and picking up the phone; 5 minutes was too short to use.
# GRACE is the one that limits real exposure — it starts the moment the phone
# actually pulls the IPA, and nothing needs the server after that.
TTL="${TTL:-900}"     # give up if nothing downloads it
GRACE="${GRACE:-120}" # once the phone has the IPA, the server has no further job

REMOTE_DIR=/opt/hydra-ota
UNIT=hydra-ota

# ── Teardown ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--off" ]]; then
  echo "==> tearing down"
  rsh "$PI" "sudo systemctl stop $UNIT-reaper >/dev/null 2>&1 || true
             sudo rm -f $REMOTE_DIR-reaper.sh
             sudo systemctl disable --now $UNIT >/dev/null 2>&1 || true
             sudo tailscale funnel --https=443 --set-path=$FUNNEL_PATH off >/dev/null 2>&1 || true
             sudo rm -rf $REMOTE_DIR"
  echo "  gone. The relay on / and the Unpack endpoint on /i are untouched."
  exit 0
fi

FAST=0
[[ "${1:-}" == "--fast" ]] && FAST=1

export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"   # use Xcode, no sudo
export HYDRA_BUNDLE_ID="$BUNDLE_ID"                    # override in app.config.ts
export SENTRY_DISABLE_AUTO_UPLOAD=true                 # skip source-map upload, matches CI
export LANG="${LANG:-en_US.UTF-8}"                     # keep CocoaPods happy
export LC_ALL="${LC_ALL:-en_US.UTF-8}"

[[ -d "$XCODE_APP" ]] || die "Xcode not found at $XCODE_APP — install it from the App Store."

# ── 1. Sources and native project ─────────────────────────────────────────
if (( FAST )); then
  [[ -d "$ROOT/ios" ]] || die "--fast needs an existing ios/ project. Run without --fast once."
  bold "Fast mode — reusing the checked-out sources and ios/ project"
else
  command -v pod >/dev/null || die "CocoaPods not found — run: brew install cocoapods"

  bold "Pulling latest code (origin/master)…"
  git pull --ff-only origin master || \
    warn "Couldn't fast-forward (local changes or divergence) — building the current checkout."

  bold "Installing dependencies (npm ci)…"
  npm ci

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
fi

# ── 2. Build ──────────────────────────────────────────────────────────────
# `generic/platform=iOS` rather than `id=$UDID`: the whole point is that the
# phone is not here, so xcodebuild must never try to resolve it.
bold "Building Hydra (Release) — this can take several minutes…"
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  build 2>&1 | grep -E "error:|warning: no rule|BUILD" || true

APP="$(/usr/bin/find "$DD/Build/Products/Release-iphoneos" -maxdepth 1 -name '*.app' 2>/dev/null | head -1)"
[[ -n "$APP" && -d "$APP" ]] || die "no .app produced under $DD/Build/Products/Release-iphoneos."

# The phone must be in the embedded profile, or the install fails on device with
# an unhelpful "Unable to Install". Better to fail here, loudly, than to hand
# over a link that cannot work.
if ! security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null \
     | plutil -convert xml1 -o - - | grep -q "$DEVICE_UDID"; then
  die "device $DEVICE_UDID is NOT in the provisioning profile.
  Plug the phone in once and run scripts/update-hydra.sh to register it."
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")"
BUILD="$(plutil -extract CFBundleVersion raw "$APP/Info.plist")"
echo "  Hydra $VERSION ($BUILD), device is provisioned"

# ── 3. Package ────────────────────────────────────────────────────────────
bold "Packaging"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
( cd "$STAGE" && zip -qry Hydra.ipa Payload && rm -rf Payload )
sips -Z 512 "$ROOT/assets/images/icon.png" --out "$STAGE/icon-512.png" >/dev/null
sips -Z 57  "$ROOT/assets/images/icon.png" --out "$STAGE/icon-57.png"  >/dev/null
echo "  $(du -h "$STAGE/Hydra.ipa" | cut -f1) IPA"

TOKEN="$(head -c 12 /dev/urandom | base64 | tr -d '/+=' | head -c 16)"
BASE="https://$HOSTNAME_TS$FUNNEL_PATH/$TOKEN"

cat > "$STAGE/manifest.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
<key>assets</key><array>
<dict><key>kind</key><string>software-package</string><key>url</key><string>$BASE/Hydra.ipa</string></dict>
<dict><key>kind</key><string>display-image</string><key>url</key><string>$BASE/icon-57.png</string></dict>
<dict><key>kind</key><string>full-size-image</string><key>url</key><string>$BASE/icon-512.png</string></dict>
</array>
<key>metadata</key><dict>
<key>bundle-identifier</key><string>$BUNDLE_ID</string>
<key>bundle-version</key><string>$VERSION</string>
<key>kind</key><string>software</string>
<key>title</key><string>Hydra</string>
</dict></dict></array></dict></plist>
PLIST
plutil -lint "$STAGE/manifest.plist" >/dev/null

cat > "$STAGE/index.html" <<HTML
<!doctype html><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Install Hydra</title>
<style>
 body{font:-apple-system-body,system-ui;margin:0;min-height:100vh;display:grid;
      place-items:center;background:#0b0b0d;color:#f2f0f5;text-align:center}
 .c{padding:32px 24px;max-width:22rem}
 img{width:104px;height:104px;border-radius:23%;box-shadow:0 8px 30px #0008}
 h1{font-size:1.6rem;margin:20px 0 4px} p{color:#a9a4b5;margin:0 0 26px}
 a{display:block;background:#ff4500;color:#fff;text-decoration:none;font-weight:600;
   padding:15px;border-radius:13px} small{display:block;color:#6f6a7d;margin-top:22px}
</style>
<div class=c>
 <img src="icon-512.png" alt="">
 <h1>Hydra</h1>
 <p>Version $VERSION (build $BUILD)</p>
 <a href="itms-services://?action=download-manifest&amp;url=$BASE/manifest.plist">Install</a>
 <small>Open in Safari. Replaces the copy already on your phone.</small>
</div>
HTML

# ── 4. Publish ────────────────────────────────────────────────────────────
bold "Publishing"
# Stop any reaper still running from an earlier run FIRST. It is watching a
# token that is about to stop existing, so it can only tear down this run's
# endpoint on the old run's schedule — and while it is loaded, systemd-run
# cannot claim the unit name, which would leave the new endpoint unreaped.
rsh "$PI" "sudo systemctl stop $UNIT-reaper >/dev/null 2>&1 || true
           sudo systemctl reset-failed $UNIT-reaper >/dev/null 2>&1 || true
           sudo rm -rf $REMOTE_DIR && sudo mkdir -p $REMOTE_DIR/$TOKEN \
           && sudo chown -R \$(id -un):\$(id -gn) $REMOTE_DIR"
rcp -q "$STAGE"/{Hydra.ipa,manifest.plist,index.html,icon-57.png,icon-512.png} \
    "$PI:$REMOTE_DIR/$TOKEN/"

rsh "$PI" "REMOTE_DIR=$REMOTE_DIR UNIT=$UNIT PORT=$PORT FUNNEL_PATH=$FUNNEL_PATH bash -s" <<'REMOTE'
set -e
# A blank index, because `python3 -m http.server` renders a DIRECTORY LISTING
# when none is present — which would hand the random token to anyone probing
# the mount point and defeat the whole point of it being unguessable.
printf '<!doctype html><title>.</title>\n' | sudo tee "$REMOTE_DIR/index.html" >/dev/null
sudo chown "$(id -un):$(id -gn)" "$REMOTE_DIR/index.html"

sudo tee "/etc/systemd/system/$UNIT.service" >/dev/null <<UNITFILE
[Unit]
Description=Hydra OTA install files
After=network-online.target
[Service]
Type=simple
User=$(id -un)
ExecStart=/usr/bin/python3 -m http.server $PORT --bind 127.0.0.1 --directory $REMOTE_DIR
Restart=on-failure
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=tmpfs
PrivateTmp=yes
ReadOnlyPaths=$REMOTE_DIR
[Install]
WantedBy=multi-user.target
UNITFILE
sudo systemctl daemon-reload
sudo systemctl enable "$UNIT" >/dev/null 2>&1
sudo systemctl restart "$UNIT"
sleep 2
# Mounted on a sub-path so the relay keeps the root of :443 to itself.
sudo tailscale funnel --bg --https=443 --set-path="$FUNNEL_PATH" "http://127.0.0.1:$PORT" >/dev/null
REMOTE

# ── 5. Verify, the same way the phone will ────────────────────────────────
bold "Verifying from this Mac (public path, not the tailnet)"
for f in "" manifest.plist Hydra.ipa; do
  code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 120 "$BASE/$f")"
  printf "  %-16s %s\n" "${f:-index}" "$code"
done
listing="$(curl -s --max-time 20 "https://$HOSTNAME_TS$FUNNEL_PATH/" | grep -c "$TOKEN" || true)"
echo "  token leaked in listing: $listing (0 = good)"
relay="$(curl -s -o /dev/null -w "%{http_code}" --max-time 20 "https://$HOSTNAME_TS/health")"
echo "  relay on / still healthy: $relay (200 = good)"

# ── 6. Arm the reaper ─────────────────────────────────────────────────────
# Only now, so the journal cursor sits AFTER the verification fetches above and
# any later hit on the IPA is genuinely the phone rather than us.
bold "Arming the reaper"
CURSOR="$(rsh "$PI" "journalctl -u $UNIT -n0 --show-cursor --no-pager 2>/dev/null \
                     | sed -n 's/^-- cursor: //p'")"

if [[ -z "$CURSOR" ]]; then
  warn "no journal cursor — REAPER NOT ARMED. Tear down by hand: $0 --off"
else
  rsh "$PI" "sudo tee $REMOTE_DIR-reaper.sh >/dev/null" <<'REAPER'
#!/bin/bash
# Tear the OTA endpoint down: GRACE seconds after the phone pulls the IPA, or
# TTL seconds from arming if nothing ever does. Runs as root under systemd, so
# it survives the Mac going to sleep or off the network.
#
# The phone is distinguishable from this script's own verification because the
# cursor was captured after verification finished. iOS also fetches the icons
# and issues a HEAD before the GET; matching only GET keeps that from counting
# twice, but the cursor is what makes this correct.
cursor="$1"; token="$2"; ttl="$3"; grace="$4"; unit="$5"; dir="$6"; fpath="$7"
deadline=$(( SECONDS + ttl )); got=0
while (( SECONDS < deadline )); do
  if (( ! got )) && journalctl -u "$unit" --after-cursor "$cursor" --no-pager 2>/dev/null \
       | grep -q "GET /$token/Hydra.ipa"; then
    got=1; deadline=$(( SECONDS + grace ))
    logger -t "$unit-reaper" "IPA fetched, tearing down in ${grace}s"
  fi
  sleep 5
done
logger -t "$unit-reaper" "tearing down (downloaded=$got)"
systemctl disable --now "$unit"
tailscale funnel --https=443 --set-path="$fpath" off
rm -rf "$dir" "$dir-reaper.sh"
REAPER
  # An arming failure must never take the script down with `set -e`: that would
  # exit without printing the URL while leaving a signed binary publicly served
  # and nothing scheduled to remove it. Report it and tear down instead.
  if rsh "$PI" "sudo chmod 0755 $REMOTE_DIR-reaper.sh
                sudo systemd-run --unit=$UNIT-reaper --collect \
                  $REMOTE_DIR-reaper.sh '$CURSOR' '$TOKEN' '$TTL' '$GRACE' '$UNIT' '$REMOTE_DIR' '$FUNNEL_PATH' >/dev/null"
  then
    echo "  armed: dies ${GRACE}s after the phone pulls it, or in ${TTL}s if nobody does"
  else
    warn "could not arm the reaper — tearing the endpoint down rather than"
    warn "leaving a signed build on a public URL with nothing to remove it."
    "$SELF" --off
    die "reaper would not start. Nothing is published. Re-run to try again."
  fi
fi

printf '\n\033[1;32m✓ Hydra %s (%s) ready to install.\033[0m\n' "$VERSION" "$BUILD"
echo
echo "  Open on the phone:  $BASE/"
echo "  Tear down now with: $SELF --off"
