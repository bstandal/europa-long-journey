import CryptoKit
import Darwin
import Foundation
import os

struct SystemPhysicalFootprintSampler: PhysicalFootprintSampling {
    func physicalFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }
}

protocol AppBuildHashing: Sendable {
    func sha256(ofAppBundleAt url: URL) throws -> String
}

struct CanonicalAppBundleHasher: AppBuildHashing {
    func sha256(ofAppBundleAt url: URL) throws -> String {
        let rootURL = url.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard rootURL.isFileURL,
              FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw PerformanceInstrumentationError.appBundleUnavailable
        }
        var enumerationFailed = false
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { _, _ in
                enumerationFailed = true
                return false
            }
        ) else {
            throw PerformanceInstrumentationError.appBuildHashFailed
        }
        var entries: [(path: String, url: URL)] = []
        for case let entryURL as URL in enumerator {
            let canonicalEntryURL = entryURL.standardizedFileURL
            let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
            guard canonicalEntryURL.path.hasPrefix(prefix) else {
                throw PerformanceInstrumentationError.appBuildHashFailed
            }
            entries.append(
                (
                    String(canonicalEntryURL.path.dropFirst(prefix.count)),
                    canonicalEntryURL
                )
            )
        }
        guard !enumerationFailed else {
            throw PerformanceInstrumentationError.appBuildHashFailed
        }
        entries.sort { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }

        var hasher = SHA256()
        for entry in entries {
            let values: URLResourceValues
            do {
                values = try entry.url.resourceValues(forKeys: [
                    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
                ])
            } catch {
                throw PerformanceInstrumentationError.appBuildHashFailed
            }
            let kind: UInt8
            let content: Data
            if values.isSymbolicLink == true {
                kind = 0x4C // L
                do {
                    content = Data(
                        try FileManager.default.destinationOfSymbolicLink(
                            atPath: entry.url.path
                        ).utf8
                    )
                } catch {
                    throw PerformanceInstrumentationError.appBuildHashFailed
                }
            } else if values.isRegularFile == true {
                kind = 0x46 // F
                content = try Self.fileDigest(at: entry.url)
            } else if values.isDirectory == true {
                kind = 0x44 // D; preserves empty signed directories.
                content = Data()
            } else {
                throw PerformanceInstrumentationError.appBuildHashFailed
            }
            let path = Data(entry.path.utf8)
            hasher.update(data: Self.bigEndianBytes(UInt64(path.count)))
            hasher.update(data: path)
            hasher.update(data: Data([kind]))
            hasher.update(data: Self.bigEndianBytes(UInt64(content.count)))
            hasher.update(data: content)
        }
        return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
    }

    private static func fileDigest(at url: URL) throws -> Data {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw PerformanceInstrumentationError.appBuildHashFailed
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
        } catch {
            throw PerformanceInstrumentationError.appBuildHashFailed
        }
        return Data(hasher.finalize())
    }

    private static func bigEndianBytes(_ value: UInt64) -> Data {
        var bigEndian = value.bigEndian
        return withUnsafeBytes(of: &bigEndian) { Data($0) }
    }
}

public struct PerformanceReportExportReceipt: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let attemptID: String
    public let gateClassification: PerformanceGateClassification
    public let reportFileName: String
    public let reportBytes: Int
    public let reportSHA256: String

    public init(
        schemaVersion: Int = 1,
        attemptID: String,
        gateClassification: PerformanceGateClassification,
        reportFileName: String,
        reportBytes: Int,
        reportSHA256: String
    ) {
        self.schemaVersion = schemaVersion
        self.attemptID = attemptID
        self.gateClassification = gateClassification
        self.reportFileName = reportFileName
        self.reportBytes = reportBytes
        self.reportSHA256 = reportSHA256
    }
}

public enum PerformanceReportExporter {
    public static func export(
        recorder: LocalPerformanceRecorder,
        appBundleURL: URL,
        reportDirectory: URL
    ) throws -> PerformanceReportExportReceipt {
        try export(
            recorder: recorder,
            appBundleURL: appBundleURL,
            reportDirectory: reportDirectory,
            hasher: CanonicalAppBundleHasher()
        )
    }

    static func export(
        recorder: LocalPerformanceRecorder,
        appBundleURL: URL,
        reportDirectory: URL,
        hasher: any AppBuildHashing
    ) throws -> PerformanceReportExportReceipt {
        let appHash = try hasher.sha256(ofAppBundleAt: appBundleURL)
        guard PerformanceCaptureValidator.isLowercaseSHA256(appHash) else {
            throw PerformanceInstrumentationError.appBuildHashFailed
        }
        let report = recorder.makeReport(appBuildSHA256: appHash)
        let bytes = try PerformanceReportCodec.encodeCanonical(report)
        let digest = Data(SHA256.hash(data: bytes)).map {
            String(format: "%02x", $0)
        }.joined()
        do {
            try FileManager.default.createDirectory(
                at: reportDirectory,
                withIntermediateDirectories: true
            )
            let reportName = "\(report.attemptID).performance.json"
            let reportURL = reportDirectory.appendingPathComponent(reportName)
            try bytes.write(to: reportURL, options: .atomic)

            let receipt = PerformanceReportExportReceipt(
                attemptID: report.attemptID,
                gateClassification: report.gateClassification,
                reportFileName: reportName,
                reportBytes: bytes.count,
                reportSHA256: digest
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let receiptBytes = try encoder.encode(receipt) + Data([0x0A])
            try receiptBytes.write(
                to: reportDirectory.appendingPathComponent(
                    "\(report.attemptID).performance.receipt.json"
                ),
                options: .atomic
            )
            return receipt
        } catch let error as PerformanceInstrumentationError {
            throw error
        } catch {
            throw PerformanceInstrumentationError.reportWriteFailed
        }
    }
}

public enum PerformanceCaptureRequestCodec {
    public static func decodeStrict(_ data: Data) throws -> PerformanceCaptureRequest {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PerformanceInstrumentationError.invalidCaptureRequest(
                "request is not JSON"
            )
        }
        guard let dictionary = object as? [String: Any],
              Set(dictionary.keys) == [
                  "schemaVersion", "protocolID", "runID", "attemptID", "repetition",
                  "rawTraceRetentionRequired",
              ] else {
            throw PerformanceInstrumentationError.invalidCaptureRequest(
                "request has missing or unknown fields"
            )
        }
        let request: PerformanceCaptureRequest
        do {
            request = try JSONDecoder().decode(PerformanceCaptureRequest.self, from: data)
        } catch {
            throw PerformanceInstrumentationError.invalidCaptureRequest(
                "request JSON did not decode"
            )
        }
        try PerformanceCaptureValidator.validate(request)
        return request
    }
}

public enum PerformanceCaptureBootstrapOutcome: Equatable, Sendable {
    case inactive
    case active(PerformanceCaptureRequest)
    case rejected
}

/// Process-local composition root. It reads one local request file, exposes no
/// network edge and writes only to Application Support/quality-gate-v1. An
/// absent request makes every hot-path call a single optional check.
public final class PerformanceCaptureRuntime: @unchecked Sendable {
    public static let shared = PerformanceCaptureRuntime()
    public static let requestRelativePath =
        "quality-gate-v1/performance-capture-request.json"

    private struct ActiveCapture {
        let recorder: LocalPerformanceRecorder
        let appBundleURL: URL
        let reportDirectory: URL
    }

    private let lock = NSLock()
    private let log = OSLog(
        subsystem: "com.thelongwest.journey",
        category: "PhysicalPerformanceBootstrap"
    )
    private var active: ActiveCapture?
    private var exportIsInFlight = false

    private init() {}

    public var recorder: (any PerformanceRecording)? {
        lock.withLock { active?.recorder }
    }

    @discardableResult
    public func bootstrapIfRequested(
        applicationSupportURL: URL,
        appBundleURL: URL? = Bundle.main.bundleURL,
        processStartMonotonicNanosecondsSinceBoot: UInt64 =
            DispatchTime.now().uptimeNanoseconds
    ) -> PerformanceCaptureBootstrapOutcome {
        let requestURL = applicationSupportURL.appendingPathComponent(
            Self.requestRelativePath
        )
        guard FileManager.default.fileExists(atPath: requestURL.path) else {
            return .inactive
        }
        do {
            let request = try PerformanceCaptureRequestCodec.decodeStrict(
                Data(contentsOf: requestURL)
            )
            guard let appBundleURL else {
                throw PerformanceInstrumentationError.appBundleUnavailable
            }
            let platform = Self.livePlatformIdentity()
            let recorder = try LocalPerformanceRecorder(
                request: request,
                platform: platform,
                clock: SystemPerformanceMonotonicClock(),
                footprintSampler: SystemPhysicalFootprintSampler(),
                maximumRecordedEvents: 250_000,
                footprintFrameCadence: 120,
                startsThermalMonitoring: true,
                processStartNanosecondsSinceBoot:
                    processStartMonotonicNanosecondsSinceBoot
            )
            let reportDirectory = applicationSupportURL.appendingPathComponent(
                "quality-gate-v1/performance-reports",
                isDirectory: true
            )
            lock.withLock {
                active = ActiveCapture(
                    recorder: recorder,
                    appBundleURL: appBundleURL,
                    reportDirectory: reportDirectory
                )
            }
            os_signpost(.event, log: log, name: "Performance Capture Active")
            return .active(request)
        } catch {
            os_signpost(.event, log: log, name: "Performance Capture Rejected")
            return .rejected
        }
    }

    /// Safe to call on every inactive transition. Concurrent or repeated calls
    /// cannot race two atomic writes for the same deterministic attempt ID.
    public func exportActiveReport() async throws -> PerformanceReportExportReceipt {
        let capture: ActiveCapture = try lock.withLock {
            guard let active else {
                throw PerformanceInstrumentationError.captureNotActive
            }
            guard !exportIsInFlight else {
                throw PerformanceInstrumentationError.reportWriteFailed
            }
            exportIsInFlight = true
            return active
        }
        defer { lock.withLock { exportIsInFlight = false } }
        return try await Task.detached(priority: .utility) {
            try PerformanceReportExporter.export(
                recorder: capture.recorder,
                appBundleURL: capture.appBundleURL,
                reportDirectory: capture.reportDirectory
            )
        }.value
    }

    static func livePlatformIdentity() -> PerformancePlatformIdentity {
#if targetEnvironment(simulator)
        let captureClass = PerformanceCaptureClass.nonDevice
#elseif os(iOS)
        let captureClass = PerformanceCaptureClass.physicalDevice
#else
        let captureClass = PerformanceCaptureClass.nonDevice
#endif
#if DEBUG
        let configuration = PerformanceBuildConfiguration.debug
#else
        let configuration = PerformanceBuildConfiguration.release
#endif
        return PerformancePlatformIdentity(
            captureClass: captureClass,
            hardwareModel: hardwareModel(),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            buildConfiguration: configuration
        )
    }

    private static func hardwareModel() -> String {
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else { return "unknown" }
        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
