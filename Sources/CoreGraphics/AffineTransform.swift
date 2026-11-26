@_exported import Foundation

/// Foundation provides CGPoint, CGSize and CGRect on Linux.
public struct CGAffineTransform: Equatable, Sendable {
    public var a, b, c, d, tx, ty: CGFloat
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public init(translationX tx: CGFloat, y ty: CGFloat) { self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty) }
    public init(scaleX sx: CGFloat, y sy: CGFloat) { self.init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0) }
    public init(rotationAngle angle: CGFloat) {
        self.init(a: cos(angle), b: sin(angle), c: -sin(angle), d: cos(angle), tx: 0, ty: 0)
    }
    public static let identity = Self(scaleX: 1, y: 1)
    public var isIdentity: Bool { self == .identity }
    public func concatenating(_ t: Self) -> Self {
        Self(a: a * t.a + b * t.c, b: a * t.b + b * t.d,
             c: c * t.a + d * t.c, d: c * t.b + d * t.d,
             tx: tx * t.a + ty * t.c + t.tx, ty: tx * t.b + ty * t.d + t.ty)
    }
    public func translatedBy(x: CGFloat, y: CGFloat) -> Self { Self(translationX: x, y: y).concatenating(self) }
    public func scaledBy(x: CGFloat, y: CGFloat) -> Self { Self(scaleX: x, y: y).concatenating(self) }
    public func rotated(by angle: CGFloat) -> Self { Self(rotationAngle: angle).concatenating(self) }
    public func inverted() -> Self {
        let det = a * d - b * c
        guard det != 0 else { return self }
        return Self(a: d / det, b: -b / det, c: -c / det, d: a / det,
                    tx: (c * ty - d * tx) / det, ty: (b * tx - a * ty) / det)
    }
}
extension CGPoint {
    public func applying(_ t: CGAffineTransform) -> CGPoint { CGPoint(x: x * t.a + y * t.c + t.tx, y: x * t.b + y * t.d + t.ty) }
}
extension CGSize {
    public func applying(_ t: CGAffineTransform) -> CGSize { CGSize(width: width * t.a + height * t.c, height: width * t.b + height * t.d) }
}
extension CGRect {
    public func applying(_ t: CGAffineTransform) -> CGRect {
        if isNull || isInfinite { return self }
        let points = [CGPoint(x: minX, y: minY), CGPoint(x: minX, y: maxY),
                      CGPoint(x: maxX, y: minY), CGPoint(x: maxX, y: maxY)].map { $0.applying(t) }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
