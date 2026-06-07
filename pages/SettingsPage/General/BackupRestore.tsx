import { Feather, MaterialCommunityIcons } from "@expo/vector-icons";
import * as DocumentPicker from "expo-document-picker";
import * as FileSystem from "expo-file-system/legacy";
import * as Sharing from "expo-sharing";
import * as Updates from "expo-updates";
import React, { useContext, useState } from "react";
import { ActivityIndicator, Alert, StyleSheet, Text, View } from "react-native";

import List from "../../../components/UI/List";
import { ThemeContext } from "../../../contexts/SettingsContexts/ThemeContext";
import {
  restoreSettingsBackup,
  serializeSettingsBackup,
} from "../../../utils/SettingsBackup";

function backupFileName() {
  const date = new Date().toISOString().slice(0, 10);
  return `Hydra-Settings-${date}.json`;
}

export default function BackupRestore() {
  const { theme } = useContext(ThemeContext);
  const [busy, setBusy] = useState<null | "backup" | "restore">(null);

  const promptRestart = (message: string) => {
    Alert.alert("Settings Restored", message, [
      { text: "Later", style: "cancel" },
      {
        text: "Restart Now",
        isPreferred: true,
        onPress: async () => {
          try {
            await Updates.reloadAsync();
          } catch {
            Alert.alert(
              "Couldn't restart automatically",
              "Please close and reopen Hydra for all settings to take effect.",
            );
          }
        },
      },
    ]);
  };

  const handleBackup = async () => {
    if (busy) return;
    setBusy("backup");
    try {
      const canShare = await Sharing.isAvailableAsync();
      if (!canShare) {
        Alert.alert(
          "Sharing unavailable",
          "This device can't open the share sheet, so the backup can't be saved.",
        );
        return;
      }

      const json = serializeSettingsBackup();
      const uri = `${FileSystem.cacheDirectory}${backupFileName()}`;
      await FileSystem.writeAsStringAsync(uri, json, {
        encoding: FileSystem.EncodingType.UTF8,
      });

      // Opens the iOS share sheet — choose "Save to Files" → iCloud Drive to
      // store the backup in iCloud. No iCloud entitlement is needed because the
      // save is user-initiated through the share sheet.
      await Sharing.shareAsync(uri, {
        mimeType: "application/json",
        UTI: "public.json",
        dialogTitle: "Save Hydra Settings Backup",
      });
    } catch (e) {
      Alert.alert(
        "Backup failed",
        e instanceof Error ? e.message : "An unexpected error occurred.",
      );
    } finally {
      setBusy(null);
    }
  };

  const handleRestore = async () => {
    if (busy) return;
    setBusy("restore");
    try {
      const picked = await DocumentPicker.getDocumentAsync({
        type: ["application/json", "public.json", "public.text", "text/plain"],
        copyToCacheDirectory: true,
        multiple: false,
      });

      if (picked.canceled || !picked.assets?.[0]) {
        return;
      }

      const content = await FileSystem.readAsStringAsync(picked.assets[0].uri, {
        encoding: FileSystem.EncodingType.UTF8,
      });

      Alert.alert(
        "Restore Settings?",
        "This will overwrite your current Hydra settings with the ones in this backup. Your logged-in accounts won't be changed.",
        [
          { text: "Cancel", style: "cancel" },
          {
            text: "Restore",
            style: "destructive",
            onPress: () => {
              try {
                const result = restoreSettingsBackup(content);
                promptRestart(
                  `Restored ${result.restored} setting${
                    result.restored !== 1 ? "s" : ""
                  }${
                    result.exportedAt
                      ? ` from a backup made ${new Date(
                          result.exportedAt,
                        ).toLocaleDateString()}`
                      : ""
                  }. Restart Hydra for all changes to take effect.`,
                );
              } catch (e) {
                Alert.alert(
                  "Restore failed",
                  e instanceof Error
                    ? e.message
                    : "An unexpected error occurred.",
                );
              }
            },
          },
        ],
      );
    } catch (e) {
      Alert.alert(
        "Restore failed",
        e instanceof Error ? e.message : "An unexpected error occurred.",
      );
    } finally {
      setBusy(null);
    }
  };

  return (
    <>
      <Text style={[styles.textDescription, { color: theme.text }]}>
        Back up your Hydra settings — themes, gestures, filters, sorting, and
        other preferences — to a file you can store in iCloud Drive. To save to
        iCloud, tap Back Up Settings, then choose &quot;Save to Files&quot; and
        pick an iCloud Drive folder. On another device, install Hydra, open this
        screen, and tap Restore Settings to load the file back.
      </Text>
      <List
        title="Backup"
        items={[
          {
            key: "backup",
            icon: <Feather name="upload-cloud" size={24} color={theme.text} />,
            text: "Back Up Settings",
            rightIcon:
              busy === "backup" ? (
                <ActivityIndicator color={theme.text} />
              ) : (
                <MaterialCommunityIcons
                  name="chevron-right"
                  size={24}
                  color={theme.subtleText}
                />
              ),
            onPress: handleBackup,
          },
          {
            key: "restore",
            icon: (
              <Feather name="download-cloud" size={24} color={theme.text} />
            ),
            text: "Restore Settings",
            rightIcon:
              busy === "restore" ? (
                <ActivityIndicator color={theme.text} />
              ) : (
                <MaterialCommunityIcons
                  name="chevron-right"
                  size={24}
                  color={theme.subtleText}
                />
              ),
            onPress: handleRestore,
          },
        ]}
      />
      <Text style={[styles.textDescription, { color: theme.subtleText }]}>
        Your Reddit login and saved accounts are stored separately and are not
        included in the backup. Restoring overwrites matching settings but
        leaves any settings not present in the backup untouched.
      </Text>
      <View style={{ marginBottom: 50 }} />
    </>
  );
}

const styles = StyleSheet.create({
  textDescription: {
    marginTop: 15,
    marginHorizontal: 15,
    lineHeight: 20,
  },
});
