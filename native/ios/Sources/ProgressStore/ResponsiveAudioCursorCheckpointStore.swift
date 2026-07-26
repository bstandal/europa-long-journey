import ContentKit
import CryptoKit
import Darwin
import Foundation
import JourneyDomain

public enum ResponsiveAudioCursorCheckpointError: Error, Equatable, Sendable {
    case authorityUnavailable
    case authorityMismatch
    case invalidTimeline
    case invalidPosition
    case positionRegressed
    case sessionIDReused
    case staleSession
    case generationExhausted
    case durabilityFailure
}

/// Complete non-positional authority for one crash-recovery cursor stream.
///
/// This value intentionally repeats identity already present in Journey state.
/// The repetition is a fail-closed comparison boundary: the sidecar may replace
/// only `cursorSample` and `loopIteration`, and only after the canonical Journey
/// journal has been restored and recreates this exact value.
public struct ResponsiveAudioCursorAuthority: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let chapterOpenNonce: UUID
    public let sessionGeneration: UInt64
    public let durableSnapshotNonPositionSHA256: String
    public let contentRevision: UInt64
    public let packageID: PackageID
    public let contentVersion: SchemaVersion
    public let programID: ResponsiveAudioProgramID
    public let programScope: ResponsiveAudioProgramScope
    public let snapshotFormatVersion: Int
    public let stage: ResponsiveAudioProgramStage
    public let interactionPhase: ResponsiveInteractionAudioPhase?
    public let causalStage: ResponsiveAudioCausalStage?
    public let durableCompletionSequence: UInt64?
    public let timelineID: AudioTimelineID
    public let timelineSHA256: String
    public let timelineSampleRate: Int
    public let timelineDurationSamples: Int64
    public let baseCursorSample: Int64
    public let baseLoopIteration: UInt64

    /// Builds authority only from an already durable Journey state and the
    /// exact integrity-checked program material selected by that state.
    public static func make(
        durableState: JourneyState,
        contentRevision: UInt64,
        program: ResponsiveAudioProgramSpec,
        timeline: AudioTimeline
    ) throws -> Self {
        guard let session = durableState.activeChapter,
              let snapshot = session.responsiveAudioSnapshot,
              let chapterOpenNonce = session.responsiveAudioChapterOpenNonce,
              session.responsiveAudioSessionIsActive,
              session.responsiveAudioSessionGeneration > 0,
              session.chapterID == program.scope.chapterID,
              session.arcID == program.scope.arcID,
              session.beatID == program.scope.beatID,
              session.interaction?.interactionID == program.scope.interactionID,
              snapshot.programID == program.id,
              snapshot.timelineID == timeline.id,
              snapshot.formatVersion
                == ResponsiveAudioProgramSnapshot.currentFormatVersion else {
            throw ResponsiveAudioCursorCheckpointError.authorityUnavailable
        }
        let duration = timeline.authoredDurationSamples
        guard duration > 0, timeline.sampleRate > 0 else {
            throw ResponsiveAudioCursorCheckpointError.invalidTimeline
        }
        try validate(
            cursorSample: snapshot.cursorSample,
            loopIteration: snapshot.loopIteration,
            stage: snapshot.stage,
            durationSamples: duration
        )
        return try Self(
            formatVersion: currentFormatVersion,
            chapterOpenNonce: chapterOpenNonce,
            sessionGeneration: session.responsiveAudioSessionGeneration,
            durableSnapshotNonPositionSHA256: digest(
                SnapshotNonPositionMaterial(snapshot: snapshot)
            ),
            contentRevision: contentRevision,
            packageID: session.packageID,
            contentVersion: session.contentVersion,
            programID: program.id,
            programScope: program.scope,
            snapshotFormatVersion: snapshot.formatVersion,
            stage: snapshot.stage,
            interactionPhase: snapshot.interactionPhase,
            causalStage: snapshot.causalStage,
            durableCompletionSequence: snapshot.durableCompletionSequence,
            timelineID: timeline.id,
            timelineSHA256: digest(timeline),
            timelineSampleRate: timeline.sampleRate,
            timelineDurationSamples: duration,
            baseCursorSample: snapshot.cursorSample,
            baseLoopIteration: snapshot.loopIteration
        )
    }

    fileprivate func replacingPosition(
        cursorSample: Int64,
        loopIteration: UInt64
    ) throws -> ResponsiveAudioProgramSnapshot {
        try Self.validate(
            cursorSample: cursorSample,
            loopIteration: loopIteration,
            stage: stage,
            durationSamples: timelineDurationSamples
        )
        guard Self.isMonotonic(
            cursorSample: cursorSample,
            loopIteration: loopIteration,
            afterCursorSample: baseCursorSample,
            afterLoopIteration: baseLoopIteration
        ) else {
            throw ResponsiveAudioCursorCheckpointError.positionRegressed
        }
        try Self.validateRepresentableDelta(
            cursorSample: cursorSample,
            loopIteration: loopIteration,
            afterCursorSample: baseCursorSample,
            afterLoopIteration: baseLoopIteration,
            durationSamples: timelineDurationSamples
        )
        return ResponsiveAudioProgramSnapshot(
            formatVersion: snapshotFormatVersion,
            programID: programID,
            stage: stage,
            interactionPhase: interactionPhase,
            timelineID: timelineID,
            cursorSample: cursorSample,
            loopIteration: loopIteration,
            causalStage: causalStage,
            durableCompletionSequence: durableCompletionSequence
        )
    }

    fileprivate func validatesNonPosition(
        _ snapshot: ResponsiveAudioProgramSnapshot
    ) -> Bool {
        snapshot.formatVersion == snapshotFormatVersion
            && snapshot.programID == programID
            && snapshot.stage == stage
            && snapshot.interactionPhase == interactionPhase
            && snapshot.timelineID == timelineID
            && snapshot.causalStage == causalStage
            && snapshot.durableCompletionSequence == durableCompletionSequence
    }

    private struct SnapshotNonPositionMaterial: Codable {
        let formatVersion: Int
        let programID: ResponsiveAudioProgramID
        let stage: ResponsiveAudioProgramStage
        let interactionPhase: ResponsiveInteractionAudioPhase?
        let timelineID: AudioTimelineID
        let causalStage: ResponsiveAudioCausalStage?
        let durableCompletionSequence: UInt64?

        init(snapshot: ResponsiveAudioProgramSnapshot) {
            formatVersion = snapshot.formatVersion
            programID = snapshot.programID
            stage = snapshot.stage
            interactionPhase = snapshot.interactionPhase
            timelineID = snapshot.timelineID
            causalStage = snapshot.causalStage
            durableCompletionSequence = snapshot.durableCompletionSequence
        }
    }

    private static func validate(
        cursorSample: Int64,
        loopIteration: UInt64,
        stage: ResponsiveAudioProgramStage,
        durationSamples: Int64
    ) throws {
        guard durationSamples > 0, cursorSample >= 0 else {
            throw ResponsiveAudioCursorCheckpointError.invalidPosition
        }
        switch stage {
        case .approach, .consequence:
            guard loopIteration == 0, cursorSample < durationSamples else {
                throw ResponsiveAudioCursorCheckpointError.invalidPosition
            }
        case .interaction:
            guard cursorSample < durationSamples else {
                throw ResponsiveAudioCursorCheckpointError.invalidPosition
            }
        case .completed:
            guard loopIteration == 0, cursorSample == durationSamples else {
                throw ResponsiveAudioCursorCheckpointError.invalidPosition
            }
        }
    }

    fileprivate static func isMonotonic(
        cursorSample: Int64,
        loopIteration: UInt64,
        afterCursorSample: Int64,
        afterLoopIteration: UInt64
    ) -> Bool {
        loopIteration > afterLoopIteration
            || (loopIteration == afterLoopIteration
                && cursorSample >= afterCursorSample)
    }

    private static func validateRepresentableDelta(
        cursorSample: Int64,
        loopIteration: UInt64,
        afterCursorSample: Int64,
        afterLoopIteration: UInt64,
        durationSamples: Int64
    ) throws {
        let iterations = loopIteration - afterLoopIteration
        guard iterations <= UInt64(Int64.max) else {
            throw ResponsiveAudioCursorCheckpointError.invalidPosition
        }
        let multiplication = Int64(iterations)
            .multipliedReportingOverflow(by: durationSamples)
        let addition = multiplication.partialValue.addingReportingOverflow(cursorSample)
        let subtraction = addition.partialValue
            .subtractingReportingOverflow(afterCursorSample)
        guard !multiplication.overflow, !addition.overflow,
              !subtraction.overflow, subtraction.partialValue >= 0 else {
            throw ResponsiveAudioCursorCheckpointError.invalidPosition
        }
    }

    fileprivate static func digest<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct ResponsiveAudioCursorCheckpointSession: Equatable, Sendable {
    public let id: UUID
    fileprivate let authority: ResponsiveAudioCursorAuthority

    fileprivate init(id: UUID, authority: ResponsiveAudioCursorAuthority) {
        self.id = id
        self.authority = authority
    }
}

/// Three-slot, synchronised cursor sidecar. It is never a source of historical
/// authority: recovery first restores Journey, rebuilds `authority`, and then
/// accepts only a monotonic position overlay with a complete identity match.
///
/// Three destinations let one obsolete periodic write finish independently
/// while an authority handoff and its successor writer keep two crash-safe
/// generations. Synchronous file durability runs outside actor isolation; the
/// actor alone reserves monotonically increasing generations and distinct
/// destinations, and it never activates a successor before that reservation
/// is durable.
public actor ResponsiveAudioCursorCheckpointStore {
    public typealias DurableWriteOperation = @Sendable (Data, URL) throws -> Void

    public nonisolated let directoryURL: URL
    public nonisolated let slotAURL: URL
    public nonisolated let slotBURL: URL
    public nonisolated let slotCURL: URL

    private let durableWrite: DurableWriteOperation
    private var activeSession: ResponsiveAudioCursorCheckpointSession?
    private var highestReservedGeneration: UInt64 = 0
    private var inFlightWritesByURL: [URL: WriteReservation] = [:]
    private var retirementWaitersByWriterSessionID: [
        UUID: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var pendingHandoff: PendingHandoff?
    private var quarantinedSlotURLs: Set<URL> = []
    private var usedSessionIDs: Set<UUID> = []

    private struct Position: Codable, Equatable, Sendable {
        let cursorSample: Int64
        let loopIteration: UInt64
    }

    private struct RecordMaterial: Codable, Sendable {
        let formatVersion: Int
        let generation: UInt64
        let writerSessionID: UUID
        let authority: ResponsiveAudioCursorAuthority
        let position: Position
        let capturedAtMonotonicNanoseconds: UInt64
    }

    private struct Record: Codable, Equatable, Sendable {
        let formatVersion: Int
        let generation: UInt64
        let writerSessionID: UUID
        let authority: ResponsiveAudioCursorAuthority
        let position: Position
        let capturedAtMonotonicNanoseconds: UInt64
        let digest: String

        var material: RecordMaterial {
            RecordMaterial(
                formatVersion: formatVersion,
                generation: generation,
                writerSessionID: writerSessionID,
                authority: authority,
                position: position,
                capturedAtMonotonicNanoseconds: capturedAtMonotonicNanoseconds
            )
        }
    }

    private struct LocatedRecord {
        let record: Record
        let url: URL
    }

    private struct WriteReservation: Equatable, Sendable {
        let id: UUID
        let generation: UInt64
        let destination: URL
        let writerSessionID: UUID
        let authority: ResponsiveAudioCursorAuthority
        let position: Position
        let capturedAtMonotonicNanoseconds: UInt64
    }

    private struct PendingHandoff: Equatable, Sendable {
        let id: UUID
        let priorSession: ResponsiveAudioCursorCheckpointSession
        let successorSession: ResponsiveAudioCursorCheckpointSession
    }

    private struct ReservedWrite: Sendable {
        let reservation: WriteReservation
        let expectedRecord: Record
        let encodedRecord: Data
    }

    private struct AuthorityFloor: Sendable {
        let generation: UInt64
        let writerSessionID: UUID
        let position: Position
        let capturedAtMonotonicNanoseconds: UInt64
    }

    public init(directoryURL: URL) throws {
        try self.init(
            directoryURL: directoryURL,
            durableWrite: Self.replaceAtomicallyAndSynchronize
        )
    }

    init(
        directoryURL: URL,
        durableWrite: @escaping DurableWriteOperation
    ) throws {
        let standardized = directoryURL.standardizedFileURL
        try FileManager.default.createDirectory(
            at: standardized,
            withIntermediateDirectories: true
        )
        let canonical = standardized.resolvingSymlinksInPath()
        self.directoryURL = canonical
        slotAURL = canonical.appendingPathComponent(
            "responsive-audio-cursor-a.json",
            isDirectory: false
        )
        slotBURL = canonical.appendingPathComponent(
            "responsive-audio-cursor-b.json",
            isDirectory: false
        )
        slotCURL = canonical.appendingPathComponent(
            "responsive-audio-cursor-c.json",
            isDirectory: false
        )
        self.durableWrite = durableWrite
    }

    public func beginSession(
        authority: ResponsiveAudioCursorAuthority,
        id: UUID = UUID()
    ) throws -> ResponsiveAudioCursorCheckpointSession {
        guard pendingHandoff == nil else {
            throw ResponsiveAudioCursorCheckpointError.staleSession
        }
        guard !writerSessionIDHasBeenUsed(id) else {
            throw ResponsiveAudioCursorCheckpointError.sessionIDReused
        }
        let session = ResponsiveAudioCursorCheckpointSession(
            id: id,
            authority: authority
        )
        usedSessionIDs.insert(id)
        activeSession = session
        return session
    }

    public func owns(
        _ session: ResponsiveAudioCursorCheckpointSession
    ) -> Bool {
        activeSession == session
    }

    /// Coalesces an unchanged position without touching disk. Every accepted
    /// changed position is in the alternate slot and synchronised before the
    /// call returns.
    public func checkpoint(
        _ snapshot: ResponsiveAudioProgramSnapshot,
        session: ResponsiveAudioCursorCheckpointSession,
        capturedAtMonotonicNanoseconds: UInt64
    ) async throws {
        guard activeSession == session, pendingHandoff == nil else {
            throw ResponsiveAudioCursorCheckpointError.staleSession
        }
        guard let write = try reserveCheckpoint(
            snapshot,
            session: session,
            capturedAtMonotonicNanoseconds: capturedAtMonotonicNanoseconds
        ) else { return }
        try await perform(write)
    }

    /// Installs a successor authority only after its first position has been
    /// synchronised. A failed write leaves the prior writer active, so Journey
    /// can either continue under the still-verifiable authority or pause.
    public func handoffSession(
        from priorSession: ResponsiveAudioCursorCheckpointSession,
        to authority: ResponsiveAudioCursorAuthority,
        initialSnapshot: ResponsiveAudioProgramSnapshot,
        capturedAtMonotonicNanoseconds: UInt64,
        id: UUID = UUID()
    ) async throws -> ResponsiveAudioCursorCheckpointSession {
        guard activeSession == priorSession, pendingHandoff == nil else {
            throw ResponsiveAudioCursorCheckpointError.staleSession
        }
        guard !writerSessionIDHasBeenUsed(id) else {
            throw ResponsiveAudioCursorCheckpointError.sessionIDReused
        }
        let successor = ResponsiveAudioCursorCheckpointSession(
            id: id,
            authority: authority
        )
        usedSessionIDs.insert(id)
        let handoff = PendingHandoff(
            id: UUID(),
            priorSession: priorSession,
            successorSession: successor
        )
        pendingHandoff = handoff
        let write: ReservedWrite
        do {
            guard let reserved = try reserveCheckpoint(
                initialSnapshot,
                session: successor,
                capturedAtMonotonicNanoseconds:
                    capturedAtMonotonicNanoseconds
            ) else {
                throw ResponsiveAudioCursorCheckpointError
                    .authorityUnavailable
            }
            write = reserved
        } catch {
            if pendingHandoff == handoff { pendingHandoff = nil }
            throw error
        }
        do {
            try await perform(write)
        } catch {
            if pendingHandoff == handoff { pendingHandoff = nil }
            throw error
        }
        guard pendingHandoff == handoff,
              activeSession == priorSession else {
            if pendingHandoff == handoff { pendingHandoff = nil }
            throw ResponsiveAudioCursorCheckpointError.staleSession
        }
        pendingHandoff = nil
        activeSession = successor
        return successor
    }

    /// Validates and reserves a generation and destination without performing
    /// file I/O that can block actor progress. Nil coalesces an unchanged
    /// position already durable for this exact writer session.
    private func reserveCheckpoint(
        _ snapshot: ResponsiveAudioProgramSnapshot,
        session: ResponsiveAudioCursorCheckpointSession,
        capturedAtMonotonicNanoseconds: UInt64
    ) throws -> ReservedWrite? {
        guard session.authority.validatesNonPosition(snapshot) else {
            throw ResponsiveAudioCursorCheckpointError.authorityMismatch
        }
        _ = try session.authority.replacingPosition(
            cursorSample: snapshot.cursorSample,
            loopIteration: snapshot.loopIteration
        )

        let records = verifiedRecords()
        let latestForAuthority = records
            .filter { $0.record.authority == session.authority }
            .max { $0.record.generation < $1.record.generation }
        let latestReservedForAuthority = inFlightWritesByURL.values
            .filter { $0.authority == session.authority }
            .max { $0.generation < $1.generation }
        let proposed = Position(
            cursorSample: snapshot.cursorSample,
            loopIteration: snapshot.loopIteration
        )
        if let latestForAuthority {
            if latestForAuthority.record.writerSessionID == session.id {
                guard capturedAtMonotonicNanoseconds
                        >= latestForAuthority.record
                            .capturedAtMonotonicNanoseconds else {
                    throw ResponsiveAudioCursorCheckpointError.positionRegressed
                }
                if latestForAuthority.record.position == proposed,
                   latestReservedForAuthority == nil {
                    return nil
                }
            }
        }

        let durableFloor = latestForAuthority.map {
            AuthorityFloor(
                generation: $0.record.generation,
                writerSessionID: $0.record.writerSessionID,
                position: $0.record.position,
                capturedAtMonotonicNanoseconds:
                    $0.record.capturedAtMonotonicNanoseconds
            )
        }
        let reservedFloor = latestReservedForAuthority.map {
            AuthorityFloor(
                generation: $0.generation,
                writerSessionID: $0.writerSessionID,
                position: $0.position,
                capturedAtMonotonicNanoseconds:
                    $0.capturedAtMonotonicNanoseconds
            )
        }
        let authorityFloor: AuthorityFloor?
        switch (durableFloor, reservedFloor) {
        case let (.some(durable), .some(reserved)):
            authorityFloor = durable.generation >= reserved.generation
                ? durable
                : reserved
        case let (.some(durable), .none):
            authorityFloor = durable
        case let (.none, .some(reserved)):
            authorityFloor = reserved
        case (.none, .none):
            authorityFloor = nil
        }
        if let authorityFloor {
            if authorityFloor.writerSessionID == session.id {
                guard capturedAtMonotonicNanoseconds
                        >= authorityFloor
                            .capturedAtMonotonicNanoseconds else {
                    throw ResponsiveAudioCursorCheckpointError
                        .positionRegressed
                }
            }
            guard ResponsiveAudioCursorAuthority.isMonotonic(
                cursorSample: proposed.cursorSample,
                loopIteration: proposed.loopIteration,
                afterCursorSample: authorityFloor.position.cursorSample,
                afterLoopIteration: authorityFloor.position.loopIteration
            ) else {
                throw ResponsiveAudioCursorCheckpointError.positionRegressed
            }
        }

        let latestDurableGeneration = records
            .map(\.record.generation)
            .max() ?? 0
        let priorGeneration = max(
            latestDurableGeneration,
            highestReservedGeneration
        )
        guard priorGeneration < UInt64.max else {
            throw ResponsiveAudioCursorCheckpointError.generationExhausted
        }
        let destination = try reserveDestination(records: records)
        let material = RecordMaterial(
            formatVersion: ResponsiveAudioCursorAuthority.currentFormatVersion,
            generation: priorGeneration + 1,
            writerSessionID: session.id,
            authority: session.authority,
            position: proposed,
            capturedAtMonotonicNanoseconds: capturedAtMonotonicNanoseconds
        )
        let record = Record(
            formatVersion: material.formatVersion,
            generation: material.generation,
            writerSessionID: material.writerSessionID,
            authority: material.authority,
            position: material.position,
            capturedAtMonotonicNanoseconds:
                material.capturedAtMonotonicNanoseconds,
            digest: try ResponsiveAudioCursorAuthority.digest(material)
        )
        let reservation = WriteReservation(
            id: UUID(),
            generation: material.generation,
            destination: destination,
            writerSessionID: session.id,
            authority: session.authority,
            position: proposed,
            capturedAtMonotonicNanoseconds:
                capturedAtMonotonicNanoseconds
        )
        highestReservedGeneration = material.generation
        inFlightWritesByURL[destination] = reservation
        return ReservedWrite(
            reservation: reservation,
            expectedRecord: record,
            encodedRecord: try Self.encoder.encode(record)
        )
    }

    private func reserveDestination(
        records: [LocatedRecord]
    ) throws -> URL {
        guard inFlightWritesByURL.count < 2 else {
            throw ResponsiveAudioCursorCheckpointError.durabilityFailure
        }
        let generationsByURL = Dictionary(
            uniqueKeysWithValues: records.map {
                ($0.url, $0.record.generation)
            }
        )
        let available = allSlotURLs.filter {
            inFlightWritesByURL[$0] == nil
        }
        guard let destination = available.min(by: { lhs, rhs in
            let left = generationsByURL[lhs] ?? 0
            let right = generationsByURL[rhs] ?? 0
            if left != right { return left < right }
            return slotOrdinal(lhs) < slotOrdinal(rhs)
        }) else {
            throw ResponsiveAudioCursorCheckpointError.durabilityFailure
        }
        return destination
    }

    /// The synchronous fsync/rename sequence is detached from actor
    /// isolation. Its destination remains reserved until it returns, so no
    /// later generation can collide with or be overwritten by this write.
    private func perform(_ write: ReservedWrite) async throws {
        let operation = durableWrite
        let data = write.encodedRecord
        let destination = write.reservation.destination
        let result = await Task.detached(priority: .userInitiated) {
            Result { try operation(data, destination) }
        }.value
        do {
            try result.get()
            guard inFlightWritesByURL[destination] == write.reservation,
                  verifiedRecord(at: destination)
                    == write.expectedRecord else {
                quarantinedSlotURLs.insert(destination)
                inFlightWritesByURL.removeValue(forKey: destination)
                throw ResponsiveAudioCursorCheckpointError
                    .durabilityFailure
            }
            quarantinedSlotURLs.remove(destination)
            inFlightWritesByURL.removeValue(forKey: destination)
            resumeRetirementWaitersIfDrained(
                writerSessionID: write.reservation.writerSessionID
            )
        } catch {
            quarantinedSlotURLs.insert(destination)
            if inFlightWritesByURL[destination] == write.reservation {
                inFlightWritesByURL.removeValue(forKey: destination)
            }
            resumeRetirementWaitersIfDrained(
                writerSessionID: write.reservation.writerSessionID
            )
            throw ResponsiveAudioCursorCheckpointError.durabilityFailure
        }
    }

    private func resumeRetirementWaitersIfDrained(
        writerSessionID: UUID
    ) {
        guard !inFlightWritesByURL.values.contains(where: {
            $0.writerSessionID == writerSessionID
        }) else { return }
        let waiters = retirementWaitersByWriterSessionID.removeValue(
            forKey: writerSessionID
        ) ?? []
        for waiter in waiters { waiter.resume() }
    }

    private var allSlotURLs: [URL] {
        [slotAURL, slotBURL, slotCURL]
    }

    private func slotOrdinal(_ url: URL) -> Int {
        if url == slotAURL { return 0 }
        if url == slotBURL { return 1 }
        return 2
    }

    private func writerSessionIDHasBeenUsed(_ id: UUID) -> Bool {
        usedSessionIDs.contains(id) || verifiedRecords(
            includingProcessUnconfirmed: true
        ).contains {
            $0.record.writerSessionID == id
        }
    }

    /// Returns a cursor overlay only after the caller has restored canonical
    /// Journey state and recreated its exact authority. A newer unrelated
    /// Journey revision therefore cannot accidentally consume an older slot.
    public func recover(
        authority: ResponsiveAudioCursorAuthority
    ) throws -> ResponsiveAudioProgramSnapshot? {
        let record = verifiedRecords()
            .filter { $0.record.authority == authority }
            .max { $0.record.generation < $1.record.generation }?
            .record
        guard let record else { return nil }
        return try authority.replacingPosition(
            cursorSample: record.position.cursorSample,
            loopIteration: record.position.loopIteration
        )
    }

    /// Revokes future writes and does not return until every write already
    /// reserved by this exact writer session has finished its durable I/O and
    /// actor-side verification. A caller may therefore inspect recovery after
    /// retirement without a latent old writer changing the answer later.
    public func retire(
        _ session: ResponsiveAudioCursorCheckpointSession
    ) async {
        var retiringWriterSessionIDs: Set<UUID> = [session.id]
        if let pendingHandoff,
           pendingHandoff.priorSession == session {
            retiringWriterSessionIDs.insert(
                pendingHandoff.successorSession.id
            )
        }
        if activeSession == session { activeSession = nil }
        for writerSessionID in retiringWriterSessionIDs {
            while inFlightWritesByURL.values.contains(where: {
                $0.writerSessionID == writerSessionID
            }) {
                await withCheckedContinuation { continuation in
                    if inFlightWritesByURL.values.contains(where: {
                        $0.writerSessionID == writerSessionID
                    }) {
                        retirementWaitersByWriterSessionID[
                            writerSessionID,
                            default: []
                        ].append(continuation)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func verifiedRecords(
        includingProcessUnconfirmed: Bool = false
    ) -> [LocatedRecord] {
        allSlotURLs.compactMap { url in
            if !includingProcessUnconfirmed,
               inFlightWritesByURL[url] != nil
                || quarantinedSlotURLs.contains(url) {
                return nil
            }
            guard let record = verifiedRecord(at: url) else { return nil }
            return LocatedRecord(record: record, url: url)
        }
    }

    private func verifiedRecord(at url: URL) -> Record? {
        guard let bytes = try? Data(contentsOf: url),
              let record = try? Self.decoder.decode(Record.self, from: bytes),
              record.formatVersion
                == ResponsiveAudioCursorAuthority.currentFormatVersion,
              record.authority.formatVersion
                == ResponsiveAudioCursorAuthority.currentFormatVersion,
              let expected = try? ResponsiveAudioCursorAuthority.digest(
                record.material
              ), expected == record.digest else {
            return nil
        }
        return record
    }

    private static let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }()

    private static let decoder = JSONDecoder()

    private nonisolated static func replaceAtomicallyAndSynchronize(
        _ data: Data,
        at destination: URL
    ) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        let descriptor = open(
            temporary.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw ResponsiveAudioCursorCheckpointError.durabilityFailure
        }
        var descriptorIsOpen = true
        var shouldRemoveTemporary = true
        defer {
            if descriptorIsOpen { _ = close(descriptor) }
            if shouldRemoveTemporary { _ = unlink(temporary.path) }
        }
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                guard count > 0 else {
                    throw ResponsiveAudioCursorCheckpointError.durabilityFailure
                }
                offset += count
            }
        }
        guard fsync(descriptor) == 0 else {
            throw ResponsiveAudioCursorCheckpointError.durabilityFailure
        }
        let closeResult = close(descriptor)
        descriptorIsOpen = false
        guard closeResult == 0 else {
            throw ResponsiveAudioCursorCheckpointError.durabilityFailure
        }
        guard rename(temporary.path, destination.path) == 0 else {
            throw ResponsiveAudioCursorCheckpointError.durabilityFailure
        }
        shouldRemoveTemporary = false
        let directoryDescriptor = open(
            destination.deletingLastPathComponent().path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC
        )
        guard directoryDescriptor >= 0 else {
            throw ResponsiveAudioCursorCheckpointError.durabilityFailure
        }
        defer { _ = close(directoryDescriptor) }
        guard fsync(directoryDescriptor) == 0 else {
            throw ResponsiveAudioCursorCheckpointError.durabilityFailure
        }
    }
}
