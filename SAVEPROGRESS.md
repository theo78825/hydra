# Save Progress

_Last updated: 2026-09-12_

## Current state

The fork is merged with upstream Hydra v4.2.2 (41 commits: Expo SDK 55→57, chat,
mute-by-default, shared video players) on the local branch `merge/upstream-v4.2.2`.
It type-checks, lints, bundles, and builds; the signed 4.2.2 build installed on the
iPhone over the air **but crashes immediately on launch**. Cause not yet known.
`master` is still the old 4.1.1 state; nothing from this session is on `master`.

## Files changed this session

| File | Why |
| --- | --- |
| `utils/SettingsBackup.ts` | Imported `expo-alternate-app-icons`, which upstream removed on 2026-07-25; every Release build failed at bundling. Now uses `utils/appIcons`. |
| Merge `f061945` (whole tree) | Upstream v4.2.2. Conflicts resolved: video files → upstream; `app.config.ts` keeps `HYDRA_BUNDLE_ID`; deps → upstream + `expo-document-picker`/`expo-file-system` at SDK 57. |
| `utils/VideoPlaybackPositions.ts` | Deleted — upstream's `utils/useSharedVideoPlayer.ts` shares one player between inline and fullscreen. |
| `pages/SettingsPage/General/{Filters,BackupRestore}.tsx` | Icon imports moved to `@react-native-vector-icons` (upstream dropped `@expo/vector-icons`). |
| `pages/SettingsPage/index.tsx` | Keeps both the `backupRestore` and upstream `modifyLinks` routes. |
| `CLAUDE.md` | Shared-player notes; how conflicting upstream syncs actually behave. |

## Verified vs. untested

**Verified:** `tsc --noEmit` 0 errors · `eslint` 0 errors · `expo export --platform ios`
bundles 2591 modules · Release device build succeeded · app is 4.2.2, bundle
`com.theo78825.hydra`, device in profile · OTA endpoint verified then self-destructed.

**Broken:** app crashes on launch on the iPhone.

**Untested:** `tests/commentTree.test.ts` (needs `bun`, not installed) · Android ·
backup restore of pre-merge v2 backups against the new icon helper.

## Open items / known issues

- **Launch crash.** Phone is unreachable from the Mac (devicectl: unavailable), so no
  crash log yet. `expo-doctor` reports 4 failed checks and 34 packages behind SDK 57's
  expected versions — prime suspect.
- `scripts/install-ota.sh` swallows xcodebuild failure (`… | grep … || true`) and will
  publish a stale `Hydra.app`. Fix in progress in a separate session.
- `sync-upstream.yml` has failed daily since 2026-07-30: its `gh pr create` lacks
  permission, and it commits conflict markers onto `upstream-sync-*` branches.
- Feed videos now resume mid-play when scrolled back into view (upstream behaviour);
  the fork used to restart them.
- `origin/claude/video-resume-playback-phu2bg` — stale, superseded twice; likely delete.

## Next steps

1. Get the crash log: phone Settings → Privacy & Security → Analytics & Improvements →
   Analytics Data → newest `Hydra-*.ips`, or plug in by USB.
2. Fix the crash; rebuild with `/install-ota` (full, not `--fast`, after dependency changes).
3. Confirm the app launches and video/backup tweaks behave on device.
4. Only then merge `merge/upstream-v4.2.2` into `master` and push.
5. Land the `install-ota.sh` and `sync-upstream.yml` fixes; prune `upstream-sync-*` branches.
