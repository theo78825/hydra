# shellcheck shell=bash
# Shared by update-hydra.sh and install-ota.sh: get ios/ ready to build, and
# skip the slow part when nothing native has changed.
#
# `expo prebuild --clean` + `pod install` take minutes, and their output depends
# only on the inputs hashed in native_inputs_hash. So the hash is stored in
# ios/ once pod install succeeds, and the next run reuses ios/ as-is when it
# still matches. A JS/TS-only change therefore goes straight to xcodebuild,
# which still re-bundles the JS.
#
# Callers source this from the repo root, with bold/warn/die defined, and set
#   NATIVE_MODE=auto  prebuild + pods only when the hash changed (default)
#   NATIVE_MODE=full  always (--full); also used after an Expo SDK bump
# --fast doesn't come through here: it skips this whole step.

NATIVE_STAMP="ios/.native-inputs.sha"

# Everything prebuild and pod install read. app.config.ts imports package.json
# (the version lands in Info.plist) and constants/, and the icon plugin copies
# assets/images. This file is in the list because the Podfile patch lives here.
# HYDRA_BUNDLE_ID and ccache presence change prebuild output without touching a
# file, so they are hashed too.
native_inputs_hash() {
  {
    git ls-files -co --exclude-standard -z -- \
        package.json package-lock.json app.config.ts plugins constants \
        assets/images scripts/native-project.sh \
      | xargs -0 shasum
    echo "bundle=${HYDRA_BUNDLE_ID:-}"
    echo "ccache=$(command -v ccache || true)"
  } | shasum | cut -d' ' -f1
}

# npm ci wipes node_modules and reinstalls, which costs ~30s even when nothing
# changed. npm writes node_modules/.package-lock.json on every install, so
# compare that against the lockfile's package list instead.
npm_install_if_needed() {
  if [[ "$NATIVE_MODE" != full && -f node_modules/.package-lock.json ]] && node -e '
      const want = require("./package-lock.json").packages, have = require("./node_modules/.package-lock.json").packages;
      // Optional deps for other platforms are in the lockfile but never installed.
      const ok = Object.entries(want).every(([k, v]) => !k || (have[k] ? have[k].version === v.version : v.optional))
        && Object.keys(have).every((k) => k in want);
      process.exit(ok ? 0 : 1);
    ' 2>/dev/null; then
    bold "node_modules matches package-lock.json — skipping npm ci"
  else
    bold "Installing dependencies (npm ci)…"
    npm ci
  fi
}

prepare_native_project() {
  npm_install_if_needed

  local want
  want="$(native_inputs_hash)"
  if [[ "$NATIVE_MODE" != full && -f "$NATIVE_STAMP" && "$(cat "$NATIVE_STAMP")" == "$want" ]]; then
    bold "Native inputs unchanged — reusing ios/ (pass --full to regenerate)"
    return
  fi

  command -v pod >/dev/null || die "CocoaPods not found — run: brew install cocoapods"
  command -v ccache >/dev/null || \
    warn "ccache not installed — pods will compile from scratch. brew install ccache"

  bold "Generating iOS project (expo prebuild → ${HYDRA_BUNDLE_ID:-default bundle id})…"
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

  # Written last, so a failed prebuild or pod install is retried next run.
  echo "$want" > "$NATIVE_STAMP"
}

# Build settings for a local device build, as xcodebuild arguments.
#
# DEBUG_INFORMATION_FORMAT=dwarf: Release defaults to dwarf-with-dsym, and
# dsymutil runs once per framework. The dSYMs only matter for Sentry symbolication,
# and SENTRY_DISABLE_AUTO_UPLOAD is set for local builds, so nothing reads them.
LOCAL_BUILD_SETTINGS=(DEBUG_INFORMATION_FORMAT=dwarf)

# ccache hashes absolute paths, so each worktree would otherwise get its own
# cache. With a base dir, paths under the repo are hashed relative to it and a
# fresh worktree hits the objects another one already compiled.
export CCACHE_BASEDIR="$PWD"
