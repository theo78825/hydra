import { APP_ICON_PLUGIN_ICONS } from "./constants/appIcons";
import packageJson from "./package.json";

const projectId = "7e403d7f-7747-4daa-a3c9-4acb948f7a60";
const IS_DEV = process.env.APP_VARIANT === "development";

<<<<<<< HEAD
// Allow signing under a personal Apple Developer team without editing the
// upstream default. `scripts/update-hydra.sh` sets HYDRA_BUNDLE_ID so local
// device builds use an identifier registered to your own team; CI and the
// daily upstream sync keep the default below untouched.
const BUNDLE_ID = process.env.HYDRA_BUNDLE_ID ?? "com.dmilin.hydra";
=======
const REDDIT_DEEP_LINK_HOSTS = [
  "reddit.com",
  "www.reddit.com",
  "old.reddit.com",
  "new.reddit.com",
];
>>>>>>> upstream/master

module.exports = {
  expo: {
    name: "Hydra",
    slug: "hydra",
    version: packageJson.version,
    runtimeVersion: {
      policy: "appVersion",
    },
    icon: "./assets/images/icon.png",
    scheme: "hydra",
    userInterfaceStyle: "automatic",
    assetBundlePatterns: ["**/*"],
    ios: {
      appStoreUrl:
        "https://apps.apple.com/us/app/hydra-for-reddit/id6478089063",
      supportsTablet: true,
      bundleIdentifier: BUNDLE_ID,
      infoPlist: {
        ITSAppUsesNonExemptEncryption: false,
      },
    },
    android: {
      package: "com.dmilin.hydra",
      adaptiveIcon: {
        foregroundImage: "./assets/images/icon_android.png",
        backgroundColor: "#000000",
      },
      intentFilters: [
        {
          action: "VIEW",
          category: ["BROWSABLE", "DEFAULT"],
          data: REDDIT_DEEP_LINK_HOSTS.flatMap((host) => [
            { scheme: "https", host },
            { scheme: "http", host },
          ]),
        },
      ],
    },
    web: {
      bundler: "metro",
      favicon: "./assets/images/favicon.png",
    },
    extra: {
      eas: {
        projectId,
      },
    },
    owner: "dmilin",
    plugins: [
      [
        "expo-media-library",
        {
          savePhotosPermission:
            "Allow $(PRODUCT_NAME) to save photos and videos to your library.",
        },
      ],
      "@sentry/react-native/expo",
      [
        "expo-image-picker",
        {
          photosPermission:
            "$(PRODUCT_NAME) accesses your photos to upload images.",
        },
      ],
      "expo-notifications",
      [
        "./plugins/withAppIcons",
        {
          icons: APP_ICON_PLUGIN_ICONS,
        },
      ],
      [
        "expo-sharing",
        {
          ios: {
            enabled: true,
            activationRule: {
              supportsWebUrlWithMaxCount: 1,
            },
          },
          android: {
            enabled: true,
            singleShareMimeTypes: ["text/plain"],
          },
        },
      ],
      [
        "expo-screen-orientation",
        {
          initialOrientation: "DEFAULT",
        },
      ],
      [
        "expo-splash-screen",
        {
          image: "./assets/images/icon_transparent.png",
          resizeMode: "contain",
          backgroundColor: "#000000",
          imageWidth: 150,
        }
      ],
      "expo-font",
      "expo-image",
      "expo-secure-store",
      "expo-sqlite",
      "expo-video",
      "expo-web-browser",
      "expo-status-bar",
    ],
    updates: {
      url: `https://u.expo.dev/${projectId}`,
      fallbackToCacheTimeout: 5000,
    },
  },
};
