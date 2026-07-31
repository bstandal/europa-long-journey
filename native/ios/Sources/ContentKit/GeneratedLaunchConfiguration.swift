// Generated from the Phase 0 catalog and delivery plan. Do not edit by hand.

public enum LaunchContent {
    public static let collectionID: CollectionID = "collection-01"
    public static let essentialPackageID: PackageID = "essential-free-v1"
    public static let fullWorkEntitlementID: EntitlementID = "launch-complete-work"
    public static let fullWorkStoreProductID = "com.thelongwest.ios.unlock.collection01"
    public static let completeInstalledWorkBytes: Int64 = 6000000000

    public static let chapterOrder: [ChapterID] = [
        "first-farmers",
        "steppe-comes-west",
        "bronze-europe",
        "greece-and-the-citizen",
        "rome-gathers-europe",
        "empire-takes-cross",
        "europe-reborn",
        "papal-revolution",
        "society-beyond-kin",
        "medieval-commercial-revolution",
        "hanseatic-north",
        "empire-many-liberties",
        "europe-holds-the-line",
        "europe-turns-seaward",
        "reformation",
        "habsburg-europe",
        "scientific-revolution",
        "dutch-republic",
        "enlightenment-public-opinion",
        "rivalry-industrial-breakthrough",
        "european-world",
        "europe-at-war",
        "continent-rebuilt",
        "europe-returns",
    ]

    public static let freeChapterIDs: Set<ChapterID> = [
        "first-farmers",
        "europe-holds-the-line",
        "european-world",
    ]

    public static let packageIDsInDeliveryOrder: [PackageID] = [
        "essential-free-v1",
        "paid-pack-01",
        "paid-pack-02",
        "paid-pack-03",
        "paid-pack-04",
        "paid-pack-05",
        "paid-pack-06",
        "paid-pack-07",
    ]

    public static let packageChapterIDs: [PackageID: Set<ChapterID>] = [
        "essential-free-v1": [
            "first-farmers",
            "europe-holds-the-line",
            "european-world",
        ],
        "paid-pack-01": [
            "steppe-comes-west",
            "bronze-europe",
            "greece-and-the-citizen",
        ],
        "paid-pack-02": [
            "rome-gathers-europe",
            "empire-takes-cross",
            "europe-reborn",
        ],
        "paid-pack-03": [
            "papal-revolution",
            "society-beyond-kin",
            "medieval-commercial-revolution",
        ],
        "paid-pack-04": [
            "hanseatic-north",
            "empire-many-liberties",
            "europe-turns-seaward",
        ],
        "paid-pack-05": [
            "reformation",
            "habsburg-europe",
            "scientific-revolution",
        ],
        "paid-pack-06": [
            "dutch-republic",
            "enlightenment-public-opinion",
            "rivalry-industrial-breakthrough",
        ],
        "paid-pack-07": [
            "europe-at-war",
            "continent-rebuilt",
            "europe-returns",
        ],
    ]

    public static let packageMaximumInstalledBytes: [PackageID: Int64] = [
        "essential-free-v1": 750000000,
        "paid-pack-01": 750000000,
        "paid-pack-02": 750000000,
        "paid-pack-03": 750000000,
        "paid-pack-04": 750000000,
        "paid-pack-05": 750000000,
        "paid-pack-06": 750000000,
        "paid-pack-07": 750000000,
    ]

    public static let launchChapters: [ChapterIndexEntry] = [
        ChapterIndexEntry(
            id: "first-farmers",
            sequence: 1,
            title: LocalizedStringSpec(
                id: "chapter-first-farmers-title",
                launchEnglish: "The First Farmers"
            ),
            period: LocalizedStringSpec(
                id: "chapter-first-farmers-period",
                launchEnglish: "7000–3300 BC"
            ),
            packageID: "essential-free-v1",
            access: .included
        ),
        ChapterIndexEntry(
            id: "steppe-comes-west",
            sequence: 2,
            title: LocalizedStringSpec(
                id: "chapter-steppe-comes-west-title",
                launchEnglish: "The Steppe Comes West"
            ),
            period: LocalizedStringSpec(
                id: "chapter-steppe-comes-west-period",
                launchEnglish: "3300–2000 BC"
            ),
            packageID: "paid-pack-01",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "bronze-europe",
            sequence: 3,
            title: LocalizedStringSpec(
                id: "chapter-bronze-europe-title",
                launchEnglish: "Bronze Europe"
            ),
            period: LocalizedStringSpec(
                id: "chapter-bronze-europe-period",
                launchEnglish: "2500–500 BC"
            ),
            packageID: "paid-pack-01",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "greece-and-the-citizen",
            sequence: 4,
            title: LocalizedStringSpec(
                id: "chapter-greece-and-the-citizen-title",
                launchEnglish: "Greece and the Citizen"
            ),
            period: LocalizedStringSpec(
                id: "chapter-greece-and-the-citizen-period",
                launchEnglish: "800–146 BC"
            ),
            packageID: "paid-pack-01",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "rome-gathers-europe",
            sequence: 5,
            title: LocalizedStringSpec(
                id: "chapter-rome-gathers-europe-title",
                launchEnglish: "Rome Gathers Europe"
            ),
            period: LocalizedStringSpec(
                id: "chapter-rome-gathers-europe-period",
                launchEnglish: "509 BC–AD 212"
            ),
            packageID: "paid-pack-02",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "empire-takes-cross",
            sequence: 6,
            title: LocalizedStringSpec(
                id: "chapter-empire-takes-cross-title",
                launchEnglish: "The Empire Takes the Cross"
            ),
            period: LocalizedStringSpec(
                id: "chapter-empire-takes-cross-period",
                launchEnglish: "AD 312–565"
            ),
            packageID: "paid-pack-02",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "europe-reborn",
            sequence: 7,
            title: LocalizedStringSpec(
                id: "chapter-europe-reborn-title",
                launchEnglish: "Europe Reborn"
            ),
            period: LocalizedStringSpec(
                id: "chapter-europe-reborn-period",
                launchEnglish: "AD 500–1000"
            ),
            packageID: "paid-pack-02",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "papal-revolution",
            sequence: 8,
            title: LocalizedStringSpec(
                id: "chapter-papal-revolution-title",
                launchEnglish: "The Papal Revolution"
            ),
            period: LocalizedStringSpec(
                id: "chapter-papal-revolution-period",
                launchEnglish: "AD 1046–1123"
            ),
            packageID: "paid-pack-03",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "society-beyond-kin",
            sequence: 9,
            title: LocalizedStringSpec(
                id: "chapter-society-beyond-kin-title",
                launchEnglish: "A Society Beyond Kin"
            ),
            period: LocalizedStringSpec(
                id: "chapter-society-beyond-kin-period",
                launchEnglish: "AD 500–1300"
            ),
            packageID: "paid-pack-03",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "medieval-commercial-revolution",
            sequence: 10,
            title: LocalizedStringSpec(
                id: "chapter-medieval-commercial-revolution-title",
                launchEnglish: "The Medieval Commercial Revolution"
            ),
            period: LocalizedStringSpec(
                id: "chapter-medieval-commercial-revolution-period",
                launchEnglish: "AD 950–1350"
            ),
            packageID: "paid-pack-03",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "hanseatic-north",
            sequence: 11,
            title: LocalizedStringSpec(
                id: "chapter-hanseatic-north-title",
                launchEnglish: "The Hanseatic North"
            ),
            period: LocalizedStringSpec(
                id: "chapter-hanseatic-north-period",
                launchEnglish: "AD 1150–1500"
            ),
            packageID: "paid-pack-04",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "empire-many-liberties",
            sequence: 12,
            title: LocalizedStringSpec(
                id: "chapter-empire-many-liberties-title",
                launchEnglish: "The Empire of Many Liberties"
            ),
            period: LocalizedStringSpec(
                id: "chapter-empire-many-liberties-period",
                launchEnglish: "AD 962–1806"
            ),
            packageID: "paid-pack-04",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "europe-holds-the-line",
            sequence: 13,
            title: LocalizedStringSpec(
                id: "chapter-europe-holds-the-line-title",
                launchEnglish: "The Frontiers Hold"
            ),
            period: LocalizedStringSpec(
                id: "chapter-europe-holds-the-line-period",
                launchEnglish: "AD 711–1699"
            ),
            packageID: "essential-free-v1",
            access: .included
        ),
        ChapterIndexEntry(
            id: "europe-turns-seaward",
            sequence: 14,
            title: LocalizedStringSpec(
                id: "chapter-europe-turns-seaward-title",
                launchEnglish: "Europe Turns Seaward"
            ),
            period: LocalizedStringSpec(
                id: "chapter-europe-turns-seaward-period",
                launchEnglish: "AD 1415–1700"
            ),
            packageID: "paid-pack-04",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "reformation",
            sequence: 15,
            title: LocalizedStringSpec(
                id: "chapter-reformation-title",
                launchEnglish: "The Reformation"
            ),
            period: LocalizedStringSpec(
                id: "chapter-reformation-period",
                launchEnglish: "AD 1517–1648"
            ),
            packageID: "paid-pack-05",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "habsburg-europe",
            sequence: 16,
            title: LocalizedStringSpec(
                id: "chapter-habsburg-europe-title",
                launchEnglish: "Habsburg Europe"
            ),
            period: LocalizedStringSpec(
                id: "chapter-habsburg-europe-period",
                launchEnglish: "AD 1526–1918"
            ),
            packageID: "paid-pack-05",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "scientific-revolution",
            sequence: 17,
            title: LocalizedStringSpec(
                id: "chapter-scientific-revolution-title",
                launchEnglish: "The Scientific Revolution"
            ),
            period: LocalizedStringSpec(
                id: "chapter-scientific-revolution-period",
                launchEnglish: "AD 1543–1700"
            ),
            packageID: "paid-pack-05",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "dutch-republic",
            sequence: 18,
            title: LocalizedStringSpec(
                id: "chapter-dutch-republic-title",
                launchEnglish: "The Dutch Republic"
            ),
            period: LocalizedStringSpec(
                id: "chapter-dutch-republic-period",
                launchEnglish: "AD 1572–1713"
            ),
            packageID: "paid-pack-06",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "enlightenment-public-opinion",
            sequence: 19,
            title: LocalizedStringSpec(
                id: "chapter-enlightenment-public-opinion-title",
                launchEnglish: "The Enlightenment"
            ),
            period: LocalizedStringSpec(
                id: "chapter-enlightenment-public-opinion-period",
                launchEnglish: "AD 1680–1789"
            ),
            packageID: "paid-pack-06",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "rivalry-industrial-breakthrough",
            sequence: 20,
            title: LocalizedStringSpec(
                id: "chapter-rivalry-industrial-breakthrough-title",
                launchEnglish: "Rivalry and the Industrial Breakthrough"
            ),
            period: LocalizedStringSpec(
                id: "chapter-rivalry-industrial-breakthrough-period",
                launchEnglish: "AD 1709–1862"
            ),
            packageID: "paid-pack-06",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "european-world",
            sequence: 21,
            title: LocalizedStringSpec(
                id: "chapter-european-world-title",
                launchEnglish: "The European World"
            ),
            period: LocalizedStringSpec(
                id: "chapter-european-world-period",
                launchEnglish: "AD 1802–1914"
            ),
            packageID: "essential-free-v1",
            access: .included
        ),
        ChapterIndexEntry(
            id: "europe-at-war",
            sequence: 22,
            title: LocalizedStringSpec(
                id: "chapter-europe-at-war-title",
                launchEnglish: "The European Civil War"
            ),
            period: LocalizedStringSpec(
                id: "chapter-europe-at-war-period",
                launchEnglish: "AD 1871–1945"
            ),
            packageID: "paid-pack-07",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "continent-rebuilt",
            sequence: 23,
            title: LocalizedStringSpec(
                id: "chapter-continent-rebuilt-title",
                launchEnglish: "The Continent Rebuilt"
            ),
            period: LocalizedStringSpec(
                id: "chapter-continent-rebuilt-period",
                launchEnglish: "AD 1945–1989"
            ),
            packageID: "paid-pack-07",
            access: .entitlement(fullWorkEntitlementID)
        ),
        ChapterIndexEntry(
            id: "europe-returns",
            sequence: 24,
            title: LocalizedStringSpec(
                id: "chapter-europe-returns-title",
                launchEnglish: "Europe Returns"
            ),
            period: LocalizedStringSpec(
                id: "chapter-europe-returns-period",
                launchEnglish: "AD 1989–20 July 2026"
            ),
            packageID: "paid-pack-07",
            access: .entitlement(fullWorkEntitlementID)
        ),
    ]

    public static let launchPackages: [ContentPackageSpec] = [
        ContentPackageSpec(
            id: "essential-free-v1",
            version: SchemaVersion(major: 1),
            chapterIDs: [
                "first-farmers",
                "europe-holds-the-line",
                "european-world",
            ],
            maximumInstalledBytes: 750000000,
            minimumRuntime: SchemaVersion(major: 1),
            isEssentialInstall: true
        ),
        ContentPackageSpec(
            id: "paid-pack-01",
            version: SchemaVersion(major: 1),
            chapterIDs: [
                "steppe-comes-west",
                "bronze-europe",
                "greece-and-the-citizen",
            ],
            maximumInstalledBytes: 750000000,
            minimumRuntime: SchemaVersion(major: 1),
            isEssentialInstall: false
        ),
        ContentPackageSpec(
            id: "paid-pack-02",
            version: SchemaVersion(major: 1),
            chapterIDs: [
                "rome-gathers-europe",
                "empire-takes-cross",
                "europe-reborn",
            ],
            maximumInstalledBytes: 750000000,
            minimumRuntime: SchemaVersion(major: 1),
            isEssentialInstall: false
        ),
        ContentPackageSpec(
            id: "paid-pack-03",
            version: SchemaVersion(major: 1),
            chapterIDs: [
                "papal-revolution",
                "society-beyond-kin",
                "medieval-commercial-revolution",
            ],
            maximumInstalledBytes: 750000000,
            minimumRuntime: SchemaVersion(major: 1),
            isEssentialInstall: false
        ),
        ContentPackageSpec(
            id: "paid-pack-04",
            version: SchemaVersion(major: 1),
            chapterIDs: [
                "hanseatic-north",
                "empire-many-liberties",
                "europe-turns-seaward",
            ],
            maximumInstalledBytes: 750000000,
            minimumRuntime: SchemaVersion(major: 1),
            isEssentialInstall: false
        ),
        ContentPackageSpec(
            id: "paid-pack-05",
            version: SchemaVersion(major: 1),
            chapterIDs: [
                "reformation",
                "habsburg-europe",
                "scientific-revolution",
            ],
            maximumInstalledBytes: 750000000,
            minimumRuntime: SchemaVersion(major: 1),
            isEssentialInstall: false
        ),
        ContentPackageSpec(
            id: "paid-pack-06",
            version: SchemaVersion(major: 1),
            chapterIDs: [
                "dutch-republic",
                "enlightenment-public-opinion",
                "rivalry-industrial-breakthrough",
            ],
            maximumInstalledBytes: 750000000,
            minimumRuntime: SchemaVersion(major: 1),
            isEssentialInstall: false
        ),
        ContentPackageSpec(
            id: "paid-pack-07",
            version: SchemaVersion(major: 1),
            chapterIDs: [
                "europe-at-war",
                "continent-rebuilt",
                "europe-returns",
            ],
            maximumInstalledBytes: 650000000,
            minimumRuntime: SchemaVersion(major: 1),
            isEssentialInstall: false
        ),
    ]

    public static let collectionManifest = CollectionManifest(
        schemaVersion: SchemaVersion(major: 1),
        collectionID: collectionID,
        locale: .launchEnglish,
        product: .current,
        chapters: launchChapters,
        packages: launchPackages,
        entitlements: [
            EntitlementSpec(
                id: fullWorkEntitlementID,
                storeProductID: fullWorkStoreProductID,
                kind: .nonConsumable
            ),
        ]
    )
}
