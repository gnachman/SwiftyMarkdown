// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "SwiftyMarkdown",
    platforms: [
        .iOS(SupportedPlatform.IOSVersion.v11),
        .tvOS(SupportedPlatform.TVOSVersion.v11),
		.macOS(.v10_12),
		.watchOS(.v4)
    ],
    products: [
        .library(name: "SwiftyMarkdown", targets: ["SwiftyMarkdown"]),
        .executable(name: "markdown2png", targets: ["markdown2png"]),
    ],
    targets: [
        .target(name: "SwiftyMarkdown"),
		.testTarget(name: "SwiftyMarkdownTests", dependencies: ["SwiftyMarkdown"]),
        .target(name: "markdown2png", dependencies: ["SwiftyMarkdown"], path: "Tools/markdown2png")
    ]
)
