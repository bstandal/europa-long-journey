import Foundation

public enum Chapter01WorldCell: String, Codable, CaseIterable, Sendable {
    case aegeanPassage = "western-anatolia-aegean"
    case thessalianHousehold = "thessalian-household-store"
    case ironGates = "iron-gates-riverbank"
    case longhouseGround = "danube-loess-longhouse"
    case settlementLandscape = "expanding-settlement-landscape"
}

public enum Chapter01Sequence: Int, Codable, CaseIterable, Identifiable, Sendable {
    case keepTheFutureAlive
    case harvestHadToLast
    case riverKnowsTheLanding
    case houseOutlives
    case moreMouthsMoreLand
    case continentRemade

    public var id: Int { rawValue }

    public var interactionID: String {
        switch self {
        case .keepTheFutureAlive:
            "interaction-first-farmers-a-household-crosses"
        case .harvestHadToLast:
            "interaction-first-farmers-the-harvest-had-to-last"
        case .riverKnowsTheLanding:
            "interaction-first-farmers-at-the-iron-gates"
        case .houseOutlives:
            "interaction-first-farmers-the-house-outlives"
        case .moreMouthsMoreLand:
            "interaction-first-farmers-more-mouths-more-land"
        case .continentRemade:
            "interaction-first-farmers-a-continent-remade"
        }
    }

    public var shortAction: String {
        switch self {
        case .keepTheFutureAlive: "Hold the line"
        case .harvestHadToLast: "Divide the harvest"
        case .riverKnowsTheLanding: "Take the landing line"
        case .houseOutlives: "Hold the load"
        case .moreMouthsMoreLand: "Lead to water"
        case .continentRemade: "Close the gate"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .keepTheFutureAlive:
            "Loaded household boat in a cross-current"
        case .harvestHadToLast:
            "Finite harvest shared between food, reserve and spring seed"
        case .riverKnowsTheLanding:
            "Landing line working with a local guide pole"
        case .houseOutlives:
            "Longhouse frame under a shared load"
        case .moreMouthsMoreLand:
            "Herd route crossing wet ground towards water"
        case .continentRemade:
            "Settlement barrier carrying several household needs"
        }
    }
}

public struct Chapter01Beat: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let sequence: Chapter01Sequence
    public let cell: Chapter01WorldCell
    public let authoredStartSeconds: Double
    public let caption: String?
    public let visualState: String

    public init(
        id: String,
        sequence: Chapter01Sequence,
        cell: Chapter01WorldCell,
        authoredStartSeconds: Double,
        caption: String? = nil,
        visualState: String
    ) {
        self.id = id
        self.sequence = sequence
        self.cell = cell
        self.authoredStartSeconds = authoredStartSeconds
        self.caption = caption
        self.visualState = visualState
    }
}

public enum Chapter01ExperienceScript {
    public static let packageID = "first-farmers-3d-review-v1"
    public static let authoredDurationSeconds: Double = 815
    public static let authoredDurationMillis: Int64 = 815_000

    /// Thirty-four durable visual states. Their authored timestamps describe
    /// the pressure curve; input remains user-paced and is never delayed to
    /// fill the clock.
    public static let beats: [Chapter01Beat] = [
        .init(id: "cross-current", sequence: .keepTheFutureAlive, cell: .aegeanPassage, authoredStartSeconds: 0, visualState: "cross-current"),
        .init(id: "load-under-tension", sequence: .keepTheFutureAlive, cell: .aegeanPassage, authoredStartSeconds: 5, visualState: "load-under-tension"),
        .init(id: "dry-bank-transfer", sequence: .keepTheFutureAlive, cell: .aegeanPassage, authoredStartSeconds: 55, caption: "Farming moved west with households carrying a complete living system.", visualState: "dry-bank-transfer"),
        .init(id: "seed-leaves-water", sequence: .keepTheFutureAlive, cell: .aegeanPassage, authoredStartSeconds: 80, visualState: "seed-leaves-water"),

        .init(id: "first-furrow", sequence: .keepTheFutureAlive, cell: .thessalianHousehold, authoredStartSeconds: 92, visualState: "first-furrow"),
        .init(id: "worked-season", sequence: .keepTheFutureAlive, cell: .thessalianHousehold, authoredStartSeconds: 120, caption: "The carried seed entered worked Thessalian soil.", visualState: "worked-season"),
        .init(id: "finite-harvest", sequence: .keepTheFutureAlive, cell: .thessalianHousehold, authoredStartSeconds: 138, visualState: "finite-harvest"),
        .init(id: "three-claims", sequence: .harvestHadToLast, cell: .thessalianHousehold, authoredStartSeconds: 150, caption: "This harvest must feed the household, cover loss and preserve spring seed.", visualState: "three-claims"),
        .init(id: "food-committed", sequence: .harvestHadToLast, cell: .thessalianHousehold, authoredStartSeconds: 175, visualState: "food-committed"),
        .init(id: "reserve-raised", sequence: .harvestHadToLast, cell: .thessalianHousehold, authoredStartSeconds: 195, visualState: "reserve-raised"),
        .init(id: "seed-sealed", sequence: .harvestHadToLast, cell: .thessalianHousehold, authoredStartSeconds: 215, visualState: "seed-sealed"),
        .init(id: "winter-breach", sequence: .harvestHadToLast, cell: .thessalianHousehold, authoredStartSeconds: 255, visualState: "winter-breach"),
        .init(id: "spring-return", sequence: .harvestHadToLast, cell: .thessalianHousehold, authoredStartSeconds: 305, caption: "The protected seed returns to worked soil instead of the hearth.", visualState: "spring-return"),

        .init(id: "later-hands", sequence: .riverKnowsTheLanding, cell: .ironGates, authoredStartSeconds: 340, visualState: "later-hands"),
        .init(id: "inhabited-bank", sequence: .riverKnowsTheLanding, cell: .ironGates, authoredStartSeconds: 355, visualState: "inhabited-bank"),
        .init(id: "forces-align", sequence: .riverKnowsTheLanding, cell: .ironGates, authoredStartSeconds: 368, visualState: "forces-align"),
        .init(id: "two-way-load", sequence: .riverKnowsTheLanding, cell: .ironGates, authoredStartSeconds: 385, caption: "Local river knowledge made the landing work.", visualState: "two-way-load"),
        .init(id: "route-inland", sequence: .riverKnowsTheLanding, cell: .ironGates, authoredStartSeconds: 415, visualState: "route-inland"),

        .init(id: "prepared-ground", sequence: .houseOutlives, cell: .longhouseGround, authoredStartSeconds: 440, visualState: "prepared-ground"),
        .init(id: "frame-rises", sequence: .houseOutlives, cell: .longhouseGround, authoredStartSeconds: 458, visualState: "frame-rises"),
        .init(id: "shelter-holds", sequence: .houseOutlives, cell: .longhouseGround, authoredStartSeconds: 500, caption: "A rebuilt house tied later work to inherited ground.", visualState: "shelter-holds"),
        .init(id: "timber-replaced", sequence: .houseOutlives, cell: .longhouseGround, authoredStartSeconds: 535, visualState: "timber-replaced"),
        .init(id: "plot-crowds", sequence: .houseOutlives, cell: .longhouseGround, authoredStartSeconds: 575, visualState: "plot-crowds"),

        .init(id: "enclosure-opens", sequence: .moreMouthsMoreLand, cell: .settlementLandscape, authoredStartSeconds: 590, visualState: "enclosure-opens"),
        .init(id: "herd-finds-water", sequence: .moreMouthsMoreLand, cell: .settlementLandscape, authoredStartSeconds: 612, visualState: "herd-finds-water"),
        .init(id: "field-edge", sequence: .moreMouthsMoreLand, cell: .settlementLandscape, authoredStartSeconds: 635, visualState: "field-edge"),
        .init(id: "daughter-clearing", sequence: .moreMouthsMoreLand, cell: .settlementLandscape, authoredStartSeconds: 660, visualState: "daughter-clearing"),
        .init(id: "settlement-grows", sequence: .moreMouthsMoreLand, cell: .settlementLandscape, authoredStartSeconds: 680, caption: "Growing households required more land.", visualState: "settlement-grows"),
        .init(id: "hearth-cools", sequence: .moreMouthsMoreLand, cell: .settlementLandscape, authoredStartSeconds: 700, visualState: "hearth-cools"),
        .init(id: "clearing-regrows", sequence: .moreMouthsMoreLand, cell: .settlementLandscape, authoredStartSeconds: 720, visualState: "clearing-regrows"),
        .init(id: "basket-relay", sequence: .continentRemade, cell: .settlementLandscape, authoredStartSeconds: 738, visualState: "basket-relay"),
        .init(id: "coupled-load", sequence: .continentRemade, cell: .settlementLandscape, authoredStartSeconds: 760, visualState: "coupled-load"),
        .init(id: "continent-condition", sequence: .continentRemade, cell: .settlementLandscape, authoredStartSeconds: 790, caption: "By 3300 BC, Europe had become a continent of fields, herds and long-lived settlements.", visualState: "continent-condition"),
        .init(id: "eastern-grass", sequence: .continentRemade, cell: .settlementLandscape, authoredStartSeconds: 810, visualState: "eastern-grass"),
    ]

    public static func firstBeatIndex(for sequence: Chapter01Sequence) -> Int {
        beats.firstIndex(where: { $0.sequence == sequence }) ?? 0
    }

    public static func beatIndices(for sequence: Chapter01Sequence) -> [Int] {
        beats.indices.filter { beats[$0].sequence == sequence }
    }

    public static func authoredStartMillis(forBeatAt index: Int) -> Int64 {
        let bounded = min(max(index, 0), beats.count - 1)
        return Int64((beats[bounded].authoredStartSeconds * 1_000).rounded())
    }

    public static func authoredEndMillis(forBeatAt index: Int) -> Int64 {
        let bounded = min(max(index, 0), beats.count - 1)
        guard bounded + 1 < beats.count else { return authoredDurationMillis }
        return authoredStartMillis(forBeatAt: bounded + 1)
    }

    public static func authoredDurationMillis(forBeatAt index: Int) -> Int64 {
        max(
            authoredEndMillis(forBeatAt: index)
                - authoredStartMillis(forBeatAt: index),
            1
        )
    }

    public static func authoredRangeMillis(
        for sequence: Chapter01Sequence
    ) -> Range<Int64> {
        let indices = beatIndices(for: sequence)
        guard let first = indices.first, let last = indices.last else { return 0 ..< 1 }
        return authoredStartMillis(forBeatAt: first)
            ..< authoredEndMillis(forBeatAt: last)
    }
}
