import ContentKit
import Foundation

public enum Chapter01InteractionCatalog {
    public static let specs: [InteractionSpec] = [
        householdCrosses,
        harvestHadToLast,
        ironGates,
        houseOutlives,
        moreMouthsMoreLand,
        continentRemade,
    ]

    public static func spec(for sequence: Chapter01Sequence) -> InteractionSpec {
        specs.first(where: { $0.id.rawValue == sequence.interactionID })!
    }

    public static let householdCrosses = InteractionSpec(
        id: "interaction-first-farmers-a-household-crosses",
        prompt: copy("carry-household", "Carry the household"),
        grammar: .trace(
            TraceInteractionSpec(
                anchors: [
                    NormalizedPoint(x: 0.76, y: 0.78),
                    NormalizedPoint(x: 0.58, y: 0.61),
                    NormalizedPoint(x: 0.43, y: 0.44),
                    NormalizedPoint(x: 0.33, y: 0.20),
                ],
                anchorIDs: [
                    "western-anatolia",
                    "aegean-islands",
                    "thessaly",
                    "danube-corridor",
                ],
                tolerance: 0.075
            )
        ),
        completionEffects: [
            WorldEffect(
                id: "effect-first-farmers-a-household-crosses",
                mutation: .establishTrace(
                    WorldTraceBlueprint(
                        id: "route-aegean-danube",
                        kind: .seaRoute,
                        origin: "western-anatolia",
                        destination: "iron-gates"
                    )
                )
            ),
        ],
        accessibilityID: "accessibility-beat-first-farmers-household-crosses"
    )

    public static let harvestHadToLast = InteractionSpec(
        id: "interaction-first-farmers-the-harvest-had-to-last",
        prompt: copy("divide-harvest", "Divide the harvest"),
        grammar: .allocate(
            AllocateInteractionSpec(
                resourceName: copy("harvest-shares", "harvest shares"),
                totalUnits: 12,
                destinations: [
                    AllocationDestination(id: "food", minimumUnits: 4),
                    AllocationDestination(id: "reserve", minimumUnits: 2),
                    AllocationDestination(id: "seed", minimumUnits: 3),
                ]
            )
        ),
        completionEffects: [
            WorldEffect(
                id: "effect-first-farmers-the-harvest-had-to-last",
                mutation: .revealNode(
                    WorldNodeBlueprint(
                        id: "trace-seasonal-store",
                        kind: .institution,
                        form: "A divided store binding winter food, reserve and seed grain",
                        position: NormalizedPoint(x: 0.56, y: 0.62),
                        attributes: [
                            NamedValue(key: "obligations", value: .integer(3)),
                            NamedValue(key: "yearBound", value: .boolean(true)),
                        ]
                    )
                )
            ),
        ],
        accessibilityID: "accessibility-beat-first-farmers-harvest-allocation"
    )

    public static let ironGates = InteractionSpec(
        id: "interaction-first-farmers-at-the-iron-gates",
        prompt: copy("take-landing-line", "Take the landing line"),
        grammar: .transform(
            TransformInteractionSpec(stages: [
                TransformationStage(id: "river-communities", controlID: "time-layer", requiredAmount: 0.33),
                TransformationStage(id: "contact-households", controlID: "time-layer", requiredAmount: 0.66),
                TransformationStage(id: "later-settlements", controlID: "time-layer", requiredAmount: 1),
            ])
        ),
        completionEffects: [
            WorldEffect(
                id: "effect-first-farmers-at-the-iron-gates",
                mutation: .setNodeAttribute(
                    nodeID: "trace-european-farming-belt",
                    value: NamedValue(key: "ironGatesContact", value: .boolean(true))
                )
            ),
        ],
        accessibilityID: "accessibility-beat-first-farmers-three-records"
    )

    public static let houseOutlives = InteractionSpec(
        id: "interaction-first-farmers-the-house-outlives",
        prompt: copy("hold-load", "Hold the load"),
        grammar: .assemble(
            AssembleInteractionSpec(components: [
                AssemblyComponent(id: "posts", targetSlot: "frame"),
                AssemblyComponent(id: "hearth", targetSlot: "centre", prerequisites: ["posts"]),
                AssemblyComponent(id: "storage", targetSlot: "dry-bay", prerequisites: ["posts"]),
                AssemblyComponent(id: "roof", targetSlot: "shelter", prerequisites: ["posts"]),
            ])
        ),
        completionEffects: [
            WorldEffect(
                id: "effect-first-farmers-the-house-outlives",
                mutation: .revealNode(
                    WorldNodeBlueprint(
                        id: "trace-european-farming-belt",
                        kind: .landscape,
                        form: "A rebuilt longhouse plot anchored to inherited ground",
                        position: NormalizedPoint(x: 0.5, y: 0.48),
                        attributes: [
                            NamedValue(key: "ironGatesContact", value: .boolean(true)),
                            NamedValue(key: "rebuiltHousePlots", value: .integer(1)),
                        ]
                    )
                )
            ),
        ],
        accessibilityID: "accessibility-beat-first-farmers-raise-longhouse"
    )

    public static let moreMouthsMoreLand = InteractionSpec(
        id: "interaction-first-farmers-more-mouths-more-land",
        prompt: copy("lead-water", "Lead to water"),
        grammar: .transform(
            TransformInteractionSpec(stages: [
                TransformationStage(id: "new-hearths", controlID: "settlement-pressure", requiredAmount: 0.32),
                TransformationStage(id: "field-edges", controlID: "settlement-pressure", requiredAmount: 0.66),
                TransformationStage(id: "herd-lanes-and-daughters", controlID: "settlement-pressure", requiredAmount: 1),
            ])
        ),
        completionEffects: [
            WorldEffect(
                id: "effect-first-farmers-more-mouths-more-land",
                mutation: .transformNode(
                    nodeID: "trace-european-farming-belt",
                    form: "New hearths, fields, herd lanes and daughter settlements",
                    attributes: [
                        NamedValue(key: "settlementGrowth", value: .text("expanding")),
                        NamedValue(key: "daughterSettlements", value: .boolean(true)),
                    ]
                )
            ),
        ],
        accessibilityID: "accessibility-beat-first-farmers-more-mouths"
    )

    public static let continentRemade = InteractionSpec(
        id: "interaction-first-farmers-a-continent-remade",
        prompt: copy("close-gate", "Close the gate"),
        grammar: .transform(
            TransformInteractionSpec(stages: [
                TransformationStage(id: "danube-fields", controlID: "continental-spread", requiredAmount: 0.34),
                TransformationStage(id: "loess-settlements", controlID: "continental-spread", requiredAmount: 0.70),
                TransformationStage(id: "european-farming-belt", controlID: "continental-spread", requiredAmount: 1),
            ])
        ),
        completionEffects: [
            WorldEffect(
                id: "effect-first-farmers-a-continent-remade",
                mutation: .transformNode(
                    nodeID: "trace-european-farming-belt",
                    form: "Fields, herds, longhouses and inherited ground across the Danube and loess plains",
                    attributes: [
                        NamedValue(key: "continental", value: .boolean(true)),
                        NamedValue(key: "readyForSteppeHandoff", value: .boolean(true)),
                    ]
                )
            ),
        ],
        accessibilityID: "accessibility-beat-first-farmers-continent-remade"
    )

    private static func copy(_ id: String, _ english: String) -> LocalizedStringSpec {
        LocalizedStringSpec(
            id: LocalizedStringID("chapter01-immersive-\(id)"),
            launchEnglish: english
        )
    }
}
