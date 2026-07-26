@testable import JourneyPersistence
import XCTest

@MainActor
final class PersistenceAuthorityFenceTests: XCTestCase {
    func testCapturedAuthorityCannotAppendAfterIdenticalReplacement() async throws {
        let harness = PersistenceAuthorityHarness()
        let committerA = PersistenceAuthorityCommitter()
        let receiptA = try harness.accept(committerA)
        let factoryBarrier = PersistenceAuthorityBarrier()

        let staleFactory = Task { @MainActor in
            await factoryBarrier.enterAndWait()
            try harness.appendUsingCapturedAuthority(
                committerA,
                receipt: receiptA
            )
        }
        await factoryBarrier.waitUntilEntered()

        // Content, route and beat are deliberately unchanged. Only the
        // accepted persistence object changes.
        let committerB = PersistenceAuthorityCommitter()
        let receiptB = try harness.accept(committerB)
        XCTAssertNotEqual(receiptA, receiptB)

        await factoryBarrier.release()
        do {
            try await staleFactory.value
            XCTFail("The captured A authority must be rejected")
        } catch let error as PersistenceAuthorityHarnessError {
            XCTAssertEqual(error, .routeAuthorityChanged)
        }
        XCTAssertEqual(committerA.appendCount, 0)

        try harness.appendUsingCapturedAuthority(
            committerB,
            receipt: receiptB
        )
        XCTAssertEqual(committerB.appendCount, 1)
    }

    func testFreshModelCannotReuseAnotherModelsFirstGeneration() throws {
        let committer = PersistenceAuthorityCommitter()
        var first = PersistenceAuthorityFence()
        var second = PersistenceAuthorityFence()

        let firstReceipt = try first.accept(committer)
        let secondReceipt = try second.accept(committer)

        XCTAssertNotEqual(firstReceipt, secondReceipt)
        XCTAssertFalse(first.matches(secondReceipt, authority: committer))
        XCTAssertFalse(second.matches(firstReceipt, authority: committer))
    }
}

@MainActor
private final class PersistenceAuthorityHarness {
    private var fence = PersistenceAuthorityFence()

    func accept(
        _ committer: PersistenceAuthorityCommitter
    ) throws -> PersistenceAuthorityFence.Receipt {
        try fence.accept(committer)
    }

    func appendUsingCapturedAuthority(
        _ committer: PersistenceAuthorityCommitter,
        receipt: PersistenceAuthorityFence.Receipt
    ) throws {
        guard fence.matches(receipt, authority: committer) else {
            throw PersistenceAuthorityHarnessError.routeAuthorityChanged
        }
        committer.append()
    }
}

@MainActor
private final class PersistenceAuthorityCommitter {
    private(set) var appendCount = 0

    func append() {
        appendCount += 1
    }
}

private enum PersistenceAuthorityHarnessError: Error, Equatable {
    case routeAuthorityChanged
}

private actor PersistenceAuthorityBarrier {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        waiters.forEach { $0.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        guard !released else { return }
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
