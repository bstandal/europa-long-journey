import CryptoKit
import XCTest

@MainActor
final class JourneyAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSignedFirstFarmersStartsAtCanonicalOpeningAndAdvancesIntoCrossing()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-runtime-first-farmers"
            ].waitForExistence(timeout: 12)
        )
        let opening = app.descendants(matching: .any)[
            "chapter-beat-beat-first-farmers-river-world"
        ]
        XCTAssertTrue(opening.waitForExistence(timeout: 5))
        let advance = app.buttons["chapter-continue"]
        for _ in 0 ..< 5 where !advance.isHittable { opening.swipeUp() }
        XCTAssertTrue(advance.isHittable)
        advance.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-beat-beat-first-farmers-household-crosses"
            ].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-semantic-trace-route"
            ].exists
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "signed-runtime-failure-diagnostic"
            ].exists
        )
    }

    func testPreviousReviewsCompletedSceneWithoutChangingCausalProgress()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
        ]
        app.launch()

        let opening = app.descendants(matching: .any)[
            "chapter-beat-beat-first-farmers-river-world"
        ]
        XCTAssertTrue(opening.waitForExistence(timeout: 12))
        let advance = app.buttons["chapter-continue"]
        XCTAssertTrue(advance.waitForExistence(timeout: 3))
        XCTAssertTrue(advance.isHittable)
        advance.tap()

        let currentBeat = app.descendants(matching: .any)[
            "chapter-beat-beat-first-farmers-household-crosses"
        ]
        XCTAssertTrue(currentBeat.waitForExistence(timeout: 8))
        let causalState = app.descendants(matching: .any)[
            "signed-runtime-review-causal-state"
        ]
        XCTAssertTrue(causalState.waitForExistence(timeout: 3))
        let stateBeforeReview = try XCTUnwrap(
            causalState.value as? String
        )

        let previous = app.buttons["chapter-previous"]
        XCTAssertTrue(previous.waitForExistence(timeout: 3))
        XCTAssertTrue(previous.isHittable)
        previous.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-review-beat-first-farmers-river-world"
            ].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.buttons["chapter-review-road"].exists)
        XCTAssertTrue(app.buttons["chapter-review-sound-control"].exists)
        let reviewSceneList = app.buttons[
            "chapter-review-visited-scenes-open"
        ]
        XCTAssertTrue(reviewSceneList.exists)
        XCTAssertTrue(reviewSceneList.isHittable)
        XCTAssertGreaterThanOrEqual(reviewSceneList.frame.height, 44)
        XCTAssertEqual(
            app.buttons["chapter-review-previous"].label,
            "Previous"
        )
        XCTAssertEqual(app.buttons["chapter-review-next"].label, "Next")
        XCTAssertGreaterThanOrEqual(
            app.buttons["chapter-review-previous"].frame.height,
            44
        )
        XCTAssertGreaterThanOrEqual(
            app.buttons["chapter-review-next"].frame.height,
            44
        )
        reviewSceneList.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-review-visited-scenes-sheet"
            ].waitForExistence(timeout: 3)
        )
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(reviewSceneList.waitForExistence(timeout: 3))
        let closeReview = app.buttons["chapter-review-close"]
        XCTAssertEqual(closeReview.label, "Return to current")
        XCTAssertTrue(closeReview.isHittable)
        XCTAssertGreaterThanOrEqual(closeReview.frame.height, 44)
        closeReview.tap()

        XCTAssertTrue(currentBeat.waitForExistence(timeout: 8))
        XCTAssertTrue(causalState.waitForExistence(timeout: 3))
        let stateAfterReview = try XCTUnwrap(
            causalState.value as? String
        )
        XCTAssertEqual(
            stateAfterReview,
            stateBeforeReview,
            "Review changed the active beat or causal chapter state"
        )
    }

    func testReviewPreviousAndNextMoveOnlyAmongArchivedScenes() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-beat=beat-first-farmers-living-system",
        ]
        app.launch()

        let currentBeat = app.descendants(matching: .any)[
            "chapter-beat-beat-first-farmers-living-system"
        ]
        XCTAssertTrue(currentBeat.waitForExistence(timeout: 12))
        let causalState = app.descendants(matching: .any)[
            "signed-runtime-review-causal-state"
        ]
        XCTAssertTrue(causalState.waitForExistence(timeout: 3))
        let stateBeforeReview = try XCTUnwrap(causalState.value as? String)

        let openPrevious = app.buttons["chapter-previous"]
        XCTAssertTrue(openPrevious.waitForExistence(timeout: 3))
        XCTAssertTrue(openPrevious.isHittable)
        openPrevious.tap()

        let secondScene = app.descendants(matching: .any)[
            "chapter-review-beat-first-farmers-household-crosses"
        ]
        XCTAssertTrue(secondScene.waitForExistence(timeout: 8))
        let soundControl = app.buttons["chapter-review-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        let secondSceneIsReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: soundControl
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [secondSceneIsReady], timeout: 8),
            .completed
        )
        let previous = app.buttons["chapter-review-previous"]
        XCTAssertTrue(previous.isEnabled)
        XCTAssertTrue(previous.isHittable)
        previous.tap()

        let firstScene = app.descendants(matching: .any)[
            "chapter-review-beat-first-farmers-river-world"
        ]
        XCTAssertTrue(firstScene.waitForExistence(timeout: 8))
        let firstSceneIsReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: soundControl
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [firstSceneIsReady], timeout: 8),
            .completed
        )
        let next = app.buttons["chapter-review-next"]
        XCTAssertTrue(next.isEnabled)
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(secondScene.waitForExistence(timeout: 8))
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "chapter-review-beat-first-farmers-living-system"
            ].exists,
            "The active, uncompleted scene entered the review archive"
        )

        let closeReview = app.buttons["chapter-review-close"]
        XCTAssertEqual(closeReview.label, "Return to current")
        closeReview.tap()
        XCTAssertTrue(currentBeat.waitForExistence(timeout: 8))
        XCTAssertTrue(causalState.waitForExistence(timeout: 3))
        XCTAssertEqual(causalState.value as? String, stateBeforeReview)
    }

    func testVisitedSceneListExcludesFutureScenes() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-beat=beat-first-farmers-living-system",
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-beat-beat-first-farmers-living-system"
            ].waitForExistence(timeout: 12)
        )
        let openVisitedScenes = app.buttons["chapter-visited-scenes-open"]
        XCTAssertTrue(openVisitedScenes.waitForExistence(timeout: 3))
        XCTAssertTrue(openVisitedScenes.isHittable)
        openVisitedScenes.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-visited-scenes-sheet"
            ].waitForExistence(timeout: 5)
        )

        let firstVisited = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS %@",
                "The River Already Held a World"
            )
        ).firstMatch
        let secondVisited = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS %@",
                "The Field Crosses the Sea"
            )
        ).firstMatch
        let current = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS %@ AND label CONTAINS %@",
                "Nothing Travels Alone",
                "Current"
            )
        ).firstMatch
        XCTAssertTrue(firstVisited.exists)
        XCTAssertTrue(secondVisited.exists)
        XCTAssertTrue(current.exists)

        let future = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "label CONTAINS %@",
                "The First Season Takes Hold"
            )
        ).firstMatch
        XCTAssertFalse(future.exists, "The scene list revealed a future scene")
    }

    func testReviewSurvivesHardKillAndReturnsToUnchangedCurrentScene()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-beat=beat-first-farmers-living-system",
        ]
        app.launch()

        let currentBeat = app.descendants(matching: .any)[
            "chapter-beat-beat-first-farmers-living-system"
        ]
        XCTAssertTrue(currentBeat.waitForExistence(timeout: 12))
        let causalState = app.descendants(matching: .any)[
            "signed-runtime-review-causal-state"
        ]
        XCTAssertTrue(causalState.waitForExistence(timeout: 3))
        let stateBeforeReview = try XCTUnwrap(causalState.value as? String)

        let openPrevious = app.buttons["chapter-previous"]
        XCTAssertTrue(openPrevious.waitForExistence(timeout: 3))
        openPrevious.tap()
        let restoredReview = app.descendants(matching: .any)[
            "chapter-review-beat-first-farmers-household-crosses"
        ]
        XCTAssertTrue(restoredReview.waitForExistence(timeout: 8))
        app.terminate()

        app.launchArguments = ["--ui-testing-signed-runtime-fixture"]
        app.launch()
        XCTAssertTrue(restoredReview.waitForExistence(timeout: 12))
        let closeReview = app.buttons["chapter-review-close"]
        XCTAssertTrue(closeReview.waitForExistence(timeout: 3))
        XCTAssertEqual(closeReview.label, "Return to current")
        closeReview.tap()

        XCTAssertTrue(currentBeat.waitForExistence(timeout: 8))
        XCTAssertTrue(causalState.waitForExistence(timeout: 3))
        XCTAssertEqual(
            causalState.value as? String,
            stateBeforeReview,
            "Restoring review changed causal chapter progress"
        )
    }

    func testCompletedChapterReviewDoneReturnsToWorld() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-beat=beat-first-farmers-before-steppe",
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-beat-beat-first-farmers-before-steppe"
            ].waitForExistence(timeout: 12)
        )
        let completeChapter = app.buttons["chapter-continue"]
        XCTAssertTrue(completeChapter.waitForExistence(timeout: 3))
        XCTAssertTrue(completeChapter.isHittable)
        completeChapter.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["living-world-field"]
                .waitForExistence(timeout: 12)
        )

        let completedChapter = app.buttons["chapter-road-first-farmers"]
        for _ in 0 ..< 20 where !completedChapter.isHittable {
            if completedChapter.frame.midY > app.frame.midY {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
        }
        XCTAssertTrue(completedChapter.isHittable)
        XCTAssertTrue(completedChapter.label.hasSuffix(", Review"))
        completedChapter.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-review-beat-first-farmers-river-world"
            ].waitForExistence(timeout: 8)
        )
        let done = app.buttons["chapter-review-close"]
        XCTAssertTrue(done.isHittable)
        XCTAssertEqual(done.label, "Done")
        done.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["living-world-field"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["content-unavailable"].exists
        )
    }

    func testAllThreeIncludedChaptersOpenFromMapAndRoad() {
        let chapters = [
            "first-farmers",
            "europe-holds-the-line",
            "european-world",
        ]

        for chapterID in chapters {
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-testing-reset-state",
                "--ui-testing-signed-runtime-fixture",
                "--ui-testing-signed-runtime-fixture-world-ready",
                "--ui-testing-signed-runtime-fixture-chapter=\(chapterID)",
            ]
            app.launch()

            let runtime = app.descendants(matching: .any)[
                "chapter-runtime-\(chapterID)"
            ]
            XCTAssertTrue(runtime.waitForExistence(timeout: 12), chapterID)
            let roadControl = app.buttons["chapter-road"]
            XCTAssertTrue(roadControl.waitForExistence(timeout: 3), chapterID)
            roadControl.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["living-world-field"]
                    .waitForExistence(timeout: 8),
                chapterID
            )

            let mapEntry = app.buttons["chapter-world-entry-\(chapterID)"]
            XCTAssertTrue(mapEntry.waitForExistence(timeout: 3), chapterID)
            for _ in 0 ..< 12 where !mapEntry.isHittable {
                app.swipeDown()
            }
            XCTAssertTrue(mapEntry.isHittable, chapterID)
            XCTAssertEqual(
                mapEntry.frame.width,
                44,
                accuracy: 0.001,
                chapterID
            )
            XCTAssertEqual(
                mapEntry.frame.height,
                44,
                accuracy: 0.001,
                chapterID
            )
            XCTAssertTrue(mapEntry.label.hasSuffix(", Resume"), chapterID)
            mapEntry.tap()
            XCTAssertTrue(runtime.waitForExistence(timeout: 8), chapterID)

            XCTAssertTrue(roadControl.waitForExistence(timeout: 3), chapterID)
            roadControl.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["living-world-field"]
                    .waitForExistence(timeout: 8),
                chapterID
            )
            let roadEntry = app.buttons["chapter-road-\(chapterID)"]
            XCTAssertTrue(roadEntry.waitForExistence(timeout: 3), chapterID)
            for _ in 0 ..< 20 where !roadEntry.isHittable {
                if roadEntry.frame.midY > app.frame.midY {
                    app.swipeUp()
                } else {
                    app.swipeDown()
                }
            }
            XCTAssertTrue(roadEntry.isHittable, chapterID)
            XCTAssertTrue(roadEntry.label.hasSuffix(", Resume"), chapterID)
            roadEntry.tap()
            XCTAssertTrue(runtime.waitForExistence(timeout: 8), chapterID)
            XCTAssertFalse(
                app.buttons["chapter-failure-return-to-road"].exists,
                chapterID
            )
            app.terminate()
        }
    }

    func testAccessibilityXXXLLinearTraceCompletesThroughSharedReducer()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-beat=beat-first-farmers-household-crosses",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-first-farmers-household-crosses"
        ]
        XCTAssertTrue(beat.waitForExistence(timeout: 12))
        let reducerDiagnostic = app.descendants(matching: .any)[
            "chapter-input-resolution-diagnostic"
        ]
        XCTAssertTrue(reducerDiagnostic.waitForExistence(timeout: 3))
        let advanceRoute = app.buttons[
            "chapter-linear-trace-route-increment"
        ]
        XCTAssertTrue(advanceRoute.waitForExistence(timeout: 3))
        XCTAssertTrue(advanceRoute.isHittable)
        XCTAssertGreaterThanOrEqual(advanceRoute.frame.width, 44)
        XCTAssertGreaterThanOrEqual(advanceRoute.frame.height, 44)
        wait(
            for: advanceRoute,
            toHaveValue: "0 of 4 route points reached"
        )

        for reachedAnchorCount in 1 ... 3 {
            advanceRoute.tap()
            wait(
                for: advanceRoute,
                toHaveValue:
                    "\(reachedAnchorCount) of 4 route points reached",
                timeout: 8
            )
            XCTAssertTrue(advanceRoute.isHittable)
        }
        advanceRoute.tap()
        wait(
            for: reducerDiagnostic,
            toHaveValue: "processed;traceReached=4",
            timeout: 8
        )

        let continueButton = app.buttons["chapter-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 8))
        XCTAssertTrue(continueButton.isHittable)
        XCTAssertGreaterThanOrEqual(continueButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(continueButton.frame.height, 44)
        XCTAssertFalse(app.buttons["chapter-failure-return-to-road"].exists)
    }

#if NON_SHIPPING_LIVE_TEST
    func testLiveFirstFarmersNeedsNoFixtureArgumentAndRestoresAfterHardKill()
        throws {
        let app = XCUIApplication()
        // NON_SHIPPING_LIVE_TEST is itself the fixture authority. The reset
        // argument clears only the review save and must not be needed again.
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let opening = app.descendants(matching: .any)[
            "chapter-beat-beat-first-farmers-river-world"
        ]
        XCTAssertTrue(opening.waitForExistence(timeout: 12))
        let advance = app.buttons["chapter-continue"]
        reveal(advance, in: opening)
        advance.tap()

        let crossing = app.descendants(matching: .any)[
            "chapter-beat-beat-first-farmers-household-crosses"
        ]
        XCTAssertTrue(crossing.waitForExistence(timeout: 8))
        app.terminate()

        app.launchArguments = []
        app.launch()
        XCTAssertTrue(crossing.waitForExistence(timeout: 12))
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-semantic-trace-route"
            ].exists
        )
        XCTAssertFalse(
            app.buttons["chapter-failure-return-to-road"].exists
        )
    }
#endif

    func testSignedFirstFarmersTraversesSeventeenBeatsWithSixPhysicalInteractions()
        throws {
        let receipt = try traverseFirstFarmersReviewBuild()
        XCTAssertEqual(receipt.beatIDs.count, 17)
        XCTAssertEqual(receipt.interactionIDs.count, 6)
        print(
            "CHAPTER_01_LIVE_UI_TRAVERSAL beats=\(receipt.beatIDs.count) "
                + "interactions=\(receipt.interactionIDs.count) "
                + "sha256=\(receipt.sha256)"
        )
    }

    func testLiveFirstFarmersRecordsHouseholdCrossing() throws {
        try recordFirstFarmersInteraction(.householdCrossing)
    }

    func testLiveFirstFarmersRecordsHarvestAllocation() throws {
        try recordFirstFarmersInteraction(.harvestAllocation)
    }

    func testLiveFirstFarmersRecordsThreeRecords() throws {
        try recordFirstFarmersInteraction(.threeRecords)
    }

    func testLiveFirstFarmersRecordsLonghouseAssembly() throws {
        try recordFirstFarmersInteraction(.longhouseAssembly)
    }

    func testLiveFirstFarmersRecordsSettlementGrowth() throws {
        try recordFirstFarmersInteraction(.settlementGrowth)
    }

    func testLiveFirstFarmersRecordsContinentRemade() throws {
        try recordFirstFarmersInteraction(.continentRemade)
    }

    func testContinentRemadeResponseCleanupSerializesTheNextTransformInput()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-beat=beat-first-farmers-continent-remade",
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-runtime-first-farmers"
            ].waitForExistence(timeout: 12)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-beat-beat-first-farmers-continent-remade"
            ].waitForExistence(timeout: 12)
        )
        let touchSurface = app.windows.firstMatch
        XCTAssertTrue(touchSurface.waitForExistence(timeout: 3))

        let firstStage = app.descendants(matching: .any)[
            "chapter-semantic-transform-danube-fields"
        ]
        let secondStage = app.descendants(matching: .any)[
            "chapter-semantic-transform-loess-settlements"
        ]
        let failure = app.buttons["chapter-failure-return-to-road"]
        XCTAssertTrue(firstStage.waitForExistence(timeout: 3))

        // An accepted Transform sample schedules response cleanup after 180 ms.
        // This deliberately slow physical drag keeps later samples arriving
        // beyond that boundary, proving that cleanup and the next input are
        // serialized instead of turning the overlap into an audio failure.
        touchSurface.coordinate(
            withNormalizedOffset: CGVector(dx: 0.1785714, dy: 0.55)
        ).press(
            forDuration: 0.15,
            thenDragTo: touchSurface.coordinate(
                withNormalizedOffset: CGVector(dx: 0.1785714, dy: 0.08)
            ),
            withVelocity: .slow,
            thenHoldForDuration: 0
        )

        XCTAssertTrue(
            secondStage.waitForExistence(timeout: 12),
            "The serialized Transform input did not reveal its next stage"
        )
        let diagnostic = app.descendants(matching: .any)[
            "signed-runtime-failure-diagnostic"
        ]
        XCTAssertFalse(
            failure.exists,
            "Response cleanup rejected the next Transform input: "
                + (diagnostic.exists
                    ? String(describing: diagnostic.value)
                    : "no diagnostic")
        )
    }

    func testSignedFirstFarmersPrimaryTimelineUsesSoundControlAndColdResumesPaused()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
        ]
        app.launch()

        let opening = app.descendants(matching: .any)[
            "chapter-beat-beat-first-farmers-river-world"
        ]
        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let primaryState = app.descendants(matching: .any)[
            "primary-audio-runtime-state"
        ]
        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(opening.waitForExistence(timeout: 12))
        XCTAssertTrue(primaryState.waitForExistence(timeout: 3))
        wait(for: phaseState, toHaveValue: "ready:none")
        wait(
            for: primaryState,
            toHaveValueBeginningWith:
                "bound;timeline=audio-beat-first-farmers-river-world;"
        )

        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        XCTAssertTrue(soundControl.isHittable)
        XCTAssertEqual(soundControl.label, "Resume sound")
        XCTAssertGreaterThanOrEqual(soundControl.frame.width, 44)
        XCTAssertGreaterThanOrEqual(soundControl.frame.height, 44)
        soundControl.tap()
        let initialStart = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value == %@ AND enabled == true",
                "playing:none"
            ),
            object: phaseState
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [initialStart], timeout: 8),
            .completed,
            "Phase: \(String(describing: phaseState.value)); primary: "
                + "\(String(describing: primaryState.value))"
        )
        wait(
            for: primaryState,
            toHaveValueBeginningWith:
                "playing;timeline=audio-beat-first-farmers-river-world;",
            timeout: 8
        )

        let checkpointWindow = expectation(
            description: "primary audio checkpoint window"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            checkpointWindow.fulfill()
        }
        wait(for: [checkpointWindow], timeout: 2)
        app.terminate()

        app.launchArguments = [
            "--ui-testing-signed-runtime-fixture",
        ]
        app.launch()
        XCTAssertTrue(opening.waitForExistence(timeout: 12))
        XCTAssertTrue(primaryState.waitForExistence(timeout: 3))
        wait(for: phaseState, toHaveValue: "resumeRequired:none")
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        XCTAssertEqual(soundControl.label, "Resume sound")
        soundControl.tap()
        wait(for: phaseState, toHaveValue: "playing:none", timeout: 8)
        wait(
            for: primaryState,
            toHaveValueBeginningWith:
                "playing;timeline=audio-beat-first-farmers-river-world;",
            timeout: 8
        )
        let resumedValue = try XCTUnwrap(primaryState.value as? String)
        let cursor = resumedValue.split(separator: ";")
            .first(where: { $0.hasPrefix("cursor=") })
            .flatMap { Int64($0.dropFirst("cursor=".count)) }
        XCTAssertGreaterThan(try XCTUnwrap(cursor), 0, resumedValue)
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "signed-runtime-failure-diagnostic"
            ].exists,
            resumedValue
        )
    }

    func testSignedFirstFarmersThreeRecordsPreparesWithoutIntegrityFailure()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-beat=beat-first-farmers-three-records",
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-runtime-first-farmers"
            ].waitForExistence(timeout: 12)
        )
        let failureDiagnostic = app.descendants(matching: .any)[
            "signed-runtime-failure-diagnostic"
        ]
        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-first-farmers-three-records"
        ]
        let audioRuntime = app.descendants(matching: .any)[
            "global-responsive-audio-runtime-state"
        ]
        let lifecycle = app.descendants(matching: .any)[
            "global-causal-lifecycle-state"
        ]
        XCTAssertTrue(
            beat.waitForExistence(timeout: 12),
            "Runtime failure: \(String(describing: failureDiagnostic.value)); "
                + "audio: \(String(describing: audioRuntime.value)); "
                + "lifecycle: \(String(describing: lifecycle.value))"
        )
        XCTAssertFalse(
            failureDiagnostic.exists,
            "Runtime failure: \(String(describing: failureDiagnostic.value))"
        )

        let sceneSurface = app.windows.firstMatch
        XCTAssertTrue(sceneSurface.waitForExistence(timeout: 3))
        let firstStage = app.descendants(matching: .any)[
            "chapter-semantic-transform-river-communities"
        ]
        XCTAssertTrue(firstStage.waitForExistence(timeout: 3))
        sceneSurface.coordinate(
            withNormalizedOffset: CGVector(dx: 0.1785714, dy: 0.55)
        ).press(
            forDuration: 0.1,
            thenDragTo: sceneSurface.coordinate(
                withNormalizedOffset: CGVector(dx: 0.1785714, dy: 0.08)
            )
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-semantic-transform-contact-households"
            ].waitForExistence(timeout: 8),
            "Runtime failure after first transform: "
                + String(describing: failureDiagnostic.value)
        )
        XCTAssertFalse(
            failureDiagnostic.exists,
            "Runtime failure after first transform: "
                + String(describing: failureDiagnostic.value)
        )
    }

    func testSignedFirstFarmersOpensEveryAuthoredBeatThroughProductionRoute()
        throws {
        let beatIDs = [
            "beat-first-farmers-river-world",
            "beat-first-farmers-household-crosses",
            "beat-first-farmers-living-system",
            "beat-first-farmers-european-ground",
            "beat-first-farmers-inhabited-frontier",
            "beat-first-farmers-harvest-allocation",
            "beat-first-farmers-stored-future",
            "beat-first-farmers-gorge-contact",
            "beat-first-farmers-three-records",
            "beat-first-farmers-frontier-consequence",
            "beat-first-farmers-raise-longhouse",
            "beat-first-farmers-plot-remains",
            "beat-first-farmers-paternal-lines",
            "beat-first-farmers-more-mouths",
            "beat-first-farmers-growth-breaks",
            "beat-first-farmers-continent-remade",
            "beat-first-farmers-before-steppe",
        ]

        for beatID in beatIDs {
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-testing-reset-state",
                "--ui-testing-signed-runtime-fixture",
                "--ui-testing-signed-runtime-fixture-beat=\(beatID)",
            ]
            app.launch()

            let failureDiagnostic = app.descendants(matching: .any)[
                "signed-runtime-failure-diagnostic"
            ]
            XCTAssertTrue(
                app.descendants(matching: .any)[
                    "chapter-beat-\(beatID)"
                ].waitForExistence(timeout: 12),
                "\(beatID): \(String(describing: failureDiagnostic.value))"
            )
            XCTAssertFalse(
                failureDiagnostic.exists,
                "\(beatID): \(String(describing: failureDiagnostic.value))"
            )
            let primaryState = app.descendants(matching: .any)[
                "primary-audio-runtime-state"
            ]
            XCTAssertTrue(
                primaryState.waitForExistence(timeout: 3),
                "\(beatID): primary authored audio was not bound"
            )
            XCTAssertTrue(
                (primaryState.value as? String)?.hasPrefix(
                    "bound;timeline=audio-\(beatID);"
                ) == true,
                "\(beatID): \(String(describing: primaryState.value))"
            )
            XCTAssertTrue(
                app.buttons["chapter-sound-control"].exists,
                "\(beatID): the fixed sound control is unavailable"
            )
            app.terminate()
        }
    }

    func testSignedRuntimeFixtureUsesProductionRouteAndColdRestoresExactly()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-beat=beat-first-farmers-harvest-allocation",
        ]
        app.launch()

        let productionRoute = app.descendants(matching: .any)[
            "chapter-runtime-first-farmers"
        ]
        XCTAssertTrue(productionRoute.waitForExistence(timeout: 12))
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "development-chapter-first-farmers"
            ].exists
        )
        let signedBeat = app.descendants(matching: .any)[
            "chapter-beat-beat-first-farmers-harvest-allocation"
        ]
        let failureDiagnostic = app.descendants(matching: .any)[
            "signed-runtime-failure-diagnostic"
        ]
        XCTAssertTrue(
            signedBeat.waitForExistence(timeout: 5),
            "Runtime failure: \(String(describing: failureDiagnostic.value))"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-semantic-allocate-winter-food"
            ].exists
        )
        let restoreState = app.descendants(matching: .any)[
            "signed-runtime-restore-state"
        ]
        XCTAssertTrue(restoreState.waitForExistence(timeout: 3))
        let exactStateBeforeKill = try XCTUnwrap(restoreState.value as? String)
        XCTAssertTrue(exactStateBeforeKill.contains(":"))

        app.terminate()
        app.launchArguments = [
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-beat=beat-first-farmers-harvest-allocation",
        ]
        app.launch()

        XCTAssertTrue(productionRoute.waitForExistence(timeout: 12))
        XCTAssertTrue(restoreState.waitForExistence(timeout: 3))
        XCTAssertEqual(restoreState.value as? String, exactStateBeforeKill)
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-beat-beat-first-farmers-harvest-allocation"
            ].exists
        )
    }

    func testResponsiveChapterSoundStartsAfterDeliberateEntryAndColdRestoreRequiresResume()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-beat=beat-first-farmers-harvest-allocation",
        ]
        app.launch()

        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let runtimeState = app.descendants(matching: .any)[
            "responsive-audio-runtime-state"
        ]
        XCTAssertTrue(phaseState.waitForExistence(timeout: 12))
        XCTAssertTrue(runtimeState.waitForExistence(timeout: 3))
        XCTAssertEqual(phaseState.value as? String, "ready:waiting")
        let initialRuntime = try XCTUnwrap(runtimeState.value as? String)
        let bindingAuthority = try XCTUnwrap(
            initialRuntime.split(separator: ";").first.map(String.init)
        )
        XCTAssertTrue(
            initialRuntime.hasPrefix(
                "\(bindingAuthority);playback=paused;stage=approach;"
            ),
            initialRuntime
        )
        let soundControl = app.buttons["chapter-sound-control"]
        let firstNarrative = app.descendants(matching: .any)[
            "chapter-beat-beat-first-farmers-harvest-allocation"
        ]
        XCTAssertTrue(firstNarrative.waitForExistence(timeout: 5))
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        XCTAssertTrue(soundControl.isHittable)
        XCTAssertEqual(soundControl.label, "Resume sound")
        soundControl.tap()
        _ = try waitForResponsiveAudioPlaybackState(
            runtimeState,
            playback: "playing",
            pause: "none",
            timeout: 8
        )
        wait(for: phaseState, toHaveValue: "playing:waiting")
        wait(
            for: runtimeState,
            toHaveValueBeginningWith: "\(bindingAuthority);playback=playing;"
        )
        wait(
            for: runtimeState,
            toHaveValueBeginningWith:
                "\(bindingAuthority);playback=playing;stage=approach;",
            timeout: 8
        )

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(soundControl.waitForExistence(timeout: 5))
        wait(for: phaseState, toHaveValue: "resumeRequired:waiting")
        XCTAssertEqual(soundControl.label, "Resume sound")
        soundControl.tap()
        wait(for: phaseState, toHaveValue: "playing:waiting")

        app.buttons["chapter-road"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["living-world-field"]
                .waitForExistence(timeout: 8)
        )
        let nextProgram = app.buttons["chapter-road-european-world"]
        for _ in 0 ..< 12 where !nextProgram.isHittable { app.swipeUp() }
        XCTAssertTrue(nextProgram.isHittable)
        nextProgram.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-runtime-european-world"
            ].waitForExistence(timeout: 12)
        )
        // The road tap is the deliberate chapter-entry grant. Sound starts
        // once the verified scene is bound, with no intermediate choice.
        wait(for: phaseState, toHaveValue: "playing:waiting", timeout: 8)
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        XCTAssertEqual(soundControl.label, "Turn sound off")
        let oceanNarrative = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let semanticTrace = app.descendants(matching: .any)[
            "chapter-semantic-trace-ocean-route"
        ]
        let choiceDiagnostic = app.descendants(matching: .any)[
            "responsive-audio-choice-diagnostic"
        ]
        let failureDiagnostic = app.descendants(matching: .any)[
            "signed-runtime-failure-diagnostic"
        ]
        XCTAssertTrue(oceanNarrative.waitForExistence(timeout: 5))
        XCTAssertTrue(semanticTrace.waitForExistence(timeout: 3))

        // The first two authored ocean-route anchors at master (0.30, 0.54)
        // and (0.43, 0.52) project through the signed baseline crop to these
        // viewport points. This drag enters the production Trace gesture and
        // reducer; it is not a transport or test-only phase hook.
        let firstOceanAnchor = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.214, dy: 0.557)
        )
        let secondOceanAnchor = app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.400, dy: 0.529)
        )
        firstOceanAnchor.press(
            forDuration: 0.15,
            thenDragTo: secondOceanAnchor
        )
        // This combined lifecycle test already generated a resolved Home
        // pause. Its diagnostic remains the last physical event for the
        // process, so current readiness is proved by a closed episode,
        // synchronized playback and the durable semantic advance. The
        // dedicated physical Trace test below owns the ephemeral-bed check.
        let runtimeEngaged = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ "
                        + "AND value CONTAINS %@ AND enabled == true",
                "playback=playing;stage=interaction",
                "presentationSync=succeeded",
                "episode=none"
            ),
            object: runtimeState
        )
        let semanticAdvanced = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value == %@ AND enabled == true",
                "2 of 4 route points reached"
            ),
            object: semanticTrace
        )
        let result = XCTWaiter().wait(
            for: [runtimeEngaged, semanticAdvanced],
            timeout: 8
        )
        let diagnosticValue: (XCUIElement) -> String = { element in
            guard element.exists else { return "absent" }
            return String(describing: element.value)
        }
        let assertionContext =
            "Runtime: \(diagnosticValue(runtimeState)); phase: "
                + "\(diagnosticValue(phaseState)); semantic: "
                + "\(diagnosticValue(semanticTrace)); choice: "
                + "\(diagnosticValue(choiceDiagnostic)); failure: "
                + diagnosticValue(failureDiagnostic)
        XCTAssertEqual(
            result,
            .completed,
            assertionContext
        )

        app.terminate()
        app.launchArguments = [
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-runtime-european-world"
            ].waitForExistence(timeout: 12)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-beat-beat-european-world-ocean-schedule"
            ].waitForExistence(timeout: 5)
        )
        wait(for: phaseState, toHaveValue: "resumeRequired:waiting")
        let coldRuntime = try waitForResponsiveAudioPhysicalState(
            runtimeState,
            playback: "paused",
            pause: "none",
            timeout: 8
        )
        XCTAssertEqual(coldRuntime.stage, "interaction")
        // Lifecycle durability removes transient contact/resistance beds before
        // persisting; interaction progress and the exact cursor remain intact.
        XCTAssertEqual(coldRuntime.phase, "waiting")
        XCTAssertEqual(coldRuntime.durablePhase, "waiting")
        XCTAssertEqual(coldRuntime.pending, "none")
        wait(for: semanticTrace, toHaveValue: "2 of 4 route points reached")
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        XCTAssertEqual(soundControl.label, "Resume sound")
    }

    func testSignedEuropeanWorldPhysicalTraceEngagesResponsiveAudio() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
        ]
        app.launch()

        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let runtimeState = app.descendants(matching: .any)[
            "responsive-audio-runtime-state"
        ]
        let failureDiagnostic = app.descendants(matching: .any)[
            "signed-runtime-failure-diagnostic"
        ]
        let choiceDiagnostic = app.descendants(matching: .any)[
            "responsive-audio-choice-diagnostic"
        ]
        let bindingReady = app.descendants(matching: .any)[
            "responsive-audio-binding-ready"
        ]
        let inputAdmissionDiagnostic = app.descendants(matching: .any)[
            "chapter-input-admission-diagnostic"
        ]
        let inputResolutionDiagnostic = app.descendants(matching: .any)[
            "chapter-input-resolution-diagnostic"
        ]
        let oceanNarrative = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let semanticTrace = app.descendants(matching: .any)[
            "chapter-semantic-trace-ocean-route"
        ]
        let touchSurface = app.descendants(matching: .any)[
            "chapter-touch-surface"
        ]
        XCTAssertTrue(phaseState.waitForExistence(timeout: 12))
        XCTAssertTrue(runtimeState.waitForExistence(timeout: 3))
        XCTAssertTrue(oceanNarrative.waitForExistence(timeout: 5))
        XCTAssertTrue(semanticTrace.waitForExistence(timeout: 3))
        XCTAssertTrue(touchSurface.waitForExistence(timeout: 3))
        XCTAssertTrue(bindingReady.waitForExistence(timeout: 3))
        XCTAssertTrue(inputAdmissionDiagnostic.waitForExistence(timeout: 3))
        XCTAssertTrue(inputResolutionDiagnostic.waitForExistence(timeout: 3))
        XCTAssertEqual(phaseState.value as? String, "ready:waiting")
        let initialBindingReadyValue = bindingReady.value as? String

        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        XCTAssertTrue(soundControl.isHittable)
        XCTAssertEqual(soundControl.label, "Resume sound")
        soundControl.tap()
        let started = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value == %@ AND enabled == true",
                "playing:waiting"
            ),
            object: phaseState
        )
        let runtimeStarted = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value CONTAINS %@ AND enabled == true",
                "playback=playing;stage=interaction;phase=waiting;durable=waiting;pending=none"
            ),
            object: runtimeState
        )
        let routeBindingReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value != %@ AND value BEGINSWITH %@ AND value CONTAINS %@ AND enabled == true",
                initialBindingReadyValue ?? "",
                "ready;",
                "identity=exact"
            ),
            object: bindingReady
        )
        guard XCTWaiter().wait(
            for: [started, runtimeStarted, routeBindingReady],
            timeout: 5
        ) == .completed else {
            let failureValue = failureDiagnostic.exists
                ? String(describing: failureDiagnostic.value)
                : "none"
            let choiceValue = choiceDiagnostic.exists
                ? String(describing: choiceDiagnostic.value)
                : "none"
            let bindingValue = String(describing: bindingReady.value)
            XCTFail(
                "Phase: \(String(describing: phaseState.value)); runtime: "
                    + "\(String(describing: runtimeState.value)); failure: "
                    + failureValue + "; choice: " + choiceValue
                    + "; binding: " + bindingValue
            )
            return
        }

        // The signed baseline crop is (0.15, 0.15, 0.70, 0.70). Project the
        // first two authored master anchors (0.30, 0.54) and (0.43, 0.52)
        // through that crop, then address the actual scene surface rather
        // than assuming it fills the application after the narrative scroll.
        let firstOceanAnchor = touchSurface.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.2142857,
                dy: 0.5571429
            )
        )
        let secondOceanAnchor = touchSurface.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.4,
                dy: 0.5285714
            )
        )
        firstOceanAnchor.press(
            forDuration: 0.15,
            thenDragTo: secondOceanAnchor
        )

        // The drag crosses the first two anchors. A transport-level duplicate
        // endpoint is filtered before the reducer, so the final authored
        // response remains progress rather than invented resistance.
        let runtimeEngaged = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value CONTAINS %@ AND value CONTAINS %@ AND value CONTAINS %@ AND enabled == true",
                "playback=playing;stage=interaction",
                "lastEphemeral=engaged",
                "pause=none"
            ),
            object: runtimeState
        )
        let semanticAdvanced = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value == %@ AND enabled == true",
                "2 of 4 route points reached"
            ),
            object: semanticTrace
        )
        let result = XCTWaiter().wait(
            for: [runtimeEngaged, semanticAdvanced],
            timeout: 8
        )
        let failureValue: String
        if failureDiagnostic.exists {
            failureValue = String(describing: failureDiagnostic.value)
        } else {
            failureValue = "absent"
        }
        let choiceValue: String
        if choiceDiagnostic.exists {
            choiceValue = String(describing: choiceDiagnostic.value)
        } else {
            choiceValue = "absent"
        }
        let bindingValue = String(describing: bindingReady.value)
        let inputAdmissionValue = String(
            describing: inputAdmissionDiagnostic.value
        )
        let inputResolutionValue = String(
            describing: inputResolutionDiagnostic.value
        )
        let assertionContext =
            "Phase: \(String(describing: phaseState.value)); runtime: "
                + "\(String(describing: runtimeState.value)); semantic: "
                + "\(String(describing: semanticTrace.value)); failure: "
                + failureValue + "; choice: " + choiceValue
                + "; binding: " + bindingValue
                + "; input: " + inputAdmissionValue
                + "; resolution: " + inputResolutionValue
        XCTAssertEqual(
            result,
            .completed,
            assertionContext
        )
        XCTAssertTrue(
            (phaseState.value as? String)?.hasPrefix("playing:") == true,
            assertionContext
        )
        XCTAssertEqual(
            semanticTrace.value as? String,
            "2 of 4 route points reached",
            assertionContext
        )
        XCTAssertFalse(failureDiagnostic.exists, assertionContext)
    }

    func testContentAuthorityWaitsForAcceptedTraceAndRebasesPhysicalPause()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            "--ui-testing-content-authority-barrier",
        ]
        app.launch()

        let route = app.descendants(matching: .any)[
            "chapter-runtime-european-world"
        ]
        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let touchSurface = app.descendants(matching: .any)[
            "chapter-touch-surface"
        ]
        let semanticTrace = app.descendants(matching: .any)[
            "chapter-semantic-trace-ocean-route"
        ]
        let barrier = app.descendants(matching: .any)[
            "content-authority-barrier-diagnostic"
        ]
        let finalAdmission = app.descendants(matching: .any)[
            "content-authority-final-admission-diagnostic"
        ]
        let failure = app.descendants(matching: .any)[
            "signed-runtime-failure-diagnostic"
        ]
        XCTAssertTrue(route.waitForExistence(timeout: 12))
        XCTAssertTrue(beat.waitForExistence(timeout: 5))
        XCTAssertTrue(touchSurface.waitForExistence(timeout: 3))
        XCTAssertTrue(semanticTrace.waitForExistence(timeout: 3))
        XCTAssertTrue(barrier.waitForExistence(timeout: 3))
        XCTAssertTrue(finalAdmission.waitForExistence(timeout: 3))

        performEuropeanWorldPhysicalTrace(on: touchSurface)

        let expectedTrace =
            "reserved:r1>desired:r2>perform:r1>presented:r1>"
                + "published:r2,gate:r2>refreshed:r2"
        wait(for: barrier, toHaveValue: expectedTrace, timeout: 12)
        wait(
            for: semanticTrace,
            toHaveValue: "1 of 4 route points reached",
            timeout: 8
        )
        let exactAdmission = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ "
                        + "AND value CONTAINS %@ AND enabled == true",
                "identity=exact",
                "physicalPause=0",
                "reservations=0"
            ),
            object: finalAdmission
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [exactAdmission], timeout: 8),
            .completed,
            "Barrier: \(String(describing: barrier.value)); admission: "
                + "\(String(describing: finalAdmission.value)); semantic: "
                + "\(String(describing: semanticTrace.value)); failure: "
                + "\(String(describing: failure.value))"
        )
        XCTAssertFalse(failure.exists)
    }

    func testAuthorityQuiesceFailureRecoversWithoutExternalWakeAndKeepsRouteSafe()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            "--ui-testing-content-authority-quiesce-recovery",
        ]
        app.launch()

        let route = app.descendants(matching: .any)[
            "chapter-runtime-european-world"
        ]
        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let touchSurface = app.descendants(matching: .any)[
            "chapter-touch-surface"
        ]
        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let semanticTrace = app.descendants(matching: .any)[
            "chapter-semantic-trace-ocean-route"
        ]
        let barrier = app.descendants(matching: .any)[
            "global-content-authority-barrier-diagnostic"
        ]
        let audioAudit = app.descendants(matching: .any)[
            "global-content-authority-audio-diagnostic"
        ]
        let lifecycle = app.descendants(matching: .any)[
            "global-causal-lifecycle-state"
        ]
        let finalAdmission = app.descendants(matching: .any)[
            "content-authority-final-admission-diagnostic"
        ]
        XCTAssertTrue(route.waitForExistence(timeout: 12))
        XCTAssertTrue(beat.waitForExistence(timeout: 5))
        XCTAssertTrue(touchSurface.waitForExistence(timeout: 3))
        XCTAssertTrue(phaseState.waitForExistence(timeout: 3))
        XCTAssertTrue(semanticTrace.waitForExistence(timeout: 3))
        XCTAssertTrue(barrier.waitForExistence(timeout: 3))
        XCTAssertTrue(audioAudit.waitForExistence(timeout: 3))
        XCTAssertTrue(lifecycle.waitForExistence(timeout: 3))
        XCTAssertTrue(finalAdmission.waitForExistence(timeout: 3))

        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        soundControl.tap()
        let playingOrResume = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value == %@ OR value == %@",
                "playing:waiting",
                "resumeRequired:waiting"
            ),
            object: phaseState
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [playingOrResume], timeout: 8),
            .completed,
            String(describing: phaseState.value)
        )
        if phaseState.value as? String == "resumeRequired:waiting" {
            soundControl.tap()
        }
        wait(for: phaseState, toHaveValue: "playing:waiting", timeout: 8)

        // No lifecycle activation, retry tap or route action follows this
        // input. The authority handoff must recover its own failed transport
        // quiescence and publish the desired verified revision.
        performEuropeanWorldPhysicalTrace(on: touchSurface)

        wait(
            for: barrier,
            toHaveValue:
                "reserved:r1>desired:r2>perform:r1>presented:r1>"
                    + "quiesce:failed>quiesce:recovered>"
                    + "published:r2,gate:none",
            timeout: 12
        )
        wait(
            for: semanticTrace,
            toHaveValue: "1 of 4 route points reached",
            timeout: 8
        )
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND value CONTAINS %@",
                "route=chapter:european-world",
                "accepted=r2",
                "desired=r2",
                "retry=0",
                "episode=none",
                "physicalPause=0",
                "reservations=0",
                "chapterPending=0"
            ),
            object: lifecycle
        )
        let exactAdmission = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND enabled == true",
                "identity=exact",
                "physicalPause=0",
                "reservations=0"
            ),
            object: finalAdmission
        )
        XCTAssertEqual(
            XCTWaiter().wait(
                for: [settled, exactAdmission],
                timeout: 8
            ),
            .completed,
            "Barrier: \(String(describing: barrier.value)); lifecycle: "
                + "\(String(describing: lifecycle.value)); admission: "
                + String(describing: finalAdmission.value)
        )

        wait(
            for: audioAudit,
            toHaveValueContaining: ";final=1",
            timeout: 8
        )
        let audioAuditValue = try XCTUnwrap(audioAudit.value as? String)
        let audioFields = Self.diagnosticFields(
            in: audioAuditValue.split(separator: ";").map(String.init)[...]
        )
        XCTAssertEqual(audioFields["mode"], "recovery")
        XCTAssertEqual(audioFields["transportPaused"], "1")
        XCTAssertEqual(audioFields["controllerSwapped"], "0")
        XCTAssertEqual(audioFields["stale"], "0")
        XCTAssertEqual(audioFields["appendDelta"], "1")
        XCTAssertEqual(audioFields["capturedExists"], "1")
        XCTAssertEqual(audioFields["capturedIdentityEqualsPre"], "1")
        XCTAssertEqual(audioFields["fallbackEqualsPre"], "1")
        XCTAssertEqual(audioFields["committedEqualsFallback"], "1")
        XCTAssertEqual(
            audioFields["fallbackIdentity"],
            audioFields["preIdentity"]
        )
        XCTAssertEqual(
            audioFields["committedIdentity"],
            audioFields["preIdentity"]
        )
        let preCursor = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(audioFields["pre"])
            )
        )
        let partialCursor = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(audioFields["partial"])
            )
        )
        let capturedCursor = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(audioFields["captured"])
            )
        )
        let fallbackCursor = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(audioFields["fallback"])
            )
        )
        let committedCursor = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(audioFields["committed"])
            )
        )
        XCTAssertTrue(
            partialCursor.isStrictlyAfter(preCursor),
            "The real paused transport must expose a later valid cursor: "
                + audioAuditValue
        )
        XCTAssertEqual(fallbackCursor, preCursor)
        XCTAssertEqual(capturedCursor, preCursor)
        XCTAssertEqual(committedCursor, preCursor)
        XCTAssertNotEqual(committedCursor, partialCursor)
        let sequenceBefore = try XCTUnwrap(
            audioFields["sequenceBefore"].flatMap(UInt64.init)
        )
        let sequenceAfter = try XCTUnwrap(
            audioFields["sequenceAfter"].flatMap(UInt64.init)
        )
        XCTAssertEqual(sequenceAfter, sequenceBefore + 1)

        // A normal route boundary after recovery must use r2 authority and
        // must not revive stale pre-recovery authority or a deferred retry.
        let returnToRoad = app.buttons["chapter-road"].firstMatch
        XCTAssertTrue(returnToRoad.waitForExistence(timeout: 3))
        XCTAssertTrue(returnToRoad.isEnabled)
        returnToRoad.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["living-world-field"]
                .waitForExistence(timeout: 12),
            "Barrier: \(String(describing: barrier.value)); lifecycle: "
                + String(describing: lifecycle.value)
        )
        let worldSettled = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND value CONTAINS %@",
                "route=world",
                "accepted=r2",
                "retry=0",
                "ordered=0"
            ),
            object: lifecycle
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [worldSettled], timeout: 8),
            .completed,
            "Barrier: \(String(describing: barrier.value)); lifecycle: "
                + String(describing: lifecycle.value)
        )
    }

    func testOrderedExitRejectsPostPauseCursorAcrossPumpAndAuthorityPublication()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            "--ui-testing-ordered-exit-quiesce-recovery",
        ]
        app.launch()

        let route = app.descendants(matching: .any)[
            "chapter-runtime-european-world"
        ]
        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let orderedAudit = app.descendants(matching: .any)[
            "ordered-exit-audio-diagnostic"
        ]
        let lifecycle = app.descendants(matching: .any)[
            "global-causal-lifecycle-state"
        ]
        XCTAssertTrue(route.waitForExistence(timeout: 12))
        XCTAssertTrue(beat.waitForExistence(timeout: 5))
        XCTAssertTrue(phaseState.waitForExistence(timeout: 3))
        XCTAssertTrue(orderedAudit.waitForExistence(timeout: 3))
        XCTAssertTrue(lifecycle.waitForExistence(timeout: 3))

        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        soundControl.tap()
        let playingOrResume = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value == %@ OR value == %@",
                "playing:waiting",
                "resumeRequired:waiting"
            ),
            object: phaseState
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [playingOrResume], timeout: 8),
            .completed,
            String(describing: phaseState.value)
        )
        if phaseState.value as? String == "resumeRequired:waiting" {
            soundControl.tap()
        }
        wait(for: phaseState, toHaveValue: "playing:waiting", timeout: 8)

        let returnToRoad = app.buttons["chapter-road"].firstMatch
        XCTAssertTrue(returnToRoad.waitForExistence(timeout: 3))
        XCTAssertTrue(returnToRoad.isEnabled)
        returnToRoad.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["living-world-field"]
                .waitForExistence(timeout: 12),
            "Audit: \(String(describing: orderedAudit.value)); lifecycle: "
                + String(describing: lifecycle.value)
        )
        wait(
            for: orderedAudit,
            toHaveValueContaining: ";final=1",
            timeout: 12
        )
        let authoritySettled = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@",
                "route=world",
                "accepted=r2",
                "desired=r2",
                "retry=0",
                "ordered=0"
            ),
            object: lifecycle
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [authoritySettled], timeout: 12),
            .completed,
            "Audit: \(String(describing: orderedAudit.value)); lifecycle: "
                + String(describing: lifecycle.value)
        )

        var auditValue = try XCTUnwrap(orderedAudit.value as? String)
        var fields = Self.diagnosticFields(
            in: auditValue.split(separator: ";").map(String.init)[...]
        )
        for (field, expected) in [
            "mode": "ordered-exit",
            "transportPaused": "1",
            "fallbackRecovered": "1",
            "controllerDiscarded": "0",
            "cursorRetired": "1",
            "pumpStopped": "1",
            "authorityRequested": "1",
            "authorityPublished": "1",
            "actorRecoveryQueried": "1",
            "partialCommitted": "0",
            "partialInSidecar": "0",
            "route": "world",
            "final": "1",
        ] {
            XCTAssertEqual(fields[field], expected, auditValue)
        }
        XCTAssertEqual(fields["preIdentity"], fields["fallbackIdentity"])
        XCTAssertEqual(
            fields["preIdentity"],
            fields["committedIdentity"]
        )
        let pre = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(fields["pre"])
            )
        )
        let partial = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(fields["partial"])
            )
        )
        let fallback = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(fields["fallback"])
            )
        )
        let committed = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(fields["committed"])
            )
        )
        let sidecar = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(fields["sidecar"])
            )
        )
        XCTAssertTrue(partial.isStrictlyAfter(pre), auditValue)
        XCTAssertEqual(fallback, pre, auditValue)
        XCTAssertEqual(committed, pre, auditValue)
        XCTAssertNotEqual(sidecar, partial, auditValue)
        XCTAssertTrue(pre.isAtOrAfter(sidecar), auditValue)
        let sequenceBefore = try XCTUnwrap(
            fields["sequenceBefore"].flatMap(UInt64.init)
        )
        let sequenceAfter = try XCTUnwrap(
            fields["sequenceAfter"].flatMap(UInt64.init)
        )
        XCTAssertEqual(sequenceAfter, sequenceBefore + 2, auditValue)

        // Leave a full pump interval after route recovery and authority
        // publication. A latent writer must still be unable to promote c1.
        let pumpTickWindow = expectation(description: "pump tick window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            pumpTickWindow.fulfill()
        }
        wait(for: [pumpTickWindow], timeout: 2)
        auditValue = try XCTUnwrap(orderedAudit.value as? String)
        fields = Self.diagnosticFields(
            in: auditValue.split(separator: ";").map(String.init)[...]
        )
        XCTAssertEqual(fields["partialCommitted"], "0", auditValue)
        XCTAssertEqual(fields["partialInSidecar"], "0", auditValue)
        XCTAssertEqual(fields["committed"], String(describing: pre))
        let settledSidecar = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(fields["sidecar"])
            )
        )
        XCTAssertNotEqual(settledSidecar, partial, auditValue)
        XCTAssertTrue(pre.isAtOrAfter(settledSidecar), auditValue)
    }

    func testOrderedExitColdRestoreRecoversC0AndNeverPostPauseC1()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            "--ui-testing-ordered-exit-quiesce-recovery",
            "--ui-testing-ordered-exit-skip-authority-publication",
        ]
        app.launch()

        let route = app.descendants(matching: .any)[
            "chapter-runtime-european-world"
        ]
        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let orderedAudit = app.descendants(matching: .any)[
            "ordered-exit-audio-diagnostic"
        ]
        XCTAssertTrue(route.waitForExistence(timeout: 12))
        XCTAssertTrue(beat.waitForExistence(timeout: 5))
        XCTAssertTrue(phaseState.waitForExistence(timeout: 3))
        XCTAssertTrue(orderedAudit.waitForExistence(timeout: 3))

        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        soundControl.tap()
        wait(for: phaseState, toHaveValue: "playing:waiting", timeout: 8)
        let returnToRoad = app.buttons["chapter-road"].firstMatch
        XCTAssertTrue(returnToRoad.waitForExistence(timeout: 3))
        returnToRoad.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["living-world-field"]
                .waitForExistence(timeout: 12)
        )
        wait(
            for: orderedAudit,
            toHaveValueContaining: ";final=1",
            timeout: 8
        )
        let auditValue = try XCTUnwrap(orderedAudit.value as? String)
        let fields = Self.diagnosticFields(
            in: auditValue.split(separator: ";").map(String.init)[...]
        )
        XCTAssertEqual(fields["fallbackRecovered"], "1", auditValue)
        XCTAssertEqual(fields["cursorRetired"], "1", auditValue)
        XCTAssertEqual(fields["pumpStopped"], "1", auditValue)
        XCTAssertEqual(fields["actorRecoveryQueried"], "1", auditValue)
        XCTAssertEqual(fields["authorityRequested"], "0", auditValue)
        XCTAssertEqual(fields["partialCommitted"], "0", auditValue)
        XCTAssertEqual(fields["partialInSidecar"], "0", auditValue)
        let pre = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(fields["pre"])
            )
        )
        let partial = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(fields["partial"])
            )
        )
        XCTAssertTrue(partial.isStrictlyAfter(pre), auditValue)
        XCTAssertEqual(fields["committed"], String(describing: pre))
        XCTAssertNotEqual(fields["sidecar"], String(describing: partial))

        // Reopen from disk. The controller, the journal cursor and the
        // recoverable sidecar-derived cursor must all restore c0, never c1.
        app.terminate()
        app.launchArguments = [
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
        ]
        app.launch()
        XCTAssertTrue(route.waitForExistence(timeout: 12))
        let runtime = app.descendants(matching: .any)[
            "global-responsive-audio-runtime-state"
        ]
        XCTAssertTrue(runtime.waitForExistence(timeout: 3))
        let restoredC0 = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@",
                "liveCursor=\(pre)",
                "durableCursor=\(pre)",
                "journalCursor=\(pre)"
            ),
            object: runtime
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [restoredC0], timeout: 8),
            .completed,
            String(describing: runtime.value)
        )
        let restoredRuntime = try XCTUnwrap(runtime.value as? String)
        let restoredFields = Self.diagnosticFields(
            in: restoredRuntime.split(separator: ";").map(String.init)[...]
        )
        for key in ["liveCursor", "durableCursor", "journalCursor"] {
            let cursor = try XCTUnwrap(
                try Self.parseResponsiveAudioCursor(
                    try XCTUnwrap(restoredFields[key])
                )
            )
            XCTAssertEqual(cursor, pre, restoredRuntime)
            XCTAssertNotEqual(cursor, partial, restoredRuntime)
        }
    }

    func testFailedConsequenceRelinquishStopsMutedGraphAndRetiresCursor()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            "--ui-testing-ordered-exit-quiesce-recovery",
            "--ui-testing-ordered-exit-consequence-relinquish-failure",
        ]
        app.launch()

        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let touchSurface = app.descendants(matching: .any)[
            "chapter-touch-surface"
        ]
        let semanticTrace = app.descendants(matching: .any)[
            "chapter-semantic-trace-ocean-route"
        ]
        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let audit = app.descendants(matching: .any)[
            "ordered-exit-audio-diagnostic"
        ]
        let lifecycle = app.descendants(matching: .any)[
            "global-causal-lifecycle-state"
        ]
        let runtime = app.descendants(matching: .any)[
            "global-responsive-audio-runtime-state"
        ]
        XCTAssertTrue(beat.waitForExistence(timeout: 12))
        XCTAssertTrue(touchSurface.waitForExistence(timeout: 5))
        XCTAssertTrue(semanticTrace.waitForExistence(timeout: 3))
        XCTAssertTrue(phaseState.waitForExistence(timeout: 3))
        XCTAssertTrue(audit.waitForExistence(timeout: 3))
        XCTAssertTrue(lifecycle.waitForExistence(timeout: 3))
        XCTAssertTrue(runtime.waitForExistence(timeout: 3))

        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        soundControl.tap()
        resumeResponsiveAudioIfNeeded(
            phaseState: phaseState,
            soundControl: soundControl
        )
        wait(for: phaseState, toHaveValue: "playing:waiting", timeout: 8)

        let anchors = [
            CGVector(dx: 0.2142857, dy: 0.5571429),
            CGVector(dx: 0.4, dy: 0.5285714),
            CGVector(dx: 0.6, dy: 0.5),
            CGVector(dx: 0.7857143, dy: 0.4714286),
        ].map { touchSurface.coordinate(withNormalizedOffset: $0) }
        anchors[0].press(forDuration: 0.15, thenDragTo: anchors[1])
        wait(
            for: semanticTrace,
            toHaveValue: "2 of 4 route points reached",
            timeout: 8
        )
        anchors[1].press(forDuration: 0.1, thenDragTo: anchors[2])
        wait(
            for: semanticTrace,
            toHaveValue: "3 of 4 route points reached",
            timeout: 8
        )
        anchors[2].press(forDuration: 0.1, thenDragTo: anchors[3])

        let consequencePlaying = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND enabled == true",
                "playback=playing",
                "stage=consequence"
            ),
            object: runtime
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [consequencePlaying], timeout: 10),
            .completed,
            String(describing: runtime.value)
        )

        let returnToRoad = app.buttons["chapter-road"].firstMatch
        XCTAssertTrue(returnToRoad.waitForExistence(timeout: 3))
        returnToRoad.tap()

        wait(for: audit, toHaveValueContaining: ";final=1", timeout: 12)
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@",
                "route=chapter:european-world",
                "ordered=0",
                "chapterPending=0"
            ),
            object: lifecycle
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [settled], timeout: 8),
            .completed,
            "Audit: \(String(describing: audit.value)); lifecycle: "
                + String(describing: lifecycle.value)
        )
        let graphStopped = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "NOT (value CONTAINS %@) AND enabled == true",
                "playback=playing"
            ),
            object: runtime
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [graphStopped], timeout: 3),
            .completed,
            String(describing: runtime.value)
        )

        let auditValue = try XCTUnwrap(audit.value as? String)
        let fields = Self.diagnosticFields(
            in: auditValue.split(separator: ";").map(String.init)[...]
        )
        for (field, expected) in [
            "transportPaused": "0",
            "fallbackRecovered": "0",
            "controllerDiscarded": "1",
            "cursorRetired": "1",
            "pumpStopped": "1",
            "appendDelta": "0",
            "route": "chapter",
            "final": "1",
        ] {
            XCTAssertEqual(fields[field], expected, auditValue)
        }
        XCTAssertEqual(fields["sequenceBefore"], fields["sequenceAfter"])
    }

    func testOrderedExitRetirementPreservesInstalledSuccessorAndBinding()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            "--ui-testing-ordered-exit-quiesce-recovery",
            "--ui-testing-ordered-exit-skip-authority-publication",
            "--ui-testing-ordered-exit-controller-swap-during-retirement",
        ]
        app.launch()

        let route = app.descendants(matching: .any)[
            "chapter-runtime-european-world"
        ]
        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let audit = app.descendants(matching: .any)[
            "ordered-exit-audio-diagnostic"
        ]
        let lifecycle = app.descendants(matching: .any)[
            "global-causal-lifecycle-state"
        ]
        let runtime = app.descendants(matching: .any)[
            "global-responsive-audio-runtime-state"
        ]
        XCTAssertTrue(route.waitForExistence(timeout: 12))
        XCTAssertTrue(beat.waitForExistence(timeout: 5))
        XCTAssertTrue(phaseState.waitForExistence(timeout: 3))
        XCTAssertTrue(audit.waitForExistence(timeout: 3))
        XCTAssertTrue(lifecycle.waitForExistence(timeout: 3))
        XCTAssertTrue(runtime.waitForExistence(timeout: 3))

        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        soundControl.tap()
        resumeResponsiveAudioIfNeeded(
            phaseState: phaseState,
            soundControl: soundControl
        )
        let returnToRoad = app.buttons["chapter-road"].firstMatch
        XCTAssertTrue(returnToRoad.waitForExistence(timeout: 3))
        returnToRoad.tap()

        wait(for: audit, toHaveValueContaining: ";final=1", timeout: 12)
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@",
                "route=chapter:european-world",
                "ordered=0",
                "chapterPending=0"
            ),
            object: lifecycle
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [settled], timeout: 8),
            .completed,
            "Audit: \(String(describing: audit.value)); lifecycle: "
                + String(describing: lifecycle.value)
        )

        let auditValue = try XCTUnwrap(audit.value as? String)
        let fields = Self.diagnosticFields(
            in: auditValue.split(separator: ";").map(String.init)[...]
        )
        for (field, expected) in [
            "transportPaused": "1",
            "fallbackRecovered": "1",
            "controllerDiscarded": "0",
            "successorInstalled": "1",
            "successorPreserved": "1",
            "bindingIdentityPreserved": "1",
            "partialCommitted": "0",
            "route": "chapter",
            "final": "1",
        ] {
            XCTAssertEqual(fields[field], expected, auditValue)
        }
        XCTAssertEqual(fields["sequenceBefore"], fields["sequenceAfter"])
        XCTAssertEqual(fields["appendDelta"], "0", auditValue)
        let runtimeValue = try XCTUnwrap(runtime.value as? String)
        XCTAssertTrue(runtimeValue.contains("binding=2"), runtimeValue)
        XCTAssertTrue(runtimeValue.contains("playback=paused"), runtimeValue)
    }

    func testOrderedExitCleanupPreservesPreinstallSuccessorLifecycle()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            "--ui-testing-ordered-exit-quiesce-recovery",
            "--ui-testing-ordered-exit-skip-authority-publication",
            "--ui-testing-ordered-exit-preinstall-successor-during-retirement",
        ]
        app.launch()

        let route = app.descendants(matching: .any)[
            "chapter-runtime-european-world"
        ]
        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let audit = app.descendants(matching: .any)[
            "ordered-exit-audio-diagnostic"
        ]
        let lifecycle = app.descendants(matching: .any)[
            "global-causal-lifecycle-state"
        ]
        XCTAssertTrue(route.waitForExistence(timeout: 12))
        XCTAssertTrue(beat.waitForExistence(timeout: 5))
        XCTAssertTrue(phaseState.waitForExistence(timeout: 3))
        XCTAssertTrue(audit.waitForExistence(timeout: 3))
        XCTAssertTrue(lifecycle.waitForExistence(timeout: 3))

        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        soundControl.tap()
        resumeResponsiveAudioIfNeeded(
            phaseState: phaseState,
            soundControl: soundControl
        )
        let returnToRoad = app.buttons["chapter-road"].firstMatch
        XCTAssertTrue(returnToRoad.waitForExistence(timeout: 3))
        returnToRoad.tap()

        wait(for: audit, toHaveValueContaining: ";final=1", timeout: 12)
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@",
                "route=chapter:european-world",
                "ordered=0",
                "chapterPending=0"
            ),
            object: lifecycle
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [settled], timeout: 8),
            .completed,
            "Audit: \(String(describing: audit.value)); lifecycle: "
                + String(describing: lifecycle.value)
        )
        let auditValue = try XCTUnwrap(audit.value as? String)
        let fields = Self.diagnosticFields(
            in: auditValue.split(separator: ";").map(String.init)[...]
        )
        for (field, expected) in [
            "transportPaused": "1",
            "fallbackRecovered": "1",
            "controllerDiscarded": "1",
            "successorInstalled": "0",
            "bindingIdentityPreserved": "1",
            "preinstallSuccessorArmed": "1",
            "preinstallSuccessorPreserved": "1",
            "partialCommitted": "0",
            "route": "chapter",
            "final": "1",
        ] {
            XCTAssertEqual(fields[field], expected, auditValue)
        }
        XCTAssertEqual(fields["sequenceBefore"], fields["sequenceAfter"])
        XCTAssertEqual(fields["appendDelta"], "0", auditValue)
    }

    func testAuthorityRetirementRejectsSnapshotFromControllerSwappedDuringAwait()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            "--ui-testing-content-authority-stale-controller-swap",
        ]
        app.launch()

        let route = app.descendants(matching: .any)[
            "chapter-runtime-european-world"
        ]
        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let touchSurface = app.descendants(matching: .any)[
            "chapter-touch-surface"
        ]
        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let semanticTrace = app.descendants(matching: .any)[
            "chapter-semantic-trace-ocean-route"
        ]
        let barrier = app.descendants(matching: .any)[
            "global-content-authority-barrier-diagnostic"
        ]
        let audioAudit = app.descendants(matching: .any)[
            "global-content-authority-audio-diagnostic"
        ]
        let lifecycle = app.descendants(matching: .any)[
            "global-causal-lifecycle-state"
        ]
        let finalAdmission = app.descendants(matching: .any)[
            "content-authority-final-admission-diagnostic"
        ]
        XCTAssertTrue(route.waitForExistence(timeout: 12))
        XCTAssertTrue(beat.waitForExistence(timeout: 5))
        XCTAssertTrue(touchSurface.waitForExistence(timeout: 3))
        XCTAssertTrue(phaseState.waitForExistence(timeout: 3))
        XCTAssertTrue(semanticTrace.waitForExistence(timeout: 3))
        XCTAssertTrue(barrier.waitForExistence(timeout: 3))
        XCTAssertTrue(audioAudit.waitForExistence(timeout: 3))
        XCTAssertTrue(lifecycle.waitForExistence(timeout: 3))
        XCTAssertTrue(finalAdmission.waitForExistence(timeout: 3))

        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        soundControl.tap()
        wait(for: phaseState, toHaveValue: "playing:waiting", timeout: 8)
        performEuropeanWorldPhysicalTrace(on: touchSurface)

        wait(
            for: barrier,
            toHaveValue:
                "reserved:r1>desired:r2>perform:r1>presented:r1>"
                    + "retire:suspended>controller:swapped>retire:resumed>"
                    + "quiesce:stale>quiesce:journal-skipped>"
                    + "published:r2,gate:none",
            timeout: 12
        )
        wait(
            for: semanticTrace,
            toHaveValue: "1 of 4 route points reached",
            timeout: 8
        )
        wait(
            for: audioAudit,
            toHaveValueContaining: ";final=1",
            timeout: 8
        )
        let audioAuditValue = try XCTUnwrap(audioAudit.value as? String)
        let audioFields = Self.diagnosticFields(
            in: audioAuditValue.split(separator: ";").map(String.init)[...]
        )
        XCTAssertEqual(audioFields["mode"], "stale")
        XCTAssertEqual(audioFields["controllerSwapped"], "1")
        XCTAssertEqual(audioFields["stale"], "1")
        XCTAssertEqual(audioFields["appendDelta"], "0")
        XCTAssertEqual(audioFields["partial"], "none")
        XCTAssertEqual(audioFields["fallback"], "none")
        XCTAssertEqual(audioFields["capturedExists"], "1")
        XCTAssertEqual(audioFields["capturedIdentityEqualsPre"], "1")
        XCTAssertEqual(audioFields["committedEqualsBaseline"], "1")
        XCTAssertEqual(
            audioFields["capturedIdentity"],
            audioFields["preIdentity"]
        )
        XCTAssertEqual(
            audioFields["committedIdentity"],
            audioFields["baselineIdentity"]
        )
        let preCursor = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(audioFields["pre"])
            )
        )
        let capturedCursor = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(audioFields["captured"])
            )
        )
        let baselineCursor = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(audioFields["baseline"])
            )
        )
        let committedCursor = try XCTUnwrap(
            try Self.parseResponsiveAudioCursor(
                try XCTUnwrap(audioFields["committed"])
            )
        )
        XCTAssertTrue(capturedCursor.isStrictlyAfter(preCursor))
        XCTAssertTrue(capturedCursor.isStrictlyAfter(baselineCursor))
        XCTAssertEqual(committedCursor, baselineCursor)
        let sequenceBefore = try XCTUnwrap(
            audioFields["sequenceBefore"].flatMap(UInt64.init)
        )
        let sequenceAfter = try XCTUnwrap(
            audioFields["sequenceAfter"].flatMap(UInt64.init)
        )
        XCTAssertEqual(sequenceAfter, sequenceBefore)

        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND value CONTAINS %@",
                "route=chapter:european-world",
                "accepted=r2",
                "desired=r2",
                "retry=0",
                "reservations=0",
                "chapterPending=0"
            ),
            object: lifecycle
        )
        let exactAdmission = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND enabled == true",
                "identity=exact",
                "physicalPause=0",
                "reservations=0"
            ),
            object: finalAdmission
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [settled, exactAdmission], timeout: 8),
            .completed,
            "Barrier: \(String(describing: barrier.value)); audio: "
                + "\(audioAuditValue); lifecycle: "
                + String(describing: lifecycle.value)
        )
    }

    func testFailedPhysicalPauseAppendRestoresAndAcceptsNextTrace()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            "--ui-testing-suspension-persistence-retry",
        ]
        app.launch()

        let route = app.descendants(matching: .any)[
            "chapter-runtime-european-world"
        ]
        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let touchSurface = app.descendants(matching: .any)[
            "chapter-touch-surface"
        ]
        let semanticTrace = app.descendants(matching: .any)[
            "chapter-semantic-trace-ocean-route"
        ]
        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let retryTrace = app.descendants(matching: .any)[
            "suspension-persistence-retry-diagnostic"
        ]
        let globalRuntime = app.descendants(matching: .any)[
            "global-responsive-audio-runtime-state"
        ]
        let globalLifecycle = app.descendants(matching: .any)[
            "global-causal-lifecycle-state"
        ]
        XCTAssertTrue(route.waitForExistence(timeout: 12))
        XCTAssertTrue(beat.waitForExistence(timeout: 5))
        XCTAssertTrue(touchSurface.waitForExistence(timeout: 3))
        XCTAssertTrue(semanticTrace.waitForExistence(timeout: 3))
        XCTAssertTrue(retryTrace.waitForExistence(timeout: 3))
        XCTAssertTrue(globalRuntime.waitForExistence(timeout: 3))
        XCTAssertTrue(globalLifecycle.waitForExistence(timeout: 3))

        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        soundControl.tap()
        wait(for: phaseState, toHaveValue: "playing:waiting", timeout: 8)

        performEuropeanWorldPhysicalTrace(on: touchSurface)

        XCTAssertTrue(
            app.descendants(matching: .any)["persistence-failure"]
                .waitForExistence(timeout: 12),
            "Retry trace: \(String(describing: retryTrace.value)); runtime: "
                + "\(String(describing: globalRuntime.value)); lifecycle: "
                + String(describing: globalLifecycle.value)
        )
        wait(
            for: retryTrace,
            toHaveValue: "reserved>pause-requested>append-failed",
            timeout: 8
        )
        wait(
            for: globalRuntime,
            toHaveValueContaining: "pause=audioRouteChange",
            timeout: 8
        )
        wait(
            for: globalRuntime,
            toHaveValueContaining: "episodeResult=failed",
            timeout: 8
        )

        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        retry.tap()

        XCTAssertTrue(route.waitForExistence(timeout: 12))
        XCTAssertTrue(beat.waitForExistence(timeout: 5))
        XCTAssertTrue(touchSurface.waitForExistence(timeout: 3))
        XCTAssertTrue(semanticTrace.waitForExistence(timeout: 3))
        wait(
            for: retryTrace,
            toHaveValue:
                "reserved>pause-requested>append-failed>restored",
            timeout: 8
        )
        wait(
            for: semanticTrace,
            toHaveValue: "1 of 4 route points reached",
            timeout: 8
        )

        let finalAdmission = app.descendants(matching: .any)[
            "content-authority-final-admission-diagnostic"
        ]
        XCTAssertTrue(finalAdmission.waitForExistence(timeout: 3))
        let recovered = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND value CONTAINS %@",
                "episode=none",
                "episodeResult=none",
                "physicalPause=0",
                "reservations=0"
            ),
            object: globalLifecycle
        )
        let exactAdmission = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@",
                "identity=exact",
                "physicalPause=0",
                "reservations=0"
            ),
            object: finalAdmission
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [recovered, exactAdmission], timeout: 8),
            .completed,
            "Retry: \(String(describing: retryTrace.value)); lifecycle: "
                + "\(String(describing: globalLifecycle.value)); admission: "
                + String(describing: finalAdmission.value)
        )

        performEuropeanWorldPhysicalTrace(on: touchSurface)
        wait(
            for: semanticTrace,
            toHaveValue: "2 of 4 route points reached",
            timeout: 8
        )
    }

    func testFailedPauseDefersAuthorityUntilRecoveryWorld() throws {
        try assertFailedPauseAuthorityRecovery(
            launchArgument:
                "--ui-testing-content-authority-failed-pause-recovery",
            expectedFinalTrace:
                "reserved:r1>e1:requested>desired:r2>perform:r1>"
                    + "presented:r1>e1:flush-failed>recovery:reserved>"
                    + "world:durable>transition:released>"
                    + "published:r2,gate:none"
        )
    }

    func testRecoveryReservationHoldsSecondPauseUntilWorldTransitionReleases()
        throws {
        let holdingTrace =
            "reserved:r1>e1:requested>desired:r2>perform:r1>"
                + "presented:r1>e1:flush-failed>recovery:reserved>"
                + "world:durable>e2:requested>e2:waiting>"
                + "recovery:holding"
        try assertFailedPauseAuthorityRecovery(
            launchArgument:
                "--ui-testing-content-authority-failed-pause-recovery-e2",
            expectedHoldingTrace: holdingTrace,
            expectedFinalTrace:
                holdingTrace + ">probe:released>transition:released>"
                    + "e2:admitted>e2:durable>published:r2,gate:none"
        )
    }

    func testResponsiveAudioSoundControlStartsWithoutModelPause() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
        ]
        app.launch()

        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let runtimeState = app.descendants(matching: .any)[
            "responsive-audio-runtime-state"
        ]
        let failureDiagnostic = app.descendants(matching: .any)[
            "signed-runtime-failure-diagnostic"
        ]
        let choiceDiagnostic = app.descendants(matching: .any)[
            "responsive-audio-choice-diagnostic"
        ]
        let bindingReady = app.descendants(matching: .any)[
            "responsive-audio-binding-ready"
        ]
        let oceanNarrative = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        XCTAssertTrue(phaseState.waitForExistence(timeout: 12))
        XCTAssertTrue(runtimeState.waitForExistence(timeout: 3))
        XCTAssertTrue(bindingReady.waitForExistence(timeout: 3))
        XCTAssertTrue(oceanNarrative.waitForExistence(timeout: 5))
        let initialBinding = try waitForResponsiveAudioBinding(
            bindingReady,
            stage: "presentation"
        )

        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        XCTAssertTrue(soundControl.isHittable)
        XCTAssertEqual(soundControl.label, "Resume sound")
        soundControl.tap()
        let completedBinding = try waitForResponsiveAudioBinding(
            bindingReady,
            stage: "after-hear",
            generation: initialBinding.generation,
            timeout: 8
        )
        wait(for: phaseState, toHaveValue: "playing:waiting")
        wait(
            for: runtimeState,
            toHaveValueContaining:
                "playback=playing;stage=interaction;phase=waiting;durable=waiting;pending=none;pause=none",
            timeout: 8
        )
        let runtime = try waitForResponsiveAudioPhysicalState(
            runtimeState,
            playback: "playing",
            pause: "none",
            timeout: 8
        )
        let failureValue: String
        if failureDiagnostic.exists {
            failureValue = String(describing: failureDiagnostic.value)
        } else {
            failureValue = "absent"
        }
        let choiceValue: String
        if choiceDiagnostic.exists {
            choiceValue = String(describing: choiceDiagnostic.value)
        } else {
            choiceValue = "absent"
        }
        let assertionContext =
            "Phase: \(String(describing: phaseState.value)); runtime: "
                + "\(String(describing: runtimeState.value)); failure: "
                + failureValue + "; choice: " + choiceValue
                + "; binding: \(String(describing: bindingReady.value))"
        XCTAssertEqual(
            phaseState.value as? String,
            "playing:waiting",
            assertionContext
        )
        XCTAssertEqual(completedBinding.status, "ready", assertionContext)
        XCTAssertEqual(completedBinding.stage, "after-hear", assertionContext)
        XCTAssertEqual(
            completedBinding.generation,
            initialBinding.generation,
            assertionContext
        )
        XCTAssertEqual(completedBinding.identity, "exact", assertionContext)
        XCTAssertEqual(runtime.playback, "playing", assertionContext)
        XCTAssertEqual(runtime.pause, "none", assertionContext)
        let liveCursor = try XCTUnwrap(runtime.liveCursor)
        let durableCursor = try XCTUnwrap(runtime.durableCursor)
        XCTAssertTrue(
            durableCursor.isAtOrAfter(liveCursor),
            "Durable cursor \(durableCursor) preceded synchronized cursor "
                + "\(liveCursor). \(assertionContext)"
        )
        XCTAssertEqual(
            choiceDiagnostic.value as? String,
            "playback-complete:playing",
            assertionContext
        )
        XCTAssertFalse(failureDiagnostic.exists, assertionContext)
    }

    func testSignedEuropeanWorldHomePauseRequiresExplicitCursorResume() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
        ]
        app.launch()

        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let runtimeState = app.descendants(matching: .any)[
            "responsive-audio-runtime-state"
        ]
        let bindingReady = app.descendants(matching: .any)[
            "responsive-audio-binding-ready"
        ]
        let failureDiagnostic = app.descendants(matching: .any)[
            "signed-runtime-failure-diagnostic"
        ]
        let oceanNarrative = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        XCTAssertTrue(phaseState.waitForExistence(timeout: 12))
        XCTAssertTrue(runtimeState.waitForExistence(timeout: 3))
        XCTAssertTrue(bindingReady.waitForExistence(timeout: 3))
        XCTAssertTrue(oceanNarrative.waitForExistence(timeout: 5))
        let initialBinding = try waitForResponsiveAudioBinding(
            bindingReady,
            stage: "presentation"
        )
        let initialRuntime = try waitForResponsiveAudioPlaybackState(
            runtimeState,
            playback: "paused",
            pause: "none"
        )
        let initialLiveCursor = try XCTUnwrap(initialRuntime.liveCursor)

        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        XCTAssertTrue(soundControl.isHittable)
        XCTAssertEqual(soundControl.label, "Resume sound")
        soundControl.tap()
        _ = try waitForResponsiveAudioBinding(
            bindingReady,
            stage: "after-hear",
            generation: initialBinding.generation,
            timeout: 8
        )
        wait(for: phaseState, toHaveValue: "playing:waiting", timeout: 8)
        let advancing = try waitForResponsiveAudioCursorAdvance(
            runtimeState,
            liveAfter: initialLiveCursor,
            durableAfter: initialLiveCursor,
            playback: "playing",
            pause: "none",
            timeout: 8
        )

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(oceanNarrative.waitForExistence(timeout: 8))
        wait(
            for: phaseState,
            toHaveValue: "resumeRequired:waiting",
            timeout: 8
        )
        let paused = try waitForResponsiveAudioDurablePause(
            runtimeState,
            timeout: 8
        )
        let pausedCursor = try XCTUnwrap(paused.liveCursor)
        XCTAssertEqual(pausedCursor, paused.durableCursor)
        XCTAssertTrue(
            pausedCursor.isAtOrAfter(try XCTUnwrap(advancing.durableCursor))
        )
        XCTAssertTrue(
            ["sceneInactive", "sceneBackground"].contains(paused.pause),
            String(describing: runtimeState.value)
        )

        XCTAssertTrue(soundControl.isHittable)
        XCTAssertEqual(soundControl.label, "Resume sound")
        soundControl.tap()
        let durableResume = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let candidate = object as? XCUIElement,
                      candidate.isEnabled,
                      let value = candidate.value as? String,
                      let runtime = try? Self.parseResponsiveAudioRuntime(
                          value
                      ), runtime.playback == "playing",
                      runtime.pause == paused.pause,
                      let liveCursor = runtime.liveCursor,
                      let durableCursor = runtime.durableCursor else {
                    return false
                }
                let fields = Self.diagnosticFields(
                    in: value.split(separator: ";").map(String.init)[...]
                )
                return liveCursor.isAtOrAfter(pausedCursor)
                    && durableCursor.isStrictlyAfter(pausedCursor)
                    && fields["cursorFailure"] == "none"
            },
            object: runtimeState
        )
        guard XCTWaiter().wait(for: [durableResume], timeout: 8)
                == .completed,
              let resumedValue = runtimeState.value as? String else {
            throw ResponsiveAudioDiagnosticError.unavailable(
                "Durable audio cursor did not advance after explicit resume: "
                    + String(describing: runtimeState.value)
            )
        }
        let resumed = try Self.parseResponsiveAudioRuntime(resumedValue)
        wait(for: phaseState, toHaveValue: "playing:waiting", timeout: 8)
        XCTAssertTrue(
            try XCTUnwrap(resumed.liveCursor).isAtOrAfter(pausedCursor)
        )
        XCTAssertFalse(failureDiagnostic.exists)
    }

    func testSignedEuropeanWorldColdRestoresTraceAndExactAudioCursor() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
        ]
        app.launch()

        let route = app.descendants(matching: .any)[
            "chapter-runtime-european-world"
        ]
        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let phaseState = app.descendants(matching: .any)[
            "responsive-audio-presentation-state"
        ]
        let runtimeState = app.descendants(matching: .any)[
            "responsive-audio-runtime-state"
        ]
        let bindingReady = app.descendants(matching: .any)[
            "responsive-audio-binding-ready"
        ]
        let semanticTrace = app.descendants(matching: .any)[
            "chapter-semantic-trace-ocean-route"
        ]
        let touchSurface = app.descendants(matching: .any)[
            "chapter-touch-surface"
        ]
        let failureDiagnostic = app.descendants(matching: .any)[
            "signed-runtime-failure-diagnostic"
        ]
        XCTAssertTrue(route.waitForExistence(timeout: 12))
        XCTAssertTrue(beat.waitForExistence(timeout: 5))
        XCTAssertTrue(runtimeState.waitForExistence(timeout: 3))
        XCTAssertTrue(bindingReady.waitForExistence(timeout: 3))
        XCTAssertTrue(semanticTrace.waitForExistence(timeout: 3))
        XCTAssertTrue(touchSurface.waitForExistence(timeout: 3))
        let initialBinding = try waitForResponsiveAudioBinding(
            bindingReady,
            stage: "presentation"
        )
        let initialRuntime = try waitForResponsiveAudioPlaybackState(
            runtimeState,
            playback: "paused",
            pause: "none"
        )
        let initialLiveCursor = try XCTUnwrap(initialRuntime.liveCursor)

        let soundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(soundControl.waitForExistence(timeout: 3))
        XCTAssertTrue(soundControl.isHittable)
        XCTAssertEqual(soundControl.label, "Resume sound")
        soundControl.tap()
        _ = try waitForResponsiveAudioBinding(
            bindingReady,
            stage: "after-hear",
            generation: initialBinding.generation,
            timeout: 8
        )
        _ = try waitForResponsiveAudioCursorAdvance(
            runtimeState,
            liveAfter: initialLiveCursor,
            durableAfter: initialLiveCursor,
            playback: "playing",
            pause: "none",
            timeout: 8
        )

        performEuropeanWorldPhysicalTrace(on: touchSurface)
        wait(
            for: semanticTrace,
            toHaveValue: "2 of 4 route points reached",
            timeout: 8
        )

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(beat.waitForExistence(timeout: 8))
        wait(
            for: phaseState,
            toHaveValue: "resumeRequired:engaged",
            timeout: 8
        )
        let pausedBeforeKill = try waitForResponsiveAudioDurablePause(
            runtimeState,
            timeout: 8
        )
        let exactCursor = try XCTUnwrap(pausedBeforeKill.liveCursor)
        XCTAssertEqual(pausedBeforeKill.durableCursor, exactCursor)

        app.terminate()
        app.launchArguments = [
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
        ]
        app.launch()

        XCTAssertTrue(route.waitForExistence(timeout: 12))
        XCTAssertTrue(beat.waitForExistence(timeout: 5))
        XCTAssertTrue(semanticTrace.waitForExistence(timeout: 3))
        wait(
            for: semanticTrace,
            toHaveValue: "2 of 4 route points reached",
            timeout: 8
        )
        XCTAssertTrue(bindingReady.waitForExistence(timeout: 3))
        _ = try waitForResponsiveAudioBinding(
            bindingReady,
            stage: "presentation",
            timeout: 8
        )
        wait(
            for: phaseState,
            toHaveValue: "resumeRequired:waiting",
            timeout: 8
        )
        let restored = try waitForResponsiveAudioPhysicalState(
            runtimeState,
            playback: "paused",
            pause: "none",
            timeout: 8
        )
        XCTAssertEqual(restored.stage, "interaction")
        // `normalizeEphemeralResponsiveAudioPhaseForDurability` makes a cold
        // process resume from the neutral bed, never a transient response.
        XCTAssertEqual(restored.phase, "waiting")
        XCTAssertEqual(restored.durablePhase, "waiting")
        XCTAssertEqual(restored.pending, "none")
        XCTAssertEqual(restored.liveCursor, exactCursor)
        XCTAssertEqual(restored.durableCursor, exactCursor)
        let restoredSoundControl = app.buttons["chapter-sound-control"]
        XCTAssertTrue(restoredSoundControl.exists)
        XCTAssertEqual(restoredSoundControl.label, "Resume sound")
        XCTAssertFalse(failureDiagnostic.exists)
    }

    func testSignedRuntimeFixtureOpensAllThreeLabChaptersThroughProductionRoute()
        throws {
        let chapters = [
            (
                id: "first-farmers",
                beat: "beat-first-farmers-harvest-allocation",
                semantic: "allocate-winter-food"
            ),
            (
                id: "europe-holds-the-line",
                beat: "beat-frontiers-northern-valleys-pressure",
                semantic: "pressure-inhabited-stores"
            ),
            (
                id: "european-world",
                beat: "beat-european-world-ocean-schedule",
                semantic: "trace-ocean-route"
            ),
        ]
        for chapter in chapters {
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-testing-reset-state",
                "--ui-testing-signed-runtime-fixture",
                "--ui-testing-signed-runtime-fixture-chapter=\(chapter.id)",
                "--ui-testing-signed-runtime-fixture-beat=\(chapter.beat)",
            ]
            app.launch()
            XCTAssertTrue(
                app.descendants(matching: .any)[
                    "chapter-runtime-\(chapter.id)"
                ].waitForExistence(timeout: 12),
                chapter.id
            )
            XCTAssertTrue(
                app.descendants(matching: .any)[
                    "chapter-beat-\(chapter.beat)"
                ].waitForExistence(timeout: 5),
                chapter.id
            )
            XCTAssertTrue(
                app.descendants(matching: .any)[
                    "chapter-semantic-\(chapter.semantic)"
                ].exists,
                chapter.id
            )
            app.terminate()
        }
    }

    func testLegacyCompletedChapterWithoutArchiveIsVisibleAndDisabled()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-legacy-completed-without-review",
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["living-world-field"]
                .waitForExistence(timeout: 12)
        )
        let unavailableReview =
            "Completed. No archived scenes are available for review."
        let worldEntry = app.buttons[
            "chapter-world-entry-first-farmers"
        ]
        XCTAssertTrue(worldEntry.waitForExistence(timeout: 5))
        XCTAssertEqual(worldEntry.value as? String, unavailableReview)
        XCTAssertFalse(worldEntry.isEnabled)

        let roadEntry = app.buttons["chapter-road-first-farmers"]
        XCTAssertTrue(roadEntry.waitForExistence(timeout: 5))
        XCTAssertEqual(roadEntry.value as? String, unavailableReview)
        XCTAssertFalse(roadEntry.isEnabled)
        XCTAssertFalse(
            app.descendants(matching: .any)["content-unavailable"].exists
        )
    }

    func testPrologueCompleteCatalogAccessGateAndColdRestore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        completePrologue(in: app)
        XCTAssertTrue(app.buttons["chapter-road-first-farmers"].exists)
        XCTAssertTrue(app.buttons["chapter-road-europe-holds-the-line"].exists)
        XCTAssertTrue(app.buttons["chapter-road-european-world"].exists)
        XCTAssertTrue(app.buttons["chapter-road-europe-returns"].exists)

        openFirstFarmers(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["development-chapter-first-farmers"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "development-beat-beat-first-farmers-river-world"
            ].exists
        )
        XCTAssertTrue(app.staticTexts["The River Already Held a World"].exists)
        XCTAssertTrue(app.buttons["chapter-road"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = [
            "--ui-testing-download-surface",
            "--ui-testing-commerce-ready",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["chapter-road"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The First Farmers"].exists)
        XCTAssertTrue(app.staticTexts["The River Already Held a World"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "development-scene-scene-first-farmers-iron-gates-dawn"
            ].exists
        )

        app.buttons["chapter-road"].tap()
        let lockedRoad = app.buttons["chapter-road-steppe-comes-west"]
        for _ in 0 ..< 3 where !lockedRoad.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(lockedRoad.waitForExistence(timeout: 2))
        lockedRoad.tap()

        let purchaseSurface = app.descendants(matching: .any)["locked-road-purchase"]
        XCTAssertTrue(purchaseSurface.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unlock all 24 chapters permanently."].exists)
        XCTAssertFalse(app.buttons["chapter-road"].exists)
    }

    func testReleaseOptInIsExplicitAndOfflineDeepLinkFocusesTheAuthoredWorldPlace()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-release-deep-link",
        ]
        app.launch()

        XCTAssertFalse(
            app.alerts.firstMatch.waitForExistence(timeout: 0.5),
            "Launch and the prologue must never trigger a notification permission sheet."
        )

        // The notification tap arrives before Journey restoration and before
        // any historical experience. Its authenticated release-ID marker must
        // survive termination without persisting an unverified route.
        XCTAssertTrue(
            app.descendants(matching: .any)["prologue-road-control"]
                .waitForExistence(timeout: 5)
        )
        app.terminate()
        app.launchArguments = []
        app.launch()
        completePrologue(in: app)

        let focus = app.descendants(matching: .any)["release-world-focus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Local release fixture"].exists)
        XCTAssertTrue(app.staticTexts["AD 1453"].exists)
        XCTAssertFalse(app.buttons["chapter-road-local-frontier-route"].exists)
        let worldFocusReference = XCTAttachment(screenshot: app.screenshot())
        worldFocusReference.name = "release-world-focus-v1"
        worldFocusReference.lifetime = .keepAlways
        add(worldFocusReference)

        app.buttons["experience-settings-open"].tap()
        let enable = app.buttons["release-notifications-enable"]
        XCTAssertTrue(enable.waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        enable.tap()
        let status = app.staticTexts["release-notifications-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertEqual(status.label, "Notifications are on.")
        let notificationSettingsReference = XCTAttachment(screenshot: app.screenshot())
        notificationSettingsReference.name = "release-notification-settings-v1"
        notificationSettingsReference.lifetime = .keepAlways
        add(notificationSettingsReference)

        // Eligibility is re-established from the authenticated Journey
        // journal after termination; it is not an in-memory prologue flag.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(
            app.buttons["experience-settings-open"].waitForExistence(timeout: 5)
        )
        app.buttons["experience-settings-open"].tap()
        XCTAssertTrue(enable.waitForExistence(timeout: 3))
        enable.tap()
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertEqual(status.label, "Notifications are on.")
    }

    func testFocusedFutureReleaseOffersOneWorkingWorldNodeAction() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-release-deep-link",
            "--ui-testing-future-release-controls",
        ]
        app.launch()
        completePrologue(in: app)

        let focus = app.descendants(matching: .any)["release-world-focus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        let action = app.buttons["release-world-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        XCTAssertEqual(action.label, "Download")
        let availableReference = XCTAttachment(screenshot: app.screenshot())
        availableReference.name = "release-world-download-v1"
        availableReference.lifetime = .keepAlways
        add(availableReference)

        action.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["release-world-preparing"]
                .waitForExistence(timeout: 3)
        )
    }

    func testFocusedFutureReleaseRendersBootstrapFailureAndRetriesFromTheWorld()
        throws
    {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-release-deep-link",
            "--ui-testing-future-release-controls",
            "--ui-testing-future-release-bootstrap-retry",
        ]
        app.launch()
        completePrologue(in: app)

        let failure = app.staticTexts["release-world-failure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 5))
        XCTAssertEqual(
            failure.label,
            "Later historical routes could not be verified on this iPhone."
        )
        let retry = app.buttons["release-world-action"]
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        XCTAssertEqual(retry.label, "Try again")

        retry.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["release-world-preparing"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(failure.exists)
    }

    func testInstalledFutureReleaseWorldEntrySurvivesColdWithdrawnCatalog()
        throws
    {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        completePrologue(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["living-world-field"]
                .waitForExistence(timeout: 5)
        )
        app.terminate()

        // The discovery cache and remote catalog are both empty. The full
        // placement and announcement can therefore come only from the
        // retained installation contract supplied at cold bootstrap.
        app.launchArguments = [
            "--ui-testing-reset-release-discovery",
            "--ui-testing-release-catalog-withdrawn",
            "--ui-testing-future-release-controls",
            "--ui-testing-future-release-installed",
        ]
        app.launch()

        let entry = app.buttons[
            "release-world-entry-release-local-fixture-v1"
        ]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        XCTAssertFalse(
            app.descendants(matching: .any)["release-world-focus"].exists
        )
        entry.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["release-world-focus"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Local release fixture"].exists)
        XCTAssertTrue(app.staticTexts["AD 1453"].exists)
        let action = app.buttons["release-world-action"]
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        // Retained placement is presentation authority only. This fixture
        // has no signed active-generation payload, so it must not offer Begin.
        let failure = app.staticTexts["release-world-failure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 3))
        XCTAssertEqual(
            failure.label,
            "The installed historical route could not be verified."
        )
        XCTAssertEqual(action.label, "Try again")
    }

    func testInterruptedRetainedFutureReleaseCanResumeWithoutLiveCatalog()
        throws
    {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        completePrologue(in: app)
        app.terminate()

        app.launchArguments = [
            "--ui-testing-reset-release-discovery",
            "--ui-testing-release-catalog-withdrawn",
            "--ui-testing-future-release-controls",
            "--ui-testing-future-release-awaiting-restore",
        ]
        app.launch()

        let entry = app.buttons[
            "release-world-entry-release-local-fixture-v1"
        ]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()
        let resume = app.buttons["release-world-action"]
        XCTAssertTrue(resume.waitForExistence(timeout: 3))
        XCTAssertEqual(resume.label, "Continue")
        resume.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["release-world-preparing"]
                .waitForExistence(timeout: 3)
        )
    }

    func testIncompleteBuildNeverOffersAnUnfulfillablePurchase() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        completePrologue(in: app)

        let lockedRoad = app.buttons["chapter-road-steppe-comes-west"]
        for _ in 0 ..< 3 where !lockedRoad.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(lockedRoad.waitForExistence(timeout: 2))
        lockedRoad.tap()

        XCTAssertTrue(
            app.staticTexts["locked-road-unavailable"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.buttons["locked-road-unlock"].exists)
        XCTAssertFalse(app.buttons["locked-road-restore"].exists)
        XCTAssertFalse(app.staticTexts["Unlock all 24 chapters permanently."].exists)
    }

    func testAccessibilityXXXLKeepsRoadTargetsDistinctAndPurchaseModal() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
            "--ui-testing-commerce-ready",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        completePrologue(in: app)

        let farmers = app.buttons["chapter-road-first-farmers"]
        let steppe = app.buttons["chapter-road-steppe-comes-west"]
        XCTAssertTrue(farmers.waitForExistence(timeout: 5))
        XCTAssertTrue(steppe.exists)
        XCTAssertFalse(farmers.frame.intersects(steppe.frame))

        for _ in 0 ..< 4 where !farmers.isHittable { app.swipeUp() }
        XCTAssertTrue(farmers.isHittable)
        farmers.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["development-chapter-first-farmers"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.descendants(matching: .any)["locked-road-purchase"].exists)

        let returnToRoad = app.buttons["chapter-road"]
        XCTAssertTrue(returnToRoad.waitForExistence(timeout: 5))
        returnToRoad.tap()
        XCTAssertTrue(steppe.waitForExistence(timeout: 5))
        for _ in 0 ..< 20 where !steppe.isHittable {
            if steppe.frame.midY > app.frame.midY {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
        }
        XCTAssertTrue(steppe.isHittable)
        steppe.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["locked-road-purchase"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.buttons["chapter-road-first-farmers"].exists)
        XCTAssertFalse(app.buttons["chapter-road-steppe-comes-west"].exists)
        XCTAssertTrue(app.staticTexts["Unlock all 24 chapters permanently."].exists)
        let unlock = app.buttons["locked-road-unlock"]
        for _ in 0 ..< 4 where !unlock.isHittable { app.swipeUp() }
        XCTAssertTrue(unlock.isHittable)
        XCTAssertEqual(unlock.label, "Unlock for $24.99")
    }

    func testPurchaseFlowsDirectlyIntoDownloadAllWithoutReturningToTheRoad()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
            "--ui-testing-commerce-ready",
        ]
        app.launch()
        completePrologue(in: app)
        openLockedSteppeRoad(in: app)

        let unlock = app.buttons["locked-road-unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
        XCTAssertTrue(unlock.isHittable)
        unlock.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["offline-chapters-surface"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["locked-road-purchase"].exists
        )
        let downloadAll = app.buttons["offline-chapters-download-all"]
        XCTAssertTrue(downloadAll.waitForExistence(timeout: 3))
        XCTAssertTrue(downloadAll.isHittable)
        downloadAll.tap()

        XCTAssertTrue(
            app.staticTexts["Transferring Chapters 2–4"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["Pause after this group"].exists)
    }

    func testRestorePurchaseFlowsDirectlyIntoTheRequestedChapterDownload()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
            "--ui-testing-commerce-ready",
            "--ui-testing-restorable-purchase",
        ]
        app.launch()
        completePrologue(in: app)
        openLockedSteppeRoad(in: app)

        let restore = app.buttons["locked-road-restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertTrue(restore.isHittable)
        XCTAssertEqual(restore.label, "Restore Purchase")
        restore.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["offline-chapters-surface"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["locked-road-purchase"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["offline-package-paid-pack-01"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["offline-chapters-download-all"].exists)
    }

    func testDocumentaryBeatAdvancesIntoTheExactInteractiveSuccessor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        completePrologue(in: app)
        openFirstFarmers(in: app)

        let continueButton = app.buttons["development-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "development-beat-beat-first-farmers-household-crosses"
            ].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["The Field Crosses the Sea"].exists)
        XCTAssertTrue(app.staticTexts["Carry the household"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)[
                "development-scene-scene-first-farmers-aegean-crossing"
            ].exists
        )
        XCTAssertFalse(continueButton.exists)
    }

    func testExperienceSettingsPersistAndReturnToTheSameRoadPosition() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        XCTAssertFalse(app.buttons["experience-settings-open"].exists)
        completePrologue(in: app)

        let settingsButton = app.buttons["experience-settings-open"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(settingsButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(settingsButton.frame.height, 44)

        let roadPosition = app.buttons["chapter-road-europe-holds-the-line"]
        for _ in 0 ..< 14 where !roadPosition.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(roadPosition.isHittable)
        let progressFingerprintBeforeSettings = settingsButton.value as? String
        XCTAssertNotNil(progressFingerprintBeforeSettings)

        settingsButton.tap()
        let sound = app.switches["experience-setting-sound"]
        let narration = app.switches["experience-setting-narration"]
        let haptics = app.switches["experience-setting-haptics"]
        for toggle in [sound, narration, haptics] {
            XCTAssertTrue(toggle.waitForExistence(timeout: 3))
            XCTAssertEqual(toggle.value as? String, "1")
            XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
        }

        XCTAssertFalse(app.staticTexts["Cellular downloads"].exists)
        XCTAssertFalse(app.staticTexts["Automatic downloads"].exists)
        XCTAssertFalse(app.staticTexts["Dynamic Type"].exists)
        XCTAssertFalse(app.staticTexts["Reduce Motion"].exists)
        XCTAssertFalse(app.staticTexts["Increased Contrast"].exists)

        for toggle in [sound, narration, haptics] {
            toggle.tap()
            wait(for: toggle, toHaveValue: "0")
        }

        let close = app.buttons["experience-settings-close"]
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        close.tap()
        XCTAssertTrue(roadPosition.waitForExistence(timeout: 3))
        XCTAssertTrue(roadPosition.isHittable)
        XCTAssertEqual(
            settingsButton.value as? String,
            progressFingerprintBeforeSettings,
            "Changing an experience preference must not append Journey progress or alter world/chapter state."
        )

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(sound.waitForExistence(timeout: 3))
        XCTAssertEqual(sound.value as? String, "0")
        XCTAssertTrue(narration.waitForExistence(timeout: 3))
        XCTAssertEqual(narration.value as? String, "0")
        XCTAssertEqual(haptics.value as? String, "0")
    }

    func testFutureExperiencePreferenceSchemaRemainsReadOnlyAcrossColdLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-future-preferences",
        ]
        app.launch()
        completePrologue(in: app)

        let settingsButton = app.buttons["experience-settings-open"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        let notice = app.staticTexts["experience-settings-storage-status"]
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        XCTAssertEqual(notice.label, "Settings are read-only until this app is updated.")
        for identifier in [
            "experience-setting-sound",
            "experience-setting-narration",
            "experience-setting-haptics",
        ] {
            let toggle = app.switches[identifier]
            XCTAssertTrue(toggle.exists)
            XCTAssertFalse(toggle.isEnabled)
        }

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        XCTAssertEqual(notice.label, "Settings are read-only until this app is updated.")
        XCTAssertFalse(app.switches["experience-setting-sound"].isEnabled)
    }

    func testOwnedOfflineChaptersStartAndPauseOnlyAtThePackageBoundary() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
            "--ui-testing-owned-downloads",
        ]
        app.launch()
        completePrologue(in: app)

        XCTAssertTrue(app.buttons["experience-settings-open"].waitForExistence(timeout: 5))
        app.buttons["experience-settings-open"].tap()
        let offline = app.buttons["offline-chapters-open"]
        XCTAssertTrue(offline.waitForExistence(timeout: 3))
        XCTAssertTrue(offline.label.contains("21 chapters available to download"))
        offline.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["offline-chapters-surface"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Installed chapters open without a connection."].exists)
        XCTAssertTrue(app.staticTexts["offline-chapters-storage-maximum"].exists)
        XCTAssertEqual(
            app.staticTexts["offline-chapters-storage-maximum"].label,
            "Remaining chapters require up to 5.15 GB after installation."
        )
        XCTAssertTrue(app.staticTexts["3 INCLUDED CHAPTERS"].exists)
        XCTAssertTrue(app.staticTexts["CHAPTERS 11, 12, 14"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["offline-package-essential-free-v1"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["offline-package-paid-pack-01"].exists
        )
        XCTAssertTrue(app.switches["experience-setting-cellular-downloads"].exists)
        let visualReference = XCTAttachment(screenshot: app.screenshot())
        visualReference.name = "offline-chapters-owned-v1"
        visualReference.lifetime = .keepAlways
        add(visualReference)

        let downloadAll = app.buttons["offline-chapters-download-all"]
        XCTAssertTrue(downloadAll.isHittable)
        downloadAll.tap()

        let queueStatus = app.descendants(matching: .any)["offline-chapters-queue-status"]
        XCTAssertTrue(queueStatus.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Transferring Chapters 2–4"].exists)
        let pause = app.buttons["Pause after this group"]
        XCTAssertTrue(pause.exists)
        XCTAssertFalse(app.buttons["Continue downloads"].exists)
        pause.tap()

        XCTAssertTrue(app.staticTexts["Finishing Chapters 2–4"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Keep downloading"].exists)
        XCTAssertFalse(app.buttons["Continue downloads"].exists)
    }

    func testRevokedOwnershipPausesAnActivePaidQueueAtThePackageBoundary() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
            "--ui-testing-download-active",
            "--ui-testing-commerce-ready",
        ]
        app.launch()
        completePrologue(in: app)

        XCTAssertTrue(app.buttons["experience-settings-open"].waitForExistence(timeout: 5))
        app.buttons["experience-settings-open"].tap()
        let offline = app.buttons["offline-chapters-open"]
        XCTAssertTrue(offline.waitForExistence(timeout: 3))
        XCTAssertTrue(offline.label.contains("3 chapters included"))
        offline.tap()

        XCTAssertTrue(app.staticTexts["Finishing Chapters 2–4"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Pause after this group"].exists)
        XCTAssertFalse(app.buttons["Keep downloading"].exists)
        XCTAssertFalse(app.buttons["Continue downloads"].exists)
        XCTAssertFalse(app.buttons["offline-chapters-download-all"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["offline-package-paid-pack-01"].exists
        )
    }

    func testRevokedPaidRestorationReturnsDurablyToWorldBeforeContentAppears() throws {
        let app = XCUIApplication()
        let arguments = [
            "--ui-testing-paid-restoration",
            "--ui-testing-commerce-ready",
        ]
        app.launchArguments = ["--ui-testing-reset-state"] + arguments
        app.launch()

        let paidRoad = app.buttons["chapter-road-steppe-comes-west"]
        XCTAssertTrue(paidRoad.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["content-unavailable"].exists)
        XCTAssertFalse(app.buttons["chapter-road"].exists)

        app.terminate()
        app.launchArguments = arguments
        app.launch()

        XCTAssertTrue(paidRoad.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["content-unavailable"].exists)
        XCTAssertFalse(app.buttons["chapter-road"].exists)
    }

    func testUnownedOfflineSurfaceShowsOnlyIncludedChaptersAndNoPurchasePrompt() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
        ]
        app.launch()
        completePrologue(in: app)
        app.buttons["experience-settings-open"].tap()
        let offline = app.buttons["offline-chapters-open"]
        XCTAssertTrue(offline.waitForExistence(timeout: 3))
        XCTAssertTrue(offline.label.contains("3 chapters included"))
        offline.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["offline-package-essential-free-v1"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["offline-package-paid-pack-01"].exists
        )
        XCTAssertFalse(app.buttons["offline-chapters-download-all"].exists)
        XCTAssertFalse(app.switches["experience-setting-cellular-downloads"].exists)
        XCTAssertFalse(app.staticTexts["Unlock all 24 chapters permanently."].exists)
    }

    func testStaleOfflineQueueCanBeClearedWithoutAFalseResumeControl() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
            "--ui-testing-owned-downloads",
            "--ui-testing-download-stale",
        ]
        app.launch()
        completePrologue(in: app)
        app.buttons["experience-settings-open"].tap()
        app.buttons["offline-chapters-open"].tap()

        XCTAssertTrue(
            app.staticTexts["The saved queue belongs to an earlier chapter set"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.buttons["Continue downloads"].exists)
        let clear = app.buttons["Clear old queue"]
        XCTAssertTrue(clear.exists)
        clear.tap()

        XCTAssertTrue(
            app.buttons["offline-chapters-download-all"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(clear.exists)
    }

    func testChapterRedownloadIntentSurvivesTwoInstallerRejectionsAndDrainsTerminalObservation()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
            "--ui-testing-owned-downloads",
            "--ui-testing-download-stale",
            "--ui-testing-chapter-redownload-drain",
        ]
        app.launch()
        completePrologue(in: app)

        let diagnostic = app.descendants(matching: .any)[
            "chapter-redownload-diagnostic"
        ]
        let queue = app.buttons["chapter-redownload-queue-probe"]
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 3))
        XCTAssertTrue(queue.waitForExistence(timeout: 3))
        XCTAssertTrue(queue.isHittable)
        queue.tap()

        wait(
            for: diagnostic,
            toHaveValue:
                "phase=awaiting-installer;package=paid-pack-01",
            timeout: 5
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["offline-chapters-surface"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts[
                "The saved queue belongs to an earlier chapter set"
            ].waitForExistence(timeout: 3)
        )

        let clear = app.buttons["Clear old queue"]
        XCTAssertTrue(clear.exists)
        XCTAssertTrue(clear.isHittable)
        clear.tap()

        // The fixture rejects two installer starts. During the second pending
        // command it publishes a terminal installer state; only a subsequent
        // deferred drain can reach the third, successful start.
        wait(
            for: diagnostic,
            toHaveValue: "phase=started;package=paid-pack-01",
            timeout: 8
        )
        XCTAssertTrue(
            app.staticTexts["Transferring Chapters 2–4"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["Pause after this group"].exists)
        XCTAssertFalse(app.buttons["offline-chapters-download-all"].exists)
        XCTAssertFalse(app.staticTexts["offline-chapters-failure"].exists)
    }

    func testInsufficientStorageKeepsEarlierChaptersAndOffersAnExplicitRetry() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
            "--ui-testing-owned-downloads",
            "--ui-testing-download-insufficient-storage",
        ]
        app.launch()
        completePrologue(in: app)
        app.buttons["experience-settings-open"].tap()
        app.buttons["offline-chapters-open"].tap()

        XCTAssertTrue(
            app.staticTexts["Chapters 2–4 could not be installed"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts[
                "Make more storage available, then try again. Earlier chapters were not changed."
            ].exists
        )
        XCTAssertTrue(app.buttons["Try again"].exists)
        XCTAssertTrue(app.buttons["Skip this group"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["offline-package-essential-free-v1"]
                .exists
        )
    }

    func testNewerChapterFilesArePreservedAndNeverOfferedAsADowngrade() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
            "--ui-testing-owned-downloads",
            "--ui-testing-download-newer-content",
        ]
        app.launch()
        completePrologue(in: app)
        app.buttons["experience-settings-open"].tap()

        let offline = app.buttons["offline-chapters-open"]
        XCTAssertTrue(offline.waitForExistence(timeout: 3))
        XCTAssertTrue(
            offline.label.contains(
                "18 chapters available to download; 3 need an app update"
            )
        )
        offline.tap()

        XCTAssertTrue(
            app.staticTexts["offline-chapters-newer-content"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertEqual(
            app.staticTexts["offline-chapters-newer-content"].label,
            "Update the app to open the newer chapter files already on this iPhone."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["offline-package-paid-pack-01"].exists
        )
        XCTAssertTrue(app.staticTexts["Update app"].exists)
        XCTAssertFalse(app.buttons["offline-package-download-paid-pack-01"].exists)
        XCTAssertTrue(app.buttons["offline-package-download-paid-pack-02"].exists)
        XCTAssertTrue(app.buttons["offline-chapters-download-all"].exists)

        app.buttons["offline-chapters-back"].tap()
        app.buttons["experience-settings-close"].tap()
        let protectedRoad = app.buttons["chapter-road-steppe-comes-west"]
        for _ in 0 ..< 4 where !protectedRoad.isHittable { app.swipeUp() }
        XCTAssertTrue(protectedRoad.isHittable)
        protectedRoad.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["content-unavailable"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts[
                "Update the app to open the newer chapter files already on this iPhone."
            ].exists
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["offline-chapters-surface"].exists
        )
    }

    func testOlderChapterFilesAreShownAsAnUpdate() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
            "--ui-testing-owned-downloads",
            "--ui-testing-download-outdated-content",
        ]
        app.launch()
        completePrologue(in: app)
        app.buttons["experience-settings-open"].tap()
        app.buttons["offline-chapters-open"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["offline-package-paid-pack-01"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["Update available"].exists)
        let update = app.buttons["offline-package-download-paid-pack-01"]
        XCTAssertTrue(update.exists)
        XCTAssertEqual(update.label, "Update")
        XCTAssertTrue(app.buttons["offline-chapters-download-all"].exists)
    }

    func testOfflineStatusBootstrapCanBeRetriedWithoutRelaunching() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
            "--ui-testing-owned-downloads",
            "--ui-testing-download-bootstrap-failure",
        ]
        app.launch()
        completePrologue(in: app)
        app.buttons["experience-settings-open"].tap()
        app.buttons["offline-chapters-open"].tap()

        let retry = app.buttons["offline-chapters-retry-status"]
        XCTAssertTrue(retry.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["offline-chapters-download-all"].exists)
        retry.tap()

        XCTAssertTrue(
            app.buttons["offline-chapters-download-all"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(retry.exists)
    }

    func testFutureInstalledIndexRequiresAppUpdateAndOffersNoRetryOrDownload() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-download-surface",
            "--ui-testing-owned-downloads",
            "--ui-testing-download-future-index",
        ]
        app.launch()
        completePrologue(in: app)
        app.buttons["experience-settings-open"].tap()
        app.buttons["offline-chapters-open"].tap()

        let failure = app.staticTexts["offline-chapters-failure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 3))
        XCTAssertEqual(
            failure.label,
            "Update the app to read the newer chapter installation already on this iPhone."
        )
        XCTAssertFalse(app.buttons["offline-chapters-retry-status"].exists)
        XCTAssertFalse(app.buttons["offline-chapters-download-all"].exists)
        XCTAssertTrue(app.buttons["offline-chapters-dismiss-failure"].exists)
    }

    func testMissingDevelopmentPayloadFailsClosedBeforeChapterStateChanges() throws {
        assertDevelopmentPayloadFailure(
            launchArgument: "--ui-testing-missing-development-payload"
        )
    }

    func testForgedDevelopmentPayloadFailsClosedBeforeChapterStateChanges() throws {
        assertDevelopmentPayloadFailure(
            launchArgument: "--ui-testing-forged-development-payload"
        )
    }

    func testContinuousInputVisualFeedbackAndJournalCadenceStayEnergyBounded()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            "--ui-testing-continuous-input-energy",
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-runtime-european-world"
            ].waitForExistence(timeout: 12)
        )
        let diagnostic = app.descendants(matching: .any)[
            "continuous-input-energy-diagnostic"
        ]
        let run = app.buttons["continuous-input-energy-run"]
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 5))
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertTrue(run.isHittable)

        run.tap()
        wait(
            for: diagnostic,
            toHaveValueContaining: "result=pass",
            timeout: 8
        )
        let value = try XCTUnwrap(diagnostic.value as? String)
        for fragment in [
            "visual=120;",
            "visualUnder50=1;",
            "authorityUnchanged=1;",
            "ordinary=trace:5,pressure:5,transform:5;",
            "protected=trace-0,pressure-exit,"
                + "transform-0,transform-1,preview-fallback,terminal;",
            "discrete=pressure-hold:1,voice-over:1;",
            "result=pass",
        ] {
            XCTAssertTrue(value.contains(fragment), value)
        }
    }

    func testSaturatedContinuousInputRemainsOneTrackedFIFOThroughLifecycleCancellation()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            "--ui-testing-chapter-input-fifo",
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-runtime-european-world"
            ].waitForExistence(timeout: 12)
        )
        let diagnostic = app.descendants(matching: .any)[
            "chapter-input-fifo-probe-diagnostic"
        ]
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 5))

        let saturate = app.buttons["chapter-input-fifo-saturate"]
        XCTAssertTrue(saturate.waitForExistence(timeout: 5))
        XCTAssertTrue(saturate.isHittable)
        saturate.tap()
        wait(
            for: diagnostic,
            toHaveValueContaining: "cycle=1;phase=held;",
            timeout: 8
        )
        var value = try XCTUnwrap(diagnostic.value as? String)
        for fragment in [
            "accepted=1,2,3,4,5,6,7,8;",
            "performed=1;",
            "completed=-;",
            "coalesced=9;",
            "dropped=-;",
            "current=1;",
            "deferred=10;",
            "pending=7;",
            "reservations=8/8;",
            "task=1;tracked=1;active=1/1;untracked=-;",
        ] {
            XCTAssertTrue(value.contains(fragment), value)
        }

        let release = app.buttons["chapter-input-fifo-release"]
        XCTAssertTrue(release.waitForExistence(timeout: 3))
        release.tap()
        wait(
            for: diagnostic,
            toHaveValueContaining: "cycle=1;phase=drained;",
            timeout: 15
        )
        value = try XCTUnwrap(diagnostic.value as? String)
        let drainedOrder = "1,2,3,4,5,6,7,8,10"
        for fragment in [
            "accepted=\(drainedOrder);",
            "performed=\(drainedOrder);",
            "completed=\(drainedOrder);",
            "coalesced=9;",
            "dropped=-;",
            "current=-;deferred=-;pending=0;",
            "reservations=0/8;",
            "task=0;tracked=-;active=0/1;untracked=-;",
            "lifecycle=0;deactivation=0;route=1",
        ] {
            XCTAssertTrue(value.contains(fragment), value)
        }

        XCTAssertTrue(saturate.waitForExistence(timeout: 3))
        XCTAssertTrue(saturate.isHittable)
        saturate.tap()
        wait(
            for: diagnostic,
            toHaveValueContaining: "cycle=2;phase=held;",
            timeout: 8
        )

        XCUIDevice.shared.press(.home)
        app.activate()
        wait(
            for: diagnostic,
            toHaveValueContaining: "lifecycle=1;deactivation=0;route=1",
            timeout: 8
        )

        let cancelRoute = app.buttons["chapter-input-fifo-cancel-route"]
        XCTAssertTrue(cancelRoute.waitForExistence(timeout: 3))
        cancelRoute.tap()
        wait(
            for: diagnostic,
            toHaveValueContaining: "cycle=2;phase=cancelling;",
            timeout: 3
        )
        value = try XCTUnwrap(diagnostic.value as? String)
        XCTAssertTrue(
            value.contains("accepted=1,2,3,4,5,6,7,8,10;"),
            value
        )
        XCTAssertTrue(value.contains("dropped=-;"), value)
        XCTAssertTrue(release.waitForExistence(timeout: 3))
        release.tap()
        wait(
            for: diagnostic,
            toHaveValueContaining: "cycle=2;phase=cancelled;",
            timeout: 15
        )
        value = try XCTUnwrap(diagnostic.value as? String)
        let cancelledOrder = "1,2,3,4,5,6,7,8,10"
        for fragment in [
            "accepted=\(cancelledOrder);",
            "performed=\(cancelledOrder);",
            "completed=\(cancelledOrder);",
            "coalesced=9;",
            "dropped=-;",
            "current=-;deferred=-;pending=0;",
            "reservations=0/9;",
            "task=0;tracked=-;active=0/1;untracked=-;",
            "lifecycle=0;deactivation=0;route=0",
        ] {
            XCTAssertTrue(value.contains(fragment), value)
        }
    }

    func testSaturatedRightAngleTraceRetainsOrderedAnchorsAndLatestSample()
        throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            "--ui-testing-chapter-input-fifo",
            "--ui-testing-chapter-input-fifo-right-angle-trace",
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)[
                "chapter-runtime-european-world"
            ].waitForExistence(timeout: 12)
        )
        let diagnostic = app.descendants(matching: .any)[
            "chapter-input-fifo-probe-diagnostic"
        ]
        let saturate = app.buttons["chapter-input-fifo-saturate"]
        let release = app.buttons["chapter-input-fifo-release"]
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 5))
        XCTAssertTrue(saturate.waitForExistence(timeout: 5))

        saturate.tap()
        wait(
            for: diagnostic,
            toHaveValueContaining: "cycle=1;phase=held;",
            timeout: 8
        )
        var value = try XCTUnwrap(diagnostic.value as? String)
        for fragment in [
            "accepted=1,2,3,4,5,6,7,8;",
            "performed=1;",
            "coalesced=-;",
            "current=1;deferred=9,10,11;pending=7;",
            "reservations=8/8;",
            "task=1;tracked=1;active=1/1;untracked=-;",
        ] {
            XCTAssertTrue(value.contains(fragment), value)
        }

        XCTAssertTrue(release.waitForExistence(timeout: 3))
        release.tap()
        wait(
            for: diagnostic,
            toHaveValueContaining: "cycle=1;phase=drained;",
            timeout: 15
        )
        value = try XCTUnwrap(diagnostic.value as? String)
        let orderedDrain = "1,2,3,4,5,6,7,8,9,10,11"
        for fragment in [
            "accepted=\(orderedDrain);",
            "performed=\(orderedDrain);",
            "completed=\(orderedDrain);",
            "coalesced=-;dropped=-;",
            "current=-;deferred=-;pending=0;",
            "reservations=0/8;",
            "task=0;tracked=-;active=0/1;untracked=-;",
        ] {
            XCTAssertTrue(value.contains(fragment), value)
        }

        XCTAssertTrue(saturate.waitForExistence(timeout: 3))
        saturate.tap()
        wait(
            for: diagnostic,
            toHaveValueContaining: "cycle=2;phase=held;",
            timeout: 8
        )
        value = try XCTUnwrap(diagnostic.value as? String)
        for fragment in [
            "accepted=1,2,3,4,5,6,7,8;",
            "coalesced=9;",
            "current=1;deferred=10,11;pending=7;",
            "reservations=8/8;",
        ] {
            XCTAssertTrue(value.contains(fragment), value)
        }

        XCTAssertTrue(release.waitForExistence(timeout: 3))
        release.tap()
        wait(
            for: diagnostic,
            toHaveValueContaining: "cycle=2;phase=drained;",
            timeout: 15
        )
        value = try XCTUnwrap(diagnostic.value as? String)
        let correctedDrain = "1,2,3,4,5,6,7,8,10,11"
        for fragment in [
            "accepted=\(correctedDrain);",
            "performed=\(correctedDrain);",
            "completed=\(correctedDrain);",
            "coalesced=9;dropped=-;",
            "current=-;deferred=-;pending=0;",
            "reservations=0/8;",
        ] {
            XCTAssertTrue(value.contains(fragment), value)
        }
    }

    private func assertDevelopmentPayloadFailure(launchArgument: String) {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state", launchArgument]
        app.launch()
        completePrologue(in: app)
        openFirstFarmers(in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["content-unavailable"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Chapter unavailable"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["development-chapter-first-farmers"].exists
        )
        XCTAssertTrue(app.buttons["Close"].exists)
    }

    private func completePrologue(in app: XCUIApplication) {
        let roadControl = app.descendants(matching: .any)["prologue-road-control"]
        XCTAssertTrue(roadControl.waitForExistence(timeout: 5))
        roadControl.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: roadControl.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)
                )
            )
        XCTAssertTrue(
            app.descendants(matching: .any)["living-world-field"]
                .waitForExistence(timeout: 5)
        )
    }

    private func openFirstFarmers(in app: XCUIApplication) {
        let firstFarmers = app.buttons["chapter-road-first-farmers"]
        for _ in 0 ..< 3 where !firstFarmers.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(firstFarmers.waitForExistence(timeout: 2))
        firstFarmers.tap()
    }

    private func reveal(
        _ control: XCUIElement,
        in narrative: XCUIElement
    ) {
        for _ in 0 ..< 12 where !control.isHittable {
            narrative.swipeUp()
        }
        let readiness = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else {
                    return false
                }
                return element.exists && element.isHittable
                    && element.isEnabled
            },
            object: control
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [readiness], timeout: 3),
            .completed,
            "Expected \(control.identifier) to become hittable and enabled"
        )
    }

    private func assertFailedPauseAuthorityRecovery(
        launchArgument: String,
        expectedHoldingTrace: String? = nil,
        expectedFinalTrace: String
    ) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-chapter=european-world",
            launchArgument,
        ]
        app.launch()

        let route = app.descendants(matching: .any)[
            "chapter-runtime-european-world"
        ]
        let beat = app.descendants(matching: .any)[
            "chapter-beat-beat-european-world-ocean-schedule"
        ]
        let touchSurface = app.descendants(matching: .any)[
            "chapter-touch-surface"
        ]
        let barrier = app.descendants(matching: .any)[
            "global-content-authority-barrier-diagnostic"
        ]
        let lifecycle = app.descendants(matching: .any)[
            "global-causal-lifecycle-state"
        ]
        let failureReturn = app.buttons[
            "chapter-failure-return-to-road"
        ]
        XCTAssertTrue(route.waitForExistence(timeout: 12))
        XCTAssertTrue(beat.waitForExistence(timeout: 5))
        XCTAssertTrue(touchSurface.waitForExistence(timeout: 3))
        XCTAssertTrue(barrier.waitForExistence(timeout: 3))
        XCTAssertTrue(lifecycle.waitForExistence(timeout: 3))

        performEuropeanWorldPhysicalTrace(on: touchSurface)

        XCTAssertTrue(
            failureReturn.waitForExistence(timeout: 12),
            "Barrier: \(String(describing: barrier.value)); lifecycle: "
                + String(describing: lifecycle.value)
        )
        let preRecoveryTrace = try XCTUnwrap(
            expectedFinalTrace.components(
                separatedBy: ">recovery:reserved"
            ).first
        )
        wait(for: barrier, toHaveValue: preRecoveryTrace, timeout: 8)
        let deferred = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@",
                "accepted=r1",
                "desired=r2",
                "retry=1",
                "episodeResult=failed",
                "physicalPause=1"
            ),
            object: lifecycle
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [deferred], timeout: 8),
            .completed,
            "Barrier: \(String(describing: barrier.value)); lifecycle: "
                + String(describing: lifecycle.value)
        )
        XCTAssertFalse(
            String(describing: barrier.value).contains("published:r2")
        )

        failureReturn.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["living-world-field"]
                .waitForExistence(timeout: 12),
            "Barrier: \(String(describing: barrier.value)); lifecycle: "
                + String(describing: lifecycle.value)
        )
        if let expectedHoldingTrace {
            wait(
                for: barrier,
                toHaveValue: expectedHoldingTrace,
                timeout: 12
            )
            let held = XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format:
                        "value CONTAINS %@ AND value CONTAINS %@ AND "
                            + "value CONTAINS %@ AND value CONTAINS %@ AND "
                            + "value CONTAINS %@ AND value CONTAINS %@ AND "
                            + "value CONTAINS %@ AND value CONTAINS %@ AND "
                            + "value CONTAINS %@",
                    "route=world",
                    "accepted=r1",
                    "desired=r2",
                    "retry=1",
                    "episodeResult=none",
                    "physicalPause=1",
                    "reservations=1",
                    "ordered=1",
                    "chapterPending=1"
                ),
                object: lifecycle
            )
            XCTAssertEqual(
                XCTWaiter().wait(for: [held], timeout: 8),
                .completed,
                "Barrier: \(String(describing: barrier.value)); lifecycle: "
                    + String(describing: lifecycle.value)
            )
            XCTAssertFalse(
                String(describing: barrier.value).contains("e2:admitted")
            )
            XCTAssertFalse(
                String(describing: barrier.value).contains("published:r2")
            )
            let release = app.buttons[
                "release-ordered-recovery-epoch-probe"
            ]
            XCTAssertTrue(release.waitForExistence(timeout: 3))
            XCTAssertTrue(release.isHittable)
            release.tap()
        }
        wait(for: barrier, toHaveValue: expectedFinalTrace, timeout: 12)

        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND value CONTAINS %@ AND "
                        + "value CONTAINS %@ AND value CONTAINS %@",
                "route=world",
                "accepted=r2",
                "desired=r2",
                "retry=0",
                "episode=none",
                "physicalPause=0",
                "reservations=0",
                "ordered=0"
            ),
            object: lifecycle
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [settled], timeout: 8),
            .completed,
            "Barrier: \(String(describing: barrier.value)); lifecycle: "
                + String(describing: lifecycle.value)
        )
    }

    private func performEuropeanWorldPhysicalTrace(
        on touchSurface: XCUIElement
    ) {
        let firstOceanAnchor = touchSurface.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.2142857,
                dy: 0.5571429
            )
        )
        let secondOceanAnchor = touchSurface.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.4,
                dy: 0.5285714
            )
        )
        firstOceanAnchor.press(
            forDuration: 0.15,
            thenDragTo: secondOceanAnchor
        )
    }

    private enum FirstFarmersRecordedInteraction: String, CaseIterable {
        case householdCrossing = "trace-household-crossing"
        case harvestAllocation = "allocate-harvest"
        case threeRecords = "transform-three-records"
        case longhouseAssembly = "assemble-longhouse"
        case settlementGrowth = "transform-settlement-growth"
        case continentRemade = "transform-continent-remade"

        var beatID: String {
            switch self {
            case .householdCrossing:
                "beat-first-farmers-household-crosses"
            case .harvestAllocation:
                "beat-first-farmers-harvest-allocation"
            case .threeRecords:
                "beat-first-farmers-three-records"
            case .longhouseAssembly:
                "beat-first-farmers-raise-longhouse"
            case .settlementGrowth:
                "beat-first-farmers-more-mouths"
            case .continentRemade:
                "beat-first-farmers-continent-remade"
            }
        }
    }

    private struct FirstFarmersTraversalReceipt {
        let beatIDs: [String]
        let interactionIDs: [String]

        var sha256: String {
            let material = (["NON_SHIPPING_LIVE_TEST"] + beatIDs
                + ["INTERACTIONS"] + interactionIDs)
                .joined(separator: "\n")
            return SHA256.hash(data: Data(material.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        }
    }

    private var firstFarmersReviewBeatIDs: [String] {
        [
            "beat-first-farmers-river-world",
            "beat-first-farmers-household-crosses",
            "beat-first-farmers-living-system",
            "beat-first-farmers-european-ground",
            "beat-first-farmers-inhabited-frontier",
            "beat-first-farmers-harvest-allocation",
            "beat-first-farmers-stored-future",
            "beat-first-farmers-gorge-contact",
            "beat-first-farmers-three-records",
            "beat-first-farmers-frontier-consequence",
            "beat-first-farmers-raise-longhouse",
            "beat-first-farmers-plot-remains",
            "beat-first-farmers-paternal-lines",
            "beat-first-farmers-more-mouths",
            "beat-first-farmers-growth-breaks",
            "beat-first-farmers-continent-remade",
            "beat-first-farmers-before-steppe",
        ]
    }

    private func recordFirstFarmersInteraction(
        _ target: FirstFarmersRecordedInteraction
    ) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
            "--ui-testing-signed-runtime-fixture-beat=\(target.beatID)",
        ]
        app.launch()

        let route = app.descendants(matching: .any)[
            "chapter-runtime-first-farmers"
        ]
        XCTAssertTrue(route.waitForExistence(timeout: 12))
        let narrative = app.descendants(matching: .any)[
            "chapter-beat-\(target.beatID)"
        ]
        XCTAssertTrue(narrative.waitForExistence(timeout: 12))
        let sceneSurface = app.windows.firstMatch
        XCTAssertTrue(sceneSurface.waitForExistence(timeout: 3))

        // These artifacts isolate the physical interaction itself. Dedicated
        // sound-control tests cover automatic start and cold-resume behavior.
        performFirstFarmersInteraction(
            target,
            app: app,
            narrative: narrative,
            sceneSurface: sceneSurface
        )
        XCTAssertFalse(
            app.buttons["chapter-failure-return-to-road"].exists
        )
        let receipt = FirstFarmersTraversalReceipt(
            beatIDs: [target.beatID],
            interactionIDs: [target.rawValue]
        )
        print(
            "CHAPTER_01_LIVE_INTERACTION_RECORDING target=\(target.rawValue) "
                + "beats=\(receipt.beatIDs.count) "
                + "interactions=\(receipt.interactionIDs.count) "
                + "sha256=\(receipt.sha256)"
        )
    }

    private func traverseFirstFarmersReviewBuild() throws
        -> FirstFarmersTraversalReceipt {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-reset-state",
            "--ui-testing-signed-runtime-fixture",
        ]
        app.launch()

        let route = app.descendants(matching: .any)[
            "chapter-runtime-first-farmers"
        ]
        let failure = app.buttons["chapter-failure-return-to-road"]
        XCTAssertTrue(route.waitForExistence(timeout: 12))

        // The live-test product exposes no debug touch proxy. Coordinates are
        // resolved against the actual app window that contains the authored
        // portrait scene and its production gesture surfaces.
        let sceneSurface = app.windows.firstMatch
        XCTAssertTrue(sceneSurface.waitForExistence(timeout: 3))

        let beatIDs = firstFarmersReviewBeatIDs
        let opening = app.descendants(matching: .any)[
            "chapter-beat-\(beatIDs[0])"
        ]
        XCTAssertTrue(opening.waitForExistence(timeout: 5))

        var observedBeatIDs: [String] = []
        var observedInteractionIDs: [String] = []
        for (index, beatID) in beatIDs.enumerated() {
            let narrative = app.descendants(matching: .any)[
                "chapter-beat-\(beatID)"
            ]
            XCTAssertTrue(
                narrative.waitForExistence(timeout: 12),
                "Missing beat \(index + 1): \(beatID)"
            )
            observedBeatIDs.append(beatID)

            if let interaction = FirstFarmersRecordedInteraction.allCases
                .first(where: { $0.beatID == beatID }) {
                performFirstFarmersInteraction(
                    interaction,
                    app: app,
                    narrative: narrative,
                    sceneSurface: sceneSurface
                )
                observedInteractionIDs.append(interaction.rawValue)
            }

            let advance = app.buttons["chapter-continue"]
            XCTAssertTrue(
                advance.waitForExistence(timeout: 8),
                "Missing primary action for beat \(index + 1): \(beatID)"
            )
            XCTAssertTrue(
                advance.isHittable,
                "The primary action required scrolling in beat "
                    + "\(index + 1): \(beatID)"
            )
            advance.tap()
            XCTAssertFalse(failure.exists, "Runtime failed after \(beatID)")
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["living-world-field"]
                .waitForExistence(timeout: 12)
        )
        XCTAssertFalse(failure.exists)
        return FirstFarmersTraversalReceipt(
            beatIDs: observedBeatIDs,
            interactionIDs: observedInteractionIDs
        )
    }

    private func performFirstFarmersInteraction(
        _ interaction: FirstFarmersRecordedInteraction,
        app: XCUIApplication,
        narrative: XCUIElement,
        sceneSurface: XCUIElement
    ) {
        switch interaction {
        case .householdCrossing:
            performFirstFarmersHouseholdTrace(
                app: app,
                touchSurface: sceneSurface
            )
        case .harvestAllocation:
            performFirstFarmersHarvestAllocation(
                app: app,
                narrative: narrative,
                touchSurface: sceneSurface
            )
        case .threeRecords:
            performFirstFarmersTransform(
                app: app,
                touchSurface: sceneSurface,
                elementIDs: [
                    "transform-river-communities",
                    "transform-contact-households",
                    "transform-later-settlements",
                ]
            )
        case .longhouseAssembly:
            performFirstFarmersLonghouse(
                app: app,
                touchSurface: sceneSurface
            )
        case .settlementGrowth:
            performFirstFarmersTransform(
                app: app,
                touchSurface: sceneSurface,
                elementIDs: [
                    "transform-new-hearths",
                    "transform-field-edges",
                    "transform-herd-lanes-and-daughters",
                ]
            )
        case .continentRemade:
            performFirstFarmersTransform(
                app: app,
                touchSurface: sceneSurface,
                elementIDs: [
                    "transform-danube-fields",
                    "transform-loess-settlements",
                    "transform-european-farming-belt",
                ]
            )
        }
    }

    private func performFirstFarmersHouseholdTrace(
        app: XCUIApplication,
        touchSurface: XCUIElement
    ) {
        let semantic = app.descendants(matching: .any)[
            "chapter-semantic-trace-route"
        ]
        XCTAssertTrue(semantic.waitForExistence(timeout: 3))
        // The signed review fixture uses the complete shared portrait plate
        // for this interaction, so authored master and viewport coordinates
        // are identical. All four points remain above the compact sheet.
        let anchors = [
            CGVector(dx: 0.76, dy: 0.78),
            CGVector(dx: 0.58, dy: 0.61),
            CGVector(dx: 0.43, dy: 0.44),
            CGVector(dx: 0.33, dy: 0.20),
        ].map { touchSurface.coordinate(withNormalizedOffset: $0) }
        anchors[0].press(forDuration: 0.12, thenDragTo: anchors[1])
        wait(
            for: semantic,
            toHaveValue: "2 of 4 route points reached",
            timeout: 8
        )
        anchors[1].press(forDuration: 0.1, thenDragTo: anchors[2])
        wait(
            for: semantic,
            toHaveValue: "3 of 4 route points reached",
            timeout: 8
        )
        anchors[2].press(forDuration: 0.1, thenDragTo: anchors[3])
        XCTAssertTrue(
            app.buttons["chapter-continue"].waitForExistence(timeout: 8),
            "The fourth physical route point did not complete Trace"
        )
    }

    private func performFirstFarmersHarvestAllocation(
        app: XCUIApplication,
        narrative: XCUIElement,
        touchSurface: XCUIElement
    ) {
        let source = CGVector(dx: 0.50, dy: 0.802)
        let allocations = [
            (id: "allocate-winter-food", point: CGVector(dx: 0.275, dy: 0.585), units: 4),
            (id: "allocate-protected-reserve", point: CGVector(dx: 0.500, dy: 0.585), units: 2),
            (id: "allocate-spring-seed", point: CGVector(dx: 0.725, dy: 0.585), units: 6),
        ]
        for allocation in allocations {
            let semantic = app.descendants(matching: .any)[
                "chapter-semantic-\(allocation.id)"
            ]
            XCTAssertTrue(semantic.waitForExistence(timeout: 3))
            for _ in 0 ..< allocation.units {
                performAllocationDrag(
                    on: touchSurface,
                    from: source,
                    to: allocation.point,
                    observing: semantic
                )
            }
            if allocation.id == "allocate-winter-food" {
                // Physical reversal remains available until the final commit.
                performAllocationDrag(
                    on: touchSurface,
                    from: allocation.point,
                    to: source,
                    observing: semantic
                )
                performAllocationDrag(
                    on: touchSurface,
                    from: source,
                    to: allocation.point,
                    observing: semantic
                )
            }
        }

        // Exercise the visible production control. It is the sole
        // accessibility representation for commit, avoiding a duplicate
        // invisible semantic button while remaining a normal touch target.
        let commit = app.buttons["chapter-allocate-commit"]
        XCTAssertTrue(
            commit.waitForExistence(timeout: 3),
            "The harvest allocation action was unavailable"
        )
        XCTAssertTrue(
            commit.isHittable,
            "The harvest allocation action required scrolling"
        )
        commit.tap()
        let advance = app.buttons["chapter-continue"]
        XCTAssertTrue(
            advance.waitForExistence(timeout: 8),
            "The physical harvest commit button did not accept the allocation"
        )
    }

    private func performAllocationDrag(
        on touchSurface: XCUIElement,
        from source: CGVector,
        to destination: CGVector,
        observing semantic: XCUIElement
    ) {
        let previousValue = String(describing: semantic.value)
        touchSurface.coordinate(withNormalizedOffset: source).press(
            forDuration: 0.08,
            thenDragTo: touchSurface.coordinate(
                withNormalizedOffset: destination
            )
        )
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value != %@ AND enabled == true",
                previousValue
            ),
            object: semantic
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [changed], timeout: 8),
            .completed,
            "Allocation did not change from \(previousValue)"
        )
    }

    private func performFirstFarmersLonghouse(
        app: XCUIApplication,
        touchSurface: XCUIElement
    ) {
        // The baseline crop is (0.15, 0.15, 0.70, 0.70). Posts establish the
        // frame; the remaining three parts deliberately use a different valid
        // order from their source list.
        let components = [
            (id: "posts", x: 0.1428571),
            (id: "roof", x: 0.8285714),
            (id: "storage", x: 0.6000000),
            (id: "hearth", x: 0.3714286),
        ]
        for (index, component) in components.enumerated() {
            let semantic = app.descendants(matching: .any)[
                "chapter-semantic-assemble-\(component.id)"
            ]
            XCTAssertTrue(semantic.waitForExistence(timeout: 3))
            touchSurface.coordinate(
                withNormalizedOffset: CGVector(
                    dx: component.x,
                    dy: 0.3714286
                )
            ).press(
                forDuration: 0.1,
                thenDragTo: touchSurface.coordinate(
                    withNormalizedOffset: CGVector(
                        dx: component.x,
                        dy: 0.7714286
                    )
                )
            )
            if index == components.indices.last {
                XCTAssertTrue(
                    app.buttons["chapter-continue"]
                        .waitForExistence(timeout: 8),
                    "The final longhouse drop did not complete Assemble"
                )
            } else {
                let accepted = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"),
                    object: semantic
                )
                XCTAssertEqual(
                    XCTWaiter().wait(for: [accepted], timeout: 8),
                    .completed,
                    "The placed component remained available for a duplicate drop"
                )
            }
        }
    }

    private func performFirstFarmersTransform(
        app: XCUIApplication,
        touchSurface: XCUIElement,
        elementIDs: [String]
    ) {
        // These three shared-state worlds use the baseline crop. A long
        // upward drag begins inside each authored target and crosses its
        // complete threshold without relying on a semantic action.
        let targetX = [0.1785714, 0.5000000, 0.8214286]
        for (index, elementID) in elementIDs.enumerated() {
            let semantic = app.descendants(matching: .any)[
                "chapter-semantic-\(elementID)"
            ]
            XCTAssertTrue(semantic.waitForExistence(timeout: 3))
            func dragActiveStage() {
                let start = touchSurface.coordinate(
                    withNormalizedOffset: CGVector(
                        dx: targetX[index],
                        dy: 0.55
                    )
                )
                let end = touchSurface.coordinate(
                    withNormalizedOffset: CGVector(
                        dx: targetX[index],
                        dy: 0.08
                    )
                )
                start.press(forDuration: 0.15, thenDragTo: end)
            }
            func currentStageStillExists() -> Bool {
                app.descendants(matching: .any)[
                    "chapter-semantic-\(elementID)"
                ].waitForExistence(timeout: 1)
            }
            let completion = index == elementIDs.indices.last
                ? app.buttons["chapter-continue"]
                : app.descendants(matching: .any)[
                    "chapter-semantic-\(elementIDs[index + 1])"
                ]
            let road = app.buttons["chapter-road"]
            let failure = app.buttons["chapter-failure-return-to-road"]

            // Simulator saturation can discard a synthesized drag before it
            // reaches the real production gesture. Retry only while the exact
            // authored stage remains active, and always use physical input.
            for _ in 0 ..< 3 where !completion.exists {
                let inputReady = XCTNSPredicateExpectation(
                    predicate: NSPredicate(
                        format: "exists == true AND enabled == true"
                    ),
                    object: road
                )
                XCTAssertEqual(
                    XCTWaiter().wait(for: [inputReady], timeout: 8),
                    .completed,
                    "Transform input did not become ready"
                )
                dragActiveStage()
                if completion.waitForExistence(timeout: 3) { break }
                XCTAssertFalse(
                    failure.exists,
                    "The signed runtime failed during Transform"
                )
                if !currentStageStillExists() { break }
            }
            XCTAssertTrue(
                completion.waitForExistence(timeout: 8),
                index == elementIDs.indices.last
                    ? "The final physical stage did not complete Transform"
                    : "The physical transform did not reveal its next stage"
            )
        }
    }

    private struct ResponsiveAudioCursorDiagnostic:
        CustomStringConvertible,
        Equatable,
        Sendable
    {
        let sample: Int64
        let loop: UInt64

        var description: String { "\(sample)@\(loop)" }

        func isAtOrAfter(
            _ other: ResponsiveAudioCursorDiagnostic
        ) -> Bool {
            loop > other.loop || (loop == other.loop && sample >= other.sample)
        }

        func isStrictlyAfter(
            _ other: ResponsiveAudioCursorDiagnostic
        ) -> Bool {
            loop > other.loop || (loop == other.loop && sample > other.sample)
        }
    }

    private struct ResponsiveAudioRuntimeDiagnostic: Sendable {
        let playback: String
        let stage: String
        let phase: String
        let durablePhase: String
        let pending: String
        let pause: String
        let liveCursor: ResponsiveAudioCursorDiagnostic?
        let durableCursor: ResponsiveAudioCursorDiagnostic?
    }

    private struct ResponsiveAudioBindingDiagnostic: Sendable {
        let status: String
        let stage: String
        let generation: UInt64
        let identity: String?
    }

    private enum ResponsiveAudioDiagnosticError: Error {
        case unavailable(String)
        case malformed(String)
    }

    private func waitForResponsiveAudioBinding(
        _ element: XCUIElement,
        stage: String,
        generation: UInt64? = nil,
        timeout: TimeInterval = 5
    ) throws -> ResponsiveAudioBindingDiagnostic {
        let prefix: String
        if let generation {
            prefix = "ready;stage=\(stage);generation=\(generation);"
        } else {
            prefix = "ready;stage=\(stage);"
        }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value BEGINSWITH %@ AND value CONTAINS %@ AND enabled == true",
                prefix,
                "identity=exact"
            ),
            object: element
        )
        guard XCTWaiter().wait(for: [expectation], timeout: timeout)
                == .completed,
              let value = element.value as? String else {
            throw ResponsiveAudioDiagnosticError.unavailable(
                "Binding did not reach \(prefix): \(String(describing: element.value))"
            )
        }
        return try Self.parseResponsiveAudioBinding(value)
    }

    private func waitForResponsiveAudioPhysicalState(
        _ element: XCUIElement,
        playback: String,
        pause: String,
        timeout: TimeInterval = 5
    ) throws -> ResponsiveAudioRuntimeDiagnostic {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ "
                        + "AND NOT (value CONTAINS %@) "
                        + "AND NOT (value CONTAINS %@) AND enabled == true",
                "playback=\(playback)",
                ";pause=\(pause);",
                ";liveCursor=none;",
                ";durableCursor=none;"
            ),
            object: element
        )
        guard XCTWaiter().wait(for: [expectation], timeout: timeout)
                == .completed,
              let value = element.value as? String else {
            throw ResponsiveAudioDiagnosticError.unavailable(
                "Physical state \(playback)/\(pause) was not durable: "
                    + String(describing: element.value)
            )
        }
        return try Self.parseResponsiveAudioRuntime(value)
    }

    private func waitForResponsiveAudioPlaybackState(
        _ element: XCUIElement,
        playback: String,
        pause: String,
        timeout: TimeInterval = 5
    ) throws -> ResponsiveAudioRuntimeDiagnostic {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format:
                    "value CONTAINS %@ AND value CONTAINS %@ AND enabled == true",
                "playback=\(playback)",
                ";pause=\(pause);"
            ),
            object: element
        )
        guard XCTWaiter().wait(for: [expectation], timeout: timeout)
                == .completed,
              let value = element.value as? String else {
            throw ResponsiveAudioDiagnosticError.unavailable(
                "Physical state \(playback)/\(pause) was unavailable: "
                    + String(describing: element.value)
            )
        }
        return try Self.parseResponsiveAudioRuntime(value)
    }

    private func waitForResponsiveAudioCursorAdvance(
        _ element: XCUIElement,
        liveAfter: ResponsiveAudioCursorDiagnostic,
        durableAfter: ResponsiveAudioCursorDiagnostic,
        playback: String,
        pause: String,
        timeout: TimeInterval = 5
    ) throws -> ResponsiveAudioRuntimeDiagnostic {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let candidate = object as? XCUIElement,
                      candidate.isEnabled,
                      let value = candidate.value as? String,
                      let runtime = try? Self.parseResponsiveAudioRuntime(
                        value
                      ),
                      runtime.playback == playback,
                      runtime.pause == pause,
                      let liveCursor = runtime.liveCursor,
                      let durableCursor = runtime.durableCursor else {
                    return false
                }
                return liveCursor.isStrictlyAfter(liveAfter)
                    && durableCursor.isStrictlyAfter(durableAfter)
            },
            object: element
        )
        guard XCTWaiter().wait(for: [expectation], timeout: timeout)
                == .completed,
              let value = element.value as? String else {
            throw ResponsiveAudioDiagnosticError.unavailable(
                "Audio cursors did not advance beyond "
                    + "(liveAfter)/(durableAfter): "
                    + String(describing: element.value)
            )
        }
        return try Self.parseResponsiveAudioRuntime(value)
    }

    private func waitForResponsiveAudioDurablePause(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) throws -> ResponsiveAudioRuntimeDiagnostic {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let candidate = object as? XCUIElement,
                      candidate.isEnabled,
                      let value = candidate.value as? String,
                      let runtime = try? Self.parseResponsiveAudioRuntime(
                        value
                      ),
                      runtime.playback == "paused",
                      (runtime.pause == "sceneInactive"
                        || runtime.pause == "sceneBackground"),
                      let liveCursor = runtime.liveCursor,
                      liveCursor == runtime.durableCursor else {
                    return false
                }
                return true
            },
            object: element
        )
        guard XCTWaiter().wait(for: [expectation], timeout: timeout)
                == .completed,
              let value = element.value as? String else {
            throw ResponsiveAudioDiagnosticError.unavailable(
                "Audio did not reach a lifecycle-paused durable cursor: "
                    + String(describing: element.value)
            )
        }
        return try Self.parseResponsiveAudioRuntime(value)
    }

    private func waitForResponsiveAudioLifecyclePause(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) throws -> ResponsiveAudioRuntimeDiagnostic {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let candidate = object as? XCUIElement,
                      candidate.isEnabled,
                      let value = candidate.value as? String,
                      let runtime = try? Self.parseResponsiveAudioRuntime(
                        value
                      ) else {
                    return false
                }
                return runtime.playback == "paused"
                    && (runtime.pause == "sceneInactive"
                        || runtime.pause == "sceneBackground")
            },
            object: element
        )
        guard XCTWaiter().wait(for: [expectation], timeout: timeout)
                == .completed,
              let value = element.value as? String else {
            throw ResponsiveAudioDiagnosticError.unavailable(
                "Audio did not reach a lifecycle pause: "
                    + String(describing: element.value)
            )
        }
        return try Self.parseResponsiveAudioRuntime(value)
    }

    nonisolated private static func parseResponsiveAudioBinding(
        _ value: String
    ) throws -> ResponsiveAudioBindingDiagnostic {
        let components = value.split(separator: ";").map(String.init)
        guard let status = components.first else {
            throw ResponsiveAudioDiagnosticError.malformed(value)
        }
        let fields = diagnosticFields(in: components.dropFirst())
        guard let stage = fields["stage"],
              let generationRaw = fields["generation"],
              let generation = UInt64(generationRaw) else {
            throw ResponsiveAudioDiagnosticError.malformed(value)
        }
        return ResponsiveAudioBindingDiagnostic(
            status: status,
            stage: stage,
            generation: generation,
            identity: fields["identity"]
        )
    }

    nonisolated private static func parseResponsiveAudioRuntime(
        _ value: String
    ) throws -> ResponsiveAudioRuntimeDiagnostic {
        let fields = diagnosticFields(
            in: value.split(separator: ";").map(String.init)[...]
        )
        guard let playback = fields["playback"],
              let stage = fields["stage"],
              let phase = fields["phase"],
              let durablePhase = fields["durable"],
              let pending = fields["pending"],
              let pause = fields["pause"],
              let liveRaw = fields["liveCursor"],
              let durableRaw = fields["durableCursor"] else {
            throw ResponsiveAudioDiagnosticError.malformed(value)
        }
        return ResponsiveAudioRuntimeDiagnostic(
            playback: playback,
            stage: stage,
            phase: phase,
            durablePhase: durablePhase,
            pending: pending,
            pause: pause,
            liveCursor: try parseResponsiveAudioCursor(liveRaw),
            durableCursor: try parseResponsiveAudioCursor(durableRaw)
        )
    }

    nonisolated private static func parseResponsiveAudioCursor(
        _ value: String
    ) throws -> ResponsiveAudioCursorDiagnostic? {
        guard value != "none" else { return nil }
        let components = value.split(
            separator: "@",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard components.count == 2,
              let sample = Int64(components[0]),
              let loop = UInt64(components[1]) else {
            throw ResponsiveAudioDiagnosticError.malformed(value)
        }
        return ResponsiveAudioCursorDiagnostic(sample: sample, loop: loop)
    }

    nonisolated private static func diagnosticFields<C: Collection>(
        in components: C
    ) -> [String: String] where C.Element == String {
        components.reduce(into: [:]) { fields, component in
            let pair = component.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            guard pair.count == 2 else { return }
            fields[String(pair[0])] = String(pair[1])
        }
    }

    private func wait(
        for element: XCUIElement,
        toHaveValue value: String,
        timeout: TimeInterval = 3
    ) {
        let predicate = NSPredicate(
            format: "value == %@ AND enabled == true",
            value
        )
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: element
        )
        guard XCTWaiter().wait(for: [expectation], timeout: timeout)
                == .completed else {
            XCTFail(
                "Expected \(element.identifier) to equal \(value); actual: "
                    + String(describing: element.value)
            )
            return
        }
    }

    private func resumeResponsiveAudioIfNeeded(
        phaseState: XCUIElement,
        soundControl: XCUIElement
    ) {
        let playable = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value == %@ OR value == %@",
                "playing:waiting",
                "resumeRequired:waiting"
            ),
            object: phaseState
        )
        guard XCTWaiter().wait(for: [playable], timeout: 8)
                == .completed else {
            XCTFail(
                "Audio did not become playable: "
                    + String(describing: phaseState.value)
            )
            return
        }
        if phaseState.value as? String == "resumeRequired:waiting" {
            soundControl.tap()
        }
        wait(
            for: phaseState,
            toHaveValue: "playing:waiting",
            timeout: 8
        )
    }

    private func openLockedSteppeRoad(in app: XCUIApplication) {
        let lockedRoad = app.buttons["chapter-road-steppe-comes-west"]
        XCTAssertTrue(lockedRoad.waitForExistence(timeout: 5))
        for _ in 0 ..< 20 where !lockedRoad.isHittable {
            if lockedRoad.frame.midY > app.frame.midY {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
        }
        XCTAssertTrue(lockedRoad.isHittable)
        lockedRoad.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["locked-road-purchase"]
                .waitForExistence(timeout: 5)
        )
    }

    private func wait(
        for element: XCUIElement,
        toHaveValueBeginningWith prefix: String,
        timeout: TimeInterval = 3
    ) {
        let predicate = NSPredicate(
            format: "value BEGINSWITH %@ AND enabled == true",
            prefix
        )
        let expectation = expectation(
            for: predicate,
            evaluatedWith: element
        )
        wait(for: [expectation], timeout: timeout)
    }

    private func wait(
        for element: XCUIElement,
        toHaveValueContaining fragment: String,
        timeout: TimeInterval = 3
    ) {
        let predicate = NSPredicate(
            format: "value CONTAINS %@ AND enabled == true",
            fragment
        )
        let expectation = expectation(
            for: predicate,
            evaluatedWith: element
        )
        wait(for: [expectation], timeout: timeout)
    }
}
