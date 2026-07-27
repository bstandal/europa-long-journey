import Foundation

public enum PerformanceCaptureValidator {
    public static let allowedRunIDs: Set<String> = [
        "cold-restore",
        "interaction-latency",
        "static-reference",
        "first-farmers-static-reference",
        "harvest-sustained",
        "first-farmers-sustained",
        "audio-restoration",
        "storage-pressure",
    ]

    public static func validate(_ request: PerformanceCaptureRequest) throws {
        guard request.schemaVersion == 1 else {
            throw PerformanceInstrumentationError.invalidCaptureRequest(
                "unsupported request schema"
            )
        }
        guard request.protocolID == "port1-physical-device-v1" else {
            throw PerformanceInstrumentationError.invalidCaptureRequest(
                "protocol identity drifted"
            )
        }
        guard allowedRunIDs.contains(request.runID) else {
            throw PerformanceInstrumentationError.invalidCaptureRequest("unknown run ID")
        }
        guard request.repetition > 0 else {
            throw PerformanceInstrumentationError.invalidCaptureRequest(
                "repetition must be positive"
            )
        }
        guard request.rawTraceRetentionRequired else {
            throw PerformanceInstrumentationError.invalidCaptureRequest(
                "raw trace retention cannot be disabled"
            )
        }
        guard isSafeAttemptID(request.attemptID) else {
            throw PerformanceInstrumentationError.invalidCaptureRequest(
                "attempt ID is not a safe deterministic file identity"
            )
        }
    }

    public static func validate(_ report: PhysicalPerformanceReport) throws {
        guard report.schemaVersion == 1 else {
            throw PerformanceInstrumentationError.invalidReport("unsupported report schema")
        }
        guard report.protocolID == "port1-physical-device-v1",
              allowedRunIDs.contains(report.runID),
              report.repetition > 0,
              isSafeAttemptID(report.attemptID),
              report.rawTraceRetentionRequired else {
            throw PerformanceInstrumentationError.invalidReport("invalid protocol identity")
        }
        guard report.localTimingScope == .commandBufferAndGPUCompletionProxyOnly else {
            throw PerformanceInstrumentationError.invalidReport(
                "local timing scope cannot claim display presentation"
            )
        }
        guard report.appBuildHashKind == "APP_BUNDLE_FILE_TREE_SHA256",
              isLowercaseSHA256(report.appBuildSHA256) else {
            throw PerformanceInstrumentationError.invalidReport("invalid app build hash")
        }
        switch report.platform.captureClass {
        case .nonDevice:
            guard report.gateClassification == .nonDevice else {
                throw PerformanceInstrumentationError.invalidReport(
                    "simulator or host evidence must be NON_DEVICE"
                )
            }
        case .physicalDevice:
            guard report.gateClassification == .deviceRawMeasurementsOnly else {
                throw PerformanceInstrumentationError.invalidReport(
                    "raw device capture cannot claim a physical-gate pass"
                )
            }
        }
        if report.gateClassification == .deviceRawMeasurementsOnly,
           report.platform.buildConfiguration != .release {
            throw PerformanceInstrumentationError.invalidReport(
                "physical raw evidence requires a Release build"
            )
        }
        guard report.captureEndedNanosecondsSinceProcessStart > 0 else {
            throw PerformanceInstrumentationError.invalidReport(
                "capture end is missing"
            )
        }

        guard !report.packages.isEmpty else {
            throw PerformanceInstrumentationError.invalidReport("package hash is missing")
        }
        var packageIDs: Set<String> = []
        for package in report.packages {
            guard !package.packageID.isEmpty,
                  packageIDs.insert(package.packageID).inserted,
                  isLowercaseSHA256(package.manifestSHA256) else {
                throw PerformanceInstrumentationError.invalidReport(
                    "invalid or duplicate package identity"
                )
            }
        }
        guard report.packages == report.packages.sorted(by: packageSort) else {
            throw PerformanceInstrumentationError.invalidReport(
                "package identities are not canonical"
            )
        }

        var globalSequences: [UInt64] = []
        var frameIDs: Set<UInt64> = []
        var previousCompletedCallback: UInt64?
        for frame in report.frameCommandBufferCompletionProxies {
            guard frameIDs.insert(frame.frameID).inserted,
                  !frame.sceneID.isEmpty,
                  frame.commandBufferScheduledCallbackNanosecondsSinceProcessStart
                    >= frame.commandBufferCommitRequestedNanosecondsSinceProcessStart,
                  frame.commandBufferCompletedCallbackNanosecondsSinceProcessStart
                    >= frame.commandBufferScheduledCallbackNanosecondsSinceProcessStart,
                  frame.commitRequestToScheduledCallbackNanoseconds
                    == frame.commandBufferScheduledCallbackNanosecondsSinceProcessStart
                        - frame.commandBufferCommitRequestedNanosecondsSinceProcessStart,
                  frame.commitRequestToCompletedCallbackNanoseconds
                    == frame.commandBufferCompletedCallbackNanosecondsSinceProcessStart
                        - frame.commandBufferCommitRequestedNanosecondsSinceProcessStart else {
                throw PerformanceInstrumentationError.invalidReport("invalid frame timing")
            }
            switch (
                frame.gpuStartHostTimeNanoseconds,
                frame.gpuEndHostTimeNanoseconds,
                frame.gpuExecutionNanoseconds
            ) {
            case (nil, nil, nil):
                break
            case let (gpuStart?, gpuEnd?, gpuExecution?):
                guard gpuEnd >= gpuStart, gpuExecution == gpuEnd - gpuStart else {
                    throw PerformanceInstrumentationError.invalidReport("invalid GPU timing")
                }
            default:
                throw PerformanceInstrumentationError.invalidReport(
                    "partial GPU timing is not canonical"
                )
            }
            if let previousCompletedCallback {
                guard frame.commandBufferCompletedCallbackNanosecondsSinceProcessStart
                        >= previousCompletedCallback,
                      frame.previousCommandBufferCompletionCallbackIntervalNanoseconds
                        == frame.commandBufferCompletedCallbackNanosecondsSinceProcessStart
                            - previousCompletedCallback else {
                    throw PerformanceInstrumentationError.invalidReport(
                        "command-buffer completion callback order drifted"
                    )
                }
            } else if frame.previousCommandBufferCompletionCallbackIntervalNanoseconds != nil {
                throw PerformanceInstrumentationError.invalidReport(
                    "first frame cannot have a prior completion-callback interval"
                )
            }
            previousCompletedCallback =
                frame.commandBufferCompletedCallbackNanosecondsSinceProcessStart
            globalSequences.append(frame.sequence)
        }

        var actionIDs: Set<UInt64> = []
        for interaction in report.interactionCommandBufferCompletionProxies {
            guard actionIDs.insert(interaction.actionID).inserted,
                  !interaction.actionName.isEmpty,
                  frameIDs.contains(interaction.completedFrameID),
                  interaction.firstCommandBufferCompletedCallbackNanosecondsSinceProcessStart
                    >= interaction.beganNanosecondsSinceProcessStart,
                  interaction.actionToCommandBufferCompletedCallbackNanoseconds
                    == interaction
                        .firstCommandBufferCompletedCallbackNanosecondsSinceProcessStart
                        - interaction.beganNanosecondsSinceProcessStart else {
                throw PerformanceInstrumentationError.invalidReport(
                    "invalid interaction command-buffer completion proxy"
                )
            }
            globalSequences.append(interaction.sequence)
        }

        for memory in report.physicalFootprint {
            guard memory.physicalFootprintBytes > 0 else {
                throw PerformanceInstrumentationError.invalidReport(
                    "physical footprint must be positive"
                )
            }
            globalSequences.append(memory.sequence)
        }
        var lastThermal: RecordedThermalState?
        for thermal in report.thermalTransitions {
            guard thermal.from == lastThermal, thermal.to != lastThermal else {
                throw PerformanceInstrumentationError.invalidReport(
                    "thermal transition chain is invalid"
                )
            }
            lastThermal = thermal.to
            globalSequences.append(thermal.sequence)
        }
        for checkpoint in report.audioCursorCheckpoints {
            guard checkpoint.sampleRate == 48_000,
                  checkpoint.cursorSample >= 0,
                  !checkpoint.timelineID.isEmpty else {
                throw PerformanceInstrumentationError.invalidReport(
                    "audio cursor is not an authored 48 kHz checkpoint"
                )
            }
            globalSequences.append(checkpoint.sequence)
        }
        for failure in report.instrumentationFailures {
            globalSequences.append(failure.sequence)
        }
        let expectedSequences = globalSequences.indices.map { UInt64($0 + 1) }
        guard globalSequences.sorted() == expectedSequences else {
            throw PerformanceInstrumentationError.invalidReport(
                "measurement sequence is incomplete or noncanonical"
            )
        }

        for milestone in [
            report.launch
                .restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart,
            report.launch.firstActionReadyNanosecondsSinceProcessStart,
            report.launch.firstActionReceivedNanosecondsSinceProcessStart,
        ].compactMap({ $0 }) where milestone > UInt64.max / 2 {
            throw PerformanceInstrumentationError.invalidReport("invalid launch milestone")
        }

        let latestMeasurement = (
            report.frameCommandBufferCompletionProxies.map(
                \.commandBufferCompletedCallbackNanosecondsSinceProcessStart
            )
            + report.interactionCommandBufferCompletionProxies.map(
                \.firstCommandBufferCompletedCallbackNanosecondsSinceProcessStart
            )
            + report.physicalFootprint.map(\.nanosecondsSinceProcessStart)
            + report.thermalTransitions.map(\.nanosecondsSinceProcessStart)
            + report.audioCursorCheckpoints.map(\.nanosecondsSinceProcessStart)
            + report.instrumentationFailures.map(\.nanosecondsSinceProcessStart)
        ).max() ?? 0
        guard latestMeasurement <= report.captureEndedNanosecondsSinceProcessStart else {
            throw PerformanceInstrumentationError.invalidReport(
                "capture ended before its last measurement"
            )
        }
    }

    public static func isLowercaseSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { character in
            character.isNumber || ("a" ... "f").contains(character)
        }
    }

    private static func isSafeAttemptID(_ value: String) -> Bool {
        guard (1 ... 80).contains(value.count),
              value.first?.isLetter == true || value.first?.isNumber == true else {
            return false
        }
        return value.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_"
        }
    }

    private static func packageSort(
        _ lhs: PerformancePackageIdentity,
        _ rhs: PerformancePackageIdentity
    ) -> Bool {
        if lhs.packageID != rhs.packageID { return lhs.packageID < rhs.packageID }
        return lhs.manifestSHA256 < rhs.manifestSHA256
    }
}

public enum PerformanceReportCodec {
    public static func encodeCanonical(_ report: PhysicalPerformanceReport) throws -> Data {
        try PerformanceCaptureValidator.validate(report)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report) + Data([0x0A])
    }

    public static func decodeAndValidate(_ data: Data) throws -> PhysicalPerformanceReport {
        try rejectUnknownTopLevelKeys(in: data)
        let decoder = JSONDecoder()
        let report: PhysicalPerformanceReport
        do {
            report = try decoder.decode(PhysicalPerformanceReport.self, from: data)
        } catch {
            throw PerformanceInstrumentationError.invalidReport("report JSON did not decode")
        }
        try PerformanceCaptureValidator.validate(report)
        return report
    }

    private static func rejectUnknownTopLevelKeys(in data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw PerformanceInstrumentationError.invalidReport("report is not JSON")
        }
        guard let dictionary = object as? [String: Any] else {
            throw PerformanceInstrumentationError.invalidReport("report root is not an object")
        }
        let expected: Set<String> = [
            "schemaVersion", "protocolID", "runID", "attemptID", "repetition",
            "gateClassification", "localTimingScope", "platform", "appBuildHashKind",
            "appBuildSHA256",
            "packages", "processStartMonotonicNanosecondsSinceBoot",
            "captureEndedNanosecondsSinceProcessStart", "launch",
            "frameCommandBufferCompletionProxies",
            "interactionCommandBufferCompletionProxies", "physicalFootprint",
            "thermalTransitions",
            "audioCursorCheckpoints", "instrumentationFailures", "rawTraceRetentionRequired",
        ]
        guard Set(dictionary.keys) == expected else {
            throw PerformanceInstrumentationError.invalidReport(
                "report has missing or unknown top-level fields"
            )
        }
        try requireObjectKeys(
            dictionary["platform"],
            required: [
                "captureClass", "hardwareModel", "operatingSystem", "buildConfiguration",
            ]
        )
        try requireObjectKeys(
            dictionary["launch"],
            required: [],
            optional: [
                "restoredFrameCommandBufferCompletionProxyNanosecondsSinceProcessStart",
                "firstActionReadyNanosecondsSinceProcessStart",
                "firstActionReceivedNanosecondsSinceProcessStart",
            ]
        )
        try requireArrayObjectKeys(
            dictionary["packages"],
            required: ["packageID", "manifestSHA256"]
        )
        try requireArrayObjectKeys(
            dictionary["frameCommandBufferCompletionProxies"],
            required: [
                "sequence", "frameID", "sceneID",
                "commandBufferCommitRequestedNanosecondsSinceProcessStart",
                "commandBufferScheduledCallbackNanosecondsSinceProcessStart",
                "commandBufferCompletedCallbackNanosecondsSinceProcessStart",
                "commitRequestToScheduledCallbackNanoseconds",
                "commitRequestToCompletedCallbackNanoseconds",
            ],
            optional: [
                "previousCommandBufferCompletionCallbackIntervalNanoseconds",
                "gpuStartHostTimeNanoseconds", "gpuEndHostTimeNanoseconds",
                "gpuExecutionNanoseconds",
            ]
        )
        try requireArrayObjectKeys(
            dictionary["interactionCommandBufferCompletionProxies"],
            required: [
                "sequence", "actionID", "source", "actionName",
                "beganNanosecondsSinceProcessStart",
                "firstCommandBufferCompletedCallbackNanosecondsSinceProcessStart",
                "actionToCommandBufferCompletedCallbackNanoseconds",
                "completedFrameID",
            ]
        )
        try requireArrayObjectKeys(
            dictionary["physicalFootprint"],
            required: [
                "sequence", "nanosecondsSinceProcessStart", "physicalFootprintBytes",
                "trigger",
            ]
        )
        try requireArrayObjectKeys(
            dictionary["thermalTransitions"],
            required: ["sequence", "nanosecondsSinceProcessStart", "to"],
            optional: ["from"]
        )
        try requireArrayObjectKeys(
            dictionary["audioCursorCheckpoints"],
            required: [
                "sequence", "nanosecondsSinceProcessStart", "timelineID", "sampleRate",
                "cursorSample", "kind",
            ]
        )
        try requireArrayObjectKeys(
            dictionary["instrumentationFailures"],
            required: ["sequence", "nanosecondsSinceProcessStart", "code"]
        )
    }

    private static func requireObjectKeys(
        _ value: Any?,
        required: Set<String>,
        optional: Set<String> = []
    ) throws {
        guard let object = value as? [String: Any],
              required.isSubset(of: Set(object.keys)),
              Set(object.keys).isSubset(of: required.union(optional)) else {
            throw PerformanceInstrumentationError.invalidReport(
                "report nested object has missing or unknown fields"
            )
        }
    }

    private static func requireArrayObjectKeys(
        _ value: Any?,
        required: Set<String>,
        optional: Set<String> = []
    ) throws {
        guard let values = value as? [Any] else {
            throw PerformanceInstrumentationError.invalidReport(
                "report measurement collection is not an array"
            )
        }
        for value in values {
            try requireObjectKeys(value, required: required, optional: optional)
        }
    }
}
