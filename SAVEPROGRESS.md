# Save Progress

_Last updated: 2026-09-12_

## Current state

The fork is merged with upstream Hydra v4.2.2 (41 commits: Expo SDK 55→57, chat,
mute-by-default, shared video players) on `merge/upstream-v4.2.2`, pushed to origin.
The first 4.2.2 build crashed on launch (dyld: missing `ExpoModulesCore` symbol);
that is fixed in `2c47066` and a fixed build was published over the air for the
iPhone. **Not yet confirmed on the phone.** `master` is still 4.1.1 and untouched.

## Files changed this session

| File | Why |
| --- | --- |
| `utils/SettingsBackup.ts` | Imported `expo-alternate-app-icons`, removed upstream 2026-07-25; broke every Release build. Now uses `utils/appIcons`. |
| Merge `f061945` (whole tree) | Upstream v4.2.2. Video files → upstream; `app.config.ts` keeps `HYDRA_BUNDLE_ID`; deps → upstream's. |
| `utils/VideoPlaybackPositions.ts` | Deleted — superseded by upstream's `utils/useSharedVideoPlayer.ts`. |
| `pages/SettingsPage/General/{Filters,BackupRestore}.tsx` | Icons moved to `@react-native-vector-icons` (upstream dropped `@expo/vector-icons`). |
| `pages/SettingsPage/index.tsx` | Keeps both `backupRestore` and upstream `modifyLinks` routes. |
| `package.json`, `package-lock.json` | `expo-file-system` and `expo-document-picker` pinned **exactly** to `57.0.1` to match `expo-modules-core 57.0.8` — the launch-crash fix. |
| `CLAUDE.md` | Shared video player; how conflicting syncs behave; the Expo module/core version trap and how to check for it. |

## Verified vs. untested

**Verified:** `tsc` 0 errors · `eslint` 0 errors · `expo export --platform ios` ·
Release Simulator build launches, runs 20s+, renders Home and loads the feed ·
device build: every framework's `ExpoModulesCore` imports resolve (`nm`), bundle
`com.theo78825.hydra`, version 4.2.2, device in provisioning profile.

**Untested:** the fixed build on the actual iPhone (phone unreachable from the Mac,
so only the Simulator was driven) · `tests/commentTree.test.ts` (needs `bun`) ·
Android · restoring a pre-merge settings backup through the new icon helper.

## Open items / known issues

- Feed videos now resume mid-play when scrolled back into view (upstream
  `backgroundPositions`); the fork used to restart them. Decide whether to re-add.
- `expo-doctor`: expo 57.0.8 has a known Hermes V1 memory regression (fixed in
  57.0.9+). Upstream's pin; bumping it means a coordinated core/module bump.
- `scripts/install-ota.sh` swallows xcodebuild failure and can publish a stale
  `Hydra.app`. A fix is running in a separate session.
- `sync-upstream.yml` fails daily since 2026-07-30 (PR step lacks permission) and
  leaves conflict markers committed on ~45 `upstream-sync-*` branches.
- `origin/claude/video-resume-playback-phu2bg` — stale, superseded; likely delete.

## Next steps

1. Install the OTA build on the iPhone and confirm it launches and the feed,
   videos, filters, and Settings → Backup & Restore work.
2. If it works: merge `merge/upstream-v4.2.2` into `master` and push.
3. Land the `install-ota.sh` fix; fix `sync-upstream.yml` permissions and stop it
   committing conflict markers; prune `upstream-sync-*` branches.
4. Decide on feed-video resume behaviour and the Expo 57.0.9+ bump.
