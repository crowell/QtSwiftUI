import Foundation

@frozen public struct CGVector: Equatable, Sendable {
    public var dx: CGFloat
    public var dy: CGFloat
    public init(dx: CGFloat, dy: CGFloat) { self.dx = dx; self.dy = dy }
    public init() { self.init(dx: 0, dy: 0) }
    public static let zero = Self()
}
