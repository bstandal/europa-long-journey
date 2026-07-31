import ContentKit
import CryptoKit
import Darwin
import ExperiencePreferences
import Foundation

public protocol OfflineAudioAssetResolving: Sendable {
    func url(for packageRelativePath: String) throws -> URL
}

/// Moves first-use digest work for the exact authored plan away from the main
/// actor. Cancellation propagates into manifest hashing at each streamed
/// chunk; successful return leaves the shared resolver cache warm for the
/// native transport's mandatory second lookup.
public enum OfflineAudioAssetPrewarmer {
    public static func prewarm(
        paths: [String],
        resolver: any OfflineAudioAssetResolving
    ) async throws {
        let uniquePaths = Array(Set(paths)).sorted()
        let task = Task.detached(priority: .userInitiated) {
            for path in uniquePaths {
                try Task.checkCancellation()
                _ = try resolver.url(for: path)
            }
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

public enum OfflineAudioAssetResolutionError: Error, Equatable, Sendable {
    case invalidVerifiedPackageRoot
    case unsafePath(String)
    case missingFile(String)
    case pathEscapedRoot(String)
    case symbolicLink(String)
    case notRegularFile(String)
    case duplicateManifestRecord(String)
    case missingManifestRecord(String)
    case assetNotDeclaredByAudioTimeline(String)
    case manifestSizeMismatch(String)
    case manifestDigestMismatch(String)
    case fileChangedDuringVerification(String)
}

public struct PackageRootAudioAssetResolver: OfflineAudioAssetResolving {
    public let packageRootURL: URL

    public init(packageRootURL: URL) {
        self.packageRootURL = packageRootURL.resolvingSymlinksInPath().standardizedFileURL
    }

    public func url(for packageRelativePath: String) throws -> URL {
        let components = packageRelativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !packageRelativePath.isEmpty,
              !packageRelativePath.hasPrefix("/"),
              !packageRelativePath.contains("\\"),
              !packageRelativePath.contains("://"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw OfflineAudioAssetResolutionError.unsafePath(packageRelativePath)
        }
        let candidate = packageRootURL.appending(
            path: packageRelativePath,
            directoryHint: .notDirectory
        ).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(packageRootURL.path + "/") else {
            throw OfflineAudioAssetResolutionError.pathEscapedRoot(packageRelativePath)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw OfflineAudioAssetResolutionError.missingFile(packageRelativePath)
        }
        return candidate
    }
}

/// Production audio boundary for an already verifier-created package value.
/// A URL is returned only after the requested timeline asset has been matched
/// to its signed manifest record and its current bytes have passed size and
/// SHA-256 verification. `NativeTimelineTransport` resolves again immediately
/// before every `AVAudioFile` construction.
public struct ManifestBoundAudioAssetResolver: OfflineAudioAssetResolving {
    private struct FileIdentity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
        let bytes: Int64
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
        let changeSeconds: Int64
        let changeNanoseconds: Int64
    }

    private struct CacheEntry: Equatable, Sendable {
        let manifestDigest: String
        let expectedBytes: Int64
        let expectedSHA256: String
        let identity: FileIdentity
    }

    private final class VerificationCache: @unchecked Sendable {
        let lock = NSLock()
        var entriesByPath: [String: CacheEntry] = [:]
        var fullHashCountByPath: [String: Int] = [:]
    }

    private let packageRootURL: URL
    private let recordsByPath: [String: PackageFileRecord]
    private let declaredAudioPaths: Set<String>
    private let manifestDigest: String
    private let cache: VerificationCache

    public init(
        verifiedPackage: VerifiedContentPackage,
        activatedPackageRoot: URL
    ) throws {
        packageRootURL = try Self.canonicalPackageRoot(activatedPackageRoot)

        var records: [String: PackageFileRecord] = [:]
        for record in verifiedPackage.manifest.files {
            guard records.updateValue(record, forKey: record.path) == nil else {
                throw OfflineAudioAssetResolutionError
                    .duplicateManifestRecord(record.path)
            }
        }
        recordsByPath = records
        manifestDigest = verifiedPackage.manifest.manifestDigest
        declaredAudioPaths = Set(
            verifiedPackage.payload.audioTimelines
                .flatMap(\.events)
                .compactMap { event in
                    event.role == .silence ? nil : event.assetPath
                }
        )
        cache = VerificationCache()
    }

    public func url(for packageRelativePath: String) throws -> URL {
        try Task.checkCancellation()
        try Self.validateSafePath(packageRelativePath)
        guard declaredAudioPaths.contains(packageRelativePath) else {
            throw OfflineAudioAssetResolutionError
                .assetNotDeclaredByAudioTimeline(packageRelativePath)
        }
        guard let record = recordsByPath[packageRelativePath] else {
            throw OfflineAudioAssetResolutionError
                .missingManifestRecord(packageRelativePath)
        }

        let expectedURL = packageRootURL
            .appending(path: packageRelativePath, directoryHint: .notDirectory)
            .standardizedFileURL
        guard expectedURL.path.hasPrefix(packageRootURL.path + "/") else {
            throw OfflineAudioAssetResolutionError.pathEscapedRoot(packageRelativePath)
        }
        cache.lock.lock()
        defer { cache.lock.unlock() }

        let canonicalBeforeRead = try Self.validateRegularFile(
            expectedURL,
            path: packageRelativePath,
            root: packageRootURL
        )
        let identityBeforeRead = try Self.fileIdentity(
            at: expectedURL,
            path: packageRelativePath
        )
        let expectedEntry = CacheEntry(
            manifestDigest: manifestDigest,
            expectedBytes: record.bytes,
            expectedSHA256: record.sha256,
            identity: identityBeforeRead
        )
        if cache.entriesByPath[packageRelativePath] == expectedEntry {
            return canonicalBeforeRead
        }

        cache.fullHashCountByPath[packageRelativePath, default: 0] += 1
        let (bytes, digest) = try Self.streamedDigest(
            expectedURL,
            path: packageRelativePath
        )
        let canonicalAfterRead = try Self.validateRegularFile(
            expectedURL,
            path: packageRelativePath,
            root: packageRootURL
        )
        let identityAfterRead = try Self.fileIdentity(
            at: expectedURL,
            path: packageRelativePath
        )
        guard canonicalAfterRead == canonicalBeforeRead,
              identityAfterRead == identityBeforeRead else {
            throw OfflineAudioAssetResolutionError
                .fileChangedDuringVerification(packageRelativePath)
        }
        guard bytes == record.bytes else {
            throw OfflineAudioAssetResolutionError.manifestSizeMismatch(packageRelativePath)
        }
        guard digest == record.sha256 else {
            throw OfflineAudioAssetResolutionError.manifestDigestMismatch(packageRelativePath)
        }
        cache.entriesByPath[packageRelativePath] = expectedEntry
        return canonicalAfterRead
    }

    func fullHashCountForTesting(_ packageRelativePath: String) -> Int {
        cache.lock.lock()
        defer { cache.lock.unlock() }
        return cache.fullHashCountByPath[packageRelativePath, default: 0]
    }

    private static func canonicalPackageRoot(_ root: URL) throws -> URL {
        guard root.isFileURL else {
            throw OfflineAudioAssetResolutionError.invalidVerifiedPackageRoot
        }
        let standardized = root.standardizedFileURL
        let values: URLResourceValues
        do {
            values = try standardized.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
        } catch {
            throw OfflineAudioAssetResolutionError.invalidVerifiedPackageRoot
        }
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw OfflineAudioAssetResolutionError.invalidVerifiedPackageRoot
        }
        return standardized.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func validateSafePath(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let containsControlCharacter = path.unicodeScalars.contains { scalar in
            scalar.value <= 0x1F || scalar.value == 0x7F
        }
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("://"),
              !containsControlCharacter,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw OfflineAudioAssetResolutionError.unsafePath(path)
        }
    }

    private static func validateRegularFile(
        _ fileURL: URL,
        path: String,
        root: URL
    ) throws -> URL {
        let values: URLResourceValues
        do {
            values = try fileURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
        } catch {
            throw OfflineAudioAssetResolutionError.missingFile(path)
        }
        guard values.isSymbolicLink != true else {
            throw OfflineAudioAssetResolutionError.symbolicLink(path)
        }
        guard values.isRegularFile == true, values.isDirectory != true else {
            throw OfflineAudioAssetResolutionError.notRegularFile(path)
        }
        let canonical = fileURL.resolvingSymlinksInPath().standardizedFileURL
        guard canonical.path.hasPrefix(root.path + "/") else {
            throw OfflineAudioAssetResolutionError.pathEscapedRoot(path)
        }
        let relative = String(canonical.path.dropFirst(root.path.count + 1))
        guard relative == path else {
            throw OfflineAudioAssetResolutionError.pathEscapedRoot(path)
        }
        return canonical
    }

    private static func streamedDigest(
        _ url: URL,
        path: String
    ) throws -> (bytes: Int64, digest: String) {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw OfflineAudioAssetResolutionError.missingFile(path)
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        var byteCount: Int64 = 0
        do {
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                try Task.checkCancellation()
                let result = byteCount.addingReportingOverflow(Int64(data.count))
                guard !result.overflow else {
                    throw OfflineAudioAssetResolutionError.manifestSizeMismatch(path)
                }
                byteCount = result.partialValue
                hasher.update(data: data)
            }
        } catch let error as OfflineAudioAssetResolutionError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw OfflineAudioAssetResolutionError.missingFile(path)
        }
        let digest = hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        return (byteCount, digest)
    }

    private static func fileIdentity(
        at url: URL,
        path: String
    ) throws -> FileIdentity {
        var value = Darwin.stat()
        guard lstat(url.path, &value) == 0 else {
            throw OfflineAudioAssetResolutionError.missingFile(path)
        }
        return FileIdentity(
            device: UInt64(value.st_dev),
            inode: UInt64(value.st_ino),
            bytes: value.st_size,
            modificationSeconds: Int64(value.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(value.st_mtimespec.tv_nsec),
            changeSeconds: Int64(value.st_ctimespec.tv_sec),
            changeNanoseconds: Int64(value.st_ctimespec.tv_nsec)
        )
    }
}

public struct NativeTimelineTransportSnapshot: Equatable, Sendable {
    public let timelineID: AudioTimelineID?
    public let cursorSample: Int64
    public let loopIteration: UInt64
    public let isPlaying: Bool

    public init(
        timelineID: AudioTimelineID?,
        cursorSample: Int64,
        loopIteration: UInt64 = 0,
        isPlaying: Bool
    ) {
        self.timelineID = timelineID
        self.cursorSample = cursorSample
        self.loopIteration = loopIteration
        self.isPlaying = isPlaying
    }
}

public enum ResponsiveAudioSuspensionReason: Equatable, Sendable {
    case sceneInactive
    case sceneBackground
    case interruption
    case routeChange
}

public enum ResponsiveAudioAutomaticBoundaryEvent: Equatable, Sendable {
    case successorStarted(NativeTimelineTransportSnapshot)
    case completed(NativeTimelineTransportSnapshot)
}

public enum ResponsiveAudioOutgoingTailFinishReason: Equatable, Sendable {
    /// The source render clock crossed the first graph sample whose authored
    /// gain is exactly zero.
    case renderClockConfirmed
    /// An owner explicitly quiesced the detached graph.
    case explicitStop
    /// The engine stopped before the render clock proved the fade complete.
    case renderClockStopped
    /// A running engine stopped publishing render progress for the bounded
    /// watchdog interval. This is fail-closed, never normal completion.
    case renderClockStalled
}

struct ResponsiveAudioOutgoingTailRenderObservation: Equatable, Sendable {
    let graphSampleEnd: Int64?
    let engineIsRunning: Bool
}

struct NativeOutgoingTailCompletionGate: Equatable, Sendable {
    enum Decision: Equatable, Sendable {
        case pending
        case finish(ResponsiveAudioOutgoingTailFinishReason)
    }

    let fadeEndGraphSample: Int64
    let stallBudgetNanoseconds: UInt64
    private(set) var latestGraphSampleEnd: Int64?
    private(set) var lastProgressNanoseconds: UInt64

    init(
        fadeEndGraphSample: Int64,
        stallBudgetNanoseconds: UInt64,
        initialGraphSampleEnd: Int64?,
        initialMonotonicNanoseconds: UInt64
    ) {
        self.fadeEndGraphSample = fadeEndGraphSample
        self.stallBudgetNanoseconds = stallBudgetNanoseconds
        latestGraphSampleEnd = initialGraphSampleEnd
        lastProgressNanoseconds = initialMonotonicNanoseconds
    }

    mutating func observe(
        _ observation: ResponsiveAudioOutgoingTailRenderObservation,
        monotonicNanoseconds: UInt64
    ) -> Decision {
        // graphSampleEnd is an exclusive upper bound. Equality means the
        // first exactly-zero sample has not itself been rendered yet.
        if let graphSampleEnd = observation.graphSampleEnd,
           graphSampleEnd > fadeEndGraphSample {
            return .finish(.renderClockConfirmed)
        }
        guard observation.engineIsRunning else {
            return .finish(.renderClockStopped)
        }
        if let graphSampleEnd = observation.graphSampleEnd,
           latestGraphSampleEnd == nil || graphSampleEnd > latestGraphSampleEnd! {
            latestGraphSampleEnd = graphSampleEnd
            lastProgressNanoseconds = monotonicNanoseconds
            return .pending
        }
        let elapsed = monotonicNanoseconds.subtractingReportingOverflow(
            lastProgressNanoseconds
        )
        guard !elapsed.overflow,
              elapsed.partialValue >= stallBudgetNanoseconds else {
            return .pending
        }
        return .finish(.renderClockStalled)
    }
}

/// Retains a detached native transport until its authored fade has physically
/// reached zero. Journey owns this handle outside the next beat's authority;
/// interruption/background may stop it immediately without creating progress.
@MainActor
public final class ResponsiveAudioOutgoingTail {
    private final class Lifetime {
        var owner: AnyObject?
        var finishOperation: ((ResponsiveAudioOutgoingTailFinishReason) -> Void)?
        var completionObservers:
            [(ResponsiveAudioOutgoingTailFinishReason) -> Void] = []
        private(set) var isFinished = false
        private(set) var finishReason: ResponsiveAudioOutgoingTailFinishReason?

        init(
            owner: AnyObject,
            finishOperation: @escaping (
                ResponsiveAudioOutgoingTailFinishReason
            ) -> Void
        ) {
            self.owner = owner
            self.finishOperation = finishOperation
        }

        func finish(reason: ResponsiveAudioOutgoingTailFinishReason) {
            guard !isFinished else { return }
            isFinished = true
            finishReason = reason
            let operation = finishOperation
            finishOperation = nil
            operation?(reason)
            owner = nil
            let observers = completionObservers
            completionObservers.removeAll()
            for observer in observers { observer(reason) }
        }

        func observeCompletion(
            _ observer: @escaping (
                ResponsiveAudioOutgoingTailFinishReason
            ) -> Void
        ) {
            if let finishReason {
                observer(finishReason)
            } else {
                completionObservers.append(observer)
            }
        }
    }

    @MainActor
    private final class CompletionMonitor {
        let lifetime: Lifetime
        let renderObservation:
            @MainActor () -> ResponsiveAudioOutgoingTailRenderObservation
        let monotonicNanoseconds: @MainActor () -> UInt64
        var gate: NativeOutgoingTailCompletionGate
        var task: Task<Void, Never>?

        init(
            lifetime: Lifetime,
            renderObservation: @escaping @MainActor ()
                -> ResponsiveAudioOutgoingTailRenderObservation,
            monotonicNanoseconds: @escaping @MainActor () -> UInt64,
            gate: NativeOutgoingTailCompletionGate
        ) {
            self.lifetime = lifetime
            self.renderObservation = renderObservation
            self.monotonicNanoseconds = monotonicNanoseconds
            self.gate = gate
        }

        @MainActor
        func observeNow() {
            guard !lifetime.isFinished else { return }
            switch gate.observe(
                renderObservation(),
                monotonicNanoseconds: monotonicNanoseconds()
            ) {
            case .pending:
                break
            case let .finish(reason):
                finish(reason)
            }
        }

        func finish(_ reason: ResponsiveAudioOutgoingTailFinishReason) {
            guard !lifetime.isFinished else { return }
            task?.cancel()
            task = nil
            lifetime.finish(reason: reason)
        }
    }

    public let fadeBoundarySample: Int64
    public let fadeDurationSamples: Int64
    public let sampleRate: Int

    private let lifetime: Lifetime
    private let monitor: CompletionMonitor

    init(
        owner: AnyObject,
        fadeBoundarySample: Int64,
        fadeDurationSamples: Int64,
        sampleRate: Int,
        initialWakeHintNanoseconds: UInt64?,
        fadeEndGraphSample: Int64,
        stallBudgetNanoseconds: UInt64 = 2_000_000_000,
        renderObservation: @escaping @MainActor ()
            -> ResponsiveAudioOutgoingTailRenderObservation,
        monotonicNanoseconds: @escaping @MainActor () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        },
        finishOperation: @escaping (
            ResponsiveAudioOutgoingTailFinishReason
        ) -> Void
    ) {
        self.fadeBoundarySample = fadeBoundarySample
        self.fadeDurationSamples = fadeDurationSamples
        self.sampleRate = sampleRate
        lifetime = Lifetime(owner: owner, finishOperation: finishOperation)
        let now = monotonicNanoseconds()
        let initialObservation = renderObservation()
        monitor = CompletionMonitor(
            lifetime: lifetime,
            renderObservation: renderObservation,
            monotonicNanoseconds: monotonicNanoseconds,
            gate: NativeOutgoingTailCompletionGate(
                fadeEndGraphSample: fadeEndGraphSample,
                stallBudgetNanoseconds: stallBudgetNanoseconds,
                initialGraphSampleEnd: initialObservation.graphSampleEnd,
                initialMonotonicNanoseconds: now
            )
        )
        if let initialWakeHintNanoseconds {
            let monitor = monitor
            // Wall time is only a polling hint. Cap the first sleep so an
            // engine stop or a stalled render clock is classified within the
            // watchdog window even when the authored fade is long.
            let firstObservationDelay = min(
                initialWakeHintNanoseconds,
                min(stallBudgetNanoseconds, 20_000_000)
            )
            monitor.task = Task { @MainActor in
                try? await Task.sleep(nanoseconds: firstObservationDelay)
                guard !Task.isCancelled else { return }
                while !Task.isCancelled, !monitor.lifetime.isFinished {
                    monitor.observeNow()
                    guard !monitor.lifetime.isFinished else { return }
                    try? await Task.sleep(nanoseconds: 2_000_000)
                }
            }
        }
    }

    public var isFinished: Bool { lifetime.isFinished }
    public var finishReason: ResponsiveAudioOutgoingTailFinishReason? {
        lifetime.finishReason
    }

    public func observeCompletion(
        _ observer: @escaping @MainActor (
            ResponsiveAudioOutgoingTailFinishReason
        ) -> Void
    ) {
        lifetime.observeCompletion(observer)
    }

    public func stopImmediately() {
        monitor.finish(.explicitStop)
    }

    func observeRenderClockNowForTesting() {
        monitor.observeNow()
    }
}

public enum ResponsiveAudioTimelineTransportContractError: Error, Equatable, Sendable {
    case causalMixUnsupported
    case outgoingTailUnsupported
    case automaticBoundaryUnsupported
    case activeAudioCursorUnsupported
}

/// Narrow boundary used by the deterministic responsive program controller.
/// NativeTimelineTransport is the production implementation; tests use an
/// in-memory sample clock without opening AVAudioEngine.
@MainActor
public protocol ResponsiveAudioTimelineTransport: AnyObject {
    func prepare(
        timeline: AudioTimeline,
        cursorSample: Int64,
        resolver: any OfflineAudioAssetResolving
    ) throws
    func play() throws
    func pause() throws -> NativeTimelineTransportSnapshot
    func pause(
        for reason: ResponsiveAudioSuspensionReason
    ) throws -> NativeTimelineTransportSnapshot
    func snapshot() -> NativeTimelineTransportSnapshot
    func applyPreferences(_ preferences: ExperiencePreferences)
    func relinquishOutgoingAudio(
        exitPolicy: ResponsiveAudioExitPolicy
    ) throws -> ResponsiveAudioOutgoingTail?
    func configureAutomaticBoundary(
        successorPlan: ResponsiveAudioTimelineTransportPlan?,
        resolver: any OfflineAudioAssetResolving,
        handler: @escaping (ResponsiveAudioAutomaticBoundaryEvent) -> Void
    ) throws
#if os(iOS)
    func activeAudioCursorBinding() throws -> NativeAudioCursorBinding
#endif
    func stop()

    /// Initial deterministic program preparation. A transport that cannot
    /// retain common material players must reject a causal mix explicitly.
    func prepareResponsiveAudio(
        plan: ResponsiveAudioTimelineTransportPlan,
        resolver: any OfflineAudioAssetResolving
    ) throws

    /// In-place interaction update. Production uses this boundary for phase
    /// replacement and sample-time causal gain ramps without restarting the
    /// shared material clock.
    func transitionResponsiveAudio(
        to plan: ResponsiveAudioTimelineTransportPlan,
        resolver: any OfflineAudioAssetResolving,
        validateBeforeCommit: (
            NativeTimelineTransportSnapshot
        ) throws -> Void
    ) throws -> NativeTimelineTransportSnapshot
}

public extension ResponsiveAudioTimelineTransport {
    func pause(
        for _: ResponsiveAudioSuspensionReason
    ) throws -> NativeTimelineTransportSnapshot {
        try pause()
    }

    func relinquishOutgoingAudio(
        exitPolicy _: ResponsiveAudioExitPolicy
    ) throws -> ResponsiveAudioOutgoingTail? {
        throw ResponsiveAudioTimelineTransportContractError
            .outgoingTailUnsupported
    }

    func configureAutomaticBoundary(
        successorPlan _: ResponsiveAudioTimelineTransportPlan?,
        resolver _: any OfflineAudioAssetResolving,
        handler _: @escaping (ResponsiveAudioAutomaticBoundaryEvent) -> Void
    ) throws {
        throw ResponsiveAudioTimelineTransportContractError
            .automaticBoundaryUnsupported
    }

#if os(iOS)
    func activeAudioCursorBinding() throws -> NativeAudioCursorBinding {
        throw ResponsiveAudioTimelineTransportContractError
            .activeAudioCursorUnsupported
    }
#endif

    func prepareResponsiveAudio(
        plan: ResponsiveAudioTimelineTransportPlan,
        resolver: any OfflineAudioAssetResolving
    ) throws {
        guard plan.causalMix == nil else {
            throw ResponsiveAudioTimelineTransportContractError.causalMixUnsupported
        }
        try prepare(
            timeline: plan.timeline,
            cursorSample: plan.cursorSample,
            resolver: resolver
        )
    }

    func transitionResponsiveAudio(
        to plan: ResponsiveAudioTimelineTransportPlan,
        resolver: any OfflineAudioAssetResolving
    ) throws -> NativeTimelineTransportSnapshot {
        try transitionResponsiveAudio(
            to: plan,
            resolver: resolver,
            validateBeforeCommit: { _ in }
        )
    }
}
