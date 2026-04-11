// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mail-cli",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/kscott/get-clear.git", branch: "main"),
        .package(url: "https://github.com/Quick/Quick.git", from: "7.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "13.0.0"),
    ],
    targets: [
        // Pure logic — no framework dependencies, fully testable
        .target(
            name: "MailLib",
            path: "Sources/MailLib"
        ),
        // Main binary — depends on MailLib plus Contacts
        .executableTarget(
            name: "mail-bin",
            dependencies: [
                "MailLib",
                .product(name: "GetClearKit", package: "get-clear"),
            ],
            path: "Sources/MailCLI",
            linkerSettings: [
                .linkedFramework("Contacts"),
            ]
        ),
        // Test suite — run via: swift test
        .testTarget(
            name: "MailLibTests",
            dependencies: [
                "MailLib",
                .product(name: "Quick", package: "Quick"),
                .product(name: "Nimble", package: "Nimble"),
            ],
            path: "Tests/MailLibTests"
        ),
    ]
)
