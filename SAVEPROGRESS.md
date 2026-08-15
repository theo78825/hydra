# Save Progress

_Last updated: 2026-08-15_

## Current state

Hydra 4.1.0 (1) builds and installs cleanly on the iPhone over the air. This
session added inline↔fullscreen video playback position sync and confirmed it
working on device, then committed the local OTA install tooling that had been
sitting uncommitted in the working tree.

## Files changed this session

**Video position sync** (commit `2972897`, branch `fix/video-position-sync`):

| File | Why |
| --- | --- |
| `utils/VideoPlaybackPositions.ts` | New. Shared uri→`currentTime` map, capped at 100 entries with least-recently-played eviction. |
| `components/UI/Gallery/Video.tsx` | Inline player records position on `timeUpdate`; seeks to the stored position when the media viewer closes. |
| `components/UI/MediaViewer.tsx/MediaVideo.ios.tsx` | Fullscreen opens at the inline position. Replaced the single-slot rotation globals with the shared store. |
| `components/UI/MediaViewer.tsx/MediaVideo.android.tsx` | Same read/write, for parity — the inline player is cross-platform. |

**OTA install tooling** (committed this run):

| File | Why |
| --- | --- |
| `scripts/install-ota.sh` | Build → package → publish a self-destructing tap-to-install link over Tailscale Funnel. No cable, no shared Wi-Fi. |
| `scripts/ota.env.example` | Template for the gitignored `scripts/ota.env` (SSH target, tailnet hostname, device UDID). |
| `.claude/commands/install-ota.md` | `/install-ota` slash command wrapping the script. |
| `.gitignore` | Ignore `build/` and `scripts/ota.env` — both carry device/signing details and this repo is public. |
| `.claude/settings.local.json` | Accumulated permission allowlist entries. |

## Verified working vs. untested

**Verified**
- Inline→fullscreen and fullscreen→inline position handoff, confirmed on device (iOS).
- `npx tsc --noEmit`, `eslint`, and `prettier --check` all clean on the changed files.
- `/install-ota --fast` end to end: build succeeded, endpoint published, public-path
  verification returned 200 for index/manifest/IPA, no token leaked in the listing,
  relay unaffected, reaper armed.

**Untested**
- `MediaVideo.android.tsx` — written for parity, never run on Android.
- The 100-entry eviction path in `VideoPlaybackPositions`.
- Whether the position survives a video whose source URI changes between renders
  (e.g. an expiring signed URL); it would simply not restore, which is the safe failure.

## Open items / known issues

- **Not merged into `master`.** The merge conflicts on `.gitignore` and was aborted
  rather than resolved unattended. Upstream rewrote `ios/` as `/ios` and added
  `/android`; this branch kept `ios/` and appended `build/` + `scripts/ota.env`.
  Resolution is mechanical — take upstream's two lines, then append both of ours.
  Everything is pushed to `origin/fix/video-position-sync`, so nothing is at risk.
- **`origin/claude/video-resume-playback-phu2bg` already does much of this.** A prior
  session built the same feature — same `utils/VideoPlaybackPositions.ts` filename,
  the same "restart feed videos when remounted" decision, plus its own OTA pipeline
  (`scripts/publish-install-page.sh`, a `signed-ipa.yml` workflow). It was never
  merged. Reconcile the two before landing either; don't merge both blind.

- **Inline videos still restart at 0 when scrolled back into view.** Deliberate: the
  seek is gated behind a ref so it only fires on a genuine fullscreen→inline
  transition. `subscribeToVisibility` also fires on mount, and without the gate every
  video re-entering the viewport would resume mid-playback.
- Positions are session-only (module state), so they reset on cold launch.
- `upstream-sync-*` branches are accumulating on origin from the scheduled
  dmilin1/hydra sync — worth pruning the merged ones at some point.
- The repo is **public**. `build/` (signed app + embedded provisioning profile) and
  `scripts/ota.env` (tailnet hostname + device UDID) must stay gitignored.

## Next steps

1. Compare this branch against `origin/claude/video-resume-playback-phu2bg` and decide
   which implementation survives. Abandon the other rather than merging both.
2. Resolve the `.gitignore` conflict and merge `fix/video-position-sync` into `master`:
   keep upstream's `/ios` and `/android`, then append the `build/` and
   `scripts/ota.env` blocks. Then push and delete the branch.
3. Use the app normally for a few days and confirm the position sync doesn't misfire
   on galleries with several videos in one post.
4. If Android ever matters, verify the fullscreen half there.
5. Consider persisting positions across launches (KeyStore) if session-only turns out
   to be too forgetful in practice.
6. Prune merged `upstream-sync-*` branches on origin (19 unmerged remote branches).
