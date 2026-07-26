@testable import ContentDelivery
import ExperiencePreferences
import XCTest

final class DownloadInitiationPolicyTests: XCTestCase {
    func testEveryNetworkIntentAndDownloadPreferenceCombination() {
        var evaluatedCombinationCount = 0
        var observedBlockReasons: Set<DownloadInitiationBlockReason> = []

        for cellularDownloadsEnabled in [false, true] {
            for automaticDeepDiveDownloadsEnabled in [false, true] {
                let preferences = ExperiencePreferences(
                    cellularDownloadsEnabled: cellularDownloadsEnabled,
                    automaticDeepDiveDownloadsEnabled: automaticDeepDiveDownloadsEnabled
                )
                let policy = DownloadInitiationPolicy(preferences: preferences)

                for isConstrained in [false, true] {
                    for networkBasis in DownloadNetworkBasis.allCases {
                        for intent in DownloadInitiationIntent.allCases {
                            let decision = policy.decision(
                                for: intent,
                                networkBasis: networkBasis,
                                isConstrained: isConstrained
                            )
                            let expected = Self.expectedDecision(
                                intent: intent,
                                networkBasis: networkBasis,
                                isConstrained: isConstrained,
                                cellularDownloadsEnabled: cellularDownloadsEnabled,
                                automaticDeepDiveDownloadsEnabled:
                                    automaticDeepDiveDownloadsEnabled
                            )

                            XCTAssertEqual(
                                decision,
                                expected,
                                "Unexpected decision for \(networkBasis), \(intent), "
                                    + "constrained=\(isConstrained), "
                                    + "cellular=\(cellularDownloadsEnabled), "
                                    + "automatic=\(automaticDeepDiveDownloadsEnabled)"
                            )
                            XCTAssertEqual(
                                decision.shouldInitiateNewRequest,
                                expected == .initiateNewRequest
                            )
                            if case let .doNotInitiateNewRequest(reason) = decision {
                                observedBlockReasons.insert(reason)
                            }
                            evaluatedCombinationCount += 1
                        }
                    }
                }
            }
        }

        XCTAssertEqual(evaluatedCombinationCount, 120)
        XCTAssertEqual(observedBlockReasons, Set(DownloadInitiationBlockReason.allCases))
    }

    func testEveryAudioAndHapticPreferenceCombinationLeavesDeliveryUnchanged() {
        for cellularDownloadsEnabled in [false, true] {
            for automaticDeepDiveDownloadsEnabled in [false, true] {
                let baseline = DownloadInitiationPolicy(preferences: ExperiencePreferences(
                    cellularDownloadsEnabled: cellularDownloadsEnabled,
                    automaticDeepDiveDownloadsEnabled: automaticDeepDiveDownloadsEnabled
                ))

                for audioMask in 0 ..< 16 {
                    let varied = DownloadInitiationPolicy(preferences: ExperiencePreferences(
                        narrationEnabled: audioMask & 1 != 0,
                        scoreEnabled: audioMask & 2 != 0,
                        soundscapeEnabled: audioMask & 4 != 0,
                        hapticsEnabled: audioMask & 8 != 0,
                        cellularDownloadsEnabled: cellularDownloadsEnabled,
                        automaticDeepDiveDownloadsEnabled:
                            automaticDeepDiveDownloadsEnabled
                    ))

                    XCTAssertEqual(varied, baseline)
                    for isConstrained in [false, true] {
                        for networkBasis in DownloadNetworkBasis.allCases {
                            for intent in DownloadInitiationIntent.allCases {
                                XCTAssertEqual(
                                    varied.decision(
                                        for: intent,
                                        networkBasis: networkBasis,
                                        isConstrained: isConstrained
                                    ),
                                    baseline.decision(
                                        for: intent,
                                        networkBasis: networkBasis,
                                        isConstrained: isConstrained
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func testNetworkChangeDeclinesOnlyANewRequestAndCannotExpressTransferCancellation() {
        let policy = DownloadInitiationPolicy(preferences: ExperiencePreferences(
            cellularDownloadsEnabled: true,
            automaticDeepDiveDownloadsEnabled: true
        ))

        let originalRequest = policy.decision(
            for: .explicitDownloadAll,
            networkBasis: .wifi
        )
        let nextRequestAfterNetworkLoss = policy.decision(
            for: .explicitDownloadAll,
            networkBasis: .offline
        )

        XCTAssertEqual(originalRequest, .initiateNewRequest)
        XCTAssertEqual(
            nextRequestAfterNetworkLoss,
            .doNotInitiateNewRequest(reason: .offline)
        )
        assertDecisionContainsNoExistingTransferCommand(originalRequest)
        assertDecisionContainsNoExistingTransferCommand(nextRequestAfterNetworkLoss)
    }

    private static func expectedDecision(
        intent: DownloadInitiationIntent,
        networkBasis: DownloadNetworkBasis,
        isConstrained: Bool,
        cellularDownloadsEnabled: Bool,
        automaticDeepDiveDownloadsEnabled: Bool
    ) -> DownloadInitiationDecision {
        switch networkBasis {
        case .offline:
            return .doNotInitiateNewRequest(reason: .offline)
        case .unknown:
            return .doNotInitiateNewRequest(reason: .unknownNetwork)
        case .cellular where !cellularDownloadsEnabled:
            return .doNotInitiateNewRequest(reason: .cellularDownloadsDisabled)
        case .wifi, .wired, .cellular:
            break
        }

        if intent == .automaticDeepDive,
           !automaticDeepDiveDownloadsEnabled {
            return .doNotInitiateNewRequest(reason: .automaticDeepDiveDownloadsDisabled)
        }
        if intent == .automaticDeepDive, isConstrained {
            return .doNotInitiateNewRequest(reason: .lowDataMode)
        }
        return .initiateNewRequest
    }

    /// An exhaustive switch makes a future cancel/suspend case fail this test's
    /// compilation until the initiation-only contract is deliberately reopened.
    private func assertDecisionContainsNoExistingTransferCommand(
        _ decision: DownloadInitiationDecision,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch decision {
        case .initiateNewRequest:
            XCTAssertTrue(decision.shouldInitiateNewRequest, file: file, line: line)
        case .doNotInitiateNewRequest:
            XCTAssertFalse(decision.shouldInitiateNewRequest, file: file, line: line)
        }
    }
}
