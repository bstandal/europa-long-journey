import CryptoKit
import Foundation

public struct PackageFileRecord: Codable, Equatable, Sendable {
    public let path: String
    public let bytes: Int64
    public let sha256: String

    public init(path: String, bytes: Int64, sha256: String) {
        self.path = path
        self.bytes = bytes
        self.sha256 = sha256
    }
}

public struct PackageSignature: Codable, Equatable, Sendable {
    public let algorithm: String
    public let keyID: String
    public let value: String

    public init(algorithm: String, keyID: String, value: String) {
        self.algorithm = algorithm
        self.keyID = keyID
        self.value = value
    }
}

/// Persisted state surfaces an authored package migration is allowed to
/// rewrite. Package identity, chapter identity, ownership and public content
/// are deliberately absent from this vocabulary.
public enum PackageSaveMigrationField: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case beatIdentity
    case interactionState
    case cameraAndTextAnchors
    case narrationAndAudioPosition
    case cumulativeWorldState
}

/// The only cumulative-world record identities one migration edge may touch.
/// Both sides are explicit because an authored migration may rename, remove or
/// introduce a record. Runtime mutation validation can therefore compare the
/// exact changed-ID set with signed package authority instead of granting the
/// package write access to the complete shared world.
public struct PackageSaveMigrationWorldOwnershipDelta: Codable, Equatable, Hashable, Sendable {
    public let oldEffectIDs: [WorldEffectID]
    public let newEffectIDs: [WorldEffectID]
    public let oldNodeIDs: [WorldNodeID]
    public let newNodeIDs: [WorldNodeID]
    public let oldTraceIDs: [WorldTraceID]
    public let newTraceIDs: [WorldTraceID]

    public init(
        oldEffectIDs: [WorldEffectID] = [],
        newEffectIDs: [WorldEffectID] = [],
        oldNodeIDs: [WorldNodeID] = [],
        newNodeIDs: [WorldNodeID] = [],
        oldTraceIDs: [WorldTraceID] = [],
        newTraceIDs: [WorldTraceID] = []
    ) {
        self.oldEffectIDs = oldEffectIDs
        self.newEffectIDs = newEffectIDs
        self.oldNodeIDs = oldNodeIDs
        self.newNodeIDs = newNodeIDs
        self.oldTraceIDs = oldTraceIDs
        self.newTraceIDs = newTraceIDs
    }

    public static let empty = PackageSaveMigrationWorldOwnershipDelta()

    var ownsAnyWorldRecord: Bool {
        !oldEffectIDs.isEmpty || !newEffectIDs.isEmpty
            || !oldNodeIDs.isEmpty || !newNodeIDs.isEmpty
            || !oldTraceIDs.isEmpty || !newTraceIDs.isEmpty
    }
}

/// A signed graph edge from one package content version to another.
///
/// `implementationSHA256` is the SHA-256 of the canonical, reviewable
/// transform descriptor registered by compiled app code. It is not a claimed
/// hash of executable bytes. Runtime admission requires an exact descriptor
/// match before the transform can run.
public struct PackageSaveMigrationDeclaration: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let fromContentVersion: SchemaVersion
    public let toContentVersion: SchemaVersion
    public let requiredSaveFormatVersion: Int
    public let requiredStateSchemaVersion: Int
    public let fields: [PackageSaveMigrationField]
    public let worldOwnershipDelta: PackageSaveMigrationWorldOwnershipDelta
    public let implementationSHA256: String

    public init(
        id: String,
        fromContentVersion: SchemaVersion,
        toContentVersion: SchemaVersion,
        requiredSaveFormatVersion: Int,
        requiredStateSchemaVersion: Int,
        fields: [PackageSaveMigrationField],
        worldOwnershipDelta: PackageSaveMigrationWorldOwnershipDelta = .empty,
        implementationSHA256: String
    ) {
        self.id = id
        self.fromContentVersion = fromContentVersion
        self.toContentVersion = toContentVersion
        self.requiredSaveFormatVersion = requiredSaveFormatVersion
        self.requiredStateSchemaVersion = requiredStateSchemaVersion
        self.fields = fields
        self.worldOwnershipDelta = worldOwnershipDelta
        self.implementationSHA256 = implementationSHA256
    }
}

/// Signed, metadata-bound inventory emitted by the native package compiler.
public struct SignedPackageManifest: Codable, Equatable, Sendable {
    public let packageID: PackageID
    public let packageVersion: SchemaVersion
    public let schemaVersion: SchemaVersion
    public let minimumRuntime: SchemaVersion
    public let saveMigrationSupportedSourceVersions: [SchemaVersion]?
    public let saveMigrationDescriptorInventorySHA256: String?
    /// Absent for packages which do not supersede a persisted content
    /// version. When present, every edge is covered by the manifest digest and
    /// signature.
    public let saveMigrations: [PackageSaveMigrationDeclaration]?
    public let files: [PackageFileRecord]
    public let manifestDigest: String
    public let signature: PackageSignature

    public init(
        packageID: PackageID,
        packageVersion: SchemaVersion,
        schemaVersion: SchemaVersion,
        minimumRuntime: SchemaVersion,
        saveMigrationSupportedSourceVersions: [SchemaVersion]? = nil,
        saveMigrationDescriptorInventorySHA256: String? = nil,
        saveMigrations: [PackageSaveMigrationDeclaration]? = nil,
        files: [PackageFileRecord],
        manifestDigest: String,
        signature: PackageSignature
    ) {
        self.packageID = packageID
        self.packageVersion = packageVersion
        self.schemaVersion = schemaVersion
        self.minimumRuntime = minimumRuntime
        self.saveMigrationSupportedSourceVersions = saveMigrationSupportedSourceVersions
        self.saveMigrationDescriptorInventorySHA256 = saveMigrationDescriptorInventorySHA256
        self.saveMigrations = saveMigrations
        self.files = files
        self.manifestDigest = manifestDigest
        self.signature = signature
    }
}

public enum ContentPackageVerificationScope: Equatable, Sendable {
    /// The signed manifest, exact installed tree, every declared file size,
    /// and the canonical payload bytes have been verified for runtime use.
    /// Non-payload asset digests remain mandatory at their decode/open edge.
    case runtimeAdmission

    /// Every file byte declared by the signed manifest has been hashed. This
    /// is the only scope accepted by the staging/activation boundary.
    case completePackage
}

public struct VerifiedContentPackage: Sendable {
    public let manifest: SignedPackageManifest
    public let payload: ContentPackagePayload
    public let verificationScope: ContentPackageVerificationScope

    init(
        manifest: SignedPackageManifest,
        payload: ContentPackagePayload,
        verificationScope: ContentPackageVerificationScope = .completePackage
    ) {
        self.manifest = manifest
        self.payload = payload
        self.verificationScope = verificationScope
    }
}

public enum PackageVerificationError: Error, Equatable, Sendable, CustomStringConvertible {
    case malformedManifest(String)
    case unsupportedSchema(required: SchemaVersion, supported: SchemaVersion)
    case unsupportedRuntime(required: SchemaVersion, available: SchemaVersion)
    case untrustedSigningKey(String)
    case invalidManifestDigest
    case invalidSignature
    case unsafePath(String)
    case installedTreeMismatch
    case fileSizeMismatch(String)
    case fileDigestMismatch(String)
    case missingContentPayload
    case multipleContentPayloads
    case packageIdentityMismatch
    case packageSpecMismatch(String)
    case installedByteCountOverflow
    case installedByteBudgetExceeded(actual: Int64, maximum: Int64)

    public var description: String {
        switch self {
        case let .malformedManifest(reason):
            "Malformed package manifest: \(reason)"
        case let .unsupportedSchema(required, supported):
            "Package schema \(required) is not supported by schema \(supported)"
        case let .unsupportedRuntime(required, available):
            "Package requires runtime \(required); this app provides \(available)"
        case let .untrustedSigningKey(keyID):
            "Package signing key is not trusted: \(keyID)"
        case .invalidManifestDigest:
            "Package manifest digest does not bind its metadata and files"
        case .invalidSignature:
            "Package signature is invalid"
        case let .unsafePath(path):
            "Unsafe package path: \(path)"
        case .installedTreeMismatch:
            "Installed package tree does not match the signed inventory"
        case let .fileSizeMismatch(path):
            "Installed package file has the wrong size: \(path)"
        case let .fileDigestMismatch(path):
            "Installed package file has the wrong digest: \(path)"
        case .missingContentPayload:
            "Package contains no canonical content payload"
        case .multipleContentPayloads:
            "Package contains more than one canonical content payload"
        case .packageIdentityMismatch:
            "Manifest package ID does not match the content payload"
        case let .packageSpecMismatch(reason):
            "Package does not match its trusted catalog specification: \(reason)"
        case .installedByteCountOverflow:
            "Installed package byte count exceeds the supported integer range"
        case let .installedByteBudgetExceeded(actual, maximum):
            "Installed package requires \(actual) bytes; its maximum is \(maximum) bytes"
        }
    }
}

public enum ContentPackageVerifier {
    public static let manifestFileName = "package-manifest.json"
    public static let signatureAlgorithm = "P-256-SHA256"

    private static let integrityHeader = "long-west-package-v1"
    private static let manifestKeys: Set<String> = [
        "packageID", "packageVersion", "schemaVersion", "minimumRuntime",
        "saveMigrationSupportedSourceVersions", "saveMigrationDescriptorInventorySHA256",
        "saveMigrations", "files", "manifestDigest", "signature",
    ]
    private static let requiredManifestKeys = manifestKeys.subtracting([
        "saveMigrationSupportedSourceVersions",
        "saveMigrationDescriptorInventorySHA256",
        "saveMigrations",
    ])
    private static let versionKeys: Set<String> = ["major", "minor", "patch"]
    private static let fileKeys: Set<String> = ["path", "bytes", "sha256"]
    private static let signatureKeys: Set<String> = ["algorithm", "keyID", "value"]
    private static let saveMigrationKeys: Set<String> = [
        "id", "fromContentVersion", "toContentVersion",
        "requiredSaveFormatVersion", "requiredStateSchemaVersion", "fields",
        "worldOwnershipDelta", "implementationSHA256",
    ]
    private static let worldOwnershipDeltaKeys: Set<String> = [
        "oldEffectIDs", "newEffectIDs", "oldNodeIDs", "newNodeIDs",
        "oldTraceIDs", "newTraceIDs",
    ]
    private static let maximumSaveMigrationEdges = 128
    private static let payloadKeys: Set<String> = [
        "schemaVersion", "packageID", "worldSeed", "chapters", "scenes", "audioTimelines",
        "responsiveAudioPrograms", "accessibility",
    ]

    /// Verifies a package in an isolated staging directory before atomic activation.
    /// The trusted key is supplied by the app, never by the downloaded package.
    public static func verifyPackage(
        at packageRoot: URL,
        expectedPackage: ContentPackageSpec,
        trustedPublicKeys: [String: Data],
        supportedSchema: SchemaVersion,
        runtimeVersion: SchemaVersion
    ) throws -> VerifiedContentPackage {
        let root = packageRoot.resolvingSymlinksInPath().standardizedFileURL
        let manifestURL = root.appending(path: manifestFileName, directoryHint: .notDirectory)
        let manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        let manifest = try verifyManifest(
            manifestData,
            expectedPackage: expectedPackage,
            trustedPublicKeys: trustedPublicKeys,
            supportedSchema: supportedSchema,
            runtimeVersion: runtimeVersion
        )
        try verifyInstalledTree(root: root, manifest: manifest)
        let payload = try decodeCanonicalPayload(root: root, manifest: manifest)
        try validate(payload, manifest: manifest, expectedPackage: expectedPackage)
        return VerifiedContentPackage(
            manifest: manifest,
            payload: payload,
            verificationScope: .completePackage
        )
    }

    /// Reconstructs runtime authority without re-reading every large scene and
    /// audio asset at cold launch. The signed manifest, exact safe tree and all
    /// declared sizes are checked. The one canonical payload is additionally
    /// digest-verified before decoding. Every other asset remains bound to its
    /// signed size and digest and must cross its decode/open verifier on first
    /// use.
    public static func admitPackageAtRuntime(
        at packageRoot: URL,
        expectedPackage: ContentPackageSpec,
        trustedPublicKeys: [String: Data],
        supportedSchema: SchemaVersion,
        runtimeVersion: SchemaVersion
    ) throws -> VerifiedContentPackage {
        let root = packageRoot.resolvingSymlinksInPath().standardizedFileURL
        let manifestURL = root.appending(path: manifestFileName, directoryHint: .notDirectory)
        let manifestData = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        let manifest = try verifyManifest(
            manifestData,
            expectedPackage: expectedPackage,
            trustedPublicKeys: trustedPublicKeys,
            supportedSchema: supportedSchema,
            runtimeVersion: runtimeVersion
        )
        try verifyInstalledTreeMetadata(root: root, manifest: manifest)
        let payload = try decodeDigestVerifiedCanonicalPayload(root: root, manifest: manifest)
        try validate(payload, manifest: manifest, expectedPackage: expectedPackage)
        return VerifiedContentPackage(
            manifest: manifest,
            payload: payload,
            verificationScope: .runtimeAdmission
        )
    }

    /// Verifies the complete signed manifest contract without reading payload
    /// files. Callers can reject an untrusted or impossible inventory before
    /// allocating a staging generation.
    public static func verifyManifest(
        _ manifestData: Data,
        expectedPackage: ContentPackageSpec,
        trustedPublicKeys: [String: Data],
        supportedSchema: SchemaVersion,
        runtimeVersion: SchemaVersion
    ) throws -> SignedPackageManifest {
        try validateManifestJSONShape(manifestData)
        let manifest: SignedPackageManifest
        do {
            manifest = try JSONDecoder().decode(SignedPackageManifest.self, from: manifestData)
        } catch {
            throw PackageVerificationError.malformedManifest(String(describing: error))
        }

        try validate(manifest, supportedSchema: supportedSchema, runtimeVersion: runtimeVersion)
        try verifyDigestAndSignature(manifest, trustedPublicKeys: trustedPublicKeys)
        try validate(manifest, matches: expectedPackage)
        try validateInstalledByteBudget(
            manifest: manifest,
            manifestBytes: manifestData.count,
            maximumInstalledBytes: expectedPackage.maximumInstalledBytes
        )
        return manifest
    }

    public static func integrityMaterial(for manifest: SignedPackageManifest) throws -> Data {
        try validateManifestRecords(manifest)
        try validateSaveMigrations(manifest)
        let fileLines = manifest.files.map { record in
            "file=\(record.path)\t\(record.bytes)\t\(record.sha256)"
        }
        let migrationLines: [String]
        if let declarations = manifest.saveMigrations,
           let sources = manifest.saveMigrationSupportedSourceVersions,
           let descriptorDigest = manifest.saveMigrationDescriptorInventorySHA256 {
            migrationLines = [
                "saveMigrationSupportedSources=\(sources.map(\.description).joined(separator: ","))",
                "saveMigrationDescriptorInventory=\(descriptorDigest)",
            ] + declarations.map { declaration in
                canonicalSaveMigrationEdgeLine(declaration)
            }
        } else {
            migrationLines = []
        }
        let lines = [
            integrityHeader,
            "packageID=\(manifest.packageID.rawValue)",
            "packageVersion=\(manifest.packageVersion)",
            "schemaVersion=\(manifest.schemaVersion)",
            "minimumRuntime=\(manifest.minimumRuntime)",
        ] + migrationLines + fileLines + [""]
        return Data(lines.joined(separator: "\n").utf8)
    }

    public static func manifestDigest(for manifest: SignedPackageManifest) throws -> String {
        hexDigest(SHA256.hash(data: try integrityMaterial(for: manifest)))
    }

    private static func validate(
        _ manifest: SignedPackageManifest,
        supportedSchema: SchemaVersion,
        runtimeVersion: SchemaVersion
    ) throws {
        try validateManifestRecords(manifest)
        guard isValidStableID(manifest.packageID.rawValue) else {
            throw PackageVerificationError.malformedManifest("packageID must be stable kebab case")
        }
        guard isValidVersion(manifest.packageVersion), isValidVersion(manifest.schemaVersion),
              isValidVersion(manifest.minimumRuntime) else {
            throw PackageVerificationError.malformedManifest("versions require non-negative components")
        }
        guard manifest.schemaVersion.major == supportedSchema.major,
              manifest.schemaVersion <= supportedSchema else {
            throw PackageVerificationError.unsupportedSchema(
                required: manifest.schemaVersion,
                supported: supportedSchema
            )
        }
        guard manifest.minimumRuntime <= runtimeVersion else {
            throw PackageVerificationError.unsupportedRuntime(
                required: manifest.minimumRuntime,
                available: runtimeVersion
            )
        }
        guard isLowercaseSHA256(manifest.manifestDigest) else {
            throw PackageVerificationError.malformedManifest("manifestDigest must be lowercase SHA-256")
        }
        try validateSaveMigrations(manifest)
        guard manifest.signature.algorithm == signatureAlgorithm,
              isValidStableID(manifest.signature.keyID),
              !manifest.signature.value.isEmpty,
              Data(base64Encoded: manifest.signature.value) != nil else {
            throw PackageVerificationError.malformedManifest("a P-256 SHA-256 signature is required")
        }
    }

    private static func validate(
        _ manifest: SignedPackageManifest,
        matches expectedPackage: ContentPackageSpec
    ) throws {
        guard expectedPackage.maximumInstalledBytes > 0,
              isValidVersion(expectedPackage.version),
              isValidVersion(expectedPackage.minimumRuntime),
              !expectedPackage.chapterIDs.isEmpty else {
            throw PackageVerificationError.packageSpecMismatch("trusted package specification is invalid")
        }
        guard manifest.packageID == expectedPackage.id else {
            throw PackageVerificationError.packageSpecMismatch("package ID changed")
        }
        guard manifest.packageVersion == expectedPackage.version else {
            throw PackageVerificationError.packageSpecMismatch("package version changed")
        }
        guard manifest.minimumRuntime == expectedPackage.minimumRuntime else {
            throw PackageVerificationError.packageSpecMismatch("minimum runtime changed")
        }
    }

    private static func validateInstalledByteBudget(
        manifest: SignedPackageManifest,
        manifestBytes: Int,
        maximumInstalledBytes: Int64
    ) throws {
        guard let manifestByteCount = Int64(exactly: manifestBytes) else {
            throw PackageVerificationError.installedByteCountOverflow
        }
        var installedBytes = manifestByteCount
        for record in manifest.files {
            let result = installedBytes.addingReportingOverflow(record.bytes)
            guard !result.overflow else {
                throw PackageVerificationError.installedByteCountOverflow
            }
            installedBytes = result.partialValue
        }
        guard installedBytes <= maximumInstalledBytes else {
            throw PackageVerificationError.installedByteBudgetExceeded(
                actual: installedBytes,
                maximum: maximumInstalledBytes
            )
        }
    }

    private static func validateManifestRecords(_ manifest: SignedPackageManifest) throws {
        guard !manifest.files.isEmpty else {
            throw PackageVerificationError.malformedManifest("files cannot be empty")
        }
        var paths: Set<String> = []
        for record in manifest.files {
            try validatePackagePath(record.path)
            guard record.path != manifestFileName else {
                throw PackageVerificationError.malformedManifest("the manifest cannot inventory itself")
            }
            guard paths.insert(record.path).inserted else {
                throw PackageVerificationError.malformedManifest("duplicate file path: \(record.path)")
            }
            guard record.bytes >= 0, isLowercaseSHA256(record.sha256) else {
                throw PackageVerificationError.malformedManifest("invalid file record: \(record.path)")
            }
        }
        let sortedPaths = manifest.files.map(\.path).sorted(by: utf8LessThan)
        guard manifest.files.map(\.path) == sortedPaths else {
            throw PackageVerificationError.malformedManifest("file records must use canonical byte order")
        }
    }

    private static func validateSaveMigrations(_ manifest: SignedPackageManifest) throws {
        let valuesArePresent = [
            manifest.saveMigrations != nil,
            manifest.saveMigrationSupportedSourceVersions != nil,
            manifest.saveMigrationDescriptorInventorySHA256 != nil,
        ]
        guard valuesArePresent.contains(true) else { return }
        guard valuesArePresent.allSatisfy({ $0 }),
              let declarations = manifest.saveMigrations,
              let supportedSources = manifest.saveMigrationSupportedSourceVersions,
              let descriptorInventoryDigest = manifest.saveMigrationDescriptorInventorySHA256 else {
            throw PackageVerificationError.malformedManifest(
                "save migration graph, supported sources and descriptor inventory digest must be present together"
            )
        }
        guard !declarations.isEmpty,
              declarations.count <= maximumSaveMigrationEdges,
              !supportedSources.isEmpty,
              supportedSources.count <= maximumSaveMigrationEdges,
              isLowercaseSHA256(descriptorInventoryDigest) else {
            throw PackageVerificationError.malformedManifest(
                "save migration authority is empty, oversized or has an invalid descriptor inventory digest"
            )
        }
        let authoredIDs = declarations.map(\.id)
        guard authoredIDs == authoredIDs.sorted(by: utf8LessThan),
              Set(authoredIDs).count == authoredIDs.count else {
            throw PackageVerificationError.malformedManifest(
                "saveMigrations must use unique migration IDs in canonical byte order"
            )
        }
        for declaration in declarations {
            let fieldNames = declaration.fields.map(\.rawValue)
            guard isValidStableID(declaration.id),
                  isValidVersion(declaration.fromContentVersion),
                  isValidVersion(declaration.toContentVersion),
                  declaration.fromContentVersion < declaration.toContentVersion,
                  declaration.toContentVersion <= manifest.packageVersion,
                  declaration.requiredSaveFormatVersion > 0,
                  declaration.requiredStateSchemaVersion > 0,
                  !fieldNames.isEmpty,
                  fieldNames == fieldNames.sorted(by: utf8LessThan),
                  Set(fieldNames).count == fieldNames.count,
                  isLowercaseSHA256(declaration.implementationSHA256) else {
                throw PackageVerificationError.malformedManifest(
                    "invalid signed save migration declaration: \(declaration.id)"
                )
            }
            try validateWorldOwnershipDelta(declaration)
        }

        guard supportedSources.allSatisfy({ source in
            isValidVersion(source) && source < manifest.packageVersion
        }), supportedSources == supportedSources.sorted(),
              Set(supportedSources).count == supportedSources.count else {
            throw PackageVerificationError.malformedManifest(
                "save migration supported sources must be unique, ordered and precede the target"
            )
        }
        let declaredSources = Set(declarations.map(\.fromContentVersion))
        guard declaredSources == Set(supportedSources) else {
            throw PackageVerificationError.malformedManifest(
                "save migration supported sources must exactly equal graph source versions"
            )
        }
        let outgoing = Dictionary(grouping: declarations, by: \.fromContentVersion)
        var memo: [SchemaVersion: Int] = [:]
        func pathCount(from version: SchemaVersion) -> Int {
            if version == manifest.packageVersion { return 1 }
            if let cached = memo[version] { return cached }
            var count = 0
            for edge in outgoing[version] ?? [] {
                count = min(2, count + pathCount(from: edge.toContentVersion))
                if count == 2 { break }
            }
            memo[version] = count
            return count
        }
        for source in supportedSources {
            switch pathCount(from: source) {
            case 1:
                continue
            case 0:
                throw PackageVerificationError.malformedManifest(
                    "save migration graph has no complete path from \(source) to \(manifest.packageVersion)"
                )
            default:
                throw PackageVerificationError.malformedManifest(
                    "save migration graph has ambiguous paths from \(source) to \(manifest.packageVersion)"
                )
            }
        }
    }

    private static func validateWorldOwnershipDelta(
        _ declaration: PackageSaveMigrationDeclaration
    ) throws {
        let delta = declaration.worldOwnershipDelta
        let allIDs: [[String]] = [
            delta.oldEffectIDs.map(\.rawValue),
            delta.newEffectIDs.map(\.rawValue),
            delta.oldNodeIDs.map(\.rawValue),
            delta.newNodeIDs.map(\.rawValue),
            delta.oldTraceIDs.map(\.rawValue),
            delta.newTraceIDs.map(\.rawValue),
        ]
        guard allIDs.allSatisfy({ identifiers in
            identifiers.allSatisfy(isValidStableID)
                && identifiers == identifiers.sorted(by: utf8LessThan)
                && Set(identifiers).count == identifiers.count
        }) else {
            throw PackageVerificationError.malformedManifest(
                "save migration world ownership IDs must be stable, unique and canonical: \(declaration.id)"
            )
        }
        let declaresWorldMutation = declaration.fields.contains(.cumulativeWorldState)
        guard declaresWorldMutation == delta.ownsAnyWorldRecord else {
            throw PackageVerificationError.malformedManifest(
                "save migration world ownership must be explicit exactly when cumulativeWorldState is declared: \(declaration.id)"
            )
        }
    }

    private static func canonicalSaveMigrationEdgeLine(
        _ declaration: PackageSaveMigrationDeclaration
    ) -> String {
        let delta = declaration.worldOwnershipDelta
        let fields = declaration.fields.map(\.rawValue).joined(separator: ",")
        return [
            "saveMigration=\(declaration.id)",
            declaration.fromContentVersion.description,
            declaration.toContentVersion.description,
            "save=\(declaration.requiredSaveFormatVersion)",
            "state=\(declaration.requiredStateSchemaVersion)",
            "fields=\(fields)",
            "oldEffectIDs=\(delta.oldEffectIDs.map(\.rawValue).joined(separator: ","))",
            "newEffectIDs=\(delta.newEffectIDs.map(\.rawValue).joined(separator: ","))",
            "oldNodeIDs=\(delta.oldNodeIDs.map(\.rawValue).joined(separator: ","))",
            "newNodeIDs=\(delta.newNodeIDs.map(\.rawValue).joined(separator: ","))",
            "oldTraceIDs=\(delta.oldTraceIDs.map(\.rawValue).joined(separator: ","))",
            "newTraceIDs=\(delta.newTraceIDs.map(\.rawValue).joined(separator: ","))",
            "implementation=\(declaration.implementationSHA256)",
        ].joined(separator: "\t")
    }

    private static func verifyDigestAndSignature(
        _ manifest: SignedPackageManifest,
        trustedPublicKeys: [String: Data]
    ) throws {
        guard try manifestDigest(for: manifest) == manifest.manifestDigest else {
            throw PackageVerificationError.invalidManifestDigest
        }
        guard let keyData = trustedPublicKeys[manifest.signature.keyID] else {
            throw PackageVerificationError.untrustedSigningKey(manifest.signature.keyID)
        }
        guard let signatureData = Data(base64Encoded: manifest.signature.value) else {
            throw PackageVerificationError.invalidSignature
        }
        do {
            let publicKey = try P256.Signing.PublicKey(x963Representation: keyData)
            let signature = try P256.Signing.ECDSASignature(derRepresentation: signatureData)
            guard publicKey.isValidSignature(signature, for: Data(manifest.manifestDigest.utf8)) else {
                throw PackageVerificationError.invalidSignature
            }
        } catch let error as PackageVerificationError {
            throw error
        } catch {
            throw PackageVerificationError.invalidSignature
        }
    }

    private static func verifyInstalledTree(
        root: URL,
        manifest: SignedPackageManifest
    ) throws {
        try verifyInstalledTreeMetadata(root: root, manifest: manifest)

        for record in manifest.files {
            let fileURL = root.appending(path: record.path, directoryHint: .notDirectory).standardizedFileURL
            guard fileURL.path.hasPrefix(root.path + "/") else {
                throw PackageVerificationError.unsafePath(record.path)
            }
            let (bytes, digest) = try streamedDigest(fileURL)
            guard bytes == record.bytes else {
                throw PackageVerificationError.fileSizeMismatch(record.path)
            }
            guard digest == record.sha256 else {
                throw PackageVerificationError.fileDigestMismatch(record.path)
            }
        }
    }

    private static func verifyInstalledTreeMetadata(
        root: URL,
        manifest: SignedPackageManifest
    ) throws {
        let actualTree = try installedTreePaths(root: root)
        let expectedFiles = Set(manifest.files.map(\.path) + [manifestFileName])
        let expectedDirectories = packageDirectories(for: expectedFiles)
        guard actualTree.files == expectedFiles,
              actualTree.directories == expectedDirectories else {
            throw PackageVerificationError.installedTreeMismatch
        }

        for record in manifest.files {
            let fileURL = root
                .appending(path: record.path, directoryHint: .notDirectory)
                .standardizedFileURL
            guard fileURL.path.hasPrefix(root.path + "/") else {
                throw PackageVerificationError.unsafePath(record.path)
            }
            let values: URLResourceValues
            do {
                values = try fileURL.resourceValues(
                    forKeys: [
                        .fileSizeKey,
                        .isDirectoryKey,
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                    ]
                )
            } catch {
                throw PackageVerificationError.installedTreeMismatch
            }
            guard values.isSymbolicLink != true,
                  values.isDirectory != true,
                  values.isRegularFile == true else {
                throw PackageVerificationError.installedTreeMismatch
            }
            guard let size = values.fileSize, Int64(size) == record.bytes else {
                throw PackageVerificationError.fileSizeMismatch(record.path)
            }
        }
    }

    private static func decodeCanonicalPayload(
        root: URL,
        manifest: SignedPackageManifest
    ) throws -> ContentPackagePayload {
        var candidates: [Data] = []
        for record in manifest.files where record.path.lowercased().hasSuffix(".json") {
            let data = try Data(
                contentsOf: root.appending(path: record.path, directoryHint: .notDirectory),
                options: [.mappedIfSafe]
            )
            if try isCanonicalPayloadJSON(data) {
                candidates.append(data)
            }
        }
        guard !candidates.isEmpty else { throw PackageVerificationError.missingContentPayload }
        guard candidates.count == 1 else { throw PackageVerificationError.multipleContentPayloads }
        return try ContentDocumentDecoder.decodePackage(candidates[0])
    }

    private static func decodeDigestVerifiedCanonicalPayload(
        root: URL,
        manifest: SignedPackageManifest
    ) throws -> ContentPackagePayload {
        var candidates: [(record: PackageFileRecord, data: Data)] = []
        for record in manifest.files where record.path.lowercased().hasSuffix(".json") {
            let data = try Data(
                contentsOf: root.appending(path: record.path, directoryHint: .notDirectory),
                options: [.mappedIfSafe]
            )
            if try isCanonicalPayloadJSON(data) {
                candidates.append((record, data))
            }
        }
        guard !candidates.isEmpty else { throw PackageVerificationError.missingContentPayload }
        guard candidates.count == 1 else { throw PackageVerificationError.multipleContentPayloads }
        let candidate = candidates[0]
        guard Int64(candidate.data.count) == candidate.record.bytes else {
            throw PackageVerificationError.fileSizeMismatch(candidate.record.path)
        }
        let digest = hexDigest(SHA256.hash(data: candidate.data))
        guard digest == candidate.record.sha256 else {
            throw PackageVerificationError.fileDigestMismatch(candidate.record.path)
        }
        return try ContentDocumentDecoder.decodePackage(candidate.data)
    }

    private static func validate(
        _ payload: ContentPackagePayload,
        manifest: SignedPackageManifest,
        expectedPackage: ContentPackageSpec
    ) throws {
        guard payload.packageID == manifest.packageID else {
            throw PackageVerificationError.packageIdentityMismatch
        }
        guard payload.schemaVersion == manifest.schemaVersion else {
            throw PackageVerificationError.unsupportedSchema(
                required: payload.schemaVersion,
                supported: manifest.schemaVersion
            )
        }
        guard Set(payload.chapters.map(\.id)) == Set(expectedPackage.chapterIDs) else {
            throw PackageVerificationError.packageSpecMismatch("payload chapter ownership changed")
        }
    }

    private static func validateManifestJSONShape(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PackageVerificationError.malformedManifest("invalid JSON")
        }
        guard let manifest = object as? [String: Any],
              requiredManifestKeys.isSubset(of: Set(manifest.keys)),
              Set(manifest.keys).isSubset(of: manifestKeys) else {
            throw PackageVerificationError.malformedManifest("manifest fields must match the canonical contract")
        }
        for name in ["packageVersion", "schemaVersion", "minimumRuntime"] {
            guard let version = manifest[name] as? [String: Any], Set(version.keys) == versionKeys else {
                throw PackageVerificationError.malformedManifest("\(name) fields must match the canonical contract")
            }
        }
        if let sources = manifest["saveMigrationSupportedSourceVersions"] as? [[String: Any]] {
            guard sources.allSatisfy({ Set($0.keys) == versionKeys }) else {
                throw PackageVerificationError.malformedManifest(
                    "save migration supported source versions are not canonical"
                )
            }
        } else if manifest.keys.contains("saveMigrationSupportedSourceVersions") {
            throw PackageVerificationError.malformedManifest(
                "saveMigrationSupportedSourceVersions must be an array"
            )
        }
        guard let records = manifest["files"] as? [[String: Any]],
              records.allSatisfy({ Set($0.keys) == fileKeys }),
              let signature = manifest["signature"] as? [String: Any],
              Set(signature.keys) == signatureKeys else {
            throw PackageVerificationError.malformedManifest("file or signature fields are not canonical")
        }
        if let migrations = manifest["saveMigrations"] as? [[String: Any]] {
            guard migrations.allSatisfy({ migration in
                Set(migration.keys) == saveMigrationKeys
                    && (migration["fromContentVersion"] as? [String: Any]).map {
                        Set($0.keys) == versionKeys
                    } == true
                    && (migration["toContentVersion"] as? [String: Any]).map {
                        Set($0.keys) == versionKeys
                    } == true
                    && (migration["worldOwnershipDelta"] as? [String: Any]).map {
                        Set($0.keys) == worldOwnershipDeltaKeys
                    } == true
            }) else {
                throw PackageVerificationError.malformedManifest(
                    "save migration fields are not canonical"
                )
            }
        } else if manifest.keys.contains("saveMigrations") {
            throw PackageVerificationError.malformedManifest("saveMigrations must be an array")
        }
        let migrationAuthorityPresence = [
            manifest.keys.contains("saveMigrations"),
            manifest.keys.contains("saveMigrationSupportedSourceVersions"),
            manifest.keys.contains("saveMigrationDescriptorInventorySHA256"),
        ]
        guard !migrationAuthorityPresence.contains(true)
                || migrationAuthorityPresence.allSatisfy({ $0 }) else {
            throw PackageVerificationError.malformedManifest(
                "save migration graph, supported sources and descriptor inventory digest must be present together"
            )
        }
    }

    private static func isCanonicalPayloadJSON(_ data: Data) throws -> Bool {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else { return false }
        return Set(dictionary.keys) == payloadKeys
    }

    private struct InstalledTreePaths {
        var files: Set<String> = []
        var directories: Set<String> = []
    }

    private static func installedTreePaths(root: URL) throws -> InstalledTreePaths {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            throw PackageVerificationError.installedTreeMismatch
        }
        var paths = InstalledTreePaths()
        while let value = enumerator.nextObject() as? URL {
            let resource = try value.resourceValues(forKeys: keys)
            if resource.isSymbolicLink == true {
                throw PackageVerificationError.unsafePath(value.lastPathComponent)
            }
            guard resource.isDirectory == true || resource.isRegularFile == true else {
                throw PackageVerificationError.installedTreeMismatch
            }
            let resolvedValue = value.resolvingSymlinksInPath().standardizedFileURL
            guard resolvedValue.path.hasPrefix(root.path + "/") else {
                throw PackageVerificationError.unsafePath(value.path)
            }
            let relative = String(resolvedValue.path.dropFirst(root.path.count + 1))
            try validatePackagePath(relative)
            if resource.isRegularFile == true {
                paths.files.insert(relative)
            } else if resource.isDirectory == true {
                paths.directories.insert(relative)
            }
        }
        return paths
    }

    private static func packageDirectories(for filePaths: Set<String>) -> Set<String> {
        var directories: Set<String> = []
        for filePath in filePaths {
            var components = filePath.split(separator: "/").map(String.init)
            guard components.count > 1 else { continue }
            components.removeLast()
            while !components.isEmpty {
                directories.insert(components.joined(separator: "/"))
                components.removeLast()
            }
        }
        return directories
    }

    private static func streamedDigest(_ url: URL) throws -> (Int64, String) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            byteCount += Int64(data.count)
            hasher.update(data: data)
        }
        return (byteCount, hexDigest(hasher.finalize()))
    }

    private static func validatePackagePath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let containsControl = path.unicodeScalars.contains { scalar in
            scalar.value <= 0x1F || scalar.value == 0x7F
        }
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !path.contains("://"), !containsControl,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw PackageVerificationError.unsafePath(path)
        }
    }

    private static func isValidVersion(_ version: SchemaVersion) -> Bool {
        version.major >= 0 && version.minor >= 0 && version.patch >= 0
    }

    private static func isValidStableID(_ value: String) -> Bool {
        guard let first = value.utf8.first, (97 ... 122).contains(first),
              let last = value.utf8.last, (97 ... 122).contains(last) || (48 ... 57).contains(last) else {
            return false
        }
        var previousWasHyphen = false
        for byte in value.utf8 {
            let validLetter = (97 ... 122).contains(byte)
            let validDigit = (48 ... 57).contains(byte)
            if byte == 45 {
                if previousWasHyphen { return false }
                previousWasHyphen = true
            } else if validLetter || validDigit {
                previousWasHyphen = false
            } else {
                return false
            }
        }
        return true
    }

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (48 ... 57).contains(byte) || (97 ... 102).contains(byte)
        }
    }

    private static func utf8LessThan(_ left: String, _ right: String) -> Bool {
        left.utf8.lexicographicallyPrecedes(right.utf8)
    }

    private static func hexDigest<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
