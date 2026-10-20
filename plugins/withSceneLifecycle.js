/**
 * Moves the iOS app onto the UIScene lifecycle.
 *
 * iOS 27 refuses to launch an app built with the iOS 27 SDK that has not adopted
 * scenes: it traps in UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption
 * before any JS runs. Expo SDK 57's template still starts React Native from
 * application(_:didFinishLaunchingWithOptions:), so this plugin:
 *
 * - declares a single-window UIApplicationSceneManifest in Info.plist, and
 * - rewrites the generated AppDelegate.swift so React Native starts in a
 *   SceneDelegate's window instead.
 *
 * With scenes, iOS delivers URLs and user activities to the scene rather than
 * the app delegate, so the SceneDelegate forwards them back to the AppDelegate.
 * That keeps RCTLinkingManager and the Expo app-delegate subscribers
 * (expo-linking, the share extension's hydra:// hand-off) working unchanged.
 *
 * AppDelegate.window is still set, because some modules read it through
 * UIApplication.shared.delegate.
 */
const { withAppDelegate, withInfoPlist } = require("expo/config-plugins");

const START_RN_IN_APP_DELEGATE = `#if os(iOS) || os(tvOS)
    window = UIWindow(frame: UIScreen.main.bounds)
    factory.startReactNative(
      withModuleName: "main",
      in: window,
      launchOptions: launchOptions)
#endif
`;

const SCENE_DELEGATE = `
// Added by plugins/withSceneLifecycle.js — iOS 27 requires the scene lifecycle.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  private var appDelegate: AppDelegate? {
    UIApplication.shared.delegate as? AppDelegate
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene,
          let appDelegate = appDelegate,
          let factory = appDelegate.reactNativeFactory else {
      return
    }

    var launchOptions: [UIApplication.LaunchOptionsKey: Any] = [:]
    if let url = connectionOptions.urlContexts.first?.url {
      launchOptions[.url] = url
    }

    let window = UIWindow(windowScene: windowScene)
    self.window = window
    appDelegate.window = window
    factory.startReactNative(
      withModuleName: "main",
      in: window,
      launchOptions: launchOptions)
    window.makeKeyAndVisible()

    if !connectionOptions.urlContexts.isEmpty {
      self.scene(scene, openURLContexts: connectionOptions.urlContexts)
    }
    for userActivity in connectionOptions.userActivities {
      self.scene(scene, continue: userActivity)
    }
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      var options: [UIApplication.OpenURLOptionsKey: Any] = [:]
      if let sourceApplication = context.options.sourceApplication {
        options[.sourceApplication] = sourceApplication
      }
      if let annotation = context.options.annotation {
        options[.annotation] = annotation
      }
      options[.openInPlace] = context.options.openInPlace
      _ = appDelegate?.application(UIApplication.shared, open: context.url, options: options)
    }
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    _ = appDelegate?.application(
      UIApplication.shared,
      continue: userActivity,
      restorationHandler: { _ in })
  }
}
`;

function withSceneAppDelegate(config) {
  return withAppDelegate(config, (config) => {
    if (config.modResults.language !== "swift") {
      throw new Error("withSceneLifecycle: expected a Swift AppDelegate.");
    }
    let contents = config.modResults.contents;
    if (contents.includes("class SceneDelegate")) {
      return config;
    }
    if (!contents.includes(START_RN_IN_APP_DELEGATE)) {
      // Fail the prebuild rather than ship a build that dies on launch.
      throw new Error(
        "withSceneLifecycle: AppDelegate.swift no longer matches the Expo template " +
          "this plugin rewrites. Update plugins/withSceneLifecycle.js.",
      );
    }
    contents = contents.replace(
      START_RN_IN_APP_DELEGATE,
      "    // React Native starts in SceneDelegate, once the window scene exists.\n",
    );
    config.modResults.contents = contents + SCENE_DELEGATE;
    return config;
  });
}

function withSceneManifest(config) {
  return withInfoPlist(config, (config) => {
    config.modResults.UIApplicationSceneManifest = {
      UIApplicationSupportsMultipleScenes: false,
      UISceneConfigurations: {
        UIWindowSceneSessionRoleApplication: [
          {
            UISceneConfigurationName: "Default Configuration",
            UISceneDelegateClassName: "$(PRODUCT_MODULE_NAME).SceneDelegate",
          },
        ],
      },
    };
    return config;
  });
}

module.exports = function withSceneLifecycle(config) {
  return withSceneManifest(withSceneAppDelegate(config));
};
