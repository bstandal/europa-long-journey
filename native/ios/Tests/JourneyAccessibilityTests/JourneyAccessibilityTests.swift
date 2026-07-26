import ContentKit
import ContentKitTestSupport
import JourneyAccessibility
import JourneyDomain
import XCTest

final class JourneyAccessibilityTests: XCTestCase {
    func testAuthoredTraceActionDrivesTheSameReducerAndReturnsTheSameEffect() throws {
        let spec = trace()
        let accessibility = accessibility(for: spec)
        var state = InteractionRuntimeState(spec: spec)
        let model = try SemanticInteractionAdapter.model(
            for: spec,
            accessibility: accessibility,
            state: state
        )
        XCTAssertEqual(model.label, accessibility.sceneSummary.launchEnglish)
        XCTAssertEqual(model.controls.first?.id, "route-control")
        XCTAssertEqual(model.controls.first?.label, "Carry the household west")

        let binding = try XCTUnwrap(model.controls.first?.actions.first)
        _ = try SemanticInteractionAdapter.reduce(
            state: &state,
            elementID: "route-control",
            authoredAction: binding,
            spec: spec,
            accessibility: accessibility
        )
        let result = try SemanticInteractionAdapter.reduce(
            state: &state,
            elementID: "route-control",
            authoredAction: binding,
            spec: spec,
            accessibility: accessibility
        )
        XCTAssertEqual(state.phase, .complete)
        XCTAssertEqual(result.completedEffects, spec.completionEffects)
    }

    func testEveryGrammarCompletesItsAuthoredVoiceOverPathWithExactConsequenceParity() throws {
        for spec in [trace(), allocate(), assemble(), pressure(), transform()] {
            let result = try SemanticInteractionAdapter.verifyParity(
                spec: spec,
                accessibility: accessibility(for: spec)
            )
            XCTAssertEqual(result.standardEffects, spec.completionEffects)
            XCTAssertEqual(result.voiceOverEffects, spec.completionEffects)
        }
    }

    func testModelKeepsBlockedAuthoredAssemblyActionOperableThroughReducerResistance() throws {
        let spec = assemble()
        let accessibility = accessibility(for: spec)
        var state = InteractionRuntimeState(spec: spec)
        var model = try SemanticInteractionAdapter.model(
            for: spec,
            accessibility: accessibility,
            state: state
        )
        XCTAssertEqual(
            model.controls.filter { $0.kind == .action }.map(\.id),
            ["place-posts", "place-roof"]
        )
        XCTAssertEqual(
            model.controls.first(where: { $0.id == "place-roof" })?.value,
            "Waiting"
        )

        let blockedRoof = try XCTUnwrap(
            model.controls.first(where: { $0.id == "place-roof" })?
                .actions.first
        )
        let blockedReduction = try SemanticInteractionAdapter.reduce(
            state: &state,
            elementID: "place-roof",
            authoredAction: blockedRoof,
            spec: spec,
            accessibility: accessibility
        )
        XCTAssertEqual(blockedReduction.feedback, .resistance)
        guard case let .assemble(blockedProgress) = state.progress else {
            return XCTFail("The blocked action changed grammar")
        }
        XCTAssertTrue(blockedProgress.placements.isEmpty)

        let binding = try XCTUnwrap(model.controls.first(where: { $0.id == "place-posts" })?.actions.first)
        _ = try SemanticInteractionAdapter.reduce(
            state: &state,
            elementID: "place-posts",
            authoredAction: binding,
            spec: spec,
            accessibility: accessibility
        )
        model = try SemanticInteractionAdapter.model(
            for: spec,
            accessibility: accessibility,
            state: state
        )
        XCTAssertEqual(model.controls.filter { $0.kind == .action }.map(\.id), ["place-roof"])
    }

    func testRejectsUnauthoredAndUnboundSemanticActions() throws {
        let spec = trace()
        let accessibility = accessibility(for: spec)
        var state = InteractionRuntimeState(spec: spec)
        let invented = AccessibilityActionSpec(
            kind: .increment,
            label: "Invent another route",
            token: .advanceTransform(stageID: "invented-stage", step: 0.1)
        )
        XCTAssertThrowsError(
            try SemanticInteractionAdapter.reduce(
                state: &state,
                elementID: "route-control",
                authoredAction: invented,
                spec: spec,
                accessibility: accessibility
            )
        ) { error in
            XCTAssertEqual(error as? SemanticInteractionError, .unauthoredAction("route-control"))
        }

        let unbound = AccessibilitySpec(
            id: spec.accessibilityID,
            sceneSummary: "A route crosses the water.",
            elements: [
                AccessibilityElementSpec(
                    id: "wrong-control",
                    role: .adjustable,
                    label: "Wrong mechanism",
                    actions: [
                        AccessibilityActionSpec(
                            kind: .increment,
                            label: "Advance a transformation",
                            token: .advanceTransform(stageID: "wrong-stage", step: 0.1)
                        ),
                    ]
                ),
            ]
        )
        XCTAssertThrowsError(try unbound.validateBinding(to: spec))
    }

    func testRejectsPressureControlsWhoseDiscretePathCannotReachTheAuthoredRange() throws {
        let spec = pressure(stableRange: 0.45 ... 0.45)
        let inaccessible = accessibility(for: spec, pressureStep: 0.2)
        XCTAssertThrowsError(
            try SemanticInteractionAdapter.verifyParity(spec: spec, accessibility: inaccessible)
        ) { error in
            XCTAssertEqual(
                error as? SemanticInteractionError,
                .inaccessibleCompletion("pressure-discrete-range")
            )
        }
    }

    private func base(id: String, grammar: InteractionSpec.Grammar) -> InteractionSpec {
        InteractionSpec(
            id: InteractionID(id),
            prompt: "Act on the historical mechanism",
            grammar: grammar,
            completionEffects: [consequence(id: id)],
            accessibilityID: AccessibilityID("access-\(id)")
        )
    }

    private func trace() -> InteractionSpec {
        base(
            id: "trace",
            grammar: .trace(
                TraceInteractionSpec(
                    anchors: [NormalizedPoint(x: 0, y: 0), NormalizedPoint(x: 1, y: 1)],
                    tolerance: 0.1
                )
            )
        )
    }

    private func allocate() -> InteractionSpec {
        base(
            id: "allocate",
            grammar: .allocate(
                AllocateInteractionSpec(
                    resourceName: "stores",
                    totalUnits: 4,
                    destinations: [
                        AllocationDestination(id: "seed", minimumUnits: 1),
                        AllocationDestination(id: "winter", minimumUnits: 1),
                    ]
                )
            )
        )
    }

    private func assemble() -> InteractionSpec {
        base(
            id: "assemble",
            grammar: .assemble(
                AssembleInteractionSpec(
                    components: [
                        AssemblyComponent(id: "posts", targetSlot: "frame"),
                        AssemblyComponent(id: "roof", targetSlot: "shelter", prerequisites: ["posts"]),
                    ]
                )
            )
        )
    }

    private func pressure(stableRange: ClosedRange<Double> = 0.4 ... 0.6) -> InteractionSpec {
        base(
            id: "pressure",
            grammar: .pressure(
                PressureInteractionSpec(
                    forces: [
                        PressureForce(
                            id: "line",
                            direction: 1,
                            initialMagnitude: 0,
                            userControllable: true
                        ),
                    ],
                    stableRange: stableRange,
                    requiredHoldMillis: 1_200
                )
            )
        )
    }

    private func transform() -> InteractionSpec {
        base(
            id: "transform",
            grammar: .transform(
                TransformInteractionSpec(
                    stages: [
                        TransformationStage(id: "clear", controlID: "field", requiredAmount: 0.6),
                        TransformationStage(id: "sow", controlID: "seed", requiredAmount: 1),
                    ]
                )
            )
        )
    }

    private func accessibility(
        for spec: InteractionSpec,
        pressureStep: Double = 0.1
    ) -> AccessibilitySpec {
        let elements: [AccessibilityElementSpec]
        switch spec.grammar {
        case .trace:
            elements = [
                adjustable(
                    id: "route-control",
                    label: "Carry the household west",
                    actions: [
                        action(.increment, "Advance along the crossing", .traceNext),
                    ]
                ),
            ]
        case let .allocate(configuration):
            elements = configuration.destinations.map { destination in
                adjustable(
                    id: "allocate-\(destination.id)",
                    label: "Stores for \(destination.id)",
                    actions: [
                        action(
                            .increment,
                            "Increase \(destination.id)",
                            .allocate(destinationID: destination.id, unitsPerStep: 1)
                        ),
                        action(
                            .decrement,
                            "Decrease \(destination.id)",
                            .allocate(destinationID: destination.id, unitsPerStep: 1)
                        ),
                    ]
                )
            } + [
                button(
                    id: "commit-stores",
                    label: "Test the stores against winter",
                    token: .commitAllocation
                ),
            ]
        case let .assemble(configuration):
            elements = configuration.components.map { component in
                button(
                    id: "place-\(component.id)",
                    label: "Set \(component.id) into \(component.targetSlot)",
                    token: .placeComponent(componentID: component.id)
                )
            }
        case let .pressure(configuration):
            elements = configuration.forces.filter(\.userControllable).map { force in
                adjustable(
                    id: "pressure-\(force.id)",
                    label: "Set \(force.id)",
                    actions: [
                        action(
                            .increment,
                            "Increase \(force.id)",
                            .adjustPressure(forceID: force.id, step: pressureStep)
                        ),
                        action(
                            .decrement,
                            "Decrease \(force.id)",
                            .adjustPressure(forceID: force.id, step: pressureStep)
                        ),
                    ]
                )
            } + [
                button(id: "hold-line", label: "Hold the line", token: .holdPressure),
            ]
        case let .transform(configuration):
            elements = configuration.stages.map { stage in
                adjustable(
                    id: "transform-\(stage.id)",
                    label: "Advance \(stage.id)",
                    actions: [
                        action(
                            .increment,
                            "Continue \(stage.id)",
                            .advanceTransform(stageID: stage.id, step: 0.25)
                        ),
                    ]
                )
            }
        }
        return AccessibilitySpec(
            id: spec.accessibilityID,
            sceneSummary: "The historical mechanism waits for the next deliberate action.",
            elements: elements
        )
    }

    private func adjustable(
        id: String,
        label: String,
        actions: [AccessibilityActionSpec]
    ) -> AccessibilityElementSpec {
        AccessibilityElementSpec(
            id: id,
            role: .adjustable,
            label: label,
            hint: "Adjust the mechanism.",
            actions: actions
        )
    }

    private func button(
        id: String,
        label: String,
        token: AccessibilityActionToken
    ) -> AccessibilityElementSpec {
        AccessibilityElementSpec(
            id: id,
            role: .action,
            label: label,
            actions: [action(.activate, label, token)]
        )
    }

    private func action(
        _ kind: AccessibilityActionKind,
        _ label: String,
        _ token: AccessibilityActionToken
    ) -> AccessibilityActionSpec {
        AccessibilityActionSpec(kind: kind, label: label, token: token)
    }

    private func consequence(id: String) -> WorldEffect {
        WorldEffect(
            id: WorldEffectID("effect-\(id)"),
            mutation: .revealNode(
                WorldNodeBlueprint(
                    id: WorldNodeID("node-\(id)"),
                    kind: .institution,
                    form: "A durable historical consequence",
                    position: NormalizedPoint(x: 0.5, y: 0.5)
                )
            )
        )
    }
}
