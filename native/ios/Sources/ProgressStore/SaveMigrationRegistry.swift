import ContentKit
import CryptoKit
import Foundation
import JourneyDomain

/// Exact durable package-generation identity which was active when the
/// repository exposed a verified package for save migration. A verified
/// staging or retained package is not sufficient authority.
public struct ActiveSaveMigrationPackageGeneration: Codable, Equatable, Sendable {
    public let generationID: String
    public let packageID: PackageID
    public let packageVersion: SchemaVersion
    public let manifestDigest: String
    public let activationSequence: UInt64

    public init(
        generationID: String,
        packageID: PackageID,
        packageVersion: SchemaVersion,
        manifestDigest: String,
        activationSequence: UInt64
    ) {
        self.generationID = generationID
        self.packageID = packageID
        self.packageVersion = packageVersion
        self.manifestDigest = manifestDigest
        self.activationSequence = activationSequence
    }
}

public enum VerifiedPackageSaveMigrationAuthorityError: Error, Equatable, Sendable {
    case activeGenerationMismatch(PackageID)
}

/// Migration authority derived only from a package which has already crossed
/// `ContentPackageVerifier` and the exact durable generation which is active
/// in the same repository snapshot. Raw downloaded, staging or retained
/// packages cannot construct this value on their own.
public struct VerifiedPackageSaveMigrationAuthority: Sendable {
    public let packageID: PackageID
    public let targetContentVersion: SchemaVersion
    public let manifestDigest: String
    public let activeGeneration: ActiveSaveMigrationPackageGeneration
    public let declarations: [PackageSaveMigrationDeclaration]

    public init(
        verifiedPackage: VerifiedContentPackage,
        activeGeneration: ActiveSaveMigrationPackageGeneration
    ) throws {
        guard !activeGeneration.generationID.isEmpty,
              activeGeneration.packageID == verifiedPackage.manifest.packageID,
              activeGeneration.packageVersion == verifiedPackage.manifest.packageVersion,
              activeGeneration.manifestDigest == verifiedPackage.manifest.manifestDigest else {
            throw VerifiedPackageSaveMigrationAuthorityError.activeGenerationMismatch(
                verifiedPackage.manifest.packageID
            )
        }
        packageID = verifiedPackage.manifest.packageID
        targetContentVersion = verifiedPackage.manifest.packageVersion
        manifestDigest = verifiedPackage.manifest.manifestDigest
        self.activeGeneration = activeGeneration
        declarations = verifiedPackage.manifest.saveMigrations ?? []
    }

    /// Internal test seam. Shipping code can obtain authority only through the
    /// public verified-package initializer above.
    init(
        packageID: PackageID,
        targetContentVersion: SchemaVersion,
        manifestDigest: String,
        activeGeneration: ActiveSaveMigrationPackageGeneration,
        declarations: [PackageSaveMigrationDeclaration]
    ) {
        self.packageID = packageID
        self.targetContentVersion = targetContentVersion
        self.manifestDigest = manifestDigest
        self.activeGeneration = activeGeneration
        self.declarations = declarations
    }
}

/// One compiled transform matched to a signed package declaration.
///
/// The descriptor is canonical source data such as a sorted JSON migration
/// plan. Its digest is reproducible and reviewable; no unverifiable executable
/// byte hash is claimed.
public struct PackageSaveMigrationStep: Sendable {
    public typealias Transform = @Sendable (JourneyState, PackageID) throws -> JourneyState

    public let packageID: PackageID
    public let declarationID: String
    public let fromContentVersion: SchemaVersion
    public let toContentVersion: SchemaVersion
    public let implementationSHA256: String
    fileprivate let transform: Transform

    public init(
        packageID: PackageID,
        declarationID: String,
        fromContentVersion: SchemaVersion,
        toContentVersion: SchemaVersion,
        canonicalTransformDescriptor: Data,
        transform: @escaping Transform
    ) {
        self.packageID = packageID
        self.declarationID = declarationID
        self.fromContentVersion = fromContentVersion
        self.toContentVersion = toContentVersion
        implementationSHA256 = Self.sha256(canonicalTransformDescriptor)
        self.transform = transform
    }

    public static func descriptorSHA256(_ descriptor: Data) -> String {
        sha256(descriptor)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public enum SaveMigrationRegistryError: Error, Equatable, Sendable {
    case duplicateAuthority(PackageID)
    case duplicateImplementation(packageID: PackageID, declarationID: String)
    case activeGenerationMismatch(PackageID)
    case incompatibleSaveFormat(required: Int, actual: Int)
    case incompatibleStateSchema(required: Int, actual: Int)
    case mixedSavedContentVersions(PackageID)
    case unknownPath(packageID: PackageID, from: SchemaVersion, to: SchemaVersion)
    case ambiguousPath(packageID: PackageID, from: SchemaVersion, to: SchemaVersion)
    case missingImplementation(packageID: PackageID, declarationID: String)
    case implementationDescriptorMismatch(packageID: PackageID, declarationID: String)
    case transformFailed(packageID: PackageID, declarationID: String)
    case nondeterministicTransform(packageID: PackageID, declarationID: String)
    case identityOrAuthorityMutation(packageID: PackageID, declarationID: String)
    case undeclaredFieldMutation(
        packageID: PackageID,
        declarationID: String,
        field: PackageSaveMigrationField
    )
    case worldOwnershipViolation(
        packageID: PackageID,
        declarationID: String,
        recordType: String,
        recordID: String
    )
    case targetVersionMismatch(packageID: PackageID, declarationID: String)
}

public struct SaveMigrationResult: Equatable, Sendable {
    public let snapshot: SaveSnapshot
    public let appliedMigrationIDs: [String]

    public var didMigrate: Bool { !appliedMigrationIDs.isEmpty }

    public init(snapshot: SaveSnapshot, appliedMigrationIDs: [String]) {
        self.snapshot = snapshot
        self.appliedMigrationIDs = appliedMigrationIDs
    }
}

/// Fail-closed graph resolver and exact-state transform gate.
public struct SaveMigrationRegistry: Sendable {
    public static let empty = try! SaveMigrationRegistry(steps: [])

    private let stepsByKey: [ImplementationKey: PackageSaveMigrationStep]

    public init(steps: [PackageSaveMigrationStep]) throws {
        var indexed: [ImplementationKey: PackageSaveMigrationStep] = [:]
        for step in steps {
            let key = ImplementationKey(
                packageID: step.packageID,
                declarationID: step.declarationID
            )
            guard indexed.updateValue(step, forKey: key) == nil else {
                throw SaveMigrationRegistryError.duplicateImplementation(
                    packageID: step.packageID,
                    declarationID: step.declarationID
                )
            }
        }
        stepsByKey = indexed
    }

    public func migrate(
        _ snapshot: SaveSnapshot,
        authorities: [VerifiedPackageSaveMigrationAuthority]
    ) throws -> SaveMigrationResult {
        var authoritiesByPackage: [PackageID: VerifiedPackageSaveMigrationAuthority] = [:]
        for authority in authorities {
            guard !authority.activeGeneration.generationID.isEmpty,
                  authority.activeGeneration.packageID == authority.packageID,
                  authority.activeGeneration.packageVersion
                    == authority.targetContentVersion,
                  authority.activeGeneration.manifestDigest
                    == authority.manifestDigest else {
                throw SaveMigrationRegistryError.activeGenerationMismatch(
                    authority.packageID
                )
            }
            guard authoritiesByPackage.updateValue(authority, forKey: authority.packageID) == nil else {
                throw SaveMigrationRegistryError.duplicateAuthority(authority.packageID)
            }
        }

        var state = snapshot.state
        var appliedIDs: [String] = []
        for authority in authorities.sorted(by: { $0.packageID < $1.packageID }) {
            let versions = savedVersions(for: authority.packageID, state: state)
            guard versions.count <= 1 else {
                throw SaveMigrationRegistryError.mixedSavedContentVersions(authority.packageID)
            }
            guard let source = versions.first,
                  source != authority.targetContentVersion else {
                continue
            }

            let path = try uniquePath(
                declarations: authority.declarations,
                packageID: authority.packageID,
                from: source,
                to: authority.targetContentVersion
            )
            for declaration in path {
                guard declaration.requiredSaveFormatVersion == snapshot.formatVersion else {
                    throw SaveMigrationRegistryError.incompatibleSaveFormat(
                        required: declaration.requiredSaveFormatVersion,
                        actual: snapshot.formatVersion
                    )
                }
                guard declaration.requiredStateSchemaVersion == state.stateSchemaVersion else {
                    throw SaveMigrationRegistryError.incompatibleStateSchema(
                        required: declaration.requiredStateSchemaVersion,
                        actual: state.stateSchemaVersion
                    )
                }
                let key = ImplementationKey(
                    packageID: authority.packageID,
                    declarationID: declaration.id
                )
                guard let implementation = stepsByKey[key],
                      implementation.fromContentVersion == declaration.fromContentVersion,
                      implementation.toContentVersion == declaration.toContentVersion else {
                    throw SaveMigrationRegistryError.missingImplementation(
                        packageID: authority.packageID,
                        declarationID: declaration.id
                    )
                }
                guard implementation.implementationSHA256 == declaration.implementationSHA256 else {
                    throw SaveMigrationRegistryError.implementationDescriptorMismatch(
                        packageID: authority.packageID,
                        declarationID: declaration.id
                    )
                }

                let before = state
                let first: JourneyState
                let repeated: JourneyState
                do {
                    first = try implementation.transform(before, authority.packageID)
                    repeated = try implementation.transform(before, authority.packageID)
                } catch {
                    throw SaveMigrationRegistryError.transformFailed(
                        packageID: authority.packageID,
                        declarationID: declaration.id
                    )
                }
                guard first == repeated else {
                    throw SaveMigrationRegistryError.nondeterministicTransform(
                        packageID: authority.packageID,
                        declarationID: declaration.id
                    )
                }
                state = first
                try validateMutation(
                    before: before,
                    after: state,
                    declaration: declaration,
                    packageID: authority.packageID
                )
                appliedIDs.append(declaration.id)
            }
        }
        return SaveMigrationResult(
            snapshot: SaveSnapshot(formatVersion: snapshot.formatVersion, state: state),
            appliedMigrationIDs: appliedIDs
        )
    }

    private func savedVersions(
        for packageID: PackageID,
        state: JourneyState
    ) -> Set<SchemaVersion> {
        let sessionVersions = state.chapterSessions
            .filter { $0.packageID == packageID }
            .map(\.contentVersion)
        let installedVersions = state.installedContent
            .filter { $0.packageID == packageID }
            .map(\.version)
        return Set(sessionVersions + installedVersions)
    }

    private func uniquePath(
        declarations: [PackageSaveMigrationDeclaration],
        packageID: PackageID,
        from source: SchemaVersion,
        to target: SchemaVersion
    ) throws -> [PackageSaveMigrationDeclaration] {
        var paths: [[PackageSaveMigrationDeclaration]] = []
        func walk(
            _ version: SchemaVersion,
            visited: Set<SchemaVersion>,
            path: [PackageSaveMigrationDeclaration]
        ) {
            guard paths.count < 2 else { return }
            if version == target {
                paths.append(path)
                return
            }
            let outgoing = declarations
                .filter { $0.fromContentVersion == version }
                .sorted { $0.id.utf8.lexicographicallyPrecedes($1.id.utf8) }
            for edge in outgoing where !visited.contains(edge.toContentVersion) {
                walk(
                    edge.toContentVersion,
                    visited: visited.union([edge.toContentVersion]),
                    path: path + [edge]
                )
            }
        }
        walk(source, visited: [source], path: [])
        guard !paths.isEmpty else {
            throw SaveMigrationRegistryError.unknownPath(
                packageID: packageID,
                from: source,
                to: target
            )
        }
        guard paths.count == 1 else {
            throw SaveMigrationRegistryError.ambiguousPath(
                packageID: packageID,
                from: source,
                to: target
            )
        }
        return paths[0]
    }

    private func validateMutation(
        before: JourneyState,
        after: JourneyState,
        declaration: PackageSaveMigrationDeclaration,
        packageID: PackageID
    ) throws {
        let failure = SaveMigrationRegistryError.identityOrAuthorityMutation(
            packageID: packageID,
            declarationID: declaration.id
        )
        guard before.stateSchemaVersion == after.stateSchemaVersion,
              before.route == after.route,
              before.prologue == after.prologue,
              before.completedChapterIDs == after.completedChapterIDs,
              before.lastLogicalTimeMillis == after.lastLogicalTimeMillis,
              before.appliedEventCount == after.appliedEventCount,
              before.chapterSessions.map(\.chapterID) == after.chapterSessions.map(\.chapterID),
              before.chapterSessions.map(\.packageID) == after.chapterSessions.map(\.packageID),
              before.installedContent.map(\.packageID) == after.installedContent.map(\.packageID) else {
            throw failure
        }

        let declared = Set(declaration.fields)
        try validateReviewMutation(
            before: before.chapterReview,
            after: after.chapterReview,
            declaration: declaration,
            packageID: packageID,
            declared: declared
        )
        if before.world != after.world,
           !declared.contains(.cumulativeWorldState) {
            throw SaveMigrationRegistryError.undeclaredFieldMutation(
                packageID: packageID,
                declarationID: declaration.id,
                field: .cumulativeWorldState
            )
        }
        if before.world != after.world {
            try validateWorldOwnership(
                before: before.world,
                after: after.world,
                declaration: declaration,
                packageID: packageID
            )
        }

        for index in before.chapterSessions.indices {
            let old = before.chapterSessions[index]
            let new = after.chapterSessions[index]
            guard old.chapterID == new.chapterID,
                  old.packageID == new.packageID,
                  old.lastVisitedAtEpochMillis == new.lastVisitedAtEpochMillis,
                  old.completedBeatReviewRecords.count
                    == new.completedBeatReviewRecords.count,
                  old.completedBeatReviewRecords.map(\.formatVersion)
                    == new.completedBeatReviewRecords.map(\.formatVersion) else {
                throw failure
            }
            if old.packageID != packageID {
                guard old == new else { throw failure }
                continue
            }
            guard old.contentVersion == declaration.fromContentVersion,
                  new.contentVersion == declaration.toContentVersion else {
                throw SaveMigrationRegistryError.targetVersionMismatch(
                    packageID: packageID,
                    declarationID: declaration.id
                )
            }
            let beatChanged = old.arcID != new.arcID
                || old.beatID != new.beatID
                || old.beatCompletionContract != new.beatCompletionContract
                || old.completedBeatIDs != new.completedBeatIDs
                || old.completedArcIDs != new.completedArcIDs
                || !reviewRecordIdentitiesMatch(
                    old.completedBeatReviewRecords,
                    new.completedBeatReviewRecords
                )
            try requireDeclared(
                beatChanged,
                field: .beatIdentity,
                declared: declared,
                packageID: packageID,
                declarationID: declaration.id
            )
            try requireDeclared(
                old.interaction != new.interaction
                    || old.completedBeatReviewRecords.map(\.interaction)
                        != new.completedBeatReviewRecords.map(\.interaction),
                field: .interactionState,
                declared: declared,
                packageID: packageID,
                declarationID: declaration.id
            )
            let anchorsChanged = old.sceneVisualSnapshot != new.sceneVisualSnapshot
                || old.cameraAnchor != new.cameraAnchor
                || old.readingAnchor != new.readingAnchor
                || !reviewRecordAnchorsMatch(
                    old.completedBeatReviewRecords,
                    new.completedBeatReviewRecords
                )
            try requireDeclared(
                anchorsChanged,
                field: .cameraAndTextAnchors,
                declared: declared,
                packageID: packageID,
                declarationID: declaration.id
            )
            let audioChanged = old.narration != new.narration
                || old.responsiveAudioSnapshot != new.responsiveAudioSnapshot
            try requireDeclared(
                audioChanged,
                field: .narrationAndAudioPosition,
                declared: declared,
                packageID: packageID,
                declarationID: declaration.id
            )
        }

        for index in before.installedContent.indices {
            let old = before.installedContent[index]
            let new = after.installedContent[index]
            if old.packageID == packageID {
                guard old.version == declaration.fromContentVersion,
                      new.version == declaration.toContentVersion else {
                    throw SaveMigrationRegistryError.targetVersionMismatch(
                        packageID: packageID,
                        declarationID: declaration.id
                    )
                }
            } else {
                guard old == new else { throw failure }
            }
        }
    }

    private func validateReviewMutation(
        before: ChapterReviewState?,
        after: ChapterReviewState?,
        declaration: PackageSaveMigrationDeclaration,
        packageID: PackageID,
        declared: Set<PackageSaveMigrationField>
    ) throws {
        let failure = SaveMigrationRegistryError.identityOrAuthorityMutation(
            packageID: packageID,
            declarationID: declaration.id
        )
        switch (before, after) {
        case (nil, nil):
            return
        case (nil, .some), (.some, nil):
            throw failure
        case let (old?, new?):
            guard old.chapterID == new.chapterID,
                  old.packageID == new.packageID else {
                throw failure
            }
            guard old.packageID == packageID else {
                guard old == new else { throw failure }
                return
            }
            guard old.contentVersion == declaration.fromContentVersion,
                  new.contentVersion == declaration.toContentVersion else {
                throw SaveMigrationRegistryError.targetVersionMismatch(
                    packageID: packageID,
                    declarationID: declaration.id
                )
            }
            try requireDeclared(
                old.beatID != new.beatID,
                field: .beatIdentity,
                declared: declared,
                packageID: packageID,
                declarationID: declaration.id
            )
            try requireDeclared(
                old.readingAnchor != new.readingAnchor,
                field: .cameraAndTextAnchors,
                declared: declared,
                packageID: packageID,
                declarationID: declaration.id
            )
        }
    }

    private func reviewRecordIdentitiesMatch(
        _ old: [CompletedBeatReviewRecord],
        _ new: [CompletedBeatReviewRecord]
    ) -> Bool {
        guard old.count == new.count else { return false }
        return zip(old, new).allSatisfy { lhs, rhs in
            lhs.formatVersion == rhs.formatVersion
                && lhs.completionContract == rhs.completionContract
        }
    }

    private func reviewRecordAnchorsMatch(
        _ old: [CompletedBeatReviewRecord],
        _ new: [CompletedBeatReviewRecord]
    ) -> Bool {
        guard old.count == new.count else { return false }
        return zip(old, new).allSatisfy { lhs, rhs in
            lhs.sceneVisualSnapshot == rhs.sceneVisualSnapshot
                && lhs.cameraAnchor == rhs.cameraAnchor
                && lhs.readingAnchor == rhs.readingAnchor
        }
    }

    private func requireDeclared(
        _ changed: Bool,
        field: PackageSaveMigrationField,
        declared: Set<PackageSaveMigrationField>,
        packageID: PackageID,
        declarationID: String
    ) throws {
        guard !changed || declared.contains(field) else {
            throw SaveMigrationRegistryError.undeclaredFieldMutation(
                packageID: packageID,
                declarationID: declarationID,
                field: field
            )
        }
    }

    private func validateWorldOwnership(
        before: WorldGraph,
        after: WorldGraph,
        declaration: PackageSaveMigrationDeclaration,
        packageID: PackageID
    ) throws {
        let delta = declaration.worldOwnershipDelta
        try requireOwnedChanges(
            before: before.nodes.map { ($0.id.rawValue, $0) },
            after: after.nodes.map { ($0.id.rawValue, $0) },
            oldIDs: Set(delta.oldNodeIDs.map(\.rawValue)),
            newIDs: Set(delta.newNodeIDs.map(\.rawValue)),
            recordType: "node",
            packageID: packageID,
            declarationID: declaration.id
        )
        try requireOwnedChanges(
            before: before.traces.map { ($0.id.rawValue, $0) },
            after: after.traces.map { ($0.id.rawValue, $0) },
            oldIDs: Set(delta.oldTraceIDs.map(\.rawValue)),
            newIDs: Set(delta.newTraceIDs.map(\.rawValue)),
            recordType: "trace",
            packageID: packageID,
            declarationID: declaration.id
        )
        try requireOwnedChanges(
            before: before.appliedEffects.map { ($0.id.rawValue, $0) },
            after: after.appliedEffects.map { ($0.id.rawValue, $0) },
            oldIDs: Set(delta.oldEffectIDs.map(\.rawValue)),
            newIDs: Set(delta.newEffectIDs.map(\.rawValue)),
            recordType: "effect",
            packageID: packageID,
            declarationID: declaration.id
        )
    }

    private func requireOwnedChanges<Value: Equatable>(
        before: [(String, Value)],
        after: [(String, Value)],
        oldIDs: Set<String>,
        newIDs: Set<String>,
        recordType: String,
        packageID: PackageID,
        declarationID: String
    ) throws {
        let beforeByID = before.reduce(into: [String: Value]()) {
            $0[$1.0] = $1.1
        }
        let afterByID = after.reduce(into: [String: Value]()) {
            $0[$1.0] = $1.1
        }
        guard beforeByID.count == before.count,
              afterByID.count == after.count else {
            throw SaveMigrationRegistryError.worldOwnershipViolation(
                packageID: packageID,
                declarationID: declarationID,
                recordType: recordType,
                recordID: "duplicate-id"
            )
        }
        for id in Set(beforeByID.keys).union(afterByID.keys).sorted() {
            guard beforeByID[id] != afterByID[id] else { continue }
            if beforeByID[id] != nil, !oldIDs.contains(id) {
                throw SaveMigrationRegistryError.worldOwnershipViolation(
                    packageID: packageID,
                    declarationID: declarationID,
                    recordType: recordType,
                    recordID: id
                )
            }
            if afterByID[id] != nil, !newIDs.contains(id) {
                throw SaveMigrationRegistryError.worldOwnershipViolation(
                    packageID: packageID,
                    declarationID: declarationID,
                    recordType: recordType,
                    recordID: id
                )
            }
        }
    }

    private struct ImplementationKey: Hashable, Sendable {
        let packageID: PackageID
        let declarationID: String
    }
}
