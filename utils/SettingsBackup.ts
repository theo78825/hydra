import { getAppIconName, setAlternateAppIcon } from "expo-alternate-app-icons";
import * as Application from "expo-application";

import KeyStore from "./KeyStore";

/**
 * Keys that should NOT be included in a settings backup. These are
 * login/session pointers rather than user-configurable settings. Reddit
 * session cookies live in encrypted cookie storage (RedditCookies), not MMKV,
 * so they are never part of a backup either.
 */
export const EXCLUDED_BACKUP_KEYS = new Set<string>([
  "currentUser", // pointer to the currently logged-in account
  "usernames", // list of saved accounts
]);

// v2 adds `appIcon`. v1 backups (no appIcon field) still restore fine — the
// icon is simply left unchanged.
export const BACKUP_FORMAT_VERSION = 2;

export type SettingsBackup = {
  app: "Hydra";
  formatVersion: number;
  appVersion: string | null;
  exportedAt: string;
  // Alternate app icon name (null = default). Stored at the OS level via
  // expo-alternate-app-icons, not in MMKV, so it must be captured separately.
  appIcon: string | null;
  data: Record<string, string | number | boolean>;
};

/** Current alternate app icon, or null on the default / unsupported platforms. */
function readAppIcon(): string | null {
  try {
    return getAppIconName();
  } catch {
    return null;
  }
}

/**
 * MMKV stores each key as exactly one type. We don't know the type up front,
 * so probe in order. A typed getter returns undefined when the stored value is
 * a different type (or absent), which makes this safe. Objects written via
 * useMMKVObject are stored as JSON strings, so they round-trip as strings.
 */
function readValue(key: string): string | number | boolean | undefined {
  const asString = KeyStore.getString(key);
  if (asString !== undefined) return asString;
  const asNumber = KeyStore.getNumber(key);
  if (asNumber !== undefined) return asNumber;
  const asBoolean = KeyStore.getBoolean(key);
  if (asBoolean !== undefined) return asBoolean;
  return undefined;
}

export function createSettingsBackup(): SettingsBackup {
  const data: Record<string, string | number | boolean> = {};
  for (const key of KeyStore.getAllKeys()) {
    if (EXCLUDED_BACKUP_KEYS.has(key)) continue;
    const value = readValue(key);
    if (value !== undefined) {
      data[key] = value;
    }
  }
  return {
    app: "Hydra",
    formatVersion: BACKUP_FORMAT_VERSION,
    appVersion: Application.nativeApplicationVersion,
    exportedAt: new Date().toISOString(),
    appIcon: readAppIcon(),
    data,
  };
}

export function serializeSettingsBackup(): string {
  return JSON.stringify(createSettingsBackup(), null, 2);
}

export type RestoreResult = {
  restored: number;
  skipped: number;
  appIconRestored: boolean;
  exportedAt?: string;
  appVersion?: string | null;
};

/**
 * Parse and apply a backup produced by createSettingsBackup. Throws a
 * user-readable Error if the input is not a valid Hydra backup. Writes each
 * setting directly to MMKV; reactive `useMMKV*` hooks pick up the new values,
 * but a relaunch is recommended since some settings are read once at startup.
 *
 * The alternate app icon lives at the OS level (not MMKV), so it is applied via
 * setAlternateAppIcon when the backup carries one (format v2+) — hence async.
 */
export async function restoreSettingsBackup(raw: string): Promise<RestoreResult> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("The selected file isn't valid JSON.");
  }

  if (
    !parsed ||
    typeof parsed !== "object" ||
    typeof (parsed as Partial<SettingsBackup>).data !== "object" ||
    (parsed as Partial<SettingsBackup>).data === null
  ) {
    throw new Error("This file isn't a Hydra settings backup.");
  }

  const backup = parsed as SettingsBackup;
  let restored = 0;
  let skipped = 0;

  for (const [key, value] of Object.entries(backup.data)) {
    if (EXCLUDED_BACKUP_KEYS.has(key)) {
      skipped++;
      continue;
    }
    if (
      typeof value === "string" ||
      typeof value === "number" ||
      typeof value === "boolean"
    ) {
      KeyStore.set(key, value);
      restored++;
    } else {
      skipped++;
    }
  }

  // Apply the OS-level app icon. Only present in v2+ backups; only change it
  // when it actually differs, to avoid an unnecessary system icon-change alert.
  let appIconRestored = false;
  const targetIcon = (parsed as Partial<SettingsBackup>).appIcon;
  if (targetIcon !== undefined) {
    try {
      if (getAppIconName() !== targetIcon) {
        await setAlternateAppIcon(
          targetIcon as Parameters<typeof setAlternateAppIcon>[0],
        );
      }
      appIconRestored = true;
    } catch {
      // Non-fatal: the icon may not exist in this build, or the platform may
      // not support alternate icons. Leave the current icon in place.
    }
  }

  return {
    restored,
    skipped,
    appIconRestored,
    exportedAt: backup.exportedAt,
    appVersion: backup.appVersion,
  };
}
