@testable import ContentDelivery
import ContentKit
import ExperiencePreferences
import Foundation
import XCTest

#if canImport(Network)
final class DownloadNetworkMonitorTests: XCTestCase {
    func testProviderIsUnknownBeforeFirstPathAndReturnsToUnknownWhenStopped() {
        let monitor = RecordingDownloadNetworkPathMonitor()
        let provider = NWPathDownloadNetworkBasisProvider(monitor: monitor)

        XCTAssertEqual(provider.currentNetworkBasis(), .unknown)
        XCTAssertEqual(provider.currentNetworkContext(), .unknown)
        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertTrue(monitor.hasPathUpdate)

        monitor.emit(.init(
            status: .satisfied,
            activeInterfaces: [.wifi],
            isConstrained: true
        ))
        XCTAssertEqual(provider.currentNetworkBasis(), .wifi)
        XCTAssertEqual(
            provider.currentNetworkContext(),
            DownloadNetworkContext(basis: .wifi, isConstrained: true)
        )

        provider.stop()
        provider.stop()

        XCTAssertEqual(provider.currentNetworkBasis(), .unknown)
        XCTAssertEqual(provider.currentNetworkContext(), .unknown)
        XCTAssertEqual(monitor.cancelCount, 1)
        XCTAssertFalse(monitor.hasPathUpdate)

        monitor.emit(.init(status: .satisfied, activeInterfaces: [.cellular]))
        XCTAssertEqual(provider.currentNetworkBasis(), .unknown)
    }

    func testStatusAndInterfaceMappingUsesConservativeDeterministicPriority() {
        let monitor = RecordingDownloadNetworkPathMonitor()
        let provider = NWPathDownloadNetworkBasisProvider(monitor: monitor)

        let cases: [(DownloadNetworkPathSnapshot, DownloadNetworkBasis)] = [
            (.init(status: .unsatisfied, activeInterfaces: [.cellular, .wifi, .wired]), .offline),
            (.init(status: .requiresConnection, activeInterfaces: [.wifi]), .unknown),
            (.init(status: .unknown, activeInterfaces: [.wired]), .unknown),
            (.init(status: .satisfied, activeInterfaces: [.wifi], isExpensive: true), .cellular),
            (.init(status: .satisfied, activeInterfaces: [.wired], isExpensive: true), .cellular),
            (.init(status: .satisfied, activeInterfaces: [.cellular, .wifi, .wired]), .cellular),
            (.init(status: .satisfied, activeInterfaces: [.wifi, .wired]), .wifi),
            (.init(status: .satisfied, activeInterfaces: [.wired]), .wired),
            (.init(status: .satisfied, activeInterfaces: [.other]), .unknown),
            (.init(status: .satisfied), .unknown),
        ]

        for (snapshot, expectedBasis) in cases {
            monitor.emit(snapshot)
            XCTAssertEqual(
                provider.currentNetworkBasis(),
                expectedBasis,
                "Unexpected mapping for \(snapshot)"
            )
        }

        provider.stop()
    }

    func testProviderDoesNotRetainItselfThroughTheMonitorCallback() {
        let monitor = RecordingDownloadNetworkPathMonitor()
        weak var weakProvider: NWPathDownloadNetworkBasisProvider?

        autoreleasepool {
            let provider = NWPathDownloadNetworkBasisProvider(monitor: monitor)
            weakProvider = provider
            XCTAssertNotNil(weakProvider)
        }

        XCTAssertNil(weakProvider)
        XCTAssertEqual(monitor.cancelCount, 1)
        XCTAssertFalse(monitor.hasPathUpdate)
    }
}
#endif

final class DownloadRequestInitiatorTests: XCTestCase {
    func testBlockedRequestsHaveNoStartSideEffect() async throws {
        let provider = MutableDownloadNetworkBasisProvider(.unknown)
        let starts = DownloadStartRecorder()
        let initiator = DownloadRequestInitiator(
            networkBasisProvider: provider,
            startOperation: { intent in await starts.record(intent) }
        )

        let cases: [(DownloadNetworkBasis, DownloadInitiationIntent, ExperiencePreferences,
                     DownloadInitiationBlockReason)] = [
            (.unknown, .explicitSinglePackage, .standard, .unknownNetwork),
            (.offline, .explicitDownloadAll, .standard, .offline),
            (.cellular, .explicitSinglePackage, .standard, .cellularDownloadsDisabled),
            (.wifi, .automaticDeepDive, .standard, .automaticDeepDiveDownloadsDisabled),
        ]

        for (networkBasis, intent, preferences, expectedReason) in cases {
            provider.set(networkBasis)
            let result = try await initiator.initiateNewRequest(
                intent: intent,
                preferences: preferences
            )
            XCTAssertEqual(result, .didNotStartNewRequest(reason: expectedReason))
        }

        let recordedIntents = await starts.intents()
        XCTAssertEqual(recordedIntents, [])
    }

    func testCurrentPreferencesAndLatestNetworkBasisAreReadForEveryCall() async throws {
        let provider = MutableDownloadNetworkBasisProvider(.cellular)
        let starts = DownloadStartRecorder()
        let initiator = DownloadRequestInitiator(
            networkBasisProvider: provider,
            startOperation: { intent in await starts.record(intent) }
        )

        let blockedCellular = try await initiator.initiateNewRequest(
            intent: .explicitSinglePackage,
            preferences: .standard
        )
        let allowedCellular = try await initiator.initiateNewRequest(
            intent: .explicitSinglePackage,
            preferences: ExperiencePreferences(cellularDownloadsEnabled: true)
        )

        provider.set(.wifi)
        let blockedAutomatic = try await initiator.initiateNewRequest(
            intent: .automaticDeepDive,
            preferences: ExperiencePreferences(cellularDownloadsEnabled: true)
        )
        let allowedAutomatic = try await initiator.initiateNewRequest(
            intent: .automaticDeepDive,
            preferences: ExperiencePreferences(
                cellularDownloadsEnabled: false,
                automaticDeepDiveDownloadsEnabled: true
            )
        )

        XCTAssertEqual(
            blockedCellular,
            .didNotStartNewRequest(reason: .cellularDownloadsDisabled)
        )
        XCTAssertEqual(allowedCellular, .startedNewRequest)
        XCTAssertEqual(
            blockedAutomatic,
            .didNotStartNewRequest(reason: .automaticDeepDiveDownloadsDisabled)
        )
        XCTAssertEqual(allowedAutomatic, .startedNewRequest)
        let recordedIntents = await starts.intents()
        XCTAssertEqual(recordedIntents, [.explicitSinglePackage, .automaticDeepDive])
        XCTAssertEqual(provider.readCount, 4)
    }

    func testLowDataModeBlocksOnlyAutomaticDeepDiveInitiation() async throws {
        let provider = MutableDownloadNetworkBasisProvider(.wifi)
        provider.set(DownloadNetworkContext(basis: .wifi, isConstrained: true))
        let starts = DownloadStartRecorder()
        let initiator = DownloadRequestInitiator(
            networkBasisProvider: provider,
            startOperation: { intent in await starts.record(intent) }
        )
        let preferences = ExperiencePreferences(
            automaticDeepDiveDownloadsEnabled: true
        )

        let automatic = try await initiator.initiateNewRequest(
            intent: .automaticDeepDive,
            preferences: preferences
        )
        let explicit = try await initiator.initiateNewRequest(
            intent: .explicitDownloadAll,
            preferences: preferences
        )

        XCTAssertEqual(automatic, .didNotStartNewRequest(reason: .lowDataMode))
        XCTAssertEqual(explicit, .startedNewRequest)
        let recordedIntents = await starts.intents()
        XCTAssertEqual(recordedIntents, [.explicitDownloadAll])
    }

    func testStartFailurePropagatesInsteadOfBecomingAPolicyBlock() async {
        let provider = MutableDownloadNetworkBasisProvider(.wired)
        let initiator = DownloadRequestInitiator(
            networkBasisProvider: provider,
            startOperation: { _ in throw DownloadStartTestError.rejected }
        )

        do {
            _ = try await initiator.initiateNewRequest(
                intent: .explicitDownloadAll,
                preferences: .standard
            )
            XCTFail("Expected the injected start error")
        } catch {
            XCTAssertEqual(error as? DownloadStartTestError, .rejected)
        }
    }

    func testConcurrentAttemptsStillExposePackageBatchInstallerAlreadyRunning() async throws {
        let provider = MutableDownloadNetworkBasisProvider(.wifi)
        let installGate = DownloadInstallGate()
        let packages = Self.packages(count: 2)
        let installer = PackageBatchInstaller { package in
            await installGate.waitForRelease(package.id)
            return Self.activation(for: package)
        }
        let initiator = DownloadRequestInitiator(
            networkBasisProvider: provider,
            startOperation: { _ in try await installer.start(packages: packages) }
        )

        let first = Task<DownloadRequestInitiationResult, any Error> {
            try await initiator.initiateNewRequest(
                intent: .explicitDownloadAll,
                preferences: .standard
            )
        }
        let second = Task<DownloadRequestInitiationResult, any Error> {
            try await initiator.initiateNewRequest(
                intent: .explicitDownloadAll,
                preferences: .standard
            )
        }

        let firstResult = await first.result
        let secondResult = await second.result
        var successful: [DownloadRequestInitiationResult] = []
        var failures: [PackageBatchInstallationError] = []
        for result in [firstResult, secondResult] {
            switch result {
            case let .success(value):
                successful.append(value)
            case let .failure(error):
                if let installerError = error as? PackageBatchInstallationError {
                    failures.append(installerError)
                }
            }
        }

        XCTAssertEqual(successful, [.startedNewRequest])
        XCTAssertEqual(failures, [.alreadyRunning])

        let firstPackageStarted = await Self.eventually {
            await installGate.startedPackageIDs().first == packages[0].id
        }
        XCTAssertTrue(firstPackageStarted)
        await installGate.release(packages[0].id)

        let secondPackageStarted = await Self.eventually {
            await installGate.startedPackageIDs().count == 2
        }
        XCTAssertTrue(secondPackageStarted)
        await installGate.release(packages[1].id)

        let completed = await Self.eventually {
            await installer.state() == .completed(installedPackageIDs: packages.map(\.id))
        }
        XCTAssertTrue(completed)
    }

    private static func packages(count: Int) -> [ContentPackageSpec] {
        (0 ..< count).map { index in
            ContentPackageSpec(
                id: PackageID(rawValue: "network-request-package-\(index)"),
                version: .init(major: 1),
                chapterIDs: [ChapterID(rawValue: "network-request-chapter-\(index)")],
                maximumInstalledBytes: 1,
                minimumRuntime: .init(major: 1),
                isEssentialInstall: false
            )
        }
    }

    private static func activation(for package: ContentPackageSpec) -> ActivatedPackage {
        ActivatedPackage(
            generation: InstalledPackageGeneration(
                generationID: "generation-\(package.id.rawValue)",
                packageID: package.id,
                packageVersion: package.version,
                manifestDigest: String(repeating: "a", count: 64),
                relativePath: "generations/\(package.id.rawValue)",
                activationSequence: 1
            ),
            packageURL: URL(fileURLWithPath: "/tmp/\(package.id.rawValue)")
        )
    }

    private static func eventually(
        attempts: Int = 2_000,
        condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0 ..< attempts {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }
}

#if canImport(Network)
private final class RecordingDownloadNetworkPathMonitor:
    DownloadNetworkPathMonitoring,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var pathUpdate: (@Sendable (DownloadNetworkPathSnapshot) -> Void)?
    private var starts = 0
    private var cancellations = 0

    var startCount: Int { lock.withLock { starts } }
    var cancelCount: Int { lock.withLock { cancellations } }
    var hasPathUpdate: Bool { lock.withLock { pathUpdate != nil } }

    func start(
        pathUpdate: @escaping @Sendable (DownloadNetworkPathSnapshot) -> Void
    ) {
        lock.withLock {
            starts += 1
            self.pathUpdate = pathUpdate
        }
    }

    func cancel() {
        lock.withLock {
            cancellations += 1
            pathUpdate = nil
        }
    }

    func emit(_ snapshot: DownloadNetworkPathSnapshot) {
        let update = lock.withLock { pathUpdate }
        update?(snapshot)
    }
}
#endif

private final class MutableDownloadNetworkBasisProvider:
    DownloadNetworkBasisProviding,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var basis: DownloadNetworkBasis
    private var isConstrained = false
    private var reads = 0

    init(_ basis: DownloadNetworkBasis) {
        self.basis = basis
    }

    var readCount: Int { lock.withLock { reads } }

    func currentNetworkBasis() -> DownloadNetworkBasis {
        lock.withLock {
            reads += 1
            return basis
        }
    }

    func currentNetworkContext() -> DownloadNetworkContext {
        lock.withLock {
            reads += 1
            return DownloadNetworkContext(
                basis: basis,
                isConstrained: isConstrained
            )
        }
    }

    func set(_ basis: DownloadNetworkBasis) {
        lock.withLock {
            self.basis = basis
            isConstrained = false
        }
    }

    func set(_ context: DownloadNetworkContext) {
        lock.withLock {
            basis = context.basis
            isConstrained = context.isConstrained
        }
    }
}

private actor DownloadStartRecorder {
    private var recordedIntents: [DownloadInitiationIntent] = []

    func record(_ intent: DownloadInitiationIntent) {
        recordedIntents.append(intent)
    }

    func intents() -> [DownloadInitiationIntent] {
        recordedIntents
    }
}

private enum DownloadStartTestError: Error, Equatable {
    case rejected
}

private actor DownloadInstallGate {
    private var started: [PackageID] = []
    private var released: Set<PackageID> = []
    private var continuations: [PackageID: CheckedContinuation<Void, Never>] = [:]

    func waitForRelease(_ packageID: PackageID) async {
        started.append(packageID)
        if released.remove(packageID) != nil { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            continuations[packageID] = continuation
        }
    }

    func release(_ packageID: PackageID) {
        if let continuation = continuations.removeValue(forKey: packageID) {
            continuation.resume()
        } else {
            released.insert(packageID)
        }
    }

    func startedPackageIDs() -> [PackageID] {
        started
    }
}
