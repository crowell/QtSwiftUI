import SwiftUI
import Foundation
import SignalI18n

@main struct MediaCheck: App {
    private static let account = "SAMPLE-ACCOUNT-ID"
    private static let key = "DEMO DEMO DEMO DEMO"
    private let canvas = CommandLine.arguments.contains("--canvas")
    private let image = MediaEditorBitmap(RGBAImage(width: 400, height: 240, pixels: Data(repeating: 255, count: 400 * 240 * 4)))
    private let document = MediaEditorSnapshot(objects: [
        MediaEditorObject(id: 1, kind: .text("Afternoon ferry", style: .outline, hue: 45, fontSize: 32), center: CGPoint(x: 200, y: 170)),
        MediaEditorObject(id: 2, kind: .digitalTime(Date(timeIntervalSince1970: 43200), style: .dark), center: CGPoint(x: 200, y: 88)),
        MediaEditorObject(id: 3, kind: .path(points: [CGPoint(x: -85, y: 6), CGPoint(x: 0, y: -10), CGPoint(x: 85, y: 0)], color: RGBA(0.1, 0.2, 0.5), width: 5, tool: .pen), center: CGPoint(x: 200, y: 200)),
    ], image: MediaEditorImageState(width: 400, height: 240))
    init() {
        let renderer = MediaEditorRenderer(background: image)
        let snapshot = document
        let view = Canvas { context, _ in renderer.draw(snapshot, in: context, zoom: 1) }.frame(width: 400, height: 240)
        let cg = ImageRenderer(content: view).cgImage!
        let pixels = MediaEditorExport.pixels(cg)!
        precondition(pixels.width == 400 && pixels.height == 240)
        let ink = stride(from: 0, to: pixels.rgba.count, by: 4).filter { pixels.rgba[$0] < 200 }.count
        precondition(ink > 250)
        let result = MediaEditorExport.export(document, background: image, caption: "Ferry", isViewOnce: false, isHighQuality: true)!
        precondition(result.data.starts(with: [0xff, 0xd8]) && result.width == 400 && !result.blurHash.isEmpty)
        let pdf = AccountKeysPDF.generate(serviceId: Self.account, backupKey: Self.key, i18n: Localizer(locale: "en"))
        precondition(pdf.starts(with: Data("%PDF".utf8)))
        if let folder = ProcessInfo.processInfo.environment["SEREIN_EXPORT_DIR"] {
            try! pdf.write(to: URL(fileURLWithPath: folder).appendingPathComponent("reference.pdf"))
        }
    }
    var body: some Scene {
        WindowGroup("Serein") {
            if canvas {
                Canvas { context, _ in MediaEditorRenderer(background: image).draw(document, in: context, zoom: 1) }
            } else {
                SignalAccountKeys(serviceId: Self.account, backupKey: Self.key, saveAccountKeysPDF: {
                    let pdf = AccountKeysPDF.generate(serviceId: Self.account, backupKey: Self.key, i18n: Localizer(locale: "en"))
                    let folder = ProcessInfo.processInfo.environment["SEREIN_EXPORT_DIR"] ?? FileManager.default.temporaryDirectory.path
                    let url = URL(fileURLWithPath: folder).appendingPathComponent(AccountKeysPDF.fileName)
                    do { try pdf.write(to: url); print("Saved sample account keys to \(url.path)") }
                    catch { print("Could not save sample PDF: \(error)") }
                })
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color.white)
                .environment(\.i18n, Localizer(locale: "en"))
            }
        }.defaultSize(width: canvas ? 400 : 430, height: canvas ? 240 : 350)
    }
}
