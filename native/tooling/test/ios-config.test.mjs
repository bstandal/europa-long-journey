import assert from "node:assert/strict";
import test from "node:test";

import { validateIOSPlist } from "../src/ios-config.mjs";

function validBuildSettingPlist() {
  return {
    BAAppGroupID: "$(BACKGROUND_ASSETS_APP_GROUP_ID)",
    BAHasManagedAssetPacks: true,
    BAUsesAppleHosting: true,
    CFBundleDisplayName: "EUROCENTRIC",
    LSRequiresIPhoneOS: true,
    UIBackgroundModes: ["fetch", "remote-notification"],
    UILaunchScreen: {},
    UIRequiredDeviceCapabilities: [
      "arm64",
      "metal",
      "iphone-performance-gaming-tier",
    ],
    UISupportedInterfaceOrientations: ["UIInterfaceOrientationPortrait"],
  };
}

test("accepts only the locked per-configuration Background Assets setting", () => {
  const plist = validBuildSettingPlist();
  assert.equal(
    validateIOSPlist(plist, "EUROCENTRIC").BAAppGroupID,
    "$(BACKGROUND_ASSETS_APP_GROUP_ID)",
  );
  plist.BAAppGroupID = "$(ARBITRARY_APP_GROUP_ID)";
  assert.throws(
    () => validateIOSPlist(plist, "EUROCENTRIC"),
    /locked build setting/,
  );
});
