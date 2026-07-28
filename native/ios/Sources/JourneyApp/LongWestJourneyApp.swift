import Foundation
import QualityInstrumentation
import ReleaseDiscovery
import SwiftUI

@main
struct LongWestJourneyApp: App {
    @UIApplicationDelegateAdaptor(JourneyAppDelegate.self)
    private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var releaseDiscovery: ReleaseDiscoveryApplicationModel
    private let futureReleaseClient: JourneyFutureReleaseClient?

    init() {
        let processStartMonotonicNanosecondsSinceBoot =
            DispatchTime.now().uptimeNanoseconds
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        _ = PerformanceCaptureRuntime.shared.bootstrapIfRequested(
            applicationSupportURL: applicationSupport,
            processStartMonotonicNanosecondsSinceBoot:
                processStartMonotonicNanosecondsSinceBoot
        )
#if DEBUG || NON_SHIPPING_LIVE_TEST
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reset-state") {
            for directoryName in [
                "journey-progress-v1",
                "commerce-v1",
                "experience-preferences-v1",
                "content-delivery-v1",
                "future-content-delivery-v1",
                "release-discovery-local-v1",
                "release-install-contracts-local-v1",
                "non-shipping-review-primary-audio-cursor-v1",
            ] {
                try? FileManager.default.removeItem(
                    at: applicationSupport.appendingPathComponent(
                        directoryName,
                        isDirectory: true
                    )
                )
            }
        }
#endif
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-reset-release-discovery"
        ) {
            try? FileManager.default.removeItem(
                at: applicationSupport.appendingPathComponent(
                    "release-discovery-local-v1",
                    isDirectory: true
                )
            )
        }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-future-preferences") {
            Self.installFuturePreferencesFixture()
        }
#endif
        let releaseServices = JourneyReleaseDiscoveryComposition.make(
            applicationSupportURL: applicationSupport
        )
        let releaseDiscovery = releaseServices.applicationModel
        _releaseDiscovery = StateObject(wrappedValue: releaseDiscovery)
        var preparedFutureReleaseClient = releaseServices.futureReleaseClient
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains(
            "--ui-testing-future-release-controls"
        ) {
            preparedFutureReleaseClient = .developmentPresentationFixture(
                failsFirstBootstrap: ProcessInfo.processInfo.arguments.contains(
                    "--ui-testing-future-release-bootstrap-retry"
                ),
                initiallyInstalled: ProcessInfo.processInfo.arguments.contains(
                    "--ui-testing-future-release-installed"
                ),
                awaitingRestore: ProcessInfo.processInfo.arguments.contains(
                    "--ui-testing-future-release-awaiting-restore"
                )
            )
        }
#endif
        futureReleaseClient = preparedFutureReleaseClient
        JourneyReleaseDiscoveryBridge.shared.install(releaseDiscovery)
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                releaseDiscovery: releaseDiscovery,
                futureReleaseClient: futureReleaseClient
            )
                .environmentObject(releaseDiscovery)
                .task {
                    await releaseDiscovery.applicationDidBecomeActive()
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains(
                        "--ui-testing-release-deep-link"
                    ) {
                        await releaseDiscovery.openRelease(
                            "release-local-fixture-v1"
                        )
                    }
#endif
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await releaseDiscovery.applicationDidBecomeActive()
                        }
                    } else if PerformanceCaptureRuntime.shared.recorder != nil {
                        Task {
                            _ = try? await PerformanceCaptureRuntime.shared.exportActiveReport()
                        }
                    }
                }
        }
    }

#if DEBUG
    private static func installFuturePreferencesFixture() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directory = applicationSupport.appendingPathComponent(
            "experience-preferences-v1",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let bytes = Data(
            #"{"schemaVersion":99,"futureMeaning":["preserve","do-not-overwrite"]}"#.utf8
        )
        try? bytes.write(
            to: directory.appendingPathComponent("experience-preferences.json"),
            options: .atomic
        )
    }
#endif
}
