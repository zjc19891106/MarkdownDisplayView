// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MarkdownDisplayView",
    platforms: [.iOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MarkdownDisplayView",
            targets: ["MarkdownDisplayView"]
        ),

    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", branch: "main"),

    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MarkdownDisplayView",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "MarkdownDisplayView/Sources/MarkdownDisplayView",
            swiftSettings: [
                // SPM自动定义SWIFT_PACKAGE,我们不需要额外设置
            ],
            linkerSettings: [
                .linkedFramework("Combine"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation")
            ]
        ),
        .testTarget(
            name: "MarkdownDisplayViewTests",
            dependencies: ["MarkdownDisplayView"],
            path: "MarkdownDisplayView/Tests/MarkdownDisplayViewTests"
        ),
    ]
)
