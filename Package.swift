// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusMenus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "StatusMenus", targets: ["StatusMenus"]),
        .executable(name: "agentdock", targets: ["AgentDockCLI"]),
        .library(name: "StatusMenusCore", targets: ["StatusMenusCore"])
    ],
    targets: [
        .target(name: "StatusMenusCore"),
        .executableTarget(
            name: "StatusMenus",
            dependencies: ["StatusMenusCore"]
        ),
        .executableTarget(
            name: "AgentDockCLI",
            dependencies: ["StatusMenusCore"]
        ),
        .executableTarget(
            name: "StatusMenusCoreChecks",
            dependencies: ["StatusMenusCore"],
            path: "Tests/StatusMenusCoreChecks"
        )
    ],
    swiftLanguageModes: [.v5]
)
