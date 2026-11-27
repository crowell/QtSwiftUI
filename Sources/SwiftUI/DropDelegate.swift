import QtBridge

public enum DropOperation: Hashable, Sendable {
    case cancel, forbidden, copy, move, delete, alias

    public struct Set: OptionSet, Hashable, CustomStringConvertible {
        public typealias Element = DropOperation.Set
        public typealias ArrayLiteralElement = DropOperation.Set
        public typealias RawValue = Int
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        nonisolated(unsafe) public static let cancel = Self([])
        nonisolated(unsafe) public static let copy = Self(rawValue: 1)
        nonisolated(unsafe) public static let move = Self(rawValue: 2)
        nonisolated(unsafe) public static let forbidden = Self(rawValue: 4)
        nonisolated(unsafe) public static let delete = Self(rawValue: 8)
        nonisolated(unsafe) public static let alias = Self(rawValue: 16)

        public var description: String {
            let flags: [(Self, String)] = [(.copy, "copy"), (.move, "move"), (.forbidden, "forbidden"),
                                           (.delete, "delete"), (.alias, "alias")]
            let names = flags.compactMap { contains($0.0) ? $0.1 : nil }
            return "DropOperation.Set(" + (names.isEmpty ? "cancel" : names.joined(separator: ", ")) + ")"
        }
    }

    var nativeProposal: QSDropAction {
        switch self {
        case .copy: QSDropCopy
        case .move, .delete: QSDropMove
        case .alias: QSDropLink
        case .forbidden, .cancel: QSDropReject
        }
    }
}

public struct DropProposal: Sendable, CustomDebugStringConvertible {
    public let operation: DropOperation
    public let operationOutsideApplication: DropOperation?
    public init(operation: DropOperation) {
        self.operation = operation
        operationOutsideApplication = nil
    }
    public init(withinApplication: DropOperation, outsideApplication: DropOperation) {
        operation = withinApplication
        operationOutsideApplication = outsideApplication
    }
    public var debugDescription: String {
        "DropProposal:(operationWithinApplication: \(operation), operationOutsideApplication: \(operationOutsideApplication.map { String(describing: $0) } ?? "nil"))"
    }
}

public struct DropInfo {
    public var location: CGPoint { position }
    let position: CGPoint
    let offered: [NSItemProvider]
    final class Payload {
        var items: [NSItemProvider] = []
    }
    let payload: Payload?

    public func hasItemsConforming(to contentTypes: [UTType]) -> Bool {
        hasItemsConforming(to: contentTypes.map(\.identifier))
    }
    public func hasItemsConforming(to types: [String]) -> Bool {
        offered.contains { item in types.contains(where: item.hasItemConformingToTypeIdentifier) }
    }
    public func itemProviders(for contentTypes: [UTType]) -> [NSItemProvider] {
        itemProviders(for: contentTypes.map(\.identifier))
    }
    public func itemProviders(for types: [String]) -> [NSItemProvider] {
        payload?.items.filter { item in types.contains(where: item.hasItemConformingToTypeIdentifier) } ?? []
    }
}

@preconcurrency @MainActor public protocol DropDelegate {
    @MainActor @preconcurrency func validateDrop(info: DropInfo) -> Bool
    @MainActor @preconcurrency func dropEntered(info: DropInfo)
    @MainActor @preconcurrency func dropUpdated(info: DropInfo) -> DropProposal?
    @MainActor @preconcurrency func dropExited(info: DropInfo)
    @MainActor @preconcurrency func performDrop(info: DropInfo) -> Bool
}
extension DropDelegate {
    @MainActor @preconcurrency public func validateDrop(info: DropInfo) -> Bool { true }
    @MainActor @preconcurrency public func dropEntered(info: DropInfo) {}
    @MainActor @preconcurrency public func dropUpdated(info: DropInfo) -> DropProposal? { nil }
    @MainActor @preconcurrency public func dropExited(info: DropInfo) {}
}

extension View {
    nonisolated public func onDrop(of supportedContentTypes: [UTType], delegate: any DropDelegate) -> some View {
        onDrop(of: supportedContentTypes.map(\.identifier), delegate: delegate)
    }
    nonisolated public func onDrop(of supportedTypes: [String], delegate: any DropDelegate) -> some View {
        TransferView(content: self, transfer: TransferAction(types: supportedTypes, delegate: delegate))
    }
}
