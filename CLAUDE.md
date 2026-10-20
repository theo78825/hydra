# CLAUDE.md

Durable notes for working in this repo. Session status lives in `SAVEPROGRESS.md`,
which gets overwritten; this file is for things that would otherwise cost the same
afternoon twice.

## This repo is a PUBLIC fork

`theo78825/hydra`, forked from `dmilin1/hydra`, and it is public. That changes what
a careless `git add -A` costs:

- **`build/`** holds the signed `Hydra.app` and its `embedded.mobileprovision` — a
  device UDID and a signing profile one commit away from being published.
- **`scripts/ota.env`** holds the SSH target, tailnet hostname, and device UDID.

Both are gitignored and must stay that way. `scripts/install-ota.sh` refuses to run
if `ota.env` has been added to git, which is the backstop, not the plan. Commit
`scripts/ota.env.example` (placeholders only) instead.

Note the Apple Team ID has been committed in `scripts/update-hydra.sh` since before
this convention existed. It is a public identifier rather than a credential, so it is
not worth rewriting history over — but don't add new ones.

## Getting a build onto the phone

Two paths, both local — no EAS, no CI:

- **`/update-hydra`** — builds and installs over USB. Needed the first time a device
  is used, since that's what registers it with the Apple Developer team.
- **`/install-ota`** — builds, then publishes a self-destructing install link over
  Tailscale Funnel. Works from anywhere; the phone does not need to share a network
  with the Mac. The link dies `GRACE` seconds after the phone pulls it, or `TTL`
  seconds if untapped.

`--fast` skips pull/npm/prebuild/pods and reuses the existing `ios/` project.
**It still re-bundles the JS during the Release build**, so JS/TS-only changes do not
need a full rebuild — `--fast` is the right default when iterating on app code.

Don't change the signing config, bundle identifier, port, or Funnel path casually:
port 443 is shared with the relay and the Unpack endpoint, and the values in the
script were picked to avoid collisions.

## Video playback positions

Upstream owns this now. Since v4.2 (`042a1b3`), the inline player
(`components/UI/Gallery/Video.tsx`) and the fullscreen player
(`MediaVideo.{ios,android}.tsx`) get their player from
`utils/useSharedVideoPlayer.ts`: one ref-counted `VideoPlayer` per source URI, so the
inline→fullscreen handoff can't drift — both views hold the same object. Rotation is
covered by the 250 ms release grace (the remount reacquires the same player) and,
past that, by the hook's `backgroundPositions` map.

This fork used to carry `utils/VideoPlaybackPositions.ts` for the same job; it was
deleted in the v4.2.2 merge. **Don't reintroduce a position map on top of the shared
player** — two sources of truth for one player's time is how they fight.

Known behaviour difference: `backgroundPositions` also restores position when a feed
video scrolls away (unmounts) and comes back, so it resumes mid-play. The old fork
tweak deliberately made those start over. If that's wanted again, gate the restore in
`getEntry` rather than seeking from the components.

## Upstream syncs

A scheduled job (`.github/workflows/sync-upstream.yml`) merges `dmilin1/hydra` daily.
A clean merge fast-forwards `master`. **A conflicting merge does not** — it commits
the conflicted files, markers and all, onto an `upstream-sync-YYYYMMDD-HHMMSS` branch
and tries to open a PR. That PR step has been failing on permissions, so conflicts
surface only as a red workflow run.

Consequences:
- **Never fast-forward or merge an `upstream-sync-*` branch** without grepping it for
  `^<<<<<<< `. `master` is its ancestor, so it looks like a clean fast-forward.
- To sync by hand, merge upstream directly:
  `git fetch https://github.com/dmilin1/hydra.git master && git merge FETCH_HEAD`.
- Local `master` goes stale either way — fetch before branching.
- After an Expo SDK bump, run `npm ci` **before** `npx expo install <pkg>`: it picks
  versions for whatever SDK is in `node_modules`, so a stale install yields the old
  SDK's versions. And `--fast` builds are wrong after an SDK bump — the native
  project needs a fresh prebuild and pod install.

## Expo module versions must match `expo-modules-core` (launch crash)

`npx expo install <pkg>` picks the **newest patch** in the SDK line, which can be
far ahead of the `expo-modules-core` that upstream's lockfile pins. Expo ships these
modules as **prebuilt binaries**, so nothing fails at build time: `tsc`, lint,
`expo export`, and a green `xcodebuild` all pass, and the app then dies instantly
on launch with `dyld: Symbol not found: _$s15ExpoModulesCore…`.

This bit the v4.2.2 merge: `expo-file-system@57.0.7` (built against core 57.0.18)
against upstream's core 57.0.8. Fix was pinning `expo-file-system` and
`expo-document-picker` **exactly** to `57.0.1`, the version upstream's own lockfile
uses. A `~` range floats back up on the next fresh install.

- When re-adding an Expo package upstream dropped, pin it to the version in
  upstream's `package-lock.json`, or one published no later than the pinned core.
- Don't reach for `npx expo install --fix` to realign: it also **downgrades**
  deliberate majors (Sentry 8→7, gesture-handler 3→2 — upstream's player needs v3).
- Verify before shipping a build: launch it. With the phone unreachable, a Release
  Simulator build (`SENTRY_DISABLE_AUTO_UPLOAD=true`, `CODE_SIGNING_ALLOWED=NO`) and
  `xcrun simctl launch --console-pty` reproduce dyld crashes. Or diff each
  framework's `nm -u` symbols containing `15ExpoModulesCore` against
  `nm -gU ExpoModulesCore`; any leftover is a guaranteed launch crash.

## iOS 27 requires the UIScene lifecycle (launch crash)

Built with the iOS 27 SDK (Xcode 27), an app with no `UIApplicationSceneManifest`
is killed at launch on iOS 27: `EXC_BREAKPOINT` in
`UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`, before any JS runs.
Expo SDK 57's template still starts React Native from `didFinishLaunching`, so
`plugins/withSceneLifecycle.js` adds the manifest and moves startup into a
`SceneDelegate` (appended to the generated `AppDelegate.swift`) that forwards URLs
and user activities back to the AppDelegate.

- The plugin throws during prebuild if Expo's AppDelegate template changes shape —
  update the plugin; don't drop it. Once Expo ships scene support, delete it.
- Read the crash on the device with
  `xcrun devicectl device info files --device <UDID> --domain-type systemCrashLogs`
  and `devicectl device copy from … --source Hydra-<date>.ips`.
