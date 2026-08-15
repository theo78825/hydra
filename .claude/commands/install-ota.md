---
description: Build Hydra and publish a tap-to-install link for the iPhone, no cable or Wi-Fi
argument-hint: "[--fast | --off]"
allowed-tools: Bash(bash scripts/install-ota.sh*), Bash(./scripts/install-ota.sh*), Bash(cat scripts/install-ota.sh), Read
---

Build Hydra and publish it as an over-the-air install link the user can tap in
Safari from anywhere — unlike `/update-hydra`, this does not need the phone on
the same network as the Mac.

Run `bash scripts/install-ota.sh $ARGUMENTS` **in the background** (the build
takes several minutes) and report the outcome:

1. Surface the current phase from the `▶` lines (build → packaging → publishing
   → verifying → arming the reaper).
2. On success the script prints an `Open on the phone:` URL. **Give that URL to
   the user as a tappable markdown link, not in a code fence** — they read
   replies on the phone, and a fenced URL cannot be tapped.
3. Also tell them the deadline the script printed: the link self-destructs
   `GRACE` seconds after the phone pulls the build, or `TTL` seconds from
   publishing if nobody taps it. If it expires, just re-run with `--fast`.

Flags: `--fast` skips the pull/npm/prebuild/pods steps and reuses the existing
`ios/` project (much quicker, right for iterating). `--off` tears the endpoint
down immediately.

Failure modes worth translating:

- **"no scripts/ota.env"** → they need to copy `scripts/ota.env.example` to
  `scripts/ota.env` and fill in the SSH target, tailnet hostname, and device
  UDID. That file is gitignored on purpose; this repo is public.
- **"is TRACKED BY GIT"** → `scripts/ota.env` got committed. Follow the
  `git rm --cached` instruction the script prints, and treat the values in it
  as exposed.
- **"device ... is NOT in the provisioning profile"** → the phone has to be
  registered with the team once over USB. Run `/update-hydra` with the phone
  plugged in, then retry.
- **"reaper would not start"** → the script already tore the endpoint down, so
  nothing is published. Just re-run.

Do not edit the signing config, bundle identifier, port, or Funnel path unless
asked — port 443 is shared with the relay and the Unpack endpoint, and the
values in the script are chosen to avoid collisions.
