import ContentKit
import CryptoKit
import Foundation
@testable import JourneyContent
import XCTest

final class FirstFarmersPayloadProjectionTests: XCTestCase {
    func testCanonicalDecoderAcceptsCompleteNonShippingFirstFarmersPayload() throws {
        let files = try payloadFiles()
        let payload = try ContentDocumentDecoder.decodePackage(files.payload)
        let receipt = try JSONDecoder().decode(PayloadProjectionReceipt.self, from: files.receipt)
        let requirements = try JSONDecoder().decode(
            AssetRequirementDocument.self,
            from: files.assetRequirements
        )

        XCTAssertEqual(payload.packageID, "first-farmers-development-v1")
        XCTAssertEqual(payload.chapters.map(\.id), ["first-farmers"])
        XCTAssertEqual(payload.chapters.flatMap(\.arcs).count, 3)
        XCTAssertEqual(payload.chapters.flatMap(\.arcs).flatMap(\.beats).count, 17)
        XCTAssertEqual(payload.scenes.count, 17)
        XCTAssertEqual(payload.audioTimelines.count, 47)
        XCTAssertEqual(payload.responsiveAudioPrograms.count, 6)
        XCTAssertEqual(payload.accessibility.count, 17)
        XCTAssertEqual(
            payload.scenes.compactMap(\.interactionVisualBinding).count,
            6
        )

        let narrationEvents = payload.audioTimelines
            .flatMap(\.events)
            .filter { $0.role == .narration }
        XCTAssertEqual(narrationEvents.count, 37)
        XCTAssertEqual(Set(narrationEvents.map(\.cueID)).count, 37)
        XCTAssertTrue(narrationEvents.allSatisfy { $0.narrationBinding != nil })
        XCTAssertEqual(payload.audioTimelines.flatMap(\.haptics).count, 19)
        XCTAssertEqual(
            Set(payload.audioTimelines.flatMap(\.haptics).map(\.kind)),
            Set([
                HapticSemantic.contact,
                .drag,
                .resistance,
                .transfer,
                .break,
                .seal,
            ])
        )

        XCTAssertEqual(receipt.status, "NON_SHIPPING_DEVELOPMENT_PAYLOAD_PROJECTION")
        XCTAssertEqual(receipt.shippingState, "PROHIBITED")
        XCTAssertEqual(receipt.payloadSHA256, sha256(files.payload))
        XCTAssertEqual(
            receipt.assetRequirementsSHA256,
            sha256(files.assetRequirements)
        )
        XCTAssertEqual(receipt.counts.scenes, 17)
        XCTAssertEqual(receipt.counts.narrationCues, 37)
        XCTAssertEqual(receipt.counts.runtimeVisualBindings, 6)
        XCTAssertEqual(receipt.counts.audioTimelines, 47)
        XCTAssertEqual(receipt.counts.responsiveAudioPrograms, 6)
        XCTAssertEqual(receipt.counts.provisionalResponsiveAudioPrograms, 5)
        XCTAssertEqual(receipt.counts.placeholderResponsiveAudioPrograms, 1)
        XCTAssertEqual(receipt.counts.nonNarrationAudioCues, 166)
        XCTAssertEqual(receipt.counts.assetRequirements, 777)
        XCTAssertTrue(receipt.claimsExcluded.contains("shipping approval"))
        XCTAssertTrue(receipt.claimsExcluded.contains("physical-device proof"))

        XCTAssertEqual(requirements.status, "NON_SHIPPING_FUTURE_ASSET_REQUIREMENTS")
        XCTAssertEqual(requirements.shippingState, "PROHIBITED")
        XCTAssertEqual(requirements.requirements.count, 777)
        XCTAssertTrue(requirements.requirements.allSatisfy {
            $0.state == "FUTURE_PRODUCTION_ASSET_NOT_PRESENT"
        })
    }

    func testEveryBeatBindsOneSceneAccessibilitySpecAndItsExactNarrationScope() throws {
        let payload = try ContentDocumentDecoder.decodePackage(payloadFiles().payload)
        let sceneByID = Dictionary(uniqueKeysWithValues: payload.scenes.map { ($0.id, $0) })
        let accessibilityIDs = Set(payload.accessibility.map(\.id))
        let narrationByCueID = Dictionary(
            uniqueKeysWithValues: payload.audioTimelines.flatMap(\.events)
                .filter { $0.role == .narration }
                .map { ($0.cueID, $0) }
        )

        for chapter in payload.chapters {
            for arc in chapter.arcs {
                for beat in arc.beats {
                    let scene = try XCTUnwrap(sceneByID[beat.sceneID])
                    XCTAssertTrue(accessibilityIDs.contains(scene.accessibilityID))
                    XCTAssertEqual(
                        scene.accessibilityID,
                        AccessibilityID("accessibility-\(beat.id.rawValue)")
                    )
                    XCTAssertEqual(
                        scene.interactionVisualBinding == nil,
                        beat.interaction == nil
                    )
                    for cueID in beat.narrationCueIDs {
                        let event = try XCTUnwrap(narrationByCueID[cueID])
                        let binding = try XCTUnwrap(event.narrationBinding)
                        XCTAssertEqual(binding.scope.chapterID, chapter.id)
                        XCTAssertEqual(binding.scope.arcID, arc.id)
                        XCTAssertEqual(binding.scope.beatID, beat.id)
                        let segment = try XCTUnwrap(
                            beat.narrative.manuscriptSegments.first {
                                $0.id == binding.manuscriptSegmentID
                            }
                        )
                        XCTAssertEqual(
                            binding.manuscriptSegmentSHA256,
                            sha256(Data(segment.launchEnglish.utf8))
                        )
                    }
                }
            }
        }
    }

    func testHarvestSceneIsThePhaseOneContractWithOnlyAccessibilityRebound() throws {
        let files = try payloadFiles()
        let payloadRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: files.payload) as? [String: Any]
        )
        let fixtureRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: files.harvestFixture) as? [String: Any]
        )
        let scenes = try XCTUnwrap(payloadRoot["scenes"] as? [[String: Any]])
        var projected = try XCTUnwrap(
            scenes.first { $0["id"] as? String == "harvest-allocation-option-1" }
        )
        var expected = try XCTUnwrap(fixtureRoot["scene"] as? [String: Any])
        projected.removeValue(forKey: "accessibilityID")
        expected.removeValue(forKey: "accessibilityID")
        XCTAssertEqual(projected as NSDictionary, expected as NSDictionary)
    }

    func testCanonicalDecoderFailsClosedOnMissingVisualBindingAndNarrationHashDrift() throws {
        let canonical = try payloadFiles().payload

        let missingVisualBinding = try mutateJSON(canonical) { root in
            var scenes = root["scenes"] as! [[String: Any]]
            let index = scenes.firstIndex { $0["interactionVisualBinding"] != nil }!
            scenes[index].removeValue(forKey: "interactionVisualBinding")
            root["scenes"] = scenes
        }
        XCTAssertThrowsError(try ContentDocumentDecoder.decodePackage(missingVisualBinding))

        let narrationHashDrift = try mutateJSON(canonical) { root in
            var timelines = root["audioTimelines"] as! [[String: Any]]
            var events = timelines[0]["events"] as! [[String: Any]]
            let index = events.firstIndex { $0["role"] as? String == "narration" }!
            var binding = events[index]["narrationBinding"] as! [String: Any]
            binding["manuscriptSegmentSHA256"] = String(repeating: "0", count: 64)
            events[index]["narrationBinding"] = binding
            timelines[0]["events"] = events
            root["audioTimelines"] = timelines
        }
        XCTAssertThrowsError(try ContentDocumentDecoder.decodePackage(narrationHashDrift))

        let missingResponsiveProgram = try mutateJSON(canonical) { root in
            var programs = root["responsiveAudioPrograms"] as! [[String: Any]]
            programs.removeLast()
            root["responsiveAudioPrograms"] = programs
        }
        XCTAssertThrowsError(
            try ContentDocumentDecoder.decodePackage(missingResponsiveProgram)
        )

        let forgedResponsiveScope = try mutateJSON(canonical) { root in
            var programs = root["responsiveAudioPrograms"] as! [[String: Any]]
            var scope = programs[0]["scope"] as! [String: Any]
            scope["interactionID"] = "forged-interaction"
            programs[0]["scope"] = scope
            root["responsiveAudioPrograms"] = programs
        }
        XCTAssertThrowsError(
            try ContentDocumentDecoder.decodePackage(forgedResponsiveScope)
        )
    }

    func testCanonicalPayloadContainsNoBackstageOrAcademicLeakage() throws {
        let payload = try payloadFiles().payload
        let text = try XCTUnwrap(String(data: payload, encoding: .utf8)).lowercased()
        for forbidden in [
            "\"sources\"",
            "\"evidence\"",
            "\"confidence\"",
            "\"historiography\"",
            "\"counterarguments\"",
            "\"methodology\"",
            "\"verifierfindings\"",
            "\"claimregister\"",
            "\"transportstatus\"",
            "\"stateid\"",
            "\"causalmixcontract\"",
            "\"monotonicrule\"",
            "\"gainunit\"",
            "scholars debate",
            "historians disagree",
            "the picture is complex",
            "this account is contested",
            "from another perspective",
            "it is important to note",
        ] {
            XCTAssertFalse(text.contains(forbidden), "Leaked backstage field or phrase: \(forbidden)")
        }

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )
        let programs = try XCTUnwrap(
            root["responsiveAudioPrograms"] as? [[String: Any]]
        )
        for causalMix in programs.compactMap({ $0["causalMix"] }) {
            XCTAssertFalse(
                jsonKeys(in: causalMix).contains("stageid"),
                "Backstage causal-mix field leaked: stageID"
            )
        }
    }

    func testContinentRemadeResponsiveAudioReplacesItsPlaceholderProjection() throws {
        let files = try payloadFiles()
        let payload = try ContentDocumentDecoder.decodePackage(files.payload)
        let receipt = try JSONDecoder().decode(PayloadProjectionReceipt.self, from: files.receipt)
        let requirements = try JSONDecoder().decode(
            AssetRequirementDocument.self,
            from: files.assetRequirements
        )

        XCTAssertEqual(receipt.counts.provisionalResponsiveAudioPrograms, 5)
        XCTAssertEqual(receipt.counts.placeholderResponsiveAudioPrograms, 1)

        let program = try XCTUnwrap(
            payload.responsiveAudioPrograms.first {
                $0.id == "continent-remade-responsive-audio-v1"
            }
        )
        XCTAssertEqual(program.scope.chapterID, "first-farmers")
        XCTAssertEqual(program.scope.arcID, "first-farmers-arc-03")
        XCTAssertEqual(program.scope.beatID, "beat-first-farmers-continent-remade")
        XCTAssertEqual(
            program.scope.interactionID,
            "interaction-first-farmers-a-continent-remade"
        )

        let timelineIDs = [program.approachTimelineID]
            + program.interactionBeds.map(\.timelineID)
            + [program.consequenceTimelineID]
        XCTAssertEqual(
            timelineIDs,
            [
                "continent-remade-approach-v1",
                "continent-remade-waiting-bed-v1",
                "continent-remade-engaged-bed-v1",
                "continent-remade-resistance-bed-v1",
                "continent-remade-consequence-v1",
            ]
        )

        let timelineIDSet = Set(timelineIDs)
        let projectedTimelines = payload.audioTimelines.filter {
            timelineIDSet.contains($0.id)
        }
        XCTAssertEqual(projectedTimelines.count, 5)
        XCTAssertTrue(projectedTimelines.allSatisfy { timeline in
            timeline.haptics.isEmpty
                && !timeline.events.contains(where: { $0.role == .narration })
        })
        let projectedAudioPaths = projectedTimelines.flatMap(\.events).compactMap(\.assetPath)
        XCTAssertEqual(projectedAudioPaths.count, 15)
        XCTAssertTrue(projectedAudioPaths.allSatisfy {
            $0.hasPrefix("audio/first-farmers/continent-remade-responsive-v1/")
        })

        let continentRequirements = requirements.requirements.filter {
            $0.sourceContract == "CONTINENT_REMADE_RESPONSIVE_AUDIO_WORK_OBJECT"
        }
        XCTAssertEqual(continentRequirements.count, 15)
        XCTAssertEqual(
            Set(continentRequirements.map(\.assetPath)),
            Set(projectedAudioPaths)
        )
    }

    func testMoreMouthsResponsiveAudioReplacesItsPlaceholderProjection() throws {
        let files = try payloadFiles()
        let payload = try ContentDocumentDecoder.decodePackage(files.payload)
        let requirements = try JSONDecoder().decode(
            AssetRequirementDocument.self,
            from: files.assetRequirements
        )

        let program = try XCTUnwrap(
            payload.responsiveAudioPrograms.first {
                $0.id == "more-mouths-responsive-audio-v1"
            }
        )
        XCTAssertEqual(program.scope.chapterID, "first-farmers")
        XCTAssertEqual(program.scope.arcID, "first-farmers-arc-03")
        XCTAssertEqual(program.scope.beatID, "beat-first-farmers-more-mouths")
        XCTAssertEqual(
            program.scope.interactionID,
            "interaction-first-farmers-more-mouths-more-land"
        )

        let timelineIDs = [program.approachTimelineID]
            + program.interactionBeds.map(\.timelineID)
            + [program.consequenceTimelineID]
        XCTAssertEqual(
            timelineIDs,
            [
                "more-mouths-approach-v1",
                "more-mouths-waiting-bed-v1",
                "more-mouths-engaged-bed-v1",
                "more-mouths-resistance-bed-v1",
                "more-mouths-consequence-v1",
            ]
        )

        let timelineIDSet = Set(timelineIDs)
        let projectedTimelines = payload.audioTimelines.filter {
            timelineIDSet.contains($0.id)
        }
        XCTAssertEqual(projectedTimelines.count, 5)
        XCTAssertTrue(projectedTimelines.allSatisfy { timeline in
            timeline.haptics.isEmpty
                && !timeline.events.contains(where: { $0.role == .narration })
        })
        let projectedAudioPaths = projectedTimelines.flatMap(\.events).compactMap(\.assetPath)
        XCTAssertEqual(projectedAudioPaths.count, 15)
        XCTAssertTrue(projectedAudioPaths.allSatisfy {
            $0.hasPrefix("audio/first-farmers/more-mouths-responsive-v1/")
        })

        let moreMouthsRequirements = requirements.requirements.filter {
            $0.sourceContract == "MORE_MOUTHS_RESPONSIVE_AUDIO_WORK_OBJECT"
        }
        XCTAssertEqual(moreMouthsRequirements.count, 15)
        XCTAssertEqual(
            Set(moreMouthsRequirements.map(\.assetPath)),
            Set(projectedAudioPaths)
        )
    }

    func testHouseholdTraceCarriesNamedReachableLatchedStages() throws {
        let payload = try ContentDocumentDecoder.decodePackage(payloadFiles().payload)
        let chapter = try XCTUnwrap(payload.chapters.first { $0.id == "first-farmers" })
        let beat = try XCTUnwrap(
            chapter.arcs.flatMap(\.beats).first {
                $0.id == "beat-first-farmers-household-crosses"
            }
        )
        let interaction = try XCTUnwrap(beat.interaction)
        guard case let .trace(configuration) = interaction.grammar else {
            return XCTFail("Household route must remain a Trace interaction")
        }
        XCTAssertEqual(
            configuration.anchorIDs,
            ["western-anatolia", "aegean-islands", "thessaly", "danube-corridor"]
        )

        let scene = try XCTUnwrap(
            payload.scenes.first { $0.id == "scene-first-farmers-aegean-crossing" }
        )
        guard let visualBinding = scene.interactionVisualBinding,
              case let .trace(binding) = visualBinding else {
            return XCTFail("Household route must bind its authored Trace visual states")
        }
        XCTAssertEqual(
            binding.reachedAnchorVariants,
            [
                .init(anchorID: "western-anatolia", variantID: "western-anatolia-loaded"),
                .init(anchorID: "aegean-islands", variantID: "aegean-passage-secured"),
                .init(anchorID: "thessaly", variantID: "thessaly-system-established"),
            ]
        )

        let target = try XCTUnwrap(
            scene.interactionTargets.first {
                $0.interactionTargetID == binding.interactionTargetID
            }
        )
        XCTAssertEqual(
            target.hitRegion.path,
            [
                NormalizedPoint(x: 0.2, y: 0.16),
                NormalizedPoint(x: 0.82, y: 0.16),
                NormalizedPoint(x: 0.82, y: 0.82),
                NormalizedPoint(x: 0.2, y: 0.82),
            ]
        )
        XCTAssertNoThrow(try scene.validateInteractionVisualBinding(to: interaction))
    }

    func testHouseholdCrossesResponsiveAudioReplacesItsPlaceholderProjection() throws {
        let files = try payloadFiles()
        let payload = try ContentDocumentDecoder.decodePackage(files.payload)
        let requirements = try JSONDecoder().decode(
            AssetRequirementDocument.self,
            from: files.assetRequirements
        )

        let program = try XCTUnwrap(
            payload.responsiveAudioPrograms.first {
                $0.id == "household-crosses-responsive-audio-v1"
            }
        )
        XCTAssertEqual(program.scope.chapterID, "first-farmers")
        XCTAssertEqual(program.scope.arcID, "first-farmers-arc-01")
        XCTAssertEqual(program.scope.beatID, "beat-first-farmers-household-crosses")
        XCTAssertEqual(
            program.scope.interactionID,
            "interaction-first-farmers-a-household-crosses"
        )

        let timelineIDs = [program.approachTimelineID]
            + program.interactionBeds.map(\.timelineID)
            + [program.consequenceTimelineID]
        XCTAssertEqual(
            timelineIDs,
            [
                "household-crosses-approach-v1",
                "household-crosses-waiting-bed-v1",
                "household-crosses-engaged-bed-v1",
                "household-crosses-resistance-bed-v1",
                "household-crosses-consequence-v1",
            ]
        )

        let timelineIDSet = Set(timelineIDs)
        let projectedTimelines = payload.audioTimelines.filter {
            timelineIDSet.contains($0.id)
        }
        XCTAssertEqual(projectedTimelines.count, 5)
        XCTAssertTrue(projectedTimelines.allSatisfy { timeline in
            timeline.haptics.isEmpty
                && !timeline.events.contains(where: { $0.role == .narration })
        })
        let projectedAudioPaths = projectedTimelines.flatMap(\.events).compactMap(\.assetPath)
        XCTAssertEqual(projectedAudioPaths.count, 15)
        XCTAssertTrue(projectedAudioPaths.allSatisfy {
            $0.hasPrefix("audio/first-farmers/household-crosses-responsive-v1/")
        })

        let householdRequirements = requirements.requirements.filter {
            $0.sourceContract == "HOUSEHOLD_CROSSES_RESPONSIVE_AUDIO_WORK_OBJECT"
        }
        XCTAssertEqual(householdRequirements.count, 15)
        XCTAssertEqual(
            Set(householdRequirements.map(\.assetPath)),
            Set(projectedAudioPaths)
        )
    }

    func testThreeRecordsRemainsAnExplicitNonShippingPlaceholderUntilItsWorkObjectIsApproved() throws {
        let files = try payloadFiles()
        let payload = try ContentDocumentDecoder.decodePackage(files.payload)
        let receipt = try JSONDecoder().decode(PayloadProjectionReceipt.self, from: files.receipt)
        let requirements = try JSONDecoder().decode(
            AssetRequirementDocument.self,
            from: files.assetRequirements
        )

        XCTAssertEqual(receipt.counts.provisionalResponsiveAudioPrograms, 5)
        XCTAssertEqual(receipt.counts.placeholderResponsiveAudioPrograms, 1)

        let program = try XCTUnwrap(
            payload.responsiveAudioPrograms.first {
                $0.scope.beatID == "beat-first-farmers-three-records"
            }
        )
        XCTAssertEqual(program.id, "responsive-program-beat-first-farmers-three-records")
        XCTAssertEqual(program.scope.chapterID, "first-farmers")
        XCTAssertEqual(program.scope.arcID, "first-farmers-arc-02")
        XCTAssertEqual(program.scope.beatID, "beat-first-farmers-three-records")
        XCTAssertEqual(
            program.scope.interactionID,
            "interaction-first-farmers-at-the-iron-gates"
        )

        XCTAssertNil(program.causalMix)
        XCTAssertEqual(
            program.exitPolicy,
            .boundedFade(durationSamples: 9_600)
        )

        let timelineIDs = [program.approachTimelineID]
            + program.interactionBeds.map(\.timelineID)
            + [program.consequenceTimelineID]
        XCTAssertEqual(
            timelineIDs,
            [
                "responsive-beat-first-farmers-three-records-approach",
                "responsive-beat-first-farmers-three-records-waiting",
                "responsive-beat-first-farmers-three-records-engaged",
                "responsive-beat-first-farmers-three-records-resistance",
                "responsive-beat-first-farmers-three-records-consequence",
            ]
        )
        let timelineIDSet = Set(timelineIDs)
        let projectedTimelines = payload.audioTimelines.filter {
            timelineIDSet.contains($0.id)
        }
        XCTAssertEqual(projectedTimelines.count, 5)
        XCTAssertTrue(projectedTimelines.allSatisfy { timeline in
            timeline.haptics.isEmpty
                && !timeline.events.contains(where: {
                    $0.role == .narration || $0.role == .silence
                })
        })
        let projectedAudioPaths = Set(projectedTimelines.flatMap(\.events).compactMap(\.assetPath))
        XCTAssertEqual(projectedAudioPaths.count, 15)
        XCTAssertTrue(projectedAudioPaths.allSatisfy {
            $0.hasPrefix(
                "requirements/first-farmers/audio/responsive/beat-first-farmers-three-records/"
            )
        })

        let threeRecordsRequirements = requirements.requirements.filter {
            $0.sourceContract == "FIRST_FARMERS_PAYLOAD_PROJECTION"
                && $0.assetPath.hasPrefix(
                    "requirements/first-farmers/audio/responsive/beat-first-farmers-three-records/"
                )
        }
        XCTAssertEqual(threeRecordsRequirements.count, 15)
        XCTAssertEqual(
            Set(threeRecordsRequirements.map(\.assetPath)),
            projectedAudioPaths
        )
    }

    private func payloadFiles() throws -> (
        payload: Data,
        assetRequirements: Data,
        receipt: Data,
        harvestFixture: Data
    ) {
#if os(iOS)
        let bundle = Bundle(for: FirstFarmersPayloadProjectionTests.self)
        func bundled(_ name: String) throws -> Data {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
            return try Data(contentsOf: url)
        }
        return (
            payload: try bundled("first-farmers.content-package"),
            assetRequirements: try bundled("first-farmers.asset-requirements"),
            receipt: try bundled("first-farmers.payload-receipt"),
            harvestFixture: try bundled("harvest-option-1.scene")
        )
#else
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let generated = root.appending(path: "phase2/generated")
        return (
            payload: try Data(
                contentsOf: generated.appending(path: "first-farmers.content-package.json")
            ),
            assetRequirements: try Data(
                contentsOf: generated.appending(path: "first-farmers.asset-requirements.json")
            ),
            receipt: try Data(
                contentsOf: generated.appending(path: "first-farmers.payload-receipt.json")
            ),
            harvestFixture: try Data(
                contentsOf: root.appending(path: "phase1/fixtures/harvest-option-1.scene.json")
            )
        )
#endif
    }

    private func mutateJSON(
        _ data: Data,
        mutation: (inout [String: Any]) -> Void
    ) throws -> Data {
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        mutation(&root)
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func jsonKeys(in value: Any) -> Set<String> {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: []) { keys, entry in
                keys.insert(entry.key.lowercased())
                keys.formUnion(jsonKeys(in: entry.value))
            }
        }
        if let array = value as? [Any] {
            return array.reduce(into: []) { keys, item in
                keys.formUnion(jsonKeys(in: item))
            }
        }
        return []
    }
}

private struct PayloadProjectionReceipt: Decodable {
    struct Counts: Decodable {
        let scenes: Int
        let runtimeVisualBindings: Int
        let audioTimelines: Int
        let responsiveAudioPrograms: Int
        let provisionalResponsiveAudioPrograms: Int
        let placeholderResponsiveAudioPrograms: Int
        let narrationCues: Int
        let nonNarrationAudioCues: Int
        let assetRequirements: Int
    }

    let status: String
    let shippingState: String
    let payloadSHA256: String
    let assetRequirementsSHA256: String
    let counts: Counts
    let claimsExcluded: [String]
}

private struct AssetRequirementDocument: Decodable {
    struct Requirement: Decodable {
        let assetPath: String
        let state: String
        let sourceContract: String
        let owners: [String]
    }

    let status: String
    let shippingState: String
    let requirements: [Requirement]
}
