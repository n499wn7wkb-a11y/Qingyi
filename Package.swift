// swift-tools-version: 6.2
import PackageDescription

// Requires PackageDescription 6.2 for `.macOS(.v26)` and the target's
// language-mode pin. The code itself stays in Swift 5 mode: jumping to Swift 6
// would turn every pre-existing concurrency warning into a hard error, which is
// a separate migration and has nothing to do with the glass work.
let package = Package(
    name: "Qingyi",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "Qingyi", targets: ["Qingyi"])],
    targets: [
        .target(name: "TranslationCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Qingyi", dependencies: ["TranslationCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
