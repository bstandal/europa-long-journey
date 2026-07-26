import assert from "node:assert/strict";
import { createHash, generateKeyPairSync } from "node:crypto";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  compileFutureReleasePackage,
  futureReleaseApprovalDigest,
  requireFutureReleaseIsolation,
  requireMatchingFutureRelease,
  saveMigrationDescriptorInventoryDigest,
  saveMigrationGraphDigest,
  validateFutureReleaseApprovalRecord,
  validateFutureReleaseSource,
  verifyCompiledPackage,
} from "../src/compile.mjs";
import { validatePublicDocument } from "../src/validate.mjs";

const version = (major = 1, minor = 0, patch = 0) => ({ major, minor, patch });
const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const localized = (id, launchEnglish) => ({ id, launchEnglish });

function validPayload() {
  const revealArrival = {
    id: "effect-first-crusade-deep-dive-arrival",
    mutation: "reveal-node",
    node: {
      id: "crusader-arrival",
      kind: "settlement",
      form: "The host reaches the fortified city",
      position: { x: 0.62, y: 0.44 },
      attributes: [{ key: "reached", value: true }],
    },
  };
  return {
    schemaVersion: version(),
    packageID: "deep-dive-first-crusade-v1",
    worldSeed: validCanonicalWorldSeed(),
    chapters: [{
      schemaVersion: version(),
      id: "first-crusade-deep-dive",
      title: localized("chapter-first-crusade-title", "The First Crusade"),
      period: localized("chapter-first-crusade-period", "AD 1095–1099"),
      arcs: [{
        id: "road-to-jerusalem",
        title: localized("arc-road-jerusalem-title", "The Road to Jerusalem"),
        targetDurationMinutes: 10,
        situation: localized("arc-road-jerusalem-situation", "The expedition must cross an immense distance."),
        mechanism: localized("arc-road-jerusalem-mechanism", "Routes, supplies and fortified cities govern its movement."),
        turn: localized("arc-road-jerusalem-turn", "The long road becomes a siege line."),
        consequence: localized("arc-road-jerusalem-consequence", "Jerusalem falls to the western host."),
        handoff: localized("arc-road-jerusalem-handoff", "New states now have to hold what the expedition took."),
        beats: [{
          id: "carry-the-road-east",
          sceneID: "anatolian-road",
          narrative: {
            heading: localized("beat-anatolian-road-heading", "The road consumes men and stores"),
            paragraphs: [localized("beat-anatolian-road-paragraph", "The host moved through heat, distance and defended ground.")],
          },
          narrationCueIDs: ["narration-anatolian-road"],
          completionEffects: [revealArrival],
          checkpoint: "onExit",
        }],
      }],
      completionEffects: [{
        id: "effect-first-crusade-deep-dive-latin-east",
        mutation: "reveal-node",
        node: {
          id: "latin-east",
          kind: "institution",
          form: "A chain of western principalities",
          position: { x: 0.68, y: 0.4 },
          attributes: [{ key: "established", value: true }],
        },
      }],
    }],
    scenes: [{
      id: "anatolian-road",
      sceneCanvas: {
        canvas: { width: 1200, height: 2600 },
        cameraTravelBounds: { x: 0.2, y: 0.2, width: 0.6, height: 0.6 },
        authoredOverscanFraction: 0.15,
        viewportCrops: [{
          id: "baseline-393x852",
          viewport: { widthPoints: 393, heightPoints: 852 },
          sourceRect: { x: 0.05, y: 0.05, width: 0.9, height: 0.9 },
          safeTextRegions: [{
            id: "opening-copy",
            rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.22 },
          }],
        }],
      },
      layers: [{
        id: "road-landscape",
        order: 0,
        assetPath: "assets/anatolian-road.heif",
        frame: { x: 0, y: 0, width: 1, height: 1 },
        depth: 0.2,
        opacity: 1,
        blendMode: "normal",
        masks: {},
        motion: { parallaxFactor: 0.1, windResponse: 0, focusResponse: 0.1 },
        stateVariants: [],
      }],
      cameraRail: {
        keyframes: [
          { progress: 0, center: { x: 0.45, y: 0.52 }, scale: 1 },
          { progress: 1, center: { x: 0.55, y: 0.46 }, scale: 1.08 },
        ],
      },
      atmosphere: [{
        kind: "dust",
        density: 0.2,
        velocity: { dx: -0.1, dy: 0 },
        deterministicSeed: 42,
      }],
      interactionTargets: [],
      reduceMotionComposition: {
        canvas: { width: 1200, height: 2600 },
        strata: [
          { id: "static-world", kind: "staticPlate", assetPath: "assets/anatolian-road-reduce.heif" },
        ],
        viewportCrops: [{
          id: "baseline-393x852",
          viewport: { widthPoints: 393, heightPoints: 852 },
          sourceRect: { x: 0.05, y: 0.05, width: 0.9, height: 0.9 },
          safeTextRegions: [{
            id: "opening-copy",
            rect: { x: 0.08, y: 0.06, width: 0.84, height: 0.22 },
          }],
        }],
      },
      mechanismFocus: localized("scene-anatolian-road-mechanism", "The viable road through defended ground"),
      accessibilityID: "access-anatolian-road",
    }],
    audioTimelines: [{
      id: "audio-anatolian-road",
      sampleRate: 48000,
      events: [{
        cueID: "narration-anatolian-road",
        role: "narration",
        startSample: 0,
        durationSamples: 96000,
        assetPath: "audio/narration.m4a",
        gain: 1,
        narrationBinding: {
          manuscriptSegmentID: "beat-anatolian-road-paragraph",
          manuscriptSegmentSHA256: sha256("The host moved through heat, distance and defended ground."),
          scope: {
            chapterID: "first-crusade-deep-dive",
            arcID: "road-to-jerusalem",
            beatID: "carry-the-road-east",
          },
        },
      }],
      haptics: [{ sample: 48000, kind: "resistance", intensity: 0.4, sharpness: 0.3 }],
    }],
    responsiveAudioPrograms: [],
    accessibility: [{
      id: "access-anatolian-road",
      sceneSummary: localized("access-anatolian-road-summary", "A long road crosses defended Anatolian ground."),
      elements: [{
        id: "road-landscape-description",
        role: "image",
        label: localized("access-anatolian-road-image-label", "A defended road across Anatolian ground"),
        actions: [],
      }],
    }],
  };
}

function validCanonicalWorldSeed() {
  return {
    nodes: [{
      id: "world-alpha",
      kind: "landscape",
      form: "The established launch world",
      position: { x: 0.5, y: 0.5 },
      attributes: [],
    }],
    traces: [],
  };
}

function validRelease() {
  return {
    id: "release-first-crusade-v1",
    contentID: "first-crusade-deep-dive",
    packageID: "deep-dive-first-crusade-v1",
    version: version(1, 2, 0),
    chapterIDs: ["first-crusade-deep-dive"],
    maximumInstalledBytes: 420_000_000,
    publishedAtUnixMillis: 1_800_000_000_000,
    minimumRuntime: version(1, 1, 0),
  };
}

function launchConfiguration() {
  const chapterIDs = Array.from({ length: 24 }, (_, index) => `launch-chapter-${index + 1}`);
  return {
    product: {},
    catalog: {
      collectionID: "collection-01",
      chapterCount: 24,
      chapters: chapterIDs.map((contentID) => ({ contentID })),
    },
    delivery: {
      packages: Array.from({ length: 8 }, (_, index) => ({
        packageID: `launch-package-${index + 1}`,
        chapterIDs: chapterIDs.slice(index * 3, index * 3 + 3),
      })),
    },
  };
}

function validPublication() {
  const release = validRelease();
  return {
    schemaVersion: 1,
    releaseID: release.id,
    contentID: release.contentID,
    packageID: release.packageID,
    worldPlacement: {
      worldNodeID: "world-alpha",
      historicalYear: 1095,
      chronologyOrdinal: 0,
    },
  };
}

function validWorldAuthority() {
  return {
    schemaVersion: 1,
    kind: "FUTURE_RELEASE_WORLD_AUTHORITY",
    status: "APPROVED_BY_EDITOR_IN_CHIEF",
    authority: "editor-in-chief",
    approvedAt: "2026-07-23T19:00:00Z",
    decisionReference: "test-only-launch-world-authority",
    collectionID: "collection-01",
    worldSeed: validCanonicalWorldSeed(),
    placementNodeIDs: ["world-alpha"],
  };
}

function zeroCostEntry(id, category = "tool") {
  return {
    id,
    category,
    version: "test-v1",
    costModel: "free-local",
    incrementalCostNOK: 0,
    billingCredentialRequired: false,
    commercialUse: "allowed",
    license: "Project-owned test fixture",
    source: "Local test fixture",
  };
}

async function createFutureSource() {
  const temporary = await mkdtemp(path.join(os.tmpdir(), "long-west-future-release-"));
  const source = path.join(temporary, "public");
  const backstage = path.join(temporary, "backstage");
  await Promise.all([
    mkdir(path.join(source, "chapters"), { recursive: true }),
    mkdir(path.join(source, "releases"), { recursive: true }),
    mkdir(path.join(source, "assets"), { recursive: true }),
    mkdir(path.join(source, "audio"), { recursive: true }),
    mkdir(backstage, { recursive: true }),
  ]);
  const payloadPath = path.join(source, "chapters", "first-crusade.json");
  const releasePath = path.join(source, "releases", "first-crusade.json");
  await writeFile(payloadPath, `${JSON.stringify(validPayload(), null, 2)}\n`);
  await writeFile(releasePath, `${JSON.stringify(validRelease(), null, 2)}\n`);
  await writeFile(path.join(source, "assets", "anatolian-road.heif"), Buffer.from("layer"));
  await writeFile(path.join(source, "assets", "anatolian-road-reduce.heif"), Buffer.from("reduced-layer"));
  await writeFile(path.join(source, "audio", "narration.m4a"), Buffer.from("narration"));

  const assets = await Promise.all([
    ["assets/anatolian-road.heif", "scene-layer", "source-road"],
    ["assets/anatolian-road-reduce.heif", "scene-layer", "source-road-reduced"],
    ["audio/narration.m4a", "narration", "source-narration"],
  ].map(async ([assetPath, role, sourceID]) => {
    const data = await readFile(path.join(source, assetPath));
    return {
      assetPath,
      bytes: data.byteLength,
      sha256: sha256(data),
      sourceLineage: [{
        lineageType: "GENERATED_ORIGINAL",
        sourceID,
        bytes: data.byteLength,
        sha256: sha256(data),
        rightsBasis: "PROJECT_OWNED",
        license: "Project-owned test fixture",
      }],
      toolLineage: [{ toolID: "test-tool" }],
      shippingRoles: [role],
      metadataPolicy: "STRIPPED_AND_INSPECTED",
      rightsStatus: "COMMERCIAL_USE_CLEARED",
      incrementalCostNOK: 0,
      approvedForShipping: true,
    };
  }));
  const assetProvenancePath = path.join(backstage, "asset-provenance.json");
  const costRegistryPath = path.join(backstage, "cost-license.json");
  await writeFile(assetProvenancePath, JSON.stringify({
    schemaVersion: 3,
    status: "ACTIVE",
    assets,
  }));
  await writeFile(costRegistryPath, JSON.stringify({
    policyVersion: 1,
    entries: [
      zeroCostEntry("test-tool"),
      zeroCostEntry("native-image-layer-production", "image"),
      zeroCostEntry("final-narration-synthesis", "audio"),
    ],
    unresolvedCapabilities: [],
  }));

  const releaseBytes = await readFile(releasePath);
  const payloadBytes = await readFile(payloadPath);
  const approvalPath = path.join(backstage, "release-approval.json");
  const publicationPath = path.join(backstage, "release-publication.json");
  const worldAuthorityPath = path.join(backstage, "world-authority.json");
  await writeFile(publicationPath, `${JSON.stringify(validPublication(), null, 2)}\n`);
  await writeFile(worldAuthorityPath, `${JSON.stringify(validWorldAuthority(), null, 2)}\n`);
  const publicationBytes = await readFile(publicationPath);
  const worldAuthorityBytes = await readFile(worldAuthorityPath);
  const saveMigrationGraphSHA256 = saveMigrationGraphDigest(validRelease().version);
  const saveMigrationDescriptorInventorySHA256 = saveMigrationDescriptorInventoryDigest();
  await writeFile(approvalPath, JSON.stringify({
    schemaVersion: 3,
    status: "APPROVED_BY_EDITOR_IN_CHIEF",
    authority: "editor-in-chief",
    approvedAt: "2026-07-23T20:00:00Z",
    decisionReference: "test-only-synthetic-editor-decision",
    releaseID: validRelease().id,
    contentID: validRelease().contentID,
    packageID: validRelease().packageID,
    releaseSHA256: sha256(releaseBytes),
    payloadSHA256: sha256(payloadBytes),
    publicationSHA256: sha256(publicationBytes),
    worldAuthoritySHA256: sha256(worldAuthorityBytes),
    saveMigrationGraphSHA256,
    saveMigrationDescriptorInventorySHA256,
    releasePayloadPublicationAuthoritySHA256: futureReleaseApprovalDigest(
      releaseBytes,
      payloadBytes,
      publicationBytes,
      worldAuthorityBytes,
      saveMigrationGraphSHA256,
      saveMigrationDescriptorInventorySHA256,
    ),
  }));
  return {
    temporary,
    source,
    payloadPath,
    releasePath,
    approvalPath,
    publicationPath,
    worldAuthorityPath,
    assetProvenancePath,
    costRegistryPath,
  };
}

function validationOptions(fixture) {
  return {
    futureReleaseApprovalPath: fixture.approvalPath,
    futureReleasePublicationPath: fixture.publicationPath,
    futureReleaseWorldAuthorityPath: fixture.worldAuthorityPath,
    assetProvenancePath: fixture.assetProvenancePath,
    costRegistryPath: fixture.costRegistryPath,
    launchConfiguration: launchConfiguration(),
  };
}

async function rewriteApprovalForCurrentInputs(fixture) {
  const [releaseBytes, payloadBytes, publicationBytes, worldAuthorityBytes] = await Promise.all([
    readFile(fixture.releasePath),
    readFile(fixture.payloadPath),
    readFile(fixture.publicationPath),
    readFile(fixture.worldAuthorityPath),
  ]);
  const release = JSON.parse(releaseBytes.toString("utf8"));
  const saveMigrationGraphSHA256 = saveMigrationGraphDigest(release.version);
  const saveMigrationDescriptorInventorySHA256 = saveMigrationDescriptorInventoryDigest();
  await writeFile(fixture.approvalPath, JSON.stringify({
    schemaVersion: 3,
    status: "APPROVED_BY_EDITOR_IN_CHIEF",
    authority: "editor-in-chief",
    approvedAt: "2026-07-23T20:00:00Z",
    decisionReference: "test-only-synthetic-editor-decision",
    releaseID: release.id,
    contentID: release.contentID,
    packageID: release.packageID,
    releaseSHA256: sha256(releaseBytes),
    payloadSHA256: sha256(payloadBytes),
    publicationSHA256: sha256(publicationBytes),
    worldAuthoritySHA256: sha256(worldAuthorityBytes),
    saveMigrationGraphSHA256,
    saveMigrationDescriptorInventorySHA256,
    releasePayloadPublicationAuthoritySHA256: futureReleaseApprovalDigest(
      releaseBytes,
      payloadBytes,
      publicationBytes,
      worldAuthorityBytes,
      saveMigrationGraphSHA256,
      saveMigrationDescriptorInventorySHA256,
    ),
  }));
}

test("Release owns its exact payload and derives a bounded verification package", () => {
  assert.equal(validatePublicDocument(validRelease()).maximumInstalledBytes, 420_000_000);
  const packageSpec = requireMatchingFutureRelease(validRelease(), validPayload());
  assert.deepEqual(packageSpec, {
    id: "deep-dive-first-crusade-v1",
    version: version(1, 2, 0),
    chapterIDs: ["first-crusade-deep-dive"],
    maximumInstalledBytes: 420_000_000,
    minimumRuntime: version(1, 1, 0),
    isEssentialInstall: false,
  });

  const missingBudget = validRelease();
  missingBudget.maximumInstalledBytes = 0;
  assert.throws(() => validatePublicDocument(missingBudget), /maximumInstalledBytes/);
  const wrongOwnership = validRelease();
  wrongOwnership.chapterIDs = ["different-deep-dive"];
  assert.throws(() => validatePublicDocument(wrongOwnership), /must identify a chapter owned/);

  const orderedRelease = {
    ...validRelease(),
    contentID: "first-deep-dive",
    chapterIDs: ["first-deep-dive", "second-deep-dive"],
  };
  const reversedPayload = {
    packageID: orderedRelease.packageID,
    chapters: [{ id: "second-deep-dive" }, { id: "first-deep-dive" }],
  };
  assert.throws(
    () => requireMatchingFutureRelease(orderedRelease, reversedPayload),
    /must exactly match ContentPackagePayload chapters/,
  );
});

test("future release path cannot claim launch chapters or launch package IDs", () => {
  const configuration = launchConfiguration();
  const payload = validPayload();
  configuration.catalog.chapters[0].contentID = payload.chapters[0].id;
  configuration.delivery.packages[0].chapterIDs[0] = payload.chapters[0].id;
  assert.throws(
    () => requireFutureReleaseIsolation(validRelease(), payload, configuration),
    /cannot own locked launch content/,
  );

  const packageCollision = launchConfiguration();
  packageCollision.delivery.packages[0].packageID = validRelease().packageID;
  assert.throws(
    () => requireFutureReleaseIsolation(validRelease(), payload, packageCollision),
    /cannot reuse a locked launch package ID/,
  );

  const effectCollision = validPayload();
  effectCollision.chapters[0].arcs[0].beats[0].completionEffects[0].id =
    "effect-launch-chapter-1-stolen-consequence";
  assert.throws(
    () => requireFutureReleaseIsolation(
      validRelease(),
      effectCollision,
      launchConfiguration(),
    ),
    /must be namespaced to owning chapter 'first-crusade-deep-dive'/,
  );
});

test("backstage approval binds Release, payload, publication and world authority", async () => {
  const fixture = await createFutureSource();
  const approval = JSON.parse(await readFile(fixture.approvalPath, "utf8"));
  const releaseBytes = await readFile(fixture.releasePath);
  const payloadBytes = await readFile(fixture.payloadPath);
  const publicationBytes = await readFile(fixture.publicationPath);
  const worldAuthorityBytes = await readFile(fixture.worldAuthorityPath);
  assert.equal(
    validateFutureReleaseApprovalRecord(
      approval,
      validRelease(),
      releaseBytes,
      payloadBytes,
      publicationBytes,
      worldAuthorityBytes,
      approval.saveMigrationGraphSHA256,
      approval.saveMigrationDescriptorInventorySHA256,
    ),
    true,
  );
  assert.throws(
    () => validateFutureReleaseApprovalRecord(
      approval,
      validRelease(),
      releaseBytes,
      Buffer.concat([payloadBytes, Buffer.from("changed")]),
      publicationBytes,
      worldAuthorityBytes,
      approval.saveMigrationGraphSHA256,
      approval.saveMigrationDescriptorInventorySHA256,
    ),
    /digest does not match/,
  );
  assert.throws(
    () => validateFutureReleaseApprovalRecord(
      approval,
      validRelease(),
      releaseBytes,
      payloadBytes,
      Buffer.concat([publicationBytes, Buffer.from("changed")]),
      worldAuthorityBytes,
      approval.saveMigrationGraphSHA256,
      approval.saveMigrationDescriptorInventorySHA256,
    ),
    /digest does not match/,
  );
  assert.throws(
    () => validateFutureReleaseApprovalRecord(
      approval,
      validRelease(),
      releaseBytes,
      payloadBytes,
      publicationBytes,
      Buffer.concat([worldAuthorityBytes, Buffer.from("changed")]),
      approval.saveMigrationGraphSHA256,
      approval.saveMigrationDescriptorInventorySHA256,
    ),
    /digest does not match/,
  );
  assert.throws(
    () => validateFutureReleaseApprovalRecord(
      approval,
      validRelease(),
      releaseBytes,
      payloadBytes,
      publicationBytes,
      worldAuthorityBytes,
      "f".repeat(64),
      approval.saveMigrationDescriptorInventorySHA256,
    ),
    /save-migration authority digest does not match/,
  );
  assert.throws(
    () => validateFutureReleaseApprovalRecord(
      approval,
      validRelease(),
      releaseBytes,
      payloadBytes,
      publicationBytes,
      worldAuthorityBytes,
      approval.saveMigrationGraphSHA256,
      "f".repeat(64),
    ),
    /save-migration authority digest does not match/,
  );
});

test("future release rejects a syntactically valid placement outside the canonical world", async () => {
  const fixture = await createFutureSource();
  const publication = validPublication();
  publication.worldPlacement.worldNodeID = "world-does-not-exist";
  await writeFile(
    fixture.publicationPath,
    `${JSON.stringify(publication, null, 2)}\n`,
  );
  await rewriteApprovalForCurrentInputs(fixture);
  await assert.rejects(
    () => validateFutureReleaseSource(fixture.source, validationOptions(fixture)),
    /world placement node 'world-does-not-exist' does not exist in the trusted launch world authority/,
  );
});

test("world authority cannot invent a placement node outside its exact world seed", async () => {
  const fixture = await createFutureSource();
  const authority = validWorldAuthority();
  authority.placementNodeIDs = ["world-does-not-exist"];
  const publication = validPublication();
  publication.worldPlacement.worldNodeID = "world-does-not-exist";
  await Promise.all([
    writeFile(
      fixture.worldAuthorityPath,
      `${JSON.stringify(authority, null, 2)}\n`,
    ),
    writeFile(
      fixture.publicationPath,
      `${JSON.stringify(publication, null, 2)}\n`,
    ),
  ]);
  await rewriteApprovalForCurrentInputs(fixture);
  await assert.rejects(
    () => validateFutureReleaseSource(fixture.source, validationOptions(fixture)),
    /'world-does-not-exist' is not an exact canonical worldSeed node/,
  );
});

test("world authority rejects duplicate canonical seed nodes", async () => {
  const fixture = await createFutureSource();
  const authority = validWorldAuthority();
  authority.worldSeed.nodes.push(structuredClone(authority.worldSeed.nodes[0]));
  await writeFile(
    fixture.worldAuthorityPath,
    `${JSON.stringify(authority, null, 2)}\n`,
  );
  await rewriteApprovalForCurrentInputs(fixture);
  await assert.rejects(
    () => validateFutureReleaseSource(fixture.source, validationOptions(fixture)),
    /worldSeed\.nodes\.id: duplicate identifier 'world-alpha'/,
  );
});

test("future release rejects world-seed continuity drift even after fresh approval", async () => {
  const fixture = await createFutureSource();
  const payload = validPayload();
  payload.worldSeed.nodes[0] = {
    ...payload.worldSeed.nodes[0],
    id: "world-beta",
  };
  await writeFile(fixture.payloadPath, `${JSON.stringify(payload, null, 2)}\n`);
  await rewriteApprovalForCurrentInputs(fixture);
  await assert.rejects(
    () => validateFutureReleaseSource(fixture.source, validationOptions(fixture)),
    /world seed drifted from the trusted launch world authority/,
  );
});

test("future release compiler signs the separately approved, zero-cost package", async () => {
  const fixture = await createFutureSource();
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const options = {
    ...validationOptions(fixture),
    keyID: "test-release-key",
    signingPrivateKey: privateKey,
  };
  const validated = await validateFutureReleaseSource(fixture.source, options);
  assert.equal(validated.release.id, "release-first-crusade-v1");
  const output = path.join(fixture.temporary, "compiled");
  const result = await compileFutureReleasePackage(fixture.source, output, options);
  assert.equal(result.manifest.packageVersion.minor, 2);
  assert.equal(result.manifest.minimumRuntime.minor, 1);
  assert.equal(result.publication.worldPlacement.worldNodeID, "world-alpha");
  assert.equal(result.manifest.files.some(({ path: file }) => file.includes("approval")), false);
  assert.equal(result.manifest.files.some(({ path: file }) => file.includes("publication")), false);
  const verified = await verifyCompiledPackage(
    output,
    publicKey,
    "test-release-key",
    result.packageSpec,
  );
  assert.equal(verified.packageID, result.release.packageID);
});

test("future release compiler fails closed on approval, provenance and P-256 gates", async () => {
  const fixture = await createFutureSource();
  await assert.rejects(
    () => validateFutureReleaseSource(fixture.source, {
      ...validationOptions(fixture),
      futureReleaseApprovalPath: undefined,
    }),
    /separate backstage approval record required/,
  );
  await assert.rejects(
    () => validateFutureReleaseSource(fixture.source, {
      ...validationOptions(fixture),
      futureReleasePublicationPath: undefined,
    }),
    /futureReleasePublicationPath: separate backstage JSON record required/,
  );
  await assert.rejects(
    () => validateFutureReleaseSource(fixture.source, {
      ...validationOptions(fixture),
      futureReleaseWorldAuthorityPath: undefined,
    }),
    /futureReleaseWorldAuthorityPath: separate backstage JSON record required/,
  );

  const originalPayload = await readFile(fixture.payloadPath, "utf8");
  await writeFile(fixture.payloadPath, `${originalPayload}\n`);
  await assert.rejects(
    () => validateFutureReleaseSource(fixture.source, validationOptions(fixture)),
    /digest does not match/,
  );

  const repaired = await createFutureSource();
  await assert.rejects(
    () => validateFutureReleaseSource(repaired.source, {
      ...validationOptions(repaired),
      assetProvenancePath: undefined,
    }),
    /production registry is required/,
  );
  await assert.rejects(
    () => compileFutureReleasePackage(
      repaired.source,
      path.join(repaired.temporary, "unsigned"),
      {
        ...validationOptions(repaired),
        keyID: "test-release-key",
      },
    ),
    /P-256 private key required/,
  );
});

test("future release source requires exactly one Release and rejects collection launch data", async () => {
  const duplicate = await createFutureSource();
  await writeFile(
    path.join(duplicate.source, "releases", "duplicate.json"),
    JSON.stringify({ ...validRelease(), id: "release-first-crusade-copy" }),
  );
  await assert.rejects(
    () => validateFutureReleaseSource(duplicate.source, validationOptions(duplicate)),
    /exactly one public Release record/,
  );

  const collection = await createFutureSource();
  await writeFile(path.join(collection.source, "collection.json"), JSON.stringify({ invalid: true }));
  await assert.rejects(
    () => validateFutureReleaseSource(collection.source, validationOptions(collection)),
    /must contain CollectionManifest|expected CollectionManifest/,
  );
});
