// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "FileMirror",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "FileMirror",
            targets: ["FileMirror"]),
        .library(
            name: "FileMirrorDiscovery",
            targets: ["FileMirrorDiscovery"]),
        .library(
            name: "FileMirrorProtocol",
            targets: ["FileMirrorProtocol"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "FileMirrorProtocol",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                "librsync"
            ],
            exclude: [
                "Protos/FileMirrorProtocol.proto"
            ]),
        .target(
            name: "FileMirror",
            dependencies: [
                "FileMirrorProtocol",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
            ]),
        .target(
            name: "FileMirrorDiscovery",
            dependencies: ["FileMirrorProtocol"]),
        .binaryTarget(
            name: "librsync",
            path: "Frameworks/librsync.xcframework"
        ),
        .testTarget(
            name: "FileMirrorTests",
            dependencies: ["FileMirror"]
        ),
    ]
)
