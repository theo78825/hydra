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
