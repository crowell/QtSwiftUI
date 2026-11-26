// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QtSwiftUI",
    products: [
        .library(name: "SwiftUI", targets: ["SwiftUI"]),
        .executable(name: "Conversation", targets: ["Conversation"]),
        .executable(name: "Controls", targets: ["Controls"])
    ],
    targets: [
        .systemLibrary(name: "CQtWidgets", pkgConfig: "Qt6Widgets", providers: [.apt(["qt6-base-dev"])]),
        .target(name: "QtBridge", dependencies: ["CQtWidgets"]),
        .target(name: "CoreGraphics"),
        .target(name: "SwiftUI", dependencies: ["QtBridge", "CoreGraphics"]),
        .executableTarget(name: "Conversation", dependencies: ["SwiftUI"], path: "Examples/Conversation"),
        .executableTarget(name: "Controls", dependencies: ["SwiftUI"], path: "Examples/Controls"),
        .testTarget(name: "SwiftUITests", dependencies: ["SwiftUI", "QtBridge", "Controls", "Conversation"])
    ],
    cxxLanguageStandard: .cxx17
)
