import Foundation

#if canImport(Network)
import Network
#endif

public struct DownloadNetworkContext: Equatable, Sendable {
    public let basis: DownloadNetworkBasis
    public let isConstrained: Bool

    public init(
        basis: DownloadNetworkBasis,
        isConstrained: Bool = false
    ) {
        self.basis = basis
        self.isConstrained = isConstrained
    }

    public static let unknown = DownloadNetworkContext(basis: .unknown)
}

public protocol DownloadNetworkBasisProviding: Sendable {
    /// Returns the latest completed path observation without waiting for a new
    /// one. Before the first observation, and after monitoring stops, this must
    /// fail closed as `unknown`.
    func currentNetworkBasis() -> DownloadNetworkBasis

    /// Supplies Low Data Mode alongside the basis when the provider can observe
    /// it. The default preserves basis-only providers as unconstrained.
    func currentNetworkContext() -> DownloadNetworkContext
}

public extension DownloadNetworkBasisProviding {
    func currentNetworkContext() -> DownloadNetworkContext {
        DownloadNetworkContext(basis: currentNetworkBasis())
    }
}

enum DownloadNetworkPathStatus: Equatable, Sendable {
    case satisfied
    case unsatisfied
    case requiresConnection
    case unknown
}

enum DownloadNetworkInterface: Hashable, Sendable {
    case wifi
    case cellular
    case wired
    case other
}

struct DownloadNetworkPathSnapshot: Equatable, Sendable {
    let status: DownloadNetworkPathStatus
    let activeInterfaces: Set<DownloadNetworkInterface>
    let isExpensive: Bool
    let isConstrained: Bool

    init(
        status: DownloadNetworkPathStatus,
        activeInterfaces: Set<DownloadNetworkInterface> = [],
        isExpensive: Bool = false,
        isConstrained: Bool = false
    ) {
        self.status = status
        self.activeInterfaces = activeInterfaces
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
    }
}

protocol DownloadNetworkPathMonitoring: Sendable {
    func start(
        pathUpdate: @escaping @Sendable (DownloadNetworkPathSnapshot) -> Void
    )
    func cancel()
}

enum DownloadNetworkPathMapper {
    static func basis(for snapshot: DownloadNetworkPathSnapshot) -> DownloadNetworkBasis {
        switch snapshot.status {
        case .unsatisfied:
            return .offline
        case .requiresConnection, .unknown:
            return .unknown
        case .satisfied:
            break
        }

        // Apple marks cellular and Personal Hotspot paths as expensive. They
        // share the user's cellular/metered-download gate. Cellular also wins
        // if a multipath route reports more than one active interface.
        if snapshot.isExpensive || snapshot.activeInterfaces.contains(.cellular) {
            return .cellular
        }
        if snapshot.activeInterfaces.contains(.wifi) {
            return .wifi
        }
        if snapshot.activeInterfaces.contains(.wired) {
            return .wired
        }
        return .unknown
    }
}

#if canImport(Network)
/// Narrow `NWPathMonitor` boundary for deciding whether the app may create a
/// new download request. It has no API for an existing Apple-managed transfer.
public final class NWPathDownloadNetworkBasisProvider:
    DownloadNetworkBasisProviding,
    @unchecked Sendable
{
    private let monitor: any DownloadNetworkPathMonitoring
    private let lock = NSLock()
    private var latestContext: DownloadNetworkContext = .unknown
    private var isStopped = false

    public convenience init() {
        self.init(monitor: SystemDownloadNetworkPathMonitor())
    }

    init(monitor: any DownloadNetworkPathMonitoring) {
        self.monitor = monitor
        monitor.start { [weak self] snapshot in
            self?.receive(snapshot)
        }
    }

    deinit {
        stop()
    }

    public func currentNetworkBasis() -> DownloadNetworkBasis {
        lock.withLock { latestContext.basis }
    }

    public func currentNetworkContext() -> DownloadNetworkContext {
        lock.withLock { latestContext }
    }

    /// Cancels monitoring once and returns the provider to its fail-closed
    /// state. Late callbacks are ignored and no task is created by this type.
    public func stop() {
        let shouldCancel = lock.withLock {
            guard !isStopped else { return false }
            isStopped = true
            latestContext = .unknown
            return true
        }
        if shouldCancel {
            monitor.cancel()
        }
    }

    private func receive(_ snapshot: DownloadNetworkPathSnapshot) {
        lock.withLock {
            guard !isStopped else { return }
            latestContext = DownloadNetworkContext(
                basis: DownloadNetworkPathMapper.basis(for: snapshot),
                isConstrained: snapshot.isConstrained
            )
        }
    }
}

private final class SystemDownloadNetworkPathMonitor:
    DownloadNetworkPathMonitoring,
    @unchecked Sendable
{
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.thelongwest.delivery.network-path")
    private let lock = NSLock()
    private var hasStarted = false
    private var isCancelled = false

    func start(
        pathUpdate: @escaping @Sendable (DownloadNetworkPathSnapshot) -> Void
    ) {
        let shouldStart = lock.withLock {
            guard !hasStarted, !isCancelled else { return false }
            hasStarted = true
            return true
        }
        guard shouldStart else { return }

        monitor.pathUpdateHandler = { path in
            pathUpdate(Self.snapshot(for: path))
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        let shouldCancel = lock.withLock {
            guard !isCancelled else { return false }
            isCancelled = true
            return true
        }
        guard shouldCancel else { return }

        monitor.pathUpdateHandler = nil
        monitor.cancel()
    }

    private static func snapshot(for path: NWPath) -> DownloadNetworkPathSnapshot {
        let status: DownloadNetworkPathStatus
        switch path.status {
        case .satisfied:
            status = .satisfied
        case .unsatisfied:
            status = .unsatisfied
        case .requiresConnection:
            status = .requiresConnection
        @unknown default:
            status = .unknown
        }

        var activeInterfaces: Set<DownloadNetworkInterface> = []
        if path.usesInterfaceType(.cellular) {
            activeInterfaces.insert(.cellular)
        }
        if path.usesInterfaceType(.wifi) {
            activeInterfaces.insert(.wifi)
        }
        if path.usesInterfaceType(.wiredEthernet) {
            activeInterfaces.insert(.wired)
        }
        if path.usesInterfaceType(.other) || path.usesInterfaceType(.loopback) {
            activeInterfaces.insert(.other)
        }
        return DownloadNetworkPathSnapshot(
            status: status,
            activeInterfaces: activeInterfaces,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }
}
#endif
