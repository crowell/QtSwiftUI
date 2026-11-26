import Foundation
import UniformTypeIdentifiers

@preconcurrency public protocol Transferable: Sendable {
    associatedtype Representation: TransferRepresentation
    @TransferRepresentationBuilder<Self> static var transferRepresentation: Representation { get }
}

public protocol TransferRepresentation<Item>: Sendable {
    associatedtype Item: Transferable
    associatedtype Body: TransferRepresentation
    @TransferRepresentationBuilder<Item> var body: Body { get }
}

extension Never: TransferRepresentation, Transferable {
    public typealias Item = Never
    public typealias Body = Never
    public var body: Never { self }
    public static var transferRepresentation: Never { fatalError("Never has no representation") }
}

extension TransferRepresentation where Body == Never {
    public var body: Never { fatalError("A primitive transfer representation has no body") }
}

private struct Format<Item: Transferable>: Sendable {
    let type: UTType
    let read: (@Sendable (Data) async throws -> Item)?
    let write: (@Sendable (Item) async throws -> Data)?
}

private protocol DataFormats<Item>: TransferRepresentation {
    var formats: [Format<Item>] { get }
}

private func formats<R: TransferRepresentation, T: Transferable>(of representation: R, for: T.Type) -> [Format<T>] {
    if let native = representation as? any DataFormats<T> { return native.formats }
    if R.Body.self == Never.self { return [] }
    return formats(of: representation.body, for: T.self)
}

public struct DataRepresentation<Item: Transferable>: DataFormats {
    public typealias Body = Never
    fileprivate let formats: [Format<Item>]

    public init(contentType: UTType, exporting: @escaping @Sendable (Item) async throws -> Data,
                importing: @escaping @Sendable (Data) async throws -> Item) {
        formats = [Format(type: contentType, read: importing, write: exporting)]
    }
    public init(exportedContentType: UTType, exporting: @escaping @Sendable (Item) async throws -> Data) {
        formats = [Format(type: exportedContentType, read: nil, write: exporting)]
    }
    public init(importedContentType: UTType, importing: @escaping @Sendable (Data) async throws -> Item) {
        formats = [Format(type: importedContentType, read: importing, write: nil)]
    }
}

public struct TupleTransferRepresentation<Item: Transferable, Value: Sendable>: DataFormats {
    fileprivate let formats: [Format<Item>]
    private struct Contents: DataFormats {
        typealias Body = Never
        let formats: [Format<Item>]
    }
    public var body: some TransferRepresentation { Contents(formats: formats) }
}

@resultBuilder public struct TransferRepresentationBuilder<Item: Transferable> {
    public static func buildExpression<R: TransferRepresentation>(_ content: R) -> R where R.Item == Item { content }
    public static func buildBlock<R: TransferRepresentation>(_ content: R) -> R where R.Item == Item { content }
    @_disfavoredOverload public static func buildBlock<each R: TransferRepresentation>(_ content: repeat each R) -> TupleTransferRepresentation<Item, (repeat each R)> {
        var result: [Format<Item>] = []
        for child in repeat each content { result.append(contentsOf: formats(of: child, for: Item.self)) }
        return TupleTransferRepresentation(formats: result)
    }
}

extension Transferable {
    public static func importedContentTypes() -> [UTType] {
        var seen: Set<UTType> = []
        return formats(of: transferRepresentation, for: Self.self).compactMap {
            $0.read != nil && seen.insert($0.type).inserted ? $0.type : nil
        }
    }
    public func importedContentTypes() -> [UTType] { Self.importedContentTypes() }

    public init(importing data: Data, contentType: UTType?) async throws {
        for format in formats(of: Self.transferRepresentation, for: Self.self) {
            if let read = format.read, contentType?.conforms(to: format.type) != false {
                self = try await read(data)
                return
            }
        }
        throw CocoaError(.fileReadUnsupportedScheme)
    }
    public func exported(as contentType: UTType?) async throws -> Data {
        for format in formats(of: Self.transferRepresentation, for: Self.self) {
            if let write = format.write, contentType.map({ format.type.conforms(to: $0) }) != false {
                return try await write(self)
            }
        }
        throw CocoaError(.fileWriteUnsupportedScheme)
    }
}

extension Data: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation<Data>(contentType: .data, exporting: { $0 }, importing: { $0 })
    }
}
extension String: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation<String>(contentType: .utf8PlainText, exporting: { Data($0.utf8) }, importing: {
            guard let result = String(data: $0, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            return result
        })
    }
}
extension URL: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        urlRepresentation(.url)
        urlRepresentation(.fileURL)
    }
    private static func urlRepresentation(_ type: UTType) -> DataRepresentation<URL> {
        DataRepresentation(contentType: type, exporting: { Data($0.absoluteString.utf8) }, importing: {
            guard let string = String(data: $0, encoding: .utf8), let url = URL(string: string) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return url
        })
    }
}
