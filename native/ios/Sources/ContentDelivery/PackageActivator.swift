import ContentKit
import Foundation

public struct VerifiedActivationReceipt: Equatable, Sendable {
    public let packageID: PackageID
    public let packageVersion: SchemaVersion
    public let manifestDigest: String

    public init(
        packageID: PackageID,
        packageVersion: SchemaVersion,
        manifestDigest: String
    ) {
        self.packageID = packageID
        self.packageVersion = packageVersion
        self.manifestDigest = manifestDigest
    }
}

public protocol PackageActivationVerifying: Sendable {
    func verifyPackage(
        at packageRoot: URL,
        expectedPackage: ContentPackageSpec,
        trustedPublicKeys: [String: Data],
        supportedSchema: SchemaVersion,
        runtimeVersion: SchemaVersion
    ) throws -> VerifiedActivationReceipt
}

public struct ContentPackageActivationVerifier: PackageActivationVerifying {
    public init() {}

    public func verifyPackage(
        at packageRoot: URL,
        expectedPackage: ContentPackageSpec,
        trustedPublicKeys: [String: Data],
        supportedSchema: SchemaVersion,
        runtimeVersion: SchemaVersion
    ) throws -> VerifiedActivationReceipt {
        let verified = try ContentPackageVerifier.verifyPackage(
            at: packageRoot,
            expectedPackage: expectedPackage,
            trustedPublicKeys: trustedPublicKeys,
            supportedSchema: supportedSchema,
            runtimeVersion: runtimeVersion
        )
        return VerifiedActivationReceipt(
            packageID: verified.manifest.packageID,
            packageVersion: verified.manifest.packageVersion,
            manifestDigest: verified.manifest.manifestDigest
        )
    }
}

/// Non-shipping Chapter 01 review packages use the existing immutable
/// generation, activation and rollback machinery with the strict V2 decoder.
public struct ImmersiveContentPackageV2ActivationVerifier: PackageActivationVerifying {
    public init() {}

    public func verifyPackage(
        at packageRoot: URL,
        expectedPackage: ContentPackageSpec,
        trustedPublicKeys: [String: Data],
        supportedSchema: SchemaVersion,
        runtimeVersion: SchemaVersion
    ) throws -> VerifiedActivationReceipt {
        let verified = try ContentPackageVerifier.verifyImmersiveV2Package(
            at: packageRoot,
            expectedPackage: expectedPackage,
            trustedPublicKeys: trustedPublicKeys,
            supportedSchema: supportedSchema,
            runtimeVersion: runtimeVersion
        )
        return VerifiedActivationReceipt(
            packageID: verified.manifest.packageID,
            packageVersion: verified.manifest.packageVersion,
            manifestDigest: verified.manifest.manifestDigest
        )
    }
}

public struct ActivatedPackage: Equatable, Sendable {
    public let generation: InstalledPackageGeneration
    public let packageURL: URL

    public init(generation: InstalledPackageGeneration, packageURL: URL) {
        self.generation = generation
        self.packageURL = packageURL
    }
}

public enum ExactPackageRollbackResult: Equatable, Sendable {
    case rolledBack(ActivatedPackage)
    case staleAuthority
}

public enum PackageDeactivationResult: Equatable, Sendable {
    case deactivated(InstalledPackageGeneration)
    case staleAuthority
}

/// Actor-resolved storage locations for bootstrap verification. Generation
/// metadata remains visible when a referenced directory is missing, while no
/// caller has to derive or trust a filesystem path from index data.
public struct RetainedPackageLocations: Equatable, Sendable {
    public let activeGeneration: InstalledPackageGeneration?
    public let activePackage: ActivatedPackage?
    public let previousGeneration: InstalledPackageGeneration?
    public let previousPackage: ActivatedPackage?

    public init(
        activeGeneration: InstalledPackageGeneration?,
        activePackage: ActivatedPackage?,
        previousGeneration: InstalledPackageGeneration?,
        previousPackage: ActivatedPackage?
    ) {
        self.activeGeneration = activeGeneration
        self.activePackage = activePackage
        self.previousGeneration = previousGeneration
        self.previousPackage = previousPackage
    }
}

/// One validated durable index snapshot and every storage location resolved
/// from that same actor-isolated snapshot. Bootstrap can therefore reject
/// unknown package IDs and make one recovery decision without cross-call
/// authority races.
public struct RetainedPackageAuthority: Equatable, Sendable {
    public let index: InstalledPackageIndex
    public let locationsByPackage: [PackageID: RetainedPackageLocations]

    public init(
        index: InstalledPackageIndex,
        locationsByPackage: [PackageID: RetainedPackageLocations]
    ) {
        self.index = index
        self.locationsByPackage = locationsByPackage
    }
}

public enum PackageActivationError: Error, Equatable, Sendable {
    case stagingDirectoryOutsideManagedRoot
    case stagingDirectoryMissing
    case stagingDirectoryIsSymbolicLink
    case verificationIdentityMismatch
    case sameVersionManifestMismatch(PackageID, SchemaVersion)
    case packageVersionRegression(
        packageID: PackageID,
        active: SchemaVersion,
        candidate: SchemaVersion
    )
    case unsafeGenerationIdentifier
    case generationDirectoryOutsideManagedRoot(String)
    case generationDirectoryIsSymbolicLink(String)
    case noActiveGeneration(String)
    case noRollbackGeneration(String)
    case essentialPackageMutationForbidden(PackageID)
}

/// Serialises verification and activation. Package generations are immutable;
/// the two-slot index is the sole atomic pointer to the currently active bytes.
/// A process death before the index write leaves only an ignored orphan, while
/// a process death after it leaves a complete verified generation active.
public actor PackageActivator {
    private static let managedGenerationPrefix = "managed-"

    public nonisolated let rootURL: URL
    public nonisolated let stagingRootURL: URL
    public nonisolated let generationsRootURL: URL

    private let verifier: any PackageActivationVerifying
    private let indexStore: InstalledPackageIndexStore
    private let generationID: @Sendable () -> String

    public init(
        rootURL: URL,
        verifier: any PackageActivationVerifying = ContentPackageActivationVerifier(),
        generationID: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        }
    ) throws {
        self.rootURL = rootURL.standardizedFileURL
        stagingRootURL = self.rootURL.appending(path: "staging", directoryHint: .isDirectory)
        generationsRootURL = self.rootURL.appending(path: "generations", directoryHint: .isDirectory)
        self.verifier = verifier
        self.generationID = generationID
        indexStore = try InstalledPackageIndexStore(
            directoryURL: self.rootURL.appending(path: "index", directoryHint: .isDirectory)
        )
        try FileManager.default.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: generationsRootURL, withIntermediateDirectories: true)
        try? Self.reconcileStorage(
            indexStore: indexStore,
            stagingRootURL: stagingRootURL,
            generationsRootURL: generationsRootURL
        )
    }

    public func makeStagingDirectory() throws -> URL {
        let url = stagingRootURL.appending(
            path: "incoming-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    public func activate(
        stagedPackageURL: URL,
        expectedPackage: ContentPackageSpec,
        trustedPublicKeys: [String: Data],
        supportedSchema: SchemaVersion,
        runtimeVersion: SchemaVersion
    ) throws -> ActivatedPackage {
        let safeStagingURL = try requireManagedStagingDirectory(stagedPackageURL)
        // Resolve the durable authority before moving verified staging bytes.
        // A future index schema must remain byte-for-byte untouched and must
        // not create a final-directory orphan under an older app.
        var index = try indexStore.load()
        let receipt = try verifier.verifyPackage(
            at: safeStagingURL,
            expectedPackage: expectedPackage,
            trustedPublicKeys: trustedPublicKeys,
            supportedSchema: supportedSchema,
            runtimeVersion: runtimeVersion
        )
        guard receipt.packageID == expectedPackage.id,
              receipt.packageVersion == expectedPackage.version else {
            throw PackageActivationError.verificationIdentityMismatch
        }
        let retained = index.retainedGenerations(for: receipt.packageID)
        if retained.contains(where: {
            $0.packageVersion == receipt.packageVersion
                && $0.manifestDigest != receipt.manifestDigest
        }) {
            throw PackageActivationError.sameVersionManifestMismatch(
                receipt.packageID,
                receipt.packageVersion
            )
        }
        if let highestRetainedVersion = retained.map(\.packageVersion).max(),
           highestRetainedVersion > receipt.packageVersion {
            throw PackageActivationError.packageVersionRegression(
                packageID: receipt.packageID,
                active: highestRetainedVersion,
                candidate: receipt.packageVersion
            )
        }

        let opaqueID = generationID()
        guard Self.isStableComponent(opaqueID) else {
            throw PackageActivationError.unsafeGenerationIdentifier
        }
        let directoryName = "\(Self.managedGenerationPrefix)\(receipt.packageID.rawValue)-\(opaqueID)"
        let finalURL = generationsRootURL.appending(path: directoryName, directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: safeStagingURL, to: finalURL)

        let generation = InstalledPackageGeneration(
            generationID: directoryName,
            packageID: receipt.packageID,
            packageVersion: receipt.packageVersion,
            manifestDigest: receipt.manifestDigest,
            relativePath: "generations/\(directoryName)",
            activationSequence: index.nextActivationSequence
        )
        let removedGenerations = try index.recordActivation(generation)

        // This first save is the activation commit. Every operation after it
        // is recoverable maintenance and cannot turn this activation into a
        // reported failure.
        try indexStore.save(index)
        let activated = ActivatedPackage(generation: generation, packageURL: finalURL)
        do {
            try indexStore.mirrorCommittedState(index)
            try Self.removePrunedGenerations(
                removedGenerations,
                protectedGenerationIDs: Set(index.generations.map(\.generationID)),
                generationsRootURL: generationsRootURL
            )
            try Self.reconcileStorage(
                indexStore: indexStore,
                stagingRootURL: stagingRootURL,
                generationsRootURL: generationsRootURL
            )
        } catch {
            // A later cold start or explicit reconciliation can finish this.
        }
        return activated
    }

    public func activePackage(for packageID: PackageID) throws -> ActivatedPackage? {
        let index = try indexStore.load()
        guard let generation = index.activeGeneration(for: packageID) else { return nil }
        return try resolve(generation)
    }

    public func installedIndex() throws -> InstalledPackageIndex {
        let index = try indexStore.load()
        for generationID in index.activeGenerationByPackage.values {
            guard let generation = index.generations.first(where: {
                $0.generationID == generationID
            }) else {
                throw InstalledPackageIndexError.activeGenerationMissing(generationID)
            }
            _ = try resolve(generation)
        }
        return index
    }

    /// Returns only actor-resolved direct-child locations. A missing directory
    /// is represented by a nil package while its generation metadata remains
    /// available for fail-closed bootstrap decisions.
    public func retainedPackageLocations(
        for packageID: PackageID
    ) throws -> RetainedPackageLocations {
        let index = try indexStore.load()
        return try retainedPackageLocations(for: packageID, in: index)
    }

    /// Returns the validated durable index and all active/rollback locations
    /// derived from precisely that snapshot. Missing referenced directories
    /// remain nil; unsafe paths or symbolic links fail closed.
    public func retainedPackageAuthority() throws -> RetainedPackageAuthority {
        let index = try indexStore.load()
        var locationsByPackage: [PackageID: RetainedPackageLocations] = [:]
        for packageID in index.activeGenerationByPackage.keys.sorted() {
            locationsByPackage[packageID] = try retainedPackageLocations(
                for: packageID,
                in: index
            )
        }
        return RetainedPackageAuthority(
            index: index,
            locationsByPackage: locationsByPackage
        )
    }

    private func retainedPackageLocations(
        for packageID: PackageID,
        in index: InstalledPackageIndex
    ) throws -> RetainedPackageLocations {
        guard let active = index.activeGeneration(for: packageID) else {
            return RetainedPackageLocations(
                activeGeneration: nil,
                activePackage: nil,
                previousGeneration: nil,
                previousPackage: nil
            )
        }
        let previous = Self.previousGeneration(in: index, active: active)
        let activePackage = try resolveIfPresent(active)
        let previousPackage: ActivatedPackage?
        if let previous {
            previousPackage = try resolveIfPresent(previous)
        } else {
            previousPackage = nil
        }
        return RetainedPackageLocations(
            activeGeneration: active,
            activePackage: activePackage,
            previousGeneration: previous,
            previousPackage: previousPackage
        )
    }

    /// Legacy test seam. Shipping recovery must use the exact compare-and-swap
    /// overload below so a verified predecessor cannot mutate a newer active
    /// generation.
    func rollback(packageID: PackageID) throws -> ActivatedPackage {
        var index = try indexStore.load()
        guard let active = index.activeGeneration(for: packageID) else {
            throw PackageActivationError.noActiveGeneration(packageID.rawValue)
        }
        guard let previous = Self.previousGeneration(in: index, active: active) else {
            throw PackageActivationError.noRollbackGeneration(packageID.rawValue)
        }
        let resolvedPrevious = try resolve(previous)
        try index.activateRetainedGeneration(previous.generationID, packageID: packageID)
        try indexStore.save(index)
        do {
            try indexStore.mirrorCommittedState(index)
            try Self.reconcileStorage(
                indexStore: indexStore,
                stagingRootURL: stagingRootURL,
                generationsRootURL: generationsRootURL
            )
        } catch {
            // The committed rollback remains authoritative in the newest slot.
        }
        return resolvedPrevious
    }

    /// Commits a rollback only while both retained pointers still match the
    /// authority which was fully byte-verified by the caller. A concurrent
    /// activation or an index swap therefore turns the request into a no-op.
    /// No generation bytes are removed by this recovery operation.
    public func rollback(
        packageID: PackageID,
        expectedActiveGeneration: InstalledPackageGeneration,
        expectedPreviousGeneration: InstalledPackageGeneration
    ) throws -> ExactPackageRollbackResult {
        guard packageID != LaunchContent.essentialPackageID else {
            throw PackageActivationError.essentialPackageMutationForbidden(packageID)
        }
        var index = try indexStore.load()
        guard expectedActiveGeneration.packageID == packageID,
              expectedPreviousGeneration.packageID == packageID,
              index.activeGeneration(for: packageID) == expectedActiveGeneration,
              Self.previousGeneration(
                  in: index,
                  active: expectedActiveGeneration
              ) == expectedPreviousGeneration else {
            return .staleAuthority
        }

        let resolvedPrevious = try resolve(expectedPreviousGeneration)
        try index.activateRetainedGeneration(
            expectedPreviousGeneration.generationID,
            packageID: packageID
        )
        try indexStore.save(index)
        // The first save is the atomic recovery commit. Mirroring is
        // recoverable maintenance and deliberately performs no reconciliation
        // or deletion while failed bytes are quarantined for diagnosis.
        try? indexStore.mirrorCommittedState(index)
        return .rolledBack(resolvedPrevious)
    }

    /// Atomically removes the active pointer only when it still names the
    /// exact failed paid generation. Both generation metadata and bytes remain
    /// retained; a cold launch sees no active package and cannot re-admit it.
    public func deactivate(
        packageID: PackageID,
        expectedActiveGeneration: InstalledPackageGeneration
    ) throws -> PackageDeactivationResult {
        guard packageID != LaunchContent.essentialPackageID else {
            throw PackageActivationError.essentialPackageMutationForbidden(packageID)
        }
        var index = try indexStore.load()
        guard expectedActiveGeneration.packageID == packageID,
              index.activeGeneration(for: packageID) == expectedActiveGeneration,
              let deactivated = try index.deactivateActiveGeneration(
                  packageID: packageID,
                  expectedGenerationID: expectedActiveGeneration.generationID
              ) else {
            return .staleAuthority
        }

        try indexStore.save(index)
        try? indexStore.mirrorCommittedState(index)
        return .deactivated(deactivated)
    }

    /// Removes only storage that can be proven unreferenced by two agreeing,
    /// current-schema index slots. An unreadable, future or divergent slot
    /// turns reconciliation into a no-op.
    public func reconcileStorage() throws {
        try Self.reconcileStorage(
            indexStore: indexStore,
            stagingRootURL: stagingRootURL,
            generationsRootURL: generationsRootURL
        )
    }

    private func resolve(_ generation: InstalledPackageGeneration) throws -> ActivatedPackage {
        guard let resolved = try resolveIfPresent(generation) else {
            throw InstalledPackageIndexError.missingActiveDirectory(generation.generationID)
        }
        return resolved
    }

    private func resolveIfPresent(
        _ generation: InstalledPackageGeneration
    ) throws -> ActivatedPackage? {
        guard generation.relativePath == "generations/\(generation.generationID)" else {
            throw PackageActivationError.generationDirectoryOutsideManagedRoot(
                generation.generationID
            )
        }
        guard try Self.isUnlinkedDirectory(generationsRootURL) else {
            throw PackageActivationError.generationDirectoryIsSymbolicLink(
                generation.generationID
            )
        }
        let url = generationsRootURL.appending(
            path: generation.generationID,
            directoryHint: .isDirectory
        ).standardizedFileURL
        guard url.deletingLastPathComponent().path == generationsRootURL.standardizedFileURL.path else {
            throw PackageActivationError.generationDirectoryOutsideManagedRoot(
                generation.generationID
            )
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
                throw PackageActivationError.generationDirectoryIsSymbolicLink(
                    generation.generationID
                )
            }
            return nil
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw PackageActivationError.generationDirectoryIsSymbolicLink(
                generation.generationID
            )
        }
        // A regular file at the indexed directory path is damaged/missing
        // package storage, not a safe location to expose. The retained
        // authority keeps its metadata and rollback candidate available; the
        // strict `resolve` view still converts this nil into
        // `missingActiveDirectory`.
        guard values.isDirectory == true else { return nil }
        return ActivatedPackage(generation: generation, packageURL: url)
    }

    private func requireManagedStagingDirectory(_ candidate: URL) throws -> URL {
        let standardized = candidate.standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let root = stagingRootURL.resolvingSymlinksInPath().standardizedFileURL
        guard standardized.path == resolved.path else {
            throw PackageActivationError.stagingDirectoryIsSymbolicLink
        }
        guard resolved.path.hasPrefix(root.path + "/") else {
            throw PackageActivationError.stagingDirectoryOutsideManagedRoot
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw PackageActivationError.stagingDirectoryMissing
        }
        return resolved
    }

    private static func reconcileStorage(
        indexStore: InstalledPackageIndexStore,
        stagingRootURL: URL,
        generationsRootURL: URL
    ) throws {
        guard let index = indexStore.agreedCurrentIndex(),
              try isUnlinkedDirectory(stagingRootURL),
              try isUnlinkedDirectory(generationsRootURL) else {
            return
        }

        let stagingChildren = try FileManager.default.contentsOfDirectory(
            at: stagingRootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        for child in stagingChildren where child.lastPathComponent.hasPrefix("incoming-") {
            guard try isDirectUnlinkedDirectory(child, within: stagingRootURL) else { continue }
            try FileManager.default.removeItem(at: child)
        }

        let protectedGenerationIDs = Set(index.generations.map(\.generationID))
        let generationChildren = try FileManager.default.contentsOfDirectory(
            at: generationsRootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        for child in generationChildren {
            let name = child.lastPathComponent
            guard name.hasPrefix(managedGenerationPrefix),
                  !protectedGenerationIDs.contains(name),
                  try isDirectUnlinkedDirectory(child, within: generationsRootURL) else {
                continue
            }
            try FileManager.default.removeItem(at: child)
        }
    }

    private static func removePrunedGenerations(
        _ generations: [InstalledPackageGeneration],
        protectedGenerationIDs: Set<String>,
        generationsRootURL: URL
    ) throws {
        guard try isUnlinkedDirectory(generationsRootURL) else { return }
        for generation in generations {
            guard !protectedGenerationIDs.contains(generation.generationID),
                  generation.relativePath == "generations/\(generation.generationID)" else {
                continue
            }
            let candidate = generationsRootURL.appending(
                path: generation.generationID,
                directoryHint: .isDirectory
            )
            guard try isDirectUnlinkedDirectory(candidate, within: generationsRootURL) else {
                continue
            }
            try FileManager.default.removeItem(at: candidate)
        }
    }

    private static func isUnlinkedDirectory(_ url: URL) throws -> Bool {
        let standardized = url.standardizedFileURL
        guard standardized.path == url.resolvingSymlinksInPath().standardizedFileURL.path else {
            return false
        }
        let values = try standardized.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static func isDirectUnlinkedDirectory(
        _ candidate: URL,
        within root: URL
    ) throws -> Bool {
        let standardizedRoot = root.standardizedFileURL
        let standardized = candidate.standardizedFileURL
        guard standardized.deletingLastPathComponent().path == standardizedRoot.path else {
            return false
        }
        let values = try standardized.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static func isStableComponent(_ value: String) -> Bool {
        !value.isEmpty && !value.hasPrefix("-") && !value.hasSuffix("-")
            && value.utf8.allSatisfy {
                ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45
            }
    }

    private static func previousGeneration(
        in index: InstalledPackageIndex,
        active: InstalledPackageGeneration
    ) -> InstalledPackageGeneration? {
        index.retainedGenerations(for: active.packageID).first {
            $0.generationID != active.generationID
                && $0.activationSequence < active.activationSequence
        }
    }
}
