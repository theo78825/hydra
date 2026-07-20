import packageJson from './package.json';

const projectId = "7e403d7f-7747-4daa-a3c9-4acb948f7a60";
const IS_DEV = process.env.APP_VARIANT === 'development';

// Allow signing under a personal Apple Developer team without editing the
// upstream default. `scripts/update-hydra.sh` sets HYDRA_BUNDLE_ID so local
// device builds use an identifier registered to your own team; CI and the
// daily upstream sync keep the default below untouched.
const BUNDLE_ID = process.env.HYDRA_BUNDLE_ID ?? "com.dmilin.hydra";

module.exports = {
  expo: {
    name: "Hydra",
    slug: "hydra",
    version: packageJson.version,
    runtimeVersion: {
      policy: 'appVersion',
    },
    icon: "./assets/images/icon.png",
    scheme: "hydra",
    userInterfaceStyle: "automatic",
    splash: {
      image: "./assets/images/splash.png",
      resizeMode: "contain",
      backgroundColor: "#000000"
    },
    assetBundlePatterns: [
      "**/*"
    ],
    ios: {
      appStoreUrl: "https://apps.apple.com/us/app/hydra-for-reddit/id6478089063",
      supportsTablet: true,
      bundleIdentifier: BUNDLE_ID,
      infoPlist: {
        ITSAppUsesNonExemptEncryption: false,
      },
    },
    android: {
      package: "com.dmilin.hydra",
      adaptiveIcon: {
        foregroundImage: "./assets/images/adaptive-icon.png",
        backgroundColor: "#000000"
      }
    },
    web: {
      bundler: "metro",
      favicon: "./assets/images/favicon.png"
    },
    extra: {
      eas: {
        projectId,
      }
    },
    owner: "dmilin",
    plugins: [
      "expo-router",
      [
        'expo-media-library', {
          savePhotosPermission: 'Allow $(PRODUCT_NAME) to save photos and videos to your library.',
        }
      ],
      "@sentry/react-native/expo",
      [
        'expo-image-picker', {
          "photosPermission": "$(PRODUCT_NAME) accesses your photos to upload images.",
        }
      ],
      "expo-notifications",
      [
        "expo-alternate-app-icons",
        [
          {
            "name": "cerberus",
            "ios": "./assets/images/custom_icons/cerberus.png",
            "android": {
              "foregroundImage": "./assets/images/custom_icons/cerberus.png",
              "backgroundColor": "#FFFFFF",
            },
          },
          {
            "name": "hail_hydra",
            "ios": "./assets/images/custom_icons/hail_hydra.png",
            "android": {
              "foregroundImage": "./assets/images/custom_icons/hail_hydra.png",
              "backgroundColor": "#FFFFFF",
            },
          },
          {
            "name": "hail_hydra_dark",
            "ios": "./assets/images/custom_icons/hail_hydra_dark.png",
            "android": {
              "foregroundImage": "./assets/images/custom_icons/hail_hydra_dark.png",
              "backgroundColor": "#000000",
            },
          },
        ]
      ],
      [
        "expo-sharing",
        {
          "ios": {
            "enabled": true,
            "activationRule": {
              "supportsWebUrlWithMaxCount": 1,
            }
          },
        }
      ],
      [
        "expo-screen-orientation",
        {
          "initialOrientation": "DEFAULT"
        }
      ],
      "expo-font",
      "expo-image",
      "expo-secure-store",
      "expo-sqlite",
      "expo-video",
      "expo-web-browser",
    ],
    updates: {
      url: `https://u.expo.dev/${projectId}`,
      fallbackToCacheTimeout: 5000,
    }
  }
}
