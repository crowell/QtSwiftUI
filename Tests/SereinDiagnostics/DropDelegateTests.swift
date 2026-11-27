import SwiftUI
import UniformTypeIdentifiers
import XCTest
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

@MainActor private final class DropRecorder: DropDelegate {
    var events: [String] = []
    var canAccept = true
    var proposal: DropProposal? = .init(operation: .move)
    var text: String?
    var lastPoint = CGPoint.zero

    func validateDrop(info: DropInfo) -> Bool {
        events.append("validate")
        return canAccept && info.hasItemsConforming(to: [UTType.text]) && !info.hasItemsConforming(to: [UTType.image])
    }
    func dropEntered(info: DropInfo) { events.append("enter") }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        events.append("update")
        return proposal
    }
    func dropExited(info: DropInfo) { events.append("exit") }
    func performDrop(info: DropInfo) -> Bool {
        events.append("perform")
        lastPoint = info.location
        guard let item = info.itemProviders(for: [UTType.text]).first else { return false }
        _ = item.loadDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, _ in
            let value = data.flatMap { String(data: $0, encoding: .utf8) }
            Task { @MainActor in self.text = value }
        }
        return true
    }
}

@MainActor private final class FileDropRecorder: DropDelegate {
    var values: [Int: Data] = [:]
    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.fileURL])
        for (index, item) in providers.enumerated() {
            _ = item.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                Task { @MainActor in self.values[index] = data }
            }
        }
        return !providers.isEmpty
    }
}

final class DropDelegateTests: XCTestCase {
    @MainActor func testFileDropOffersOneProviderPerURLInOrder() async throws {
        let urls = [URL(fileURLWithPath: "/tmp/Ferry Crew.pdf"), URL(fileURLWithPath: "/tmp/Harbor.txt")]
        let delegate = FileDropRecorder()
        let content = HStack(spacing: 0) {
            Color.blue.frame(width: 60, height: 50).onDrag {
                #if os(Linux)
                let list = urls.map(\.absoluteString).joined(separator: "\r\n") + "\r\n"
                return NSItemProvider(item: Data(list.utf8) as NSData, typeIdentifier: UTType.url.identifier)
                #else
                return NSItemProvider(object: urls[0] as NSURL)
                #endif
            }
            Color.red.frame(width: 80, height: 50).onDrop(of: [.fileURL], delegate: delegate)
        }
        let window = try await ScreenWindow(content, width: 140, height: 50)
        defer { window.close() }
        #if os(Linux)
        XCTAssertEqual(qs_transfer_between(window.host.window, 15, 20, 85, 20), 1)
        #else
        let drag = PasteboardDrag(window: window.window, point: CGPoint(x: 85, y: 30), writers: urls.map { $0 as NSURL })
        defer { drag.draggingPasteboard.releaseGlobally() }
        let view = try XCTUnwrap(dragReceiver(window.hosting))
        XCTAssertFalse(view.draggingEntered(drag).isEmpty)
        XCTAssertTrue(view.prepareForDragOperation(drag))
        XCTAssertTrue(view.performDragOperation(drag))
        view.concludeDragOperation(drag)
        #endif
        let deadline = ContinuousClock.now + .seconds(2)
        while delegate.values.count < 2 && ContinuousClock.now < deadline { try await window.settle() }
        XCTAssertEqual([delegate.values[0], delegate.values[1]], urls.map { Data($0.absoluteString.utf8) })
    }

    @available(macOS 26, *)
    func testOperationSetsAndProposals() {
        let sets: [DropOperation.Set] = [.cancel, .copy, .move, .forbidden, .delete, .alias]
        XCTAssertEqual(sets.map(\.rawValue), [0, 1, 2, 4, 8, 16])
        XCTAssertEqual(DropOperation.Set(rawValue: -1).description, "DropOperation.Set(copy, move, forbidden, delete, alias)")
        XCTAssertEqual(DropOperation.Set(rawValue: 256).description, "DropOperation.Set(cancel)")
        let plain = DropProposal(operation: .copy)
        XCTAssertEqual(plain.operation, .copy)
        XCTAssertNil(plain.operationOutsideApplication)
        let local = DropProposal(withinApplication: .move, outsideApplication: .forbidden)
        XCTAssertEqual(local.operationOutsideApplication, .forbidden)
        XCTAssertEqual(local.debugDescription, "DropProposal:(operationWithinApplication: move, operationOutsideApplication: forbidden)")
    }

    @available(macOS 26, *)
    @MainActor func testChangingProposalAndLeavingAnExternalDrag() async throws {
        let recorder = DropRecorder()
        recorder.proposal = nil
        let content = Color.red.onDrop(of: [UTType.text.identifier], delegate: recorder)
        let window = try await ScreenWindow(content, width: 160, height: 80)
        defer { window.close() }
        #if os(Linux)
        qs_clipboard_text("Ferry")
        func enter() -> Bool {
            qs_send_external_drop(window.host.window, QSTargetEnter, 32, 25, qs_clipboard_contents()) != QSDropReject
        }
        func move() -> DropOperation {
            switch qs_send_external_drop(window.host.window, QSUpdateTransfer, 35, 27, qs_clipboard_contents()) {
            case QSDropCopy: .copy
            case QSDropMove: .move
            case QSDropLink: .alias
            default: .cancel
            }
        }
        func leave() { _ = qs_send_external_drop(window.host.window, QSTargetLeave, 35, 27, qs_clipboard_contents()) }
        #else
        let drag = PasteboardDrag(window: window.window, point: CGPoint(x: 32, y: 55), local: false)
        defer { drag.draggingPasteboard.releaseGlobally() }
        let view = try XCTUnwrap(dragReceiver(window.hosting))
        func enter() -> Bool { !view.draggingEntered(drag).isEmpty }
        func move() -> DropOperation {
            switch view.draggingUpdated(drag) {
            case .copy: .copy
            case .move: .move
            case .link: .alias
            default: .cancel
            }
        }
        func leave() { view.draggingExited(drag) }
        #endif
        XCTAssertTrue(enter())
        XCTAssertEqual(move(), .copy)
        recorder.proposal = .init(operation: .move)
        XCTAssertEqual(move(), .move)
        recorder.proposal = nil
        XCTAssertEqual(move(), .copy)
        #if os(Linux)
        recorder.proposal = .init(withinApplication: .move, outsideApplication: .forbidden)
        XCTAssertEqual(move(), .cancel)
        #endif
        recorder.proposal = .init(operation: .forbidden)
        XCTAssertEqual(move(), .cancel)
        leave()
        XCTAssertEqual(recorder.events.last, "exit")
        XCTAssertFalse(recorder.events.contains("perform"))
        recorder.canAccept = false
        recorder.events.removeAll()
        XCTAssertFalse(enter())
        XCTAssertEqual(recorder.events, ["validate"])
    }

    @MainActor func testDelegateReceivesTheTypedDropAndLocalCoordinates() async throws {
        let recorder = DropRecorder()
        let content = HStack(spacing: 0) {
            Color.blue.frame(width: 80, height: 60).onDrag { NSItemProvider(object: "Ferry" as NSString) }
            Color.red.frame(width: 120, height: 60).onDrop(of: [.text], delegate: recorder)
        }
        let window = try await ScreenWindow(content, width: 200, height: 60)
        defer { window.close() }
        #if os(Linux)
        XCTAssertEqual(qs_transfer_between(window.host.window, 30, 30, 104, 21), 1)
        #else
        let drag = PasteboardDrag(window: window.window, point: CGPoint(x: 104, y: 39))
        defer { drag.draggingPasteboard.releaseGlobally() }
        let view = try XCTUnwrap(dragReceiver(window.hosting))
        XCTAssertFalse(view.draggingEntered(drag).isEmpty)
        XCTAssertEqual(view.draggingUpdated(drag), .move)
        XCTAssertTrue(view.prepareForDragOperation(drag))
        XCTAssertTrue(view.performDragOperation(drag))
        view.concludeDragOperation(drag)
        #endif
        XCTAssertTrue(recorder.events.contains("validate"))
        XCTAssertTrue(recorder.events.contains("enter"))
        XCTAssertTrue(recorder.events.contains("update"))
        XCTAssertTrue(recorder.events.contains("perform"))
        XCTAssertEqual(recorder.lastPoint.x, 24, accuracy: 1)
        XCTAssertEqual(recorder.lastPoint.y, 21, accuracy: 1)
        let deadline = ContinuousClock.now + .seconds(2)
        while recorder.text == nil && ContinuousClock.now < deadline { try await window.settle() }
        XCTAssertEqual(recorder.text, "Ferry")
    }
}

#if os(macOS)
@MainActor private func dragReceiver(_ view: NSView) -> NSView? {
    for child in view.subviews { if let receiver = dragReceiver(child) { return receiver } }
    return view.registeredDraggedTypes.isEmpty ? nil : view
}

@MainActor private final class PasteboardDrag: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    let draggingLocation: CGPoint
    let draggingPasteboard = NSPasteboard.withUniqueName()
    let draggingSourceOperationMask: NSDragOperation = [.copy, .move]
    var draggedImageLocation: CGPoint { draggingLocation }
    let draggingSource: Any?
    let writers: [any NSPasteboardWriting]
    let draggingSequenceNumber = 10
    nonisolated var draggedImage: NSImage? { nil }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    init(window: NSWindow, point: CGPoint, local: Bool = true, writers: [any NSPasteboardWriting] = ["Ferry" as NSString]) {
        self.writers = writers
        numberOfValidItemsForDrop = writers.count
        draggingSource = local ? window.contentView : nil
        draggingDestinationWindow = window
        draggingLocation = point
        super.init()
        draggingPasteboard.writeObjects(writers)
    }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop: ObjCBool = false
        for (index, writer) in writers.enumerated() {
            block(NSDraggingItem(pasteboardWriter: writer), index, &stop)
            if stop.boolValue { break }
        }
    }
}
#endif
