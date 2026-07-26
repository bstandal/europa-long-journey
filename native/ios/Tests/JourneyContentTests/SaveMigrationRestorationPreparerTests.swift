import ContentKit
import Foundation
@testable import JourneyDomain
import JourneyPersistence
@testable import ProgressStore
import XCTest

final class SaveMigrationRestorationPreparerTests: XCTestCase {
    func testMutationBarrierKeepsAuthorityRestoreClosedUntilEveryWriterFinishes() {
        var barrier = JourneyPersistenceMutationBarrier()
        let actionDrain = try! XCTUnwrap(barrier.begin())
        let chapterSceneCommit = try! XCTUnwrap(barrier.begin())
        let admittedGeneration = barrier.generation

        XCTAssertTrue(barrier.hasActiveMutations)
        XCTAssertEqual(barrier.activeMutationCount, 2)
        XCTAssertTrue(barrier.finish(actionDrain))
        XCTAssertTrue(barrier.hasActiveMutations)
        XCTAssertEqual(barrier.activeMutationCount, 1)
        XCTAssertTrue(barrier.finish(chapterSceneCommit))
        XCTAssertFalse(barrier.hasActiveMutations)

        let laterWriter = try! XCTUnwrap(barrier.begin())
        XCTAssertGreaterThan(barrier.generation, admittedGeneration)
        XCTAssertFalse(barrier.finish(actionDrain))
        XCTAssertTrue(barrier.finish(laterWriter))
        XCTAssertFalse(barrier.hasActiveMutations)
    }

    func testSnapshotRevisionPolicyRejectsEqualAndOutOfOrderContinuations() {
        XCTAssertTrue(VerifiedSnapshotRevisionPolicy.admits(
            candidate: 7,
            after: nil
        ))
        XCTAssertTrue(VerifiedSnapshotRevisionPolicy.admits(
            candidate: 8,
            after: 7
        ))
        XCTAssertFalse(VerifiedSnapshotRevisionPolicy.admits(
            candidate: 7,
            after: 7
        ))
        XCTAssertFalse(VerifiedSnapshotRevisionPolicy.admits(
            candidate: 6,
            after: 7
        ))
    }

    func testRestoreInternalMutationRequiresTheLockedAuthorityRestoreWindow() {
        var barrier = JourneyPersistenceMutationBarrier()

        XCTAssertNil(barrier.beginRestoreInternal(
            authorityRestoreIsInFlight: false,
            persistenceIsLocked: true
        ))
        XCTAssertNil(barrier.beginRestoreInternal(
            authorityRestoreIsInFlight: true,
            persistenceIsLocked: false
        ))
        XCTAssertNil(barrier.beginRestoreInternal(
            authorityRestoreIsInFlight: false,
            persistenceIsLocked: false
        ))
        XCTAssertEqual(barrier.generation, 0)
        XCTAssertEqual(barrier.activeMutationCount, 0)

        let fallback = try! XCTUnwrap(barrier.beginRestoreInternal(
            authorityRestoreIsInFlight: true,
            persistenceIsLocked: true
        ))
        XCTAssertEqual(barrier.generation, 1)
        XCTAssertEqual(barrier.activeMutationCount, 1)
        XCTAssertTrue(barrier.hasActiveMutations)
        XCTAssertTrue(barrier.finish(fallback))
        XCTAssertEqual(barrier.generation, 1)
        XCTAssertEqual(barrier.activeMutationCount, 0)
        XCTAssertFalse(barrier.hasActiveMutations)

        let ordinary = try! XCTUnwrap(barrier.begin())
        XCTAssertNil(barrier.beginRestoreInternal(
            authorityRestoreIsInFlight: true,
            persistenceIsLocked: true
        ))
        XCTAssertEqual(barrier.generation, 2)
        XCTAssertEqual(barrier.activeMutationCount, 1)
        XCTAssertTrue(barrier.finish(ordinary))
    }

    func testAuthorityTransitionStartRequiresLockedRestorationWindow() {
        XCTAssertTrue(
            JourneyAuthorityTransitionStartAdmissionPolicy.admits(
                persistenceIsLocked: true,
                restorationIsInFlight: true,
                authorityPreparationIsInFlight: false,
                authorityTransitionIsInFlight: false,
                authorityRestoreIsInFlight: false,
                persistenceMutationIsInFlight: false
            )
        )
        XCTAssertFalse(
            JourneyAuthorityTransitionStartAdmissionPolicy.admits(
                persistenceIsLocked: false,
                restorationIsInFlight: false,
                authorityPreparationIsInFlight: false,
                authorityTransitionIsInFlight: false,
                authorityRestoreIsInFlight: false,
                persistenceMutationIsInFlight: false
            )
        )
    }

    func testAuthorityTransitionStartRejectsEveryConflictingState() {
        let rejected: [(String, Bool)] = [
            (
                "unlocked",
                JourneyAuthorityTransitionStartAdmissionPolicy.admits(
                    persistenceIsLocked: false,
                    restorationIsInFlight: true,
                    authorityPreparationIsInFlight: false,
                    authorityTransitionIsInFlight: false,
                    authorityRestoreIsInFlight: false,
                    persistenceMutationIsInFlight: false
                )
            ),
            (
                "not-restoring",
                JourneyAuthorityTransitionStartAdmissionPolicy.admits(
                    persistenceIsLocked: true,
                    restorationIsInFlight: false,
                    authorityPreparationIsInFlight: false,
                    authorityTransitionIsInFlight: false,
                    authorityRestoreIsInFlight: false,
                    persistenceMutationIsInFlight: false
                )
            ),
            (
                "preparing",
                JourneyAuthorityTransitionStartAdmissionPolicy.admits(
                    persistenceIsLocked: true,
                    restorationIsInFlight: true,
                    authorityPreparationIsInFlight: true,
                    authorityTransitionIsInFlight: false,
                    authorityRestoreIsInFlight: false,
                    persistenceMutationIsInFlight: false
                )
            ),
            (
                "transitioning",
                JourneyAuthorityTransitionStartAdmissionPolicy.admits(
                    persistenceIsLocked: true,
                    restorationIsInFlight: true,
                    authorityPreparationIsInFlight: false,
                    authorityTransitionIsInFlight: true,
                    authorityRestoreIsInFlight: false,
                    persistenceMutationIsInFlight: false
                )
            ),
            (
                "restoring-authority",
                JourneyAuthorityTransitionStartAdmissionPolicy.admits(
                    persistenceIsLocked: true,
                    restorationIsInFlight: true,
                    authorityPreparationIsInFlight: false,
                    authorityTransitionIsInFlight: false,
                    authorityRestoreIsInFlight: true,
                    persistenceMutationIsInFlight: false
                )
            ),
            (
                "writer",
                JourneyAuthorityTransitionStartAdmissionPolicy.admits(
                    persistenceIsLocked: true,
                    restorationIsInFlight: true,
                    authorityPreparationIsInFlight: false,
                    authorityTransitionIsInFlight: false,
                    authorityRestoreIsInFlight: false,
                    persistenceMutationIsInFlight: true
                )
            ),
        ]

        for (name, admitted) in rejected {
            XCTAssertFalse(admitted, name)
        }
    }

    func testIdentityDriftRollsBackCompletedV2BeforeV3FailureAndOldAuthorityRestoresExactPair()
        async throws
    {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let legacyStore = try ProgressStore(directoryURL: directory)
        try await legacyStore.checkpoint(Self.v1State)
        _ = try await legacyStore.append(JourneyEvent(
            logicalTimeMillis: 43,
            action: .showWorld
        ))
        let expected = try await ProgressStore(
            directoryURL: directory
        ).restore().state
        let snapshotBefore = try Data(
            contentsOf: legacyStore.snapshotFileURL
        )
        let journalBefore = try Data(
            contentsOf: legacyStore.journalFileURL
        )

        let v2Store = try ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: try SaveMigrationRegistry(
                steps: [Self.v1ToV2Step]
            ),
            saveMigrationAuthorities: [Self.v2Authority]
        )
        let prepared = try await SaveMigrationRestorationPreparer.prepare(
            store: v2Store
        ) {
            try await v2Store.restore()
        }
        XCTAssertTrue(prepared.committedSaveMigration)
        XCTAssertEqual(
            prepared.restoration.state.chapterSession(Self.chapterID)?
                .contentVersion,
            Self.v2
        )

        // The desired package identity changes before the prepared v2 state
        // is accepted. Discarding it must first restore the v1 save pair under
        // the still-active v2 migration authority.
        try await prepared.rollbackCommittedSaveMigrationIfNeeded()
        XCTAssertEqual(
            try Data(contentsOf: legacyStore.snapshotFileURL),
            snapshotBefore
        )
        XCTAssertEqual(
            try Data(contentsOf: legacyStore.journalFileURL),
            journalBefore
        )

        let v3Store = try ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: .empty,
            saveMigrationAuthorities: [Self.v3AuthorityWithoutV1Path]
        )
        do {
            _ = try await v3Store.restore()
            XCTFail("v1 cannot open through a v2-to-v3-only declaration")
        } catch {
            XCTAssertEqual(
                error as? SaveMigrationRegistryError,
                .unknownPath(
                    packageID: Self.packageID,
                    from: Self.v1,
                    to: Self.v3
                )
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: legacyStore.snapshotFileURL),
            snapshotBefore
        )
        XCTAssertEqual(
            try Data(contentsOf: legacyStore.journalFileURL),
            journalBefore
        )

        let revertedPackageStore = try ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: .empty,
            saveMigrationAuthorities: [Self.v1Authority]
        )
        let restored = try await revertedPackageStore.restore()
        XCTAssertEqual(restored.state, expected)
        XCTAssertEqual(
            restored.state.chapterSession(Self.chapterID)?.contentVersion,
            Self.v1
        )
        XCTAssertEqual(
            try Data(contentsOf: legacyStore.snapshotFileURL),
            snapshotBefore
        )
        XCTAssertEqual(
            try Data(contentsOf: legacyStore.journalFileURL),
            journalBefore
        )
    }

    func testOwnershipFallbackStaysDeferredUntilMigratedAuthorityIsAccepted()
        async throws
    {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = try ProgressStore(directoryURL: directory)
        try await legacy.checkpoint(Self.v1State)
        let snapshotBefore = try Data(contentsOf: legacy.snapshotFileURL)
        let journalBefore = try Data(contentsOf: legacy.journalFileURL)
        let registry = try SaveMigrationRegistry(steps: [Self.v1ToV2Step])

        let supersededStore = try ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: registry,
            saveMigrationAuthorities: [Self.v2Authority]
        )
        let superseded = try await SaveMigrationRestorationPreparer.prepare(
            store: supersededStore
        ) {
            try await supersededStore.restore()
        }
        XCTAssertEqual(
            superseded.restoration.state.route,
            .chapter(Self.chapterID)
        )

        // A newer snapshot arrives before acceptance. No ownership fallback
        // has touched the migrated pair, so the exact authority-bound rollback
        // remains usable.
        try await superseded.rollbackCommittedSaveMigrationIfNeeded()
        XCTAssertEqual(
            try Data(contentsOf: legacy.snapshotFileURL),
            snapshotBefore
        )
        XCTAssertEqual(
            try Data(contentsOf: legacy.journalFileURL),
            journalBefore
        )

        let acceptedStore = try ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: registry,
            saveMigrationAuthorities: [Self.v2Authority]
        )
        let accepted = try await SaveMigrationRestorationPreparer.prepare(
            store: acceptedStore
        ) {
            try await acceptedStore.restore()
        }
        XCTAssertTrue(accepted.committedSaveMigration)
        _ = try await accepted.store.append(JourneyEvent(
            logicalTimeMillis: 43,
            action: .showWorld
        ))
        let afterFallback = try await ProgressStore(
            directoryURL: directory,
            saveMigrationRegistry: registry,
            saveMigrationAuthorities: [Self.v2Authority]
        ).restore()
        XCTAssertEqual(afterFallback.state.route, .world)
        XCTAssertEqual(
            afterFallback.state.chapterSession(Self.chapterID)?.contentVersion,
            Self.v2
        )
    }

    private static let packageID: PackageID = "drift-test-package"
    private static let chapterID: ChapterID = "drift-test-chapter"
    private static let v1 = SchemaVersion(major: 1)
    private static let v2 = SchemaVersion(major: 2)
    private static let v3 = SchemaVersion(major: 3)
    private static let descriptor = Data(
        #"{"id":"drift-one-to-two","operation":"beat-map","version":1}"#.utf8
    )

    private static let v1State = JourneyState(
        route: .chapter(chapterID),
        activeChapter: ChapterSession(
            chapterID: chapterID,
            packageID: packageID,
            contentVersion: v1,
            arcID: "drift-arc",
            beatID: "v1-beat"
        ),
        installedContent: [
            InstalledContentVersion(packageID: packageID, version: v1),
        ],
        lastLogicalTimeMillis: 42
    )

    private static let v1ToV2Step = PackageSaveMigrationStep(
        packageID: packageID,
        declarationID: "drift-one-to-two",
        fromContentVersion: v1,
        toContentVersion: v2,
        canonicalTransformDescriptor: descriptor
    ) { state, packageID in
        let sessions = state.chapterSessions.map { session in
            guard session.packageID == packageID else { return session }
            return ChapterSession(
                chapterID: session.chapterID,
                packageID: session.packageID,
                contentVersion: v2,
                arcID: session.arcID,
                beatID: "v2-beat",
                beatCompletionContract: session.beatCompletionContract,
                sceneVisualSnapshot: session.sceneVisualSnapshot,
                interaction: session.interaction,
                responsiveAudioSnapshot: session.responsiveAudioSnapshot,
                cameraAnchor: session.cameraAnchor,
                readingAnchor: session.readingAnchor,
                narration: session.narration,
                completedBeatIDs: session.completedBeatIDs,
                completedArcIDs: session.completedArcIDs,
                lastVisitedAtEpochMillis: session.lastVisitedAtEpochMillis
            )
        }
        let installed = state.installedContent.map { item in
            item.packageID == packageID
                ? InstalledContentVersion(packageID: packageID, version: v2)
                : item
        }
        return JourneyState(
            route: state.route,
            prologue: state.prologue,
            world: state.world,
            chapterSessions: sessions,
            completedChapterIDs: state.completedChapterIDs,
            installedContent: installed,
            lastLogicalTimeMillis: state.lastLogicalTimeMillis,
            appliedEventCount: state.appliedEventCount
        )
    }

    private static let v1ToV2Declaration = PackageSaveMigrationDeclaration(
        id: "drift-one-to-two",
        fromContentVersion: v1,
        toContentVersion: v2,
        requiredSaveFormatVersion: SaveSnapshot.currentFormatVersion,
        requiredStateSchemaVersion: JourneyState.currentStateSchemaVersion,
        fields: [.beatIdentity],
        implementationSHA256: v1ToV2Step.implementationSHA256
    )

    private static let v1Authority = authority(
        target: v1,
        generation: "drift-v1",
        declarations: []
    )
    private static let v2Authority = authority(
        target: v2,
        generation: "drift-v2",
        declarations: [v1ToV2Declaration]
    )
    private static let v3AuthorityWithoutV1Path = authority(
        target: v3,
        generation: "drift-v3",
        declarations: [
            PackageSaveMigrationDeclaration(
                id: "drift-two-to-three",
                fromContentVersion: v2,
                toContentVersion: v3,
                requiredSaveFormatVersion: SaveSnapshot.currentFormatVersion,
                requiredStateSchemaVersion:
                    JourneyState.currentStateSchemaVersion,
                fields: [.beatIdentity],
                implementationSHA256: String(repeating: "c", count: 64)
            ),
        ]
    )

    private static func authority(
        target: SchemaVersion,
        generation: String,
        declarations: [PackageSaveMigrationDeclaration]
    ) -> VerifiedPackageSaveMigrationAuthority {
        let digest = String(repeating: "b", count: 64)
        return VerifiedPackageSaveMigrationAuthority(
            packageID: packageID,
            targetContentVersion: target,
            manifestDigest: digest,
            activeGeneration: ActiveSaveMigrationPackageGeneration(
                generationID: generation,
                packageID: packageID,
                packageVersion: target,
                manifestDigest: digest,
                activationSequence: UInt64(target.major)
            ),
            declarations: declarations
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "save-migration-drift-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try! FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}
