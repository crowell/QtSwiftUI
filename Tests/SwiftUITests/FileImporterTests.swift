import Foundation
import QtBridge
import XCTest
@testable import SwiftUI

final class FileImporterTests: XCTestCase {
    @MainActor func testCustomDialogLabelsAndRemovingAnOverride() async throws {
        var shown = true
        var custom = true
        let binding = Binding(get: { shown }, set: { shown = $0 })
        let count = 12500
        let host = Host(title: "Import test") { context in
            Color.white.fileImporter(isPresented: binding, allowedContentTypes: [.png]) { _ in }
                .fileDialogMessage(custom ? Text("Selection \(count, format: .number)") : nil)
                .fileDialogConfirmationLabel(custom ? Text(verbatim: "Use artwork") : nil)
                .fileDialogConfirmationLabel("Outer label")
                .fileDialogMessage("Outer message")
                .environment(\.locale, Locale(identifier: "en-US"))
                .resolve(context)
        }
        defer { host.close() }
        host.open(width: 240, height: 160)
        qs_flush()
        XCTAssertEqual(qs_accessible_element(host.window, "Selection 12,500", -1, nil), 1)
        XCTAssertEqual(qs_accessible_element(host.window, "Use artwork", -1, nil), 1)
        _ = qs_key_escape(host.window)
        qs_flush()
        XCTAssertFalse(shown)
        host.update()
        qs_flush()
        custom = false
        shown = true
        host.update()
        qs_flush()
        qs_flush()
        XCTAssertEqual(qs_enter(host.window, "fileNameEdit", "art.png"), 1)
        XCTAssertEqual(qs_accessible_element(host.window, "Open", -1, nil), 1)
        XCTAssertEqual(qs_accessible_element(host.window, "Outer message", -1, nil), 0)
        XCTAssertEqual(qs_accessible_element(host.window, "Use artwork", -1, nil), 0)
    }

    @MainActor func testSingleFileURLAndCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("avatar #50% 風.png")
        try Data("selection".utf8).write(to: file)
        var presented = true
        let binding = Binding(get: { presented }, set: { presented = $0 })
        var selections: [URL] = []
        let host = Host(title: "Avatar") { context in
            Text("Photo").fileImporter(isPresented: binding, allowedContentTypes: [.gif, .jpeg, .png, .webP]) { result in
                XCTAssertFalse(presented)
                do { selections.append(try result.get()) } catch { XCTFail(String(describing: error)) }
            }.fileDialogDefaultDirectory(directory).resolve(context)
        }
        defer { host.close() }
        host.open(width: 250, height: 200)
        qs_flush()
        qs_flush()
        let unsupported = directory.appendingPathComponent("settings.txt")
        try Data().write(to: unsupported)
        XCTAssertEqual(qs_enter(host.window, "fileNameEdit", unsupported.lastPathComponent), 1)
        XCTAssertEqual(qs_key_return(host.window, "fileNameEdit"), 1)
        XCTAssertTrue(presented)
        XCTAssertTrue(selections.isEmpty)
        XCTAssertEqual(qs_enter(host.window, "fileNameEdit", file.lastPathComponent), 1)
        XCTAssertEqual(qs_key_return(host.window, "fileNameEdit"), 1)
        qs_flush()
        XCTAssertEqual(selections.map(\.path), [file.path])
        host.update()
        qs_flush()
        presented = true
        host.update()
        qs_flush()
        qs_flush()
        _ = qs_key_escape(host.window)
        qs_flush()
        XCTAssertFalse(presented)
        XCTAssertEqual(selections.count, 1)
    }

    @MainActor func testCancellationCanImmediatelyPresentTheNextImporter() async {
        var shown = true, canceled = 0
        let host = Host(title: "Import again") { context in
            Text("Photo").fileImporter(isPresented: Binding(get: { shown }, set: { shown = $0 }),
                                       allowedContentTypes: [.image], allowsMultipleSelection: false) { _ in
                XCTFail("Unexpected selection")
            } onCancellation: {
                canceled += 1
                shown = canceled == 1
            }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 200, height: 120)
        for _ in 0..<2 {
            host.update()
            qs_flush()
            qs_flush()
            _ = qs_key_escape(host.window)
            qs_flush()
        }
        XCTAssertFalse(shown)
        XCTAssertEqual(canceled, 2)
    }

    @MainActor func testImportFoldersAndMixedFileSelections() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folderA = dir.appendingPathComponent("Folder A"), folderB = dir.appendingPathComponent("Folder B")
        let file = dir.appendingPathComponent("image.png")
        for folder in [folderA, folderB] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data().write(to: file)
        for types in [[UTType.folder], [.directory, .png]] {
            var shown = true, picked: [URL] = []
            let host = Host(title: "Select") { context in
                Text("Import").fileImporter(isPresented: Binding(get: { shown }, set: { shown = $0 }),
                                            allowedContentTypes: types, allowsMultipleSelection: true) {
                    do { picked = try $0.get() } catch { XCTFail(String(describing: error)) }
                }.fileDialogDefaultDirectory(dir).fileDialogConfirmationLabel(String("Import selected entries")).resolve(context)
            }
            defer { host.close() }
            host.open(width: 180, height: 100)
            let second = types.count == 1 ? folderB : file
            var selected = false
            for _ in 0..<50 {
                qs_flush()
                if qs_select_import_entry(host.window, folderA.path, 0) == 1,
                   qs_select_import_entry(host.window, second.path, 1) == 1 { selected = true; break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(selected)
            XCTAssertEqual(qs_accessible_element(host.window, "Import selected entries", -1, nil), 1)
            XCTAssertEqual(qs_click(host.window, "qsImportSelection"), 1)
            qs_flush()
            XCTAssertEqual(Set(picked.map(\.path)), [folderA.path, second.path])
            XCTAssertFalse(shown)
        }
    }

    @MainActor func testMultipleFilesCancelAndExternalDismissal() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = ["one.txt", "two files.txt"]
        for name in names { try Data(name.utf8).write(to: dir.appendingPathComponent(name)) }
        var shown = true, canceled = 0
        var allowed = [UTType.plainText]
        var multiple = true
        let binding = Binding(get: { shown }, set: { shown = $0 })
        var files: [URL] = []
        let host = Host(title: "Import") { context in
            Color.white.fileImporter(isPresented: binding, allowedContentTypes: allowed, allowsMultipleSelection: multiple) { result in
                XCTAssertFalse(shown)
                do { files = try result.get() } catch { XCTFail(String(describing: error)) }
            } onCancellation: {
                XCTAssertFalse(shown)
                canceled += 1
            }.fileDialogDefaultDirectory(dir).resolve(context)
        }
        defer { host.close() }
        func update() { host.update(); qs_flush(); qs_flush() }
        host.open(width: 240, height: 160)
        update()
        allowed = [.png]
        multiple = false
        update()
        XCTAssertEqual(qs_enter(host.window, "fileNameEdit", "\"one.txt\" \"two files.txt\""), 1)
        XCTAssertEqual(qs_key_return(host.window, "fileNameEdit"), 1)
        qs_flush()
        XCTAssertEqual(files.map(\.lastPathComponent), names)
        XCTAssertEqual(canceled, 0)
        update()
        shown = true
        update()
        _ = qs_key_escape(host.window)
        qs_flush()
        XCTAssertFalse(shown)
        XCTAssertEqual(canceled, 1)
        update()
        shown = true
        update()
        shown = false
        update()
        XCTAssertEqual(canceled, 1)
        XCTAssertEqual(files.count, 2)
    }
}
