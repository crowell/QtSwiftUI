// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "QtSwiftUI",
    products: [
        .library(name: "SwiftUI", targets: ["SwiftUI"]),
        .executable(name: "Conversation", targets: ["Conversation"]),
        .executable(name: "Controls", targets: ["Controls"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0")
    ],
    targets: [
        .macro(name: "QtSwiftUIMacros", dependencies: [
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
        ]),
        .systemLibrary(name: "CQtWidgets", pkgConfig: "Qt6Widgets", providers: [.apt(["qt6-base-dev"])]),
        .target(name: "QtBridge", dependencies: ["CQtWidgets"]),
        .target(name: "CoreGraphics"),
        .target(name: "UniformTypeIdentifiers"),
        .target(name: "SwiftUI", dependencies: ["QtBridge", "CoreGraphics", "UniformTypeIdentifiers", "QtSwiftUIMacros"]),
        .executableTarget(name: "Conversation", dependencies: ["SwiftUI"], path: "Examples/Conversation"),
        .executableTarget(name: "Controls", dependencies: ["SwiftUI"], path: "Examples/Controls"),
        .testTarget(name: "SwiftUITests", dependencies: ["SwiftUI", "QtBridge", "Controls", "Conversation"])
    ],
    cxxLanguageStandard: .cxx17
)
