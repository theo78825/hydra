#!/usr/bin/env bash
#
# publish-install-page.sh — serve Hydra over the air from a Raspberry Pi.
#
# Downloads a signed IPA published by .github/workflows/signed-ipa.yml and
# writes the itms-services manifest + install page next to it, so the phone can
# install Hydra by opening a link. Run it on the Pi (or wherever the install
# page is hosted), not on a Mac.
#
# ── REQUIREMENTS ──────────────────────────────────────────────────────────
#   * The IPA must be signed (ad-hoc, with this phone's UDID registered).
#     iOS silently refuses unsigned IPAs served this way — the build.yml
#     artifact will NOT work here.
#   * HYDRA_INSTALL_BASE_URL must be HTTPS with a certificate the phone
#     already trusts. iOS rejects plain HTTP and untrusted/self-signed certs
#     for itms-services, usually with a bare "Cannot connect to <host>".
#
# ── USAGE ─────────────────────────────────────────────────────────────────
#   HYDRA_INSTALL_BASE_URL=https://pi.example.com/hydra \
#     scripts/publish-install-page.sh [release-tag]
#
#   With no tag, the latest release is used.
#
# ── ENVIRONMENT ───────────────────────────────────────────────────────────
#   HYDRA_INSTALL_BASE_URL  (required) public HTTPS URL that serves WEB_ROOT,
#                           no trailing slash
#   HYDRA_WEB_ROOT          output directory        (default /var/www/hydra)
#   HYDRA_REPO              GitHub repo             (default theo78825/hydra)
#   GITHUB_TOKEN            only needed if the repo is private
#
set -euo pipefail

BASE_URL="${HYDRA_INSTALL_BASE_URL:-}"
WEB_ROOT="${HYDRA_WEB_ROOT:-/var/www/hydra}"
REPO="${HYDRA_REPO:-theo78825/hydra}"
TAG="${1:-}"

bold() { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
die()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[ -n "$BASE_URL" ] || die "Set HYDRA_INSTALL_BASE_URL to the public HTTPS URL serving $WEB_ROOT."
case "$BASE_URL" in
  https://*) ;;
  *) die "HYDRA_INSTALL_BASE_URL must start with https:// — iOS won't install over plain HTTP." ;;
esac
BASE_URL="${BASE_URL%/}"
command -v curl    >/dev/null || die "curl is required."
command -v python3 >/dev/null || die "python3 is required."

AUTH=()
[ -n "${GITHUB_TOKEN:-}" ] && AUTH=(-H "Authorization: Bearer $GITHUB_TOKEN")

# ── 1. Find the release and its IPA ───────────────────────────────────────
if [ -n "$TAG" ]; then
  bold "Looking up release $TAG…"
  API="https://api.github.com/repos/$REPO/releases/tags/$TAG"
else
  bold "Looking up the latest release…"
  API="https://api.github.com/repos/$REPO/releases/latest"
fi

RELEASE_JSON="$(curl -fsSL "${AUTH[@]}" "$API")" \
  || die "Couldn't read $API — check the repo name, the tag, and GITHUB_TOKEN if private."

read -r TAG IPA_URL IPA_NAME <<EOF
$(printf '%s' "$RELEASE_JSON" | python3 -c '
import json, sys
release = json.load(sys.stdin)
assets = [a for a in release.get("assets", []) if a["name"].endswith(".ipa")]
if not assets:
    sys.exit("no .ipa asset attached to this release")
asset = assets[0]
print(release["tag_name"], asset["url"], asset["name"])
')
EOF
[ -n "${IPA_URL:-}" ] || die "No .ipa asset found on that release."
echo "  $TAG → $IPA_NAME"

# ── 2. Download it ────────────────────────────────────────────────────────
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

bold "Downloading $IPA_NAME…"
# The asset API URL needs this Accept header to return the binary itself
# rather than the asset's JSON metadata.
curl -fsSL "${AUTH[@]}" -H "Accept: application/octet-stream" \
  -o "$STAGING/Hydra.ipa" "$IPA_URL" || die "Download failed."

# ── 3. Read the app's identity out of the IPA ─────────────────────────────
bold "Reading app metadata…"
read -r BUNDLE_ID VERSION BUILD <<EOF
$(python3 - "$STAGING/Hydra.ipa" <<'PYEOF'
import plistlib, re, sys, zipfile

with zipfile.ZipFile(sys.argv[1]) as ipa:
    matches = [n for n in ipa.namelist()
               if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
    if not matches:
        sys.exit("couldn't find Info.plist inside the IPA")
    info = plistlib.loads(ipa.read(matches[0]))

print(info["CFBundleIdentifier"],
      info.get("CFBundleShortVersionString", "0"),
      info.get("CFBundleVersion", "0"))
PYEOF
)
EOF
[ -n "${BUNDLE_ID:-}" ] || die "Couldn't read the bundle identifier from the IPA."
echo "  $BUNDLE_ID — $VERSION ($BUILD)"

# ── 4. Write the manifest and install page ────────────────────────────────
bold "Writing install page…"
cat > "$STAGING/manifest.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key><string>software-package</string>
          <key>url</key><string>${BASE_URL}/Hydra.ipa</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key><string>${BUNDLE_ID}</string>
        <key>bundle-version</key><string>${VERSION}</string>
        <key>kind</key><string>software</string>
        <key>title</key><string>Hydra</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

INSTALL_LINK="itms-services://?action=download-manifest&amp;url=${BASE_URL}/manifest.plist"
PUBLISHED_AT="$(date '+%Y-%m-%d %H:%M %Z')"

cat > "$STAGING/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Install Hydra</title>
<style>
  :root { color-scheme: light dark; }
  body {
    font: 17px/1.5 -apple-system, system-ui, sans-serif;
    margin: 0; min-height: 100vh; display: flex; align-items: center;
    justify-content: center; padding: 24px; background: Canvas; color: CanvasText;
  }
  main { width: 100%; max-width: 22rem; text-align: center; }
  h1 { font-size: 1.5rem; margin: 0 0 .25rem; }
  .meta { opacity: .6; font-size: .9rem; margin: 0 0 2rem; }
  a.install {
    display: block; padding: 14px; border-radius: 12px; background: #0a84ff;
    color: #fff; text-decoration: none; font-weight: 600;
  }
  .note { margin-top: 2rem; font-size: .8rem; opacity: .6; }
</style>
</head>
<body>
<main>
  <h1>Hydra $VERSION</h1>
  <p class="meta">build $BUILD &middot; $TAG<br>published $PUBLISHED_AT</p>
  <a class="install" href="$INSTALL_LINK">Install on this iPhone</a>
  <p class="note">Open this page in Safari on the iPhone itself &mdash; other
  browsers ignore install links. Tap Install when iOS asks.</p>
</main>
</body>
</html>
HTML

# ── 5. Publish ────────────────────────────────────────────────────────────
bold "Publishing to $WEB_ROOT…"
mkdir -p "$WEB_ROOT" || die "Couldn't create $WEB_ROOT — try sudo, or set HYDRA_WEB_ROOT."
# Move the IPA in first so the page never advertises a build that isn't there.
mv -f "$STAGING/Hydra.ipa"      "$WEB_ROOT/Hydra.ipa"
mv -f "$STAGING/manifest.plist" "$WEB_ROOT/manifest.plist"
mv -f "$STAGING/index.html"     "$WEB_ROOT/index.html"
chmod 644 "$WEB_ROOT/Hydra.ipa" "$WEB_ROOT/manifest.plist" "$WEB_ROOT/index.html"

printf '\n\033[1;32m✓ Hydra %s (%s) is live at %s\033[0m\n' "$VERSION" "$TAG" "$BASE_URL/"
echo "  Open that URL in Safari on the iPhone to install."
