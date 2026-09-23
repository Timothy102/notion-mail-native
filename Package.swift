// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Mail",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "Mail", path: "Sources/Mail", resources: [.copy("Fonts")])
    ]
)
