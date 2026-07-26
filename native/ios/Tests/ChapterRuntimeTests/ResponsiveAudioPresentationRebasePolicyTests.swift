@testable import ChapterRuntime
import ContentKit
import Foundation
import JourneyDomain
import SceneRuntime
import XCTest

final class ResponsiveAudioPresentationRebasePolicyTests: XCTestCase {
    func testIdenticalStateIsAnExplicitNoOp() throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }

        XCTAssertEqual(
            ResponsiveAudioPresentationRebasePolicy.decide(
                published: fixture.state,
                committed: fixture.state
            ),
            .unchanged
        )
    }

    func testReducerProducedBeginSnapshotAndEndAreTheOnlyForwardRebases() throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let waiting = try audioSnapshot(in: fixture, cursorSample: 0)
        let begun = try reducing(
            .beginResponsiveAudioSession(
                chapterOpenNonce: UUID(),
                generation: 1,
                snapshot: waiting
            ),
            from: fixture.state
        )
        XCTAssertEqual(decision(fixture.state, begun), .rebase)

        let movedSnapshot = try audioSnapshot(in: fixture, cursorSample: 480)
        let moved = try reducing(
            .setResponsiveAudioSnapshot(movedSnapshot),
            from: begun
        )
        XCTAssertEqual(decision(begun, moved), .rebase)

        let endedSnapshot = try audioSnapshot(in: fixture, cursorSample: 960)
        let ended = try reducing(
            .endResponsiveAudioSession(endedSnapshot),
            from: moved
        )
        XCTAssertEqual(decision(moved, ended), .rebase)
        XCTAssertEqual(
            decision(fixture.state, moved),
            .rebase,
            "Several consecutive audio-only commits may be adopted together"
        )
    }

    func testEveryNonAudioAuthorityClassRejectsTheRebase() throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let waiting = try audioSnapshot(in: fixture, cursorSample: 0)
        let source = try reducing(
            .beginResponsiveAudioSession(
                chapterOpenNonce: UUID(),
                generation: 1,
                snapshot: waiting
            ),
            from: fixture.state
        )
        let otherVersion = SchemaVersion(major: 2)
        let cases: [(String, (inout JourneyState) throws -> Void)] = [
            ("route", { $0.route = .world }),
            ("active chapter", { state in
                let other = ChapterSession(
                    chapterID: "other-chapter",
                    packageID: "other-package",
                    contentVersion: otherVersion
                )
                state.route = .chapter(other.chapterID)
                state.activeChapter = other
            }),
            ("package", { state in
                let session = try XCTUnwrap(state.activeChapter)
                state.activeChapter = self.copySession(
                    session,
                    packageID: "other-package"
                )
            }),
            ("content version", { state in
                let session = try XCTUnwrap(state.activeChapter)
                state.activeChapter = self.copySession(
                    session,
                    contentVersion: otherVersion
                )
            }),
            ("arc", { state in
                var session = try XCTUnwrap(state.activeChapter)
                session.arcID = "other-arc"
                state.activeChapter = session
            }),
            ("beat", { state in
                var session = try XCTUnwrap(state.activeChapter)
                session.beatID = "other-beat"
                state.activeChapter = session
            }),
            ("beat completion contract", { state in
                var session = try XCTUnwrap(state.activeChapter)
                session.beatCompletionContract = nil
                state.activeChapter = session
            }),
            ("scene snapshot", { state in
                var session = try XCTUnwrap(state.activeChapter)
                let snapshot = try XCTUnwrap(session.sceneVisualSnapshot)
                session.sceneVisualSnapshot = SceneVisualSnapshot(
                    sceneID: snapshot.sceneID,
                    deterministicTick: snapshot.deterministicTick + 1
                )
                state.activeChapter = session
            }),
            ("interaction phase", { state in
                var session = try XCTUnwrap(state.activeChapter)
                var interaction = try XCTUnwrap(session.interaction)
                interaction.phase = interaction.phase == .active ? .ready : .active
                session.interaction = interaction
                state.activeChapter = session
            }),
            ("interaction progress", { state in
                var session = try XCTUnwrap(state.activeChapter)
                var interaction = try XCTUnwrap(session.interaction)
                interaction.progress = .trace(
                    TraceProgress(
                        reachedAnchorCount: 1,
                        lastPoint: NormalizedPoint(x: 0.36, y: 0.5)
                    )
                )
                session.interaction = interaction
                state.activeChapter = session
            }),
            ("world", { state in
                try state.world.applyAtomically(fixture.interaction.completionEffects)
            }),
            ("camera", { state in
                var session = try XCTUnwrap(state.activeChapter)
                session.cameraAnchor = 0.75
                state.activeChapter = session
            }),
            ("reading", { state in
                var session = try XCTUnwrap(state.activeChapter)
                session.readingAnchor = "paragraph-2"
                state.activeChapter = session
            }),
            ("narration", { state in
                var session = try XCTUnwrap(state.activeChapter)
                session.narration = NarrationCursor(
                    cueID: "narration-cue",
                    sampleOffset: 240,
                    isEnabled: true,
                    isPlaying: true
                )
                state.activeChapter = session
            }),
            ("completed beat", { state in
                var session = try XCTUnwrap(state.activeChapter)
                session.completedBeatIDs.append("completed-beat")
                state.activeChapter = session
            }),
            ("completed arc", { state in
                var session = try XCTUnwrap(state.activeChapter)
                session.completedArcIDs.append("completed-arc")
                state.activeChapter = session
            }),
            ("completed chapter", { state in
                state.completedChapterIDs.append("completed-chapter")
            }),
            ("installed content", { state in
                state.installedContent.append(
                    InstalledContentVersion(
                        packageID: "other-package",
                        version: otherVersion
                    )
                )
            }),
            ("last visit", { state in
                var session = try XCTUnwrap(state.activeChapter)
                session.lastVisitedAtEpochMillis = 42
                state.activeChapter = session
            }),
            ("prologue", { state in
                state.prologue = PrologueState(
                    phase: .tracing,
                    traceProgress: 0.5
                )
            }),
            ("inactive chapter audio", { state in
                state.chapterSessions.append(
                    ChapterSession(
                        chapterID: "inactive-chapter",
                        packageID: "inactive-package",
                        contentVersion: otherVersion,
                        responsiveAudioSnapshot: waiting,
                        responsiveAudioChapterOpenNonce: UUID(),
                        responsiveAudioSessionGeneration: 1,
                        responsiveAudioSessionIsActive: true
                    )
                )
                state.chapterSessions.sort { $0.chapterID < $1.chapterID }
            }),
        ]

        for (name, mutation) in cases {
            var target = source
            try mutation(&target)
            target.lastLogicalTimeMillis += 1
            target.appliedEventCount += 1
            XCTAssertNotEqual(target, source, name)
            XCTAssertEqual(
                decision(source, target),
                .reject,
                "A change to \(name) cannot enter through the audio seam"
            )
        }
    }

    func testUnequalAudioStateRequiresBothCountersToAdvanceStrictly() throws {
        let fixture = try RuntimeTestFixture.trace()
        defer { try? FileManager.default.removeItem(at: fixture.packageRoot) }
        let begun = try reducing(
            .beginResponsiveAudioSession(
                chapterOpenNonce: UUID(),
                generation: 1,
                snapshot: try audioSnapshot(in: fixture, cursorSample: 0)
            ),
            from: fixture.state
        )

        var noLogicalAdvance = begun
        noLogicalAdvance.lastLogicalTimeMillis = fixture.state.lastLogicalTimeMillis
        XCTAssertEqual(decision(fixture.state, noLogicalAdvance), .reject)

        var noEventAdvance = begun
        noEventAdvance.appliedEventCount = fixture.state.appliedEventCount
        XCTAssertEqual(decision(fixture.state, noEventAdvance), .reject)

        var regressed = begun
        regressed.lastLogicalTimeMillis = fixture.state.lastLogicalTimeMillis - 1
        regressed.appliedEventCount = fixture.state.appliedEventCount - 1
        XCTAssertEqual(decision(fixture.state, regressed), .reject)
    }

    private func decision(
        _ published: JourneyState,
        _ committed: JourneyState
    ) -> ResponsiveAudioPresentationRebaseDecision {
        ResponsiveAudioPresentationRebasePolicy.decide(
            published: published,
            committed: committed
        )
    }

    private func reducing(
        _ action: JourneyAction,
        from state: JourneyState
    ) throws -> JourneyState {
        var candidate = state
        let effects = JourneyReducer().reduce(
            state: &candidate,
            event: JourneyEvent(
                logicalTimeMillis: state.lastLogicalTimeMillis + 1,
                action: action
            )
        )
        XCTAssertFalse(
            effects.contains { effect in
                if case .rejected = effect { return true }
                return false
            }
        )
        return candidate
    }

    private func audioSnapshot(
        in fixture: RuntimeTestFixture,
        cursorSample: Int64
    ) throws -> ResponsiveAudioProgramSnapshot {
        let program = fixture.repository.program
        let waiting = try XCTUnwrap(program.interactionBed(for: .waiting))
        return ResponsiveAudioProgramSnapshot(
            programID: program.id,
            stage: .interaction,
            interactionPhase: .waiting,
            timelineID: waiting.timelineID,
            cursorSample: cursorSample,
            loopIteration: 0,
            durableCompletionSequence: nil
        )
    }

    private func copySession(
        _ source: ChapterSession,
        chapterID: ChapterID? = nil,
        packageID: PackageID? = nil,
        contentVersion: SchemaVersion? = nil
    ) -> ChapterSession {
        ChapterSession(
            chapterID: chapterID ?? source.chapterID,
            packageID: packageID ?? source.packageID,
            contentVersion: contentVersion ?? source.contentVersion,
            arcID: source.arcID,
            beatID: source.beatID,
            beatCompletionContract: source.beatCompletionContract,
            sceneVisualSnapshot: source.sceneVisualSnapshot,
            interaction: source.interaction,
            responsiveAudioSnapshot: source.responsiveAudioSnapshot,
            responsiveAudioChapterOpenNonce:
                source.responsiveAudioChapterOpenNonce,
            responsiveAudioSessionGeneration:
                source.responsiveAudioSessionGeneration,
            responsiveAudioSessionIsActive:
                source.responsiveAudioSessionIsActive,
            cameraAnchor: source.cameraAnchor,
            readingAnchor: source.readingAnchor,
            narration: source.narration,
            completedBeatIDs: source.completedBeatIDs,
            completedArcIDs: source.completedArcIDs,
            lastVisitedAtEpochMillis: source.lastVisitedAtEpochMillis
        )
    }
}
