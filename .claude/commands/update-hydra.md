---
description: Build the latest Hydra and install it on the connected iPhone
argument-hint: "[device-name-or-udid]"
allowed-tools: Bash(bash scripts/update-hydra.sh*), Bash(cat scripts/update-hydra.sh), Read
---

Build the latest Hydra from `origin/master` and install it on the user's iPhone,
signed with their paid Apple Developer team.

Run the build script and report the outcome:

1. Execute `bash scripts/update-hydra.sh $ARGUMENTS` **in the background** (the
   clean Release build takes several minutes), and monitor its output.
2. While it runs, surface the current phase from the `▶` progress lines
   (pulling code → npm → prebuild → pods → build → install).
3. On success, confirm the installed version (from the final `✓ Done` line).
4. If it fails, relay the exact `✗` message and the fix:
   - **"No iPhone found"** → tell them to unlock the phone, ensure it's on the
     same Wi-Fi, and (first run only) connect by USB and tap "Trust This
     Computer". They can also re-run as `/update-hydra <device-name>`.
   - **Signing / provisioning errors** → they likely need to sign their Apple ID
     into Xcode once (Xcode ▸ Settings ▸ Accounts) so automatic signing can
     create the profile for team `3U345JAS74`.
   - **Any other build error** → show the last ~20 lines of xcodebuild output.

Do not edit signing config, the bundle identifier, or the script unless the user
asks — the setup in `scripts/update-hydra.sh` is intentional.
