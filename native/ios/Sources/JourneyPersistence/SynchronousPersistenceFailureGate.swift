/// Orders a fail-closed physical stop before persistence becomes unavailable.
/// The operation is synchronous by design: once `lockPersistence` runs, no
/// later lifecycle callback can be relied on to stop uncheckpointed output.
@MainActor
public enum SynchronousPersistenceFailureGate {
    public static func close(
        physicalStop: @MainActor () -> Void,
        lockPersistence: @MainActor () -> Void
    ) {
        physicalStop()
        lockPersistence()
    }
}
