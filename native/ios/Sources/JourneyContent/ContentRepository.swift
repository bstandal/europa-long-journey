import ContentKit
import Foundation

public enum ContentRepositoryError: Error, Equatable, Sendable, CustomStringConvertible {
    case launchManifestMismatch
    case invalidLaunchManifest(String)
    case invalidFutureRelease(String)
    case emptyPackageSet
    case missingEssentialPackage(PackageID)
    case bundledEssentialPackageMismatch(actual: PackageID)
    case downloadedEssentialPackageForbidden(PackageID)
    case unknownPackage(PackageID)
    case duplicatePackage(PackageID)
    case invalidPackage(packageID: PackageID, reason: String)
    case packageVersionMismatch(
        packageID: PackageID,
        expected: SchemaVersion,
        actual: SchemaVersion
    )
    case packageSchemaMismatch(
        packageID: PackageID,
        expected: SchemaVersion,
        actual: SchemaVersion
    )
    case packageRuntimeMismatch(
        packageID: PackageID,
        expected: SchemaVersion,
        actual: SchemaVersion
    )
    case chapterOwnershipMismatch(packageID: PackageID)
    case catalogChapterMismatch(chapterID: ChapterID)
    case worldSeedMismatch(packageID: PackageID)
    case futureReleaseLaunchCollision(namespace: String, identifier: String)
    case invalidCumulativeWorld(String)
    case duplicateIdentifier(
        namespace: String,
        identifier: String,
        firstPackage: PackageID,
        secondPackage: PackageID
    )

    public var description: String {
        switch self {
        case .launchManifestMismatch:
            "The repository requires the generated launch manifest"
        case let .invalidLaunchManifest(reason):
            "The generated launch manifest is invalid: \(reason)"
        case let .invalidFutureRelease(reason):
            "The future release contract is invalid: \(reason)"
        case .emptyPackageSet:
            "A content repository requires at least the essential package"
        case let .missingEssentialPackage(packageID):
            "The essential package is missing: \(packageID)"
        case let .bundledEssentialPackageMismatch(actual):
            "The code-signed bundle supplied \(actual) where the essential package was required"
        case let .downloadedEssentialPackageForbidden(packageID):
            "Downloaded package \(packageID) cannot replace the code-signed essential package"
        case let .unknownPackage(packageID):
            "The package is not declared in the launch manifest: \(packageID)"
        case let .duplicatePackage(packageID):
            "The package was supplied more than once: \(packageID)"
        case let .invalidPackage(packageID, reason):
            "Package \(packageID) failed canonical validation: \(reason)"
        case let .packageVersionMismatch(packageID, expected, actual):
            "Package \(packageID) has version \(actual); expected \(expected)"
        case let .packageSchemaMismatch(packageID, expected, actual):
            "Package \(packageID) has schema \(actual); expected \(expected)"
        case let .packageRuntimeMismatch(packageID, expected, actual):
            "Package \(packageID) requires runtime \(actual); expected \(expected)"
        case let .chapterOwnershipMismatch(packageID):
            "Package \(packageID) does not contain its exact declared chapter sequence"
        case let .catalogChapterMismatch(chapterID):
            "Chapter \(chapterID) does not match its launch-catalog title, period or package"
        case let .worldSeedMismatch(packageID):
            "Package \(packageID) does not carry the repository's exact world seed"
        case let .futureReleaseLaunchCollision(namespace, identifier):
            "Future release \(namespace) \(identifier) collides with locked launch content"
        case let .invalidCumulativeWorld(reason):
            "Available packages do not compose one deterministic world: \(reason)"
        case let .duplicateIdentifier(namespace, identifier, firstPackage, secondPackage):
            "Duplicate \(namespace) identifier \(identifier) in \(firstPackage) and \(secondPackage)"
        }
    }
}

public struct ArcContentLocation: Equatable, Sendable {
    public let chapterID: ChapterID
    public let arcIndex: Int

    public init(chapterID: ChapterID, arcIndex: Int) {
        self.chapterID = chapterID
        self.arcIndex = arcIndex
    }
}

public struct BeatContentLocation: Equatable, Sendable {
    public let chapterID: ChapterID
    public let arcID: ArcID
    public let arcIndex: Int
    public let beatIndex: Int

    public init(
        chapterID: ChapterID,
        arcID: ArcID,
        arcIndex: Int,
        beatIndex: Int
    ) {
        self.chapterID = chapterID
        self.arcID = arcID
        self.arcIndex = arcIndex
        self.beatIndex = beatIndex
    }
}

/// An immutable runtime view of content that has already crossed either the
/// signed-package verifier boundary or the code-signed bundled-payload boundary.
/// It revalidates every payload against the generated launch catalog before any
/// content object becomes addressable by the Journey.
public struct ContentRepository: Sendable {
    private enum ManifestBoundary {
        case launch
        case retainedLaunchContinuity
        case futureRelease(
            requiredPackageID: PackageID,
            requiredCollectionID: CollectionID,
            expectedWorldSeed: WorldSeedSpec
        )
#if DEBUG || NON_SHIPPING_LIVE_TEST
        case developmentVerticalSlice(requiredPackageID: PackageID)
#endif
    }

    public let manifest: CollectionManifest
    public let worldSeed: WorldSeedSpec
    public let availablePackageIDs: [PackageID]
    public let availableChapterIDs: [ChapterID]

    private let packagesByID: [PackageID: ContentPackageSpec]
    private let catalogByChapterID: [ChapterID: ChapterIndexEntry]
    private let chaptersByID: [ChapterID: ChapterSpec]
    private let arcsByID: [ArcID: ArcSpec]
    private let beatsByID: [BeatID: BeatSpec]
    private let scenesByID: [SceneID: SceneSpec]
    private let interactionsByID: [InteractionID: InteractionSpec]
    private let audioTimelinesByID: [AudioTimelineID: AudioTimeline]
    private let responsiveAudioProgramsByID: [ResponsiveAudioProgramID: ResponsiveAudioProgramSpec]
    private let responsiveAudioProgramIDByInteractionID: [InteractionID: ResponsiveAudioProgramID]
    private let timelineIDByCueID: [AudioCueID: AudioTimelineID]
    private let accessibilityByID: [AccessibilityID: AccessibilitySpec]
    private let packageIDByChapterID: [ChapterID: PackageID]
    private let arcLocationsByID: [ArcID: ArcContentLocation]
    private let beatLocationsByID: [BeatID: BeatContentLocation]

    /// Used for bundled essential content after its canonical payload has been
    /// decoded. Validation is repeated here so malformed in-memory inputs fail
    /// closed at the same indexing boundary as downloaded packages.
    public init(
        manifest: CollectionManifest = LaunchContent.collectionManifest,
        packagePayloads: [ContentPackagePayload]
    ) throws {
        try self.init(
            manifest: manifest,
            inputs: packagePayloads.map {
                RepositoryPackageInput(payload: $0, signedManifest: nil)
            },
            boundary: .launch
        )
    }

    /// Used for activated downloads after a verifier-created signature,
    /// inventory and file-tree boundary. The signed metadata is checked again
    /// against the current generated launch catalog before payload indexing.
    public init(
        manifest: CollectionManifest = LaunchContent.collectionManifest,
        verifiedPackages: [VerifiedContentPackage]
    ) throws {
        try self.init(
            manifest: manifest,
            inputs: verifiedPackages.map {
                RepositoryPackageInput(
                    payload: $0.payload,
                    signedManifest: $0.manifest
                )
            },
            boundary: .launch
        )
    }

    /// Production launch assembly has two explicit trust domains: one
    /// code-signed essential payload and zero or more packages that have
    /// already crossed signature and installed-tree verification. The
    /// downloaded side can never shadow the free package bundled with the app.
    public init(
        manifest: CollectionManifest = LaunchContent.collectionManifest,
        bundledEssentialPayload: ContentPackagePayload,
        verifiedPackages: [VerifiedContentPackage]
    ) throws {
        guard bundledEssentialPayload.packageID == LaunchContent.essentialPackageID else {
            throw ContentRepositoryError.bundledEssentialPackageMismatch(
                actual: bundledEssentialPayload.packageID
            )
        }
        if let essentialDownload = verifiedPackages.first(where: {
            $0.payload.packageID == LaunchContent.essentialPackageID
        }) {
            throw ContentRepositoryError.downloadedEssentialPackageForbidden(
                essentialDownload.payload.packageID
            )
        }
        try self.init(
            manifest: manifest,
            inputs: [
                RepositoryPackageInput(
                    payload: bundledEssentialPayload,
                    signedManifest: nil
                ),
            ] + verifiedPackages.map {
                RepositoryPackageInput(
                    payload: $0.payload,
                    signedManifest: $0.manifest
                )
            },
            boundary: .launch
        )
    }

    init(
        retainedLaunchContinuityManifest manifest: CollectionManifest,
        bundledEssentialPayload: ContentPackagePayload,
        verifiedPackages: [VerifiedContentPackage]
    ) throws {
        guard bundledEssentialPayload.packageID
            == LaunchContent.essentialPackageID else {
            throw ContentRepositoryError.bundledEssentialPackageMismatch(
                actual: bundledEssentialPayload.packageID
            )
        }
        if let essentialDownload = verifiedPackages.first(where: {
            $0.payload.packageID == LaunchContent.essentialPackageID
        }) {
            throw ContentRepositoryError.downloadedEssentialPackageForbidden(
                essentialDownload.payload.packageID
            )
        }
        try self.init(
            manifest: manifest,
            inputs: [
                RepositoryPackageInput(
                    payload: bundledEssentialPayload,
                    signedManifest: nil
                ),
            ] + verifiedPackages.map {
                RepositoryPackageInput(
                    payload: $0.payload,
                    signedManifest: $0.manifest
                )
            },
            boundary: .retainedLaunchContinuity
        )
    }

    /// Admits one independently delivered post-launch work after the package
    /// has crossed signature, installed-tree and canonical-payload
    /// verification against its separately authenticated Release contract.
    /// The synthetic one-package collection exists only as a runtime index; it
    /// cannot widen or replace any of the 24 locked launch chapters.
    public init(
        trustedFutureRelease release: Release,
        verifiedPackage: VerifiedContentPackage,
        expectedWorldSeed: WorldSeedSpec
    ) throws {
        try self.init(
            trustedFutureReleaseContinuity: release,
            verifiedPackage: verifiedPackage,
            expectedWorldSeed: expectedWorldSeed,
            admittedPackageVersion: release.version
        )
    }

    /// Re-admits an exact retained predecessor after a failed save migration.
    /// Only the version may move backwards: package/chapter ownership, byte
    /// budget, minimum runtime and world continuity remain bound to the
    /// independently authenticated current Release.
    init(
        trustedFutureReleaseContinuity release: Release,
        retainedVerifiedPackage verifiedPackage: VerifiedContentPackage,
        expectedWorldSeed: WorldSeedSpec,
        retainedPackageVersion: SchemaVersion
    ) throws {
        guard retainedPackageVersion <= release.version,
              verifiedPackage.manifest.packageVersion
                == retainedPackageVersion else {
            throw ContentRepositoryError.invalidFutureRelease(
                "Retained package identity is outside Release continuity"
            )
        }
        try self.init(
            trustedFutureReleaseContinuity: release,
            verifiedPackage: verifiedPackage,
            expectedWorldSeed: expectedWorldSeed,
            admittedPackageVersion: retainedPackageVersion
        )
    }

    private init(
        trustedFutureReleaseContinuity release: Release,
        verifiedPackage: VerifiedContentPackage,
        expectedWorldSeed: WorldSeedSpec,
        admittedPackageVersion: SchemaVersion
    ) throws {
        do {
            try release.validate()
        } catch {
            throw ContentRepositoryError.invalidFutureRelease(
                String(describing: error)
            )
        }

        let payload = verifiedPackage.payload
        guard release.packageID == payload.packageID else {
            throw ContentRepositoryError.invalidFutureRelease(
                "Release and payload package IDs differ"
            )
        }
        guard release.chapterIDs == payload.chapters.map(\.id) else {
            throw ContentRepositoryError.invalidFutureRelease(
                "Release chapter order must exactly match the payload"
            )
        }
        guard payload.worldSeed == expectedWorldSeed else {
            throw ContentRepositoryError.worldSeedMismatch(
                packageID: payload.packageID
            )
        }
        try Self.requireFutureReleaseWorldEffectNamespaces(in: payload)

        if LaunchContent.packageIDsInDeliveryOrder.contains(release.packageID) {
            throw ContentRepositoryError.futureReleaseLaunchCollision(
                namespace: "package",
                identifier: release.packageID.rawValue
            )
        }
        if let collision = release.chapterIDs.first(where: {
            LaunchContent.chapterOrder.contains($0)
        }) {
            throw ContentRepositoryError.futureReleaseLaunchCollision(
                namespace: "chapter",
                identifier: collision.rawValue
            )
        }

        let package = ContentPackageSpec(
            id: release.packageID,
            version: admittedPackageVersion,
            chapterIDs: release.chapterIDs,
            maximumInstalledBytes: release.maximumInstalledBytes,
            minimumRuntime: release.minimumRuntime,
            isEssentialInstall: false
        )
        let collectionID = CollectionID(
            "future-release-\(release.id.rawValue)"
        )
        let manifest = CollectionManifest(
            schemaVersion: payload.schemaVersion,
            collectionID: collectionID,
            locale: .launchEnglish,
            product: .current,
            chapters: payload.chapters.enumerated().map { offset, chapter in
                ChapterIndexEntry(
                    id: chapter.id,
                    sequence: offset + 1,
                    title: chapter.title,
                    period: chapter.period,
                    packageID: package.id,
                    access: .included
                )
            },
            packages: [package],
            entitlements: []
        )
        try self.init(
            manifest: manifest,
            inputs: [
                RepositoryPackageInput(
                    payload: payload,
                    signedManifest: verifiedPackage.manifest
                ),
            ],
            boundary: .futureRelease(
                requiredPackageID: package.id,
                requiredCollectionID: collectionID,
                expectedWorldSeed: expectedWorldSeed
            )
        )
    }

#if DEBUG || NON_SHIPPING_LIVE_TEST
    /// The only non-launch repository admitted by the app. The package must
    /// already have crossed `ContentPackageVerifier` under the isolated
    /// development vertical-slice identity. This overload is absent from an
    /// ordinary Release build, so fixture trust can never widen the launch
    /// manifest.
    public init(developmentVerticalSlice verifiedPackage: VerifiedContentPackage) throws {
        let packageID = PackageID("vertical-slice-development-v1")
        let chapterIDs = [
            ChapterID("first-farmers"),
            ChapterID("europe-holds-the-line"),
            ChapterID("european-world"),
        ]
        let requiredVersion = SchemaVersion(major: 1)
        guard verifiedPackage.manifest.packageID == packageID,
              verifiedPackage.payload.packageID == packageID,
              verifiedPackage.manifest.signature.keyID
                == "vertical-slice-development-key-v1",
              verifiedPackage.manifest.packageVersion == requiredVersion,
              verifiedPackage.manifest.schemaVersion == requiredVersion,
              verifiedPackage.manifest.minimumRuntime == requiredVersion,
              verifiedPackage.payload.schemaVersion == requiredVersion,
              verifiedPackage.payload.chapters.map(\.id) == chapterIDs else {
            throw ContentRepositoryError.invalidLaunchManifest(
                "Non-shipping vertical-slice trust boundary mismatch"
            )
        }

        let package = ContentPackageSpec(
            id: packageID,
            version: requiredVersion,
            chapterIDs: chapterIDs,
            maximumInstalledBytes: 750_000_000,
            minimumRuntime: requiredVersion,
            isEssentialInstall: true
        )
        let manifest = CollectionManifest(
            schemaVersion: requiredVersion,
            collectionID: CollectionID("vertical-slice-development-collection-v1"),
            locale: .launchEnglish,
            product: .current,
            chapters: verifiedPackage.payload.chapters.enumerated().map { index, chapter in
                ChapterIndexEntry(
                    id: chapter.id,
                    sequence: index + 1,
                    title: chapter.title,
                    period: chapter.period,
                    packageID: packageID,
                    access: .included
                )
            },
            packages: [package],
            entitlements: []
        )
        try self.init(
            manifest: manifest,
            inputs: [
                RepositoryPackageInput(
                    payload: verifiedPackage.payload,
                    signedManifest: verifiedPackage.manifest
                ),
            ],
            boundary: .developmentVerticalSlice(requiredPackageID: packageID)
        )
    }
#endif

    public func package(_ id: PackageID) -> ContentPackageSpec? {
        packagesByID[id]
    }

    public func catalogEntry(_ id: ChapterID) -> ChapterIndexEntry? {
        catalogByChapterID[id]
    }

    public func chapter(_ id: ChapterID) -> ChapterSpec? {
        chaptersByID[id]
    }

    public func arc(_ id: ArcID) -> ArcSpec? {
        arcsByID[id]
    }

    public func beat(_ id: BeatID) -> BeatSpec? {
        beatsByID[id]
    }

    public func scene(_ id: SceneID) -> SceneSpec? {
        scenesByID[id]
    }

    public func interaction(_ id: InteractionID) -> InteractionSpec? {
        interactionsByID[id]
    }

    public func audioTimeline(_ id: AudioTimelineID) -> AudioTimeline? {
        audioTimelinesByID[id]
    }

    public func audioTimeline(containing cueID: AudioCueID) -> AudioTimeline? {
        guard let timelineID = timelineIDByCueID[cueID] else { return nil }
        return audioTimelinesByID[timelineID]
    }

    public func responsiveAudioProgram(
        _ id: ResponsiveAudioProgramID
    ) -> ResponsiveAudioProgramSpec? {
        responsiveAudioProgramsByID[id]
    }

    public func responsiveAudioProgram(
        for interactionID: InteractionID
    ) -> ResponsiveAudioProgramSpec? {
        guard let programID = responsiveAudioProgramIDByInteractionID[interactionID] else {
            return nil
        }
        return responsiveAudioProgramsByID[programID]
    }

    public func responsiveAudioTimelines(
        for interactionID: InteractionID
    ) -> [AudioTimeline]? {
        guard let program = responsiveAudioProgram(for: interactionID) else { return nil }
        let ids = [program.approachTimelineID]
            + program.interactionBeds.map(\.timelineID)
            + [program.consequenceTimelineID]
        let timelines = ids.compactMap { audioTimelinesByID[$0] }
        return timelines.count == ids.count ? timelines : nil
    }

    public func accessibility(_ id: AccessibilityID) -> AccessibilitySpec? {
        accessibilityByID[id]
    }

    public func packageID(for chapterID: ChapterID) -> PackageID? {
        packageIDByChapterID[chapterID]
    }

    public func contentVersion(for chapterID: ChapterID) -> SchemaVersion? {
        guard let packageID = packageIDByChapterID[chapterID] else { return nil }
        return packagesByID[packageID]?.version
    }

    public func location(of arcID: ArcID) -> ArcContentLocation? {
        arcLocationsByID[arcID]
    }

    public func location(of beatID: BeatID) -> BeatContentLocation? {
        beatLocationsByID[beatID]
    }

    public func audioTimelineIDs(for beatID: BeatID) -> [AudioTimelineID]? {
        guard let beat = beatsByID[beatID] else { return nil }
        var seen: Set<AudioTimelineID> = []
        return beat.narrationCueIDs.compactMap { cueID in
            guard let timelineID = timelineIDByCueID[cueID],
                  seen.insert(timelineID).inserted else {
                return nil
            }
            return timelineID
        }
    }

    private init(
        manifest: CollectionManifest,
        inputs: [RepositoryPackageInput],
        boundary: ManifestBoundary
    ) throws {
        let requiredBasePackageID: PackageID
        switch boundary {
        case .launch:
            guard manifest == LaunchContent.collectionManifest else {
                throw ContentRepositoryError.launchManifestMismatch
            }
            do {
                try manifest.validateLaunch()
            } catch {
                throw ContentRepositoryError.invalidLaunchManifest(String(describing: error))
            }
            requiredBasePackageID = LaunchContent.essentialPackageID
        case .retainedLaunchContinuity:
            try Self.validateRetainedLaunchContinuity(manifest)
            requiredBasePackageID = LaunchContent.essentialPackageID
        case let .futureRelease(
            requiredPackageID,
            requiredCollectionID,
            _
        ):
            do {
                try manifest.validate()
            } catch {
                throw ContentRepositoryError.invalidFutureRelease(
                    String(describing: error)
                )
            }
            guard manifest.collectionID == requiredCollectionID,
                  manifest.locale == .launchEnglish,
                  manifest.product == .current,
                  manifest.packages.count == 1,
                  manifest.packages[0].id == requiredPackageID,
                  !manifest.packages[0].isEssentialInstall,
                  manifest.chapters.map(\.packageID).allSatisfy({
                      $0 == requiredPackageID
                  }),
                  manifest.chapters.allSatisfy({ chapter in
                      if case .included = chapter.access { return true }
                      return false
                  }),
                  manifest.entitlements.isEmpty else {
                throw ContentRepositoryError.invalidFutureRelease(
                    "isolated one-package collection boundary mismatch"
                )
            }
            requiredBasePackageID = requiredPackageID
#if DEBUG || NON_SHIPPING_LIVE_TEST
        case let .developmentVerticalSlice(requiredPackageID):
            do {
                try manifest.validate()
            } catch {
                throw ContentRepositoryError.invalidLaunchManifest(String(describing: error))
            }
            guard manifest.packages.map(\.id) == [requiredPackageID],
                  !manifest.chapters.isEmpty,
                  manifest.chapters.allSatisfy({
                      $0.packageID == requiredPackageID
                  }),
                  manifest.entitlements.isEmpty else {
                throw ContentRepositoryError.invalidLaunchManifest(
                    "Non-shipping vertical-slice manifest boundary mismatch"
                )
            }
            requiredBasePackageID = requiredPackageID
#endif
        }
        guard !inputs.isEmpty else {
            throw ContentRepositoryError.emptyPackageSet
        }

        let packageSpecs = Dictionary(
            uniqueKeysWithValues: manifest.packages.map { ($0.id, $0) }
        )
        let catalog = Dictionary(
            uniqueKeysWithValues: manifest.chapters.map { ($0.id, $0) }
        )
        var inputByPackageID: [PackageID: RepositoryPackageInput] = [:]

        for input in inputs {
            let packageID = input.payload.packageID
            guard let packageSpec = packageSpecs[packageID] else {
                throw ContentRepositoryError.unknownPackage(packageID)
            }
            guard inputByPackageID.updateValue(input, forKey: packageID) == nil else {
                throw ContentRepositoryError.duplicatePackage(packageID)
            }
            do {
                try input.payload.validate()
            } catch {
                throw ContentRepositoryError.invalidPackage(
                    packageID: packageID,
                    reason: String(describing: error)
                )
            }
            guard input.payload.schemaVersion == manifest.schemaVersion else {
                throw ContentRepositoryError.packageSchemaMismatch(
                    packageID: packageID,
                    expected: manifest.schemaVersion,
                    actual: input.payload.schemaVersion
                )
            }
            guard input.payload.chapters.map(\.id) == packageSpec.chapterIDs else {
                throw ContentRepositoryError.chapterOwnershipMismatch(packageID: packageID)
            }

            if let signedManifest = input.signedManifest {
                guard signedManifest.packageID == packageID else {
                    throw ContentRepositoryError.chapterOwnershipMismatch(packageID: packageID)
                }
                guard signedManifest.packageVersion == packageSpec.version else {
                    throw ContentRepositoryError.packageVersionMismatch(
                        packageID: packageID,
                        expected: packageSpec.version,
                        actual: signedManifest.packageVersion
                    )
                }
                guard signedManifest.schemaVersion == input.payload.schemaVersion else {
                    throw ContentRepositoryError.packageSchemaMismatch(
                        packageID: packageID,
                        expected: input.payload.schemaVersion,
                        actual: signedManifest.schemaVersion
                    )
                }
                guard signedManifest.minimumRuntime == packageSpec.minimumRuntime else {
                    throw ContentRepositoryError.packageRuntimeMismatch(
                        packageID: packageID,
                        expected: packageSpec.minimumRuntime,
                        actual: signedManifest.minimumRuntime
                    )
                }
            } else if case .futureRelease = boundary {
                throw ContentRepositoryError.invalidFutureRelease(
                    "a verifier-authenticated signed package is required"
                )
            }

            for chapter in input.payload.chapters {
                guard let entry = catalog[chapter.id],
                      entry.packageID == packageID,
                      entry.title == chapter.title,
                      entry.period == chapter.period else {
                    throw ContentRepositoryError.catalogChapterMismatch(chapterID: chapter.id)
                }
            }
        }

        guard inputByPackageID[requiredBasePackageID] != nil else {
            throw ContentRepositoryError.missingEssentialPackage(
                requiredBasePackageID
            )
        }

        let orderedPackageIDs = manifest.packages.map(\.id).filter {
            inputByPackageID[$0] != nil
        }
        guard let firstPackageID = orderedPackageIDs.first,
              let canonicalWorldSeed = inputByPackageID[firstPackageID]?.payload.worldSeed else {
            throw ContentRepositoryError.emptyPackageSet
        }
        for packageID in orderedPackageIDs.dropFirst() {
            guard inputByPackageID[packageID]?.payload.worldSeed == canonicalWorldSeed else {
                throw ContentRepositoryError.worldSeedMismatch(packageID: packageID)
            }
        }
        if case let .futureRelease(_, _, expectedWorldSeed) = boundary,
           canonicalWorldSeed != expectedWorldSeed {
            throw ContentRepositoryError.worldSeedMismatch(
                packageID: requiredBasePackageID
            )
        }

        var chapterIndex: [ChapterID: ChapterSpec] = [:]
        var arcIndex: [ArcID: ArcSpec] = [:]
        var beatIndex: [BeatID: BeatSpec] = [:]
        var sceneIndex: [SceneID: SceneSpec] = [:]
        var interactionIndex: [InteractionID: InteractionSpec] = [:]
        var audioIndex: [AudioTimelineID: AudioTimeline] = [:]
        var responsiveAudioIndex: [ResponsiveAudioProgramID: ResponsiveAudioProgramSpec] = [:]
        var responsiveAudioByInteraction: [InteractionID: ResponsiveAudioProgramID] = [:]
        var cueIndex: [AudioCueID: AudioTimelineID] = [:]
        var accessibilityIndex: [AccessibilityID: AccessibilitySpec] = [:]
        var packageByChapter: [ChapterID: PackageID] = [:]
        var arcLocations: [ArcID: ArcContentLocation] = [:]
        var beatLocations: [BeatID: BeatContentLocation] = [:]

        var chapterOwners: [ChapterID: PackageID] = [:]
        var arcOwners: [ArcID: PackageID] = [:]
        var beatOwners: [BeatID: PackageID] = [:]
        var sceneOwners: [SceneID: PackageID] = [:]
        var interactionOwners: [InteractionID: PackageID] = [:]
        var timelineOwners: [AudioTimelineID: PackageID] = [:]
        var responsiveAudioOwners: [ResponsiveAudioProgramID: PackageID] = [:]
        var responsiveInteractionOwners: [InteractionID: PackageID] = [:]
        var cueOwners: [AudioCueID: PackageID] = [:]
        var accessibilityOwners: [AccessibilityID: PackageID] = [:]
        var effectOwners: [WorldEffectID: PackageID] = [:]

        for packageID in orderedPackageIDs {
            guard let payload = inputByPackageID[packageID]?.payload else { continue }
            for chapter in payload.chapters {
                try Self.register(
                    chapter.id,
                    namespace: "chapter",
                    packageID: packageID,
                    owners: &chapterOwners
                )
                chapterIndex[chapter.id] = chapter
                packageByChapter[chapter.id] = packageID

                for effect in chapter.completionEffects {
                    try Self.register(
                        effect.id,
                        namespace: "world-effect",
                        packageID: packageID,
                        owners: &effectOwners
                    )
                }
                for (arcOffset, arc) in chapter.arcs.enumerated() {
                    try Self.register(
                        arc.id,
                        namespace: "arc",
                        packageID: packageID,
                        owners: &arcOwners
                    )
                    arcIndex[arc.id] = arc
                    arcLocations[arc.id] = ArcContentLocation(
                        chapterID: chapter.id,
                        arcIndex: arcOffset
                    )

                    for (beatOffset, beat) in arc.beats.enumerated() {
                        try Self.register(
                            beat.id,
                            namespace: "beat",
                            packageID: packageID,
                            owners: &beatOwners
                        )
                        beatIndex[beat.id] = beat
                        beatLocations[beat.id] = BeatContentLocation(
                            chapterID: chapter.id,
                            arcID: arc.id,
                            arcIndex: arcOffset,
                            beatIndex: beatOffset
                        )
                        for effect in beat.completionEffects {
                            try Self.register(
                                effect.id,
                                namespace: "world-effect",
                                packageID: packageID,
                                owners: &effectOwners
                            )
                        }
                        if let interaction = beat.interaction {
                            try Self.register(
                                interaction.id,
                                namespace: "interaction",
                                packageID: packageID,
                                owners: &interactionOwners
                            )
                            interactionIndex[interaction.id] = interaction
                            for effect in interaction.completionEffects {
                                try Self.register(
                                    effect.id,
                                    namespace: "world-effect",
                                    packageID: packageID,
                                    owners: &effectOwners
                                )
                            }
                        }
                    }
                }
            }

            for scene in payload.scenes {
                try Self.register(
                    scene.id,
                    namespace: "scene",
                    packageID: packageID,
                    owners: &sceneOwners
                )
                sceneIndex[scene.id] = scene
            }
            for timeline in payload.audioTimelines {
                try Self.register(
                    timeline.id,
                    namespace: "audio-timeline",
                    packageID: packageID,
                    owners: &timelineOwners
                )
                audioIndex[timeline.id] = timeline
                for event in timeline.events {
                    try Self.register(
                        event.cueID,
                        namespace: "audio-cue",
                        packageID: packageID,
                        owners: &cueOwners
                    )
                    cueIndex[event.cueID] = timeline.id
                }
            }
            for program in payload.responsiveAudioPrograms {
                try Self.register(
                    program.id,
                    namespace: "responsive-audio-program",
                    packageID: packageID,
                    owners: &responsiveAudioOwners
                )
                try Self.register(
                    program.scope.interactionID,
                    namespace: "responsive-audio-interaction-binding",
                    packageID: packageID,
                    owners: &responsiveInteractionOwners
                )
                responsiveAudioIndex[program.id] = program
                responsiveAudioByInteraction[program.scope.interactionID] = program.id
            }
            for specification in payload.accessibility {
                try Self.register(
                    specification.id,
                    namespace: "accessibility",
                    packageID: packageID,
                    owners: &accessibilityOwners
                )
                accessibilityIndex[specification.id] = specification
            }
        }

        let canonicalChapters = manifest.chapters.compactMap { chapterIndex[$0.id] }
        do {
            _ = try WorldReplayValidator.validate(
                seed: canonicalWorldSeed,
                chapters: canonicalChapters
            )
        } catch {
            throw ContentRepositoryError.invalidCumulativeWorld(
                String(describing: error)
            )
        }

        self.manifest = manifest
        worldSeed = canonicalWorldSeed
        availablePackageIDs = orderedPackageIDs
        availableChapterIDs = manifest.chapters.map(\.id).filter {
            chapterIndex[$0] != nil
        }
        packagesByID = packageSpecs
        catalogByChapterID = catalog
        chaptersByID = chapterIndex
        arcsByID = arcIndex
        beatsByID = beatIndex
        scenesByID = sceneIndex
        interactionsByID = interactionIndex
        audioTimelinesByID = audioIndex
        responsiveAudioProgramsByID = responsiveAudioIndex
        responsiveAudioProgramIDByInteractionID = responsiveAudioByInteraction
        timelineIDByCueID = cueIndex
        accessibilityByID = accessibilityIndex
        packageIDByChapterID = packageByChapter
        arcLocationsByID = arcLocations
        beatLocationsByID = beatLocations
    }

    private static func validateRetainedLaunchContinuity(
        _ manifest: CollectionManifest
    ) throws {
        let trusted = LaunchContent.collectionManifest
        do {
            try manifest.validateLaunch()
        } catch {
            throw ContentRepositoryError.invalidLaunchManifest(
                String(describing: error)
            )
        }
        guard manifest.schemaVersion == trusted.schemaVersion,
              manifest.collectionID == trusted.collectionID,
              manifest.locale == trusted.locale,
              manifest.product == trusted.product,
              manifest.chapters == trusted.chapters,
              manifest.entitlements == trusted.entitlements,
              manifest.packages.count == trusted.packages.count else {
            throw ContentRepositoryError.launchManifestMismatch
        }
        for (candidate, current) in zip(
            manifest.packages,
            trusted.packages
        ) {
            guard candidate.id == current.id,
                  candidate.chapterIDs == current.chapterIDs,
                  candidate.maximumInstalledBytes
                    == current.maximumInstalledBytes,
                  candidate.minimumRuntime == current.minimumRuntime,
                  candidate.isEssentialInstall
                    == current.isEssentialInstall,
                  candidate.version <= current.version,
                  candidate.id != LaunchContent.essentialPackageID
                    || candidate.version == current.version else {
                throw ContentRepositoryError.launchManifestMismatch
            }
        }
    }

    private static func register<Identifier>(
        _ identifier: Identifier,
        namespace: String,
        packageID: PackageID,
        owners: inout [Identifier: PackageID]
    ) throws where Identifier: Hashable, Identifier: CustomStringConvertible {
        if let firstPackage = owners[identifier] {
            throw ContentRepositoryError.duplicateIdentifier(
                namespace: namespace,
                identifier: identifier.description,
                firstPackage: firstPackage,
                secondPackage: packageID
            )
        }
        owners[identifier] = packageID
    }

    /// JourneyState stores applied effects in one global cumulative world.
    /// A future package is indexed separately, so its effect identity must be
    /// derived from the globally unique owning chapter rather than relying on
    /// cross-package dictionary checks which cannot see uninstalled content.
    private static func requireFutureReleaseWorldEffectNamespaces(
        in payload: ContentPackagePayload
    ) throws {
        for chapter in payload.chapters {
            let prefix = "effect-\(chapter.id.rawValue)-"
            let effects = chapter.completionEffects + chapter.arcs.flatMap {
                $0.beats.flatMap { beat in
                    beat.completionEffects
                        + (beat.interaction?.completionEffects ?? [])
                }
            }
            if let invalid = effects.first(where: {
                !$0.id.rawValue.hasPrefix(prefix)
                    || $0.id.rawValue.count == prefix.count
            }) {
                throw ContentRepositoryError.invalidFutureRelease(
                    "world-effect \(invalid.id.rawValue) must use owning chapter namespace \(prefix)"
                )
            }
        }
    }
}

private struct RepositoryPackageInput: Sendable {
    let payload: ContentPackagePayload
    let signedManifest: SignedPackageManifest?
}
