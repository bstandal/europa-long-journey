import ContentKit
import JourneyDomain
import SceneRuntime
import XCTest

final class HarvestAllocationLabTests: XCTestCase {
    func testDraftIsDebugOnlyAndCannotClaimApprovalOrShipping() throws {
        XCTAssertEqual(
            HarvestAllocationLabStatus.editorialStatus,
            "DRAFT_AWAITING_EDITOR_APPROVAL"
        )
        XCTAssertEqual(HarvestAllocationLabStatus.shippingState, "PROHIBITED")

        let spec = try HarvestAllocationLabSpec.harvestDraftV1()
        XCTAssertEqual(spec.totalUnits, 12)
        XCTAssertEqual(spec.minimumUnits, 9)
        XCTAssertEqual(spec.surplusUnits, 3)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: spec.destinations.map {
                ($0.destinationID, $0.minimumUnits)
            }),
            ["food": 4, "reserve": 2, "seed": 3]
        )
        XCTAssertEqual(
            spec.completionEffects.map(\.id),
            [WorldEffectID("effect-first-farmers-the-harvest-had-to-last")]
        )
    }

    func testEverySurplusDistributionCompletesWithOneSharedHistoricalEffect() throws {
        let spec = try HarvestAllocationLabSpec.harvestDraftV1()
        var completedDistributions = Set<String>()

        for foodSurplus in 0 ... 3 {
            for reserveSurplus in 0 ... (3 - foodSurplus) {
                let seedSurplus = 3 - foodSurplus - reserveSurplus
                var driver = try HarvestAllocationLabDriver(spec: spec)
                _ = try driver.submit(
                    .touch(.set(destinationID: "food", units: 4 + foodSurplus))
                )
                _ = try driver.submit(
                    .touch(.set(destinationID: "reserve", units: 2 + reserveSurplus))
                )
                _ = try driver.submit(
                    .touch(.set(destinationID: "seed", units: 3 + seedSurplus))
                )

                let completion = try driver.submit(.touch(.commit))
                XCTAssertEqual(completion.feedback, .completed)
                XCTAssertEqual(completion.completedEffects, spec.completionEffects)
                XCTAssertEqual(completion.after.phase, .complete)
                XCTAssertEqual(completion.after.remainingUnits, 0)
                XCTAssertTrue(completion.after.allMinimumsMet)

                let encodedDistribution = completion.after.allocations
                    .map { "\($0.destinationID)=\($0.units)" }
                    .joined(separator: ",")
                completedDistributions.insert(encodedDistribution)

                let restored = try HarvestAllocationLabDriver(
                    spec: spec,
                    restoring: completion.checkpoint
                )
                XCTAssertEqual(try restored.snapshot(), completion.after)
            }
        }

        // Three genuinely free surplus shares across three obligations yield
        // ten valid terminal distributions. A hidden exact answer would yield one.
        XCTAssertEqual(completedDistributions.count, 10)
    }

    func testSourceExhaustionWithAnUnmetObligationResistsAndNamesTheDeficit() throws {
        let spec = try HarvestAllocationLabSpec.harvestDraftV1()
        var driver = try HarvestAllocationLabDriver(spec: spec)

        _ = try driver.submit(.touch(.set(destinationID: "food", units: 8)))
        _ = try driver.submit(.touch(.set(destinationID: "reserve", units: 2)))
        _ = try driver.submit(.touch(.set(destinationID: "seed", units: 2)))

        let resisted = try driver.submit(.touch(.commit))
        XCTAssertEqual(resisted.feedback, .resistance)
        XCTAssertEqual(resisted.completedEffects, [])
        XCTAssertEqual(resisted.after.phase, .active)
        XCTAssertEqual(resisted.after.remainingUnits, 0)
        XCTAssertFalse(resisted.after.canCommit)
        XCTAssertEqual(
            resisted.after.obligations.filter { $0.unmetUnits > 0 },
            [
                HarvestAllocationObligation(
                    destinationID: "seed",
                    minimumUnits: 3,
                    allocatedUnits: 2,
                    unmetUnits: 1
                ),
            ]
        )

        // Nothing is locked before commit: one share can be recovered from
        // food and moved to seed without restarting the scene.
        _ = try driver.submit(.semantic(.adjust(destinationID: "food", delta: -1)))
        _ = try driver.submit(.semantic(.adjust(destinationID: "seed", delta: 1)))
        let completion = try driver.submit(.semantic(.commit))
        XCTAssertEqual(completion.feedback, .completed)
        XCTAssertEqual(completion.completedEffects, spec.completionEffects)
        XCTAssertEqual(allocationMap(completion.after), ["food": 7, "reserve": 2, "seed": 3])
    }

    func testOverdrawAndUnknownDestinationLeaveTheCausalStateUntouched() throws {
        let spec = try HarvestAllocationLabSpec.harvestDraftV1()
        var driver = try HarvestAllocationLabDriver(spec: spec)
        _ = try driver.submit(.touch(.set(destinationID: "food", units: 12)))

        let beforeOverdraw = try driver.snapshot()
        let overdraw = try driver.submit(
            .touch(.set(destinationID: "reserve", units: 1))
        )
        XCTAssertEqual(overdraw.feedback, .resistance)
        XCTAssertEqual(overdraw.before, beforeOverdraw)
        XCTAssertEqual(overdraw.after, beforeOverdraw)

        let unknown = try driver.submit(
            .semantic(.adjust(destinationID: "tribute", delta: 1))
        )
        XCTAssertEqual(unknown.feedback, .resistance)
        XCTAssertEqual(unknown.before, unknown.after)
    }

    func testTouchAndVoiceOverUseTheSameReducerAtEveryRestoredStep() throws {
        let spec = try HarvestAllocationLabSpec.harvestDraftV1()
        let actions: [HarvestAllocationLabAction] = [
            .set(destinationID: "food", units: 5),
            .adjust(destinationID: "food", delta: -1),
            .set(destinationID: "reserve", units: 2),
            .set(destinationID: "seed", units: 3),
            .adjust(destinationID: "reserve", delta: 1),
            .adjust(destinationID: "seed", delta: 2),
            .commit,
        ]

        var uninterrupted = try HarvestAllocationLabDriver(spec: spec)
        for action in actions {
            let priorBytes = try JSONEncoder().encode(uninterrupted.checkpoint())
            let decodedPrior = try JSONDecoder().decode(
                HarvestAllocationLabCheckpoint.self,
                from: priorBytes
            )
            var restored = try HarvestAllocationLabDriver(
                spec: spec,
                restoring: decodedPrior
            )

            let touch = try uninterrupted.submit(.touch(action))
            let voiceOver = try restored.submit(.semantic(action))
            XCTAssertEqual(touch, voiceOver)
            XCTAssertEqual(try restored.checkpoint(), touch.checkpoint)
        }

        let finalBytes = try JSONEncoder().encode(uninterrupted.checkpoint())
        let finalCheckpoint = try JSONDecoder().decode(
            HarvestAllocationLabCheckpoint.self,
            from: finalBytes
        )
        let coldRestored = try HarvestAllocationLabDriver(
            spec: spec,
            restoring: finalCheckpoint
        )
        XCTAssertEqual(try coldRestored.snapshot().phase, .complete)
        XCTAssertEqual(
            allocationMap(try coldRestored.snapshot()),
            ["food": 4, "reserve": 3, "seed": 5]
        )
    }

    func testCheckpointRejectsSpecDriftVersionDriftAndForgedCompletion() throws {
        let spec = try HarvestAllocationLabSpec.harvestDraftV1()
        let driver = try HarvestAllocationLabDriver(spec: spec)
        let checkpoint = try driver.checkpoint()

        let changedSpec = try HarvestAllocationLabSpec(
            totalUnits: 13,
            destinations: spec.destinations,
            completionEffects: spec.completionEffects
        )
        XCTAssertThrowsError(
            try HarvestAllocationLabDriver(
                spec: changedSpec,
                restoring: checkpoint
            )
        ) { error in
            XCTAssertEqual(error as? HarvestAllocationLabError, .checkpointSpecMismatch)
        }

        let wrongVersion = HarvestAllocationLabCheckpoint(
            formatVersion: 2,
            specDigest: checkpoint.specDigest,
            sequenceNumber: checkpoint.sequenceNumber,
            state: checkpoint.state
        )
        XCTAssertThrowsError(
            try HarvestAllocationLabDriver(spec: spec, restoring: wrongVersion)
        ) { error in
            XCTAssertEqual(
                error as? HarvestAllocationLabError,
                .unsupportedCheckpointVersion(2)
            )
        }

        let forgedCompletion = HarvestAllocationLabCheckpoint(
            specDigest: checkpoint.specDigest,
            sequenceNumber: checkpoint.sequenceNumber,
            state: HarvestAllocationLabState(
                phase: .complete,
                allocations: checkpoint.state.allocations
            )
        )
        XCTAssertThrowsError(
            try HarvestAllocationLabDriver(spec: spec, restoring: forgedCompletion)
        ) { error in
            XCTAssertEqual(error as? HarvestAllocationLabError, .invalidState)
        }
    }

    func testSpecRejectsAHiddenExactAnswerAndMalformedObligations() throws {
        let effect = try HarvestAllocationLabSpec.harvestDraftV1().completionEffects

        XCTAssertThrowsError(
            try HarvestAllocationLabSpec(
                totalUnits: 9,
                destinations: [
                    HarvestAllocationMinimum(destinationID: "food", minimumUnits: 4),
                    HarvestAllocationMinimum(destinationID: "reserve", minimumUnits: 2),
                    HarvestAllocationMinimum(destinationID: "seed", minimumUnits: 3),
                ],
                completionEffects: effect
            )
        )

        XCTAssertThrowsError(
            try HarvestAllocationLabSpec(
                totalUnits: 12,
                destinations: [
                    HarvestAllocationMinimum(destinationID: "food", minimumUnits: 4),
                    HarvestAllocationMinimum(destinationID: "food", minimumUnits: 2),
                ],
                completionEffects: effect
            )
        )

        XCTAssertThrowsError(
            try HarvestAllocationLabSpec(
                totalUnits: 12,
                destinations: [
                    HarvestAllocationMinimum(destinationID: "food", minimumUnits: 4),
                    HarvestAllocationMinimum(destinationID: "seed", minimumUnits: 3),
                ],
                completionEffects: []
            )
        )
    }

    private func allocationMap(
        _ snapshot: HarvestAllocationLabSnapshot
    ) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: snapshot.allocations.map {
            ($0.destinationID, $0.units)
        })
    }
}
