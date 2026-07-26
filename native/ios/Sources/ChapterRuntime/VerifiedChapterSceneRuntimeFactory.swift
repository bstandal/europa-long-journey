import ContentKit
import Foundation
import JourneyContent
import JourneyDomain
import ProgressStore
import SceneRuntime

public enum VerifiedChapterSceneRuntimeFactoryError: Error, Equatable, Sendable {
    case chapterUnavailable(ChapterID)
    case packageAuthorityMissing(PackageID)
    case packageAuthorityMismatch(PackageID)
    case activeRouteMismatch(ChapterID)
    case activePackageMismatch(PackageID)
}

/// The immutable authority captured when a production chapter route opens.
/// Its controller, repository, verified manifest and activated root all come
/// from the same `VerifiedJourneyContentSnapshot` revision.
@MainActor
public struct VerifiedChapterSceneRuntime {
    public let contentRevision: UInt64
    public let chapterID: ChapterID
    public let packageID: PackageID
    public let assetFailureAuthority: PackageAssetFailureAuthority
    public let controller: ChapterSceneRuntimeController

    public init(
        contentRevision: UInt64,
        chapterID: ChapterID,
        packageID: PackageID,
        assetFailureAuthority: PackageAssetFailureAuthority,
        controller: ChapterSceneRuntimeController
    ) {
        self.contentRevision = contentRevision
        self.chapterID = chapterID
        self.packageID = packageID
        self.assetFailureAuthority = assetFailureAuthority
        self.controller = controller
    }
}

/// Production composition boundary from verified repository authority to the
/// scene-facing runtime. There is deliberately no payload-only overload: an
/// app route cannot create a scene inventory without the verifier-created
/// package value and exact activated root from the same snapshot.
@MainActor
public enum VerifiedChapterSceneRuntimeFactory {
    public static func make(
        snapshot: VerifiedJourneyContentSnapshot,
        chapterID: ChapterID,
        committer: DurableJourneyCommitter,
        viewportCropID: String,
        reduceMotion: Bool,
        hapticBridge: (any ChapterRuntimeHapticBridging)? = nil,
        audioConsequenceBridge: (any ChapterRuntimeAudioConsequenceBridging)? = nil
    ) async throws -> VerifiedChapterSceneRuntime {
        try await make(
            authority: snapshot.chapterRuntimeAuthority,
            chapterID: chapterID,
            committer: committer,
            viewportCropID: viewportCropID,
            reduceMotion: reduceMotion,
            hapticBridge: hapticBridge,
            audioConsequenceBridge: audioConsequenceBridge
        )
    }

    /// Shared production entry for launch chapters and later deep dives. The
    /// caller may not supply a naked repository or package root; both must be
    /// captured in one verifier-backed authority revision.
    public static func make(
        authority: VerifiedChapterRuntimeContentAuthority,
        chapterID: ChapterID,
        committer: DurableJourneyCommitter,
        viewportCropID: String,
        reduceMotion: Bool,
        hapticBridge: (any ChapterRuntimeHapticBridging)? = nil,
        audioConsequenceBridge: (any ChapterRuntimeAudioConsequenceBridging)? = nil
    ) async throws -> VerifiedChapterSceneRuntime {
        guard authority.repository.chapter(chapterID) != nil,
              let packageID = authority.repository.packageID(for: chapterID),
              let contentVersion = authority.repository.contentVersion(for: chapterID) else {
            throw VerifiedChapterSceneRuntimeFactoryError.chapterUnavailable(chapterID)
        }
        guard let verifiedPackage = authority.verifiedPackage(for: packageID),
              let activatedRoot = authority.packageRootURL(for: packageID),
              let assetFailureAuthority = authority.assetFailureAuthority(
                  for: packageID
              ) else {
            throw VerifiedChapterSceneRuntimeFactoryError.packageAuthorityMissing(packageID)
        }
        guard verifiedPackage.payload.packageID == packageID,
              verifiedPackage.manifest.packageID == packageID,
              verifiedPackage.manifest.packageVersion == contentVersion,
              verifiedPackage.payload.chapters.contains(where: { $0.id == chapterID }) else {
            throw VerifiedChapterSceneRuntimeFactoryError.packageAuthorityMismatch(packageID)
        }

        let journeyState = await committer.currentCommittedState()
        guard journeyState.route == .chapter(chapterID) else {
            throw VerifiedChapterSceneRuntimeFactoryError.activeRouteMismatch(chapterID)
        }
        guard let activeChapter = journeyState.activeChapter,
              activeChapter.chapterID == chapterID,
              activeChapter.packageID == packageID,
              activeChapter.contentVersion == contentVersion else {
            throw VerifiedChapterSceneRuntimeFactoryError.activePackageMismatch(packageID)
        }

        // Construction binds every authored scene path to its signed manifest
        // record and activated root. Metal rechecks the selected frame bytes at
        // first texture load, so a post-activation replacement still fails
        // closed without forcing every chapter asset into memory on route entry.
        let assets = try await Task.detached(priority: .userInitiated) {
            try SceneAssetInventory(
                verifiedPackage: verifiedPackage,
                activatedPackageRoot: activatedRoot
            )
        }.value
        try Task.checkCancellation()
        let controller = try await ChapterSceneRuntimeController(
            committer: committer,
            coordinator: ChapterCoordinator(repository: authority.repository),
            assets: assets,
            viewportCropID: viewportCropID,
            reduceMotion: reduceMotion,
            hapticBridge: hapticBridge,
            audioConsequenceBridge: audioConsequenceBridge
        )
        guard controller.presentation.cursor.chapter.id == chapterID,
              controller.presentation.cursor.packageID == packageID,
              controller.presentation.cursor.contentVersion == contentVersion else {
            throw VerifiedChapterSceneRuntimeFactoryError.packageAuthorityMismatch(packageID)
        }
        return VerifiedChapterSceneRuntime(
            contentRevision: authority.revision,
            chapterID: chapterID,
            packageID: packageID,
            assetFailureAuthority: assetFailureAuthority,
            controller: controller
        )
    }
}
