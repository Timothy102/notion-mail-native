// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Mail",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "MailCore", targets: ["MailCore"])],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift", from: "7.9.0")],
    targets: [
        .target(name: "MailCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "Mail", dependencies: ["MailCore", .product(name: "GRDB", package: "GRDB.swift")], resources: [.copy("Fonts"), .copy("Art")]),
        .testTarget(name: "MailTests", dependencies: ["MailCore"], resources: [.copy("Fixtures")]),
    ]
)
