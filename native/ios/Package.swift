// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LongWestNative",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS("26.4"),
    ],
    products: [
        .library(name: "ContentKit", targets: ["ContentKit"]),
        .library(name: "JourneyDomain", targets: ["JourneyDomain"]),
        .library(name: "JourneyContent", targets: ["JourneyContent"]),
        .library(name: "JourneyPersistence", targets: ["JourneyPersistence"]),
        .library(name: "ProgressStore", targets: ["ProgressStore"]),
        .library(name: "ContentDelivery", targets: ["ContentDelivery"]),
        .library(name: "CommerceKit", targets: ["CommerceKit"]),
        .library(name: "ReleaseDiscovery", targets: ["ReleaseDiscovery"]),
        .library(name: "DramaticAudio", targets: ["DramaticAudio"]),
        .library(name: "SceneRuntime", targets: ["SceneRuntime"]),
        .library(name: "JourneyAccessibility", targets: ["JourneyAccessibility"]),
        .library(name: "ChapterRuntime", targets: ["ChapterRuntime"]),
        .library(name: "ExperiencePreferences", targets: ["ExperiencePreferences"]),
        .library(name: "QualityInstrumentation", targets: ["QualityInstrumentation"]),
    ],
    targets: [
        .target(name: "ContentKit"),
        .target(
            name: "JourneyDomain",
            dependencies: ["ContentKit"]
        ),
        .target(
            name: "JourneyContent",
            dependencies: ["ContentDelivery", "ContentKit", "JourneyDomain"]
        ),
        .target(
            name: "JourneyPersistence",
            dependencies: [
                "ContentDelivery",
                "ContentKit",
                "JourneyContent",
                "ProgressStore",
            ]
        ),
        .target(
            name: "ProgressStore",
            dependencies: ["ContentKit", "JourneyDomain"]
        ),
        .target(
            name: "ContentDelivery",
            dependencies: ["ContentKit", "ExperiencePreferences"]
        ),
        .target(
            name: "CommerceKit",
            dependencies: ["ContentKit"]
        ),
        .target(
            name: "ReleaseDiscovery",
            dependencies: [
                "ContentDelivery",
                "ContentKit",
                "ExperiencePreferences",
            ]
        ),
        .target(
            name: "DramaticAudio",
            dependencies: [
                "ContentKit",
                "ExperiencePreferences",
                "JourneyContent",
                "JourneyDomain",
                "ProgressStore",
                "QualityInstrumentation",
            ]
        ),
        .target(
            name: "SceneRuntime",
            dependencies: ["ContentKit", "JourneyDomain", "QualityInstrumentation"],
            linkerSettings: [
                .linkedFramework("ImageIO"),
            ]
        ),
        .target(
            name: "JourneyAccessibility",
            dependencies: ["ContentKit", "JourneyDomain"]
        ),
        .target(
            name: "ChapterRuntime",
            dependencies: [
                "ContentKit",
                "DramaticAudio",
                "JourneyAccessibility",
                "JourneyContent",
                "JourneyDomain",
                "ProgressStore",
                "SceneRuntime",
            ]
        ),
        .target(name: "ExperiencePreferences"),
        .target(name: "QualityInstrumentation"),
        .target(
            name: "ContentKitTestSupport",
            dependencies: ["ContentKit"]
        ),
        .testTarget(
            name: "ContentKitTests",
            dependencies: ["ContentKit", "ContentKitTestSupport"]
        ),
        .testTarget(
            name: "JourneyDomainTests",
            dependencies: ["ContentKit", "ContentKitTestSupport", "JourneyDomain"]
        ),
        .testTarget(
            name: "JourneyContentTests",
            dependencies: [
                "ContentKit",
                "ContentKitTestSupport",
                "ContentDelivery",
                "JourneyDomain",
                "JourneyContent",
                "JourneyPersistence",
            ]
        ),
        .testTarget(
            name: "ProgressStoreTests",
            dependencies: [
                "ContentKit",
                "ContentKitTestSupport",
                "JourneyDomain",
                "JourneyPersistence",
                "ProgressStore",
            ]
        ),
        .testTarget(
            name: "ContentDeliveryTests",
            dependencies: [
                "ContentKit",
                "ContentKitTestSupport",
                "ContentDelivery",
                "ExperiencePreferences",
            ]
        ),
        .testTarget(
            name: "CommerceKitTests",
            dependencies: ["ContentKit", "CommerceKit"]
        ),
        .testTarget(
            name: "ReleaseDiscoveryTests",
            dependencies: [
                "ContentDelivery",
                "ContentKit",
                "ExperiencePreferences",
                "ReleaseDiscovery",
            ]
        ),
        .testTarget(
            name: "DramaticAudioTests",
            dependencies: [
                "ContentKit",
                "DramaticAudio",
                "ExperiencePreferences",
                "JourneyContent",
                "JourneyDomain",
                "ProgressStore",
            ]
        ),
        .testTarget(
            name: "SceneRuntimeTests",
            dependencies: ["ContentKit", "ContentKitTestSupport", "JourneyDomain", "SceneRuntime"]
        ),
        .testTarget(
            name: "JourneyAccessibilityTests",
            dependencies: ["ContentKit", "ContentKitTestSupport", "JourneyDomain", "JourneyAccessibility"]
        ),
        .testTarget(
            name: "ChapterRuntimeTests",
            dependencies: [
                "ChapterRuntime",
                "ContentDelivery",
                "ContentKit",
                "ContentKitTestSupport",
                "DramaticAudio",
                "JourneyAccessibility",
                "JourneyContent",
                "JourneyDomain",
                "ProgressStore",
                "SceneRuntime",
            ]
        ),
        .testTarget(
            name: "ExperiencePreferencesTests",
            dependencies: ["ExperiencePreferences"]
        ),
        .testTarget(
            name: "QualityInstrumentationTests",
            dependencies: ["QualityInstrumentation"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
