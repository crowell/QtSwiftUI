// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "QtSwiftUI",
    products: [
        .library(name: "SwiftUI", targets: ["SwiftUI"]),
        .library(name: "Combine", targets: ["Combine"]),
        .executable(name: "Conversation", targets: ["Conversation"]),
        .executable(name: "Controls", targets: ["Controls"])
    ],
    dependencies: [
        .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0")
    ],
    targets: [
        .macro(name: "QtSwiftUIMacros", dependencies: [
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
        ]),
        .systemLibrary(name: "CQtWidgets", pkgConfig: "Qt6Widgets", providers: [.apt(["qt6-base-dev"])]),
        .target(name: "QtBridge", dependencies: ["CQtWidgets"]),
        .target(name: "CoreGraphics", dependencies: ["QtBridge"]),
        .target(name: "UniformTypeIdentifiers"),
        .target(name: "CoreTransferable", dependencies: ["UniformTypeIdentifiers"]),
        .target(name: "Combine", dependencies: [
            .product(name: "OpenCombine", package: "OpenCombine"),
            .product(name: "OpenCombineFoundation", package: "OpenCombine"),
            .product(name: "OpenCombineDispatch", package: "OpenCombine")
        ]),
        .target(name: "SwiftUI", dependencies: ["Combine", "QtBridge", "CoreGraphics", "UniformTypeIdentifiers", "CoreTransferable", "QtSwiftUIMacros"]),
        .executableTarget(name: "Conversation", dependencies: ["SwiftUI"], path: "Examples/Conversation"),
        .executableTarget(name: "Controls", dependencies: ["SwiftUI"], path: "Examples/Controls"),
        .testTarget(name: "SwiftUITests", dependencies: ["SwiftUI", "Combine", "QtBridge", "Controls", "Conversation"])
    ],
    cxxLanguageStandard: .cxx17
)
