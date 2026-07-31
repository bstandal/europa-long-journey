import Foundation
import Synchronization

/// One stable render boundary whose worker authority is fenced by playback
/// epoch. Audio units retain this object across stop, reset, and resume; only
/// the worker-facing token changes.
public final class NativeAudioDurabilityGate: @unchecked Sendable {
    public enum ResetError: Error, Equatable, Sendable {
        case invalidRenderedGraphSample
        case transportIsRunning
        case epochExhausted
    }

    public struct EpochToken: ActiveAudioCursorGateAuthorizing, Sendable {
        public let epoch: UInt64
        private let owner: NativeAudioDurabilityGate

        fileprivate init(owner: NativeAudioDurabilityGate, epoch: UInt64) {
            self.owner = owner
            self.epoch = epoch
        }

        public func claimCapture(
            atRenderedGraphSample sample: Int64
        ) -> Bool {
            owner.claimCapture(sample, epoch: epoch)
        }

        public func authorizeAudio(
            throughRenderedGraphSample cutoff: Int64
        ) -> Bool {
            owner.authorizeAudio(cutoff, epoch: epoch)
        }

        /// Atomically replaces worker authority with one terminal transport
        /// tail. A render callback that has already closed the durable prefix
        /// wins; a successful call permanently rejects later worker claims
        /// and extensions for this epoch.
        func authorizeTerminalTail(
            fromRenderedGraphSample capturedSample: Int64,
            throughRenderedGraphSample terminalCutoff: Int64
        ) -> Bool {
            owner.authorizeTerminalTail(
                from: capturedSample,
                through: terminalCutoff,
                epoch: epoch
            )
        }

        /// Closes worker authority before transport quiescence begins. Render
        /// callbacks may finish only the already-authorized prefix until the
        /// engine stop below drains them.
        @discardableResult
        public func transportWillStop() -> Bool {
            owner.markTransportStopping(epoch: epoch)
        }

        /// Call only after this epoch's transport has stopped and drained all
        /// render callbacks. A stale token cannot stop a successor epoch.
        @discardableResult
        public func transportDidStop() -> Bool {
            owner.markTransportStopped(epoch: epoch)
        }
    }

    private static let runningBit: UInt64 = 1 << 63
    private static let resettingBit: UInt64 = 1 << 62
    private static let stoppingBit: UInt64 = 1 << 61
    private static let terminalTailBit: UInt64 = 1 << 60
    private static let epochMask = ~(
        runningBit | resettingBit | stoppingBit | terminalTailBit
    )

    // Control operations may lock. The audio render path reads only these two
    // atomics and never allocates, retains, or enters the control lock.
    private let controlLock = NSLock()
    private let activeEpochAndTransport = Atomic<UInt64>(0)
    /// Monotone token identity is kept outside the active render word so a
    /// stopped epoch can retire to zero. That inactive state lets AVAudioEngine
    /// pre-roll silent graph pulls before the next graph start is known without
    /// accidentally reviving the old epoch or blocking the reset.
    private var issuedEpoch: UInt64 = 0
    // Nonnegative values are open cutoffs. A latched cutoff is encoded as its
    // bitwise complement so every bus rendering the same quantum observes the
    // same exact prefix while authorization remains permanently disabled.
    private let cutoff = Atomic<Int64>(~Int64(0))

    public init() {}

    /// Starts a new authority epoch. The initial cutoff is exclusive: the
    /// sample at the cutoff is the first sample that must be silent.
    public func resetWhileTransportStopped(
        atRenderedGraphSample initialCutoff: Int64
    ) throws -> EpochToken {
        guard initialCutoff >= 0 else {
            throw ResetError.invalidRenderedGraphSample
        }
        controlLock.lock()
        defer { controlLock.unlock() }

        let active = activeEpochAndTransport.load(ordering: .acquiring)
        guard active & Self.resettingBit == 0,
              active & Self.epochMask == 0,
              active & Self.runningBit == 0 else {
            throw ResetError.transportIsRunning
        }
        guard issuedEpoch < Self.epochMask else {
            throw ResetError.epochExhausted
        }
        issuedEpoch += 1
        let nextEpoch = issuedEpoch

        // The resetting marker prevents a render callback from observing the
        // new cutoff under the old epoch or claiming the running bit midway.
        activeEpochAndTransport.store(
            Self.resettingBit,
            ordering: .releasing
        )
        cutoff.store(initialCutoff, ordering: .releasing)
        activeEpochAndTransport.store(nextEpoch, ordering: .releasing)
        return EpochToken(owner: self, epoch: nextEpoch)
    }

    private func markTransportStopped(epoch: UInt64) -> Bool {
        controlLock.lock()
        defer { controlLock.unlock() }

        let active = activeEpochAndTransport.load(ordering: .acquiring)
        guard active & Self.resettingBit == 0,
              active & Self.stoppingBit != 0,
              active & Self.epochMask == epoch else { return false }
        // The caller has already stopped and drained the engine. Retiring to
        // zero makes any pre-roll pull before the next reset fail silent and
        // prevents an old token from matching a later playback epoch.
        activeEpochAndTransport.store(0, ordering: .releasing)
        return true
    }

    private func markTransportStopping(epoch: UInt64) -> Bool {
        controlLock.lock()
        defer { controlLock.unlock() }

        var active = activeEpochAndTransport.load(ordering: .acquiring)
        while true {
            guard active & Self.resettingBit == 0,
                  active & Self.epochMask == epoch else { return false }
            if active & Self.stoppingBit != 0 { return true }
            let result = activeEpochAndTransport.compareExchange(
                expected: active,
                desired: active | Self.stoppingBit,
                ordering: .acquiringAndReleasing
            )
            if result.exchanged { return true }
            active = result.original
        }
    }

    private func claimCapture(_ sample: Int64, epoch: UInt64) -> Bool {
        guard sample >= 0 else { return false }
        controlLock.lock()
        defer { controlLock.unlock() }
        guard isCurrentControlEpoch(epoch) else { return false }

        while true {
            let openCutoff = cutoff.load(ordering: .acquiring)
            guard openCutoff >= 0 else { return false }
            if sample > openCutoff {
                let result = cutoff.compareExchange(
                    expected: openCutoff,
                    desired: ~openCutoff,
                    ordering: .acquiringAndReleasing
                )
                if result.exchanged { return false }
                continue
            }
            // The same-value CAS linearizes this claim against the render
            // callback that may permanently close the gate at this boundary.
            let result = cutoff.compareExchange(
                expected: openCutoff,
                desired: openCutoff,
                ordering: .acquiringAndReleasing
            )
            if result.exchanged { return true }
        }
    }

    private func authorizeAudio(_ proposedCutoff: Int64, epoch: UInt64) -> Bool {
        guard proposedCutoff >= 0 else { return false }
        controlLock.lock()
        defer { controlLock.unlock() }
        guard isCurrentControlEpoch(epoch) else { return false }

        while true {
            let openCutoff = cutoff.load(ordering: .acquiring)
            guard openCutoff >= 0,
                  proposedCutoff >= openCutoff else { return false }
            let result = cutoff.compareExchange(
                expected: openCutoff,
                desired: proposedCutoff,
                ordering: .acquiringAndReleasing
            )
            if result.exchanged { return true }
        }
    }

    private func authorizeTerminalTail(
        from capturedSample: Int64,
        through proposedCutoff: Int64,
        epoch: UInt64
    ) -> Bool {
        guard capturedSample >= 0,
              proposedCutoff >= capturedSample else { return false }
        controlLock.lock()
        defer { controlLock.unlock() }
        guard isCurrentControlEpoch(epoch) else { return false }

        // Seal the epoch while the control lock excludes every worker call.
        // Render callbacks remain lock-free and may still win the cutoff CAS;
        // that failure is final and the transport must stop fail-closed.
        markCurrentEpochAsTerminalTail(epoch: epoch)
        while true {
            let openCutoff = cutoff.load(ordering: .acquiring)
            guard openCutoff >= 0 else { return false }
            guard capturedSample <= openCutoff else {
                let result = cutoff.compareExchange(
                    expected: openCutoff,
                    desired: ~openCutoff,
                    ordering: .acquiringAndReleasing
                )
                if result.exchanged { return false }
                continue
            }
            // A short authored fade may finish inside the already-authorized
            // durability window. Do not shrink that window while render
            // callbacks are in flight; the scheduled gain ramp supplies the
            // exact zero boundary and the terminal bit forbids any extension.
            let terminalCutoff = max(openCutoff, proposedCutoff)
            let result = cutoff.compareExchange(
                expected: openCutoff,
                desired: terminalCutoff,
                ordering: .acquiringAndReleasing
            )
            if result.exchanged { return true }
        }
    }

    private func markCurrentEpochAsTerminalTail(epoch: UInt64) {
        var active = activeEpochAndTransport.load(ordering: .acquiring)
        while true {
            // The control lock makes reset/stop and other authority operations
            // mutually exclusive. Only the render thread may add runningBit.
            precondition(active & Self.epochMask == epoch)
            if active & Self.terminalTailBit != 0 { return }
            let result = activeEpochAndTransport.compareExchange(
                expected: active,
                desired: active | Self.terminalTailBit,
                ordering: .acquiringAndReleasing
            )
            if result.exchanged { return }
            active = result.original
        }
    }

    private func isCurrentControlEpoch(_ epoch: UInt64) -> Bool {
        let active = activeEpochAndTransport.load(ordering: .acquiring)
        return active & Self.resettingBit == 0
            && active & Self.stoppingBit == 0
            && active & Self.terminalTailBit == 0
            && active & Self.epochMask == epoch
    }

    /// Returns the precise audible prefix and permanently closes at the first
    /// denied sample. This is the only method called by the render thread.
    @inline(__always)
    func audibleFrameCount(
        fromRenderedGraphSample renderStart: Int64,
        frameCount: UInt32
    ) -> UInt32 {
        guard renderStart >= 0,
              frameCount > 0,
              markCurrentEpochRunning() else { return 0 }

        while true {
            let encodedCutoff = cutoff.load(ordering: .acquiring)
            let boundary = encodedCutoff >= 0
                ? encodedCutoff
                : ~encodedCutoff
            guard renderStart < boundary else {
                guard encodedCutoff >= 0 else { return 0 }
                let result = cutoff.compareExchange(
                    expected: encodedCutoff,
                    desired: ~boundary,
                    ordering: .acquiringAndReleasing
                )
                if result.exchanged { return 0 }
                continue
            }

            let available = UInt64(boundary - renderStart)
            if available > UInt64(frameCount) { return frameCount }

            if encodedCutoff < 0 {
                return min(frameCount, UInt32(available))
            }

            // Authorization and closing race on this CAS. Whichever operation
            // wins is final: a late durable write cannot reopen a closed gate.
            let result = cutoff.compareExchange(
                expected: encodedCutoff,
                desired: ~boundary,
                ordering: .acquiringAndReleasing
            )
            if result.exchanged { return UInt32(available) }
        }
    }

    @inline(__always)
    private func markCurrentEpochRunning() -> Bool {
        var active = activeEpochAndTransport.load(ordering: .acquiring)
        while true {
            guard active & Self.resettingBit == 0,
                  active & Self.epochMask != 0 else { return false }
            if active & Self.runningBit != 0 { return true }
            let result = activeEpochAndTransport.compareExchange(
                expected: active,
                desired: active | Self.runningBit,
                ordering: .acquiringAndReleasing
            )
            if result.exchanged { return true }
            active = result.original
        }
    }
}
