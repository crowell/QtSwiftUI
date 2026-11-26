// swift-tools-version:6.2
import Foundation
import PackageDescription

let environment = ProcessInfo.processInfo.environment
let serein = environment["SEREIN_ROOT"] ?? "/linux/serein"
let qt = environment["QTSWIFTUI_ROOT"] ?? "/linux/QtSwiftUI"
let package = Package(name: "StickerCreatorCheck", dependencies: [
    .package(path: qt),
    .package(path: "\(serein)/Packages/SignalUI"),
    .package(path: "\(serein)/Packages/SignalI18n"),
    .package(path: "\(serein)/Packages/SignalMediaService"),
], targets: [.executableTarget(name: "StickerCreatorCheck", dependencies: [
    .product(name: "SwiftUI", package: "QtSwiftUI"),
    .product(name: "SignalUI", package: "SignalUI"),
    .product(name: "SignalI18n", package: "SignalI18n"),
    .product(name: "MediaXPCInterface", package: "SignalMediaService"),
])])
