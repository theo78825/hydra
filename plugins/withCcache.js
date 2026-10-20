/**
 * Compiles the iOS pods through ccache, so a fresh worktree or a
 * `prebuild --clean` stops recompiling ~170 pods of C/C++/Obj-C from scratch.
 *
 * The generated Podfile already has `ccache_enabled?`, which reads
 * `apple.ccacheEnabled` from ios/Podfile.properties.json and hands it to
 * react_native_post_install. Setting it here, rather than editing ios/, is what
 * makes it survive `expo prebuild --clean`. It does the same job as
 * expo-build-properties' `ios.ccacheEnabled`, without adding a prebuilt Expo
 * module whose version has to match expo-modules-core.
 *
 * ccache is optional: if it isn't installed the property is left unset, so the
 * Podfile doesn't point the compiler at a binary that isn't there. USE_CCACHE=0
 * in the environment still overrides it at `pod install` time.
 */
const { execSync } = require("child_process");
const { withPodfileProperties } = require("expo/config-plugins");

function hasCcache() {
  try {
    execSync("command -v ccache", { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

module.exports = function withCcache(config) {
  return withPodfileProperties(config, (cfg) => {
    if (hasCcache()) {
      cfg.modResults["apple.ccacheEnabled"] = "true";
    }
    return cfg;
  });
};
