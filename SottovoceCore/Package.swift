// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SottovoceCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SottovoceCore", targets: ["SottovoceCore"]),
    ],
    targets: [
        .target(name: "SottovoceCore"),
        .testTarget(name: "SottovoceCoreTests", dependencies: ["SottovoceCore"]),
    ]
)
