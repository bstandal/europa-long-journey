import Foundation

/// Local-only evidence for editing the Chapter 01 review build. No event is
/// transmitted, and the recorder is inert outside an explicitly launched
/// immersive review process.
@MainActor
final class Chapter01ReviewMetricsRecorder {
    private struct Record: Encodable {
        let schemaVersion = 1
        let sessionID: String
        let event: String
        let elapsedRealMillis: Int64
        let cellID: String
        let sequenceID: String
        let beatID: String
        let authoredCursorMillis: Int64
        let assistanceTier: String
        let hesitationMillis: Int64
        let missCount: Int
        let engagementBudgetMillis: Int64
        let transitionProgress: Double?
    }

    private let isEnabled: Bool
    private let outputURL: URL
    private let sessionID = UUID().uuidString.lowercased()
    private let startedAt = DispatchTime.now().uptimeNanoseconds

    init(storageURL: URL) {
#if DEBUG || NON_SHIPPING_LIVE_TEST
        isEnabled = ProcessInfo.processInfo.arguments.contains(
            "--chapter01-immersive-review"
        )
#else
        isEnabled = false
#endif
        outputURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("review-metrics.ndjson", isDirectory: false)
    }

    func record(_ event: String, state: Chapter01DurableState) {
        guard isEnabled else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now >= startedAt
            ? Int64((now - startedAt) / 1_000_000)
            : 0
        let record = Record(
            sessionID: sessionID,
            event: event,
            elapsedRealMillis: elapsed,
            cellID: state.experience.worldCellID,
            sequenceID: state.experience.sequenceID,
            beatID: state.experience.beatID.rawValue,
            authoredCursorMillis: state.authoredCursorMillis,
            assistanceTier: state.experience.assistance.tier.rawValue,
            hesitationMillis: state.experience.assistance.hesitationMillis,
            missCount: state.experience.assistance.missCount,
            engagementBudgetMillis: state.engagementBudgetMillis,
            transitionProgress: state.experience.transition?.progress
        )
        do {
            let directory = outputURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(record)
            data.append(0x0A)
            if !FileManager.default.fileExists(atPath: outputURL.path) {
                try data.write(to: outputURL, options: .atomic)
                return
            }
            let handle = try FileHandle(forWritingTo: outputURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // Metrics can never interrupt or alter the historical experience.
        }
    }
}
