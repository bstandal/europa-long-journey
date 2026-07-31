import ContentKit
import CryptoKit
import Foundation
@testable import JourneyDomain
@testable import ProgressStore
import XCTest

final class SaveMigrationRegistryTests: XCTestCase {
    func testSignedGraphMigratesEveryRestorationSurfaceAndReplaysDeterministically() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyStore = try ProgressStore(directoryURL: directory)
        try await legacyStore.checkpoint(Self.legacyState)
        let snapshotBefore = try Data(contentsOf: legacyStore.snapshotFileURL)
        let journalBefore = try Data(contentsOf: legacyStore.journalFileURL)

        let registry = try SaveMigrationRegistry(steps: [Self.fullStep])
        let migratingStore = try ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: registry,
            saveMigrationAuthorities: [Self.fullAuthority]
        )
        let first = try await migratingStore.restore()
        assertFullyMigrated(first.state)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: migratingStore.migrationLastKnownGoodFileURL.path
            )
        )

        try await migratingStore.rollbackToLastKnownGoodSave()
        XCTAssertEqual(try Data(contentsOf: migratingStore.snapshotFileURL), snapshotBefore)
        XCTAssertEqual(try Data(contentsOf: migratingStore.journalFileURL), journalBefore)

        let replayStore = try ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: registry,
            saveMigrationAuthorities: [Self.fullAuthority]
        )
        let replayed = try await replayStore.restore()
        assertFullyMigrated(replayed.state)
        XCTAssertEqual(replayed.state, first.state)
        XCTAssertEqual(
            Self.sha256(try Self.canonicalEncoder.encode(replayed.state)),
            Self.sha256(try Self.canonicalEncoder.encode(first.state))
        )
    }

    func testUnknownAndAmbiguousSignedPathsFailClosedBeforeTransform() throws {
        let unknownAuthority = Self.authority(
            target: Self.v3,
            declarations: [
                Self.declaration(id: "only-two-to-three", from: Self.v2, to: Self.v3),
            ]
        )
        XCTAssertThrowsError(
            try SaveMigrationRegistry.empty.migrate(
                SaveSnapshot(state: Self.legacyState),
                authorities: [unknownAuthority]
            )
        ) { error in
            XCTAssertEqual(
                error as? SaveMigrationRegistryError,
                .unknownPath(packageID: Self.packageID, from: Self.v1, to: Self.v3)
            )
        }

        let ambiguousAuthority = Self.authority(
            target: Self.v3,
            declarations: [
                Self.declaration(id: "direct-one-to-three", from: Self.v1, to: Self.v3),
                Self.declaration(id: "one-to-two", from: Self.v1, to: Self.v2),
                Self.declaration(id: "two-to-three", from: Self.v2, to: Self.v3),
            ]
        )
        XCTAssertThrowsError(
            try SaveMigrationRegistry.empty.migrate(
                SaveSnapshot(state: Self.legacyState),
                authorities: [ambiguousAuthority]
            )
        ) { error in
            XCTAssertEqual(
                error as? SaveMigrationRegistryError,
                .ambiguousPath(packageID: Self.packageID, from: Self.v1, to: Self.v3)
            )
        }
    }

    func testDescriptorTamperAndUndeclaredMutationFailClosed() throws {
        let mismatchedStep = PackageSaveMigrationStep(
            packageID: Self.packageID,
            declarationID: Self.fullDeclaration.id,
            fromContentVersion: Self.v1,
            toContentVersion: Self.v2,
            canonicalTransformDescriptor: Data("different-descriptor".utf8),
            transform: Self.fullTransform
        )
        let mismatchedRegistry = try SaveMigrationRegistry(steps: [mismatchedStep])
        XCTAssertThrowsError(
            try mismatchedRegistry.migrate(
                SaveSnapshot(state: Self.legacyState),
                authorities: [Self.fullAuthority]
            )
        ) { error in
            XCTAssertEqual(
                error as? SaveMigrationRegistryError,
                .implementationDescriptorMismatch(
                    packageID: Self.packageID,
                    declarationID: Self.fullDeclaration.id
                )
            )
        }

        let narrowDeclaration = Self.declaration(
            id: "narrow-one-to-two",
            from: Self.v1,
            to: Self.v2,
            fields: [.beatIdentity]
        )
        let narrowStep = PackageSaveMigrationStep(
            packageID: Self.packageID,
            declarationID: narrowDeclaration.id,
            fromContentVersion: Self.v1,
            toContentVersion: Self.v2,
            canonicalTransformDescriptor: Self.fullDescriptor,
            transform: Self.fullTransform
        )
        let narrowRegistry = try SaveMigrationRegistry(steps: [narrowStep])
        let narrowAuthority = Self.authority(target: Self.v2, declarations: [
            PackageSaveMigrationDeclaration(
                id: narrowDeclaration.id,
                fromContentVersion: narrowDeclaration.fromContentVersion,
                toContentVersion: narrowDeclaration.toContentVersion,
                requiredSaveFormatVersion: narrowDeclaration.requiredSaveFormatVersion,
                requiredStateSchemaVersion: narrowDeclaration.requiredStateSchemaVersion,
                fields: narrowDeclaration.fields,
                implementationSHA256: narrowStep.implementationSHA256
            ),
        ])
        XCTAssertThrowsError(
            try narrowRegistry.migrate(
                SaveSnapshot(state: Self.legacyState),
                authorities: [narrowAuthority]
            )
        ) { error in
            XCTAssertEqual(
                error as? SaveMigrationRegistryError,
                .undeclaredFieldMutation(
                    packageID: Self.packageID,
                    declarationID: narrowDeclaration.id,
                    field: .cumulativeWorldState
                )
            )
        }
    }

    func testInterruptedCommitRestoresExactPriorBytesAndTamperedRecoveryFailsClosed() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyStore = try ProgressStore(directoryURL: directory)
        try await legacyStore.checkpoint(Self.legacyState)
        let snapshotBefore = try Data(contentsOf: legacyStore.snapshotFileURL)
        let journalBefore = try Data(contentsOf: legacyStore.journalFileURL)

        let interrupted = try ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: SaveMigrationRegistry(steps: [Self.fullStep]),
            saveMigrationAuthorities: [Self.fullAuthority],
            saveMigrationBoundaryOperation: { boundary in
                if case .snapshotActivated = boundary { throw InjectedInterruption() }
            }
        )
        do {
            _ = try await interrupted.restore()
            XCTFail("Injected migration interruption must escape")
        } catch {
            XCTAssertEqual(error as? ProgressStoreError, .migrationInterrupted)
        }
        XCTAssertEqual(try Data(contentsOf: interrupted.snapshotFileURL), snapshotBefore)
        XCTAssertEqual(try Data(contentsOf: interrupted.journalFileURL), journalBefore)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: interrupted.migrationInFlightFileURL.path)
        )

        var tampered = try Data(contentsOf: interrupted.migrationLastKnownGoodFileURL)
        tampered[tampered.startIndex] ^= 0x01
        try tampered.write(
            to: interrupted.migrationInFlightFileURL,
            options: Data.WritingOptions.atomic
        )
        let recovering = try ProgressStore(directoryURL: directory)
        do {
            _ = try await recovering.restore()
            XCTFail("A tampered rollback authority must fail closed")
        } catch {
            XCTAssertEqual(error as? ProgressStoreError, .migrationRollbackTampered)
        }
        XCTAssertEqual(try Data(contentsOf: recovering.snapshotFileURL), snapshotBefore)
        XCTAssertEqual(try Data(contentsOf: recovering.journalFileURL), journalBefore)
    }

    func testLastKnownGoodRollbackRefusesToEraseLaterProgress() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyStore = try ProgressStore(directoryURL: directory)
        try await legacyStore.checkpoint(Self.legacyState)

        let store = try ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: SaveMigrationRegistry(steps: [Self.fullStep]),
            saveMigrationAuthorities: [Self.fullAuthority]
        )
        _ = try await store.restore()
        _ = try await store.append(
            JourneyEvent(logicalTimeMillis: 78, action: .showWorld)
        )
        let snapshotAfterProgress = try Data(contentsOf: store.snapshotFileURL)
        let journalAfterProgress = try Data(contentsOf: store.journalFileURL)

        do {
            try await store.rollbackToLastKnownGoodSave()
            XCTFail("A stale migration backup must never erase newer progress")
        } catch {
            XCTAssertEqual(error as? ProgressStoreError, .migrationRollbackStale)
        }
        XCTAssertEqual(try Data(contentsOf: store.snapshotFileURL), snapshotAfterProgress)
        XCTAssertEqual(try Data(contentsOf: store.journalFileURL), journalAfterProgress)
    }

    func testRollbackRequiresTheExactActiveGenerationAuthority() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyStore = try ProgressStore(directoryURL: directory)
        try await legacyStore.checkpoint(Self.legacyState)

        let migratingStore = try ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: SaveMigrationRegistry(steps: [Self.fullStep]),
            saveMigrationAuthorities: [Self.fullAuthority]
        )
        _ = try await migratingStore.restore()
        let snapshotAfterMigration = try Data(contentsOf: migratingStore.snapshotFileURL)
        let journalAfterMigration = try Data(contentsOf: migratingStore.journalFileURL)

        let otherGenerationAuthority = VerifiedPackageSaveMigrationAuthority(
            packageID: Self.packageID,
            targetContentVersion: Self.v2,
            manifestDigest: String(repeating: "b", count: 64),
            activeGeneration: ActiveSaveMigrationPackageGeneration(
                generationID: "different-active-generation",
                packageID: Self.packageID,
                packageVersion: Self.v2,
                manifestDigest: String(repeating: "b", count: 64),
                activationSequence: 2
            ),
            declarations: [Self.fullDeclaration]
        )
        let mismatchedStore = try ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: SaveMigrationRegistry(steps: [Self.fullStep]),
            saveMigrationAuthorities: [otherGenerationAuthority]
        )
        do {
            try await mismatchedStore.rollbackToLastKnownGoodSave()
            XCTFail("Rollback must be bound to the exact active generation")
        } catch {
            XCTAssertEqual(
                error as? ProgressStoreError,
                .migrationRollbackAuthorityMismatch
            )
        }
        XCTAssertEqual(try Data(contentsOf: mismatchedStore.snapshotFileURL), snapshotAfterMigration)
        XCTAssertEqual(try Data(contentsOf: mismatchedStore.journalFileURL), journalAfterMigration)
    }

    func testInterruptedManualRollbackRecoversTheExactOldSavePair() async throws {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyStore = try ProgressStore(directoryURL: directory)
        try await legacyStore.checkpoint(Self.legacyState)
        _ = try await legacyStore.append(
            JourneyEvent(logicalTimeMillis: 78, action: .showWorld)
        )
        let snapshotBefore = try Data(contentsOf: legacyStore.snapshotFileURL)
        let journalBefore = try Data(contentsOf: legacyStore.journalFileURL)
        XCTAssertFalse(journalBefore.isEmpty)

        let migratingStore = try ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: SaveMigrationRegistry(steps: [Self.fullStep]),
            saveMigrationAuthorities: [Self.fullAuthority]
        )
        _ = try await migratingStore.restore()

        let interrupted = try ProgressStore(
            directoryURL: directory,
            atomicReplacementOperation: { data, url in
                if url.lastPathComponent == "journey.events", data == journalBefore {
                    throw InjectedInterruption()
                }
                try data.write(to: url, options: .atomic)
            },
            saveMigrationRegistry: SaveMigrationRegistry(steps: [Self.fullStep]),
            saveMigrationAuthorities: [Self.fullAuthority]
        )
        do {
            try await interrupted.rollbackToLastKnownGoodSave()
            XCTFail("The injected rollback interruption must escape")
        } catch {
            XCTAssertEqual(error as? ProgressStoreError, .migrationRollbackFailed)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: interrupted.migrationInFlightFileURL.path
            )
        )

        let recovering = try ProgressStore(directoryURL: directory)
        let restoration = try await recovering.restore()
        XCTAssertEqual(
            restoration.state.chapterSession(Self.chapterID)?.contentVersion,
            Self.v1
        )
        XCTAssertEqual(try Data(contentsOf: recovering.snapshotFileURL), snapshotBefore)
        XCTAssertEqual(try Data(contentsOf: recovering.journalFileURL), journalBefore)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: recovering.migrationInFlightFileURL.path
            )
        )
    }

    func testNondeterministicTransformFailsBeforeAnyStateCanPublish() throws {
        let counter = LockedCounter()
        let step = PackageSaveMigrationStep(
            packageID: Self.packageID,
            declarationID: Self.fullDeclaration.id,
            fromContentVersion: Self.v1,
            toContentVersion: Self.v2,
            canonicalTransformDescriptor: Self.fullDescriptor
        ) { state, _ in
            var candidate = state
            candidate.route = counter.nextIsOdd() ? .world : .prologue
            return candidate
        }
        let declaration = PackageSaveMigrationDeclaration(
            id: Self.fullDeclaration.id,
            fromContentVersion: Self.v1,
            toContentVersion: Self.v2,
            requiredSaveFormatVersion: SaveSnapshot.currentFormatVersion,
            requiredStateSchemaVersion: JourneyState.currentStateSchemaVersion,
            fields: [.beatIdentity],
            implementationSHA256: step.implementationSHA256
        )
        let registry = try SaveMigrationRegistry(steps: [step])
        XCTAssertThrowsError(
            try registry.migrate(
                SaveSnapshot(state: Self.legacyState),
                authorities: [Self.authority(target: Self.v2, declarations: [declaration])]
            )
        ) { error in
            XCTAssertEqual(
                error as? SaveMigrationRegistryError,
                .nondeterministicTransform(
                    packageID: Self.packageID,
                    declarationID: Self.fullDeclaration.id
                )
            )
        }
    }

    func testWorldMigrationCannotRewriteAnotherPackagesRecords() throws {
        let step = PackageSaveMigrationStep(
            packageID: Self.packageID,
            declarationID: Self.fullDeclaration.id,
            fromContentVersion: Self.v1,
            toContentVersion: Self.v2,
            canonicalTransformDescriptor: Self.fullDescriptor
        ) { state, packageID in
            var candidate = try Self.fullTransform(state, packageID)
            candidate.world = WorldGraph(
                nodes: candidate.world.nodes.filter {
                    $0.id != Self.foreignWorldNodeID
                },
                traces: candidate.world.traces,
                appliedEffects: candidate.world.appliedEffects.filter {
                    $0.id != Self.foreignWorldEffect.id
                }
            )
            return candidate
        }
        let declaration = PackageSaveMigrationDeclaration(
            id: Self.fullDeclaration.id,
            fromContentVersion: Self.v1,
            toContentVersion: Self.v2,
            requiredSaveFormatVersion: SaveSnapshot.currentFormatVersion,
            requiredStateSchemaVersion: JourneyState.currentStateSchemaVersion,
            fields: PackageSaveMigrationField.allCases.sorted {
                $0.rawValue < $1.rawValue
            },
            worldOwnershipDelta: Self.fullDeclaration.worldOwnershipDelta,
            implementationSHA256: step.implementationSHA256
        )
        let registry = try SaveMigrationRegistry(steps: [step])
        XCTAssertThrowsError(
            try registry.migrate(
                SaveSnapshot(state: Self.legacyStateWithForeignWorld),
                authorities: [Self.authority(target: Self.v2, declarations: [declaration])]
            )
        ) { error in
            XCTAssertEqual(
                error as? SaveMigrationRegistryError,
                .worldOwnershipViolation(
                    packageID: Self.packageID,
                    declarationID: Self.fullDeclaration.id,
                    recordType: "node",
                    recordID: Self.foreignWorldNodeID.rawValue
                )
            )
        }
    }

    func testPackageMigrationCarriesExactReviewRecordThroughDeclaredBeatAndAnchorMaps() throws {
        let oldContract = Self.reviewContract(
            contentVersion: Self.v1,
            beatID: "old-review-beat"
        )
        let newContract = Self.reviewContract(
            contentVersion: Self.v2,
            beatID: "new-review-beat"
        )
        let oldRecord = CompletedBeatReviewRecord(
            completionContract: oldContract,
            sceneVisualSnapshot: SceneVisualSnapshot(
                sceneID: "old-review-scene",
                deterministicTick: 12
            ),
            interaction: nil,
            cameraAnchor: 0.25,
            readingAnchor: "old-review-paragraph"
        )
        let newRecord = CompletedBeatReviewRecord(
            completionContract: newContract,
            sceneVisualSnapshot: SceneVisualSnapshot(
                sceneID: "new-review-scene",
                deterministicTick: 48
            ),
            interaction: nil,
            cameraAnchor: 0.75,
            readingAnchor: "new-review-paragraph"
        )
        let source = JourneyState(
            route: .chapter(Self.chapterID),
            activeChapter: ChapterSession(
                chapterID: Self.chapterID,
                packageID: Self.packageID,
                contentVersion: Self.v1,
                arcID: "review-arc",
                beatID: "old-review-beat",
                beatCompletionContract: oldContract,
                sceneVisualSnapshot: oldRecord.sceneVisualSnapshot,
                cameraAnchor: oldRecord.cameraAnchor,
                readingAnchor: oldRecord.readingAnchor,
                completedBeatIDs: ["old-review-beat"],
                completedBeatReviewRecords: [oldRecord]
            ),
            installedContent: [
                InstalledContentVersion(packageID: Self.packageID, version: Self.v1),
            ]
        )
        let descriptor = Data(#"{"id":"review-one-to-two","version":1}"#.utf8)
        let step = PackageSaveMigrationStep(
            packageID: Self.packageID,
            declarationID: "review-one-to-two",
            fromContentVersion: Self.v1,
            toContentVersion: Self.v2,
            canonicalTransformDescriptor: descriptor
        ) { state, packageID in
            let old = state.chapterSessions[0]
            return JourneyState(
                route: state.route,
                prologue: state.prologue,
                world: state.world,
                activeChapter: ChapterSession(
                    chapterID: old.chapterID,
                    packageID: packageID,
                    contentVersion: Self.v2,
                    arcID: "review-arc",
                    beatID: "new-review-beat",
                    beatCompletionContract: newContract,
                    sceneVisualSnapshot: newRecord.sceneVisualSnapshot,
                    cameraAnchor: newRecord.cameraAnchor,
                    readingAnchor: newRecord.readingAnchor,
                    completedBeatIDs: ["new-review-beat"],
                    completedBeatReviewRecords: [newRecord]
                ),
                completedChapterIDs: state.completedChapterIDs,
                installedContent: [
                    InstalledContentVersion(packageID: packageID, version: Self.v2),
                ],
                lastLogicalTimeMillis: state.lastLogicalTimeMillis,
                appliedEventCount: state.appliedEventCount
            )
        }
        let declaration = PackageSaveMigrationDeclaration(
            id: "review-one-to-two",
            fromContentVersion: Self.v1,
            toContentVersion: Self.v2,
            requiredSaveFormatVersion: SaveSnapshot.currentFormatVersion,
            requiredStateSchemaVersion: JourneyState.currentStateSchemaVersion,
            fields: [.beatIdentity, .cameraAndTextAnchors],
            implementationSHA256: step.implementationSHA256
        )

        let result = try SaveMigrationRegistry(steps: [step]).migrate(
            SaveSnapshot(state: source),
            authorities: [Self.authority(target: Self.v2, declarations: [declaration])]
        )

        let migrated = try XCTUnwrap(
            result.snapshot.state.chapterSession(Self.chapterID)?
                .completedBeatReviewRecords.first
        )
        XCTAssertEqual(migrated.beatID, "new-review-beat")
        XCTAssertEqual(migrated.contentVersion, Self.v2)
        XCTAssertEqual(migrated.sceneVisualSnapshot.sceneID, "new-review-scene")
        XCTAssertEqual(migrated.cameraAnchor, 0.75)
        XCTAssertEqual(migrated.readingAnchor, "new-review-paragraph")
    }

    func testPackageMigrationCannotSilentlyDiscardReviewRecords() throws {
        let contract = Self.reviewContract(
            contentVersion: Self.v1,
            beatID: "old-review-beat"
        )
        let record = CompletedBeatReviewRecord(
            completionContract: contract,
            sceneVisualSnapshot: SceneVisualSnapshot(
                sceneID: "old-review-scene",
                deterministicTick: 12
            ),
            interaction: nil,
            cameraAnchor: 0.25,
            readingAnchor: nil
        )
        let source = JourneyState(
            route: .chapter(Self.chapterID),
            activeChapter: ChapterSession(
                chapterID: Self.chapterID,
                packageID: Self.packageID,
                contentVersion: Self.v1,
                arcID: "review-arc",
                beatID: "old-review-beat",
                beatCompletionContract: contract,
                sceneVisualSnapshot: record.sceneVisualSnapshot,
                completedBeatIDs: ["old-review-beat"],
                completedBeatReviewRecords: [record]
            ),
            installedContent: [
                InstalledContentVersion(packageID: Self.packageID, version: Self.v1),
            ]
        )
        let descriptor = Data(#"{"id":"drop-review","version":1}"#.utf8)
        let step = PackageSaveMigrationStep(
            packageID: Self.packageID,
            declarationID: "drop-review",
            fromContentVersion: Self.v1,
            toContentVersion: Self.v2,
            canonicalTransformDescriptor: descriptor
        ) { state, packageID in
            let old = state.chapterSessions[0]
            return JourneyState(
                route: state.route,
                prologue: state.prologue,
                world: state.world,
                activeChapter: ChapterSession(
                    chapterID: old.chapterID,
                    packageID: packageID,
                    contentVersion: Self.v2,
                    arcID: old.arcID,
                    beatID: old.beatID,
                    beatCompletionContract: old.beatCompletionContract,
                    sceneVisualSnapshot: old.sceneVisualSnapshot,
                    completedBeatIDs: old.completedBeatIDs
                ),
                completedChapterIDs: state.completedChapterIDs,
                installedContent: [
                    InstalledContentVersion(packageID: packageID, version: Self.v2),
                ],
                lastLogicalTimeMillis: state.lastLogicalTimeMillis,
                appliedEventCount: state.appliedEventCount
            )
        }
        let declaration = PackageSaveMigrationDeclaration(
            id: "drop-review",
            fromContentVersion: Self.v1,
            toContentVersion: Self.v2,
            requiredSaveFormatVersion: SaveSnapshot.currentFormatVersion,
            requiredStateSchemaVersion: JourneyState.currentStateSchemaVersion,
            fields: PackageSaveMigrationField.allCases,
            implementationSHA256: step.implementationSHA256
        )
        let registry = try SaveMigrationRegistry(steps: [step])

        XCTAssertThrowsError(
            try registry.migrate(
                SaveSnapshot(state: source),
                authorities: [Self.authority(target: Self.v2, declarations: [declaration])]
            )
        ) { error in
            XCTAssertEqual(
                error as? SaveMigrationRegistryError,
                .identityOrAuthorityMutation(
                    packageID: Self.packageID,
                    declarationID: "drop-review"
                )
            )
        }
    }

    private func assertFullyMigrated(
        _ state: JourneyState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let session = state.chapterSession(Self.chapterID)
        XCTAssertEqual(session?.contentVersion, Self.v2, file: file, line: line)
        XCTAssertEqual(session?.arcID, "new-arc", file: file, line: line)
        XCTAssertEqual(session?.beatID, "new-beat", file: file, line: line)
        XCTAssertEqual(session?.interaction?.interactionID, "new-interaction", file: file, line: line)
        XCTAssertEqual(session?.cameraAnchor, 0.875, file: file, line: line)
        XCTAssertEqual(session?.readingAnchor, "new-text-anchor", file: file, line: line)
        XCTAssertEqual(session?.narration.cueID, "new-cue", file: file, line: line)
        XCTAssertEqual(session?.narration.sampleOffset, 48_000, file: file, line: line)
        XCTAssertEqual(session?.responsiveAudioSnapshot?.cursorSample, 96_000, file: file, line: line)
        XCTAssertEqual(state.world.appliedEffectIDs, [Self.migratedWorldEffect.id], file: file, line: line)
        XCTAssertEqual(state.installedContent, [
            InstalledContentVersion(packageID: Self.packageID, version: Self.v2),
        ], file: file, line: line)
    }

    private static let packageID: PackageID = "migration-test-pack"
    private static let chapterID: ChapterID = "migration-test-chapter"
    private static let v1 = SchemaVersion(major: 1)
    private static let v2 = SchemaVersion(major: 2)
    private static let v3 = SchemaVersion(major: 3)
    private static let fullDescriptor = Data(
        #"{"id":"full-one-to-two","operations":["beat-map","interaction-map","anchor-map","audio-map","world-replay"],"version":1}"#.utf8
    )

    private static let migratedWorldEffect = WorldEffect(
        id: "migration-world-effect",
        mutation: .revealNode(
            WorldNodeBlueprint(
                id: "migration-world-node",
                kind: .settlement,
                form: "migrated-form",
                position: NormalizedPoint(x: 0.4, y: 0.6)
            )
        )
    )

    private static let foreignWorldNodeID: WorldNodeID = "foreign-world-node"
    private static let foreignWorldEffect = WorldEffect(
        id: "foreign-world-effect",
        mutation: .revealNode(
            WorldNodeBlueprint(
                id: foreignWorldNodeID,
                kind: .settlement,
                form: "foreign-form",
                position: NormalizedPoint(x: 0.2, y: 0.8)
            )
        )
    )

    private static let interactionSpec = InteractionSpec(
        id: "new-interaction",
        prompt: "Move the saved mechanism",
        grammar: .transform(
            TransformInteractionSpec(
                stages: [
                    TransformationStage(
                        id: "migration-stage",
                        controlID: "migration-control",
                        requiredAmount: 1
                    ),
                ]
            )
        ),
        completionEffects: [],
        accessibilityID: "new-interaction-accessibility"
    )

    private static let legacyState = JourneyState(
        route: .chapter(chapterID),
        activeChapter: ChapterSession(
            chapterID: chapterID,
            packageID: packageID,
            contentVersion: v1,
            arcID: "old-arc",
            beatID: "old-beat",
            sceneVisualSnapshot: SceneVisualSnapshot(
                sceneID: "old-scene",
                deterministicTick: 12
            ),
            cameraAnchor: 0.125,
            readingAnchor: "old-text-anchor",
            narration: NarrationCursor(
                cueID: "old-cue",
                sampleOffset: 12_000,
                isEnabled: true,
                isPlaying: false
            ),
            completedBeatIDs: ["old-completed-beat"],
            completedArcIDs: ["old-completed-arc"],
            lastVisitedAtEpochMillis: 123_456
        ),
        installedContent: [
            InstalledContentVersion(packageID: packageID, version: v1),
        ],
        lastLogicalTimeMillis: 77,
        appliedEventCount: 9
    )

    private static let legacyStateWithForeignWorld: JourneyState = {
        var state = legacyState
        try! state.world.apply(foreignWorldEffect)
        return state
    }()

    private static let fullTransform: PackageSaveMigrationStep.Transform = { state, packageID in
        var interaction = InteractionRuntimeState(spec: interactionSpec)
        interaction.phase = .active
        var world = state.world
        try world.apply(migratedWorldEffect)
        let sessions = state.chapterSessions.map { old -> ChapterSession in
            guard old.packageID == packageID else { return old }
            return ChapterSession(
                chapterID: old.chapterID,
                packageID: old.packageID,
                contentVersion: v2,
                arcID: "new-arc",
                beatID: "new-beat",
                sceneVisualSnapshot: SceneVisualSnapshot(
                    sceneID: "new-scene",
                    deterministicTick: 48
                ),
                interaction: interaction,
                responsiveAudioSnapshot: ResponsiveAudioProgramSnapshot(
                    programID: "new-audio-program",
                    stage: .interaction,
                    interactionPhase: .engaged,
                    timelineID: "new-audio-timeline",
                    cursorSample: 96_000,
                    loopIteration: 3,
                    durableCompletionSequence: nil
                ),
                cameraAnchor: 0.875,
                readingAnchor: "new-text-anchor",
                narration: NarrationCursor(
                    cueID: "new-cue",
                    sampleOffset: 48_000,
                    isEnabled: true,
                    isPlaying: false
                ),
                completedBeatIDs: ["new-completed-beat"],
                completedArcIDs: ["new-completed-arc"],
                lastVisitedAtEpochMillis: old.lastVisitedAtEpochMillis
            )
        }
        let installed = state.installedContent.map { old in
            old.packageID == packageID
                ? InstalledContentVersion(packageID: old.packageID, version: v2)
                : old
        }
        return JourneyState(
            route: state.route,
            prologue: state.prologue,
            world: world,
            chapterSessions: sessions,
            completedChapterIDs: state.completedChapterIDs,
            installedContent: installed,
            lastLogicalTimeMillis: state.lastLogicalTimeMillis,
            appliedEventCount: state.appliedEventCount
        )
    }

    private static let fullStep = PackageSaveMigrationStep(
        packageID: packageID,
        declarationID: "full-one-to-two",
        fromContentVersion: v1,
        toContentVersion: v2,
        canonicalTransformDescriptor: fullDescriptor,
        transform: fullTransform
    )

    private static let fullDeclaration = PackageSaveMigrationDeclaration(
        id: "full-one-to-two",
        fromContentVersion: v1,
        toContentVersion: v2,
        requiredSaveFormatVersion: SaveSnapshot.currentFormatVersion,
        requiredStateSchemaVersion: JourneyState.currentStateSchemaVersion,
        fields: PackageSaveMigrationField.allCases.sorted {
            $0.rawValue.utf8.lexicographicallyPrecedes($1.rawValue.utf8)
        },
        worldOwnershipDelta: PackageSaveMigrationWorldOwnershipDelta(
            newEffectIDs: [migratedWorldEffect.id],
            newNodeIDs: ["migration-world-node"]
        ),
        implementationSHA256: fullStep.implementationSHA256
    )

    private static let fullAuthority = authority(
        target: v2,
        declarations: [fullDeclaration]
    )

    private static func declaration(
        id: String,
        from: SchemaVersion,
        to: SchemaVersion,
        fields: [PackageSaveMigrationField] = [.beatIdentity]
    ) -> PackageSaveMigrationDeclaration {
        PackageSaveMigrationDeclaration(
            id: id,
            fromContentVersion: from,
            toContentVersion: to,
            requiredSaveFormatVersion: SaveSnapshot.currentFormatVersion,
            requiredStateSchemaVersion: JourneyState.currentStateSchemaVersion,
            fields: fields,
            implementationSHA256: String(repeating: "a", count: 64)
        )
    }

    private static func authority(
        target: SchemaVersion,
        declarations: [PackageSaveMigrationDeclaration]
    ) -> VerifiedPackageSaveMigrationAuthority {
        VerifiedPackageSaveMigrationAuthority(
            packageID: packageID,
            targetContentVersion: target,
            manifestDigest: String(repeating: "b", count: 64),
            activeGeneration: ActiveSaveMigrationPackageGeneration(
                generationID: "migration-test-generation-\(target)",
                packageID: packageID,
                packageVersion: target,
                manifestDigest: String(repeating: "b", count: 64),
                activationSequence: 1
            ),
            declarations: declarations
        )
    }

    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static let canonicalEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static func reviewContract(
        contentVersion: SchemaVersion,
        beatID: BeatID
    ) -> BeatCompletionContract {
        BeatCompletionContract(
            packageID: packageID,
            contentVersion: contentVersion,
            chapterID: chapterID,
            arcID: "review-arc",
            beatID: beatID,
            arcIndex: 0,
            beatIndex: 0,
            absoluteBeatIndex: 0,
            mode: .documentary(effects: [])
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct InjectedInterruption: Error {}

    private final class LockedCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func nextIsOdd() -> Bool {
            lock.withLock {
                value += 1
                return value.isMultiple(of: 2) == false
            }
        }
    }
}
