// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TookMac",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TookCore", targets: ["TookCore"]),
               .executable(name: "TookMac", targets: ["TookMac"])],
    targets: [
        .target(name: "TookCore"),
        .executableTarget(name: "TookMac", dependencies: ["TookCore"]),
        .testTarget(name: "TookCoreTests", dependencies: ["TookCore"], path: "Tests")
    ]
)
