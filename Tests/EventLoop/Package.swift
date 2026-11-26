// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EventLoopProbe",
    dependencies: [.package(name: "QtSwiftUI", path: "../..")],
    targets: [.executableTarget(name: "EventLoopProbe", dependencies: [.product(name: "SwiftUI", package: "QtSwiftUI")])]
)
