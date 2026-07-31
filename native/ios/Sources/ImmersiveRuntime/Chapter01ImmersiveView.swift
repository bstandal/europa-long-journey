import RealityKit
import SwiftUI

/// The portrait-only Chapter 01 route. The historical world owns the screen;
/// SwiftUI is limited to captions, adaptive help and a deliberately opened
/// compact control surface.
@MainActor
public struct Chapter01ImmersiveView: View {
    @StateObject private var controller: Chapter01ExperienceController
    @State private var world: Chapter01RealityWorld
    @State private var sensoryBridge: Chapter01SensoryBridge
    @State private var controlsArePresented = false
    @State private var captionIsVisible = false
    @State private var captionsAreEnabled = true
    @State private var soundIsEnabled = true
    @State private var directManipulationBegan = false
    @State private var primaryGestureIsActive = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let onLeave: @MainActor () -> Void

    public init(
        storageURL: URL? = nil,
        runtimePackageContext: Chapter01RuntimePackageContext? = nil,
        assetRepository: Chapter01RealityAssetRepository? = nil,
        sensoryCatalog: Chapter01AuthoredSampleCatalog? = nil,
        sensoryResolver: Chapter01OfflineSampleResolver? = nil,
        onLeave: @escaping @MainActor () -> Void = {}
    ) {
        _controller = StateObject(
            wrappedValue: Chapter01ExperienceController(storageURL: storageURL)
        )
        _world = State(
            initialValue: Chapter01RealityWorld(
                runtimePackageContext: runtimePackageContext,
                assetRepository: assetRepository
            )
        )
        _sensoryBridge = State(initialValue: Chapter01SensoryBridge(
            catalog: sensoryCatalog,
            resolver: sensoryResolver
        ))
        self.onLeave = onLeave
    }

    public var body: some View {
        ZStack {
            Color(red: 0.008, green: 0.011, blue: 0.011)
                .ignoresSafeArea()

            TimelineView(.animation(minimumInterval: 1 / 30, paused: controlsArePresented)) { timeline in
                RealityView { content in
                    content.camera = .virtual
                    await world.prepare(initialCell: controller.currentCell)
                    content.add(world.root)
                    content.cameraTarget = world.camera
                    content.audioListener = world.camera
                } update: { content in
                    world.update(
                        from: controller,
                        reduceMotion: reduceMotion,
                        elapsedTime: timeline.date.timeIntervalSinceReferenceDate
                    )
                    content.cameraTarget = world.camera
                }
                .realityViewCameraControls(.none)
            }
            .ignoresSafeArea()
            .gesture(primaryManipulationGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(controller.currentSequence.accessibilityLabel)
            .accessibilityValue(accessibilityProgress)
            .accessibilityAction(named: Text(controller.currentSequence.shortAction)) {
                controller.semanticStep()
            }
            .accessibilityIdentifier("chapter01-immersive-world")

            readabilityFrame
                .allowsHitTesting(false)

            if let cue = controller.actionCue {
                adaptiveCue(cue)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96)))
            }

            if captionsAreEnabled,
               captionIsVisible,
               let caption = visibleCaption {
                captionView(caption)
                    .transition(reduceMotion ? .identity : .opacity)
            }

            controlsButton

            if controlsArePresented {
                compactControls
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .preferredColorScheme(.dark)
        .chapter01SystemChromeHidden()
        .onAppear {
            sensoryBridge.authoredSamplesAreEnabled = soundIsEnabled
            sensoryBridge.resumeAfterSuspension()
            controller.start()
            synchronizeSensoryProgram()
        }
        .onDisappear {
            controller.stop()
            sensoryBridge.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !controlsArePresented {
                sensoryBridge.resumeAfterSuspension()
                controller.start()
                synchronizeSensoryProgram()
            } else {
                controller.stop()
                sensoryBridge.quiesceForSuspension()
            }
        }
        .onChange(of: controller.sensoryEventGeneration) { _, generation in
            sensoryBridge.consume(
                event: controller.sensoryEvent,
                generation: generation,
                sequence: controller.currentSequence
            )
        }
        .onChange(of: controller.currentBeat.id, initial: true) { _, _ in
            presentCurrentCaption()
            synchronizeSensoryProgram()
        }
    }

    private var primaryManipulationGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .targetedToAnyEntity()
            .onChanged { value in
                if !primaryGestureIsActive {
                    primaryGestureIsActive = true
                    synchronizeSensoryProgram()
                }
                let distance = hypot(
                    value.gestureValue.translation.width,
                    value.gestureValue.translation.height
                )
                let strength = min(max(distance / 88, 0.18), 1)
                if controller.currentSequence != .harvestHadToLast,
                   distance >= 6 {
                    if directManipulationBegan {
                        controller.updateContinuousManipulation(
                            strength: strength
                        )
                    } else {
                        directManipulationBegan = true
                        controller.beginContinuousManipulation(
                            entityName: value.entity.name,
                            strength: strength
                        )
                    }
                } else {
                    controller.updateTransientManipulation(strength)
                }
            }
            .onEnded { value in
                primaryGestureIsActive = false
                let translation = value.gestureValue.translation
                let distance = hypot(translation.width, translation.height)
                let wasContinuous = directManipulationBegan
                directManipulationBegan = false
                controller.endContinuousManipulation()
                if controller.currentSequence == .harvestHadToLast,
                   distance >= 8 {
                    controller.transferGrain(
                        to: grainDestination(for: translation)
                    )
                } else if distance < 8 {
                    controller.activateEntity(named: value.entity.name)
                } else if !wasContinuous {
                    controller.commitPrimaryManipulation(
                        strength: min(max(distance / 88, 0.2), 1)
                    )
                }
                synchronizeSensoryProgram()
            }
    }

    private var visibleCaption: String? {
        // The approved eight-line source is 75 words. Omitting the redundant
        // five-word expansion line keeps the shipped visible total at 70.
        guard controller.currentBeat.id != "settlement-grows" else { return nil }
        return controller.currentBeat.caption
    }

    private var accessibilityProgress: String {
        let percent = Int((controller.normalizedExperienceProgress * 100).rounded())
        return controller.chapterIsComplete ? "Complete" : "\(percent) percent complete"
    }

    private func grainDestination(
        for translation: CGSize
    ) -> String {
        if translation.height < -abs(translation.width) * 0.72 {
            return "reserve"
        }
        return translation.width < 0 ? "food" : "seed"
    }

    private var readabilityFrame: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.34), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 118)
            Spacer()
            LinearGradient(
                colors: [.clear, .black.opacity(contrast == .increased ? 0.88 : 0.68)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 210)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func adaptiveCue(_ cue: String) -> some View {
        VStack {
            Spacer()
            Group {
                if controller.semanticStepIsAvailable {
                    Button(cue) { controller.semanticStep() }
                        .buttonStyle(.plain)
                } else {
                    Text(cue)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(.callout, design: .rounded, weight: .semibold))
            .foregroundStyle(Color(red: 0.94, green: 0.73, blue: 0.36))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(.black.opacity(contrast == .increased ? 0.92 : 0.72), in: Capsule())
            .overlay {
                Capsule().stroke(Color.white.opacity(contrast == .increased ? 0.55 : 0.14))
            }
            .padding(.bottom, visibleCaption == nil ? 46 : 118)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: controller.actionCue)
    }

    private func captionView(_ caption: String) -> some View {
        VStack {
            Spacer()
            Text(caption)
                .font(.system(.title3, design: .serif, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
                .lineLimit(2)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.56 : 0.72)
                .frame(maxWidth: 390, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 38)
                .shadow(color: .black, radius: 5, y: 2)
                .accessibilityIdentifier("chapter01-caption")
        }
        .allowsHitTesting(false)
    }

    private var controlsButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    setControlsPresented(!controlsArePresented)
                } label: {
                    Image(systemName: controlsArePresented ? "xmark" : "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(controlsArePresented ? 0.95 : 0.70))
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(controlsArePresented ? 0.72 : 0.34), in: Circle())
                }
                .accessibilityLabel(controlsArePresented ? "Close controls" : "Pause and sound")
                .accessibilityIdentifier("chapter01-compact-controls")
            }
            Spacer()
        }
        .padding(.top, 4)
        .padding(.trailing, 12)
    }

    private var compactControls: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()
                .onTapGesture { setControlsPresented(false) }
            VStack(spacing: 8) {
                controlRow(
                    title: soundIsEnabled ? "Sound on" : "Sound off",
                    systemImage: soundIsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill"
                ) {
                    soundIsEnabled.toggle()
                    sensoryBridge.authoredSamplesAreEnabled = soundIsEnabled
                    synchronizeSensoryProgram()
                }
                controlRow(
                    title: captionsAreEnabled ? "Captions on" : "Captions off",
                    systemImage: "captions.bubble.fill"
                ) {
                    captionsAreEnabled.toggle()
                    if captionsAreEnabled { presentCurrentCaption() }
                }
                controlRow(title: "Leave chapter", systemImage: "map.fill") {
                    controller.stop()
                    onLeave()
                }
            }
            .padding(12)
            .frame(maxWidth: 262)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(contrast == .increased ? 0.44 : 0.12))
            }
            .accessibilityIdentifier("chapter01-controls-surface")
        }
    }

    private func controlRow(
        title: String,
        systemImage: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.body, design: .rounded, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                .padding(.horizontal, 14)
                .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func setControlsPresented(_ presented: Bool) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            controlsArePresented = presented
        }
        if presented {
            controller.stop()
            sensoryBridge.quiesceForSuspension()
        } else {
            sensoryBridge.resumeAfterSuspension()
            controller.start()
            synchronizeSensoryProgram()
        }
    }

    private func synchronizeSensoryProgram() {
        sensoryBridge.synchronizeExperience(
            cell: controller.currentCell,
            beatID: controller.currentBeat.id,
            narrationSampleCursor: controller.state.narrationSampleCursor,
            preciseInputIsActive: primaryGestureIsActive
        ) { beatID, sampleFrame in
            controller.updateNarrationSampleCursor(
                sampleFrame,
                forBeatID: beatID
            )
        }
    }

    private func presentCurrentCaption() {
        captionIsVisible = visibleCaption != nil
        guard captionIsVisible else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5.5))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                captionIsVisible = false
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func chapter01SystemChromeHidden() -> some View {
#if os(iOS)
        statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
#else
        self
#endif
    }
}
