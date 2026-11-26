// swift-tools-version:6.2
import PackageDescription
let package = Package(name: "ComposerCheck", dependencies: [
    .package(path: "QtSwiftUI"), .package(path: "SignalCodecs"), .package(path: "SignalI18n"),
], targets: [.executableTarget(name: "ComposerCheck", dependencies: [
    .product(name: "SwiftUI", package: "QtSwiftUI"), .product(name: "CodecCore", package: "SignalCodecs"), .product(name: "SignalI18n", package: "SignalI18n"),
], resources: [.copy("Fonts"), .copy("emoji-data.json")], swiftSettings: [.strictMemorySafety(), .treatAllWarnings(as: .error)])])
