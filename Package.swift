// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vision-ocr-mcp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "vision-ocr-mcp", targets: ["VisionOCRMCP"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "VisionOCRMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "Logging", package: "swift-log"),
            ],
            resources: [
                .copy("Resources/ui")
            ]
        ),
        .testTarget(
            name: "VisionOCRMCPTests",
            dependencies: ["VisionOCRMCP"],
            path: "Tests/VisionOCRMCPTests"
        ),
    ]
)
