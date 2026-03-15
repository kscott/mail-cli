// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mail-cli",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/kscott/get-clear", branch: "main"),
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
        // Test runner — executable rather than XCTest target so it works
        // with just the Swift CLI toolchain (no Xcode required)
        .executableTarget(
            name: "mail-tests",
            dependencies: ["MailLib"],
            path: "Tests/MailLibTests"
        ),
    ]
)
