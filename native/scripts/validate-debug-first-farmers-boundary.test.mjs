import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const nativeRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const iosRoot = join(nativeRoot, 'ios');

async function source(path) {
  return readFile(join(iosRoot, path), 'utf8');
}

test('unsigned development repository and loader remain DEBUG-only', async () => {
  for (const path of [
    'Sources/JourneyContent/DevelopmentFirstFarmersRepository.swift',
    'Sources/JourneyApp/DevelopmentFirstFarmersAppContent.swift',
  ]) {
    const text = (await source(path)).trim();
    assert.ok(text.startsWith('#if DEBUG'), `${path} must begin at the DEBUG boundary`);
    assert.ok(text.endsWith('#endif'), `${path} must end at the DEBUG boundary`);
  }
});

test('generated development payload resources stay outside Release and live-test trust', async () => {
  const project = await source('project.yml');
  const journeyApp = project.slice(
    project.indexOf('  JourneyApp:'),
    project.indexOf('  AssetDownloaderExtension:'),
  );
  const liveTestConfig = journeyApp.slice(
    journeyApp.indexOf('        NON_SHIPPING_LIVE_TEST:'),
    journeyApp.indexOf('        Release:'),
  );
  const releaseConfig = journeyApp.slice(journeyApp.indexOf('        Release:'));
  for (const resource of [
    'first-farmers.content-package.json',
    'first-farmers.payload-receipt.json',
  ]) {
    assert.ok(project.includes(`path: ../phase2/generated/${resource}`));
    assert.ok(liveTestConfig.includes(`            - ${resource}`));
    assert.ok(releaseConfig.includes(`            - ${resource}`));
  }
});

test('signed fixture has one explicit release-optimized non-shipping trust domain', async () => {
  const project = await source('project.yml');
  const loader = (await source(
    'Sources/JourneyApp/DevelopmentSignedRuntimeFixtureAppContent.swift',
  )).trim();
  const rootView = await source('Sources/JourneyApp/RootView.swift');
  const model = await source('Sources/JourneyApp/JourneyModel.swift');
  const repository = await source('Sources/JourneyContent/ContentRepository.swift');

  assert.match(
    project,
    /^configs:\n  Debug: debug\n  Release: release\n  NON_SHIPPING_LIVE_TEST: release$/m,
  );
  assert.match(
    project,
    /NON_SHIPPING_LIVE_TEST:\n\s+PRODUCT_BUNDLE_IDENTIFIER: com\.thelongwest\.journey\.nonshippinglivetest\n\s+PRODUCT_DISPLAY_NAME: EUROCENTRIC LIVE TEST\n\s+SWIFT_ACTIVE_COMPILATION_CONDITIONS: "\$\(inherited\) NON_SHIPPING_LIVE_TEST"\n\s+SWIFT_OPTIMIZATION_LEVEL: "-O"/,
  );
  assert.match(
    project,
    /LongWestJourneyLiveTest:[\s\S]*?run:\n\s+config: NON_SHIPPING_LIVE_TEST\n\s+debugEnabled: false[\s\S]*?profile:\n\s+config: NON_SHIPPING_LIVE_TEST[\s\S]*?archive:\n\s+config: Release/,
  );

  assert.ok(loader.startsWith('#if DEBUG || NON_SHIPPING_LIVE_TEST'));
  assert.ok(loader.endsWith('#endif'));
  assert.match(
    loader,
    /private static let trustDomain = "the-long-west-vertical-slice-development-v1"/,
  );
  assert.match(loader, /receipt\.trustDomain == trustDomain/);
  assert.match(
    rootView,
    /#if DEBUG \|\| NON_SHIPPING_LIVE_TEST\n\s+let fixtureClient:[\s\S]*?DevelopmentSignedRuntimeFixtureAppContent\.makeClient\(\)/,
  );
  assert.match(
    model,
    /#if DEBUG \|\| NON_SHIPPING_LIVE_TEST(?:(?!#endif)[\s\S])*?private func appendSignedRuntimeFixtureSeekActions/,
  );
  assert.match(
    repository,
    /#if DEBUG \|\| NON_SHIPPING_LIVE_TEST[\s\S]{0,500}public init\(developmentVerticalSlice/,
  );
});

test('ordinary Release still excludes the signed fixture and its trust receipt', async () => {
  const project = await source('project.yml');
  assert.doesNotMatch(project, /distribution-cache|distribution-coding-v1/);
  const journeyApp = project.slice(
    project.indexOf('  JourneyApp:'),
    project.indexOf('  AssetDownloaderExtension:'),
  );
  const liveTestConfig = journeyApp.slice(
    journeyApp.indexOf('        NON_SHIPPING_LIVE_TEST:'),
    journeyApp.indexOf('        Release:'),
  );
  const releaseConfig = journeyApp.slice(journeyApp.indexOf('        Release:'));
  for (const resource of [
    'vertical-slice-development-v1.runtimefixture',
    'vertical-slice-development-trust-receipt.json',
  ]) {
    assert.doesNotMatch(liveTestConfig, new RegExp(`- ${resource.replace('.', '\\.')}`));
    assert.ok(releaseConfig.includes(`            - ${resource}`));
  }
});

test('live-test signing is isolated from production push, CloudKit and app-group state', async () => {
  const project = await source('project.yml');
  const liveEntitlements = await source('Config/NonShippingLiveTest.entitlements');
  const productionAppEntitlements = await source('Config/JourneyApp.entitlements');
  const productionExtensionEntitlements = await source(
    'Config/AssetDownloaderExtension.entitlements',
  );
  const composition = await source(
    'Sources/JourneyApp/JourneyReleaseDiscoveryComposition.swift',
  );
  const liveComposition = composition.slice(
    composition.indexOf('#if NON_SHIPPING_LIVE_TEST'),
    composition.indexOf('#else', composition.indexOf('#if NON_SHIPPING_LIVE_TEST')),
  );

  assert.match(
    liveEntitlements,
    /<string>group\.com\.thelongwest\.journey\.nonshippinglivetest\.assets<\/string>/,
  );
  assert.doesNotMatch(liveEntitlements, /aps-environment|icloud|CloudKit/iu);
  assert.doesNotMatch(
    liveEntitlements,
    /<string>group\.com\.thelongwest\.journey\.assets<\/string>/,
  );
  assert.match(productionAppEntitlements, /<key>aps-environment<\/key>/);
  assert.match(productionAppEntitlements, /iCloud\.com\.thelongwest\.journey/);
  assert.match(
    productionAppEntitlements,
    /<string>group\.com\.thelongwest\.journey\.assets<\/string>/,
  );
  assert.match(
    productionExtensionEntitlements,
    /<string>group\.com\.thelongwest\.journey\.assets<\/string>/,
  );

  assert.match(
    project,
    /BAAppGroupID: "\$\(BACKGROUND_ASSETS_APP_GROUP_ID\)"/,
  );
  assert.match(
    project,
    /BACKGROUND_ASSETS_APP_GROUP_ID: group\.com\.thelongwest\.journey\.assets/,
  );
  assert.match(
    project,
    /CODE_SIGN_ENTITLEMENTS: Config\/NonShippingLiveTest\.entitlements\n\s+BACKGROUND_ASSETS_APP_GROUP_ID: group\.com\.thelongwest\.journey\.nonshippinglivetest\.assets/,
  );
  assert.equal(
    project.match(/CODE_SIGN_ENTITLEMENTS: Config\/NonShippingLiveTest\.entitlements/gu)
      ?.length,
    2,
  );
  assert.match(
    liveComposition,
    /applicationModel: ReleaseDiscoveryApplicationModel\(\),\n\s+futureReleaseClient: nil/,
  );
  assert.doesNotMatch(
    liveComposition,
    /CloudKit|makeApple|RemoteNotification|UIApplication/,
  );
});

test('live-test bootstrap compiles out Apple commerce while Debug and Release retain it', async () => {
  const model = await source('Sources/JourneyApp/JourneyModel.swift');
  const bootstrap = model.slice(
    model.indexOf('    func bootstrap() async {'),
    model.indexOf('    private func beginObservingRuntimeContent() async {'),
  );
  const appleCommerceBootstrap = bootstrap.match(
    /#if !NON_SHIPPING_LIVE_TEST\n([\s\S]*?)#endif/g,
  ) ?? [];

  assert.equal(appleCommerceBootstrap.length, 2);
  assert.match(
    appleCommerceBootstrap[0],
    /await prepareCommerceForRestoration\(\)/,
  );
  assert.match(
    appleCommerceBootstrap[1],
    /await configureCommerceAfterRestoration\(\)/,
  );
  assert.doesNotMatch(
    bootstrap.replaceAll(/#if !NON_SHIPPING_LIVE_TEST\n[\s\S]*?#endif/g, ''),
    /prepareCommerceForRestoration|configureCommerceAfterRestoration/,
  );

  const commerceImplementation = model.slice(
    model.indexOf('#if !NON_SHIPPING_LIVE_TEST\n    /// Loads only the authenticated local ownership snapshot'),
    model.indexOf('    private func applyEntitlementSnapshot'),
  );
  assert.ok(commerceImplementation.startsWith('#if !NON_SHIPPING_LIVE_TEST'));
  assert.match(commerceImplementation, /StoreKit2Provider\(\)/);
  assert.match(commerceImplementation, /commerceClient\.productDetails\(\)/);
  assert.match(
    commerceImplementation,
    /commerceClient\.refreshCurrentEntitlements\(\)/,
  );
  assert.ok(commerceImplementation.trimEnd().endsWith('#endif'));
});

test('app chapter route is coordinator-driven and the public content tree remains empty', async () => {
  const model = await source('Sources/JourneyApp/JourneyModel.swift');
  const rootView = await source('Sources/JourneyApp/RootView.swift');
  assert.match(model, /ChapterCoordinator/);
  assert.match(model, /advanceActions\(state: committedState\)/);
  assert.doesNotMatch(rootView, /ChapterFoundationView/);

  const publicRoot = join(nativeRoot, 'content/public');
  if (existsSync(publicRoot)) {
    const entries = await readdir(publicRoot, { recursive: true });
    assert.deepEqual(entries, []);
  }
});
