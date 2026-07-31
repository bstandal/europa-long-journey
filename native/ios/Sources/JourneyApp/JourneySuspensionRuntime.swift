import AVFAudio
import Foundation
import JourneyPersistence
import UIKit

@MainActor
final class ApplicationSuspensionExecutionLease:
    JourneySuspensionExecutionLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var didEnd = false

    static func begin(
        expiration: @escaping @MainActor () -> Void
    ) -> ApplicationSuspensionExecutionLease? {
        let lease = ApplicationSuspensionExecutionLease()
        let identifier = UIApplication.shared.beginBackgroundTask(
            withName: "Persist Journey position"
        ) { [weak lease] in
            Task { @MainActor [weak lease] in
                guard let lease, !lease.didEnd else { return }
                expiration()
            }
        }
        guard identifier != .invalid else { return nil }
        lease.identifier = identifier
        return lease
    }

    func end() {
        guard !didEnd else { return }
        didEnd = true
        let identifier = identifier
        self.identifier = .invalid
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
    }

    deinit {
        // The coordinator owns and ends every admitted lease. Deinit is a
        // final idempotent guard for a construction/teardown exception.
        if !didEnd, identifier != .invalid {
            let identifier = identifier
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(identifier)
            }
        }
    }
}

@MainActor
final class JourneyAudioSessionLifecycleObserver {
    enum Event: Equatable {
        case interruptionBegan
        case interruptionEnded
        case routeChanged(reasonRawValue: UInt?)
    }

    private let center: NotificationCenter
    private let receive: @MainActor (Event) -> Void
    private let tokenBag: NotificationTokenBag

    /// Block-observer tokens are Objective-C identities and therefore are not
    /// `Sendable`. Keeping their teardown in a deliberately unchecked,
    /// non-actor helper lets deinit remove them without reaching into
    /// MainActor-isolated storage from Swift's nonisolated deinitializer.
    private final class NotificationTokenBag: @unchecked Sendable {
        let center: NotificationCenter
        var tokens: [NSObjectProtocol] = []

        init(center: NotificationCenter) {
            self.center = center
        }

        deinit {
            for token in tokens { center.removeObserver(token) }
        }
    }

    init(
        center: NotificationCenter = .default,
        receive: @escaping @MainActor (Event) -> Void
    ) {
        self.center = center
        self.receive = receive
        tokenBag = NotificationTokenBag(center: center)
    }

    func start() {
        guard tokenBag.tokens.isEmpty else { return }
        tokenBag.tokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let rawValue = notification.userInfo?[
                    AVAudioSessionInterruptionTypeKey
                ] as? UInt
                let type = rawValue.flatMap(AVAudioSession.InterruptionType.init)
                Task { @MainActor [weak self] in
                    switch type {
                    case .began:
                        self?.receive(.interruptionBegan)
                    case .ended:
                        self?.receive(.interruptionEnded)
                    case nil:
                        break
                    @unknown default:
                        self?.receive(.interruptionBegan)
                    }
                }
            }
        )
        tokenBag.tokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let reasonRawValue = notification.userInfo?[
                    AVAudioSessionRouteChangeReasonKey
                ] as? UInt
                guard JourneyAudioRouteChangeSuspensionPolicy.shouldSuspend(
                    reasonRawValue: reasonRawValue
                ) else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.receive(
                        .routeChanged(reasonRawValue: reasonRawValue)
                    )
                }
            }
        )
    }

    func stop() {
        for token in tokenBag.tokens { center.removeObserver(token) }
        tokenBag.tokens.removeAll()
    }
}
