import CommerceKit
import ContentDelivery
import ContentKit
import JourneyContent
import JourneyDomain
import ReleaseDiscovery
import SceneRuntime
import SwiftUI

struct RootView: View {
    @StateObject private var model: JourneyModel
    @ObservedObject private var releaseDiscovery: ReleaseDiscoveryApplicationModel
    @Environment(\.scenePhase) private var scenePhase

    init(
        releaseDiscovery: ReleaseDiscoveryApplicationModel,
        futureReleaseClient: JourneyFutureReleaseClient? = nil
    ) {
        self.releaseDiscovery = releaseDiscovery
#if DEBUG || NON_SHIPPING_LIVE_TEST
        let fixtureClient: JourneyContentClient? = ProcessInfo.processInfo.arguments.contains(
            DevelopmentSignedRuntimeFixtureAppContent.launchArgument
        ) ? try! DevelopmentSignedRuntimeFixtureAppContent.makeClient() : nil
#else
        let fixtureClient: JourneyContentClient? = nil
#endif
        _model = StateObject(
            wrappedValue: JourneyModel(
                contentClient: fixtureClient,
                futureReleaseClient: futureReleaseClient,
                releaseDiscovery: releaseDiscovery
            )
        )
    }

    var body: some View {
        Group {
            if let failure = model.persistenceFailure, !model.isRestoring {
                PersistenceFailureView(message: failure) {
                    model.retryPersistence()
                }
            } else if let failure = model.contentFailure, model.lockedRoad == nil {
                ContentUnavailableView(
                    message: failure,
                    actionTitle: {
                        if case .chapter = model.state.route { return "Return to the road" }
                        return "Close"
                    }()
                ) {
                    if case .chapter = model.state.route {
                        model.showWorldRecoveringChapterFailure()
                    } else {
                        model.dismissContentFailure()
                    }
                }
            } else if let lockedRoad = model.lockedRoad {
                LockedRoadPurchaseView(lockedRoad: lockedRoad, model: model)
            } else if model.isRestoring {
                Color(red: 0.012, green: 0.015, blue: 0.016)
                    .ignoresSafeArea()
                    .accessibilityElement()
                    .accessibilityLabel("Restoring your place")
                    .accessibilityIdentifier("journey-restoring")
            } else {
                switch model.state.route {
                case .prologue:
                    PrologueView(model: model)
                case .world:
                    WorldRouteView(
                        model: model,
                        releaseDiscovery: releaseDiscovery
                    )
                case let .chapter(chapterID):
                    ChapterRouteView(chapterID: chapterID, model: model)
                }
            }
        }
#if DEBUG
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                ZStack {
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Global responsive audio runtime")
                        .accessibilityValue(
                            model.responsiveAudioRuntimeDiagnosticForTesting
                        )
                        .accessibilityIdentifier(
                            "global-responsive-audio-runtime-state"
                        )
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel("Global causal lifecycle state")
                        .accessibilityValue(
                            model.causalLifecycleStateDiagnosticForTesting
                        )
                        .accessibilityIdentifier(
                            "global-causal-lifecycle-state"
                        )
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(
                            "Global content authority barrier diagnostic"
                        )
                        .accessibilityValue(
                            model.contentAuthorityBarrierDiagnosticForTesting
                        )
                        .accessibilityIdentifier(
                            "global-content-authority-barrier-diagnostic"
                        )
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(
                            "Global content authority audio diagnostic"
                        )
                        .accessibilityValue(
                            model.contentAuthorityAudioDiagnosticForTesting
                        )
                        .accessibilityIdentifier(
                            "global-content-authority-audio-diagnostic"
                        )
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(
                            "Ordered exit audio diagnostic"
                        )
                        .accessibilityValue(
                            model.orderedExitAudioDiagnosticForTesting
                        )
                        .accessibilityIdentifier(
                            "ordered-exit-audio-diagnostic"
                        )
                    Color.black.opacity(0.001)
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityLabel(
                            "Suspension persistence retry diagnostic"
                        )
                        .accessibilityValue(
                            model
                                .suspensionPersistenceRetryDiagnosticForTesting
                        )
                        .accessibilityIdentifier(
                            "suspension-persistence-retry-diagnostic"
                        )
                }
                .allowsHitTesting(false)

                if model.orderedRecoveryEpochProbeIsHoldingForTesting {
                    Button("Release recovery epoch probe") {
                        model.releaseOrderedRecoveryEpochProbeForTesting()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .frame(width: 240, height: 48)
                    .padding(.leading, 20)
                    .padding(.top, 80)
                    .zIndex(1_000)
                    .accessibilityIdentifier(
                        "release-ordered-recovery-epoch-probe"
                    )
                }
            }
        }
#endif
        .task {
            model.startLifecycleObservation()
            model.handleScenePhase(scenePhase)
        }
        .onChange(of: scenePhase) { _, phase in
            model.handleScenePhase(phase)
        }
        .onChange(of: releaseDiscovery.pendingDeepLink) { _, _ in
            routePendingReleaseIfReady()
        }
        .onChange(of: model.isRestoring) { _, isRestoring in
            if !isRestoring { routePendingReleaseIfReady() }
        }
        .onChange(of: model.state.prologue.phase) { _, phase in
            if phase == .awakened { routePendingReleaseIfReady() }
        }
        .onChange(of: model.state.route) { _, route in
            if route == .world { routePendingReleaseIfReady() }
        }
        .preferredColorScheme(.dark)
        .sheet(
            item: Binding(
                get: { model.offlineChapterRequest },
                set: { request in
                    if request == nil { model.dismissOfflineChapterRequest() }
                }
            )
        ) { request in
            NavigationStack {
                OfflineChaptersView(
                    model: model,
                    focusedPackageID: request.packageID,
                    showsDismissButton: true
                )
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }

    private func routePendingReleaseIfReady() {
        guard let intent = releaseDiscovery.pendingDeepLink,
              model.openReleaseDeepLink(intent) else {
            return
        }
        Task {
            _ = await releaseDiscovery.consumePendingDeepLink(
                releaseID: intent.releaseID
            )
        }
    }
}

private struct ContentUnavailableView: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Chapter unavailable")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.72, green: 0.52, blue: 0.22))
            }
            .padding(28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("content-unavailable")
    }
}

private struct PersistenceFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.015, blue: 0.016)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Progress is paused")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                Text(message)
                    .foregroundStyle(.secondary)
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.72, green: 0.52, blue: 0.22))
            }
            .padding(28)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("persistence-failure")
    }
}

private struct PrologueView: View {
    @ObservedObject var model: JourneyModel
    @StateObject private var renderer = PrologueRenderer()
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        GeometryReader { geometry in
            switch renderer.configurationState {
            case .notConfigured:
                PrologueConfigurationPendingView()
            case let .failed(failure):
                PrologueConfigurationFailureView(failure: failure) {
                    renderer.configure()
                }
            case .ready:
                ZStack(alignment: .bottom) {
                    PrologueMetalView(
                        renderer: renderer,
                        sceneState: PrologueSceneState(
                            routeReveal: Float(model.state.prologue.traceProgress),
                            focus: Float(0.2 + model.state.prologue.traceProgress * 0.6),
                            reducesMotion: reducesMotion
                        )
                    )
                    .accessibilityHidden(true)
                    .ignoresSafeArea()

                    LinearGradient(
                        colors: [.black.opacity(0.76), .clear, .black.opacity(0.84)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(FoundationCatalog.manifest.product.franchiseName.uppercased())
                            .font(.caption.weight(.semibold))
                            .tracking(3.2)
                            .foregroundStyle(Color(red: 0.72, green: 0.62, blue: 0.43))
                        Text(FoundationCatalog.manifest.product.workTitle)
                            .font(.system(size: 45, weight: .light, design: .serif))
                            .foregroundStyle(Color(red: 0.91, green: 0.89, blue: 0.82))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        Spacer()

                        Text("Follow the road")
                            .font(.system(.headline, design: .serif, weight: .medium))
                            .foregroundStyle(Color(red: 0.91, green: 0.89, blue: 0.82))

                        GeometryReader { track in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.12)).frame(height: 2)
                                Capsule()
                                    .fill(Color(red: 0.80, green: 0.61, blue: 0.30))
                                    .frame(
                                        width: max(2, track.size.width * model.state.prologue.traceProgress),
                                        height: 2
                                    )
                                Circle()
                                    .fill(Color(red: 0.90, green: 0.74, blue: 0.43))
                                    .shadow(color: .orange.opacity(0.5), radius: 12)
                                    .frame(width: 18, height: 18)
                                    .offset(
                                        x: max(
                                            0,
                                            (track.size.width - 18) * model.state.prologue.traceProgress
                                        )
                                    )
                            }
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        model.previewPrologue(
                                            progress: value.location.x / max(track.size.width, 1)
                                        )
                                    }
                                    .onEnded { value in
                                        let progress = min(max(value.location.x / max(track.size.width, 1), 0), 1)
                                        model.persistPrologue(progress: progress)
                                        if progress >= 0.94 { model.completePrologue() }
                                    }
                            )
                            .accessibilityElement()
                            .accessibilityIdentifier("prologue-road-control")
                            .accessibilityLabel("Follow the road")
                            .accessibilityValue(
                                "\(Int((model.state.prologue.traceProgress * 100).rounded())) percent"
                            )
                            .accessibilityHint("Swipe up until the road is awake.")
                            .accessibilityAdjustableAction { direction in
                                let delta = direction == .increment ? 0.2 : -0.2
                                let progress = min(
                                    max(model.state.prologue.traceProgress + delta, 0),
                                    1
                                )
                                model.previewPrologue(progress: progress)
                                model.persistPrologue(progress: progress)
                                if progress >= 0.94 { model.completePrologue() }
                            }
                        }
                        .frame(height: 44)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, max(24, geometry.safeAreaInsets.top + 12))
                    .padding(.bottom, max(24, geometry.safeAreaInsets.bottom + 20))
                }
            }
        }
        .task {
            if renderer.configurationState == .notConfigured {
                renderer.configure()
            }
        }
    }
}

private struct PrologueConfigurationPendingView: View {
    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.015, blue: 0.016)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .tint(Color(red: 0.80, green: 0.61, blue: 0.30))
                Text("Preparing the opening scene")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color(red: 0.91, green: 0.89, blue: 0.82))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preparing the opening scene")
        }
    }
}

private struct PrologueConfigurationFailureView: View {
    let failure: PrologueRendererConfigurationFailure
    let retry: () -> Void
    @AccessibilityFocusState private var headingIsFocused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.015, blue: 0.016)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("The opening scene could not start")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingIsFocused)
                Text("Your saved place has not changed. Try again, or close and reopen the app.")
                    .foregroundStyle(.secondary)
                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.72, green: 0.52, blue: 0.22))
#if DEBUG
                Text("DEBUG · \(failure.rawValue)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
#endif
            }
            .padding(28)
        }
        .onAppear {
            headingIsFocused = true
        }
    }
}

private struct WorldRouteView: View {
    @ObservedObject var model: JourneyModel
    @ObservedObject var releaseDiscovery: ReleaseDiscoveryApplicationModel
    @State private var settingsArePresented = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(FoundationCatalog.manifest.product.franchiseName.uppercased())
                                .font(.caption2.weight(.semibold))
                                .tracking(2.8)
                                .foregroundStyle(.secondary)
                            Text(FoundationCatalog.manifest.product.workTitle)
                                .font(.system(size: 34, weight: .light, design: .serif))
                                .foregroundStyle(Color(red: 0.91, green: 0.89, blue: 0.82))
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 28)

                        LivingWorldField(
                            world: model.state.world,
                            retainedReleaseEntries:
                                model.retainedFutureReleaseWorldEntries,
                            focus: model.releaseWorldFocus,
                            announcement: model.releaseWorldFocus.flatMap { focus in
                                model.futureReleaseAnnouncement(
                                    for: focus.releaseID
                                )
                            },
                            releaseState: model.releaseWorldFocus.map {
                                model.futureReleasePresentationState(
                                    for: $0.releaseID
                                )
                            },
                            releaseFailureMessage: model.releaseWorldFocus
                                .flatMap {
                                    model.futureReleaseFailureMessage(
                                        for: $0.releaseID
                                    )
                                },
                            releaseActionIsPending:
                                model.futureReleaseCommandIsPending,
                            selectRetainedRelease: {
                                _ = model.focusRetainedFutureRelease($0)
                            },
                            releaseAction: {
                                guard let releaseID = model.releaseWorldFocus?
                                    .releaseID else { return }
                                if model.futureReleasePresentationState(
                                    for: releaseID
                                ) == .ready {
                                    _ = model.openFutureRelease(releaseID)
                                } else {
                                    model.requestFutureReleaseDownload(releaseID)
                                }
                            }
                        )
                            .frame(height: 230)
                            .padding(.top, 18)

                        ChapterRoad(
                            chapters: FoundationCatalog.chapters,
                            completedChapterIDs: Set(model.state.completedChapterIDs),
                            activeChapterID: model.state.mostRecentlyVisitedChapterID,
                            access: { model.access(to: $0) },
                            select: model.selectChapter
                        )
                        .padding(.top, 8)
                        .padding(.bottom, 52)
                    }
                }
                .background(Color(red: 0.012, green: 0.015, blue: 0.016).ignoresSafeArea())
                .scrollIndicators(.hidden)
                .onAppear {
                    guard let chapterID = model.state.mostRecentlyVisitedChapterID else { return }
                    proxy.scrollTo(chapterID, anchor: .center)
                }
            }

            Button {
                settingsArePresented = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.84, green: 0.77, blue: 0.64))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.68), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.10), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("experience-settings-open")
#if DEBUG
            .accessibilityValue(model.journeyProgressFingerprintForTesting)
#endif
            .padding(.top, 14)
            .padding(.trailing, 18)
        }
        .sheet(isPresented: $settingsArePresented) {
            ExperienceSettingsView(
                model: model,
                releaseDiscovery: releaseDiscovery
            )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }
}

private struct ExperienceSettingsView: View {
    @ObservedObject var model: JourneyModel
    @ObservedObject var releaseDiscovery: ReleaseDiscoveryApplicationModel
    @Environment(\.dismiss) private var dismiss

    private let surface = Color(red: 0.022, green: 0.026, blue: 0.026)
    private let line = Color.white.opacity(0.09)
    private let accent = Color(red: 0.80, green: 0.61, blue: 0.30)

    var body: some View {
        NavigationStack {
            ZStack {
                surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Settings")
                                .font(.system(.title2, design: .serif, weight: .semibold))
                                .foregroundStyle(Color(red: 0.92, green: 0.90, blue: 0.84))
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Button("Done") { dismiss() }
                                .font(.body.weight(.semibold))
                                .foregroundStyle(accent)
                                .frame(minWidth: 52, minHeight: 52)
                                .contentShape(Rectangle())
                                .accessibilityIdentifier("experience-settings-close")
                        }
                        .padding(.bottom, 18)

                        preferenceToggle(
                            "Narration",
                            identifier: "experience-setting-narration",
                            isOn: Binding(
                                get: { model.experiencePreferences.narrationEnabled },
                                set: { model.setNarrationEnabled($0) }
                            )
                        )
                        preferenceToggle(
                            "Score",
                            identifier: "experience-setting-score",
                            isOn: Binding(
                                get: { model.experiencePreferences.scoreEnabled },
                                set: { model.setScoreEnabled($0) }
                            )
                        )
                        preferenceToggle(
                            "Soundscape",
                            identifier: "experience-setting-soundscape",
                            isOn: Binding(
                                get: { model.experiencePreferences.soundscapeEnabled },
                                set: { model.setSoundscapeEnabled($0) }
                            )
                        )
                        preferenceToggle(
                            "Haptics",
                            identifier: "experience-setting-haptics",
                            isOn: Binding(
                                get: { model.experiencePreferences.hapticsEnabled },
                                set: { model.setHapticsEnabled($0) }
                            )
                        )

                        releaseNotificationControl

                        if model.downloadSurfaceIsConfigured {
                            NavigationLink {
                                OfflineChaptersView(
                                    model: model,
                                    focusedPackageID: nil,
                                    showsDismissButton: false
                                )
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 18, weight: .regular))
                                        .foregroundStyle(accent)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Offline chapters")
                                            .font(.system(.body, design: .serif))
                                            .foregroundStyle(
                                                Color(red: 0.88, green: 0.86, blue: 0.80)
                                            )
                                        Text(downloadSummary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 64)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(line).frame(height: 1)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("offline-chapters-open")
                        }

                        if let failure = model.experiencePreferencesFailure {
                            Text(failure.message)
                                .font(.footnote)
                                .foregroundStyle(Color(red: 0.76, green: 0.72, blue: 0.64))
                                .padding(.top, 18)
                                .accessibilityIdentifier("experience-settings-storage-status")
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .interactiveDismissDisabled(model.experiencePreferenceWriteIsPending)
        .accessibilityIdentifier("experience-settings-surface")
    }

    private var releaseNotificationControl: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("New historical routes")
                .font(.system(.body, design: .serif))
                .foregroundStyle(Color(red: 0.88, green: 0.86, blue: 0.80))
            Text("Receive one notification when a finished route opens in the world.")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch releaseDiscovery.notificationAuthorizationStatus {
            case .authorized?, .provisional?, .ephemeral?:
                Text("Notifications are on.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .accessibilityIdentifier("release-notifications-status")
            case .denied?:
                Text("Notifications are off in iPhone Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("release-notifications-status")
            case .notDetermined?:
                Button("Allow notifications") {
                    Task {
                        await releaseDiscovery.requestNotificationAuthorization()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("release-notifications-enable")
            case nil:
                ProgressView()
                    .tint(accent)
                    .accessibilityLabel("Checking notification settings")
            }

            if releaseDiscovery.notificationEnrollment == .unavailable {
                Text("Notifications could not be changed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("release-notifications-error")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(line).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("release-notifications-control")
    }

    private var downloadSummary: String {
        guard model.completeWorkIsOwned else { return "3 chapters included" }
        guard let presentation = model.downloadPresentation else {
            return "Checking this iPhone"
        }
        guard presentation.bootstrapState == .ready else {
            return "Checking this iPhone"
        }
        if presentation.refreshFailure != nil {
            return "Installed chapters need checking"
        }
        let pendingChapters = presentation.packageRows
            .filter {
                switch $0.state {
                case .pending, .updatePending:
                    return true
                default:
                    return false
                }
            }
            .reduce(into: 0) { $0 += $1.chapters.count }
        let protectedChapters = presentation.packageRows
            .filter {
                if case .requiresNewerApp = $0.state { return true }
                return false
            }
            .reduce(into: 0) { $0 += $1.chapters.count }
        if protectedChapters > 0, pendingChapters > 0 {
            return "\(pendingChapters) chapters available to download; \(protectedChapters) need an app update"
        }
        if protectedChapters > 0 {
            return "\(protectedChapters) chapters need an app update"
        }
        if pendingChapters == 0 { return "All 24 chapters on this iPhone" }
        return "\(pendingChapters) chapters available to download"
    }

    private func preferenceToggle(
        _ title: String,
        identifier: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(title, isOn: isOn)
            .font(.system(.body, design: .serif))
            .foregroundStyle(Color(red: 0.88, green: 0.86, blue: 0.80))
            .tint(accent)
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) {
                Rectangle().fill(line).frame(height: 1)
            }
            .contentShape(Rectangle())
            .disabled(model.experiencePreferenceEditingIsDisabled)
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier)
    }
}

private struct OfflineChaptersView: View {
    @ObservedObject var model: JourneyModel
    let focusedPackageID: PackageID?
    let showsDismissButton: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @AccessibilityFocusState private var accessibilityFocusedPackageID: PackageID?

    private let background = Color(red: 0.012, green: 0.015, blue: 0.016)
    private let surface = Color(red: 0.026, green: 0.031, blue: 0.030)
    private let line = Color.white.opacity(0.09)
    private let accent = Color(red: 0.80, green: 0.61, blue: 0.30)
    private let primaryText = Color(red: 0.92, green: 0.90, blue: 0.84)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        summary
                        queueStatus

                        if model.completeWorkIsOwned {
                            downloadAllControl
                        }

                        VStack(spacing: 12) {
                            ForEach(visibleRows) { row in
                                OfflinePackageCard(
                                    row: row,
                                    isActive: activePackageID == row.id,
                                    canDownload: model.completeWorkIsOwned
                                        && allowedCommands.contains(.requestSinglePackage(row.id)),
                                    commandIsPending: model.downloadCommandIsPending,
                                    download: {
                                        model.performDownloadCommand(.requestSinglePackage(row.id))
                                    }
                                )
                                .id(row.id)
                                .accessibilityFocused(
                                    $accessibilityFocusedPackageID,
                                    equals: row.id
                                )
                            }
                        }

                        if model.completeWorkIsOwned {
                            cellularPreference
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 42)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    guard let focusedPackageID else { return }
                    DispatchQueue.main.async {
                        if reducesMotion {
                            proxy.scrollTo(focusedPackageID, anchor: .center)
                        } else {
                            withAnimation(.easeOut(duration: 0.28)) {
                                proxy.scrollTo(focusedPackageID, anchor: .center)
                            }
                        }
                        DispatchQueue.main.asyncAfter(
                            deadline: .now() + (reducesMotion ? 0 : 0.3)
                        ) {
                            accessibilityFocusedPackageID = focusedPackageID
                        }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("offline-chapters-surface")
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center) {
            if !showsDismissButton {
                Button {
                    dismiss()
                } label: {
                    Label("Settings", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("offline-chapters-back")
            }
            Spacer()
            if showsDismissButton {
                Button("Done") {
                    model.dismissOfflineChapterRequest()
                    dismiss()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(accent)
                .frame(minWidth: 52, minHeight: 52)
                .accessibilityIdentifier("offline-chapters-close")
            }
        }

        Text("Offline chapters")
            .font(.system(size: 34, weight: .light, design: .serif))
            .foregroundStyle(primaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 9) {
            if model.completeWorkIsOwned {
                Text("Installed chapters open without a connection.")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color(red: 0.82, green: 0.81, blue: 0.76))
                if let presentation = model.downloadPresentation,
                   presentation.remainingMaximumInstalledBytes > 0 {
                    Text(
                        "Remaining chapters require up to \(Self.storageString(presentation.remainingMaximumInstalledBytes)) after installation."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("offline-chapters-storage-maximum")
                }
                if model.downloadPresentation?.protectedNewerPackages.isEmpty == false {
                    Text("Update the app to open the newer chapter files already on this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(accent)
                        .accessibilityIdentifier("offline-chapters-newer-content")
                }
            } else {
                Text("The three included chapters stay on this iPhone.")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color(red: 0.82, green: 0.81, blue: 0.76))
            }

            if let failure = model.downloadFailure {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                    Text(failure.message)
                        .font(.footnote)
                        .foregroundStyle(Color(red: 0.78, green: 0.74, blue: 0.66))
                        .accessibilityIdentifier("offline-chapters-failure")
                    Spacer(minLength: 0)
                    Button(failure == .statusUnavailable ? "Try again" : "Close") {
                        if failure == .statusUnavailable {
                            model.retryDownloadStatus()
                        } else {
                            model.dismissDownloadFailure()
                        }
                    }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(accent)
                        .disabled(model.downloadCommandIsPending)
                        .accessibilityIdentifier(
                            failure == .statusUnavailable
                                ? "offline-chapters-retry-status"
                                : "offline-chapters-dismiss-failure"
                        )
                }
                .padding(12)
                .background(surface)
                .overlay { Rectangle().stroke(line, lineWidth: 1) }
            }
        }
    }

    @ViewBuilder
    private var queueStatus: some View {
        if let presentation = model.downloadPresentation {
            switch presentation.applicationQueueState {
            case .idle, .completed:
                if allowedCommands.contains(.refreshInstalledChapters) {
                    statusPanel(
                        title: "Installed chapters could not be checked",
                        detail: "Try again before starting another download.",
                        progress: nil,
                        commands: [("Try again", .refreshInstalledChapters)]
                    )
                }
            case let .starting(packageID, completed, total):
                statusPanel(
                    title: "Preparing \(packageName(packageID))",
                    detail: "\(completed.count) of \(total) groups installed",
                    progress: nil,
                    commands: []
                )
            case let .installing(packageID, completed, total):
                statusPanel(
                    title: transferTitle(
                        defaultTitle: "Installing \(packageName(packageID))",
                        transfer: presentation.appleSystemTransferState
                    ),
                    detail: transferDetail(
                        fallback: "\(completed.count) of \(total) groups installed",
                        transfer: presentation.appleSystemTransferState
                    ),
                    progress: transferProgress(presentation.appleSystemTransferState),
                    commands: allowedCommands.contains(.requestQueuePauseAfterCurrentPackage)
                        ? [("Pause after this group", .requestQueuePauseAfterCurrentPackage)]
                        : []
                )
            case let .pausingAfterCurrent(packageID, completed, total):
                statusPanel(
                    title: "Finishing \(packageName(packageID))",
                    detail: "Downloads pause after this group. \(completed.count) of \(total) installed.",
                    progress: transferProgress(presentation.appleSystemTransferState),
                    commands: allowedCommands.contains(.resumeApplicationQueue)
                        ? [("Keep downloading", .resumeApplicationQueue)]
                        : []
                )
            case let .paused(nextPackageID, completed, total):
                statusPanel(
                    title: "Downloads paused",
                    detail: nextPackageID.map {
                        "\(packageName($0)) is next. \(completed.count) of \(total) groups installed."
                    } ?? "\(completed.count) of \(total) groups installed.",
                    progress: nil,
                    commands: allowedCommands.contains(.resumeApplicationQueue)
                        ? [("Continue downloads", .resumeApplicationQueue)]
                        : []
                )
            case let .awaitingExplicitRestore(nextPackageID, completed, total):
                statusPanel(
                    title: "Ready to continue",
                    detail: "\(packageName(nextPackageID)) is next. \(completed.count) of \(total) groups installed.",
                    progress: nil,
                    commands: allowedCommands.contains(.resumeApplicationQueue)
                        ? [("Continue downloads", .resumeApplicationQueue)]
                        : []
                )
            case let .staleJournal(reason):
                switch reason {
                case .corruptJournal:
                    statusPanel(
                        title: "The saved download queue could not be read",
                        detail: "Clear the saved queue, then choose the chapters again.",
                        progress: nil,
                        commands: [("Clear saved queue", .discardStaleQueue)]
                    )
                case .unknownOrRemovedPackageIDs, .nonCanonicalPackageOrder:
                    statusPanel(
                        title: "The saved queue belongs to an earlier chapter set",
                        detail: "Clear the old queue, then choose the chapters again.",
                        progress: nil,
                        commands: [("Clear old queue", .discardStaleQueue)]
                    )
                case .protectedNewerPackageVersions:
                    statusPanel(
                        title: "Update the app to continue",
                        detail: "This saved queue includes newer chapter files already on this iPhone.",
                        progress: nil,
                        commands: []
                    )
                case .requiresNewerApp:
                    statusPanel(
                        title: "Update the app to continue",
                        detail: "This download queue was saved by a newer version of the app.",
                        progress: nil,
                        commands: []
                    )
                }
            case let .failed(packageID, completed, failure):
                statusPanel(
                    title: "\(packageName(packageID)) could not be installed",
                    detail: installationFailureDetail(
                        failure,
                        completedPackageCount: completed.count
                    ),
                    progress: nil,
                    commands: [
                        allowedCommands.contains(.retryFailedPackage)
                            ? ("Try again", .retryFailedPackage)
                            : nil,
                        allowedCommands.contains(.removeFailedPackage)
                            ? ("Skip this group", .removeFailedPackage)
                            : nil,
                    ].compactMap { $0 }
                )
            }
        }
    }

    @ViewBuilder
    private var downloadAllControl: some View {
        if allowedCommands.contains(.requestDownloadAll) {
            Button {
                model.performDownloadCommand(.requestDownloadAll)
            } label: {
                HStack {
                    Text("Download all remaining chapters")
                    Spacer()
                    if model.downloadCommandIsPending {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "arrow.down")
                    }
                }
                .font(.system(.body, design: .serif, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 58)
                .padding(.horizontal, 18)
                .background(Color(red: 0.82, green: 0.64, blue: 0.34))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .disabled(model.downloadCommandIsPending)
            .accessibilityIdentifier("offline-chapters-download-all")
        }
    }

    private var cellularPreference: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                "Allow new downloads to start on cellular",
                isOn: Binding(
                    get: { model.experiencePreferences.cellularDownloadsEnabled },
                    set: { model.setCellularDownloadsEnabled($0) }
                )
            )
            .font(.system(.body, design: .serif))
            .foregroundStyle(Color(red: 0.88, green: 0.86, blue: 0.80))
            .tint(accent)
            .frame(minHeight: 52)
            .disabled(model.experiencePreferenceEditingIsDisabled)
            .accessibilityIdentifier("experience-setting-cellular-downloads")
            .accessibilityHint("Apple manages a transfer after it begins.")
            Text("Apple manages a transfer after it begins.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func statusPanel(
        title: String,
        detail: String,
        progress: Double?,
        commands: [(String, DownloadPresentationCommand)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(primaryText)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let progress {
                ProgressView(value: progress)
                    .tint(accent)
                    .accessibilityLabel(title)
                    .accessibilityValue("\(Int((progress * 100).rounded())) percent")
            }
            if !commands.isEmpty {
                HStack(spacing: 18) {
                    ForEach(Array(commands.enumerated()), id: \.offset) { _, item in
                        Button(item.0) { model.performDownloadCommand(item.1) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(accent)
                            .frame(minHeight: 44)
                            .disabled(model.downloadCommandIsPending)
                    }
                }
            }
        }
        .padding(16)
        .background(surface)
        .overlay { Rectangle().stroke(line, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-chapters-queue-status")
    }

    private var visibleRows: [DownloadPackagePresentationRow] {
        guard let rows = model.downloadPresentation?.packageRows else { return [] }
        if model.completeWorkIsOwned { return rows }
        return rows.filter { $0.state == .includedInApp }
    }

    private var allowedCommands: Set<DownloadPresentationCommand> {
        model.allowedDownloadCommands
    }

    private var activePackageID: PackageID? {
        guard let state = model.downloadPresentation?.applicationQueueState else { return nil }
        switch state {
        case let .starting(packageID, _, _),
             let .installing(packageID, _, _),
             let .pausingAfterCurrent(packageID, _, _):
            return packageID
        case .idle, .paused, .awaitingExplicitRestore, .staleJournal, .failed, .completed:
            return nil
        }
    }

    private func packageName(_ packageID: PackageID) -> String {
        guard let row = model.downloadPresentation?.packageRows.first(where: {
            $0.id == packageID
        }) else {
            return "chapter group"
        }
        let first = row.chapters.first?.sequence ?? 0
        let last = row.chapters.last?.sequence ?? first
        return first == last ? "Chapter \(first)" : "Chapters \(first)–\(last)"
    }

    private func installationFailureDetail(
        _ failure: PackageBatchFailure,
        completedPackageCount: Int
    ) -> String {
        if failure.isInsufficientStorage {
            return "Make more storage available, then try again. Earlier chapters were not changed."
        }
        if completedPackageCount == 1 {
            return "1 group was installed. Earlier chapters were not changed."
        }
        return "\(completedPackageCount) groups were installed. Earlier chapters were not changed."
    }

    private func transferTitle(
        defaultTitle: String,
        transfer: PackageSystemTransferState
    ) -> String {
        switch transfer {
        case let .downloading(packageID, _, _), let .began(packageID, _):
            "Transferring \(packageName(packageID))"
        case let .paused(packageID):
            "Transfer paused for \(packageName(packageID))"
        case let .finished(packageID):
            "Verifying \(packageName(packageID))"
        case let .failed(packageID, _):
            "Transfer stopped for \(packageName(packageID))"
        case .idle:
            defaultTitle
        }
    }

    private func transferDetail(
        fallback: String,
        transfer: PackageSystemTransferState
    ) -> String {
        switch transfer {
        case .paused:
            "iOS will continue the transfer when the system allows."
        case .failed:
            "The installer will keep earlier chapters unchanged."
        case .began, .downloading, .finished, .idle:
            fallback
        }
    }

    private func transferProgress(_ transfer: PackageSystemTransferState) -> Double? {
        guard case let .downloading(_, completed, total) = transfer,
              total > 0,
              completed >= 0,
              completed <= total else {
            return nil
        }
        return Double(completed) / Double(total)
    }

    private static func storageString(_ bytes: Int64) -> String {
        if bytes >= 1_000_000_000 {
            return String(
                format: "%.2f GB",
                locale: Locale(identifier: "en_US_POSIX"),
                Double(bytes) / 1_000_000_000
            )
        }
        return String(
            format: "%.0f MB",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(bytes) / 1_000_000
        )
    }
}

private struct OfflinePackageCard: View {
    let row: DownloadPackagePresentationRow
    let isActive: Bool
    let canDownload: Bool
    let commandIsPending: Bool
    let download: () -> Void

    private let accent = Color(red: 0.80, green: 0.61, blue: 0.30)

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(groupLabel.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.35)
                    .foregroundStyle(Color(red: 0.72, green: 0.62, blue: 0.43))
                Spacer()
                Label(statusLabel, systemImage: statusSymbol)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(row.chapters, id: \.id) { chapter in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chapter.period.launchEnglish.uppercased())
                            .font(.caption2.weight(.medium))
                            .tracking(1.05)
                            .foregroundStyle(.secondary)
                        Text(chapter.title.launchEnglish)
                            .font(.system(.title3, design: .serif, weight: .medium))
                            .foregroundStyle(Color(red: 0.91, green: 0.89, blue: 0.82))
                    }
                }
            }

            if canDownload {
                Button(actionLabel, action: download)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(minHeight: 44)
                    .disabled(commandIsPending)
                    .accessibilityIdentifier("offline-package-download-\(row.id)")
            }
        }
        .padding(16)
        .background(Color(red: 0.024, green: 0.029, blue: 0.028))
        .overlay {
            Rectangle().stroke(
                accent.opacity(isActive ? 0.62 : 0.14),
                lineWidth: isActive ? 1.5 : 1
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("offline-package-\(row.id)")
    }

    private var groupLabel: String {
        let sequences = row.chapters.map(\.sequence)
        guard let first = sequences.first else { return "Chapters" }
        guard let last = sequences.last, sequences.count > 1 else {
            return "Chapter \(first)"
        }
        let isContiguous = zip(sequences, sequences.dropFirst()).allSatisfy {
            $0.1 == $0.0 + 1
        }
        if isContiguous { return "Chapters \(first)–\(last)" }
        if row.state == .includedInApp {
            return "\(sequences.count) included chapters"
        }
        return "Chapters \(sequences.map(String.init).joined(separator: ", "))"
    }

    private var statusLabel: String {
        if isActive { return "In progress" }
        switch row.state {
        case .includedInApp:
            return "Included"
        case .awaitingBootstrap:
            return "Checking"
        case .installedCurrent:
            return "On this iPhone"
        case .pending:
            return "Not downloaded"
        case .updatePending:
            return "Update available"
        case .requiresNewerApp:
            return "Update app"
        }
    }

    private var statusSymbol: String {
        if isActive { return "arrow.down.circle" }
        switch row.state {
        case .includedInApp, .installedCurrent:
            return "checkmark.circle"
        case .awaitingBootstrap:
            return "clock"
        case .pending:
            return "circle"
        case .updatePending:
            return "arrow.triangle.2.circlepath"
        case .requiresNewerApp:
            return "arrow.up.circle"
        }
    }

    private var statusColor: Color {
        switch row.state {
        case .includedInApp, .installedCurrent:
            return Color(red: 0.68, green: 0.73, blue: 0.56)
        case .awaitingBootstrap, .pending:
            return isActive ? accent : .secondary
        case .updatePending, .requiresNewerApp:
            return accent
        }
    }

    private var actionLabel: String {
        if case .updatePending = row.state { return "Update" }
        return "Download"
    }
}

private struct LivingWorldField: View {
    let world: WorldGraph
    let retainedReleaseEntries: [ReleaseCatalogEntry]
    let focus: ReleaseDeepLinkIntent?
    let announcement: ReleaseAnnouncement?
    let releaseState: FutureReleasePresentationState?
    let releaseFailureMessage: String?
    let releaseActionIsPending: Bool
    let selectRetainedRelease: (ReleaseID) -> Void
    let releaseAction: () -> Void

    private struct RetainedEntryPoint: Identifiable {
        let entry: ReleaseCatalogEntry
        let node: WorldNodeState

        var id: ReleaseID { entry.id }
    }

    private var visibleNodes: [WorldNodeState] {
        world.nodes.filter { $0.visibility != .hidden }
    }

    private var activeTraces: [WorldTraceStateRecord] {
        world.traces.filter { $0.state == .active }
    }

    private var retainedEntryPoints: [RetainedEntryPoint] {
        let nodes = Dictionary(
            uniqueKeysWithValues: visibleNodes.map { ($0.id, $0) }
        )
        return retainedReleaseEntries.compactMap { entry in
            nodes[entry.placement.worldNodeID].map {
                RetainedEntryPoint(entry: entry, node: $0)
            }
        }
    }

    var body: some View {
        Canvas { context, size in
            let pointByID = Dictionary(uniqueKeysWithValues: visibleNodes.map { node in
                (
                    node.id,
                    CGPoint(
                        x: size.width * CGFloat(node.position.x),
                        y: size.height * CGFloat(node.position.y)
                    )
                )
            })

            for trace in activeTraces {
                guard let origin = pointByID[trace.origin],
                      let destination = pointByID[trace.destination] else { continue }
                var path = Path()
                path.move(to: origin)
                path.addCurve(
                    to: destination,
                    control1: CGPoint(x: origin.x, y: (origin.y + destination.y) * 0.5),
                    control2: CGPoint(x: destination.x, y: (origin.y + destination.y) * 0.5)
                )
                context.stroke(
                    path,
                    with: .color(Color(red: 0.73, green: 0.51, blue: 0.22).opacity(0.72)),
                    style: StrokeStyle(
                        lineWidth: max(1, CGFloat(trace.strength) * 2),
                        lineCap: .round
                    )
                )
            }

            if let focus,
               let basePoint = pointByID[focus.worldNodeID] {
                let point = retainedEntryPoints.first(where: {
                    $0.id == focus.releaseID
                }).map {
                    markerPoint(for: $0, size: size)
                } ?? basePoint
                let outer = CGRect(
                    x: point.x - 22,
                    y: point.y - 22,
                    width: 44,
                    height: 44
                )
                let inner = CGRect(
                    x: point.x - 14,
                    y: point.y - 14,
                    width: 28,
                    height: 28
                )
                context.stroke(
                    Path(ellipseIn: outer),
                    with: .color(
                        Color(red: 0.90, green: 0.70, blue: 0.34).opacity(0.42)
                    ),
                    lineWidth: 1
                )
                context.stroke(
                    Path(ellipseIn: inner),
                    with: .color(Color(red: 0.94, green: 0.78, blue: 0.45)),
                    lineWidth: 2
                )
            }

            for node in visibleNodes {
                guard let point = pointByID[node.id] else { continue }
                let diameter: CGFloat = node.visibility == .transformed ? 17 : 12
                let rect = CGRect(
                    x: point.x - diameter * 0.5,
                    y: point.y - diameter * 0.5,
                    width: diameter,
                    height: diameter
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color(red: 0.87, green: 0.70, blue: 0.38))
                )
                context.stroke(
                    Path(ellipseIn: rect.insetBy(dx: -6, dy: -6)),
                    with: .color(Color(red: 0.79, green: 0.58, blue: 0.27).opacity(0.28)),
                    lineWidth: 1
                )
            }
        }
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.045, blue: 0.044),
                    Color(red: 0.012, green: 0.015, blue: 0.016),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay {
            GeometryReader { proxy in
                ForEach(retainedEntryPoints) { point in
                    Button {
                        selectRetainedRelease(point.id)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.025, green: 0.030, blue: 0.029))
                            Circle()
                                .stroke(
                                    Color(red: 0.94, green: 0.78, blue: 0.45),
                                    lineWidth: focus?.releaseID == point.id ? 2.2 : 1.4
                                )
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(
                                    Color(red: 0.90, green: 0.70, blue: 0.34)
                                )
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle().inset(by: -8))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .position(markerPoint(for: point, size: proxy.size))
                    .accessibilityLabel(
                        "\(point.entry.announcement.title), \(Self.historicalYearLabel(point.entry.placement.historicalTime.astronomicalYear))"
                    )
                    .accessibilityHint("Opens this historical route in the world.")
                    .accessibilityIdentifier(
                        "release-world-entry-\(point.id.rawValue)"
                    )
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let focus, let announcement {
                VStack(alignment: .trailing, spacing: 7) {
                    Text(announcement.title)
                        .font(.system(.subheadline, design: .serif, weight: .semibold))
                        .foregroundStyle(Color(red: 0.94, green: 0.91, blue: 0.83))
                        .multilineTextAlignment(.trailing)
                    Text(Self.historicalYearLabel(focus.historicalTime.astronomicalYear))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(red: 0.90, green: 0.70, blue: 0.34))
                    if let releaseFailureMessage {
                        Text(releaseFailureMessage)
                            .font(.caption2)
                            .foregroundStyle(
                                Color(red: 0.86, green: 0.82, blue: 0.73)
                            )
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier(
                                "release-world-failure"
                            )
                    }
                    releaseControl
                }
                .frame(maxWidth: 250, alignment: .trailing)
                .padding(.leading, 46)
                .padding(.trailing, 14)
                .padding(.vertical, 10)
                .background {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.84)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("release-world-focus")
            }
        }
        .accessibilityElement()
        .accessibilityIdentifier("living-world-field")
        .accessibilityLabel(
            "The historical world. \(visibleNodes.count) places revealed and \(activeTraces.count) roads active."
        )
        .accessibilityValue(
            focus.map {
                "Focused at \(Self.historicalYearLabel($0.historicalTime.astronomicalYear))."
            } ?? ""
        )
    }

    @ViewBuilder
    private var releaseControl: some View {
        switch releaseState {
        case .availableToDownload?, .failed?:
            Button(action: releaseAction) {
                Label(
                    releaseState == .failed ? "Try again" : "Download",
                    systemImage: releaseState == .failed
                        ? "arrow.clockwise" : "arrow.down"
                )
                .frame(minWidth: 94, minHeight: 44)
            }
            .font(.system(.caption, design: .serif, weight: .semibold))
            .foregroundStyle(.black)
            .background(
                Color(red: 0.82, green: 0.64, blue: 0.34),
                in: RoundedRectangle(cornerRadius: 3, style: .continuous)
            )
            .buttonStyle(.plain)
            .disabled(releaseActionIsPending)
            .accessibilityIdentifier("release-world-action")
        case .awaitingResume?:
            Button(action: releaseAction) {
                Label("Continue", systemImage: "arrow.down")
                    .frame(minWidth: 94, minHeight: 44)
            }
            .font(.system(.caption, design: .serif, weight: .semibold))
            .foregroundStyle(.black)
            .background(
                Color(red: 0.82, green: 0.64, blue: 0.34),
                in: RoundedRectangle(cornerRadius: 3, style: .continuous)
            )
            .buttonStyle(.plain)
            .disabled(releaseActionIsPending)
            .accessibilityIdentifier("release-world-action")
        case .preparing?:
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color(red: 0.90, green: 0.70, blue: 0.34))
                Text("Preparing")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color(red: 0.90, green: 0.70, blue: 0.34))
            .frame(minHeight: 36)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preparing historical route")
            .accessibilityIdentifier("release-world-preparing")
        case .ready?:
            Button(action: releaseAction) {
                Label("Begin", systemImage: "arrow.right")
                    .frame(minWidth: 94, minHeight: 44)
            }
                .font(.system(.caption, design: .serif, weight: .semibold))
                .foregroundStyle(.black)
                .background(
                    Color(red: 0.82, green: 0.64, blue: 0.34),
                    in: RoundedRectangle(cornerRadius: 3, style: .continuous)
                )
                .buttonStyle(.plain)
                .disabled(releaseActionIsPending)
                .accessibilityIdentifier("release-world-action")
        case .unavailable?, nil:
            EmptyView()
        }
    }

    private static func historicalYearLabel(_ astronomicalYear: Int) -> String {
        if astronomicalYear > 0 { return "AD \(astronomicalYear)" }
        return "\(1 - astronomicalYear) BC"
    }

    private func markerPoint(
        for point: RetainedEntryPoint,
        size: CGSize
    ) -> CGPoint {
        let siblings = retainedEntryPoints.filter {
            $0.node.id == point.node.id
        }.sorted {
            if $0.entry.placement.historicalTime
                != $1.entry.placement.historicalTime {
                return $0.entry.placement.historicalTime
                    < $1.entry.placement.historicalTime
            }
            return $0.id < $1.id
        }
        let base = CGPoint(
            x: size.width * CGFloat(point.node.position.x),
            y: size.height * CGFloat(point.node.position.y)
        )
        guard siblings.count > 1,
              let index = siblings.firstIndex(where: { $0.id == point.id }) else {
            return base
        }
        let angle = (-Double.pi / 2)
            + (2 * Double.pi * Double(index) / Double(siblings.count))
        let radius = 24.0
        return CGPoint(
            x: min(max(22, base.x + CGFloat(cos(angle) * radius)), size.width - 22),
            y: min(max(22, base.y + CGFloat(sin(angle) * radius)), size.height - 22)
        )
    }
}

private struct ChapterRoad: View {
    let chapters: [ChapterIndexEntry]
    let completedChapterIDs: Set<ChapterID>
    let activeChapterID: ChapterID?
    let access: (ChapterID) -> ChapterAccess
    let select: (ChapterID) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let rowHeight: CGFloat = 112

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(chapters, id: \.id) { chapter in
                    roadNode(chapter)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(chapter.id)
                }
            }
            .padding(.horizontal, 18)
            .background(alignment: .leading) {
                Rectangle()
                    .fill(Color(red: 0.60, green: 0.43, blue: 0.22).opacity(0.48))
                    .frame(width: 2)
                    .padding(.leading, 39)
                    .accessibilityHidden(true)
            }
        } else {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        guard !chapters.isEmpty else { return }
                        var road = Path()
                        for index in chapters.indices {
                            let point = roadPoint(index: index, size: size)
                            if index == chapters.startIndex {
                                road.move(to: point)
                            } else {
                                let previous = roadPoint(index: index - 1, size: size)
                                road.addCurve(
                                    to: point,
                                    control1: CGPoint(
                                        x: previous.x,
                                        y: (previous.y + point.y) * 0.5
                                    ),
                                    control2: CGPoint(
                                        x: point.x,
                                        y: (previous.y + point.y) * 0.5
                                    )
                                )
                            }
                        }
                        context.stroke(
                            road,
                            with: .linearGradient(
                                Gradient(colors: [
                                    Color(red: 0.30, green: 0.22, blue: 0.12).opacity(0.62),
                                    Color(red: 0.68, green: 0.48, blue: 0.23).opacity(0.46),
                                    Color(red: 0.28, green: 0.21, blue: 0.13).opacity(0.52),
                                ]),
                                startPoint: CGPoint(x: 0, y: 0),
                                endPoint: CGPoint(x: size.width, y: size.height)
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                    }
                    .accessibilityHidden(true)

                    ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                        let nodeWidth = min(geometry.size.width - 36, 290)
                        roadNode(chapter)
                            .frame(width: nodeWidth, alignment: .leading)
                            .position(
                                x: min(
                                    max(
                                        nodeWidth * 0.5 + 18,
                                        geometry.size.width * horizontalFraction(index)
                                    ),
                                    geometry.size.width - nodeWidth * 0.5 - 18
                                ),
                                y: rowHeight * CGFloat(index) + rowHeight * 0.5
                            )
                            .id(chapter.id)
                    }
                }
            }
            .frame(height: rowHeight * CGFloat(chapters.count))
        }
    }

    private func roadNode(_ chapter: ChapterIndexEntry) -> some View {
        ChapterRoadNode(
            chapter: chapter,
            access: access(chapter.id),
            isCompleted: completedChapterIDs.contains(chapter.id),
            isCurrent: activeChapterID == chapter.id
        ) {
            select(chapter.id)
        }
    }

    private func roadPoint(index: Int, size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * horizontalFraction(index),
            y: rowHeight * CGFloat(index) + rowHeight * 0.5
        )
    }

    private func horizontalFraction(_ index: Int) -> CGFloat {
        let positions: [CGFloat] = [0.24, 0.48, 0.72, 0.59, 0.30, 0.43, 0.69, 0.78]
        return positions[index % positions.count]
    }
}

private struct ChapterRoadNode: View {
    let chapter: ChapterIndexEntry
    let access: ChapterAccess
    let isCompleted: Bool
    let isCurrent: Bool
    let action: () -> Void

    private var isLocked: Bool {
        if case .locked = access { return true }
        return false
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(
                        Color(red: 0.80, green: 0.61, blue: 0.30)
                            .opacity(isCurrent ? 0.32 : 0.15)
                    )
                    Circle().stroke(
                        Color(red: 0.80, green: 0.61, blue: 0.30)
                            .opacity(isLocked ? 0.48 : 1),
                        lineWidth: isCurrent ? 2 : 1
                    )
                        .padding(5)
                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                    } else if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.period.launchEnglish.uppercased())
                        .font(.caption2.weight(.medium))
                        .tracking(1.2)
                        .foregroundStyle(Color(red: 0.72, green: 0.62, blue: 0.43))
                    Text(chapter.title.launchEnglish)
                        .font(.system(.title3, design: .serif, weight: .medium))
                        .foregroundStyle(Color(red: 0.91, green: 0.89, blue: 0.82))
                        .opacity(isLocked ? 0.72 : 1)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chapter-road-\(chapter.id)")
        .accessibilityLabel(
            "\(chapter.title.launchEnglish), \(chapter.period.launchEnglish)" +
                (isLocked ? ", locked" : isCompleted ? ", completed" : "")
        )
        .accessibilityHint(isLocked ? "Opens the permanent unlock." : "Opens this road.")
    }
}

private struct LockedRoadPurchaseView: View {
    let lockedRoad: LockedRoad
    @ObservedObject var model: JourneyModel
    @AccessibilityFocusState private var headingIsFocused: Bool

    private var operationIsRunning: Bool {
        model.purchaseState == .purchasing || model.purchaseState == .restoring
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer()
                    Button("Close") { model.dismissLockedRoad() }
                        .foregroundStyle(.secondary)
                        .disabled(operationIsRunning)
                }

                        Spacer(minLength: 40)

                Text(lockedRoad.chapter.period.launchEnglish.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(Color(red: 0.72, green: 0.62, blue: 0.43))
                Text(lockedRoad.chapter.title.launchEnglish)
                    .font(.system(.largeTitle, design: .serif, weight: .light))
                    .foregroundStyle(Color(red: 0.91, green: 0.89, blue: 0.82))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingIsFocused)

                Rectangle()
                    .fill(Color(red: 0.72, green: 0.52, blue: 0.22))
                    .frame(width: 54, height: 1)

                if model.completeWorkPurchaseIsAvailable
                    || model.completeWorkRestoreIsAvailable {
                    Text("Unlock all 24 chapters permanently.")
                        .font(.system(.title3, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)

                    if case let .failed(message) = model.purchaseState {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isStaticText)
                    } else if model.purchaseState == .pending {
                        Text("The purchase is waiting for approval.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if model.completeWorkPurchaseIsAvailable {
                        Button {
                            model.purchaseCompleteWork()
                        } label: {
                            HStack {
                                if model.purchaseState == .purchasing {
                                    ProgressView().tint(.black)
                                }
                                Text(
                                    model.storeDisplayPrice.map { "Unlock for \($0)" }
                                        ?? "Unlock the complete work"
                                )
                                    .frame(maxWidth: .infinity)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.82, green: 0.64, blue: 0.34))
                        .foregroundStyle(.black)
                        .controlSize(.large)
                        .disabled(operationIsRunning || model.purchaseState == .pending)
                        .accessibilityIdentifier("locked-road-unlock")
                    }

                    if model.completeWorkRestoreIsAvailable {
                        Button {
                            model.restoreCompleteWork()
                        } label: {
                            HStack {
                                if model.purchaseState == .restoring {
                                    ProgressView()
                                }
                                Text("Restore purchase")
                            }
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color(red: 0.80, green: 0.61, blue: 0.30))
                        .frame(minHeight: 44)
                        .disabled(operationIsRunning)
                        .accessibilityIdentifier("locked-road-restore")
                    }
                } else {
                    Text("The complete work is unavailable.")
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("locked-road-unavailable")
                }

                        Spacer(minLength: 40)
                    }
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .padding(28)
                }
            }
        }
        .accessibilityIdentifier("locked-road-purchase")
        .onAppear { headingIsFocused = true }
    }
}

private struct ChapterRouteView: View {
    let chapterID: ChapterID
    @ObservedObject var model: JourneyModel
    @StateObject private var session = ProductionChapterRouteSession()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = SceneViewportCanvasMetrics.fullCanvasSize(
                contentSize: SceneFrameSize(
                    width: geometry.size.width,
                    height: geometry.size.height
                ),
                safeAreaTop: geometry.safeAreaInsets.top,
                safeAreaLeading: geometry.safeAreaInsets.leading,
                safeAreaBottom: geometry.safeAreaInsets.bottom,
                safeAreaTrailing: geometry.safeAreaInsets.trailing
            )
            if let cursor = model.chapterCursor,
               cursor.chapter.id == chapterID,
               let viewportCropID = try? SceneViewportCropSelector.selectCropID(
                   scene: cursor.scene,
                   viewport: canvasSize,
                   reduceMotion: reduceMotion
               ) {
                if let identity = model.chapterRuntimeRouteIdentity(
                    for: chapterID,
                    viewportCropID: viewportCropID,
                    reduceMotion: reduceMotion
                ) {
                    ProductionChapterView(
                        model: model,
                        session: session,
                        identity: identity
                    )
                    .task(id: identity) {
                        await session.activate(model: model, identity: identity)
                    }
                } else {
#if DEBUG
                    if chapterID == DevelopmentFirstFarmersRepository.chapterID {
                        DevelopmentChapterDiagnosticView(model: model, cursor: cursor)
                    } else {
                        ChapterUnavailableRouteView(chapterID: chapterID, model: model)
                    }
#else
                    ChapterUnavailableRouteView(chapterID: chapterID, model: model)
#endif
                }
            } else {
                ChapterUnavailableRouteView(chapterID: chapterID, model: model)
            }
        }
        .onDisappear { session.deactivate() }
    }
}

#if DEBUG
/// Debug-only diagnostic for the generated First Farmers fixture. It keeps
/// UI and restoration tests on real decoded chapter/beat data while verified
/// package roots and production assets are absent. This type and its route
/// branch do not exist in Release builds.
private struct DevelopmentChapterDiagnosticView: View {
    @ObservedObject var model: JourneyModel
    let cursor: ChapterCursor

    private var canAdvance: Bool {
        cursor.beat.interaction == nil
            || model.state.activeChapter?.interaction?.phase == .complete
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.012, green: 0.015, blue: 0.016).ignoresSafeArea()
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.18, green: 0.15, blue: 0.10),
                            Color(red: 0.025, green: 0.028, blue: 0.026),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel(cursor.accessibility.sceneSummary.launchEnglish)
                .accessibilityIdentifier("development-scene-\(cursor.scene.id)")

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Return to the road") { model.showWorld() }
                        .foregroundStyle(Color(red: 0.80, green: 0.61, blue: 0.30))
                    Text(cursor.chapter.title.launchEnglish)
                        .font(.system(.title3, design: .serif, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(cursor.beat.narrative.heading.launchEnglish)
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.87))
                    ForEach(cursor.beat.narrative.paragraphs) { paragraph in
                        Text(paragraph.launchEnglish)
                            .font(.system(size: 17, design: .serif))
                            .foregroundStyle(Color(red: 0.84, green: 0.83, blue: 0.79))
                    }
                    if let interaction = cursor.beat.interaction,
                       model.state.activeChapter?.interaction?.phase != .complete {
                        Text(
                            cursor.beat.narrative.actionPrompt?.launchEnglish
                                ?? interaction.prompt.launchEnglish
                        )
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(Color(red: 0.90, green: 0.73, blue: 0.43))
                    }
                    if canAdvance {
                        Button("Continue") { model.advanceCurrentBeat() }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.82, green: 0.64, blue: 0.34))
                            .foregroundStyle(.black)
                            .disabled(model.chapterTransitionIsPending)
                            .accessibilityIdentifier("development-continue")
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.72))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("development-beat-\(cursor.beat.id)")
            }
            .frame(maxHeight: 520, alignment: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("development-chapter-\(cursor.chapter.id)")
    }
}
#endif

private struct ChapterUnavailableRouteView: View {
    let chapterID: ChapterID
    @ObservedObject var model: JourneyModel

    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.015, blue: 0.016).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Button("Return to the road") { model.showWorld() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(red: 0.80, green: 0.61, blue: 0.30))
                Spacer()
                Text("Chapter content is not installed.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(28)
        }
        .accessibilityIdentifier("chapter-unavailable-\(chapterID)")
    }
}
