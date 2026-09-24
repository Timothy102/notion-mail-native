// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Mail",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "MailCore", targets: ["MailCore"]),
        .executable(name: "nmail-mcp", targets: ["nmail-mcp"]),
    ],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift", from: "7.9.0")],
    targets: [
        .target(name: "MailCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "Mail", dependencies: ["MailCore", .product(name: "GRDB", package: "GRDB.swift")], resources: [.copy("Fonts"), .copy("Art")]),
        .target(name: "MailMCP", dependencies: ["MailCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "nmail-mcp", dependencies: ["MailMCP"]),
        .testTarget(name: "MailTests", dependencies: ["MailCore", "MailMCP"], resources: [.copy("Fixtures")]),
    ]
)
