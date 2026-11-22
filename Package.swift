// swift-tools-version:6.0
import PackageDescription

// LigeroCore is pure Swift (Foundation only) and builds and tests on Linux.
// The app target needs AppKit, so it only exists when the manifest is
// evaluated on macOS. That keeps `swift test` working in the Linux CI job.
var targets: [Target] = [
    .target(name: "LigeroCore"),
    .testTarget(name: "LigeroCoreTests", dependencies: ["LigeroCore"]),
]

var products: [Product] = [
    .library(name: "LigeroCore", targets: ["LigeroCore"]),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "Ligero",
        dependencies: ["LigeroCore"],
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("Carbon"),
            .linkedFramework("ApplicationServices"),
            .linkedFramework("IOKit"),
            .linkedFramework("ServiceManagement"),
        ]
    )
)
products.append(.executable(name: "Ligero", targets: ["Ligero"]))
#endif

let package = Package(
    name: "Ligero",
    // Localized strings live in Resources/<lang>.lproj and are copied into
    // Ligero.app/Contents/Resources by scripts/bundle.sh (see SPEC §2.7).
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: products,
    targets: targets
)
