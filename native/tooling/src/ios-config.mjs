import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";
import { ValidationError } from "./validate.mjs";

const execFileAsync = promisify(execFile);
const requiredCapabilities = new Set([
  "arm64",
  "metal",
  "iphone-performance-gaming-tier",
]);
const requiredBackgroundModes = new Set(["fetch", "remote-notification"]);
const assetAppGroupID = "group.com.thelongwest.journey.assets";
const cloudContainerID = "iCloud.com.thelongwest.journey";

export function validateIOSPlist(plist, expectedDisplayName) {
  const issues = [];
  const capabilities = new Set(plist.UIRequiredDeviceCapabilities ?? []);
  if (
    capabilities.size !== requiredCapabilities.size
    || [...requiredCapabilities].some((capability) => !capabilities.has(capability))
  ) {
    issues.push("Info.plist: required capabilities must be arm64, metal and iphone-performance-gaming-tier");
  }
  if (
    !Array.isArray(plist.UISupportedInterfaceOrientations)
    || plist.UISupportedInterfaceOrientations.length !== 1
    || plist.UISupportedInterfaceOrientations[0] !== "UIInterfaceOrientationPortrait"
  ) {
    issues.push("Info.plist: launch orientation must be iPhone portrait only");
  }
  if (
    plist.CFBundleDisplayName !== expectedDisplayName
    && plist.CFBundleDisplayName !== "$(PRODUCT_DISPLAY_NAME)"
  ) {
    issues.push("Info.plist: display name must come from locked product metadata");
  }
  if (!plist.UILaunchScreen || Array.isArray(plist.UILaunchScreen) || typeof plist.UILaunchScreen !== "object") {
    issues.push("Info.plist: UILaunchScreen dictionary is required to avoid compatibility letterboxing");
  }
  if (plist.LSRequiresIPhoneOS !== true) {
    issues.push("Info.plist: LSRequiresIPhoneOS must be true");
  }
  if (plist.BAAppGroupID !== assetAppGroupID) {
    issues.push(`Info.plist: BAAppGroupID must be ${assetAppGroupID}`);
  }
  if (plist.BAHasManagedAssetPacks !== true || plist.BAUsesAppleHosting !== true) {
    issues.push("Info.plist: managed Apple-hosted Background Assets must remain enabled");
  }
  const backgroundModes = new Set(plist.UIBackgroundModes ?? []);
  if (
    backgroundModes.size !== requiredBackgroundModes.size
    || [...requiredBackgroundModes].some((mode) => !backgroundModes.has(mode))
  ) {
    issues.push("Info.plist: CloudKit release hints require fetch and remote-notification modes");
  }
  if (issues.length) throw new ValidationError(issues);
  return plist;
}

export function validateAppleServiceConfiguration({
  appEntitlements,
  extensionEntitlements,
  extensionPlist,
}) {
  const issues = [];
  const exactArray = (actual, expected) => (
    Array.isArray(actual)
    && actual.length === expected.length
    && expected.every((item) => actual.includes(item))
  );
  if (
    !exactArray(
      appEntitlements["com.apple.security.application-groups"],
      [assetAppGroupID],
    )
  ) {
    issues.push("JourneyApp entitlements: Background Assets app group drifted");
  }
  if (
    !exactArray(
      extensionEntitlements["com.apple.security.application-groups"],
      [assetAppGroupID],
    )
  ) {
    issues.push("AssetDownloaderExtension entitlements: shared app group drifted");
  }
  if (
    !exactArray(
      appEntitlements["com.apple.developer.icloud-container-identifiers"],
      [cloudContainerID],
    )
    || !exactArray(appEntitlements["com.apple.developer.icloud-services"], ["CloudKit"])
  ) {
    issues.push("JourneyApp entitlements: CloudKit container or service drifted");
  }
  if (!new Set(["development", "production"]).has(appEntitlements["aps-environment"])) {
    issues.push("JourneyApp entitlements: aps-environment is missing or invalid");
  }
  if (
    extensionPlist.EXAppExtensionAttributes?.EXExtensionPointIdentifier
    !== "com.apple.background-asset-downloader-extension"
  ) {
    issues.push("AssetDownloaderExtension: extension point drifted");
  }
  if (issues.length) throw new ValidationError(issues);
  return {
    assetAppGroupID,
    cloudContainerID,
    sourceAPSEnvironment: appEntitlements["aps-environment"],
  };
}

export async function validateIOSConfiguration(root) {
  const nativeRoot = path.dirname(root);
  const product = JSON.parse(await readFile(path.join(nativeRoot, "product.json"), "utf8"));
  const projectPath = path.join(root, "project.yml");
  const plistPath = path.join(root, "Config", "Info.plist");
  const appEntitlementsPath = path.join(root, "Config", "JourneyApp.entitlements");
  const extensionEntitlementsPath = path.join(
    root,
    "Config",
    "AssetDownloaderExtension.entitlements",
  );
  const extensionPlistPath = path.join(root, "Config", "AssetDownloaderExtension-Info.plist");
  const project = await readFile(projectPath, "utf8");
  const { stdout } = await execFileAsync("plutil", ["-convert", "json", "-o", "-", plistPath]);
  const plist = validateIOSPlist(JSON.parse(stdout), product.displayName);
  const [appEntitlementsResult, extensionEntitlementsResult, extensionPlistResult] =
    await Promise.all([
      execFileAsync("plutil", ["-convert", "json", "-o", "-", appEntitlementsPath]),
      execFileAsync("plutil", ["-convert", "json", "-o", "-", extensionEntitlementsPath]),
      execFileAsync("plutil", ["-convert", "json", "-o", "-", extensionPlistPath]),
    ]);
  const appleServices = validateAppleServiceConfiguration({
    appEntitlements: JSON.parse(appEntitlementsResult.stdout),
    extensionEntitlements: JSON.parse(extensionEntitlementsResult.stdout),
    extensionPlist: JSON.parse(extensionPlistResult.stdout),
  });
  const issues = [];

  if (!/deploymentTarget:\s*[\s\S]*?iOS:\s*["']26\.4["']/.test(project)) {
    issues.push("project.yml: iOS deployment target must remain 26.4");
  }
  if (!/SWIFT_STRICT_CONCURRENCY:\s*complete/.test(project)) {
    issues.push("project.yml: Swift strict concurrency must remain complete");
  }
  const appStart = project.indexOf("  JourneyApp:\n");
  const testsStart = project.indexOf("  LongWestNativeTests:\n", appStart);
  const appTarget = appStart >= 0 ? project.slice(appStart, testsStart >= 0 ? testsStart : undefined) : "";
  if (!/TARGETED_DEVICE_FAMILY:\s*["']1["']/.test(appTarget)) {
    issues.push("project.yml: JourneyApp must explicitly target device family 1");
  }
  if (issues.length) throw new ValidationError(issues);
  await execFileAsync("node", [path.join(nativeRoot, "scripts", "sync-product-metadata.mjs"), "--check"]);
  return {
    deploymentTarget: "26.4",
    displayName: product.displayName,
    capabilities: [...requiredCapabilities].sort(),
    orientation: "portrait",
    appleServices,
  };
}
