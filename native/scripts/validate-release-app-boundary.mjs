import {
  ECDH,
  createHash,
  createPrivateKey,
  createPublicKey,
  createVerify,
} from 'node:crypto';
import { createReadStream } from 'node:fs';
import {
  lstat,
  readFile,
  readdir,
  realpath,
} from 'node:fs/promises';
import {
  basename,
  dirname,
  extname,
  join,
  relative,
  resolve,
  sep,
} from 'node:path';
import { fileURLToPath } from 'node:url';
import { validatePublicDocument } from '../tooling/src/validate.mjs';

export const releaseValidationModes = Object.freeze({
  boundaryOnly: 'boundary-only',
  releaseCandidate: 'release-candidate',
});

export const forbiddenReleaseBasenames = Object.freeze([
  'first-farmers.content-package.json',
  'first-farmers.payload-receipt.json',
  'vertical-slice-development-trust-receipt.json',
  'projection-authority.json',
  'harvest-v26-parallax-development-source.png',
  'harvest-v26-parallax-diagnostic-underlay.png',
  'harvest-v26-parallax-alpha-people.png',
  'harvest-v26-parallax-alpha-grain.png',
  'harvest-v26-parallax-alpha-foreground.png',
  'harvest-v26-parallax-reduce-motion-static.png',
]);

export const forbiddenReleaseExtensions = Object.freeze([
  '.der',
  '.jwk',
  '.key',
  '.p8',
  '.pem',
  '.pk8',
  '.storekit',
]);

export const forbiddenReleaseByteSequences = Object.freeze([
  'DevelopmentFirstFarmersRepository',
  'DevelopmentFirstFarmersEnvelope',
  'first-farmers-development-v1',
  'CODEX_PROVISIONAL_NON_SHIPPING_PRODUCTION_MASTER',
  'CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_FIXTURE',
  'CODEX_PROVISIONAL_NON_SHIPPING_TECHNICAL_INPUT',
  'CODEX_PROVISIONAL_NON_SHIPPING',
  'NON_SHIPPING',
  'NON-SHIPPING',
  'The River Already Held a World',
  'DevelopmentJourneyDownloadFixture',
  'LocalReleaseCatalogProvider',
  'Local release fixture',
  'release-local-fixture-v1',
  '--release-discovery-live',
  '--ui-testing-',
  'vertical-slice-development-v1',
  'vertical-slice-development-key-v1',
  'the-long-west-vertical-slice-development-v1',
  'long-west-vertical-slice-development-receipt-v1',
  'DEVELOPMENT_BLUEPRINT_PROJECTION_AUTHORITY',
  'CODEX_PROVISIONAL_NON_SHIPPING_BLUEPRINT_PROJECTION',
  'codex-local-production',
  'privateKeyBase64',
  '-----BEGIN PRIVATE KEY-----',
  '-----BEGIN ENCRYPTED PRIVATE KEY-----',
  '-----BEGIN EC PRIVATE KEY-----',
  '-----BEGIN RSA PRIVATE KEY-----',
  '-----BEGIN DSA PRIVATE KEY-----',
  '-----BEGIN OPENSSH PRIVATE KEY-----',
]);

const maximumStructuredSecretInspectionBytes = 1024 * 1024;
const maximumPrivateKeyInspectionBytes = 64 * 1024;
const trustResourceBasename = 'launch-package-trust.json';
const essentialResourceParentDirectory = 'JourneyContent';
const essentialPackageID = 'essential-free-v1';
const essentialManifestBasename = 'package-manifest.json';
const signatureAlgorithm = 'P-256-SHA256';
const packageIntegrityHeader = 'long-west-package-v1';
const lowercaseSHA256Pattern = /^[a-f0-9]{64}$/u;
const stablePackageIDPattern = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/u;
const essentialChapterIDs = Object.freeze([
  'first-farmers',
  'europe-holds-the-line',
  'european-world',
]);

async function filesUnder(root) {
  const result = [];
  const queue = [root];
  while (queue.length > 0) {
    const current = queue.pop();
    const info = await lstat(current);
    if (info.isSymbolicLink()) {
      throw new Error(`Release app contains an unresolved symbolic link: ${current}`);
    }
    if (info.isDirectory()) {
      const children = await readdir(current, { withFileTypes: true });
      for (const child of children) queue.push(resolve(current, child.name));
    } else if (info.isFile()) {
      result.push(current);
    } else {
      throw new Error(`Release app contains a special filesystem object: ${current}`);
    }
  }
  return result.sort();
}

function canonicalValue(value) {
  if (Array.isArray(value)) return value.map(canonicalValue);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value).sort().map((key) => [key, canonicalValue(value[key])]),
    );
  }
  return value;
}

function canonicalJSONBytes(value) {
  return Buffer.from(JSON.stringify(canonicalValue(value)), 'utf8');
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function exactFields(object, fields, description) {
  if (object === null || Array.isArray(object) || typeof object !== 'object') {
    throw new Error(`${description} must be an object`);
  }
  const actual = Object.keys(object).sort();
  const expected = [...fields].sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${description} has unexpected or missing fields`);
  }
}

function isStableProductionKeyIdentifier(value) {
  return typeof value === 'string'
    && /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/.test(value)
    && Buffer.byteLength(value, 'utf8') <= 64
    && !/(?:^|-)(?:debug|development|fixture|local|test)(?:-|$)/.test(value);
}

function decodeCanonicalBase64(value, description) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`${description} is not canonical base64`);
  }
  const decoded = Buffer.from(value, 'base64');
  if (decoded.length === 0 || decoded.toString('base64') !== value) {
    throw new Error(`${description} is not canonical base64`);
  }
  return decoded;
}

function parseCanonicalJSON(bytes, description) {
  const text = bytes.toString('utf8');
  if (!Buffer.from(text, 'utf8').equals(bytes)) {
    throw new Error(`${description} is not UTF-8`);
  }
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    throw new Error(`${description} is not valid JSON`);
  }
  if (!canonicalJSONBytes(value).equals(bytes)) {
    throw new Error(`${description} is not canonical JSON`);
  }
  return value;
}

function validateTrustDocument(bytes) {
  const document = parseCanonicalJSON(bytes, 'Launch package trust resource');
  exactFields(document, ['schemaVersion', 'keys'], 'Launch package trust resource');
  if (document.schemaVersion !== 1 || !Array.isArray(document.keys)
      || document.keys.length !== 1) {
    throw new Error('Launch package trust resource must contain exactly one schema-v1 key');
  }
  const record = document.keys[0];
  exactFields(record, ['id', 'x963PublicKeyBase64'], 'Launch package trust key');
  if (!isStableProductionKeyIdentifier(record.id)) {
    throw new Error('Launch package trust key ID is not a production identifier');
  }
  const publicKey = decodeCanonicalBase64(
    record.x963PublicKeyBase64,
    'Launch package trust public key',
  );
  if (publicKey.length !== 65 || publicKey[0] !== 0x04) {
    throw new Error('Launch package trust public key is not an uncompressed P-256 point');
  }
  try {
    const normalized = ECDH.convertKey(
      publicKey,
      'prime256v1',
      undefined,
      undefined,
      'uncompressed',
    );
    if (!normalized.equals(publicKey)) throw new Error('noncanonical point');
  } catch {
    throw new Error('Launch package trust public key is not a valid P-256 point');
  }
  const verificationKey = createPublicKey({
    format: 'jwk',
    key: {
      kty: 'EC',
      crv: 'P-256',
      x: publicKey.subarray(1, 33).toString('base64url'),
      y: publicKey.subarray(33, 65).toString('base64url'),
    },
  });
  return { id: record.id, publicKey, verificationKey };
}

function parseJSON(bytes, description) {
  const text = bytes.toString('utf8');
  if (!Buffer.from(text, 'utf8').equals(bytes)) {
    throw new Error(`${description} is not UTF-8`);
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`${description} is not valid JSON`);
  }
}

function isWithin(root, candidate) {
  const path = relative(root, candidate);
  return path === '' || (!path.startsWith(`..${sep}`) && path !== '..' && !path.startsWith(sep));
}

function safePackagePath(value) {
  return typeof value === 'string'
    && value.length > 0
    && !value.startsWith('/')
    && !value.includes('\\')
    && !value.includes('://')
    && !/[\u0000-\u001f\u007f]/u.test(value)
    && value.split('/').every((segment) => segment && segment !== '.' && segment !== '..');
}

function validateVersion(value, description) {
  exactFields(value, ['major', 'minor', 'patch'], description);
  if (['major', 'minor', 'patch'].some((key) =>
    !Number.isSafeInteger(value[key]) || value[key] < 0)) {
    throw new Error(`${description} requires non-negative integer components`);
  }
  return value;
}

function versionString(value) {
  return `${value.major}.${value.minor}.${value.patch}`;
}

function sameVersion(left, right) {
  return left?.major === right?.major
    && left?.minor === right?.minor
    && left?.patch === right?.patch;
}

function packageManifestIntegrityMaterial(manifest) {
  return [
    packageIntegrityHeader,
    `packageID=${manifest.packageID}`,
    `packageVersion=${versionString(manifest.packageVersion)}`,
    `schemaVersion=${versionString(manifest.schemaVersion)}`,
    `minimumRuntime=${versionString(manifest.minimumRuntime)}`,
    ...manifest.files.map((record) =>
      `file=${record.path}\t${record.bytes}\t${record.sha256}`),
    '',
  ].join('\n');
}

function validateEssentialManifest(manifestBytes, trust) {
  const manifest = parseJSON(manifestBytes, 'Bundled essential package manifest');
  exactFields(
    manifest,
    [
      'packageID',
      'packageVersion',
      'schemaVersion',
      'minimumRuntime',
      'files',
      'manifestDigest',
      'signature',
    ],
    'Bundled essential package manifest',
  );
  if (manifest.packageID !== essentialPackageID) {
    throw new Error('Bundled essential package manifest has the wrong package identity');
  }
  if (!stablePackageIDPattern.test(manifest.packageID)) {
    throw new Error('Bundled essential package manifest has an unsafe package ID');
  }
  validateVersion(manifest.packageVersion, 'Bundled essential package version');
  validateVersion(manifest.schemaVersion, 'Bundled essential schema version');
  validateVersion(manifest.minimumRuntime, 'Bundled essential minimum runtime');
  if (!Array.isArray(manifest.files) || manifest.files.length === 0) {
    throw new Error('Bundled essential package manifest requires a non-empty file inventory');
  }

  const paths = [];
  const seen = new Set();
  for (const [index, record] of manifest.files.entries()) {
    exactFields(
      record,
      ['path', 'bytes', 'sha256'],
      `Bundled essential package manifest file ${index}`,
    );
    if (!safePackagePath(record.path) || record.path === essentialManifestBasename) {
      throw new Error(`Bundled essential package manifest contains an unsafe path: ${record.path}`);
    }
    if (seen.has(record.path)) {
      throw new Error(`Bundled essential package manifest repeats path: ${record.path}`);
    }
    seen.add(record.path);
    paths.push(record.path);
    if (!Number.isSafeInteger(record.bytes) || record.bytes < 0
        || !lowercaseSHA256Pattern.test(record.sha256)) {
      throw new Error(`Bundled essential package manifest has an invalid file record: ${record.path}`);
    }
  }
  const sortedPaths = [...paths].sort((left, right) =>
    Buffer.compare(Buffer.from(left), Buffer.from(right)));
  if (JSON.stringify(paths) !== JSON.stringify(sortedPaths)) {
    throw new Error('Bundled essential package manifest inventory is not in canonical UTF-8 order');
  }
  if (!lowercaseSHA256Pattern.test(manifest.manifestDigest)
      || manifest.manifestDigest !== sha256(Buffer.from(
        packageManifestIntegrityMaterial(manifest),
        'utf8',
      ))) {
    throw new Error('Bundled essential package manifestDigest is invalid');
  }

  exactFields(
    manifest.signature,
    ['algorithm', 'keyID', 'value'],
    'Bundled essential package signature',
  );
  if (manifest.signature.algorithm !== signatureAlgorithm
      || manifest.signature.keyID !== trust.id) {
    throw new Error('Bundled essential package signature does not use the approved launch key');
  }
  const signature = decodeCanonicalBase64(
    manifest.signature.value,
    'Bundled essential package signature',
  );
  const verifier = createVerify('SHA256');
  verifier.update(Buffer.from(manifest.manifestDigest, 'utf8'));
  verifier.end();
  let verified = false;
  try {
    verified = verifier.verify(
      { key: trust.verificationKey, dsaEncoding: 'der' },
      signature,
    );
  } catch {
    verified = false;
  }
  if (!verified) throw new Error('Bundled essential package signature is invalid');
  return manifest;
}

async function hashFile(path) {
  const hasher = createHash('sha256');
  let bytes = 0;
  for await (const chunk of createReadStream(path)) {
    bytes += chunk.byteLength;
    hasher.update(chunk);
  }
  return { bytes, sha256: hasher.digest('hex') };
}

async function packageTree(root) {
  const files = [];
  const directories = [];
  async function visit(directory) {
    const entries = await readdir(directory);
    entries.sort((left, right) => Buffer.compare(Buffer.from(left), Buffer.from(right)));
    for (const entry of entries) {
      const path = join(directory, entry);
      const info = await lstat(path);
      if (info.isSymbolicLink()) {
        throw new Error(`Bundled essential package contains a symbolic link: ${path}`);
      }
      const relativePath = relative(root, path).split(sep).join('/');
      if (!safePackagePath(relativePath)) {
        throw new Error(`Bundled essential package contains an unsafe path: ${relativePath}`);
      }
      if (info.isDirectory()) {
        directories.push(relativePath);
        await visit(path);
      } else if (info.isFile()) {
        files.push(relativePath);
      } else {
        throw new Error(`Bundled essential package contains a special file: ${path}`);
      }
    }
  }
  await visit(root);
  return { files, directories };
}

function expectedPackageDirectories(filePaths) {
  const directories = new Set();
  for (const filePath of filePaths) {
    const components = filePath.split('/');
    for (let count = 1; count < components.length; count += 1) {
      directories.add(components.slice(0, count).join('/'));
    }
  }
  return [...directories].sort((left, right) =>
    Buffer.compare(Buffer.from(left), Buffer.from(right)));
}

const payloadFields = Object.freeze([
  'schemaVersion',
  'packageID',
  'worldSeed',
  'chapters',
  'scenes',
  'audioTimelines',
  'responsiveAudioPrograms',
  'accessibility',
]);

function hasExactPayloadFields(value) {
  return value !== null && !Array.isArray(value) && typeof value === 'object'
    && JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...payloadFields].sort());
}

async function validateEssentialPackageRoot(appRoot, allAppFiles, trust) {
  const manifestCandidates = allAppFiles.filter((path) =>
    basename(path) === essentialManifestBasename
      && basename(dirname(path)) === essentialPackageID);
  if (manifestCandidates.length !== 1) {
    throw new Error(
      'Release candidate must contain exactly one signed JourneyContent/essential-free-v1 package root',
    );
  }
  const expectedRoot = join(appRoot, essentialResourceParentDirectory, essentialPackageID);
  const expectedManifestPath = join(expectedRoot, essentialManifestBasename);
  if (manifestCandidates[0] !== expectedManifestPath) {
    throw new Error(
      'Bundled essential package must be rooted at JourneyContent/essential-free-v1',
    );
  }
  const rootInfo = await lstat(expectedRoot).catch(() => null);
  if (!rootInfo?.isDirectory() || rootInfo.isSymbolicLink()) {
    throw new Error('Bundled essential package root must be a real directory');
  }

  const manifestBytes = await readFile(expectedManifestPath);
  const manifest = validateEssentialManifest(manifestBytes, trust);
  const tree = await packageTree(expectedRoot);
  const expectedFiles = [essentialManifestBasename, ...manifest.files.map((record) => record.path)]
    .sort((left, right) => Buffer.compare(Buffer.from(left), Buffer.from(right)));
  if (JSON.stringify(tree.files) !== JSON.stringify(expectedFiles)) {
    throw new Error('Bundled essential package tree differs from the signed manifest inventory');
  }
  const expectedDirectories = expectedPackageDirectories(expectedFiles);
  if (JSON.stringify(tree.directories) !== JSON.stringify(expectedDirectories)) {
    throw new Error('Bundled essential package contains a foreign or empty directory');
  }

  const recordByPath = new Map(manifest.files.map((record) => [record.path, record]));
  for (const [recordPath, record] of recordByPath) {
    const actual = await hashFile(join(expectedRoot, ...recordPath.split('/')));
    if (actual.bytes !== record.bytes || actual.sha256 !== record.sha256) {
      throw new Error(`Bundled essential package file differs from manifest: ${recordPath}`);
    }
  }

  const payloadCandidates = [];
  for (const record of manifest.files) {
    if (extname(record.path).toLowerCase() !== '.json') continue;
    const bytes = await readFile(join(expectedRoot, ...record.path.split('/')));
    const document = parseJSON(bytes, `Bundled essential JSON ${record.path}`);
    if (!hasExactPayloadFields(document)) continue;
    payloadCandidates.push({ path: record.path, bytes, document });
  }
  if (payloadCandidates.length !== 1) {
    throw new Error('Bundled essential package must contain exactly one canonical public payload');
  }
  const payload = payloadCandidates[0];
  try {
    validatePublicDocument(payload.document, 'Bundled essential payload');
  } catch (error) {
    throw new Error(`Bundled essential public payload is invalid: ${error.message}`);
  }
  const chapterIDs = payload.document.chapters.map((chapter) => chapter?.id);
  if (payload.document.packageID !== essentialPackageID
      || !sameVersion(payload.document.schemaVersion, manifest.schemaVersion)
      || JSON.stringify(chapterIDs) !== JSON.stringify(essentialChapterIDs)) {
    throw new Error(
      'Bundled essential payload must contain the ordered three included chapters under essential-free-v1',
    );
  }
  return {
    manifest,
    manifestBytes,
    payloadPath: payload.path,
    payloadBytes: payload.bytes,
  };
}

async function validateApprovedTrustReceipt(receiptPath, trustBytes, trust) {
  if (!receiptPath) {
    throw new Error('Release-candidate validation requires --approved-trust-receipt');
  }
  const receiptBytes = await readFile(resolve(receiptPath)).catch(() => null);
  if (!receiptBytes) throw new Error('Approved trust receipt could not be read');
  const receipt = parseCanonicalJSON(receiptBytes, 'Approved trust receipt');
  exactFields(
    receipt,
    ['schemaVersion', 'trustFileSHA256', 'keys'],
    'Approved trust receipt',
  );
  if (receipt.schemaVersion !== 1 || !Array.isArray(receipt.keys)
      || receipt.keys.length !== 1) {
    throw new Error('Approved trust receipt must contain exactly one schema-v1 key');
  }
  if (receipt.trustFileSHA256 !== sha256(trustBytes)) {
    throw new Error('Launch package trust resource does not match the approved receipt');
  }
  const approved = receipt.keys[0];
  exactFields(approved, ['id', 'x963PublicKeySHA256'], 'Approved trust key');
  if (approved.id !== trust.id
      || approved.x963PublicKeySHA256 !== sha256(trust.publicKey)) {
    throw new Error('Launch package trust key does not match the approved receipt');
  }
}

async function validateApprovedEssentialReceipt(receiptPath, appRoot, essentialPackage) {
  if (!receiptPath) {
    throw new Error('Release-candidate validation requires --approved-essential-receipt');
  }
  const resolvedReceiptPath = resolve(receiptPath);
  const receiptInfo = await lstat(resolvedReceiptPath).catch(() => null);
  if (!receiptInfo?.isFile() || receiptInfo.isSymbolicLink()) {
    throw new Error('Approved essential-package receipt could not be read as a regular file');
  }
  const [realAppRoot, realReceiptPath] = await Promise.all([
    realpath(appRoot),
    realpath(resolvedReceiptPath),
  ]);
  if (isWithin(realAppRoot, realReceiptPath)) {
    throw new Error('Approved essential-package receipt must remain outside the app bundle');
  }
  const receiptBytes = await readFile(resolvedReceiptPath);
  const receipt = parseCanonicalJSON(receiptBytes, 'Approved essential-package receipt');
  exactFields(
    receipt,
    [
      'schemaVersion',
      'status',
      'authority',
      'approvedAt',
      'decisionReference',
      'packageID',
      'chapterIDs',
      'packageManifestSHA256',
      'manifestDigest',
      'payloadPath',
      'payloadSHA256',
    ],
    'Approved essential-package receipt',
  );
  if (receipt.schemaVersion !== 1
      || receipt.status !== 'APPROVED_BY_EDITOR_IN_CHIEF'
      || receipt.authority !== 'editor-in-chief'
      || typeof receipt.approvedAt !== 'string'
      || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/u.test(receipt.approvedAt)
      || typeof receipt.decisionReference !== 'string'
      || receipt.decisionReference.length < 12
      || receipt.packageID !== essentialPackageID
      || !Array.isArray(receipt.chapterIDs)
      || JSON.stringify(receipt.chapterIDs) !== JSON.stringify(essentialChapterIDs)
      || receipt.packageManifestSHA256 !== sha256(essentialPackage.manifestBytes)
      || receipt.manifestDigest !== essentialPackage.manifest.manifestDigest
      || !safePackagePath(receipt.payloadPath)
      || receipt.payloadPath !== essentialPackage.payloadPath
      || receipt.payloadSHA256 !== sha256(essentialPackage.payloadBytes)) {
    throw new Error('Bundled essential signed package does not match the exact editor-approved receipt');
  }
}

function containsPrivateJWKOrSecretField(value) {
  if (Array.isArray(value)) return value.some(containsPrivateJWKOrSecretField);
  if (value === null || typeof value !== 'object') return false;
  if (typeof value.kty === 'string' && Object.hasOwn(value, 'd')) return true;
  for (const [key, child] of Object.entries(value)) {
    const normalized = key.toLowerCase().replace(/[^a-z0-9]/g, '');
    if (normalized.includes('privatekey')
        || normalized.includes('signingkey')
        || normalized === 'clientsecret'
        || normalized === 'secretkey') {
      return true;
    }
    if (containsPrivateJWKOrSecretField(child)) return true;
  }
  return false;
}

function containsStructuredSecret(bytes) {
  if (bytes.length === 0 || bytes.length > maximumStructuredSecretInspectionBytes) {
    return false;
  }
  const text = bytes.toString('utf8').trim();
  if (!(text.startsWith('{') || text.startsWith('['))) return false;
  try {
    return containsPrivateJWKOrSecretField(JSON.parse(text));
  } catch {
    return false;
  }
}

function parsesAsPrivateKey(bytes) {
  if (bytes.length === 0 || bytes.length > maximumPrivateKeyInspectionBytes) return false;
  const attempts = [
    () => createPrivateKey(bytes),
    () => createPrivateKey({ key: bytes, format: 'der', type: 'pkcs8' }),
    () => createPrivateKey({ key: bytes, format: 'der', type: 'sec1' }),
    () => createPrivateKey({ key: bytes, format: 'der', type: 'pkcs1' }),
  ];
  return attempts.some((attempt) => {
    try {
      attempt();
      return true;
    } catch {
      return false;
    }
  });
}

function validateReleasePath(appRoot, path) {
  const pathBasename = basename(path);
  if (forbiddenReleaseBasenames.includes(pathBasename)) {
    throw new Error(`Release app contains a DEBUG-only resource: ${path}`);
  }
  const extension = extname(pathBasename).toLowerCase();
  if (forbiddenReleaseExtensions.includes(extension)) {
    throw new Error(`Release app contains a forbidden key, test or config file: ${path}`);
  }
  const components = relative(appRoot, path).split(sep);
  if (components.some((component) => component === 'Tests' || component === 'UITests'
      || component.endsWith('.xctest') || component === 'ContentKitTestSupport.framework')) {
    throw new Error(`Release app contains test support: ${path}`);
  }
}

export async function validateReleaseAppBoundary(
  appPath,
  {
    mode = releaseValidationModes.boundaryOnly,
    approvedTrustReceiptPath,
    approvedEssentialReceiptPath,
  } = {},
) {
  const appRoot = resolve(appPath);
  const info = await lstat(appRoot).catch(() => null);
  if (!info?.isDirectory() || !appRoot.endsWith('.app')) {
    throw new Error(`Expected a built .app directory, received: ${appRoot}`);
  }
  if (!Object.values(releaseValidationModes).includes(mode)) {
    throw new Error(`Unknown release validation mode: ${mode}`);
  }

  const forbiddenBuffers = forbiddenReleaseByteSequences.map((value) => ({
    value,
    bytes: Buffer.from(value, 'utf8'),
  }));
  const files = await filesUnder(appRoot);
  for (const path of files) {
    validateReleasePath(appRoot, path);
    const bytes = await readFile(path);
    for (const forbidden of forbiddenBuffers) {
      if (bytes.indexOf(forbidden.bytes) !== -1) {
        throw new Error(
          `Release app contains DEBUG-only bytes ${JSON.stringify(forbidden.value)} in ${path}`,
        );
      }
    }
    if (parsesAsPrivateKey(bytes) || containsStructuredSecret(bytes)) {
      throw new Error(`Release app contains private signing material: ${path}`);
    }
  }

  if (mode === releaseValidationModes.releaseCandidate) {
    const trustResources = files.filter((path) => basename(path) === trustResourceBasename);
    if (trustResources.length !== 1) {
      throw new Error('Release candidate must contain exactly one launch-package-trust.json');
    }
    const trustBytes = await readFile(trustResources[0]);
    const trust = validateTrustDocument(trustBytes);
    await validateApprovedTrustReceipt(
      approvedTrustReceiptPath,
      trustBytes,
      trust,
    );

    const essentialPackage = await validateEssentialPackageRoot(
      appRoot,
      files,
      trust,
    );
    await validateApprovedEssentialReceipt(
      approvedEssentialReceiptPath,
      appRoot,
      essentialPackage,
    );
  }

  return { appRoot, mode, status: 'PASS' };
}

async function main() {
  const valueAfter = (flag) => {
    const index = process.argv.indexOf(flag);
    return index === -1 ? undefined : process.argv[index + 1];
  };
  const appPath = valueAfter('--app');
  if (!appPath) {
    throw new Error(
      'Usage: validate-release-app-boundary.mjs --app <path.app> '
        + '[--mode boundary-only|release-candidate] '
        + '[--approved-trust-receipt <path.json>] '
        + '[--approved-essential-receipt <external-path.json>]\n'
        + 'Release-candidate mode requires the complete signed package root at '
        + 'JourneyContent/essential-free-v1/package-manifest.json.',
    );
  }
  const result = await validateReleaseAppBoundary(appPath, {
    mode: valueAfter('--mode') ?? releaseValidationModes.boundaryOnly,
    approvedTrustReceiptPath: valueAfter('--approved-trust-receipt'),
    approvedEssentialReceiptPath: valueAfter('--approved-essential-receipt'),
  });
  console.log(`Release app ${result.mode}: ${result.status}`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
