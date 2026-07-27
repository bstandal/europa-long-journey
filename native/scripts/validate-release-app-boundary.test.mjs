import assert from 'node:assert/strict';
import {
  createHash,
  createSign,
  generateKeyPairSync,
} from 'node:crypto';
import { execFile } from 'node:child_process';
import {
  cp,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

import {
  forbiddenReleaseBasenames,
  forbiddenReleaseByteSequences,
  forbiddenReleaseExtensions,
  enforceReleaseCandidateByteBudgets,
  requireReleaseByteBudgetAuthorityWithinLockedCeilings,
  releaseValidationModes,
  validateReleaseAppBoundary,
} from './validate-release-app-boundary.mjs';

const execFileAsync = promisify(execFile);
const scriptPath = fileURLToPath(new URL('./validate-release-app-boundary.mjs', import.meta.url));
const signedRuntimeFixtureRoot = fileURLToPath(new URL(
  '../phase2/runtime-fixture/compiled/vertical-slice-development-v1.runtimefixture',
  import.meta.url,
));
const signedRuntimeFixtureReceipt = fileURLToPath(new URL(
  '../phase2/runtime-fixture/vertical-slice-development-trust-receipt.json',
  import.meta.url,
));
const version = { major: 1, minor: 0, patch: 0 };
const essentialChapterIDs = [
  'first-farmers',
  'europe-holds-the-line',
  'european-world',
];

async function withApp(run) {
  const root = await mkdtemp(join(tmpdir(), 'long-west-release-boundary-'));
  const app = join(root, 'LongWestJourney.app');
  await mkdir(app);
  try {
    await run(app, root);
  } finally {
    await rm(root, { force: true, recursive: true });
  }
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonical(value[key])]),
    );
  }
  return value;
}

function canonicalJSON(value) {
  return Buffer.from(JSON.stringify(canonical(value)), 'utf8');
}

function hash(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

const deliveryPlanPath = fileURLToPath(new URL(
  '../blueprint/delivery-plan.json',
  import.meta.url,
));
const deliveryPlanBytes = await readFile(deliveryPlanPath);
const deliveryPlan = JSON.parse(deliveryPlanBytes);
const essentialDeliveryRecord = deliveryPlan.packages.find(
  (record) => record.packageID === 'essential-free-v1',
);
const byteBudgetAuthority = Object.freeze({
  appBundleMaximumBytes:
    deliveryPlan.budgets.shellAndEngineBytes + essentialDeliveryRecord.maximumInstalledBytes,
  essentialPackageMaximumBytes: essentialDeliveryRecord.maximumInstalledBytes,
  shellAndEngineMaximumBytes: deliveryPlan.budgets.shellAndEngineBytes,
});
const deliveryPlanSHA256 = hash(deliveryPlanBytes);
const boundaryOnlyOptions = Object.freeze({
  mode: releaseValidationModes.boundaryOnly,
});

function productionTrustFixture() {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const jwk = publicKey.export({ format: 'jwk' });
  const x963 = Buffer.concat([
    Buffer.from([0x04]),
    Buffer.from(jwk.x, 'base64url'),
    Buffer.from(jwk.y, 'base64url'),
  ]);
  const trust = canonicalJSON({
    schemaVersion: 1,
    keys: [{
      id: 'launch-2026-a',
      x963PublicKeyBase64: x963.toString('base64'),
    }],
  });
  const receipt = canonicalJSON({
    schemaVersion: 1,
    trustFileSHA256: hash(trust),
    keys: [{
      id: 'launch-2026-a',
      x963PublicKeySHA256: hash(x963),
    }],
  });
  return { privateKey, publicKey, receipt, trust, x963 };
}

function localized(id, launchEnglish) {
  return { id, launchEnglish };
}

function essentialContentDocument(chapterIDs = essentialChapterIDs) {
  const worldNodeID = 'essential-world-anchor';
  return {
    schemaVersion: version,
    packageID: 'essential-free-v1',
    worldSeed: {
      nodes: [{
        id: worldNodeID,
        kind: 'institution',
        form: 'The bundled historical world',
        position: { x: 0.5, y: 0.5 },
        attributes: [],
      }],
      traces: [],
    },
    chapters: chapterIDs.map((chapterID, index) => ({
      schemaVersion: version,
      id: chapterID,
      title: localized(`${chapterID}-title`, `Chapter ${index + 1}`),
      period: localized(`${chapterID}-period`, `Period ${index + 1}`),
      arcs: [{
        id: `${chapterID}-arc`,
        title: localized(`${chapterID}-arc-title`, `Arc ${index + 1}`),
        targetDurationMinutes: 8,
        situation: localized(`${chapterID}-situation`, 'A historical order stands in place.'),
        mechanism: localized(`${chapterID}-mechanism`, 'Named institutions carry action.'),
        turn: localized(`${chapterID}-turn`, 'The inherited arrangement changes.'),
        consequence: localized(`${chapterID}-consequence`, 'The result remains in the world.'),
        handoff: localized(`${chapterID}-handoff`, 'The road continues from altered ground.'),
        beats: [{
          id: `${chapterID}-beat`,
          sceneID: 'essential-scene',
          narrative: {
            heading: localized(`${chapterID}-heading`, `The ground of chapter ${index + 1}`),
            paragraphs: [localized(
              `${chapterID}-paragraph-1`,
              'People act through the material order around them.',
            )],
          },
          narrationCueIDs: [],
          completionEffects: [],
          checkpoint: 'onExit',
        }],
      }],
      completionEffects: [{
        id: `effect-${chapterID}`,
        mutation: 'transform-node',
        nodeID: worldNodeID,
        form: `The world after chapter ${index + 1}`,
        attributes: [{ key: `completed-${index + 1}`, value: true }],
      }],
    })),
    scenes: [{
      id: 'essential-scene',
      sceneCanvas: {
        canvas: { width: 1200, height: 2600 },
        cameraTravelBounds: { x: 0.2, y: 0.2, width: 0.6, height: 0.6 },
        authoredOverscanFraction: 0.15,
        viewportCrops: [{
          id: 'baseline-393x852',
          viewport: { widthPoints: 393, heightPoints: 852 },
          sourceRect: { x: 0.05, y: 0.05, width: 0.9, height: 0.9 },
          safeTextRegions: [{
            id: 'opening-copy',
            rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.22 },
          }],
        }],
      },
      layers: [{
        id: 'landscape',
        order: 0,
        assetPath: 'assets/world.heif',
        frame: { x: 0, y: 0, width: 1, height: 1 },
        depth: 0.2,
        opacity: 1,
        blendMode: 'normal',
        masks: {},
        motion: { parallaxFactor: 0.1, windResponse: 0.1, focusResponse: 0.1 },
        stateVariants: [],
      }],
      cameraRail: {
        keyframes: [
          { progress: 0, center: { x: 0.45, y: 0.5 }, scale: 1 },
          { progress: 1, center: { x: 0.55, y: 0.45 }, scale: 1.05 },
        ],
      },
      atmosphere: [],
      interactionTargets: [],
      reduceMotionComposition: {
        canvas: { width: 1200, height: 2600 },
        strata: [{
          id: 'static-world',
          kind: 'staticPlate',
          assetPath: 'assets/world-reduce.heif',
        }],
        viewportCrops: [{
          id: 'baseline-393x852',
          viewport: { widthPoints: 393, heightPoints: 852 },
          sourceRect: { x: 0.05, y: 0.05, width: 0.9, height: 0.9 },
          safeTextRegions: [{
            id: 'opening-copy',
            rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.22 },
          }],
        }],
      },
      mechanismFocus: localized('essential-focus', 'The changed institution'),
      accessibilityID: 'essential-access',
    }],
    audioTimelines: [{
      id: 'essential-audio',
      sampleRate: 48_000,
      events: [{
        cueID: 'essential-silence',
        role: 'silence',
        startSample: 0,
        durationSamples: 48_000,
        gain: 0,
      }],
      haptics: [],
    }],
    responsiveAudioPrograms: [],
    accessibility: [{
      id: 'essential-access',
      sceneSummary: localized('essential-summary', 'A historical institution changes.'),
      elements: [{
        id: 'essential-image',
        role: 'image',
        label: localized('essential-image-label', 'The changing historical world'),
        actions: [],
      }],
    }],
  };
}

function manifestMaterial(manifest) {
  return [
    'long-west-package-v1',
    `packageID=${manifest.packageID}`,
    'packageVersion=1.0.0',
    'schemaVersion=1.0.0',
    'minimumRuntime=1.0.0',
    ...manifest.files.map((record) =>
      `file=${record.path}\t${record.bytes}\t${record.sha256}`),
    '',
  ].join('\n');
}

function signedManifest(files, trustFixture, mutateManifest = undefined) {
  const unsigned = {
    packageID: 'essential-free-v1',
    packageVersion: version,
    schemaVersion: version,
    minimumRuntime: version,
    files,
  };
  if (mutateManifest) mutateManifest(unsigned);
  const manifestDigest = hash(Buffer.from(manifestMaterial(unsigned), 'utf8'));
  const signer = createSign('SHA256');
  signer.update(Buffer.from(manifestDigest, 'utf8'));
  signer.end();
  return {
    ...unsigned,
    manifestDigest,
    signature: {
      algorithm: 'P-256-SHA256',
      keyID: 'launch-2026-a',
      value: signer.sign({
        key: trustFixture.privateKey,
        dsaEncoding: 'der',
      }).toString('base64'),
    },
  };
}

function essentialReceiptFixture(packageFixture) {
  return canonicalJSON({
    schemaVersion: 1,
    status: 'APPROVED_BY_EDITOR_IN_CHIEF',
    authority: 'editor-in-chief',
    approvedAt: '2026-07-25T08:00:00Z',
    decisionReference: 'test-only-essential-package-approval',
    packageID: 'essential-free-v1',
    chapterIDs: essentialChapterIDs,
    deliveryPlanSHA256,
    packageManifestSHA256: hash(packageFixture.manifestBytes),
    manifestDigest: packageFixture.manifest.manifestDigest,
    payloadPath: packageFixture.payloadPath,
    payloadSHA256: hash(packageFixture.payloadBytes),
  });
}

async function writeEssentialPackage(app, trustFixture, {
  chapterIDs = essentialChapterIDs,
  mutatePayload,
  mutateManifest,
} = {}) {
  const packageRoot = join(app, 'JourneyContent', 'essential-free-v1');
  const payloadPath = 'chapters/essential-free-v1.json';
  const payloadDocument = essentialContentDocument(chapterIDs);
  if (mutatePayload) mutatePayload(payloadDocument);
  const payloadBytes = Buffer.from(`${JSON.stringify(payloadDocument, null, 2)}\n`, 'utf8');
  const assets = new Map([
    ['assets/world-reduce.heif', Buffer.from('essential-reduce-motion-plate')],
    ['assets/world.heif', Buffer.from('essential-scene-layer')],
    [payloadPath, payloadBytes],
  ]);
  const records = [...assets].map(([path, bytes]) => ({
    path,
    bytes: bytes.byteLength,
    sha256: hash(bytes),
  })).sort((left, right) => Buffer.compare(Buffer.from(left.path), Buffer.from(right.path)));
  const manifest = signedManifest(records, trustFixture, mutateManifest);
  const manifestBytes = Buffer.from(`${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
  for (const [path, bytes] of assets) {
    const file = join(packageRoot, ...path.split('/'));
    await mkdir(dirname(file), { recursive: true });
    await writeFile(file, bytes);
  }
  await writeFile(join(packageRoot, 'package-manifest.json'), manifestBytes);
  return { packageRoot, payloadPath, payloadBytes, manifest, manifestBytes };
}

async function writeReleaseCandidateResources(app, root, packageOptions = {}) {
  const fixture = productionTrustFixture();
  const receiptPath = join(root, 'approved-trust-receipt.json');
  const essentialReceiptPath = join(root, 'approved-essential-receipt.json');
  await writeFile(join(app, 'launch-package-trust.json'), fixture.trust);
  const essentialPackage = await writeEssentialPackage(app, fixture, packageOptions);
  await writeFile(receiptPath, fixture.receipt);
  await writeFile(essentialReceiptPath, essentialReceiptFixture(essentialPackage));
  return {
    ...fixture,
    ...essentialPackage,
    receiptPath,
    essentialReceiptPath,
  };
}

test('accepts a clean release app bundle in boundary-only mode', async () => {
  await withApp(async (app) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    await assert.rejects(
      validateReleaseAppBoundary(app),
      /Unknown release validation mode: undefined/,
    );
    const result = await validateReleaseAppBoundary(app, boundaryOnlyOptions);
    assert.equal(result.status, 'PASS_BOUNDARY_ONLY_NON_SHIPPING');
    assert.equal(result.mode, releaseValidationModes.boundaryOnly);
  });
});

test('rejects every DEBUG-only resource basename', async () => {
  for (const forbidden of forbiddenReleaseBasenames) {
    await withApp(async (app) => {
      await writeFile(join(app, forbidden), '{}');
      await assert.rejects(
        validateReleaseAppBoundary(app, boundaryOnlyOptions),
        /DEBUG-only resource/,
      );
    });
  }
});

test('rejects every key, test and config extension', async () => {
  for (const extension of forbiddenReleaseExtensions) {
    await withApp(async (app) => {
      await writeFile(join(app, `renamed-material${extension}`), 'opaque');
      await assert.rejects(
        validateReleaseAppBoundary(app, boundaryOnlyOptions),
        /forbidden key, test or config file/,
      );
    });
  }
});

test('rejects every DEBUG-only byte sequence in arbitrary app files', async () => {
  for (const forbidden of forbiddenReleaseByteSequences) {
    await withApp(async (app) => {
      await writeFile(join(app, 'LongWestJourney'), `prefix\0${forbidden}\0suffix`);
      await assert.rejects(
        validateReleaseAppBoundary(app, boundaryOnlyOptions),
        /DEBUG-only bytes/,
      );
    });
  }
});

test('rejects the exact signed runtime fixture and trust receipt after renaming', async () => {
  await withApp(async (app) => {
    await cp(signedRuntimeFixtureRoot, join(app, 'opaque-content'), {
      recursive: true,
    });
    await assert.rejects(
      validateReleaseAppBoundary(app, boundaryOnlyOptions),
      /DEBUG-only (?:bytes|resource)/,
    );
  });

  await withApp(async (app) => {
    await cp(signedRuntimeFixtureReceipt, join(app, 'opaque-receipt.bin'));
    await assert.rejects(
      validateReleaseAppBoundary(app, boundaryOnlyOptions),
      /DEBUG-only bytes/,
    );
  });
});

test('rejects a binary private key even after it is renamed', async () => {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const key = privateKey.export({ format: 'der', type: 'pkcs8' });
  await withApp(async (app) => {
    await writeFile(join(app, 'innocent-looking-resource.bin'), key);
    await assert.rejects(
      validateReleaseAppBoundary(app, boundaryOnlyOptions),
      /private signing material/,
    );
  });
});

test('rejects JWK private material even after it is renamed', async () => {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const jwk = privateKey.export({ format: 'jwk' });
  await withApp(async (app) => {
    await writeFile(join(app, 'catalog.bin'), JSON.stringify(jwk));
    await assert.rejects(
      validateReleaseAppBoundary(app, boundaryOnlyOptions),
      /private signing material/,
    );
  });
});

test('release-candidate mode requires approved trust and accepts actual bytes within budget', async () => {
  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    await assert.rejects(
      validateReleaseAppBoundary(app, { mode: releaseValidationModes.releaseCandidate }),
      /exactly one launch-package-trust/,
    );

    const fixture = await writeReleaseCandidateResources(app, root);
    const result = await validateReleaseAppBoundary(app, {
      mode: releaseValidationModes.releaseCandidate,
      approvedTrustReceiptPath: fixture.receiptPath,
      approvedEssentialReceiptPath: fixture.essentialReceiptPath,
    });
    assert.equal(result.status, 'PASS');
    assert.equal(result.mode, releaseValidationModes.releaseCandidate);
    const expectedEssentialBytes = fixture.manifestBytes.byteLength
      + fixture.manifest.files.reduce((total, record) => total + record.bytes, 0);
    const expectedShellBytes = 4 + fixture.trust.byteLength;
    const { appBundleFileTreeSHA256, ...measuredBudget } = result.byteBudget;
    assert.match(appBundleFileTreeSHA256, /^[a-f0-9]{64}$/u);
    assert.deepEqual(measuredBudget, {
      deliveryPlanSHA256,
      appBundleBytes: expectedEssentialBytes + expectedShellBytes,
      essentialPackageBytes: expectedEssentialBytes,
      shellAndEngineBytes: expectedShellBytes,
      ...byteBudgetAuthority,
    });
  });
});

test('release-candidate byte boundary rejects package, shell and complete bundle excess', () => {
  const exactBudget = {
    appBundleBytes: byteBudgetAuthority.appBundleMaximumBytes,
    essentialPackageBytes: byteBudgetAuthority.essentialPackageMaximumBytes,
    shellAndEngineBytes: byteBudgetAuthority.shellAndEngineMaximumBytes,
  };
  assert.deepEqual(
    enforceReleaseCandidateByteBudgets(exactBudget, byteBudgetAuthority),
    { ...exactBudget, ...byteBudgetAuthority },
  );

  const packageExcess = byteBudgetAuthority.essentialPackageMaximumBytes + 1;
  assert.throws(
    () => enforceReleaseCandidateByteBudgets({
      appBundleBytes: packageExcess,
      essentialPackageBytes: packageExcess,
      shellAndEngineBytes: 0,
    }, byteBudgetAuthority),
    new RegExp(
      `Bundled essential package uses ${packageExcess} bytes; delivery-plan budget `
        + `for essential-free-v1 is ${byteBudgetAuthority.essentialPackageMaximumBytes} bytes`,
      'u',
    ),
  );

  const shellExcess = byteBudgetAuthority.shellAndEngineMaximumBytes + 1;
  assert.throws(
    () => enforceReleaseCandidateByteBudgets({
      appBundleBytes: shellExcess,
      essentialPackageBytes: 0,
      shellAndEngineBytes: shellExcess,
    }, byteBudgetAuthority),
    new RegExp(
      `Release app shell and engine use ${shellExcess} bytes; delivery-plan budget `
        + `is ${byteBudgetAuthority.shellAndEngineMaximumBytes} bytes`,
      'u',
    ),
  );

  const narrowedBundleAuthority = {
    ...byteBudgetAuthority,
    appBundleMaximumBytes: byteBudgetAuthority.appBundleMaximumBytes - 1,
  };
  assert.throws(
    () => enforceReleaseCandidateByteBudgets(exactBudget, narrowedBundleAuthority),
    /Release byte-budget authority does not partition the base-install ceiling/,
  );

  for (const authority of [
    {
      shellAndEngineMaximumBytes: 100_000_001,
      essentialPackageMaximumBytes: 750_000_000,
      appBundleMaximumBytes: 850_000_001,
    },
    {
      shellAndEngineMaximumBytes: 100_000_000,
      essentialPackageMaximumBytes: 750_000_001,
      appBundleMaximumBytes: 850_000_001,
    },
    {
      shellAndEngineMaximumBytes: 100_000_000,
      essentialPackageMaximumBytes: 750_000_000,
      appBundleMaximumBytes: 850_000_001,
    },
  ]) {
    assert.throws(
      () => requireReleaseByteBudgetAuthorityWithinLockedCeilings(authority),
      /exceeds the locked 100\/750\/850 MB release ceilings/,
    );
  }
});

test('release-candidate mode rejects noncanonical, extra or unapproved trust', async () => {
  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    const fixture = productionTrustFixture();
    const trustPath = join(app, 'launch-package-trust.json');
    const receiptPath = join(root, 'approved-trust-receipt.json');
    const essentialReceiptPath = join(root, 'approved-essential-receipt.json');
    const essentialPackage = await writeEssentialPackage(app, fixture);
    await writeFile(receiptPath, fixture.receipt);
    await writeFile(
      essentialReceiptPath,
      essentialReceiptFixture(essentialPackage),
    );

    await writeFile(trustPath, Buffer.concat([fixture.trust, Buffer.from('\n')]));
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: receiptPath,
        approvedEssentialReceiptPath: essentialReceiptPath,
      }),
      /not canonical JSON/,
    );

    const parsed = JSON.parse(fixture.trust);
    parsed.keys.push({
      id: 'launch-2026-b',
      x963PublicKeyBase64: fixture.x963.toString('base64'),
    });
    await writeFile(trustPath, canonicalJSON(parsed));
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: receiptPath,
        approvedEssentialReceiptPath: essentialReceiptPath,
      }),
      /exactly one schema-v1 key/,
    );

    await writeFile(trustPath, fixture.trust);
    const wrongReceipt = JSON.parse(fixture.receipt);
    wrongReceipt.trustFileSHA256 = '0'.repeat(64);
    await writeFile(receiptPath, canonicalJSON(wrongReceipt));
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: receiptPath,
        approvedEssentialReceiptPath: essentialReceiptPath,
      }),
      /does not match the approved receipt/,
    );
  });
});

test('release-candidate mode requires one complete signed essential package root', async () => {
  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    const fixture = productionTrustFixture();
    const receiptPath = join(root, 'approved-trust-receipt.json');
    const essentialReceiptPath = join(root, 'approved-essential-receipt.json');
    await writeFile(join(app, 'launch-package-trust.json'), fixture.trust);
    await writeFile(receiptPath, fixture.receipt);
    await writeFile(
      join(app, 'essential-free-v1.content.json'),
      canonicalJSON(essentialContentDocument()),
    );

    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: receiptPath,
        approvedEssentialReceiptPath: essentialReceiptPath,
      }),
      /exactly one signed JourneyContent\/essential-free-v1 package root/,
    );
    await rm(join(app, 'essential-free-v1.content.json'));

    const incomplete = await writeEssentialPackage(app, fixture, {
      chapterIDs: essentialChapterIDs.slice(0, 2),
    });
    await writeFile(
      essentialReceiptPath,
      essentialReceiptFixture(incomplete),
    );
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: receiptPath,
        approvedEssentialReceiptPath: essentialReceiptPath,
      }),
      /ordered three included chapters/,
    );
    await rm(join(app, 'JourneyContent'), { recursive: true, force: true });

    const noncanonical = await writeEssentialPackage(app, fixture, {
      mutatePayload: (payload) => {
        payload.unexpectedPublicField = true;
      },
    });
    await writeFile(
      essentialReceiptPath,
      essentialReceiptFixture(noncanonical),
    );
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: receiptPath,
        approvedEssentialReceiptPath: essentialReceiptPath,
      }),
      /exactly one canonical public payload/,
    );
    await rm(join(app, 'JourneyContent'), { recursive: true, force: true });

    const essential = await writeEssentialPackage(app, fixture);
    const wrongEssentialReceipt = JSON.parse(essentialReceiptFixture(essential));
    wrongEssentialReceipt.packageManifestSHA256 = '0'.repeat(64);
    await writeFile(essentialReceiptPath, canonicalJSON(wrongEssentialReceipt));
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: receiptPath,
        approvedEssentialReceiptPath: essentialReceiptPath,
      }),
      /signed package does not match the exact editor-approved receipt/,
    );
  });
});

test('release-candidate mode rejects manifest, signature, inventory and file drift', async () => {
  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    const fixture = await writeReleaseCandidateResources(app, root);
    await writeFile(join(fixture.packageRoot, 'assets', 'world.heif'), 'changed bytes');
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: fixture.receiptPath,
        approvedEssentialReceiptPath: fixture.essentialReceiptPath,
      }),
      /file differs from manifest/,
    );
  });

  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    const fixture = await writeReleaseCandidateResources(app, root);
    const manifestPath = join(fixture.packageRoot, 'package-manifest.json');
    const manifest = JSON.parse(await readFile(manifestPath));
    manifest.signature.value = Buffer.from('invalid-signature').toString('base64');
    await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: fixture.receiptPath,
        approvedEssentialReceiptPath: fixture.essentialReceiptPath,
      }),
      /signature is invalid/,
    );
  });

  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    const fixture = await writeReleaseCandidateResources(app, root, {
      mutateManifest: (manifest) => manifest.files.reverse(),
    });
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: fixture.receiptPath,
        approvedEssentialReceiptPath: fixture.essentialReceiptPath,
      }),
      /canonical UTF-8 order/,
    );
  });

  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    const fixture = await writeReleaseCandidateResources(app, root, {
      mutateManifest: (manifest) => {
        manifest.files[0].path = '../foreign.heif';
      },
    });
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: fixture.receiptPath,
        approvedEssentialReceiptPath: fixture.essentialReceiptPath,
      }),
      /unsafe path/,
    );
  });

  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    const fixture = await writeReleaseCandidateResources(app, root);
    await writeFile(join(fixture.packageRoot, 'foreign.txt'), 'not signed');
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: fixture.receiptPath,
        approvedEssentialReceiptPath: fixture.essentialReceiptPath,
      }),
      /tree differs from the signed manifest inventory/,
    );
  });
});

test('release-candidate mode rejects duplicate roots, symlinks and foreign directories', async () => {
  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    const fixture = await writeReleaseCandidateResources(app, root);
    const duplicate = join(app, 'Duplicate', 'essential-free-v1');
    await mkdir(duplicate, { recursive: true });
    await writeFile(join(duplicate, 'package-manifest.json'), fixture.manifestBytes);
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: fixture.receiptPath,
        approvedEssentialReceiptPath: fixture.essentialReceiptPath,
      }),
      /exactly one signed JourneyContent\/essential-free-v1 package root/,
    );
  });

  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    const fixture = await writeReleaseCandidateResources(app, root);
    await symlink(
      join(fixture.packageRoot, 'assets', 'world.heif'),
      join(fixture.packageRoot, 'assets', 'alias.heif'),
    );
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: fixture.receiptPath,
        approvedEssentialReceiptPath: fixture.essentialReceiptPath,
      }),
      /unresolved symbolic link/,
    );
  });

  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    const fixture = await writeReleaseCandidateResources(app, root);
    await mkdir(join(fixture.packageRoot, 'empty-foreign-directory'));
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: fixture.receiptPath,
        approvedEssentialReceiptPath: fixture.essentialReceiptPath,
      }),
      /foreign or empty directory/,
    );
  });
});

test('approved essential receipt binds every required package authority field', async () => {
  const mutations = [
    (receipt) => { receipt.status = 'CODEX_PROVISIONAL_NON_SHIPPING_PRODUCTION_MASTER'; },
    (receipt) => { receipt.authority = 'codex'; },
    (receipt) => { receipt.approvedAt = 'not-a-date'; },
    (receipt) => { receipt.decisionReference = 'too-short'; },
    (receipt) => { receipt.deliveryPlanSHA256 = 'f'.repeat(64); },
    (receipt) => { receipt.packageManifestSHA256 = '0'.repeat(64); },
    (receipt) => { receipt.manifestDigest = '1'.repeat(64); },
    (receipt) => { receipt.payloadPath = 'chapters/renamed.json'; },
    (receipt) => { receipt.payloadSHA256 = '2'.repeat(64); },
    (receipt) => { receipt.packageID = 'paid-pack-01'; },
    (receipt) => { receipt.chapterIDs = [...essentialChapterIDs].reverse(); },
  ];
  for (const mutate of mutations) {
    await withApp(async (app, root) => {
      await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
      const fixture = await writeReleaseCandidateResources(app, root);
      const receipt = JSON.parse(await readFile(fixture.essentialReceiptPath));
      mutate(receipt);
      await writeFile(fixture.essentialReceiptPath, canonicalJSON(receipt));
      await assert.rejects(
        validateReleaseAppBoundary(app, {
          mode: releaseValidationModes.releaseCandidate,
          approvedTrustReceiptPath: fixture.receiptPath,
          approvedEssentialReceiptPath: fixture.essentialReceiptPath,
        }),
        /signed package does not match the exact editor-approved receipt/,
      );
    });
  }
});

test('approved essential receipt remains canonical and external to the app', async () => {
  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    const fixture = await writeReleaseCandidateResources(app, root);
    const receiptBytes = await readFile(fixture.essentialReceiptPath);
    await writeFile(
      fixture.essentialReceiptPath,
      Buffer.concat([receiptBytes, Buffer.from('\n')]),
    );
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: fixture.receiptPath,
        approvedEssentialReceiptPath: fixture.essentialReceiptPath,
      }),
      /Approved essential-package receipt is not canonical JSON/,
    );
  });

  await withApp(async (app, root) => {
    await writeFile(join(app, 'LongWestJourney'), Buffer.from([0, 1, 2, 3]));
    const fixture = await writeReleaseCandidateResources(app, root);
    const inBundleReceipt = join(app, 'approved-essential-receipt.json');
    await writeFile(inBundleReceipt, await readFile(fixture.essentialReceiptPath));
    await assert.rejects(
      validateReleaseAppBoundary(app, {
        mode: releaseValidationModes.releaseCandidate,
        approvedTrustReceiptPath: fixture.receiptPath,
        approvedEssentialReceiptPath: inBundleReceipt,
      }),
      /must remain outside the app bundle/,
    );
  });
});

test('CLI help names the signed essential root and external approval receipt', async () => {
  await assert.rejects(
    execFileAsync(process.execPath, [scriptPath]),
    (error) => error.code === 1
      && /--approved-essential-receipt <external-path\.json>/u.test(error.stderr)
      && /JourneyContent\/essential-free-v1\/package-manifest\.json/u.test(error.stderr),
  );
});

test('rejects a path that is not a built app directory', async () => {
  const root = await mkdtemp(join(tmpdir(), 'long-west-release-boundary-'));
  try {
    await assert.rejects(validateReleaseAppBoundary(root), /built \.app directory/);
  } finally {
    await rm(root, { force: true, recursive: true });
  }
});
