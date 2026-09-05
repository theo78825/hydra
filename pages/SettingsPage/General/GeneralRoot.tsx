import AntDesign from "@react-native-vector-icons/ant-design";
import Feather from "@react-native-vector-icons/feather";
import FontAwesome from "@react-native-vector-icons/fontawesome";
import MaterialCommunityIcons from "@react-native-vector-icons/material-design-icons";
import React, { useContext } from "react";
import { StyleSheet, Text, View } from "react-native";

import List from "../../../components/UI/List";
import { ThemeContext } from "../../../contexts/SettingsContexts/ThemeContext";
import { useURLNavigation } from "../../../utils/navigation";

const CUSTOM_VERSION = "1.0.0";

export default function GeneralRoot() {
  const { theme } = useContext(ThemeContext);
  const { pushURL } = useURLNavigation();

  return (
    <>
      <List
        title="General"
        items={[
          {
            key: "gestures",
            icon: <FontAwesome name="hand-o-up" size={24} color={theme.text} />,
            text: "Gestures",
            onPress: () => pushURL("hydra://settings/general/gestures"),
          },
          {
            key: "sorting",
            icon: <FontAwesome name="sort" size={24} color={theme.text} />,
            text: "Post & Comment Sorting",
            onPress: () => pushURL("hydra://settings/general/sorting"),
          },
          {
            key: "filters",
            icon: <AntDesign name="filter" size={24} color={theme.text} />,
            text: "Filters",
            onPress: () => pushURL("hydra://settings/general/filters"),
          },
          {
            key: "openInHydra",
            icon: <Feather name="external-link" size={24} color={theme.text} />,
            text: "Open in Hydra",
            onPress: () => pushURL("hydra://settings/general/openInHydra"),
          },
          {
            key: "startup",
            icon: (
              <MaterialCommunityIcons
                name="restart"
                size={24}
                color={theme.text}
              />
            ),
            text: "App Startup",
            onPress: () => pushURL("hydra://settings/general/startup"),
          },
          {
            key: "externalLinks",
            icon: <Feather name="link" size={22} color={theme.text} />,
            text: "External Links",
            onPress: () => pushURL("hydra://settings/general/externalLinks"),
          },
          {
            key: "backupRestore",
            icon: <Feather name="cloud" size={22} color={theme.text} />,
            text: "Backup & Restore",
            onPress: () => pushURL("hydra://settings/general/backupRestore"),
          },
        ]}
      />
      <View style={styles.versionContainer}>
        <Text style={[styles.versionText, { color: theme.subtleText }]}>
          Custom Build v{CUSTOM_VERSION}
          {"\n"}
          Bulk Import · Backup & Restore
        </Text>
      </View>
    </>
  );
}

const styles = StyleSheet.create({
  versionContainer: {
    marginVertical: 25,
    marginHorizontal: 15,
    alignItems: "center",
  },
  versionText: {
    textAlign: "center",
    fontSize: 13,
    lineHeight: 20,
  },
});
