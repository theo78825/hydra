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

`utils/VideoPlaybackPositions.ts` is the single source of truth for "where was this
video." Keyed by source URI, which is what makes the handoff work: the inline player
(`components/UI/Gallery/Video.tsx`) uses `uri` and the fullscreen player
(`MediaVideo.{ios,android}.tsx`) uses `source.source`, and they are the same string.

This replaced a pair of module-level globals (`lastPlaybackPosition` /
`lastPlaybackSource`) that upstream added to fix the player resetting on rotation.
Those only ever remembered one video. The map covers rotation too, since a remount
re-reads the same key — so **don't reintroduce the single-slot approach** thinking
the rotation case needs its own mechanism.

One non-obvious constraint: the inline player must **not** restore position in its
`useVideoPlayer` init callback, and must not seek unconditionally in its
`subscribeToVisibility` listener. That listener also fires on mount, so an ungated
seek makes every video scrolling back into the feed resume mid-playback instead of
starting over. The seek is gated behind a ref that only trips on a real
fullscreen→inline transition.

## Upstream syncs

A scheduled job opens `upstream-sync-YYYYMMDD-HHMMSS` branches against
`dmilin1/hydra` and lands them on `master`. Local `master` therefore goes stale
quickly — fetch and fast-forward before branching, or a feature branch ends up based
on a commit that is many syncs behind.
