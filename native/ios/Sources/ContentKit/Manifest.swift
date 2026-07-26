import Foundation

public struct ProductMetadata: Codable, Equatable, Sendable {
    public let franchiseName: String
    public let workTitle: String

    public init(franchiseName: String, workTitle: String) {
        self.franchiseName = franchiseName
        self.workTitle = workTitle
    }
}

public struct LocaleDescriptor: Codable, Equatable, Sendable {
    public let identifier: String
    public let fallbackIdentifier: String?

    public init(identifier: String, fallbackIdentifier: String? = nil) {
        self.identifier = identifier
        self.fallbackIdentifier = fallbackIdentifier
    }

    public static let launchEnglish = LocaleDescriptor(identifier: "en")

    public func validate(field: String = "locale") throws {
        guard isCanonicalBCP47Identifier(identifier) else {
            throw ContentValidationError.invalidValue(
                field: "\(field).identifier",
                reason: "must be a canonical BCP-47 language tag"
            )
        }
        if let fallbackIdentifier {
            guard isCanonicalBCP47Identifier(fallbackIdentifier),
                  fallbackIdentifier != identifier else {
                throw ContentValidationError.invalidValue(
                    field: "\(field).fallbackIdentifier",
                    reason: "must be a different canonical BCP-47 language tag"
                )
            }
        }
    }
}

public enum AccessRule: Codable, Equatable, Sendable {
    case included
    case entitlement(EntitlementID)

    private enum Kind: String, Codable {
        case included
        case entitlement
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case entitlementID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .included:
            self = .included
        case .entitlement:
            self = .entitlement(
                try container.decode(EntitlementID.self, forKey: .entitlementID)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .included:
            try container.encode(Kind.included, forKey: .kind)
        case let .entitlement(id):
            try container.encode(Kind.entitlement, forKey: .kind)
            try container.encode(id, forKey: .entitlementID)
        }
    }
}

public enum EntitlementKind: String, Codable, Equatable, Sendable {
    case nonConsumable
}

public struct EntitlementSpec: Codable, Equatable, Sendable {
    public let id: EntitlementID
    public let storeProductID: String
    public let kind: EntitlementKind

    public init(id: EntitlementID, storeProductID: String, kind: EntitlementKind) {
        self.id = id
        self.storeProductID = storeProductID
        self.kind = kind
    }
}

public struct ChapterIndexEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: ChapterID
    public let sequence: Int
    public let title: LocalizedStringSpec
    public let period: LocalizedStringSpec
    public let packageID: PackageID
    public let access: AccessRule

    public init(
        id: ChapterID,
        sequence: Int,
        title: LocalizedStringSpec,
        period: LocalizedStringSpec,
        packageID: PackageID,
        access: AccessRule
    ) {
        self.id = id
        self.sequence = sequence
        self.title = title
        self.period = period
        self.packageID = packageID
        self.access = access
    }
}

public struct ContentPackageSpec: Codable, Equatable, Identifiable, Sendable {
    public let id: PackageID
    public let version: SchemaVersion
    public let chapterIDs: [ChapterID]
    public let maximumInstalledBytes: Int64
    public let minimumRuntime: SchemaVersion
    public let isEssentialInstall: Bool

    public init(
        id: PackageID,
        version: SchemaVersion,
        chapterIDs: [ChapterID],
        maximumInstalledBytes: Int64,
        minimumRuntime: SchemaVersion,
        isEssentialInstall: Bool
    ) {
        self.id = id
        self.version = version
        self.chapterIDs = chapterIDs
        self.maximumInstalledBytes = maximumInstalledBytes
        self.minimumRuntime = minimumRuntime
        self.isEssentialInstall = isEssentialInstall
    }
}

public struct CollectionManifest: Codable, Equatable, Sendable {
    public let schemaVersion: SchemaVersion
    public let collectionID: CollectionID
    public let locale: LocaleDescriptor
    public let product: ProductMetadata
    public let chapters: [ChapterIndexEntry]
    public let packages: [ContentPackageSpec]
    public let entitlements: [EntitlementSpec]

    public init(
        schemaVersion: SchemaVersion,
        collectionID: CollectionID,
        locale: LocaleDescriptor,
        product: ProductMetadata,
        chapters: [ChapterIndexEntry],
        packages: [ContentPackageSpec],
        entitlements: [EntitlementSpec]
    ) {
        self.schemaVersion = schemaVersion
        self.collectionID = collectionID
        self.locale = locale
        self.product = product
        self.chapters = chapters
        self.packages = packages
        self.entitlements = entitlements
    }

    public func validate() throws {
        try requireNonempty(collectionID, field: "collectionID")
        try locale.validate()
        guard schemaVersion.isValid,
              !product.franchiseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !product.workTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContentValidationError.invalidValue(
                field: "collection.metadata",
                reason: "valid schema and product metadata are required"
            )
        }
        try requireUnique(chapters.map(\.id))
        try requireUnique(packages.map(\.id))
        try requireUnique(entitlements.map(\.id))
        guard Set(chapters.map(\.sequence)).count == chapters.count else {
            throw ContentValidationError.invalidValue(
                field: "chapters.sequence",
                reason: "must be unique"
            )
        }

        let chapterIDs = Set(chapters.map { $0.id.rawValue })
        let packageIDs = Set(packages.map { $0.id.rawValue })
        let entitlementIDs = Set(entitlements.map { $0.id.rawValue })

        for chapter in chapters {
            try requireNonempty(chapter.id, field: "chapters.id")
            try chapter.title.validate(field: "chapters.\(chapter.id).title")
            try chapter.period.validate(field: "chapters.\(chapter.id).period")
            guard chapter.sequence > 0 else {
                throw ContentValidationError.invalidValue(
                    field: "chapters",
                    reason: "sequence must be positive"
                )
            }
            guard packageIDs.contains(chapter.packageID.rawValue) else {
                throw ContentValidationError.missingReference(
                    field: "chapters.packageID",
                    identifier: chapter.packageID.rawValue
                )
            }
            if case let .entitlement(id) = chapter.access,
               !entitlementIDs.contains(id.rawValue) {
                throw ContentValidationError.missingReference(
                    field: "chapters.access",
                    identifier: id.rawValue
                )
            }
        }

        for package in packages {
            try requireNonempty(package.id, field: "packages.id")
            try requireUnique(package.chapterIDs)
            guard package.version.isValid, package.minimumRuntime.isValid,
                  package.maximumInstalledBytes > 0, !package.chapterIDs.isEmpty else {
                throw ContentValidationError.invalidValue(
                    field: "packages.maximumInstalledBytes",
                    reason: "must be positive"
                )
            }
            for chapterID in package.chapterIDs {
                try requireNonempty(chapterID, field: "packages.chapterIDs")
            }
            for chapterID in package.chapterIDs where !chapterIDs.contains(chapterID.rawValue) {
                throw ContentValidationError.missingReference(
                    field: "packages.chapterIDs",
                    identifier: chapterID.rawValue
                )
            }
        }

        for entitlement in entitlements {
            try requireNonempty(entitlement.id, field: "entitlements.id")
            guard !entitlement.storeProductID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ContentValidationError.invalidValue(
                    field: "entitlements.storeProductID",
                    reason: "must be authored"
                )
            }
        }

        for chapter in chapters {
            let owningPackages = packages.filter { $0.chapterIDs.contains(chapter.id) }
            guard owningPackages.count == 1, owningPackages.first?.id == chapter.packageID else {
                throw ContentValidationError.invalidValue(
                    field: "chapters.packageID",
                    reason: "each chapter must belong to exactly one declared package"
                )
            }
        }
        try requireConsistentLocalizedStrings(
            chapters.flatMap { [$0.title, $0.period] },
            field: "collection.localizedStrings"
        )
    }

    /// Launch-only gate. Foundation previews may use a partial manifest, but no
    /// production collection can activate without this stricter contract.
    public func validateLaunch() throws {
        try validate()
        guard locale == .launchEnglish,
              collectionID == LaunchContent.collectionID,
              product == .current,
              chapters.count == 24,
              chapters.map(\.sequence).sorted() == Array(1 ... 24),
              chapters.sorted(by: { $0.sequence < $1.sequence }).map(\.id) == LaunchContent.chapterOrder,
              packages.count == 8,
              entitlements.count == 1,
              entitlements[0].kind == .nonConsumable,
              entitlements[0].id == LaunchContent.fullWorkEntitlementID,
              entitlements[0].storeProductID == LaunchContent.fullWorkStoreProductID else {
            throw ContentValidationError.invalidValue(
                field: "collection.launch",
                reason: "must match the generated product, chapter order and permanent entitlement"
            )
        }

        let included = Set(chapters.compactMap { chapter -> ChapterID? in
            if case .included = chapter.access { return chapter.id }
            return nil
        })
        guard included == LaunchContent.freeChapterIDs else {
            throw ContentValidationError.invalidValue(
                field: "collection.chapters.access",
                reason: "included chapters must equal the stable free triad"
            )
        }
        let packageByID = Dictionary(uniqueKeysWithValues: packages.map { ($0.id, $0) })
        var declaredInstalledBytes: Int64 = 0
        for package in packages {
            let result = declaredInstalledBytes.addingReportingOverflow(package.maximumInstalledBytes)
            guard !result.overflow else {
                throw ContentValidationError.invalidValue(
                    field: "collection.packages.maximumInstalledBytes",
                    reason: "aggregate package budget exceeds Int64"
                )
            }
            declaredInstalledBytes = result.partialValue
        }
        guard Set(packageByID.keys) == Set(LaunchContent.packageIDsInDeliveryOrder),
              declaredInstalledBytes <= LaunchContent.maximumInstalledContentBytes,
              LaunchContent.packageIDsInDeliveryOrder.allSatisfy({ packageID in
                  guard let package = packageByID[packageID],
                        let expectedChapterIDs = LaunchContent.packageChapterIDs[packageID],
                        let maximumBytes = LaunchContent.packageMaximumInstalledBytes[packageID] else {
                      return false
                  }
                  return Set(package.chapterIDs) == expectedChapterIDs
                    && package.maximumInstalledBytes <= maximumBytes
                    && package.isEssentialInstall == (packageID == LaunchContent.essentialPackageID)
              }) else {
            throw ContentValidationError.invalidValue(
                field: "collection.packages",
                reason: "must match the generated eight-package ownership and size plan"
            )
        }
        let entitlementID = entitlements[0].id
        guard chapters.allSatisfy({ chapter in
            if LaunchContent.freeChapterIDs.contains(chapter.id) {
                if case .included = chapter.access { return true }
                return false
            }
            if case let .entitlement(id) = chapter.access { return id == entitlementID }
            return false
        }) else {
            throw ContentValidationError.invalidValue(
                field: "collection.chapters.access",
                reason: "every paid chapter must use the single permanent entitlement"
            )
        }
    }
}

private func isCanonicalBCP47Identifier(_ value: String) -> Bool {
    let pattern = #"^(?:[a-z]{2,3}(?:-[A-Z][a-z]{3})?(?:-(?:[A-Z]{2}|[0-9]{3}))?(?:-(?:[a-z0-9]{5,8}|[0-9][a-z0-9]{3}))*(?:-[0-9a-wy-z](?:-[a-z0-9]{2,8})+)*(?:-x(?:-[a-z0-9]{1,8})+)?|x(?:-[a-z0-9]{1,8})+)$"#
    return value.range(of: pattern, options: .regularExpression) != nil
}
